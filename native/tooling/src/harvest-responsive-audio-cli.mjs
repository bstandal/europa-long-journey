#!/usr/bin/env node
import {
  renderHarvestResponsiveAudio,
  validateHarvestResponsiveAudio,
} from "./harvest-responsive-audio.mjs";
import { AudioProductionError } from "./audio-production.mjs";

const command = process.argv[2];

async function main() {
  if (command === "render") {
    const result = await renderHarvestResponsiveAudio({ verifyReproducibility: true });
    process.stdout.write(
      `Rendered ${result.receipt.outputs.length} Harvest audio files twice with identical bytes.\n`,
    );
    return;
  }
  if (command === "validate") {
    const result = await validateHarvestResponsiveAudio();
    process.stdout.write(
      `Validated provisional Harvest work object ${result.workObjectSHA256} and receipt ${result.receiptSHA256}.\n`,
    );
    return;
  }
  throw new AudioProductionError([
    "usage: harvest-responsive-audio-cli.mjs render | validate",
  ]);
}

main().catch((error) => {
  if (error instanceof AudioProductionError || error instanceof SyntaxError) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
    return;
  }
  throw error;
});
