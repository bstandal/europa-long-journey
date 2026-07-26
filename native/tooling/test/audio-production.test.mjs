import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  compileScoreStemMIDI,
  inspectPCM24StereoWAV,
  readAudioProductionFiles,
  renderAudioTechnicalProbe,
  renderProceduralSoundscapeLayers,
  validateAudioToolchain,
  validateAudioProductionEvidence,
  validateAudioRendererRuntime,
  validateScoreProductionPlan,
  validateSoundscapeProductionPlan,
} from "../src/audio-production.mjs";

const repositoryRoot = fileURLToPath(new URL("../../../", import.meta.url));
const audioRoot = path.join(repositoryRoot, "native", "audio", "score-soundscape");
const scorePath = path.join(audioRoot, "harvest-score-technique.json");
const soundscapePath = path.join(audioRoot, "harvest-soundscape-technique.json");
const toolchainPath = path.join(audioRoot, "toolchain.json");
const receiptPath = path.join(audioRoot, "probes", "technical-probe-receipt.json");
const costRegistryPath = path.join(repositoryRoot, "native", "tooling", "registries", "cost-license.json");
const soundFontPath = path.join(audioRoot, "cache", "ms-basic-0.2.0.sf3");
const fluidSynthPath = "/opt/homebrew/bin/fluidsynth";
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

async function fixtures() {
  return readAudioProductionFiles(scorePath, soundscapePath, toolchainPath);
}

test("the Harvest technique plans preserve symbolic score, independent stems and authored silence", async () => {
  const { scorePlan, soundscapePlan } = await fixtures();
  assert.equal(validateScoreProductionPlan(scorePlan), scorePlan);
  assert.equal(validateSoundscapeProductionPlan(soundscapePlan), soundscapePlan);
  assert.equal(scorePlan.stems.length, 3);
  assert.deepEqual(
    new Set(soundscapePlan.layers.map(({ material }) => material)),
    new Set(["rain", "fire", "grain", "textile", "work"]),
  );
  assert.equal(soundscapePlan.silenceWindows[0].entry, "authored-cut");
  assert.equal(soundscapePlan.silenceWindows[0].exit, "authored-return");
});

test("score validation fails closed on uneditable, dangling and out-of-range material", async () => {
  const { scorePlan } = await fixtures();

  const rawTrack = structuredClone(scorePlan);
  rawTrack.stems = [];
  assert.throws(() => validateScoreProductionPlan(rawTrack), /independently renderable stems/);

  const dangling = structuredClone(scorePlan);
  dangling.stems[0].phrases[0].motifID = "unknown-motif";
  assert.throws(() => validateScoreProductionPlan(dangling), /known motif required/);

  const overflow = structuredClone(scorePlan);
  overflow.stems[0].phrases[0].atBeat = 23;
  assert.throws(() => validateScoreProductionPlan(overflow), /exceeds durationBeats/);
});

test("each score stem compiles to stable standard MIDI with the shared tempo track", async () => {
  const { scorePlan } = await fixtures();
  const outputs = scorePlan.stems.map(({ id }) => compileScoreStemMIDI(scorePlan, id));
  for (const midi of outputs) {
    assert.equal(midi.toString("ascii", 0, 4), "MThd");
    assert.equal(midi.readUInt16BE(8), 1);
    assert.equal(midi.readUInt16BE(10), 2);
    assert.equal(midi.readUInt16BE(12), 960);
  }
  assert.equal(sha256(outputs[0]), sha256(compileScoreStemMIDI(scorePlan, scorePlan.stems[0].id)));
  assert.equal(new Set(outputs.map(sha256)).size, scorePlan.stems.length);
});

test("procedural material layers are deterministic 48 kHz 24-bit stereo WAVs", async () => {
  const { soundscapePlan } = await fixtures();
  const first = renderProceduralSoundscapeLayers(soundscapePlan);
  const second = renderProceduralSoundscapeLayers(soundscapePlan);
  assert.equal(first.size, 5);
  for (const [id, wav] of first) {
    assert.equal(sha256(wav), sha256(second.get(id)));
    assert.deepEqual(inspectPCM24StereoWAV(wav), {
      sampleRate: 48_000,
      bitDepth: 24,
      channels: 2,
      frames: 384_000,
    });
    assert.notEqual(sha256(wav.subarray(44)), sha256(Buffer.alloc(wav.length - 44)));
  }
});

