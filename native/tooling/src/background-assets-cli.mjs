#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { packagePaidLaunchBackgroundAssets } from "./background-assets-archive.mjs";
import { ValidationError } from "./validate.mjs";

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.resolve(moduleDirectory, "../..");

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function readJSON(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

async function readLaunchConfiguration() {
  const [product, catalog, delivery] = await Promise.all([
    readJSON(path.join(nativeRoot, "product.json")),
    readJSON(path.join(nativeRoot, "blueprint", "chapter-catalog.json")),
    readJSON(path.join(nativeRoot, "blueprint", "delivery-plan.json")),
  ]);
  return { product, catalog, delivery };
}

async function main() {
  const launchSetRoot = valueAfter("--launch-set");
  const outputRoot = valueAfter("--output");
  const trustResourcePath = valueAfter("--trust");
  const approvedTrustReceiptPath = valueAfter("--approved-trust-receipt");
  if (!launchSetRoot || !outputRoot || !trustResourcePath || !approvedTrustReceiptPath) {
    throw new ValidationError([
      "Usage: background-assets-cli.mjs --launch-set <compiled-root> --output <archive-set> "
        + "--trust <launch-package-trust.json> --approved-trust-receipt <receipt.json>",
    ]);
  }
  const receipt = await packagePaidLaunchBackgroundAssets(
    path.resolve(launchSetRoot),
    path.resolve(outputRoot),
    {
      launchConfiguration: await readLaunchConfiguration(),
      trustResourcePath: path.resolve(trustResourcePath),
      approvedTrustReceiptPath: path.resolve(approvedTrustReceiptPath),
    },
  );
  console.log(
    `Packaged ${receipt.packages.length} paid Apple-hosted asset packs `
      + `(${receipt.receiptSHA256}).`,
  );
}

main().catch((error) => {
  if (error instanceof ValidationError) console.error(error.issues.join("\n"));
  else console.error(error.stack ?? error.message);
  process.exitCode = 1;
});
