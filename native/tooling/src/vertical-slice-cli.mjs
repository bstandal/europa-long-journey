#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { compileDevelopmentVerticalSlice } from "./vertical-slice-compile.mjs";
import { ValidationError } from "./validate.mjs";

const [, , sourceRoot, outputRoot, projectionAuthorityPath, trustReceiptPath] = process.argv;
const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.resolve(moduleDirectory, "../..");
const version = { major: 1, minor: 0, patch: 0 };

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`)
    && relative !== ".." && !path.isAbsolute(relative));
}

async function readJSON(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

async function main() {
  if (!sourceRoot || !outputRoot || !projectionAuthorityPath || !trustReceiptPath
      || process.argv.length !== 6) {
    throw new ValidationError([
      "compile-vertical-slice: source, output, backstage provisional projection authority and separate trust-receipt paths required",
    ]);
  }
  const resolvedSource = path.resolve(sourceRoot);
  const resolvedOutput = path.resolve(outputRoot);
  const resolvedAuthority = path.resolve(projectionAuthorityPath);
  const resolvedReceipt = path.resolve(trustReceiptPath);
  if (isWithin(resolvedOutput, resolvedReceipt) || isWithin(resolvedSource, resolvedReceipt)) {
    throw new ValidationError([
      "compile-vertical-slice: trust receipt must remain outside source and package trees",
    ]);
  }
  const [product, catalog, delivery] = await Promise.all([
    readJSON(path.join(nativeRoot, "product.json")),
    readJSON(path.join(nativeRoot, "blueprint", "chapter-catalog.json")),
    readJSON(path.join(nativeRoot, "blueprint", "delivery-plan.json")),
  ]);
  const result = await compileDevelopmentVerticalSlice(
    resolvedSource,
    resolvedOutput,
    {
      blueprintRoot: path.resolve(
        process.env.LONG_WEST_BLUEPRINT_ROOT ?? path.join(nativeRoot, "blueprint"),
      ),
      launchConfiguration: { product, catalog, delivery },
      projectionAuthorityPath: resolvedAuthority,
      packageVersion: version,
      minimumRuntime: version,
      maximumInstalledBytes: delivery.budgets.essentialInstallBytes,
    },
  );
  await mkdir(path.dirname(resolvedReceipt), { recursive: true });
  await writeFile(
    resolvedReceipt,
    `${JSON.stringify(result.trustReceipt, null, 2)}\n`,
    { flag: "wx", mode: 0o600 },
  );
  console.log(
    `Compiled development-only vertical slice ${result.manifest.manifestDigest}; trust receipt ${resolvedReceipt}.`,
  );
}

main().catch((error) => {
  if (error instanceof ValidationError) console.error(error.issues.join("\n"));
  else console.error(error.stack ?? error.message);
  process.exitCode = 1;
});