test("herd ground movement is deterministic, source-bound and sensitive to authored density", async () => {
  const { soundscapePlan } = await fixtures();
  const herdPlan = structuredClone(soundscapePlan);
  herdPlan.layers[0] = {
    id: "herd-lanes",
    material: "herd",
    visibleSource: "Visible domestic herds moving on the worn lane between enclosure and pasture",
    generator: {
      algorithm: "herd-ground-movement-v1",
      seed: 55004001,
      density: 0.42,
      colour: 0.61,
    },
    gainDB: -22,
    pan: -0.12,
    loop: false,
  };
  assert.equal(validateSoundscapeProductionPlan(herdPlan), herdPlan);

  const first = renderProceduralSoundscapeLayers(herdPlan).get("herd-lanes");
  const second = renderProceduralSoundscapeLayers(herdPlan).get("herd-lanes");
  assert.equal(sha256(first), sha256(second));
  assert.deepEqual(inspectPCM24StereoWAV(first), {
    sampleRate: 48_000,
    bitDepth: 24,
    channels: 2,
    frames: 384_000,
  });
  assert.notEqual(sha256(first.subarray(44)), sha256(Buffer.alloc(first.length - 44)));

  const denserPlan = structuredClone(herdPlan);
  denserPlan.layers[0].generator.density = 0.7;
  const denser = renderProceduralSoundscapeLayers(denserPlan).get("herd-lanes");
  assert.notEqual(sha256(first), sha256(denser));

  const mismatched = structuredClone(herdPlan);
  mismatched.layers[0].generator.algorithm = "distant-material-work-v1";
  assert.throws(() => validateSoundscapeProductionPlan(mismatched), /material\/algorithm mismatch/);
});

test("close water movement is deterministic, distinct from rain and sensitive to authored density", async () => {
  const { soundscapePlan } = await fixtures();
  const waterPlan = structuredClone(soundscapePlan);
  waterPlan.layers[0] = {
    id: "close-water",
    material: "water",
    visibleSource: "Visible shallows, wake and close river surface moving around the loaded craft",
    generator: {
      algorithm: "close-water-movement-v1",
      seed: 55005001,
      density: 0.46,
      colour: 0.54,
    },
    gainDB: -22,
    pan: 0.08,
    loop: false,
  };
  assert.equal(validateSoundscapeProductionPlan(waterPlan), waterPlan);

  const first = renderProceduralSoundscapeLayers(waterPlan).get("close-water");
  const second = renderProceduralSoundscapeLayers(waterPlan).get("close-water");
  assert.equal(sha256(first), sha256(second));
  assert.deepEqual(inspectPCM24StereoWAV(first), {
    sampleRate: 48_000,
    bitDepth: 24,
    channels: 2,
    frames: 384_000,
  });
  assert.notEqual(sha256(first.subarray(44)), sha256(Buffer.alloc(first.length - 44)));

  const denserPlan = structuredClone(waterPlan);
  denserPlan.layers[0].generator.density = 0.72;
  const denser = renderProceduralSoundscapeLayers(denserPlan).get("close-water");
  assert.notEqual(sha256(first), sha256(denser));

  const rainPlan = structuredClone(waterPlan);
  rainPlan.layers[0].material = "rain";
  rainPlan.layers[0].generator.algorithm = "rain-on-earth-v1";
  const rain = renderProceduralSoundscapeLayers(rainPlan).get("close-water");
  assert.notEqual(sha256(first), sha256(rain));

  const mismatched = structuredClone(waterPlan);
  mismatched.layers[0].generator.algorithm = "rain-on-earth-v1";
  assert.throws(() => validateSoundscapeProductionPlan(mismatched), /material\/algorithm mismatch/);
});

