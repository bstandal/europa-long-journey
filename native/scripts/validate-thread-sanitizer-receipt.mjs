#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const nativeRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const iosRoot = path.join(nativeRoot, "ios");

async function regularFilesRecursively(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const absolute = path.join(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await regularFilesRecursively(absolute)));
    } else if (entry.isFile() || (entry.isSymbolicLink() && (await stat(absolute)).isFile())) {
      files.push(absolute);
    }
  }
  return files;
}

export async function sourceAuthorityForReceipt(receipt) {
  const roots = receipt.sourceAuthority.roots.map((root) => {
    const prefix = "native/ios/";
    assert.ok(root.startsWith(prefix), `source-authority root escaped native/ios: ${root}`);
    const relative = root.slice(prefix.length);
    assert.ok(relative && !relative.startsWith("../"), `invalid source-authority root: ${root}`);
    return path.join(iosRoot, relative);
  });

  const files = (await Promise.all(roots.map(regularFilesRecursively)))
    .flat()
    .map((absolute) => ({
      absolute,
      relative: path.relative(iosRoot, absolute).split(path.sep).join("/"),
    }))
    .sort((left, right) => left.relative.localeCompare(right.relative, "en"));

  const aggregate = createHash("sha256");
  for (const file of files) {
    const digest = createHash("sha256").update(await readFile(file.absolute)).digest("hex");
    aggregate.update(`${digest}  ${file.relative}\n`);
  }
  return {
    fileCount: files.length,
    sha256OfSortedFileHashLines: aggregate.digest("hex"),
  };
}

export async function validateThreadSanitizerReceipt(receipt) {
  assert.equal(receipt.schemaVersion, 1, "unsupported Thread Sanitizer receipt schema");
  assert.equal(
    receipt.status,
    "PASS_LOCAL_SIMULATOR_THREAD_SANITIZER_NON_DEVICE",
    "receipt cannot claim physical-device or shipping authority",
  );
  assert.equal(receipt.threadSanitizerEnabled, true, "Thread Sanitizer must be enabled");
  assert.equal(receipt.destination.platform, "iOS Simulator");
  assert.equal(receipt.destination.device, "iPhone 17 Pro");
  assert.equal(receipt.destination.osVersion, "26.5");
  assert.equal(receipt.destination.architecture, "arm64");
  assert.deepEqual(receipt.testSelections, [
    "LongWestNativeTests/ProgressStoreTests",
    "LongWestNativeTests/ProgressStoreAppendBoundaryTests",
    "LongWestNativeTests/ResponsiveAudioCursorCheckpointStoreTests",
    "LongWestNativeTests/ResponsiveAudioCursorCheckpointPumpTests",
    "LongWestNativeTests/SaveMigrationRegistryTests",
    "LongWestNativeTests/ChapterSceneRuntimeControllerTests",
    "LongWestNativeTests/DownloadControllerTests",
    "LongWestNativeTests/ContentDeliveryTests",
    "LongWestNativeTests/SaveMigrationRestorationPreparerTests",
    "LongWestNativeTests/VerifiedSaveMigrationAuthoritySetTests",
    "LongWestNativeTests/VerifiedJourneyRepositoryAuthorityTests",
    "LongWestNativeTests/VerifiedFutureReleaseRepositoryAuthorityTests",
  ]);
  assert.deepEqual(receipt.result, {
    total: 194,
    passed: 194,
    failed: 0,
    skipped: 0,
    expectedFailures: 0,
    threadSanitizerFindings: 0,
  });
  assert.match(receipt.command, /-enableThreadSanitizer YES/);
  assert.match(receipt.command, /-parallel-testing-enabled NO/);
  for (const selection of receipt.testSelections) {
    assert.ok(receipt.command.includes(`-only-testing:${selection}`));
  }
  assert.equal(receipt.shippingApproval, false);
  assert.ok(receipt.scope.doesNotCover.includes("physical iPhone execution"));
  assert.ok(receipt.scope.doesNotCover.includes("artistic or shipping approval"));

  const currentAuthority = await sourceAuthorityForReceipt(receipt);
  assert.deepEqual(
    currentAuthority,
    {
      fileCount: receipt.sourceAuthority.fileCount,
      sha256OfSortedFileHashLines: receipt.sourceAuthority.sha256OfSortedFileHashLines,
    },
    "Thread Sanitizer evidence is stale for the current source set; rerun and refresh the receipt",
  );
  return receipt;
}

async function main() {
  const receiptPath = path.join(
    iosRoot,
    "qa",
    "thread-sanitizer-focused-2026-07-26.receipt.json",
  );
  const receipt = JSON.parse(await readFile(receiptPath, "utf8"));
  await validateThreadSanitizerReceipt(receipt);
  process.stdout.write(
    `Thread Sanitizer receipt current: ${receipt.result.passed}/${receipt.result.total}; simulator-only.\n`,
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
