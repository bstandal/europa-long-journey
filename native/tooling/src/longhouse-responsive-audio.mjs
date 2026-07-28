import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  AudioProductionError,
  compileScoreStemMIDI,
  encodePCM24StereoWAV,
  inspectPCM24StereoWAV,
  renderProceduralSoundscapeLayers,
  validateAudioRendererRuntime,
  validateAudioToolchain,
  validateScoreProductionPlan,
  validateSoundscapeProductionPlan,
} from "./audio-production.mjs";

const modulePath = fileURLToPath(import.meta.url);
const repositoryRoot = path.resolve(path.dirname(modulePath), "../../..");
const audioRoot = path.join(repositoryRoot, "native/audio/score-soundscape");
const sourceRoot = path.join(audioRoot, "longhouse-responsive-v1");
const cacheRoot = path.join(audioRoot, "cache/longhouse-responsive-v1");
const scoreSourcePath = path.join(sourceRoot, "score-source.json");
const soundscapeSourcePath = path.join(sourceRoot, "soundscape-source.json");
const workObjectPath = path.join(sourceRoot, "longhouse-responsive-work-object.json");
const receiptPath = path.join(sourceRoot, "render-receipt.json");
const draftPath = path.join(
  repositoryRoot,
  "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json",
);
const audioBiblePath = path.join(repositoryRoot, "native/bibles/audio-bible.md");
const responsiveSpecPath = path.join(
  repositoryRoot,
  "native/ios/Sources/ContentKit/ResponsiveAudioProgramSpec.swift",
);
const responsiveRuntimePath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/ResponsiveAudioProgramRuntime.swift",
);
const responsiveControllerPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/ResponsiveAudioProgramController.swift",
);
const timelinePlannerPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/TimelinePlaybackPlan.swift",
);
const offlineResolverPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/OfflineAudioAssetResolver.swift",
);
const nativeTransportPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/NativeTimelineTransport.swift",
);
const durableCompletionPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/DurableInteractionAudioCompletion.swift",
);
const hapticRuntimePath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/SemanticHapticTransport.swift",
);
const audioRendererPath = path.join(
  repositoryRoot,
  "native/tooling/src/audio-production.mjs",
);
const toolchainPath = path.join(audioRoot, "toolchain.json");
const soundFontPath = path.join(audioRoot, "cache/ms-basic-0.2.0.sf3");
const noticePath = path.join(audioRoot, "licenses/MS-Basic-0.2.0-LICENSE.md");
const costRegistryPath = path.join(
  repositoryRoot,
  "native/tooling/registries/cost-license.json",
);

const fluidSynthPath = "/opt/homebrew/bin/fluidsynth";
const ffmpegPath = "/opt/homebrew/bin/ffmpeg";
const regions = ["approach", "waiting", "engaged", "resistance", "consequence"];
const loopRegions = new Set(["waiting", "engaged", "resistance"]);
const regionDurations = new Map([
  ["approach", 48],
  ["waiting", 15],
  ["engaged", 15],
  ["resistance", 15],
  ["consequence", 45],
]);
const timelineGains = { score: 0.72, soundscape: 0.82, spatialDetail: 0.9 };
const canonicalHaptics = ["contact", "drag", "resistance", "transfer", "break", "seal"];
const activeLonghouseHaptics = ["contact", "resistance", "seal"];
const packageRoot = "audio/first-farmers/longhouse-responsive-v1";
const stableIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/u;

function fail(...issues) {
  throw new AudioProductionError(issues.flat());
}