test("distant human presence is deterministic, non-lexical and sensitive to authored density", async () => {
  const { soundscapePlan } = await fixtures();
  const humanPlan = structuredClone(soundscapePlan);
  humanPlan.layers[0] = {
    id: "household-voices",
    material: "human",
    visibleSource: "Visible households working together at the river landing without attributed speech",
    generator: {
      algorithm: "distant-human-presence-v1",
      seed: 55006001,
      density: 0.38,
      colour: 0.45,
    },
    gainDB: -25,
    pan: 0.16,
    loop: false,
  };
  assert.equal(validateSoundscapeProductionPlan(humanPlan), humanPlan);

  const first = renderProceduralSoundscapeLayers(humanPlan).get("household-voices");
  const second = renderProceduralSoundscapeLayers(humanPlan).get("household-voices");
  assert.equal(sha256(first), sha256(second));
  assert.deepEqual(inspectPCM24StereoWAV(first), {
    sampleRate: 48_000,
    bitDepth: 24,
    channels: 2,
    frames: 384_000,
  });
  assert.notEqual(sha256(first.subarray(44)), sha256(Buffer.alloc(first.length - 44)));

  const denserPlan = structuredClone(humanPlan);
  denserPlan.layers[0].generator.density = 0.68;
  const denser = renderProceduralSoundscapeLayers(denserPlan).get("household-voices");
  assert.notEqual(sha256(first), sha256(denser));

  const textInput = structuredClone(humanPlan);
  textInput.layers[0].generator.text = "invented words";
  assert.throws(() => validateSoundscapeProductionPlan(textInput), /unsupported field/);

  const mismatched = structuredClone(humanPlan);
  mismatched.layers[0].generator.algorithm = "herd-ground-movement-v1";
  assert.throws(() => validateSoundscapeProductionPlan(mismatched), /material\/algorithm mismatch/);
});

test("new source-bound generators leave every earlier procedural generator byte-identical", async () => {
  const { soundscapePlan } = await fixtures();
  const expected = new Map([
    ["rain-earth", "1aab4dd5a9e99a49be6aec44c27ebb1513dab60cc2ce6148eb424878f0a09fd8"],
    ["hearth-fire", "379f5a17a118e2f97d4917fce9d6d4123971456cfbecfb53cad6015cefdc5532"],
    ["grain-contact", "9629787cb6b3dec3c11816af6fda04e12c069d203a2c7d89ce71cc995dfb0e46"],
    ["fibre-strain", "21d4e4320234f80c9daa1b6441abbf9a32023ea616a65c5794665ca484fd06dd"],
    ["settlement-work", "1aa560035b3f76ba2a8a006e8f1ef4d94d84f27b525c51c868411cfd8c982388"],
  ]);
  for (const [id, wav] of renderProceduralSoundscapeLayers(soundscapePlan)) {
    assert.equal(sha256(wav), expected.get(id));
  }

  const herdPlan = structuredClone(soundscapePlan);
  herdPlan.layers[0] = {
    id: "herd-lanes",
    material: "herd",
    visibleSource: "Visible domestic herds moving on the worn lane between enclosure and pasture",
    generator: {
      algorithm: "herd-ground-movement-v1",
      seed: 55004001,
      density: 0.42,
      colour: 0.61,
    },
    gainDB: -22,
    pan: -0.12,
    loop: false,
  };
  const herd = renderProceduralSoundscapeLayers(herdPlan).get("herd-lanes");
  assert.equal(sha256(herd), "c74cbd18b7f680c82ab222a019a192ae37c1033ee7bc6b969ab1cbdf2d73837d");
});

test("soundscape validation rejects missing source binding and implicit silence", async () => {
  const { soundscapePlan } = await fixtures();

  const sourceLess = structuredClone(soundscapePlan);
  sourceLess.layers[0].visibleSource = "";
  assert.throws(() => validateSoundscapeProductionPlan(sourceLess), /visibleSource/);

  const noSilence = structuredClone(soundscapePlan);
  noSilence.silenceWindows = [];
  assert.throws(() => validateSoundscapeProductionPlan(noSilence), /authored silence/);

  const mismatched = structuredClone(soundscapePlan);
  mismatched.layers[0].generator.algorithm = "small-hearth-fire-v1";
  assert.throws(() => validateSoundscapeProductionPlan(mismatched), /material\/algorithm mismatch/);

  const tooFew = structuredClone(soundscapePlan);
  tooFew.layers = tooFew.layers.slice(0, 4);
  assert.throws(() => validateSoundscapeProductionPlan(tooFew), /at least five source-bound/);
});

