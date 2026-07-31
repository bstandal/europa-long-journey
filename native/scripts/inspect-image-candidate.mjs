#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const DEFAULTS = Object.freeze({
  minWidth: 1290,
  minHeight: 2796,
  sampleWidth: 96,
  sampleHeight: 96,
  minimumLumaRange: 24,
  minimumLumaStandardDeviation: 10,
  minimumMeanLuma: 3,
  maximumMeanLuma: 252,
  maximumNearBlackFraction: 0.97,
  maximumNearWhiteFraction: 0.97,
});

const parsePositiveInteger = (name, value) => {
  if (!/^\d+$/.test(value)) {
    throw new Error(`${name} must be a positive integer`);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
};

export function analyseLuma(sample) {
  if (!(sample instanceof Uint8Array) || sample.length === 0) {
    throw new Error("luma sample must contain bytes");
  }

  let minimum = 255;
  let maximum = 0;
  let sum = 0;
  let sumSquares = 0;
  let nearBlack = 0;
  let nearWhite = 0;

  for (const value of sample) {
    minimum = Math.min(minimum, value);
    maximum = Math.max(maximum, value);
    sum += value;
    sumSquares += value * value;
    if (value <= 4) nearBlack += 1;
    if (value >= 251) nearWhite += 1;
  }

  const mean = sum / sample.length;
  const variance = Math.max(0, sumSquares / sample.length - mean * mean);

  return {
    minimum,
    maximum,
    range: maximum - minimum,
    mean,
    standardDeviation: Math.sqrt(variance),
    nearBlackFraction: nearBlack / sample.length,
    nearWhiteFraction: nearWhite / sample.length,
  };
}

export function evaluateCandidate({ width, height, formatName, luma }, limits = DEFAULTS) {
  const failures = [];
  if (formatName !== "png_pipe") failures.push(`format ${formatName} is not PNG`);
  if (width < limits.minWidth) failures.push(`width ${width} is below ${limits.minWidth}`);
  if (height < limits.minHeight) failures.push(`height ${height} is below ${limits.minHeight}`);
  if (luma.range < limits.minimumLumaRange) {
    failures.push(`luma range ${luma.range} is below ${limits.minimumLumaRange}`);
  }
  if (luma.standardDeviation < limits.minimumLumaStandardDeviation) {
    failures.push(
      `luma standard deviation ${luma.standardDeviation.toFixed(3)} is below ${limits.minimumLumaStandardDeviation}`,
    );
  }
  if (luma.mean <= limits.minimumMeanLuma) {
    failures.push(`mean luma ${luma.mean.toFixed(3)} is effectively black`);
  }
  if (luma.mean >= limits.maximumMeanLuma) {
    failures.push(`mean luma ${luma.mean.toFixed(3)} is effectively white`);
  }
  if (luma.nearBlackFraction >= limits.maximumNearBlackFraction) {
    failures.push(
      `near-black fraction ${luma.nearBlackFraction.toFixed(5)} exceeds ${limits.maximumNearBlackFraction}`,
    );
  }
  if (luma.nearWhiteFraction >= limits.maximumNearWhiteFraction) {
    failures.push(
      `near-white fraction ${luma.nearWhiteFraction.toFixed(5)} exceeds ${limits.maximumNearWhiteFraction}`,
    );
  }
  return failures;
}

function run(command, arguments_, options = {}) {
  const result = spawnSync(command, arguments_, {
    encoding: options.encoding,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const stderr = Buffer.isBuffer(result.stderr)
      ? result.stderr.toString("utf8")
      : result.stderr;
    throw new Error(`${command} failed: ${stderr?.trim() || `exit ${result.status}`}`);
  }
  return result.stdout;
}

function parseArguments(argv) {
  const options = { ...DEFAULTS };
  let candidatePath;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) {
      if (candidatePath) throw new Error("only one candidate path is permitted");
      candidatePath = argument;
      continue;
    }

    const value = argv[index + 1];
    if (argument === "--min-width") {
      options.minWidth = parsePositiveInteger(argument, value);
    } else if (argument === "--min-height") {
      options.minHeight = parsePositiveInteger(argument, value);
    } else {
      throw new Error(`unknown argument ${argument}`);
    }
    index += 1;
  }

  if (!candidatePath) {
    throw new Error("usage: inspect-image-candidate.mjs <candidate.png> [--min-width N] [--min-height N]");
  }
  return { candidatePath: path.resolve(candidatePath), options };
}

export async function inspectImageCandidate(candidatePath, limits = DEFAULTS) {
  const probeBytes = run(
    "ffprobe",
    [
      "-v", "error",
      "-select_streams", "v:0",
      "-show_entries", "stream=width,height:format=format_name",
      "-of", "json",
      candidatePath,
    ],
    { encoding: "utf8" },
  );
  const probe = JSON.parse(probeBytes);
  const stream = probe.streams?.[0];
  if (!stream) throw new Error("candidate has no visual stream");

  const rawLuma = run("ffmpeg", [
    "-v", "error",
    "-i", candidatePath,
    "-vf", `scale=${limits.sampleWidth}:${limits.sampleHeight}:flags=area,format=gray`,
    "-frames:v", "1",
    "-f", "rawvideo",
    "pipe:1",
  ]);
  const expectedSampleBytes = limits.sampleWidth * limits.sampleHeight;
  if (rawLuma.length !== expectedSampleBytes) {
    throw new Error(`expected ${expectedSampleBytes} luma bytes, received ${rawLuma.length}`);
  }

  const fileBytes = await readFile(candidatePath);
  const luma = analyseLuma(rawLuma);
  const report = {
    schemaVersion: 1,
    candidatePath,
    sha256: createHash("sha256").update(fileBytes).digest("hex"),
    bytes: fileBytes.length,
    formatName: probe.format?.format_name,
    width: stream.width,
    height: stream.height,
    luma,
  };
  report.failures = evaluateCandidate(report, limits);
  report.status = report.failures.length === 0 ? "SANITY_PASS" : "REJECT";
  return report;
}

async function main() {
  const { candidatePath, options } = parseArguments(process.argv.slice(2));
  const report = await inspectImageCandidate(candidatePath, options);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (report.status !== "SANITY_PASS") process.exitCode = 2;
}

const isMain = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}

