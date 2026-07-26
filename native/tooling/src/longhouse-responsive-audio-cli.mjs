#!/usr/bin/env node
import { AudioProductionError } from "./audio-production.mjs";
import {
  renderLonghouseResponsiveAudio,
  validateLonghouseResponsiveAudio,
} from "./longhouse-responsive-audio.mjs";

const command = process.argv[2];

async function main() {
  if (command === "render") {
    const result = await renderLonghouseResponsiveAudio({ verifyReproducibility: true });
    process.stdout.write(
      `Rendered ${result.receipt.outputs.length} Longhouse audio files twice with identical bytes.\n`,
    );
    return;
  }
  if (command === "validate") {
    const result = await validateLonghouseResponsiveAudio();
    process.stdout.write(
      `Validated provisional Longhouse work object ${result.workObjectSHA256} and receipt ${result.receiptSHA256}.\n`,
    );
    return;
  }
  throw new AudioProductionError([
    "usage: longhouse-responsive-audio-cli.mjs render | validate",
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
