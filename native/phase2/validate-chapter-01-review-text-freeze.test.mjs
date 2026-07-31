import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { validateChapter01ReviewTextFreeze } from "./validate-chapter-01-review-text-freeze.mjs";

const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const freezePath = path.join(
  repositoryRoot,
  "native/content/backstage/first-farmers/chapter-01-review-text-freeze-v1.json",
);
const loadFreeze = async () => JSON.parse(await readFile(freezePath, "utf8"));

test("freezes all 37 Chapter 01 narration segments by exact text hash", async () => {
  const freeze = await validateChapter01ReviewTextFreeze({ repositoryRoot });
  assert.equal(freeze.segmentCount, 37);
  assert.equal(freeze.segments.length, 37);
  assert.equal(new Set(freeze.segments.map(({ textSha256 }) => textSha256)).size, 37);
});

test("rejects one changed segment hash or a shipping-bound freeze", async () => {
  const hash = await loadFreeze();
  hash.segments[13].textSha256 = "0".repeat(64);
  await assert.rejects(
    validateChapter01ReviewTextFreeze({ repositoryRoot, freeze: hash }),
    /segment IDs or hashes drifted/u,
  );

  const shipping = await loadFreeze();
  shipping.shippingBoundary = "PUBLIC_CONTENT";
  await assert.rejects(
    validateChapter01ReviewTextFreeze({ repositoryRoot, freeze: shipping }),
    /BACKSTAGE_ONLY_DO_NOT_PACKAGE/u,
  );
});

test("rejects narration-binding order drift", async () => {
  const reordered = await loadFreeze();
  [reordered.segments[0], reordered.segments[1]] = [reordered.segments[1], reordered.segments[0]];
  await assert.rejects(
    validateChapter01ReviewTextFreeze({ repositoryRoot, freeze: reordered }),
    /segment IDs or hashes drifted/u,
  );
});
