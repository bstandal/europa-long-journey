#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import process from "node:process";
import {
  LaunchAssemblyError,
  validateLaunchAssembly,
} from "./launch-assembly.mjs";
import {
  ValidationError,
  validatePublicDocument,
} from "./validate.mjs";

const expectedPayloadCount = 8;

async function readJSON(filePath, label) {
  let source;
  try {
    source = await readFile(filePath, "utf8");
  } catch (error) {
    throw new LaunchAssemblyError([`${label}: cannot read '${filePath}' (${error.code ?? error.message})`]);
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new LaunchAssemblyError([`${label}: invalid JSON in '${filePath}' (${error.message})`]);
  }
}

async function main() {
  const [collectionPath, ...payloadPaths] = process.argv.slice(2);
  if (!collectionPath || payloadPaths.length !== expectedPayloadCount) {
    throw new LaunchAssemblyError([
      "Usage: launch-assembly-cli.mjs <collection.json> <payload-1.json> ... <payload-8.json>",
    ]);
  }

  const collection = await readJSON(collectionPath, "collection");
  const payloads = await Promise.all(payloadPaths.map((payloadPath, index) =>
    readJSON(payloadPath, `payload[${index}]`)));
  validatePublicDocument(collection, collectionPath);
  payloads.forEach((payload, index) => validatePublicDocument(payload, payloadPaths[index]));

  const result = validateLaunchAssembly(collection, payloads);
  console.log(
    `Validated launch assembly: ${result.packageCount} packages, ${result.chapterCount} chapters, final world SHA-256 ${result.finalWorldSHA256}.`,
  );
}

main().catch((error) => {
  if (error instanceof LaunchAssemblyError || error instanceof ValidationError) {
    console.error(error.issues.join("\n"));
  } else {
    console.error(error.stack ?? error.message);
  }
  process.exitCode = 1;
});
