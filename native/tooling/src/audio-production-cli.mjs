#!/usr/bin/env node
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  AudioProductionError,
  readAudioProductionFiles,
  renderAudioTechnicalProbe,
  validateAudioRendererRuntime,
  validateAudioProductionEvidence,
} from "./audio-production.mjs";

const [, , command, ...args] = process.argv;
const toolingDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolingDirectory, "../../..");
const audioRoot = path.join(repositoryRoot, "native", "audio", "score-soundscape");
const defaults = {
  scorePath: path.join(audioRoot, "harvest-score-technique.json"),
  soundscapePath: path.join(audioRoot, "harvest-soundscape-technique.json"),
  toolchainPath: path.join(audioRoot, "toolchain.json"),
  soundFontPath: path.join(audioRoot, "cache", "ms-basic-0.2.0.sf3"),
  outputDirectory: path.join(audioRoot, "cache", "technical-probe"),
  receiptPath: path.join(audioRoot, "probes", "technical-probe-receipt.json"),
  costRegistryPath: path.join(repositoryRoot, "native", "tooling", "registries", "cost-license.json"),
};

async function validate() {
  const [scorePath = defaults.scorePath, soundscapePath = defaults.soundscapePath, toolchainPath = defaults.toolchainPath] = args;
  await readAudioProductionFiles(
    path.resolve(scorePath),
    path.resolve(soundscapePath),
    path.resolve(toolchainPath),
  );
  console.log("Validated symbolic score, procedural soundscape and pinned zero-cost toolchain.");
}

async function bootstrap() {
  const { toolchain } = await readAudioProductionFiles(
    defaults.scorePath,
    defaults.soundscapePath,
    defaults.toolchainPath,
  );
  await mkdir(path.dirname(defaults.soundFontPath), { recursive: true });
  const response = await fetch(toolchain.soundFont.sourceURL, { redirect: "follow" });
  if (!response.ok) throw new AudioProductionError([`soundfont bootstrap: HTTP ${response.status}`]);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length !== toolchain.soundFont.bytes) {
    throw new AudioProductionError(["soundfont bootstrap: downloaded byte count differs from pinned source"]);
  }
  const { createHash } = await import("node:crypto");
  const digest = createHash("sha256").update(bytes).digest("hex");
  if (digest !== toolchain.soundFont.sha256) {
    throw new AudioProductionError(["soundfont bootstrap: downloaded SHA-256 differs from pinned source"]);
  }
  await writeFile(defaults.soundFontPath, bytes);
  console.log(`Verified and cached ${bytes.length} bytes at ${defaults.soundFontPath}.`);
}

async function preflight() {
  const files = await readAudioProductionFiles(
    defaults.scorePath,
    defaults.soundscapePath,
    defaults.toolchainPath,
  );
  await validateAudioRendererRuntime({
    toolchain: files.toolchain,
    soundFontPath: defaults.soundFontPath,
  });
  await validateAudioProductionEvidence({
    files,
    costRegistryPath: defaults.costRegistryPath,
    receiptPath: defaults.receiptPath,
  });
  console.log("Verified exact audio sources, runtime, renderer, SoundFont, notice, receipt and zero-cost bindings.");
}

async function render() {
  const [outputDirectory = defaults.outputDirectory, soundFontPath = defaults.soundFontPath] = args;
  const files = await readAudioProductionFiles(
    defaults.scorePath,
    defaults.soundscapePath,
    defaults.toolchainPath,
  );
  const receipt = await renderAudioTechnicalProbe({
    ...files,
    outputDirectory: path.resolve(outputDirectory),
    soundFontPath: path.resolve(soundFontPath),
  });
  await mkdir(path.dirname(defaults.receiptPath), { recursive: true });
  await writeFile(defaults.receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
  console.log(`Rendered ${receipt.outputs.length} technical files; receipt: ${defaults.receiptPath}.`);
}

async function main() {
  if (command === "validate") return validate();
  if (command === "bootstrap") return bootstrap();
  if (command === "preflight") return preflight();
  if (command === "render") return render();
  throw new AudioProductionError([
    "usage: audio-production-cli.mjs validate [score soundscape toolchain] | bootstrap | preflight | render [output-dir soundfont]",
  ]);
}

main().catch((error) => {
  if (error instanceof AudioProductionError || error instanceof SyntaxError) {
    console.error(error.message);
    process.exitCode = 1;
    return;
  }
  throw error;
});
