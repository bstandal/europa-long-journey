#!/usr/bin/env node
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  compileFutureReleasePackage,
  validateFutureReleaseSource,
} from "./compile.mjs";
import { compileLaunchSet } from "./launch-set-compile.mjs";
import { validateBlueprint } from "./blueprint.mjs";
import { validateIOSConfiguration } from "./ios-config.mjs";
import {
  ValidationError,
  validateCollectionAgainstLaunchConfiguration,
  validateCostRegistry,
  validatePublicTree,
} from "./validate.mjs";

const [, , command, ...args] = process.argv;
const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(moduleDirectory, "../../..");
const webSourceInventoryPath = path.join(
  repositoryRoot,
  "native",
  "blueprint",
  "source-asset-provenance.json",
);

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

async function readProductionSigningKey() {
  const configuredPath = process.env.LONG_WEST_PACKAGE_SIGNING_KEY_FILE;
  if (!configuredPath) {
    throw new ValidationError(["LONG_WEST_PACKAGE_SIGNING_KEY_FILE: path to a private P-256 PEM file required"]);
  }
  const keyPath = path.resolve(configuredPath);
  if (isWithin(repositoryRoot, keyPath)) {
    throw new ValidationError(["LONG_WEST_PACKAGE_SIGNING_KEY_FILE: signing keys must remain outside the repository"]);
  }
  let keyStat;
  try {
    keyStat = await stat(keyPath);
  } catch {
    throw new ValidationError(["LONG_WEST_PACKAGE_SIGNING_KEY_FILE: key file is not readable"]);
  }
  if (!keyStat.isFile()) throw new ValidationError(["LONG_WEST_PACKAGE_SIGNING_KEY_FILE: regular file required"]);
  if ((keyStat.mode & 0o077) !== 0) {
    throw new ValidationError(["LONG_WEST_PACKAGE_SIGNING_KEY_FILE: permissions must deny group and other access (chmod 600)"]);
  }
  try {
    return await readFile(keyPath);
  } catch {
    throw new ValidationError(["LONG_WEST_PACKAGE_SIGNING_KEY_FILE: key file could not be read"]);
  }
}

async function readLaunchConfiguration() {
  const [product, catalog, delivery] = await Promise.all([
    readFile(path.join(repositoryRoot, "native", "product.json"), "utf8").then(JSON.parse),
    readFile(path.join(repositoryRoot, "native", "blueprint", "chapter-catalog.json"), "utf8").then(JSON.parse),
    readFile(path.join(repositoryRoot, "native", "blueprint", "delivery-plan.json"), "utf8").then(JSON.parse),
  ]);
  return { product, catalog, delivery };
}

function requireConfiguredPath(variableName) {
  const configuredPath = process.env[variableName];
  if (!configuredPath) throw new ValidationError([`${variableName}: absolute file path required`]);
  return path.resolve(configuredPath);
}

function futureReleaseOptions(launchConfiguration) {
  return {
    futureReleaseApprovalPath: requireConfiguredPath("LONG_WEST_RELEASE_APPROVAL_FILE"),
    futureReleasePublicationPath: requireConfiguredPath(
      "LONG_WEST_RELEASE_PUBLICATION_FILE",
    ),
    futureReleaseWorldAuthorityPath: requireConfiguredPath(
      "LONG_WEST_RELEASE_WORLD_AUTHORITY_FILE",
    ),
    assetProvenancePath: requireConfiguredPath("LONG_WEST_RELEASE_ASSET_PROVENANCE_FILE"),
    costRegistryPath: path.join(
      repositoryRoot,
      "native",
      "tooling",
      "registries",
      "cost-license.json",
    ),
    webSourceInventoryPath,
    projectSourceRoot: repositoryRoot,
    launchConfiguration,
  };
}

