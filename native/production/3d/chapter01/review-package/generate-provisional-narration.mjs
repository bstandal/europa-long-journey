#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import {
  mkdir,
  mkdtemp,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.join(root, "backstage/provisional-narration-script.json");
const outputRoot = path.join(root, "provisional-audio");

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function authoredDurationSeconds(text) {
  const words = text.trim().split(/\s+/u).length;
  return Math.max(3, Math.min(14, Math.ceil(words / 2.35) + 1));
}

async function toolVersion(executable, args) {
  const { stdout, stderr } = await execFileAsync(executable, args);
  return `${stdout}${stderr}`.split(/\r?\n/u)[0];
}

async function main() {
  const scriptBytes = await readFile(scriptPath);
  const script = JSON.parse(scriptBytes);
  if (script.status !== "NON_SHIPPING_TECHNICAL_REVIEW_AUDIO"
      || script.shippingState !== "PROHIBITED"
      || script.voice !== "Daniel"
      || script.speechRateWordsPerMinute !== 165
      || !Array.isArray(script.cues)
      || script.cues.length !== 10) {
    throw new Error("provisional narration script authority is invalid");
  }

  await mkdir(outputRoot, { recursive: true });
  const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "chapter01-v2-narration-"));
  try {
    const outputs = [];
    for (const [index, cue] of script.cues.entries()) {
      const expectedID = `narration-${String(index + 1).padStart(2, "0")}`;
      if (cue.id !== expectedID || typeof cue.text !== "string" || !cue.text.trim()) {
        throw new Error(`${expectedID}: invalid provisional narration cue`);
      }
      const durationSeconds = authoredDurationSeconds(cue.text);
      const aiff = path.join(temporaryRoot, `${cue.id}.aiff`);
      const destination = path.join(outputRoot, `${cue.id}.m4a`);
      await execFileAsync("say", [
        "-v", script.voice,
        "-r", String(script.speechRateWordsPerMinute),
        "-o", aiff,
        cue.text,
      ]);
      await execFileAsync("ffmpeg", [
        "-hide_banner", "-loglevel", "error", "-y",
        "-i", aiff,
        "-af", "apad",
        "-t", String(durationSeconds),
        "-ar", "48000",
        "-ac", "1",
        "-c:a", "aac",
        "-b:a", "160k",
        "-map_metadata", "-1",
        "-fflags", "+bitexact",
        "-flags:a", "+bitexact",
        destination,
      ]);
      const bytes = await readFile(destination);
      outputs.push({
        id: cue.id,
        textSHA256: sha256(Buffer.from(cue.text, "utf8")),
        authoredDurationSeconds: durationSeconds,
        sampleRate: 48000,
        repositoryPath: path.relative(
          path.resolve(root, "../../../../.."),
          destination,
        ).split(path.sep).join("/"),
        bytes: (await stat(destination)).size,
        sha256: sha256(bytes),
      });
    }
    const receipt = {
      schemaVersion: 1,
      status: script.status,
      shippingState: script.shippingState,
      finalNarrationGate: "OPEN",
      outputsAreFrozenPackageInputs: true,
      generatorReproducibilityAuthority: false,
      sourceScriptSHA256: sha256(scriptBytes),
      voice: script.voice,
      speechRateWordsPerMinute: script.speechRateWordsPerMinute,
      toolchain: {
        say: "macOS system say",
        ffmpeg: await toolVersion("ffmpeg", ["-version"]),
      },
      outputs,
    };
    await writeFile(
      path.join(root, "backstage/provisional-narration-receipt.json"),
      `${JSON.stringify(receipt, null, 2)}\n`,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
}

await main();
