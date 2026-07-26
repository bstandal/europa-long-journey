#!/usr/bin/env node

import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const publicRoot = path.join(repositoryRoot, "site", "public");
const sourceRegistryPath = path.join(repositoryRoot, "site", "src", "data", "sources.ts");
const outputPath = path.join(repositoryRoot, "native", "blueprint", "source-asset-provenance.json");
const visualExtensions = new Set([".avif", ".heic", ".heif", ".jpeg", ".jpg", ".png", ".svg", ".webp"]);

async function listVisualFiles(root) {
  const output = [];
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) await visit(absolute);
      else if (entry.isFile() && visualExtensions.has(path.extname(entry.name).toLowerCase())) output.push(absolute);
    }
  }
  await visit(root);
  return output.sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
}

function quotedField(block, field) {
  const match = new RegExp(`${field}:\\s*("(?:\\\\.|[^"\\\\])*")`, "u").exec(block);
  return match ? JSON.parse(match[1]) : undefined;
}

function parseAssetRecords(source) {
  const marker = "export const assetRecords: AssetRecord[] = [";
  const start = source.indexOf(marker);
  const end = source.indexOf("\n];", start);
  if (start < 0 || end < 0) throw new Error("Could not isolate site assetRecords");
  const section = source.slice(start + marker.length, end);
  const records = [];
  for (const match of section.matchAll(/\n  \{([\s\S]*?)\n  \},/gu)) {
    const block = match[1];
    const record = Object.fromEntries(
      ["id", "title", "creator", "institution", "sourceUrl", "license", "requiredCredit", "localPath"]
        .map((field) => [field, quotedField(block, field)])
    );
    if (Object.values(record).some((value) => value === undefined)) {
      throw new Error(`Incomplete asset record near ${record.id ?? "unknown record"}`);
    }
    records.push(record);
  }
  if (!records.length) throw new Error("No site assetRecords were parsed");
  return records;
}

async function hashFile(file) {
  const digest = createHash("sha256");
  let bytes = 0;
  for await (const chunk of createReadStream(file)) {
    bytes += chunk.byteLength;
    digest.update(chunk);
  }
  return { bytes, sha256: digest.digest("hex") };
}

function obligations(records) {
  const output = [];
  for (const record of records) {
    if (/CC BY/i.test(record.license)) output.push(`Preserve attribution and licence terms: ${record.requiredCredit}`);
    else if (!/^(Public domain|Public-domain|CC0|Project-owned generated artwork)/i.test(record.license)) {
      output.push(`Preserve the documented source terms and credit: ${record.requiredCredit}`);
    }
  }
  return [...new Set(output)];
}

async function buildInventory() {
  const registrySource = await readFile(sourceRegistryPath, "utf8");
  const records = parseAssetRecords(registrySource);
  const recordsByPath = new Map();
  for (const record of records) {
    const list = recordsByPath.get(record.localPath) ?? [];
    list.push(record);
    recordsByPath.set(record.localPath, list);
  }
  const files = await listVisualFiles(publicRoot);
  const assets = [];
  for (const file of files) {
    const localPath = `/${path.relative(publicRoot, file).split(path.sep).join("/")}`;
    const provenanceRecords = recordsByPath.get(localPath) ?? [];
    const allowed = provenanceRecords.length > 0;
    assets.push({
      localPath,
      ...await hashFile(file),
      mediaType: path.extname(file).slice(1).toLowerCase(),
      provenanceStatus: allowed ? "RECORDED_SOURCE_RIGHTS" : "BLOCKED_PROVENANCE_MISSING",
      allowedAsNativeRawMaterial: allowed,
      obligations: obligations(provenanceRecords),
      provenanceRecords,
    });
  }
  const presentPaths = new Set(assets.map(({ localPath }) => localPath));
  const declaredButMissing = [...recordsByPath.keys()].filter((localPath) => !presentPaths.has(localPath)).sort();
  const recorded = assets.filter(({ allowedAsNativeRawMaterial }) => allowedAsNativeRawMaterial);
  const blocked = assets.filter(({ allowedAsNativeRawMaterial }) => !allowedAsNativeRawMaterial);
  return {
    schemaVersion: 1,
    status: blocked.length ? "RAW_MATERIAL_REQUIRES_PROVENANCE_WORK" : "ALL_RAW_MATERIAL_RECORDED",
    scope: "Every visual file currently present under site/public; these are web source plates, never finished native assets.",
    policy: "An unrecorded file may be inspected as project history but cannot enter native production. A transformed native asset requires its own output hash, source lineage, tool lineage and rights record.",
    generatedFrom: {
      assetRegistry: "site/src/data/sources.ts#assetRecords",
      assetRegistrySHA256: createHash("sha256").update(registrySource).digest("hex"),
      publicRoot: "site/public",
    },
    counts: {
      visualFiles: assets.length,
      sourceRecords: records.length,
      uniqueRecordedPaths: recordsByPath.size,
      recordedFiles: recorded.length,
      blockedFiles: blocked.length,
      declaredButMissing: declaredButMissing.length,
    },
    declaredButMissing,
    assets,
  };
}

async function main() {
  const expected = `${JSON.stringify(await buildInventory(), null, 2)}\n`;
  if (process.argv.includes("--check")) {
    const actual = await readFile(outputPath, "utf8").catch(() => null);
    if (actual !== expected) throw new Error("source-asset-provenance.json is stale; rebuild the source asset inventory");
    process.stdout.write("Validated source-asset provenance and hashes.\n");
    return;
  }
  await writeFile(outputPath, expected);
  const inventory = JSON.parse(expected);
  process.stdout.write(
    `Inventoried ${inventory.counts.visualFiles} visual files: ${inventory.counts.recordedFiles} recorded, ${inventory.counts.blockedFiles} blocked pending provenance.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
