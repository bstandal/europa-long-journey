#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  sourceAuthorityForReceipt,
  validateThreadSanitizerReceipt,
} from "./validate-thread-sanitizer-receipt.mjs";

const nativeRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const receipt = JSON.parse(
  await readFile(
    path.join(nativeRoot, "ios", "qa", "thread-sanitizer-focused-2026-07-25.receipt.json"),
    "utf8",
  ),
);

test("focused Thread Sanitizer receipt matches the current source authority", async () => {
  await assert.doesNotReject(validateThreadSanitizerReceipt(structuredClone(receipt)));
});

test("a simulator Thread Sanitizer run cannot claim shipping approval", async () => {
  const drifted = structuredClone(receipt);
  drifted.shippingApproval = true;
  await assert.rejects(validateThreadSanitizerReceipt(drifted));
});

test("the pass cannot survive a changed source authority", async () => {
  const drifted = structuredClone(receipt);
  drifted.sourceAuthority.sha256OfSortedFileHashLines = "0".repeat(64);
  await assert.rejects(validateThreadSanitizerReceipt(drifted));
});

test("the source-authority helper reproduces the bound digest", async () => {
  assert.deepEqual(await sourceAuthorityForReceipt(receipt), {
    fileCount: 62,
    sha256OfSortedFileHashLines:
      "59ef7d56798519bf5ff8f57ccb0fc0287c8dffdbfbf2a41b6b162658038aa5d9",
  });
});
