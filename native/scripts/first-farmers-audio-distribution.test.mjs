import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import {
  candidatePathFor,
  encodeAndInspectAsset,
  loadSourceInventory,
  validateConfig,
} from "../audio/score-soundscape/distribution-coding-v1/build-first-farmers-candidate.mjs";

const repositoryConfig = JSON.parse(readFileSync(
  new URL("../audio/score-soundscape/distribution-coding-v1/config.json", import.meta.url),
  "utf8",
));

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function writePCM24StereoWAV(path, frames = 48000) {
  const channels = 2;
  const sampleRate = 48000;
  const bytesPerSample = 3;
  const dataBytes = frames * channels * bytesPerSample;
  const bytes = Buffer.alloc(44 + dataBytes);
  bytes.write("RIFF", 0, "ascii");
  bytes.writeUInt32LE(36 + dataBytes, 4);
  bytes.write("WAVEfmt ", 8, "ascii");
  bytes.writeUInt32LE(16, 16);
  bytes.writeUInt16LE(1, 20);
  bytes.writeUInt16LE(channels, 22);
  bytes.writeUInt32LE(sampleRate, 24);
  bytes.writeUInt32LE(sampleRate * channels * bytesPerSample, 28);
  bytes.writeUInt16LE(channels * bytesPerSample, 32);
  bytes.writeUInt16LE(24, 34);
  bytes.write("data", 36, "ascii");
  bytes.writeUInt32LE(dataBytes, 40);
  for (let frame = 0; frame < frames; frame += 1) {
    const normalized = frame === frames - 1 ? 0 : Math.sin(2 * Math.PI * 200 * frame / sampleRate) * 0.1;
    const sample = Math.round(normalized * 8388607);
    for (let channel = 0; channel < channels; channel += 1) {
      bytes.writeIntLE(sample, 44 + (frame * channels + channel) * bytesPerSample, bytesPerSample);
    }
  }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes);
  return bytes;
}

test("distribution config is fail-closed and Chapter 1-scoped", () => {
  assert.equal(validateConfig(structuredClone(repositoryConfig)).shippingState, "PROHIBITED");
  const promoted = structuredClone(repositoryConfig);
  promoted.shippingState = "APPROVED";
  assert.throws(() => validateConfig(promoted), /shipping must remain prohibited/);
  const integrated = structuredClone(repositoryConfig);
  integrated.approvalBoundary.runtimePathIntegration = "APPROVED";
  assert.throws(() => validateConfig(integrated), /runtime integration boundary drifted/);
});

test("candidate paths replace only Chapter 1 WAV leaves", () => {
  assert.equal(
    candidatePathFor("audio/first-farmers/example/waiting/score-master.wav"),
    "audio/first-farmers/example/waiting/score-master.m4a",
  );
  assert.throws(() => candidatePathFor("audio/first-farmers/example/master.m4a"), /must be WAV/);
  assert.throws(() => candidatePathFor("audio/other/example/master.wav"), /outside Chapter 1/);
  assert.throws(() => candidatePathFor("../audio/first-farmers/master.wav"), /escapes its root/);
});

test("source inventory requires exact receipt bytes, hashes and open approvals", () => {
  const root = mkdtempSync(join(tmpdir(), "eurocentric-audio-inventory-test-"));
  try {
    const workID = "test-responsive-v1";
    const sourceRelative = `native/audio/score-soundscape/cache/${workID}/waiting/score-master.wav`;
    const sourcePath = join(root, sourceRelative);
    const wav = writePCM24StereoWAV(sourcePath, 480);
    const receiptRelative = `native/audio/score-soundscape/${workID}/render-receipt.json`;
    const receiptPath = join(root, receiptRelative);
    mkdirSync(dirname(receiptPath), { recursive: true });
    const receipt = {
      id: "test-render",
      status: "PROVISIONAL_NON_SHIPPING",
      shippingState: "PROHIBITED",
      gates: { audioApproval: "OPEN", editorApproval: "OPEN", shippingApproval: "PROHIBITED" },
      outputs: [{
        regionID: "waiting",
        role: "score-master",
        sourceID: "test",
        path: "waiting/score-master.wav",
        packageAssetPath: `audio/first-farmers/${workID}/waiting/score-master.wav`,
        bytes: wav.length,
        sha256: sha256(wav),
        format: { sampleRate: 48000, bitDepth: 24, channels: 2, frames: 480 },
      }],
    };
    writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
    const config = structuredClone(repositoryConfig);
    config.sourceReceiptPaths = [receiptRelative, receiptRelative, receiptRelative, receiptRelative, receiptRelative, receiptRelative];
    assert.throws(() => loadSourceInventory(root, config), /duplicate responsive WAV source/);

    config.sourceReceiptPaths = [receiptRelative];
    config.expectedInventory = {
      responsiveWAVAssets: 1,
      preExistingResponsiveM4AAssets: 0,
      sourceBytes: wav.length,
      sourceFrames: 480,
      scheduledDecodedFloat32Bytes: 480 * 2 * 4,
    };
    const inventory = loadSourceInventory(root, config);
    assert.equal(inventory.assets.length, 1);
    writeFileSync(join(root, "native/audio/score-soundscape/cache/foreign.m4a"), "unexpected");
    assert.throws(() => loadSourceInventory(root, config), /pre-existing responsive M4A inventory count drifted/);
    rmSync(join(root, "native/audio/score-soundscape/cache/foreign.m4a"));
    receipt.outputs[0].sha256 = "0".repeat(64);
    writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
    assert.throws(() => loadSourceInventory(root, config), /source hash drifted/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("pinned AAC-LC coding is byte-repeatable and frame-bounded on a loop", () => {
  const root = mkdtempSync(join(tmpdir(), "eurocentric-audio-code-test-"));
  try {
    const sourcePath = join(root, "source.wav");
    writePCM24StereoWAV(sourcePath);
    const item = { sourceFrames: 48000, loopAsset: true };
    const firstPath = join(root, "first.m4a");
    const secondPath = join(root, "second.m4a");
    const first = encodeAndInspectAsset({ sourcePath, outputPath: firstPath, item, config: repositoryConfig });
    const second = encodeAndInspectAsset({ sourcePath, outputPath: secondPath, item, config: repositoryConfig });
    assert.equal(first.sha256, second.sha256);
    assert.equal(first.bytes, second.bytes);
    assert.equal(first.format.codec, "aac");
    assert.equal(first.format.profile, "LC");
    assert.equal(first.format.durationSamples, 48000);
    assert.ok(first.decoded.decoderTailPaddingFrames <= 1024);
    assert.ok(first.decoded.loopSeam.leftDelta <= 0.005);
    assert.ok(first.decoded.loopSeam.rightDelta <= 0.005);
    assert.ok(first.loudness.truePeakDBFS <= -1);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
