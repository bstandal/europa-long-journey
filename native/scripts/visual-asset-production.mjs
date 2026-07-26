#!/usr/bin/env node

import {
  mkdtemp,
  mkdir,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { createHash } from "node:crypto";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  buildVisualAssetDAG,
  createProvisionalVisualMasterAuthority,
  validateVisualProductionContract,
  verifyVisualAssetReceipt,
} from "../tooling/src/visual-asset-production.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const defaults = {
  contract: path.join(repositoryRoot, "native/design/phase1/harvest/layer-production-contract.json"),
  fixture: path.join(repositoryRoot, "native/phase1/fixtures/harvest-option-1.scene.json"),
  costs: path.join(repositoryRoot, "native/tooling/registries/cost-license.json"),
};

const readJSON = async (filePath) => JSON.parse(await readFile(filePath, "utf8"));
const repositoryPath = (filePath) => path.relative(repositoryRoot, path.resolve(filePath)).split(path.sep).join("/");

function parse(argv) {
  const command = argv.shift();
  if (!["validate-contract", "freeze-provisional-master", "build", "verify"].includes(command)) {
    throw new Error("usage: visual-asset-production.mjs validate-contract | freeze-provisional-master --candidate FILE --metadata FILE --authority FILE | build --dag FILE --output DIR --receipt FILE | verify --dag FILE --receipt FILE");
  }
  const options = { ...defaults };
  while (argv.length) {
    const flag = argv.shift();
    const value = argv.shift();
    if (!["--contract", "--fixture", "--costs", "--candidate", "--metadata", "--authority", "--dag", "--output", "--receipt"].includes(flag) || !value) {
      throw new Error(`unknown or incomplete option '${flag}'`);
    }
    options[flag.slice(2)] = path.resolve(value);
  }
  if (command === "build" && (!options.dag || !options.output || !options.receipt)) {
    throw new Error("build requires --dag, --output and --receipt");
  }
  if (command === "verify" && (!options.dag || !options.receipt)) {
    throw new Error("verify requires --dag and --receipt");
  }
  if (command === "freeze-provisional-master" && (!options.candidate || !options.metadata || !options.authority)) {
    throw new Error("freeze-provisional-master requires --candidate, --metadata and --authority");
  }
  return { command, options };
}

async function loadCommon(options) {
  const [fixtureBytes, contract, costRegistry] = await Promise.all([
    readFile(options.fixture),
    readJSON(options.contract),
    readJSON(options.costs),
  ]);
  return {
    fixtureBytes,
    fixture: JSON.parse(fixtureBytes),
    contract,
    costRegistry,
    repositoryRoot,
    contractRepositoryPath: repositoryPath(options.contract),
  };
}

async function directoryExists(filePath) {
  try {
    return (await stat(filePath)).isDirectory();
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

async function main() {
  const { command, options } = parse(process.argv.slice(2));
  const common = await loadCommon(options);
  if (command === "validate-contract") {
    const result = await validateVisualProductionContract(common);
    process.stdout.write(
      `Harvest visual production contract locked to ${result.inventory.counts.total} future files; no asset or shipping approval was created.\n`,
    );
    return;
  }

  if (command === "freeze-provisional-master") {
    const backstageRoot = path.join(repositoryRoot, "native/content/backstage");
    const resolvedAuthority = path.resolve(options.authority);
    if (!resolvedAuthority.startsWith(`${backstageRoot}${path.sep}`)) {
      throw new Error("provisional authority must remain under native/content/backstage");
    }
    const authority = await createProvisionalVisualMasterAuthority({
      ...common,
      candidatePath: options.candidate,
      candidateMetadataPath: options.metadata,
    });
    const authorityBytes = Buffer.from(`${JSON.stringify(authority, null, 2)}\n`);
    await mkdir(path.dirname(resolvedAuthority), { recursive: true });
    try {
      await writeFile(resolvedAuthority, authorityBytes, { flag: "wx" });
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      const existing = await readFile(resolvedAuthority);
      if (!existing.equals(authorityBytes)) {
        throw new Error(`refusing to replace a different frozen authority: ${resolvedAuthority}`);
      }
    }
    const authoritySHA256 = createHash("sha256").update(authorityBytes).digest("hex");
    process.stdout.write(
      `Frozen ${authority.candidate.id} as ${authority.status} for local development only at ${repositoryPath(resolvedAuthority)} (${authoritySHA256}); editor and shipping authority remain absent.\n`,
    );
    return;
  }

  const dag = await readJSON(options.dag);
  if (command === "build") {
    if (dag.buildMode === "CODEX_PROVISIONAL_NON_SHIPPING_DEVELOPMENT") {
      const developmentRoot = path.join(repositoryRoot, "native/.build");
      const backstageRoot = path.join(repositoryRoot, "native/content/backstage");
      if (!options.output.startsWith(`${developmentRoot}${path.sep}`)) {
        throw new Error("provisional visual output must remain under native/.build");
      }
      if (!options.dag.startsWith(`${backstageRoot}${path.sep}`)
          || !options.receipt.startsWith(`${backstageRoot}${path.sep}`)) {
        throw new Error("provisional visual DAG and receipt must remain under native/content/backstage");
      }
    }
    if (await directoryExists(options.output)) {
      throw new Error(`output directory already exists: ${options.output}`);
    }
    await mkdir(options.output, { recursive: true });
    const result = await buildVisualAssetDAG({ ...common, dag, outputRoot: options.output });
    await mkdir(path.dirname(options.receipt), { recursive: true });
    await writeFile(options.receipt, `${JSON.stringify(result.receipt, null, 2)}\n`);
    process.stdout.write(
      `Built ${result.receipt.outputs.length} registered outputs in ${result.receipt.buildMode}; editor asset and shipping approval remain separate.\n`,
    );
    return;
  }

  const expectedReceipt = await readJSON(options.receipt);
  const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-verify-"));
  try {
    const result = await verifyVisualAssetReceipt({
      ...common,
      dag,
      outputRoot: temporaryRoot,
      expectedReceipt,
    });
    process.stdout.write(
      `Rebuilt ${result.receipt.outputs.length} outputs with byte-identical hashes and matching recomposition metrics.\n`,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