function assert(condition, issue) {
  if (!condition) fail(issue);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function hashFile(file) {
  const bytes = await readFile(file);
  return { bytes: bytes.length, sha256: sha256(bytes) };
}

function relativeToRepository(file) {
  const relative = path.relative(repositoryRoot, file).split(path.sep).join("/");
  assert(relative && !relative.startsWith("../"), `path escaped repository: ${file}`);
  return relative;
}

async function inputRecord(id, file) {
  return { id, path: relativeToRepository(file), ...await hashFile(file) };
}

function stableID(value, location) {
  assert(typeof value === "string" && stableIDPattern.test(value), `${location}: stable kebab-case ID required`);
}

function unique(values, location) {
  assert(new Set(values).size === values.length, `${location}: duplicate value`);
}

function validateOutput(output, location) {
  assert(output?.sampleRate === 48_000, `${location}.sampleRate: 48000 required`);
  assert(output?.bitDepth === 24, `${location}.bitDepth: 24 required`);
  assert(output?.channels === 2, `${location}.channels: stereo required`);
  assert(output?.container === "wav", `${location}.container: wav required`);
}

function scorePlan(source, region) {
  return {
    schemaVersion: 1,
    kind: "symbolic-score",
    id: `${source.id}-${region.id}`,
    status: "TECHNICAL_PROBE_NOT_APPROVED",
    output: source.output,
    ppq: source.ppq,
    durationBeats: region.durationSeconds * source.tempoBPM / 60,
    meter: source.meter,
    tempoMap: [{ atBeat: 0, bpm: source.tempoBPM }],
    motifs: source.motifs,
    stems: region.stems,
  };
}

function soundscapePlan(source, region) {
  return {
    schemaVersion: 1,
    kind: "procedural-soundscape",
    id: `${source.id}-${region.id}`,
    status: "TECHNICAL_PROBE_NOT_APPROVED",
    output: source.output,
    durationSeconds: region.durationSeconds,
    layers: region.layers,
    silenceWindows: region.silenceWindows,
  };
}

function validateScoreSource(source) {
  assert(source?.schemaVersion === 1, "scoreSource.schemaVersion: 1 required");
  assert(source.kind === "responsive-symbolic-score", "scoreSource.kind drifted");
  stableID(source.id, "scoreSource.id");
  assert(source.status === "PROVISIONAL_NON_SHIPPING", "scoreSource.status drifted");
  assert(source.shippingState === "PROHIBITED", "scoreSource.shippingState drifted");
  validateOutput(source.output, "scoreSource.output");
  assert(source.ppq === 960, "scoreSource.ppq: 960 required");
  assert(source.meter?.numerator === 4 && source.meter?.denominator === 4, "scoreSource.meter: authored 4/4 required");
  assert(source.tempoBPM === 54, "scoreSource.tempoBPM: authored 54 BPM required");
  assert(typeof source.direction === "string" && source.direction.trim(), "scoreSource.direction required");
  assert(Array.isArray(source.motifs) && source.motifs.length >= 6, "scoreSource.motifs: authored vocabulary required");
  unique(source.motifs.map(({ id }) => id), "scoreSource.motifs.id");
  assert(JSON.stringify(source.regions?.map(({ id }) => id)) === JSON.stringify(regions), "scoreSource.regions order drifted");
  for (const region of source.regions) {
    stableID(region.timelineID, `${region.id}.timelineID`);
    stableID(region.scoreStateID, `${region.id}.scoreStateID`);
    assert(region.durationSeconds === regionDurations.get(region.id), `${region.id}: duration drifted`);
    assert(region.loop === loopRegions.has(region.id), `${region.id}: loop binding drifted`);
    assert(Array.isArray(region.stems) && region.stems.length === 3, `${region.id}: exact three editable score stems required`);
    unique(region.stems.map(({ id }) => id), `${region.id}.stems.id`);
    validateScoreProductionPlan(scorePlan(source, region));
  }
  return source;
}

function validateSoundscapeSource(source, scoreSource) {
  assert(source?.schemaVersion === 1, "soundscapeSource.schemaVersion: 1 required");
  assert(source.kind === "responsive-procedural-soundscape", "soundscapeSource.kind drifted");
  stableID(source.id, "soundscapeSource.id");
  assert(source.status === "PROVISIONAL_NON_SHIPPING", "soundscapeSource.status drifted");
  assert(source.shippingState === "PROHIBITED", "soundscapeSource.shippingState drifted");
  validateOutput(source.output, "soundscapeSource.output");
  assert(JSON.stringify(source.mixGroups) === JSON.stringify({
    soundscape: ["weather-ground", "hearth-fire", "timber-work"],
    spatialDetail: ["daub-chaff", "fibre-lashing"],
  }), "soundscapeSource.mixGroups drifted");
  assert(JSON.stringify(source.regions?.map(({ id }) => id)) === JSON.stringify(regions), "soundscapeSource.regions order drifted");
  for (const [index, region] of source.regions.entries()) {
    const scoreRegion = scoreSource.regions[index];
    assert(region.timelineID === scoreRegion.timelineID, `${region.id}: score timeline binding drifted`);
    assert(region.durationSeconds === scoreRegion.durationSeconds, `${region.id}: score duration binding drifted`);
    assert(region.loop === scoreRegion.loop, `${region.id}: score loop binding drifted`);
    stableID(region.soundscapeStateID, `${region.id}.soundscapeStateID`);
    assert(region.layers?.length === 5, `${region.id}: exact five source-bound layers required`);
    assert(region.silenceWindows?.length === 1, `${region.id}: one named silence window required`);
    validateSoundscapeProductionPlan(soundscapePlan(source, region));
  }
  return source;
}

function decodePCM24StereoWAV(buffer, targetFrames = undefined) {
  const format = inspectPCM24StereoWAV(buffer);
  const frames = targetFrames ?? format.frames;
  const left = new Float64Array(frames);
  const right = new Float64Array(frames);
  const available = Math.min(frames, format.frames);
  for (let frame = 0; frame < available; frame += 1) {
    const offset = 44 + frame * 6;
    let leftValue = buffer[offset] | (buffer[offset + 1] << 8) | (buffer[offset + 2] << 16);
    let rightValue = buffer[offset + 3] | (buffer[offset + 4] << 8) | (buffer[offset + 5] << 16);
    if (leftValue & 0x800000) leftValue -= 0x1000000;
    if (rightValue & 0x800000) rightValue -= 0x1000000;
    left[frame] = leftValue / 8_388_607;
    right[frame] = rightValue / 8_388_607;
  }
  return { left, right };
}

function cloneAudio(audio) {
  return { left: new Float64Array(audio.left), right: new Float64Array(audio.right) };
}

function applyEdgeFade(audio, frames) {
  const count = Math.min(frames, Math.floor(audio.left.length / 2));
  for (let index = 0; index < count; index += 1) {
    const gain = Math.sin((index / Math.max(1, count - 1)) * Math.PI / 2) ** 2;
    const tailGain = Math.cos((index / Math.max(1, count - 1)) * Math.PI / 2) ** 2;
    audio.left[index] *= gain;
    audio.right[index] *= gain;
    const tail = audio.left.length - count + index;
    audio.left[tail] *= tailGain;
    audio.right[tail] *= tailGain;
  }
}

function makePeriodic(audio) {
  const original = cloneAudio(audio);
  const frames = audio.left.length;
  const half = Math.floor(frames / 2);
  for (let frame = 0; frame < frames; frame += 1) {
    const weight = Math.sin(Math.PI * frame / frames) ** 2;
    const shifted = (frame + half) % frames;
    audio.left[frame] = original.left[frame] * weight + original.left[shifted] * (1 - weight);
    audio.right[frame] = original.right[frame] * weight + original.right[shifted] * (1 - weight);
  }
}

function applySilenceWindows(audio, windows, sampleRate) {
  const fadeFrames = Math.round(sampleRate * 0.012);
  for (const silence of windows) {
    const start = Math.round(silence.atSeconds * sampleRate);
    const end = Math.round((silence.atSeconds + silence.durationSeconds) * sampleRate);
    for (let frame = Math.max(0, start - fadeFrames); frame < start; frame += 1) {
      const gain = (start - frame) / fadeFrames;
      audio.left[frame] *= gain;
      audio.right[frame] *= gain;
    }
    audio.left.fill(0, start, end);
    audio.right.fill(0, start, end);
    for (let frame = end; frame < Math.min(audio.left.length, end + fadeFrames); frame += 1) {
      const gain = (frame - end) / fadeFrames;
      audio.left[frame] *= gain;
      audio.right[frame] *= gain;
    }
    if (end === audio.left.length) {
      for (let frame = 0; frame < Math.min(fadeFrames, audio.left.length); frame += 1) {
        const gain = frame / fadeFrames;
        audio.left[frame] *= gain;
        audio.right[frame] *= gain;
      }
    }
  }
}

function mixAudios(items) {
  assert(items.length > 0, "audio mix: at least one source required");
  const frames = items[0].audio.left.length;
  const mixed = { left: new Float64Array(frames), right: new Float64Array(frames) };
  for (const { audio, gain = 1 } of items) {
    assert(audio.left.length === frames && audio.right.length === frames, "audio mix: frame mismatch");
    for (let frame = 0; frame < frames; frame += 1) {
      mixed.left[frame] += audio.left[frame] * gain;
      mixed.right[frame] += audio.right[frame] * gain;
    }
  }
  return mixed;
}

function peak(audio) {
  let maximum = 0;
  for (let frame = 0; frame < audio.left.length; frame += 1) {
    maximum = Math.max(maximum, Math.abs(audio.left[frame]), Math.abs(audio.right[frame]));
  }
  return maximum;
}

function scale(audio, gain) {
  for (let frame = 0; frame < audio.left.length; frame += 1) {
    audio.left[frame] *= gain;
    audio.right[frame] *= gain;
  }
}

function normalizeGroup(audios, targetPeakDBFS) {
  const mixed = mixAudios(audios.map((audio) => ({ audio })));
  const currentPeak = peak(mixed);
  assert(currentPeak > 0, "audio normalization: silent group");
  const factor = 10 ** (targetPeakDBFS / 20) / currentPeak;
  audios.forEach((audio) => scale(audio, factor));
  scale(mixed, factor);
  return { mixed, factor };
}

function verifySilence(audio, windows, sampleRate, location) {
  for (const silence of windows) {
    const start = Math.round(silence.atSeconds * sampleRate);
    const end = Math.round((silence.atSeconds + silence.durationSeconds) * sampleRate);
    for (let frame = start; frame < end; frame += 1) {
      if (audio.left[frame] !== 0 || audio.right[frame] !== 0) {
        fail(`${location}: authored silence '${silence.id}' contains non-zero samples`);
      }
    }
  }
}

function verifyLoopSeam(audio, location) {
  const last = audio.left.length - 1;
  const leftDelta = Math.abs(audio.left[0] - audio.left[last]);
  const rightDelta = Math.abs(audio.right[0] - audio.right[last]);
  assert(leftDelta <= 0.005 && rightDelta <= 0.005, `${location}: loop seam delta exceeds 0.005`);
  return { leftDelta, rightDelta };
}

async function writeWAV(file, audio) {
  const wav = encodePCM24StereoWAV(audio.left, audio.right, 48_000);
  await writeFile(file, wav);
  return { bytes: wav.length, sha256: sha256(wav), format: inspectPCM24StereoWAV(wav) };
}

async function renderFluidStem(plan, stem, directory, targetFrames) {
  const midi = compileScoreStemMIDI(plan, stem.id);
  const midiName = `score-${stem.id}.mid`;
  const midiPath = path.join(directory, midiName);
  const rawPath = path.join(directory, `.${stem.id}-fluidsynth-raw.wav`);
  await writeFile(midiPath, midi);
  const result = spawnSync(fluidSynthPath, [
    "-ni", "-q", "-C", "0", "-R", "0", "-g", "2.5", "-r", "48000",
    "-o", "synth.cpu-cores=1", "-O", "s24", "-T", "wav", "-F", rawPath,
    soundFontPath, midiPath,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    fail(`FluidSynth ${plan.id}/${stem.id}: ${result.stderr?.trim() || result.stdout?.trim() || "render failed"}`);
  }
  const audio = decodePCM24StereoWAV(await readFile(rawPath), targetFrames);
  await rm(rawPath, { force: true });
  return { midiName, midiPath, audio };
}

function outputRecord({ regionID, role, sourceID, file, root, packageAssetPath = null, lineage, rights, format = undefined }) {
  return hashFile(file).then((record) => ({
    regionID,
    role,
    sourceID,
    path: path.relative(root, file).split(path.sep).join("/"),
    packageAssetPath,
    ...record,
    ...(format ? { format } : {}),
    lineage,
    commercialRights: rights,
    incrementalCostNOK: 0,
  }));
}

async function renderScoreRegion(scoreSource, soundscapeSource, region, outputRoot, outputs) {
  const directory = path.join(outputRoot, region.id);
  await mkdir(directory, { recursive: true });
  const plan = scorePlan(scoreSource, region);
  const targetFrames = Math.round(region.durationSeconds * 48_000);
  const silenceWindows = soundscapeSource.regions.find(({ id }) => id === region.id).silenceWindows;
  const rendered = [];
  for (const stem of region.stems) {
    const item = await renderFluidStem(plan, stem, directory, targetFrames);
    applyEdgeFade(item.audio, Math.round(48_000 * (region.loop ? 0.4 : 0.025)));
    applySilenceWindows(item.audio, silenceWindows, 48_000);
    rendered.push({ stem, ...item });
  }
  const normalized = normalizeGroup(rendered.map(({ audio }) => audio), -14);
  for (const item of rendered) {
    const wavPath = path.join(directory, `score-${item.stem.id}.wav`);
    const wavRecord = await writeWAV(wavPath, item.audio);
    outputs.push(await outputRecord({
      regionID: region.id,
      role: "score-stem-midi",
      sourceID: item.stem.id,
      file: item.midiPath,
      root: outputRoot,
      lineage: "PROJECT_AUTHORED_SYMBOLIC_SCORE",
      rights: "PROJECT_OWNED_SOURCE",
    }));
    outputs.push(await outputRecord({
      regionID: region.id,
      role: "score-stem-master",
      sourceID: item.stem.id,
      file: wavPath,
      root: outputRoot,
      lineage: "PROJECT_AUTHORED_SCORE_RENDERED_WITH_PINNED_MIT_SOUNDFONT",
      rights: "COMMERCIAL_REDISTRIBUTION_ALLOWED_WITH_RETAINED_MIT_NOTICE",
      format: wavRecord.format,
    }));
  }
  const masterPath = path.join(directory, "score-master.wav");
  const masterRecord = await writeWAV(masterPath, normalized.mixed);
  const packageAssetPath = `${packageRoot}/${region.id}/score-master.wav`;
  outputs.push(await outputRecord({
    regionID: region.id,
    role: "score-master",
    sourceID: region.scoreStateID,
    file: masterPath,
    root: outputRoot,
    packageAssetPath,
    lineage: "PROJECT_AUTHORED_SCORE_RENDERED_WITH_PINNED_MIT_SOUNDFONT",
    rights: "COMMERCIAL_REDISTRIBUTION_ALLOWED_WITH_RETAINED_MIT_NOTICE",
    format: masterRecord.format,
  }));
  return { path: masterPath, packageAssetPath };
}

async function renderSoundscapeRegion(source, region, outputRoot, outputs) {
  const directory = path.join(outputRoot, region.id);
  await mkdir(directory, { recursive: true });
  const buffers = renderProceduralSoundscapeLayers(soundscapePlan(source, region));
  const layerAudios = new Map();
  for (const layer of region.layers) {
    const audio = decodePCM24StereoWAV(buffers.get(layer.id));
    if (region.loop) {
      makePeriodic(audio);
      applyEdgeFade(audio, Math.round(48_000 * 0.03));
    }
    applySilenceWindows(audio, region.silenceWindows, 48_000);
    layerAudios.set(layer.id, audio);
  }
  const broad = source.mixGroups.soundscape.map((id) => layerAudios.get(id));
  const spatial = source.mixGroups.spatialDetail.map((id) => layerAudios.get(id));
  const broadNormalized = normalizeGroup(broad, -18);
  const spatialNormalized = normalizeGroup(spatial, -16);
  for (const layer of region.layers) {
    const file = path.join(directory, `sound-${layer.id}.wav`);
    const wavRecord = await writeWAV(file, layerAudios.get(layer.id));
    outputs.push(await outputRecord({
      regionID: region.id,
      role: source.mixGroups.soundscape.includes(layer.id) ? "soundscape-layer-master" : "spatial-layer-master",
      sourceID: layer.id,
      file,
      root: outputRoot,
      lineage: "PROJECT_AUTHORED_PROCEDURAL_AUDIO",
      rights: "PROJECT_OWNED_SOURCE_AND_OUTPUT",
      format: wavRecord.format,
    }));
  }
  const soundscapePath = path.join(directory, "soundscape-master.wav");
  const spatialPath = path.join(directory, "spatial-detail-master.wav");
  const soundscapeRecord = await writeWAV(soundscapePath, broadNormalized.mixed);
  const spatialRecord = await writeWAV(spatialPath, spatialNormalized.mixed);
  const soundscapePackagePath = `${packageRoot}/${region.id}/soundscape-master.wav`;
  const spatialPackagePath = `${packageRoot}/${region.id}/spatial-detail-master.wav`;
  outputs.push(await outputRecord({
    regionID: region.id,
    role: "soundscape-master",
    sourceID: region.soundscapeStateID,
    file: soundscapePath,
    root: outputRoot,
    packageAssetPath: soundscapePackagePath,
    lineage: "PROJECT_AUTHORED_PROCEDURAL_AUDIO",
    rights: "PROJECT_OWNED_SOURCE_AND_OUTPUT",
    format: soundscapeRecord.format,
  }));
  outputs.push(await outputRecord({
    regionID: region.id,
    role: "spatial-detail-master",
    sourceID: `${region.soundscapeStateID}-near-material`,
    file: spatialPath,
    root: outputRoot,
    packageAssetPath: spatialPackagePath,
    lineage: "PROJECT_AUTHORED_PROCEDURAL_AUDIO",
    rights: "PROJECT_OWNED_SOURCE_AND_OUTPUT",
    format: spatialRecord.format,
  }));
  return { soundscapePath, spatialPath };
}

function analyseWithFFmpeg(file) {
  const result = spawnSync(ffmpegPath, [
    "-hide_banner", "-nostats", "-i", file, "-filter_complex", "ebur128=peak=true", "-f", "null", "-",
  ], { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  assert(result.status === 0, `ffmpeg ebur128 failed: ${result.stderr?.trim()}`);
  const summary = result.stderr.slice(result.stderr.lastIndexOf("Summary:"));
  const integrated = /Integrated loudness:[\s\S]*?I:\s+(-?\d+(?:\.\d+)?) LUFS/u.exec(summary);
  const truePeak = /True peak:[\s\S]*?Peak:\s+(-?\d+(?:\.\d+)?) dBFS/u.exec(summary);
  assert(integrated && truePeak, "ffmpeg ebur128 summary could not be parsed");
  return { integratedLUFS: Number(integrated[1]), truePeakDBTP: Number(truePeak[1]) };
}

async function renderPreview(region, score, sound, outputRoot, outputs) {
  const [scoreBytes, soundscapeBytes, spatialBytes] = await Promise.all([
    readFile(score.path), readFile(sound.soundscapePath), readFile(sound.spatialPath),
  ]);
  const preview = mixAudios([
    { audio: decodePCM24StereoWAV(scoreBytes), gain: timelineGains.score },
    { audio: decodePCM24StereoWAV(soundscapeBytes), gain: timelineGains.soundscape },
    { audio: decodePCM24StereoWAV(spatialBytes), gain: timelineGains.spatialDetail },
  ]);
  verifySilence(preview, region.silenceWindows, 48_000, `${region.id} preview`);
  const seam = region.loop ? verifyLoopSeam(preview, `${region.id} preview`) : null;
  const file = path.join(outputRoot, region.id, "program-preview.wav");
  const record = await writeWAV(file, preview);
  const metrics = analyseWithFFmpeg(file);
  assert(metrics.truePeakDBTP <= -1, `${region.id} preview true peak exceeds -1 dBTP`);
  outputs.push(await outputRecord({
    regionID: region.id,
    role: "program-preview",
    sourceID: `${region.id}-offline-preview`,
    file,
    root: outputRoot,
    lineage: "PROJECT_AUTHORED_OFFLINE_MIX",
    rights: "SCORE_NOTICE_REQUIRED; PROCEDURAL_AUDIO_PROJECT_OWNED",
    format: record.format,
  }));
  return { ...metrics, ...(seam ? { loopSeam: seam } : {}) };
}

async function productionInputs() {
  return Promise.all([
    inputRecord("longhouse-responsive-score-source", scoreSourcePath),
    inputRecord("longhouse-responsive-soundscape-source", soundscapeSourcePath),
    inputRecord("first-farmers-manuscript-source", draftPath),
    inputRecord("native-audio-bible", audioBiblePath),
    inputRecord("responsive-audio-program-spec", responsiveSpecPath),
    inputRecord("responsive-audio-program-runtime", responsiveRuntimePath),
    inputRecord("responsive-audio-program-controller", responsiveControllerPath),
    inputRecord("responsive-audio-timeline-planner", timelinePlannerPath),
    inputRecord("responsive-audio-transport-contract", offlineResolverPath),
    inputRecord("native-timeline-transport", nativeTransportPath),
    inputRecord("durable-audio-completion-runtime", durableCompletionPath),
    inputRecord("semantic-haptic-runtime", hapticRuntimePath),
    inputRecord("audio-production-renderer", audioRendererPath),
    inputRecord("longhouse-responsive-renderer", modulePath),
    inputRecord("score-soundscape-toolchain", toolchainPath),
    inputRecord("required-mit-notice", noticePath),
    inputRecord("zero-cost-license-registry", costRegistryPath),
  ]);
}

async function validateZeroCostRegistry(registry) {
  const entries = new Map((registry.entries ?? []).map((entry) => [entry.id, entry]));
  for (const id of [
    "fluid-synth-local",
    "musescore-ms-basic-sf3",
    "audio-production-local",
    "authored-score-rendering",
    "soundscape-generation",
  ]) {
    const entry = entries.get(id);
    assert(entry, `zero-cost registry is missing '${id}'`);
    assert(entry.incrementalCostNOK === 0, `${id}: incremental cost must remain zero`);
    assert(entry.billingCredentialRequired === false, `${id}: billing credentials are forbidden`);
    assert(entry.commercialUse === "allowed", `${id}: commercial use must be explicit`);
    assert(typeof entry.license === "string" && entry.license.trim(), `${id}: licence required`);
  }
}

async function pinnedRuntime(toolchain) {
  await validateAudioRendererRuntime({ toolchain, soundFontPath, fluidSynthPath });
  const ffmpeg = await hashFile(ffmpegPath).catch(() => fail("ffmpeg runtime missing"));
  assert(ffmpeg.sha256 === toolchain.ffmpeg.installedBinarySHA256, "ffmpeg binary hash drifted");
  const version = spawnSync(ffmpegPath, ["-version"], { encoding: "utf8" });
  assert(version.status === 0 && version.stdout.includes(`ffmpeg version ${toolchain.ffmpeg.version}`), "ffmpeg version drifted");
  return {
    fluidSynth: {
      version: toolchain.fluidSynth.version,
      binarySHA256: toolchain.fluidSynth.installedBinarySHA256,
    },
    soundFont: {
      version: toolchain.soundFont.version,
      bytes: toolchain.soundFont.bytes,
      sha256: toolchain.soundFont.sha256,
      license: toolchain.soundFont.license,
      noticeSHA256: toolchain.soundFont.noticeSHA256,
    },
    ffmpeg: { version: toolchain.ffmpeg.version, binarySHA256: ffmpeg.sha256 },
    node: { version: process.version, executable: await hashFile(process.execPath) },
  };
}

async function readSources() {
  const [scoreBytes, soundscapeBytes, draftBytes, toolchainBytes, costBytes] = await Promise.all([
    readFile(scoreSourcePath), readFile(soundscapeSourcePath), readFile(draftPath),
    readFile(toolchainPath), readFile(costRegistryPath),
  ]);
  const scoreSource = validateScoreSource(JSON.parse(scoreBytes));
  const soundscapeSource = validateSoundscapeSource(JSON.parse(soundscapeBytes), scoreSource);
  const toolchain = validateAudioToolchain(JSON.parse(toolchainBytes));
  await validateZeroCostRegistry(JSON.parse(costBytes));
  return { scoreSource, soundscapeSource, draft: JSON.parse(draftBytes), toolchain };
}

export async function validateLonghouseResponsiveAudioSources() {
  const { scoreSource, soundscapeSource, draft } = await readSources();
  const assembly = findBeat(draft, "beat-first-farmers-raise-longhouse");
  assert(assembly?.interaction?.grammar === "assemble", "Longhouse source lost its Assemble mechanism");
  return {
    scoreSourceID: scoreSource.id,
    soundscapeSourceID: soundscapeSource.id,
    regionCount: scoreSource.regions.length,
  };
}

function timeline(region, scoreRegion, soundRegion) {
  const durationSamples = Math.round(region.durationSeconds * 48_000);
  return {
    id: region.timelineID,
    sampleRate: 48_000,
    events: [
      {
        cueID: `${region.id}-score-master`, role: "score", startSample: 0, durationSamples,
        assetPath: `${packageRoot}/${region.id}/score-master.wav`, gain: timelineGains.score,
      },
      {
        cueID: `${region.id}-soundscape-master`, role: "soundscape", startSample: 0, durationSamples,
        assetPath: `${packageRoot}/${region.id}/soundscape-master.wav`, gain: timelineGains.soundscape,
      },
      {
        cueID: `${region.id}-spatial-detail-master`, role: "spatialDetail", startSample: 0, durationSamples,
        assetPath: `${packageRoot}/${region.id}/spatial-detail-master.wav`, gain: timelineGains.spatialDetail,
      },
      ...region.silenceWindows.map((silence) => ({
        cueID: `${region.id}-${silence.id}`,
        role: "silence",
        startSample: Math.round(silence.atSeconds * 48_000),
        durationSamples: Math.round(silence.durationSeconds * 48_000),
        assetPath: null,
        gain: 1,
      })),
    ],
    haptics: [],
    __scoreStateID: scoreRegion.scoreStateID,
    __soundscapeStateID: soundRegion.soundscapeStateID,
  };
}

function manuscriptSlot(timelineID, requiredAssetPath, beat, sourceDigest) {
  return {
    timelineID,
    status: "MISSING_EDITOR_SELECTED_NARRATION_MASTER",
    requiredAssetPath,
    sourceDocumentSHA256: sourceDigest,
    segments: beat.narrative.segments.map((segment) => ({
      manuscriptSegmentID: segment.id,
      manuscriptSegmentSHA256: sha256(Buffer.from(segment.text, "utf8")),
    })),
    insertionRule: "ADD_NARRATION_EVENTS_ONLY_AFTER_EDITOR_VOICE_SELECTION_AND_EXACT_WORD_ALIGNMENT",
    shippingBlock: true,
  };
}

function findBeat(draft, beatID) {
  return draft.arcs.flatMap(({ beats }) => beats).find(({ beatID: candidate }) => candidate === beatID);
}

async function buildWorkObject({ scoreSource, soundscapeSource, draft, inputs, outputs, metrics }) {
  const assembly = findBeat(draft, "beat-first-farmers-raise-longhouse");
  const consequence = findBeat(draft, "beat-first-farmers-plot-remains");
  assert(assembly && consequence, "Longhouse manuscript beats are missing");
  assert(assembly.interaction?.id === "interaction-first-farmers-the-house-outlives", "Longhouse interaction ID drifted");
  assert(assembly.interaction.grammar === "assemble", "Longhouse interaction grammar drifted");
  assert(JSON.stringify(assembly.interaction.components) === JSON.stringify([
    { id: "posts", targetSlot: "frame", prerequisites: [] },
    { id: "hearth", targetSlot: "centre", prerequisites: ["posts"] },
    { id: "storage", targetSlot: "dry-bay", prerequisites: ["posts"] },
    { id: "roof", targetSlot: "shelter", prerequisites: ["posts"] },
  ]), "Longhouse posts-first/free-remainder dependency drifted");
  assert(JSON.stringify(assembly.interaction.haptics) === JSON.stringify(activeLonghouseHaptics), "Longhouse haptic subset drifted");
  const authored = soundscapeSource.regions.map((region, index) => timeline(
    region,
    scoreSource.regions[index],
    region,
  ));
  const timelines = structuredClone(authored);
  timelines.forEach((item) => {
    delete item.__scoreStateID;
    delete item.__soundscapeStateID;
  });
  const metadata = outputs.filter(({ packageAssetPath }) => packageAssetPath).map((output) => ({
    path: output.packageAssetPath,
    sampleRate: output.format.sampleRate,
    frameCount: output.format.frames,
    channelCount: output.format.channels,
  }));
  const draftDigest = inputs.find(({ id }) => id === "first-farmers-manuscript-source").sha256;
  return {
    schemaVersion: 1,
    kind: "responsive-dramatic-audio-work-object",
    id: "longhouse-responsive-audio-v1",
    status: "PROVISIONAL_NON_SHIPPING",
    shippingState: "PROHIBITED",
    trustDomain: "BACKSTAGE_AUDIO_PRODUCTION",
    scope: {
      chapterID: "first-farmers",
      arcID: "first-farmers-arc-03",
      beatID: "beat-first-farmers-raise-longhouse",
      interactionID: "interaction-first-farmers-the-house-outlives",
    },
    responsiveProgram: {
      id: "longhouse-responsive-audio-v1",
      scope: {
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-03",
        beatID: "beat-first-farmers-raise-longhouse",
        interactionID: "interaction-first-farmers-the-house-outlives",
      },
      approachTimelineID: "longhouse-approach-v1",
      interactionBeds: [
        {
          phase: "waiting",
          timelineID: "longhouse-waiting-bed-v1",
          layerStates: {
            scoreStateID: "components-wait-on-open-ground",
            soundscapeStateID: "components-wait-on-open-ground",
          },
        },
        {
          phase: "engaged",
          timelineID: "longhouse-engaged-bed-v1",
          layerStates: {
            scoreStateID: "accepted-parts-take-weight",
            soundscapeStateID: "accepted-parts-take-weight",
          },
        },
        {
          phase: "resistance",
          timelineID: "longhouse-resistance-bed-v1",
          layerStates: {
            scoreStateID: "unsupported-order-holds",
            soundscapeStateID: "unsupported-component-resists",
          },
        },
      ],
      consequenceTimelineID: "longhouse-consequence-v1",
      exitPolicy: {
        kind: "bounded-fade",
        durationSamples: 9_600,
      },
    },
    interactionDependency: {
      prerequisiteComponentID: "posts",
      requiredFirst: true,
      remainingComponentIDs: ["hearth", "storage", "roof"],
      remainingOrder: "ANY_ORDER",
      resistanceOnlyBeforePrerequisite: true,
    },
    timelines,
    audioAssetMetadata: metadata,
    narrationSlots: [
      manuscriptSlot(
        "longhouse-approach-v1",
        `${packageRoot}/approach/narration-selected-master-required.wav`,
        assembly,
        draftDigest,
      ),
      manuscriptSlot(
        "longhouse-consequence-v1",
        `${packageRoot}/consequence/narration-selected-master-required.wav`,
        consequence,
        draftDigest,
      ),
    ],
    hapticProgram: {
      vocabulary: canonicalHaptics,
      activeLonghouseSemantics: activeLonghouseHaptics,
      reservedForOtherGrammars: ["drag", "transfer", "break"],
      runtimeBindings: [
        { trigger: "interaction-begin", semantic: "contact", durableCommitRequired: false },
        { trigger: "component-rejected", semantic: "resistance", durableCommitRequired: false },
        { trigger: "durable-completion", semantic: "seal", durableCommitRequired: true },
      ],
      loopedTimelineHaptics: "FORBIDDEN",
      accessibilityRule: "HAPTICS_NEVER_CARRY_THE_ONLY_CAUSAL_SIGNAL",
    },
    authoredSilence: soundscapeSource.regions.flatMap((region) => region.silenceWindows.map((silence) => ({
      timelineID: region.timelineID,
      sampleRate: 48_000,
      startSample: Math.round(silence.atSeconds * 48_000),
      durationSamples: Math.round(silence.durationSeconds * 48_000),
      id: silence.id,
      reason: silence.reason,
    }))),
    previewMetrics: metrics,
    provenance: {
      productionInputs: inputs,
      outputReceipt: "render-receipt.json",
      scoreLineage: "PROJECT_AUTHORED_SYMBOLIC_SCORE_RENDERED_WITH_PINNED_MIT_SOUNDFONT",
      soundscapeLineage: "PROJECT_AUTHORED_PROCEDURAL_AUDIO_WITH_NO_IMPORTED_RECORDINGS",
      runtimeGeneration: "PROHIBITED",
      incrementalCostNOK: 0,
      commercialRights: "ALLOWED_WITH_RETAINED_MS_BASIC_MIT_NOTICE",
      requiredNoticePath: "native/audio/score-soundscape/licenses/MS-Basic-0.2.0-LICENSE.md",
    },
    gates: {
      responsiveProgramContract: "PASS_LOCAL_SPEC_VALIDATION_REQUIRED_BY_SWIFT_TEST",
      exactOfflineMasters: "PASS",
      sampleExactPhaseBeds: "PASS",
      authoredSilence: "PASS",
      canonicalHapticVocabulary: "PASS",
      zeroIncrementalCost: "PASS",
      commercialRights: "PASS_WITH_RETAINED_MIT_NOTICE",
      narrationMaster: "OPEN_MISSING_EDITOR_SELECTED_MASTER",
      narrationWordAlignment: "OPEN_MISSING_EDITOR_SELECTED_MASTER",
      integratedLoudnessCalibration: "OPEN_UNTIL_NARRATION_MASTER_IS_BOUND",
      artisticApproval: "OPEN",
      editorApproval: "OPEN",
      shippingApproval: "PROHIBITED",
      physicalDeviceAudit: "OPEN",
    },
    claimsExcluded: [
      "editor approval",
      "artistic approval",
      "shipping approval",
      "final narration integration",
      "physical-device quality",
    ],
  };
}

async function renderAll(outputRoot) {
  const { scoreSource, soundscapeSource, draft, toolchain } = await readSources();
  const inputs = await productionInputs();
  const runtime = await pinnedRuntime(toolchain);
  await mkdir(outputRoot, { recursive: true });
  const outputs = [];
  const metrics = {};
  for (const regionID of regions) {
    const scoreRegion = scoreSource.regions.find(({ id }) => id === regionID);
    const soundRegion = soundscapeSource.regions.find(({ id }) => id === regionID);
    const score = await renderScoreRegion(scoreSource, soundscapeSource, scoreRegion, outputRoot, outputs);
    const sound = await renderSoundscapeRegion(soundscapeSource, soundRegion, outputRoot, outputs);
    metrics[regionID] = await renderPreview(soundRegion, score, sound, outputRoot, outputs);
  }
  outputs.sort((left, right) => left.path.localeCompare(right.path));
  const finalInputs = await productionInputs();
  assert(JSON.stringify(inputs) === JSON.stringify(finalInputs), "production inputs changed during offline rendering");
  const workObject = await buildWorkObject({
    scoreSource, soundscapeSource, draft, inputs, outputs, metrics,
  });
  return { workObject, outputs, inputs, runtime };
}

function outputIdentity(outputs) {
  return outputs.map(({ path: outputPath, bytes, sha256: digest, format }) => ({
    path: outputPath,
    bytes,
    sha256: digest,
    ...(format ? { format } : {}),
  }));
}

export async function renderLonghouseResponsiveAudio({ verifyReproducibility = true } = {}) {
  await rm(cacheRoot, { recursive: true, force: true });
  const first = await renderAll(cacheRoot);
  let reproducibility = "NOT_RUN";
  if (verifyReproducibility) {
    const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-longhouse-responsive-"));
    try {
      const second = await renderAll(temporary);
      assert(
        JSON.stringify(outputIdentity(first.outputs)) === JSON.stringify(outputIdentity(second.outputs)),
        "second complete offline render produced different output bytes",
      );
      assert(JSON.stringify(first.workObject.previewMetrics) === JSON.stringify(second.workObject.previewMetrics), "second render metrics drifted");
      reproducibility = "PASS_SECOND_COMPLETE_OFFLINE_RENDER";
    } finally {
      await rm(temporary, { recursive: true, force: true });
    }
  }
  const receipt = {
    schemaVersion: 1,
    id: "longhouse-responsive-audio-render-v1",
    status: "PROVISIONAL_NON_SHIPPING",
    shippingState: "PROHIBITED",
    productionInputs: first.inputs,
    toolchain: first.runtime,
    outputs: first.outputs,
    reproducibility,
    gates: {
      sourceValidation: "PASS",
      exactPCMFormat: "PASS_48000_HZ_24_BIT_STEREO",
      editableScoreMIDISourceAndStems: "PASS",
      sourceBoundSoundscapeAndSpatialLayers: "PASS",
      loopSeams: "PASS_LOCAL_NUMERIC_GATE",
      authoredSilence: "PASS_SAMPLE_ZERO_WINDOWS",
      truePeak: "PASS_ALL_PREVIEWS_AT_OR_BELOW_MINUS_1_DBTP",
      narration: "OPEN_MISSING_EDITOR_SELECTED_MASTER",
      artisticApproval: "OPEN",
      editorApproval: "OPEN",
      shippingApproval: "PROHIBITED",
    },
  };
  await writeFile(workObjectPath, `${JSON.stringify(first.workObject, null, 2)}\n`);
  await writeFile(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
  await validateLonghouseResponsiveAudio();
  return { workObject: first.workObject, receipt };
}

function validateWorkObject(work) {
  assert(work.schemaVersion === 1 && work.kind === "responsive-dramatic-audio-work-object", "work object identity drifted");
  assert(work.id === "longhouse-responsive-audio-v1", "work object ID drifted");
  assert(work.status === "PROVISIONAL_NON_SHIPPING" && work.shippingState === "PROHIBITED", "work object approval boundary drifted");
  assert(work.trustDomain === "BACKSTAGE_AUDIO_PRODUCTION", "work object trust domain drifted");
  assert(work.scope.beatID === "beat-first-farmers-raise-longhouse", "work object beat scope drifted");
  assert(work.responsiveProgram.id === work.id, "responsive program identity drifted");
  assert(JSON.stringify(work.interactionDependency) === JSON.stringify({
    prerequisiteComponentID: "posts",
    requiredFirst: true,
    remainingComponentIDs: ["hearth", "storage", "roof"],
    remainingOrder: "ANY_ORDER",
    resistanceOnlyBeforePrerequisite: true,
  }), "Longhouse audio dependency contract drifted");
  assert(work.responsiveProgram.approachTimelineID === "longhouse-approach-v1", "approach timeline drifted");
  assert(work.responsiveProgram.consequenceTimelineID === "longhouse-consequence-v1", "consequence timeline drifted");
  assert(JSON.stringify(work.responsiveProgram.exitPolicy) === JSON.stringify({
    kind: "bounded-fade",
    durationSamples: 9_600,
  }), "authored exit policy drifted");
  assert(JSON.stringify(work.responsiveProgram.interactionBeds.map(({ phase }) => phase))
    === JSON.stringify(["waiting", "engaged", "resistance"]), "responsive bed phase set drifted");
  unique(work.timelines.map(({ id }) => id), "work.timelines.id");
  assert(work.timelines.length === 5, "work.timelines: exact five authored regions required");
  for (const timelineItem of work.timelines) {
    assert(timelineItem.sampleRate === 48_000, `${timelineItem.id}: 48 kHz required`);
    assert(timelineItem.events?.length === 4, `${timelineItem.id}: score, soundscape, spatial detail and silence required`);
    assert(timelineItem.haptics?.length === 0, `${timelineItem.id}: timed haptics must not bypass semantic commits`);
    const roles = new Set(timelineItem.events.map(({ role }) => role));
    assert(JSON.stringify([...roles].sort()) === JSON.stringify(["score", "silence", "soundscape", "spatialDetail"].sort()), `${timelineItem.id}: audible role set drifted`);
  }
  const bedDurations = work.responsiveProgram.interactionBeds.map(({ timelineID }) => {
    const selected = work.timelines.find(({ id }) => id === timelineID);
    return Math.max(...selected.events.map(({ startSample, durationSamples }) => startSample + durationSamples));
  });
  assert(new Set(bedDurations).size === 1 && bedDurations[0] === 720_000, "phase beds are not sample-identical 15-second loops");
  assert(JSON.stringify(work.hapticProgram.vocabulary) === JSON.stringify(canonicalHaptics), "canonical haptic vocabulary drifted");
  assert(JSON.stringify(work.hapticProgram.activeLonghouseSemantics) === JSON.stringify(activeLonghouseHaptics), "Longhouse haptic subset drifted");
  assert(work.hapticProgram.runtimeBindings.find(({ semantic }) => semantic === "seal")?.durableCommitRequired === true, "seal escaped durable completion");
  assert(work.narrationSlots.length === 2
    && work.narrationSlots.every(({ status, shippingBlock }) => status === "MISSING_EDITOR_SELECTED_NARRATION_MASTER" && shippingBlock), "narration placeholders drifted");
  assert(work.provenance.incrementalCostNOK === 0, "work object introduced incremental cost");
  assert(work.gates.artisticApproval === "OPEN" && work.gates.shippingApproval === "PROHIBITED", "work object fabricated approval");
}

async function validateOutputs(receipt) {
  assert(receipt.outputs.length === 75, `receipt.outputs: expected 75, got ${receipt.outputs.length}`);
  for (const output of receipt.outputs) {
    const file = path.join(cacheRoot, output.path);
    const current = await hashFile(file).catch(() => fail(`missing rendered output: ${output.path}`));
    assert(current.bytes === output.bytes && current.sha256 === output.sha256, `${output.path}: rendered bytes drifted`);
    assert(output.incrementalCostNOK === 0, `${output.path}: incremental cost drifted`);
    if (output.format) {
      const format = inspectPCM24StereoWAV(await readFile(file));
      assert(JSON.stringify(format) === JSON.stringify(output.format), `${output.path}: WAV format drifted`);
      assert(format.frames === regionDurations.get(output.regionID) * 48_000, `${output.path}: exact frame duration drifted`);
    }
  }
  assert(receipt.reproducibility === "PASS_SECOND_COMPLETE_OFFLINE_RENDER", "receipt lacks complete second-render proof");
}

export async function validateLonghouseResponsiveAudio() {
  const { toolchain } = await readSources();
  const [workBytes, receiptBytes] = await Promise.all([
    readFile(workObjectPath), readFile(receiptPath),
  ]).catch(() => fail("Longhouse responsive work object and receipt are required"));
  const work = JSON.parse(workBytes);
  const receipt = JSON.parse(receiptBytes);
  validateWorkObject(work);
  assert(receipt.status === "PROVISIONAL_NON_SHIPPING" && receipt.shippingState === "PROHIBITED", "receipt approval boundary drifted");
  const expectedInputs = await productionInputs();
  assert(JSON.stringify(receipt.productionInputs) === JSON.stringify(expectedInputs), "receipt production inputs drifted");
  assert(JSON.stringify(work.provenance.productionInputs) === JSON.stringify(expectedInputs), "work provenance inputs drifted");
  await pinnedRuntime(toolchain);
  await validateOutputs(receipt);
  const outputByPackagePath = new Map(receipt.outputs.filter(({ packageAssetPath }) => packageAssetPath)
    .map((output) => [output.packageAssetPath, output]));
  assert(outputByPackagePath.size === 15, "exact fifteen runtime masters required");
  assert(work.audioAssetMetadata.length === 15, "exact fifteen runtime metadata records required");
  for (const metadata of work.audioAssetMetadata) {
    const output = outputByPackagePath.get(metadata.path);
    assert(output, `${metadata.path}: package master missing from receipt`);
    assert(output.format.frames === metadata.frameCount
      && output.format.sampleRate === metadata.sampleRate
      && output.format.channels === metadata.channelCount, `${metadata.path}: runtime metadata drifted`);
  }
  for (const slot of work.narrationSlots) {
    assert(!outputByPackagePath.has(slot.requiredAssetPath), `${slot.timelineID}: placeholder narration unexpectedly exists`);
  }
  const notice = await hashFile(noticePath);
  assert(notice.sha256 === toolchain.soundFont.noticeSHA256 && notice.bytes === toolchain.soundFont.noticeBytes, "required MIT notice drifted");
  return { work, receipt, workObjectSHA256: sha256(workBytes), receiptSHA256: sha256(receiptBytes) };
}

export const longhouseResponsiveAudioPaths = Object.freeze({
  repositoryRoot,
  sourceRoot,
  cacheRoot,
  scoreSourcePath,
  soundscapeSourcePath,
  workObjectPath,
  receiptPath,
});
