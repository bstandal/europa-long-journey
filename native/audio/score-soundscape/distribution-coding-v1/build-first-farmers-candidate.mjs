#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import {
  dirname,
  isAbsolute,
  join,
  posix,
  relative,
  resolve,
} from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const scriptPath = fileURLToPath(import.meta.url);
const scriptDirectory = dirname(scriptPath);
export const repositoryRoot = resolve(scriptDirectory, "../../../..");
export const defaultConfigPath = join(scriptDirectory, "config.json");
export const defaultOutputRoot = join(
  repositoryRoot,
  "native/audio/score-soundscape/distribution-cache/first-farmers-aac-lc-384-alac-fallback-v1",
);
export const defaultReceiptPath = join(scriptDirectory, "render-receipt.json");

function fail(message) {
  throw new Error(message);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
}

export function canonicalJSON(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function sha256Bytes(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function sha256File(path) {
  return sha256Bytes(readFileSync(path));
}

function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function assertSafeRelativePath(path, label) {
  requireCondition(typeof path === "string" && path.length > 0, `${label} must be a non-empty string`);
  requireCondition(!isAbsolute(path), `${label} must be relative`);
  requireCondition(path === posix.normalize(path), `${label} must be normalized POSIX text`);
  requireCondition(path !== ".." && !path.startsWith("../"), `${label} escapes its root`);
  requireCondition(!path.includes("\\"), `${label} must not contain backslashes`);
}

function resolveInside(root, relativePath, label) {
  assertSafeRelativePath(relativePath, label);
  const candidate = resolve(root, relativePath);
  const relation = relative(resolve(root), candidate);
  requireCondition(relation !== ".." && !relation.startsWith(`..${posix.sep}`) && !isAbsolute(relation), `${label} escapes its root`);
  return candidate;
}

export function candidatePathFor(sourcePackageAssetPath) {
  assertSafeRelativePath(sourcePackageAssetPath, "source package asset path");
  requireCondition(sourcePackageAssetPath.startsWith("audio/first-farmers/"), "source asset is outside Chapter 1");
  requireCondition(sourcePackageAssetPath.endsWith(".wav"), "source package asset must be WAV");
  return sourcePackageAssetPath.slice(0, -4) + ".m4a";
}

export function validateConfig(config) {
  requireCondition(config?.schemaVersion === 1, "distribution config schemaVersion must be 1");
  requireCondition(config.status === "PROVISIONAL_NON_SHIPPING", "distribution config must remain non-shipping");
  requireCondition(config.shippingState === "PROHIBITED", "distribution config shipping must remain prohibited");
  requireCondition(config.trustDomain === "BACKSTAGE_AUDIO_DISTRIBUTION_PROBE", "distribution trust domain drifted");
  requireCondition(config.chapterID === "first-farmers", "distribution config must stay scoped to Chapter 1");
  requireCondition(config.candidateFormat?.container === "m4a", "candidate container must be m4a");
  requireCondition(config.candidateFormat?.codec === "aac", "candidate codec must be AAC");
  requireCondition(config.candidateFormat?.profile === "LC", "candidate AAC profile must be LC");
  requireCondition(config.candidateFormat?.encoder === "ffmpeg-native-aac", "candidate encoder drifted");
  requireCondition(config.candidateFormat?.bitRate === 384000, "candidate bitrate drifted");
  requireCondition(config.candidateFormat?.sampleRate === 48000, "candidate sample rate drifted");
  requireCondition(config.candidateFormat?.channels === 2, "candidate channel count drifted");
  requireCondition(config.candidateFormat?.losslessFallback?.codec === "alac", "lossless fallback codec drifted");
  requireCondition(config.candidateFormat?.losslessFallback?.encoder === "ffmpeg-native-alac", "lossless fallback encoder drifted");
  requireCondition(config.candidateFormat?.losslessFallback?.sampleFormat === "s32p", "lossless fallback sample format drifted");
  requireCondition(config.candidateFormat?.losslessFallback?.requireDecodedPCMIdentityWithSource === true, "lossless fallback must preserve decoded source PCM");
  requireCondition(config.sourceFormat?.sampleRate === 48000, "source sample rate drifted");
  requireCondition(config.sourceFormat?.bitDepth === 24, "source bit depth drifted");
  requireCondition(config.sourceFormat?.channels === 2, "source channel count drifted");
  requireCondition(config.approvalBoundary?.audioApproval === "OPEN", "audio approval may not be inferred");
  requireCondition(config.approvalBoundary?.editorApproval === "OPEN", "editor approval may not be inferred");
  requireCondition(config.approvalBoundary?.physicalIPhonePlayback === "OPEN", "physical playback must remain open");
  requireCondition(config.approvalBoundary?.physicalIPhoneEnergy === "OPEN", "physical energy validation must remain open");
  requireCondition(config.approvalBoundary?.runtimePathIntegration === "NOT_AUTHORIZED_BY_THIS_CANDIDATE", "runtime integration boundary drifted");
  requireCondition(config.approvalBoundary?.shippingApproval === "PROHIBITED", "shipping approval may not be inferred");
  requireCondition(Array.isArray(config.sourceReceiptPaths) && config.sourceReceiptPaths.length === 6, "exactly six responsive render receipts are required");
  for (const receiptPath of config.sourceReceiptPaths) assertSafeRelativePath(receiptPath, "source receipt path");
  assertSafeRelativePath(config.sourceCacheRoot, "source cache root");
  return config;
}

function run(binary, args, { binaryOutput = false, maxBuffer = 64 * 1024 * 1024 } = {}) {
  const result = spawnSync(binary, args, {
    encoding: binaryOutput ? null : "utf8",
    maxBuffer,
  });
  requireCondition(result.error == null, `${binary} could not start: ${result.error?.message ?? "unknown error"}`);
  const stderr = binaryOutput ? result.stderr?.toString("utf8") : result.stderr;
  requireCondition(result.status === 0, `${binary} failed (${result.status}): ${(stderr ?? "").trim()}`);
  return result;
}

export function verifyToolchain(config) {
  const { toolchain } = config;
  requireCondition(existsSync(toolchain.ffmpegPath), "pinned ffmpeg is missing");
  requireCondition(existsSync(toolchain.ffprobePath), "pinned ffprobe is missing");
  requireCondition(sha256File(toolchain.ffmpegPath) === toolchain.ffmpegSHA256, "ffmpeg binary hash drifted");
  requireCondition(sha256File(toolchain.ffprobePath) === toolchain.ffprobeSHA256, "ffprobe binary hash drifted");
  const ffmpegVersion = run(toolchain.ffmpegPath, ["-version"]).stdout;
  const ffprobeVersion = run(toolchain.ffprobePath, ["-version"]).stdout;
  requireCondition(ffmpegVersion.includes(`ffmpeg version ${toolchain.ffmpegVersion}`), "ffmpeg version drifted");
  requireCondition(ffprobeVersion.includes(`ffprobe version ${toolchain.ffprobeVersion}`), "ffprobe version drifted");
  return {
    ffmpeg: {
      path: toolchain.ffmpegPath,
      version: toolchain.ffmpegVersion,
      sha256: toolchain.ffmpegSHA256,
    },
    ffprobe: {
      path: toolchain.ffprobePath,
      version: toolchain.ffprobeVersion,
      sha256: toolchain.ffprobeSHA256,
    },
  };
}

function isLoopAsset(item) {
  return ["waiting", "engaged", "resistance", "interaction-material-loop"].includes(item.regionID);
}

export function loadSourceInventory(projectRoot, config) {
  const cacheRoot = resolveInside(projectRoot, config.sourceCacheRoot, "source cache root");
  const preExistingResponsiveM4AAssets = readdirSync(cacheRoot, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".m4a"))
    .length;
  requireCondition(
    preExistingResponsiveM4AAssets === config.expectedInventory.preExistingResponsiveM4AAssets,
    "pre-existing responsive M4A inventory count drifted",
  );
  const seenSources = new Set();
  const seenCandidates = new Set();
  const receiptInputs = [];
  const assets = [];

  for (const receiptRelativePath of config.sourceReceiptPaths) {
    const receiptPath = resolveInside(projectRoot, receiptRelativePath, "source receipt path");
    const receipt = readJSON(receiptPath);
    requireCondition(receipt.status === "PROVISIONAL_NON_SHIPPING", `${receiptRelativePath} status may not claim approval`);
    requireCondition(receipt.shippingState === "PROHIBITED", `${receiptRelativePath} shipping must remain prohibited`);
    requireCondition(receipt.gates?.shippingApproval === "PROHIBITED", `${receiptRelativePath} shipping gate drifted`);
    requireCondition(receipt.gates?.audioApproval === "OPEN" || receipt.gates?.artisticApproval === "OPEN", `${receiptRelativePath} audio approval must remain open`);
    requireCondition(receipt.gates?.editorApproval === "OPEN", `${receiptRelativePath} editor approval must remain open`);
    requireCondition(Array.isArray(receipt.outputs), `${receiptRelativePath} outputs are missing`);

    const workID = posix.basename(posix.dirname(receiptRelativePath));
    const receiptBytes = statSync(receiptPath).size;
    receiptInputs.push({
      id: receipt.id,
      path: receiptRelativePath,
      bytes: receiptBytes,
      sha256: sha256File(receiptPath),
      status: receipt.status,
      shippingState: receipt.shippingState,
    });

    for (const output of receipt.outputs.filter((candidate) => candidate.packageAssetPath != null)) {
      requireCondition(typeof output.path === "string" && output.path.endsWith(".wav"), `${receiptRelativePath}: package source must be WAV`);
      assertSafeRelativePath(output.path, `${receiptRelativePath}: output path`);
      const candidateRelativePath = candidatePathFor(output.packageAssetPath);
      const sourceRelativePath = posix.join(config.sourceCacheRoot, workID, output.path);
      const sourcePath = resolveInside(projectRoot, sourceRelativePath, "responsive WAV source");
      requireCondition(existsSync(sourcePath), `responsive WAV source is missing: ${sourceRelativePath}`);
      requireCondition(!seenSources.has(sourceRelativePath), `duplicate responsive WAV source: ${sourceRelativePath}`);
      requireCondition(!seenCandidates.has(candidateRelativePath), `duplicate candidate M4A path: ${candidateRelativePath}`);
      seenSources.add(sourceRelativePath);
      seenCandidates.add(candidateRelativePath);

      const actualBytes = statSync(sourcePath).size;
      const actualSHA256 = sha256File(sourcePath);
      requireCondition(actualBytes === output.bytes, `source byte count drifted: ${sourceRelativePath}`);
      requireCondition(actualSHA256 === output.sha256, `source hash drifted: ${sourceRelativePath}`);
      requireCondition(output.format?.sampleRate === config.sourceFormat.sampleRate, `source sample rate drifted: ${sourceRelativePath}`);
      requireCondition(output.format?.bitDepth === config.sourceFormat.bitDepth, `source bit depth drifted: ${sourceRelativePath}`);
      requireCondition(output.format?.channels === config.sourceFormat.channels, `source channels drifted: ${sourceRelativePath}`);
      requireCondition(Number.isSafeInteger(output.format?.frames) && output.format.frames > 0, `source frame count is invalid: ${sourceRelativePath}`);

      assets.push({
        workID,
        regionID: output.regionID,
        role: output.role,
        sourceID: output.sourceID,
        sourceReceiptPath: receiptRelativePath,
        sourceRelativePath,
        sourcePackageAssetPath: output.packageAssetPath,
        candidateRelativePath,
        sourceBytes: output.bytes,
        sourceSHA256: output.sha256,
        sourceFrames: output.format.frames,
        sourceSampleRate: output.format.sampleRate,
        sourceBitDepth: output.format.bitDepth,
        sourceChannels: output.format.channels,
        loopAsset: isLoopAsset(output),
      });
    }
  }

  assets.sort((left, right) => left.candidateRelativePath.localeCompare(right.candidateRelativePath));
  const totals = assets.reduce((sum, asset) => ({
    assets: sum.assets + 1,
    bytes: sum.bytes + asset.sourceBytes,
    frames: sum.frames + asset.sourceFrames,
    scheduledDecodedFloat32Bytes: sum.scheduledDecodedFloat32Bytes + asset.sourceFrames * asset.sourceChannels * 4,
  }), { assets: 0, bytes: 0, frames: 0, scheduledDecodedFloat32Bytes: 0 });

  requireCondition(totals.assets === config.expectedInventory.responsiveWAVAssets, "responsive WAV inventory count drifted");
  requireCondition(totals.bytes === config.expectedInventory.sourceBytes, "responsive WAV byte total drifted");
  requireCondition(totals.frames === config.expectedInventory.sourceFrames, "responsive WAV frame total drifted");
  requireCondition(totals.scheduledDecodedFloat32Bytes === config.expectedInventory.scheduledDecodedFloat32Bytes, "decoded PCM inventory total drifted");
  return { receiptInputs, assets, totals, preExistingResponsiveM4AAssets };
}

function probeM4A(path, config, expectedFrames, expectedCodec = config.candidateFormat.codec) {
  const result = run(config.toolchain.ffprobePath, [
    "-v", "error",
    "-select_streams", "a:0",
    "-show_entries", "stream=codec_name,profile,sample_fmt,sample_rate,channels,channel_layout,duration_ts,time_base,bit_rate,nb_frames:format=duration,size,bit_rate",
    "-of", "json",
    path,
  ]);
  const probe = JSON.parse(result.stdout);
  requireCondition(Array.isArray(probe.streams) && probe.streams.length === 1, "candidate must contain exactly one audio stream");
  const stream = probe.streams[0];
  requireCondition(stream.codec_name === expectedCodec, "candidate codec drifted");
  if (expectedCodec === "aac") requireCondition(stream.profile === config.candidateFormat.profile, "candidate profile drifted");
  requireCondition(Number(stream.sample_rate) === config.candidateFormat.sampleRate, "candidate sample rate drifted");
  requireCondition(Number(stream.channels) === config.candidateFormat.channels, "candidate channel count drifted");
  requireCondition(stream.channel_layout === "stereo", "candidate channel layout drifted");
  requireCondition(stream.time_base === "1/48000", "candidate time base drifted");
  requireCondition(Number(stream.duration_ts) === expectedFrames, "candidate container duration is not source-frame exact");
  return {
    codec: stream.codec_name,
    profile: stream.profile ?? null,
    sampleFormat: stream.sample_fmt,
    sampleRate: Number(stream.sample_rate),
    channels: Number(stream.channels),
    channelLayout: stream.channel_layout,
    timeBase: stream.time_base,
    durationSamples: Number(stream.duration_ts),
    encodedBitRate: Number(stream.bit_rate),
    packetCount: Number(stream.nb_frames),
  };
}

function decodedMetrics(path, config, scheduledFrames, loopAsset, enforceLoopSeam = true) {
  const result = run(config.toolchain.ffmpegPath, [
    "-hide_banner", "-loglevel", "error", "-nostdin",
    "-i", path,
    "-map", "0:a:0",
    "-f", "f32le",
    "-acodec", "pcm_f32le",
    "-ar", String(config.candidateFormat.sampleRate),
    "-ac", String(config.candidateFormat.channels),
    "-",
  ], { binaryOutput: true });
  const decoded = result.stdout;
  const bytesPerFrame = config.candidateFormat.channels * 4;
  requireCondition(decoded.byteLength % bytesPerFrame === 0, "decoded PCM byte count is not frame-aligned");
  const emittedFrames = decoded.byteLength / bytesPerFrame;
  requireCondition(emittedFrames >= scheduledFrames, "AAC decoder emitted fewer frames than the source timeline requires");
  const tailPaddingFrames = emittedFrames - scheduledFrames;
  requireCondition(tailPaddingFrames <= config.candidateFormat.maximumDecoderTailPaddingFrames, "AAC decoder tail padding exceeded the locked bound");

  let loopSeam = null;
  if (loopAsset) {
    const lastFrameOffset = (scheduledFrames - 1) * bytesPerFrame;
    const leftDelta = Math.abs(decoded.readFloatLE(0) - decoded.readFloatLE(lastFrameOffset));
    const rightDelta = Math.abs(decoded.readFloatLE(4) - decoded.readFloatLE(lastFrameOffset + 4));
    if (enforceLoopSeam) {
      requireCondition(leftDelta <= config.candidateFormat.maximumLoopSeamDelta, "decoded left loop seam exceeded the locked bound");
      requireCondition(rightDelta <= config.candidateFormat.maximumLoopSeamDelta, "decoded right loop seam exceeded the locked bound");
    }
    loopSeam = { leftDelta, rightDelta, maximumAllowed: config.candidateFormat.maximumLoopSeamDelta };
  }

  return {
    scheduledFrames,
    scheduledFloat32Bytes: scheduledFrames * bytesPerFrame,
    decoderEmittedFrames: emittedFrames,
    decoderEmittedFloat32Bytes: decoded.byteLength,
    decoderTailPaddingFrames: tailPaddingFrames,
    decoderOutputSHA256: sha256Bytes(decoded),
    ...(loopSeam ? { loopSeam } : {}),
  };
}

function parseEBUR128(stderr) {
  const integrated = [...stderr.matchAll(/\bI:\s+(-?(?:\d+(?:\.\d+)?|inf))\s+LUFS/g)];
  const peak = [...stderr.matchAll(/\bPeak:\s+(-?(?:\d+(?:\.\d+)?|inf))\s+dBFS/g)];
  requireCondition(integrated.length > 0 && peak.length > 0, "ffmpeg ebur128 summary could not be parsed");
  const decode = (value) => value === "-inf" ? null : Number(value);
  return {
    integratedLUFS: decode(integrated.at(-1)[1]),
    truePeakDBFS: decode(peak.at(-1)[1]),
  };
}

function loudnessMetrics(path, config) {
  const result = run(config.toolchain.ffmpegPath, [
    "-hide_banner", "-nostdin",
    "-i", path,
    "-filter_complex", "ebur128=peak=true",
    "-f", "null", "-",
  ]);
  return parseEBUR128(result.stderr);
}

function encode(path, outputPath, config, codec = "aac") {
  mkdirSync(dirname(outputPath), { recursive: true });
  const codecArguments = codec === "alac"
    ? ["-c:a", "alac", "-sample_fmt", config.candidateFormat.losslessFallback.sampleFormat]
    : ["-c:a", "aac", "-profile:a", "aac_low", "-b:a", String(config.candidateFormat.bitRate)];
  run(config.toolchain.ffmpegPath, [
    "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
    "-i", path,
    "-map", "0:a:0",
    "-map_metadata", "-1",
    "-map_chapters", "-1",
    "-vn", "-sn", "-dn",
    ...codecArguments,
    "-ar", String(config.candidateFormat.sampleRate),
    "-ac", String(config.candidateFormat.channels),
    "-movflags", "+faststart",
    outputPath,
  ]);
}

export function encodeAndInspectAsset({ sourcePath, outputPath, item, config }) {
  encode(sourcePath, outputPath, config, "aac");
  const primary = {
    bytes: statSync(outputPath).size,
    sha256: sha256File(outputPath),
    format: probeM4A(outputPath, config, item.sourceFrames, "aac"),
    decoded: decodedMetrics(outputPath, config, item.sourceFrames, item.loopAsset, false),
    loudness: loudnessMetrics(outputPath, config),
  };
  const seamRejected = item.loopAsset && (
    primary.decoded.loopSeam.leftDelta > config.candidateFormat.maximumLoopSeamDelta
    || primary.decoded.loopSeam.rightDelta > config.candidateFormat.maximumLoopSeamDelta
  );
  const peakRejected = primary.loudness.truePeakDBFS != null
    && primary.loudness.truePeakDBFS > config.candidateFormat.maximumTruePeakDBFS;
  if (!seamRejected && !peakRejected) {
    return { ...primary, codingDecision: "AAC_LC_384_PRIMARY_ACCEPTED" };
  }

  const rejectionReasons = [
    ...(seamRejected ? ["AAC_LOOP_SEAM_EXCEEDS_SOURCE_GATE"] : []),
    ...(peakRejected ? ["AAC_TRUE_PEAK_EXCEEDS_SOURCE_GATE"] : []),
  ];
  for (const reason of rejectionReasons) {
    requireCondition(config.candidateFormat.losslessFallback.reasons.includes(reason), `unauthorized lossless fallback reason: ${reason}`);
  }
  encode(sourcePath, outputPath, config, "alac");
  const fallback = {
    bytes: statSync(outputPath).size,
    sha256: sha256File(outputPath),
    format: probeM4A(outputPath, config, item.sourceFrames, "alac"),
    decoded: decodedMetrics(outputPath, config, item.sourceFrames, item.loopAsset, true),
    loudness: loudnessMetrics(outputPath, config),
  };
  requireCondition(fallback.loudness.truePeakDBFS == null || fallback.loudness.truePeakDBFS <= config.candidateFormat.maximumTruePeakDBFS, "lossless fallback exceeds the true-peak ceiling");
  const sourceDecoded = decodedMetrics(sourcePath, config, item.sourceFrames, item.loopAsset, true);
  requireCondition(fallback.decoded.decoderEmittedFrames === item.sourceFrames, "lossless fallback emitted a padded decode range");
  requireCondition(fallback.decoded.decoderOutputSHA256 === sourceDecoded.decoderOutputSHA256, "lossless fallback decoded PCM differs from the source master");
  return {
    ...fallback,
    codingDecision: "ALAC_FALLBACK_AFTER_AAC_GATE_REJECTION",
    rejectedPrimary: {
      codec: "aac",
      profile: "LC",
      targetBitRate: config.candidateFormat.bitRate,
      bytes: primary.bytes,
      sha256: primary.sha256,
      reasons: rejectionReasons,
      decoded: primary.decoded,
      loudness: primary.loudness,
    },
  };
}

function buildReceipt({ config, configPath, toolchain, inventory, outputs }) {
  const encodedBytes = outputs.reduce((sum, output) => sum + output.bytes, 0);
  const decoderEmittedFloat32Bytes = outputs.reduce((sum, output) => sum + output.decoded.decoderEmittedFloat32Bytes, 0);
  const maximumSingleAssetScheduledFloat32Bytes = Math.max(...outputs.map((output) => output.decoded.scheduledFloat32Bytes));
  const maximumSingleAssetDecoderEmittedFloat32Bytes = Math.max(...outputs.map((output) => output.decoded.decoderEmittedFloat32Bytes));
  const savingsBytes = inventory.totals.bytes - encodedBytes;
  return {
    schemaVersion: 1,
    id: "first-farmers-responsive-aac-lc-384-alac-fallback-render-v1",
    status: "PROVISIONAL_NON_SHIPPING",
    shippingState: "PROHIBITED",
    trustDomain: "BACKSTAGE_AUDIO_DISTRIBUTION_PROBE",
    scope: { chapterID: config.chapterID, contents: "responsive score, soundscape and spatial-detail candidates only" },
    config: {
      path: relative(repositoryRoot, configPath).split("\\").join("/"),
      bytes: statSync(configPath).size,
      sha256: sha256File(configPath),
    },
    builder: {
      path: relative(repositoryRoot, scriptPath).split("\\").join("/"),
      bytes: statSync(scriptPath).size,
      sha256: sha256File(scriptPath),
    },
    sourceReceipts: inventory.receiptInputs,
    toolchain,
    coding: {
      container: config.candidateFormat.container,
      codec: config.candidateFormat.codec,
      profile: config.candidateFormat.profile,
      encoder: config.candidateFormat.encoder,
      targetBitRate: config.candidateFormat.bitRate,
      sampleRate: config.candidateFormat.sampleRate,
      channels: config.candidateFormat.channels,
      ffmpegArguments: [
        "-map 0:a:0",
        "-map_metadata -1",
        "-map_chapters -1",
        "-vn -sn -dn",
        "-c:a aac",
        "-profile:a aac_low",
        `-b:a ${config.candidateFormat.bitRate}`,
        `-ar ${config.candidateFormat.sampleRate}`,
        `-ac ${config.candidateFormat.channels}`,
        "-movflags +faststart",
      ],
      losslessFallback: {
        codec: config.candidateFormat.losslessFallback.codec,
        encoder: config.candidateFormat.losslessFallback.encoder,
        sampleFormat: config.candidateFormat.losslessFallback.sampleFormat,
        reasons: config.candidateFormat.losslessFallback.reasons,
        decodedPCMIdentityRequired: config.candidateFormat.losslessFallback.requireDecodedPCMIdentityWithSource,
      },
    },
    inventory: {
      sourceResponsiveWAVAssets: inventory.totals.assets,
      preExistingResponsiveM4AAssets: inventory.preExistingResponsiveM4AAssets,
      candidateM4AAssets: outputs.length,
      aacLCAssets: outputs.filter((output) => output.format.codec === "aac").length,
      alacFallbackAssets: outputs.filter((output) => output.format.codec === "alac").length,
      sourcePCMBytes: inventory.totals.bytes,
      candidateEncodedBytes: encodedBytes,
      savedBytes: savingsBytes,
      encodedFractionOfSource: Number((encodedBytes / inventory.totals.bytes).toFixed(9)),
      storageReductionFraction: Number((savingsBytes / inventory.totals.bytes).toFixed(9)),
      sourceFrames: inventory.totals.frames,
      durationSeconds: inventory.totals.frames / config.candidateFormat.sampleRate,
    },
    decodedPCM: {
      scheduledFloat32BytesAcrossAllAssets: inventory.totals.scheduledDecodedFloat32Bytes,
      decoderEmittedFloat32BytesAcrossAllAssets: decoderEmittedFloat32Bytes,
      maximumSingleAssetScheduledFloat32Bytes,
      maximumSingleAssetDecoderEmittedFloat32Bytes,
      distributionEncodingDoesNotReduceDecodedWorkingSet: true,
      allAssetsAreNotExpectedToBeResidentTogether: true,
      runtimeConcurrentMemoryGateIsSeparate: true,
      physicalIPhoneMeasurement: "OPEN",
    },
    outputs,
    gates: {
      sourceReceiptBoundary: "PASS_ALL_SOURCES_PROVISIONAL_AND_SHIPPING_PROHIBITED",
      sourceBytesAndHashes: `PASS_${inventory.totals.assets}_EXACT_WAV_INPUTS`,
      sourcePCMFormat: "PASS_48000_HZ_24_BIT_STEREO",
      codecSelection: `PASS_${outputs.filter((output) => output.format.codec === "aac").length}_AAC_PRIMARY_${outputs.filter((output) => output.format.codec === "alac").length}_LOSSLESS_GATE_FALLBACK`,
      candidateContainerDuration: `PASS_${outputs.length}_SOURCE_FRAME_EXACT_M4A_CONTAINERS`,
      decodedAvailability: `PASS_${outputs.length}_FULL_SCHEDULED_FRAME_RANGES_WITH_BOUNDED_TAIL_PADDING`,
      decodedLoopSeams: "PASS_ALL_RESPONSIVE_LOOP_ASSETS_AT_OR_BELOW_0_005",
      encodedTruePeak: "PASS_ALL_SELECTED_CANDIDATES_AT_OR_BELOW_MINUS_1_DBFS",
      deterministicReplay: `PASS_${outputs.length}_BYTE_IDENTICAL_SECOND_ENCODINGS`,
      offlineAvailability: "CANDIDATE_FILES_ARE_LOCAL_AND_SELF_CONTAINED",
      audioApproval: "OPEN",
      editorApproval: "OPEN",
      physicalIPhonePlayback: "OPEN",
      physicalIPhoneEnergy: "OPEN",
      runtimePathIntegration: "NOT_AUTHORIZED_BY_THIS_CANDIDATE",
      narration: "OUT_OF_SCOPE_NOT_INCLUDED",
      shippingApproval: "PROHIBITED",
    },
  };
}

function assertEmptyDestination(path) {
  requireCondition(!existsSync(path), `destination already exists; use a new empty path: ${path}`);
}

export function buildCandidate({ projectRoot, configPath, outputRoot, receiptPath }) {
  const config = validateConfig(readJSON(configPath));
  const toolchain = verifyToolchain(config);
  const inventory = loadSourceInventory(projectRoot, config);
  assertEmptyDestination(outputRoot);
  mkdirSync(outputRoot, { recursive: true });
  const replayRoot = mkdtempSync(join(tmpdir(), "eurocentric-first-farmers-aac-replay-"));
  const outputs = [];

  try {
    for (const [index, item] of inventory.assets.entries()) {
      const sourcePath = resolveInside(projectRoot, item.sourceRelativePath, "responsive WAV source");
      const candidatePath = resolveInside(outputRoot, item.candidateRelativePath, "candidate M4A path");
      const replayPath = resolveInside(replayRoot, item.candidateRelativePath, "replay M4A path");
      const result = encodeAndInspectAsset({ sourcePath, outputPath: candidatePath, item, config });
      encode(sourcePath, replayPath, config, result.format.codec);
      const replayBytes = statSync(replayPath).size;
      const replaySHA256 = sha256File(replayPath);
      requireCondition(replayBytes === result.bytes && replaySHA256 === result.sha256, `second encode was not byte-identical: ${item.candidateRelativePath}`);

      outputs.push({
        workID: item.workID,
        regionID: item.regionID,
        role: item.role,
        sourceID: item.sourceID,
        sourceReceiptPath: item.sourceReceiptPath,
        sourceRelativePath: item.sourceRelativePath,
        sourcePackageAssetPath: item.sourcePackageAssetPath,
        candidateRelativePath: item.candidateRelativePath,
        status: "PROVISIONAL_NON_SHIPPING",
        shippingState: "PROHIBITED",
        source: {
          bytes: item.sourceBytes,
          sha256: item.sourceSHA256,
          frames: item.sourceFrames,
          sampleRate: item.sourceSampleRate,
          bitDepth: item.sourceBitDepth,
          channels: item.sourceChannels,
        },
        bytes: result.bytes,
        sha256: result.sha256,
        format: result.format,
        codingDecision: result.codingDecision,
        ...(result.rejectedPrimary ? { rejectedPrimary: result.rejectedPrimary } : {}),
        decoded: result.decoded,
        loudness: result.loudness,
        deterministicReplay: { bytes: replayBytes, sha256: replaySHA256, byteIdentical: true },
      });
      process.stdout.write(`[${index + 1}/${inventory.assets.length}] ${item.candidateRelativePath}\n`);
    }
  } catch (error) {
    rmSync(outputRoot, { recursive: true, force: true });
    throw error;
  } finally {
    rmSync(replayRoot, { recursive: true, force: true });
  }

  const receipt = buildReceipt({ config, configPath, toolchain, inventory, outputs });
  mkdirSync(dirname(receiptPath), { recursive: true });
  const temporaryReceiptPath = `${receiptPath}.partial`;
  writeFileSync(temporaryReceiptPath, canonicalJSON(receipt));
  renameSync(temporaryReceiptPath, receiptPath);
  writeFileSync(`${receiptPath}.sha256`, `${sha256File(receiptPath)}  ${posix.basename(receiptPath)}\n`);
  return receipt;
}

export function verifyCandidate({ projectRoot, configPath, outputRoot, receiptPath }) {
  const config = validateConfig(readJSON(configPath));
  verifyToolchain(config);
  const inventory = loadSourceInventory(projectRoot, config);
  const receipt = readJSON(receiptPath);
  requireCondition(receipt.status === "PROVISIONAL_NON_SHIPPING", "candidate receipt must remain non-shipping");
  requireCondition(receipt.shippingState === "PROHIBITED", "candidate receipt shipping must remain prohibited");
  requireCondition(receipt.gates?.audioApproval === "OPEN", "candidate receipt may not infer audio approval");
  requireCondition(receipt.gates?.editorApproval === "OPEN", "candidate receipt may not infer editor approval");
  requireCondition(receipt.gates?.shippingApproval === "PROHIBITED", "candidate receipt may not infer shipping approval");
  requireCondition(receipt.config?.sha256 === sha256File(configPath), "candidate config hash drifted");
  requireCondition(receipt.builder?.path === relative(repositoryRoot, scriptPath).split("\\").join("/"), "candidate builder path drifted");
  requireCondition(receipt.builder?.bytes === statSync(scriptPath).size, "candidate builder byte count drifted");
  requireCondition(receipt.builder?.sha256 === sha256File(scriptPath), "candidate builder hash drifted");
  requireCondition(Array.isArray(receipt.outputs) && receipt.outputs.length === inventory.assets.length, "candidate receipt output count drifted");

  const inventoryByCandidatePath = new Map(inventory.assets.map((asset) => [asset.candidateRelativePath, asset]));
  let encodedBytes = 0;
  for (const output of receipt.outputs) {
    requireCondition(output.status === "PROVISIONAL_NON_SHIPPING" && output.shippingState === "PROHIBITED", `candidate approval boundary drifted: ${output.candidateRelativePath}`);
    const source = inventoryByCandidatePath.get(output.candidateRelativePath);
    requireCondition(source != null, `candidate is not present in the source inventory: ${output.candidateRelativePath}`);
    requireCondition(output.sourceRelativePath === source.sourceRelativePath, `candidate source path drifted: ${output.candidateRelativePath}`);
    requireCondition(output.source?.bytes === source.sourceBytes, `candidate source bytes drifted: ${output.candidateRelativePath}`);
    requireCondition(output.source?.sha256 === source.sourceSHA256, `candidate source hash drifted: ${output.candidateRelativePath}`);
    requireCondition(output.source?.frames === source.sourceFrames, `candidate source frames drifted: ${output.candidateRelativePath}`);
    requireCondition(output.decoded?.scheduledFrames === source.sourceFrames, `candidate decoded schedule drifted: ${output.candidateRelativePath}`);
    requireCondition(output.decoded?.decoderEmittedFrames >= source.sourceFrames, `candidate decoded range is short: ${output.candidateRelativePath}`);
    requireCondition(output.decoded?.decoderTailPaddingFrames <= config.candidateFormat.maximumDecoderTailPaddingFrames, `candidate decoder padding drifted: ${output.candidateRelativePath}`);
    if (source.loopAsset) {
      requireCondition(output.decoded?.loopSeam?.leftDelta <= config.candidateFormat.maximumLoopSeamDelta, `candidate left seam drifted: ${output.candidateRelativePath}`);
      requireCondition(output.decoded?.loopSeam?.rightDelta <= config.candidateFormat.maximumLoopSeamDelta, `candidate right seam drifted: ${output.candidateRelativePath}`);
    }
    requireCondition(output.loudness?.truePeakDBFS == null || output.loudness.truePeakDBFS <= config.candidateFormat.maximumTruePeakDBFS, `candidate true peak drifted: ${output.candidateRelativePath}`);
    requireCondition(output.format?.codec === "aac" || output.format?.codec === "alac", `candidate codec is not authorized: ${output.candidateRelativePath}`);
    if (output.format.codec === "aac") {
      requireCondition(output.codingDecision === "AAC_LC_384_PRIMARY_ACCEPTED", `AAC coding decision drifted: ${output.candidateRelativePath}`);
      requireCondition(output.rejectedPrimary == null, `accepted AAC candidate contains rejected-primary evidence: ${output.candidateRelativePath}`);
    } else {
      requireCondition(output.codingDecision === "ALAC_FALLBACK_AFTER_AAC_GATE_REJECTION", `ALAC coding decision drifted: ${output.candidateRelativePath}`);
      requireCondition(Array.isArray(output.rejectedPrimary?.reasons) && output.rejectedPrimary.reasons.length > 0, `ALAC fallback lacks a rejected AAC reason: ${output.candidateRelativePath}`);
      for (const reason of output.rejectedPrimary.reasons) {
        requireCondition(config.candidateFormat.losslessFallback.reasons.includes(reason), `ALAC fallback reason drifted: ${output.candidateRelativePath}`);
      }
      requireCondition(output.decoded.decoderEmittedFrames === source.sourceFrames, `ALAC fallback must not contain decoder padding: ${output.candidateRelativePath}`);
    }
    const candidatePath = resolveInside(outputRoot, output.candidateRelativePath, "candidate M4A path");
    requireCondition(existsSync(candidatePath), `candidate M4A is missing: ${output.candidateRelativePath}`);
    requireCondition(statSync(candidatePath).size === output.bytes, `candidate byte count drifted: ${output.candidateRelativePath}`);
    requireCondition(sha256File(candidatePath) === output.sha256, `candidate hash drifted: ${output.candidateRelativePath}`);
    probeM4A(candidatePath, config, output.source.frames, output.format.codec);
    encodedBytes += output.bytes;
  }
  requireCondition(encodedBytes === receipt.inventory.candidateEncodedBytes, "candidate encoded byte total drifted");
  requireCondition(sha256File(receiptPath) === readFileSync(`${receiptPath}.sha256`, "utf8").trim().split(/\s+/)[0], "candidate receipt hash drifted");
  return {
    status: receipt.status,
    shippingState: receipt.shippingState,
    assets: receipt.outputs.length,
    sourceBytes: receipt.inventory.sourcePCMBytes,
    encodedBytes,
    savedBytes: receipt.inventory.savedBytes,
  };
}

function parseArguments(argv) {
  const options = {
    command: "build",
    configPath: defaultConfigPath,
    outputRoot: defaultOutputRoot,
    receiptPath: defaultReceiptPath,
  };
  const args = [...argv];
  if (args[0] === "build" || args[0] === "verify" || args[0] === "inventory") options.command = args.shift();
  while (args.length > 0) {
    const key = args.shift();
    const value = args.shift();
    requireCondition(value != null, `missing value for ${key}`);
    if (key === "--config") options.configPath = resolve(value);
    else if (key === "--output") options.outputRoot = resolve(value);
    else if (key === "--receipt") options.receiptPath = resolve(value);
    else fail(`unknown argument: ${key}`);
  }
  return options;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.command === "inventory") {
    const config = validateConfig(readJSON(options.configPath));
    verifyToolchain(config);
    const inventory = loadSourceInventory(repositoryRoot, config);
    process.stdout.write(canonicalJSON({
      status: config.status,
      shippingState: config.shippingState,
      responsiveWAVAssets: inventory.totals.assets,
      preExistingResponsiveM4AAssets: inventory.preExistingResponsiveM4AAssets,
      sourceBytes: inventory.totals.bytes,
      sourceFrames: inventory.totals.frames,
      scheduledDecodedFloat32Bytes: inventory.totals.scheduledDecodedFloat32Bytes,
    }));
    return;
  }
  if (options.command === "verify") {
    process.stdout.write(canonicalJSON(verifyCandidate({
      projectRoot: repositoryRoot,
      configPath: options.configPath,
      outputRoot: options.outputRoot,
      receiptPath: options.receiptPath,
    })));
    return;
  }
  const receipt = buildCandidate({
    projectRoot: repositoryRoot,
    configPath: options.configPath,
    outputRoot: options.outputRoot,
    receiptPath: options.receiptPath,
  });
  process.stdout.write(canonicalJSON({
    status: receipt.status,
    shippingState: receipt.shippingState,
    assets: receipt.outputs.length,
    sourceBytes: receipt.inventory.sourcePCMBytes,
    encodedBytes: receipt.inventory.candidateEncodedBytes,
    savedBytes: receipt.inventory.savedBytes,
    storageReductionFraction: receipt.inventory.storageReductionFraction,
  }));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