test("the production toolchain requires one pinned official source and licence chain", async () => {
  const { toolchain } = await fixtures();
  assert.equal(validateAudioToolchain(toolchain), toolchain);

  const mirror = structuredClone(toolchain);
  mirror.soundFont.sourceURL = "https://example.invalid/ms-basic.sf3";
  assert.throws(() => validateAudioToolchain(mirror), /pinned official MuseScore commit/);

  const conditional = structuredClone(toolchain);
  conditional.soundFont.license = "custom-commercial";
  assert.throws(() => validateAudioToolchain(conditional), /MIT record required/);
});

test("the pinned local renderer produces separately hashed technical stems", {
  skip: !(existsSync(soundFontPath) && existsSync(fluidSynthPath)),
}, async () => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-audio-probe-"));
  try {
    const files = await fixtures();
    const receipt = await renderAudioTechnicalProbe({
      ...files,
      outputDirectory: temporary,
      soundFontPath,
      fluidSynthPath,
    });
    assert.equal(receipt.status, "TECHNICAL_PROBE_NOT_APPROVED");
    assert.equal(receipt.gates.symbolicEditability, "PASS");
    assert.equal(receipt.gates.artisticHarvestApproval, "OPEN");
    const recorded = JSON.parse(await readFile(receiptPath, "utf8"));
    assert.deepEqual(receipt.inputs, recorded.inputs);
    assert.deepEqual(receipt.toolchain, recorded.toolchain);
    assert.deepEqual(receipt.outputs, recorded.outputs);
    const wavOutputs = receipt.outputs.filter(({ path: outputPath }) => outputPath.endsWith(".wav"));
    assert.equal(wavOutputs.length, 8);
    assert.equal(new Set(wavOutputs.map(({ sha256: digest }) => digest)).size, 8);
    for (const output of wavOutputs) {
      assert.deepEqual(inspectPCM24StereoWAV(await readFile(path.join(temporary, output.path))), output.format);
    }
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
});

test("audio evidence binds exact source, renderer, runtime, notice, receipt and cost bytes", async () => {
  const files = await fixtures();
  const result = await validateAudioProductionEvidence({
    files,
    costRegistryPath,
    receiptPath,
  });
  assert.equal(result.receiptSHA256, sha256(await readFile(receiptPath)));

  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-audio-evidence-"));
  try {
    const driftedCostPath = path.join(temporary, "cost-license.json");
    const costs = JSON.parse(await readFile(costRegistryPath, "utf8"));
    costs.entries.find(({ id }) => id === "audio-production-local").version = "fabricated";
    await writeFile(driftedCostPath, `${JSON.stringify(costs)}\n`);
    await assert.rejects(
      () => validateAudioProductionEvidence({ files, costRegistryPath: driftedCostPath, receiptPath }),
      /version\/hash binding drifted/,
    );

    const driftedReceiptPath = path.join(temporary, "receipt.json");
    const receipt = JSON.parse(await readFile(receiptPath, "utf8"));
    receipt.inputs[0].sha256 = "0".repeat(64);
    await writeFile(driftedReceiptPath, `${JSON.stringify(receipt)}\n`);
    await assert.rejects(
      () => validateAudioProductionEvidence({ files, costRegistryPath, receiptPath: driftedReceiptPath }),
      /no longer binds the exact production cause/,
    );
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
});

test("renderer preflight fails instead of skipping a missing production dependency", async () => {
  const { toolchain } = await fixtures();
  await assert.rejects(
    () => validateAudioRendererRuntime({
      toolchain,
      soundFontPath: "/definitely-missing/ms-basic.sf3",
      fluidSynthPath,
    }),
    /pinned FluidSynth binary and SoundFont are both required/,
  );
});
