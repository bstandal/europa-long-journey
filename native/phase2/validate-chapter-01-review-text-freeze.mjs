import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

const freezeRelativePath =
  "native/content/backstage/first-farmers/chapter-01-review-text-freeze-v1.json";
const sha256Pattern = /^[a-f0-9]{64}$/u;
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function projectSegments(draft) {
  let ordinal = 0;
  return draft.arcs.flatMap((arc) => arc.beats.flatMap((beat) =>
    beat.narrative.segments.map((segment) => ({
      ordinal: ++ordinal,
      arcID: arc.arcID,
      beatID: beat.beatID,
      sceneID: beat.sceneID,
      segmentID: segment.id,
      textSha256: sha256(Buffer.from(segment.text, "utf8")),
    }))));
}

function combinedBindingBytes(segments) {
  return Buffer.from(`${segments.map((segment) => [
    segment.ordinal,
    segment.arcID,
    segment.beatID,
    segment.sceneID,
    segment.segmentID,
    segment.textSha256,
  ].join("\0")).join("\n")}\n`, "utf8");
}

export async function validateChapter01ReviewTextFreeze({ repositoryRoot, freeze } = {}) {
  assert.ok(repositoryRoot, "Chapter 01 review-text validation requires the repository root");
  const root = path.resolve(repositoryRoot);
  const freezePath = path.resolve(root, freezeRelativePath);
  assert.ok(path.relative(root, freezePath).split(path.sep).includes("backstage"),
    "Chapter 01 review-text freeze must remain backstage");
  const record = freeze ?? JSON.parse(await readFile(freezePath, "utf8"));

  assert.equal(record.schemaVersion, 1, "Chapter 01 text-freeze schema drifted");
  assert.equal(record.freezeID, "first-farmers-chapter-01-review-text-v1");
  assert.equal(record.milestone, "CHAPTER_01_REVIEW_READY");
  assert.equal(record.status, "CHAPTER_01_REVIEW_TEXT_FROZEN");
  assert.equal(record.shippingBoundary, "BACKSTAGE_ONLY_DO_NOT_PACKAGE");
  assert.equal(record.chapterID, "first-farmers");
  assert.equal(record.locale, "en");
  assert.equal(record.frozenAt, "2026-07-27");
  assert.equal(record.authority, "EDITOR_IN_CHIEF_APPROVED_REVIEW_TEXT");
  assert.equal(record.sourceDraft.path,
    "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json");
  assert.match(record.sourceDraft.sha256, sha256Pattern);
  assert.match(record.combinedBindingSha256, sha256Pattern);

  const draftPath = path.resolve(root, record.sourceDraft.path);
  const draftBytes = await readFile(draftPath);
  assert.equal(sha256(draftBytes), record.sourceDraft.sha256,
    "Chapter 01 frozen source-draft bytes drifted");
  const draft = JSON.parse(draftBytes.toString("utf8"));
  assert.equal(draft.status, record.status, "Chapter 01 draft is not review-text frozen");

  const projection = projectSegments(draft);
  assert.equal(record.segmentCount, 37, "Chapter 01 review requires exactly 37 text segments");
  assert.equal(record.segments.length, 37, "Chapter 01 freeze must bind all 37 text segments");
  assert.deepEqual(record.segments, projection, "Chapter 01 frozen segment IDs or hashes drifted");
  assert.equal(new Set(record.segments.map(({ segmentID }) => segmentID)).size, 37,
    "Chapter 01 frozen segment IDs are not unique");
  assert.ok(record.segments.every((segment) => !Object.hasOwn(segment, "text")),
    "Chapter 01 freeze must bind hashes without duplicating public prose backstage");
  assert.equal(sha256(combinedBindingBytes(projection)), record.combinedBindingSha256,
    "Chapter 01 combined narration binding hash drifted");

  return record;
}

if (process.argv[1]
    && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
  await validateChapter01ReviewTextFreeze({ repositoryRoot });
  process.stdout.write("Chapter 01 review manuscript frozen at 37 segment hashes.\n");
}
