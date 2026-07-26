#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { validateNativeAssetProvenanceLineage } from "../tooling/src/validate.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const registryPath = path.join(repositoryRoot, "native", "content", "backstage", "native-asset-provenance.json");
const webSourceInventoryPath = path.join(repositoryRoot, "native", "blueprint", "source-asset-provenance.json");

async function exactProjectFiles(registry) {
  const paths = new Set();
  for (const asset of registry.assets ?? []) {
    for (const lineage of asset.sourceLineage ?? []) {
      if (lineage.lineageType === "PROJECT_AUTHORED_AUDIO") paths.add(lineage.sourcePath);
      if (lineage.lineageType === "OPEN_LICENSE_AUDIO_SOURCE" && lineage.licenseSPDX === "MIT") {
        paths.add(lineage.noticePath);
      }
    }
  }
  const records = new Map();
  for (const relativePath of [...paths].sort()) {
    const file = path.resolve(repositoryRoot, relativePath);
    if (!file.startsWith(`${repositoryRoot}${path.sep}`)) {
      throw new Error(`project source escaped repository: ${relativePath}`);
    }
    const bytes = await readFile(file);
    records.set(relativePath, {
      bytes: bytes.byteLength,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    });
  }
  return records;
}

async function main() {
  const [registry, webSourceInventory] = await Promise.all([
    readFile(registryPath, "utf8").then(JSON.parse),
    readFile(webSourceInventoryPath, "utf8").then(JSON.parse),
  ]);
  validateNativeAssetProvenanceLineage(
    registry,
    webSourceInventory,
    await exactProjectFiles(registry),
  );
  process.stdout.write(`Validated ${registry.assets.length} approved native assets; compiler remains fail-closed for unregistered files.\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
