#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const modulePath = fileURLToPath(import.meta.url);
const repositoryRoot = path.resolve(path.dirname(modulePath), "../../..");
const audioRoot = path.join(repositoryRoot, "native/audio/score-soundscape");

const targets = Object.freeze([
  ["harvest-responsive-v1", "work-object.json"],
  ["longhouse-responsive-v1", "longhouse-responsive-work-object.json"],
  ["continent-remade-responsive-v1", "continent-remade-responsive-work-object.json"],
  ["more-mouths-responsive-v1", "more-mouths-responsive-work-object.json"],
  ["household-crosses-responsive-v1", "household-crosses-responsive-work-object.json"],
]);

function fail(message) {
  throw new Error(message);
}

function serialize(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function fileRecord(file) {
  const bytes = await readFile(file);
  return { bytes: bytes.length, sha256: sha256(bytes) };
}

function resolveRepositoryPath(relativePath) {
  if (typeof relativePath !== "string" || path.isAbsolute(relativePath)) {
    fail(`production input path must be repository-relative: ${relativePath}`);
  }
  const resolved = path.resolve(repositoryRoot, relativePath);
  if (!resolved.startsWith(`${repositoryRoot}${path.sep}`)) {
    fail(`production input escapes repository root: ${relativePath}`);
  }
  return resolved;
}

function resolveOutputPath(targetRoot, relativePath) {
  if (typeof relativePath !== "string" || path.isAbsolute(relativePath)) {
    fail(`receipt output path must be target-relative: ${relativePath}`);
  }
  const resolved = path.resolve(targetRoot, relativePath);
  if (!resolved.startsWith(`${targetRoot}${path.sep}`)) {
    fail(`receipt output escapes target root: ${relativePath}`);
  }
  return resolved;
}

async function verifiedCurrentInputs(inputs) {
  if (!Array.isArray(inputs) || inputs.length === 0) {
    fail("receipt productionInputs must be a non-empty array");
  }
  const ids = new Set();
  const paths = new Set();
  return Promise.all(inputs.map(async (input) => {
    if (typeof input?.id !== "string" || typeof input?.path !== "string") {
      fail("receipt production input requires stable id and path");
    }
    if (ids.has(input.id) || paths.has(input.path)) {
      fail(`duplicate production input binding: ${input.id} / ${input.path}`);
    }
    ids.add(input.id);
    paths.add(input.path);
    return {
      id: input.id,
      path: input.path,
      ...await fileRecord(resolveRepositoryPath(input.path)),
    };
  }));
}

async function verifyExistingOutputs(targetRoot, receipt) {
  if (receipt.reproducibility !== "PASS_SECOND_COMPLETE_OFFLINE_RENDER") {
    fail(`${path.basename(targetRoot)} lacks its prior two-render reproducibility proof`);
  }
  if (!Array.isArray(receipt.outputs) || receipt.outputs.length === 0) {
    fail(`${path.basename(targetRoot)} has no receipt-bound outputs`);
  }
  await Promise.all(receipt.outputs.map(async (output) => {
    const current = await fileRecord(resolveOutputPath(targetRoot, output.path));
    if (current.bytes !== output.bytes || current.sha256 !== output.sha256) {
      fail(`${path.basename(targetRoot)}/${output.path}: existing output bytes drifted`);
    }
  }));
}

async function prepareTarget(directory, workObjectName) {
  const targetRoot = path.join(audioRoot, directory);
  const cacheRoot = path.join(audioRoot, "cache", directory);
  const workObjectPath = path.join(targetRoot, workObjectName);
  const receiptPath = path.join(targetRoot, "render-receipt.json");
  const [workBytes, receiptBytes] = await Promise.all([
    readFile(workObjectPath),
    readFile(receiptPath),
  ]);
  const workObject = JSON.parse(workBytes);
  const receipt = JSON.parse(receiptBytes);

  if (workObject.status !== "PROVISIONAL_NON_SHIPPING"
      || workObject.shippingState !== "PROHIBITED"
      || receipt.status !== "PROVISIONAL_NON_SHIPPING"
      || receipt.shippingState !== "PROHIBITED") {
    fail(`${directory}: non-shipping approval boundary drifted`);
  }
  if (JSON.stringify(workObject.provenance?.productionInputs)
      !== JSON.stringify(receipt.productionInputs)) {
    fail(`${directory}: work object and receipt do not share one prior input authority`);
  }

  await verifyExistingOutputs(cacheRoot, receipt);
  const productionInputs = await verifiedCurrentInputs(receipt.productionInputs);
  workObject.provenance.productionInputs = productionInputs;
  receipt.productionInputs = productionInputs;

  return {
    directory,
    workObjectPath,
    receiptPath,
    workObjectBytes: serialize(workObject),
    receiptBytes: serialize(receipt),
  };
}

async function atomicWrite(file, bytes) {
  const temporary = `${file}.receipt-rebind.tmp`;
  await writeFile(temporary, bytes, { flag: "wx" });
  await rename(temporary, file);
}

async function main() {
  if (process.argv.length !== 3 || process.argv[2] !== "--write") {
    fail("usage: rebind-responsive-audio-receipts.mjs --write");
  }
  const prepared = [];
  for (const [directory, workObjectName] of targets) {
    prepared.push(await prepareTarget(directory, workObjectName));
  }
  for (const target of prepared) {
    await atomicWrite(target.workObjectPath, target.workObjectBytes);
    await atomicWrite(target.receiptPath, target.receiptBytes);
    process.stdout.write(
      `${target.directory}\twork-object ${sha256(target.workObjectBytes)}\treceipt ${sha256(target.receiptBytes)}\n`,
    );
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