async function main() {
  if (command === "validate-public") {
    const [root] = args;
    const resolvedRoot = path.resolve(root);
    const files = await validatePublicTree(resolvedRoot);
    let collection;
    try {
      collection = JSON.parse(await readFile(path.join(resolvedRoot, "collection.json"), "utf8"));
    } catch {
      throw new ValidationError(["validate-public: collection.json is required for a launch package"]);
    }
    const issues = validateCollectionAgainstLaunchConfiguration(
      collection,
      await readLaunchConfiguration(),
    );
    if (issues.length) throw new ValidationError(issues);
    console.log(`Validated ${files.length} public package files.`);
    return;
  }
  if (command === "validate-costs") {
    const [registryPath] = args;
    const registry = JSON.parse(await readFile(path.resolve(registryPath), "utf8"));
    validateCostRegistry(registry);
    console.log(`Validated ${registry.entries.length} zero-cost production entries.`);
    return;
  }
  if (command === "validate-blueprint") {
    const [root] = args;
    const result = await validateBlueprint(path.resolve(root));
    console.log(`Validated Phase 0: ${result.chapters} chapters, ${result.arcs} arcs, ${result.movements} movements, ${result.interactions} interactions and ${result.traces} world traces.`);
    return;
  }
  if (command === "validate-ios") {
    const [root] = args;
    const result = await validateIOSConfiguration(path.resolve(root));
    console.log(`Validated ${result.displayName}: iOS ${result.deploymentTarget}, iPhone ${result.orientation}, performance gaming tier.`);
    return;
  }
  if (command === "validate-release") {
    const [sourceRoot] = args;
    if (!sourceRoot) throw new ValidationError(["validate-release: source path required"]);
    const launchConfiguration = await readLaunchConfiguration();
    const result = await validateFutureReleaseSource(
      path.resolve(sourceRoot),
      futureReleaseOptions(launchConfiguration),
    );
    console.log(`Validated future release ${result.release.id} for ${result.packageSpec.id}.`);
    return;
  }
  if (command === "compile") {
    throw new ValidationError([
      "compile: single-package launch signing is disabled; use compile-launch-set",
    ]);
  }
  if (command === "compile-launch-set") {
    const [descriptorPath, outputRoot] = args;
    if (!descriptorPath || !outputRoot || args.length !== 2) {
      throw new ValidationError([
        "compile-launch-set: launch-set input JSON and output paths required",
      ]);
    }
    let descriptor;
    try {
      descriptor = JSON.parse(await readFile(path.resolve(descriptorPath), "utf8"));
    } catch (error) {
      throw new ValidationError([`compile-launch-set: ${error.message}`]);
    }
    const receipt = await compileLaunchSet(descriptor, path.resolve(outputRoot), {
      blueprintRoot: path.resolve(process.env.LONG_WEST_BLUEPRINT_ROOT ?? path.resolve(moduleDirectory, "../../blueprint")),
      keyID: process.env.LONG_WEST_PACKAGE_SIGNING_KEY_ID,
      signingPrivateKey: await readProductionSigningKey(),
      launchConfiguration: await readLaunchConfiguration(),
      costRegistryPath: path.join(
        repositoryRoot,
        "native",
        "tooling",
        "registries",
        "cost-license.json",
      ),
      webSourceInventoryPath,
      projectSourceRoot: repositoryRoot,
    });
    console.log(`Compiled and signed launch set ${receipt.receiptSHA256} with final world ${receipt.finalWorldSHA256}.`);
    return;
  }
  if (command === "compile-release") {
    const [sourceRoot, outputRoot] = args;
    if (!sourceRoot || !outputRoot) {
      throw new ValidationError(["compile-release: source and output paths required"]);
    }
    const launchConfiguration = await readLaunchConfiguration();
    const result = await compileFutureReleasePackage(
      path.resolve(sourceRoot),
      path.resolve(outputRoot),
      {
        ...futureReleaseOptions(launchConfiguration),
        keyID: process.env.LONG_WEST_PACKAGE_SIGNING_KEY_ID,
        signingPrivateKey: await readProductionSigningKey(),
      },
    );
    console.log(`Compiled and signed future release ${result.release.id} as ${result.manifest.packageID} (${result.manifest.manifestDigest}).`);
    return;
  }
  throw new Error("Usage: cli.mjs <validate-public|validate-release|validate-costs|validate-blueprint|validate-ios|compile-launch-set|compile-release> <paths...>; compilation requires the documented LONG_WEST_* environment");
}

main().catch((error) => {
  if (error instanceof ValidationError) {
    console.error(error.issues.join("\n"));
  } else {
    console.error(error.stack ?? error.message);
  }
  process.exitCode = 1;
});
