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
} from "./audio-production.mjs";

const modulePath = fileURLToPath(import.meta.url);
const repositoryRoot = path.resolve(path.dirname(modulePath), "../../..");
const audioRoot = path.join(repositoryRoot, "native", "audio", "score-soundscape");
const sourceRoot = path.join(audioRoot, "harvest-responsive-v1");
const cacheRoot = path.join(audioRoot, "cache", "harvest-responsive-v1");
const scoreSourcePath = path.join(sourceRoot, "score-source.json");
const soundscapeSourcePath = path.join(sourceRoot, "soundscape-source.json");
const workObjectPath = path.join(sourceRoot, "work-object.json");
const receiptPath = path.join(sourceRoot, "render-receipt.json");
const draftPath = path.join(
  repositoryRoot,
  "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json",
);
const sceneFixturePath = path.join(
  repositoryRoot,
  "native/phase1/fixtures/harvest-option-1.scene.json",
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
const timelinePlaybackPlannerPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/TimelinePlaybackPlan.swift",
);
const offlineAudioTransportContractPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/OfflineAudioAssetResolver.swift",
);
const nativeTimelineTransportPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/NativeTimelineTransport.swift",
);
const experienceAudioRoutingPolicyPath = path.join(
  repositoryRoot,
  "native/ios/Sources/DramaticAudio/ExperienceAudioRoutingPolicy.swift",
);
const experiencePreferencesContractPath = path.join(
  repositoryRoot,
  "native/ios/Sources/ExperiencePreferences/ExperiencePreferences.swift",
);
const durableAudioCompletionPath = path.join(
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
const soundFontPath = path.join(audioRoot, "cache", "ms-basic-0.2.0.sf3");
const noticePath = path.join(audioRoot, "licenses", "MS-Basic-0.2.0-LICENSE.md");
const costRegistryPath = path.join(
  repositoryRoot,
  "native/tooling/registries/cost-license.json",
);
const fluidSynthPath = "/opt/homebrew/bin/fluidsynth";
const ffmpegPath = "/opt/homebrew/bin/ffmpeg";

const stableIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/u;
const sha256Pattern = /^[a-f0-9]{64}$/u;
const canonicalHaptics = ["contact", "drag", "resistance", "transfer", "break", "seal"];
const activeHarvestHaptics = ["contact", "resistance", "transfer", "seal"];
const regions = ["approach", "waiting", "engaged", "resistance", "consequence"];
const loopRegions = new Set(["waiting", "engaged", "resistance"]);
const timelineGains = { score: 0.72, soundscape: 0.82, spatialDetail: 0.9 };
const materialAlgorithms = {
  rain: "rain-on-earth-v1",
  fire: "small-hearth-fire-v1",
  grain: "dry-grain-contact-v1",
  textile: "woven-fibre-friction-v1",
  work: "distant-material-work-v1",
};

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

function exactKeys(value, expected, location) {
  assert(value && typeof value === "object" && !Array.isArray(value), `${location}: object required`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  assert(JSON.stringify(actual) === JSON.stringify(wanted), `${location}: expected keys ${wanted.join(", ")}`);
}

function stableID(value, location) {
  assert(typeof value === "string" && stableIDPattern.test(value), `${location}: stable kebab-case ID required`);
}

function finite(value, location, minimum, maximum) {
  assert(Number.isFinite(value) && value >= minimum && value <= maximum, `${location}: ${minimum}...${maximum} required`);
}

function unique(values, location) {
  assert(new Set(values).size === values.length, `${location}: duplicate value`);
}

function validateOutput(output, location) {
  exactKeys(output, ["sampleRate", "bitDepth", "channels", "container"], location);
  assert(output.sampleRate === 48_000, `${location}.sampleRate: 48000 required`);
  assert(output.bitDepth === 24, `${location}.bitDepth: 24 required`);
  assert(output.channels === 2, `${location}.channels: stereo required`);
  assert(output.container === "wav", `${location}.container: wav required`);
}

function validateScoreSource(source) {
  exactKeys(source, [
    "schemaVersion", "kind", "id", "status", "shippingState", "output", "ppq",
    "meter", "tempoBPM", "direction", "motifs", "regions",
  ], "scoreSource");
  assert(source.schemaVersion === 1, "scoreSource.schemaVersion: 1 required");
  assert(source.kind === "responsive-symbolic-score", "scoreSource.kind drifted");
  stableID(source.id, "scoreSource.id");
  assert(source.status === "PROVISIONAL_NON_SHIPPING", "scoreSource.status drifted");
  assert(source.shippingState === "PROHIBITED", "scoreSource.shippingState drifted");
  validateOutput(source.output, "scoreSource.output");
  assert(Number.isSafeInteger(source.ppq) && source.ppq === 960, "scoreSource.ppq: locked 960 required");
  exactKeys(source.meter, ["numerator", "denominator"], "scoreSource.meter");
  assert(source.meter.numerator === 5 && source.meter.denominator === 4, "scoreSource.meter: authored 5/4 required");
  assert(source.tempoBPM === 60, "scoreSource.tempoBPM: authored 60 BPM required");
  assert(typeof source.direction === "string" && source.direction.trim(), "scoreSource.direction required");
  assert(Array.isArray(source.motifs) && source.motifs.length >= 5, "scoreSource.motifs: authored vocabulary required");
  unique(source.motifs.map(({ id }) => id), "scoreSource.motifs.id");
  for (const [index, motif] of source.motifs.entries()) {
    exactKeys(motif, ["id", "notes"], `scoreSource.motifs[${index}]`);
    stableID(motif.id, `scoreSource.motifs[${index}].id`);
    assert(Array.isArray(motif.notes) && motif.notes.length > 0, `scoreSource.motifs[${index}].notes required`);
  }
  assert(Array.isArray(source.regions), "scoreSource.regions required");
  assert(JSON.stringify(source.regions.map(({ id }) => id)) === JSON.stringify(regions), "scoreSource.regions order drifted");
  const timelineIDs = [];
  for (const [index, region] of source.regions.entries()) {
    const location = `scoreSource.regions[${index}]`;
    exactKeys(region, ["id", "timelineID", "scoreStateID", "durationSeconds", "loop", "stems"], location);
    stableID(region.id, `${location}.id`);
    stableID(region.timelineID, `${location}.timelineID`);
    stableID(region.scoreStateID, `${location}.scoreStateID`);
    finite(region.durationSeconds, `${location}.durationSeconds`, 1, 120);
    assert(region.loop === loopRegions.has(region.id), `${location}.loop drifted`);
    timelineIDs.push(region.timelineID);
    assert(Array.isArray(region.stems) && region.stems.length >= 3, `${location}.stems: at least three required`);
    unique(region.stems.map(({ id }) => id), `${location}.stems.id`);
  }
  unique(timelineIDs, "scoreSource.regions.timelineID");
  assert(source.regions.filter(({ loop }) => loop).every(({ durationSeconds }) => durationSeconds === 15), "scoreSource: phase beds require one sample-exact duration");
  return source;
}

function validateSoundscapeSource(source, scoreSource) {
  exactKeys(source, [
    "schemaVersion", "kind", "id", "status", "shippingState", "output", "mixGroups", "regions",
  ], "soundscapeSource");
  assert(source.schemaVersion === 1, "soundscapeSource.schemaVersion: 1 required");
  assert(source.kind === "responsive-procedural-soundscape", "soundscapeSource.kind drifted");
  stableID(source.id, "soundscapeSource.id");
  assert(source.status === "PROVISIONAL_NON_SHIPPING", "soundscapeSource.status drifted");
  assert(source.shippingState === "PROHIBITED", "soundscapeSource.shippingState drifted");
  validateOutput(source.output, "soundscapeSource.output");
  exactKeys(source.mixGroups, ["soundscape", "spatialDetail"], "soundscapeSource.mixGroups");
  const grouped = [...source.mixGroups.soundscape, ...source.mixGroups.spatialDetail];
  assert(JSON.stringify(grouped) === JSON.stringify([
    "rain-earth", "hearth-fire", "settlement-work", "grain-contact", "fibre-strain",
  ]), "soundscapeSource.mixGroups drifted");
  unique(grouped, "soundscapeSource.mixGroups");
  assert(Array.isArray(source.regions), "soundscapeSource.regions required");
  assert(JSON.stringify(source.regions.map(({ id }) => id)) === JSON.stringify(regions), "soundscapeSource.regions order drifted");
  for (const [index, region] of source.regions.entries()) {
    const location = `soundscapeSource.regions[${index}]`;
    exactKeys(region, [
      "id", "timelineID", "soundscapeStateID", "durationSeconds", "loop", "layers", "silenceWindows",
    ], location);
    const scoreRegion = scoreSource.regions[index];
    assert(region.timelineID === scoreRegion.timelineID, `${location}.timelineID: score binding drifted`);
    assert(region.durationSeconds === scoreRegion.durationSeconds, `${location}.durationSeconds: score binding drifted`);
    assert(region.loop === scoreRegion.loop, `${location}.loop: score binding drifted`);
    stableID(region.soundscapeStateID, `${location}.soundscapeStateID`);
    assert(Array.isArray(region.layers) && region.layers.length === 5, `${location}.layers: exact five material layers required`);
    unique(region.layers.map(({ id }) => id), `${location}.layers.id`);
    assert(new Set(region.layers.map(({ id }) => id)).size === grouped.length
      && grouped.every((id) => region.layers.some((layer) => layer.id === id)), `${location}.layers: mix-group coverage drifted`);
    for (const [layerIndex, layer] of region.layers.entries()) {
      const layerLocation = `${location}.layers[${layerIndex}]`;
      exactKeys(layer, ["id", "material", "visibleSource", "generator", "gainDB", "pan", "loop"], layerLocation);
      assert(materialAlgorithms[layer.material] === layer.generator?.algorithm, `${layerLocation}: material generator drifted`);
      assert(typeof layer.visibleSource === "string" && layer.visibleSource.trim(), `${layerLocation}.visibleSource required`);
      assert(layer.loop === region.loop, `${layerLocation}.loop: region binding drifted`);
    }
    assert(Array.isArray(region.silenceWindows) && region.silenceWindows.length > 0, `${location}.silenceWindows required`);
    unique(region.silenceWindows.map(({ id }) => id), `${location}.silenceWindows.id`);
    for (const silence of region.silenceWindows) {
      stableID(silence.id, `${location}.silenceWindows.id`);
      finite(silence.atSeconds, `${location}.silenceWindows.atSeconds`, 0, region.durationSeconds);
      finite(silence.durationSeconds, `${location}.silenceWindows.durationSeconds`, 0.1, region.durationSeconds);
      assert(silence.atSeconds + silence.durationSeconds <= region.durationSeconds, `${location}.silenceWindows: exceeds region`);
      assert(silence.entry === "authored-cut" && silence.exit === "authored-return", `${location}.silenceWindows: transition drifted`);
      assert(typeof silence.reason === "string" && silence.reason.trim(), `${location}.silenceWindows.reason required`);
    }
  }
  return source;
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

function applySilenceWindows(audio, silenceWindows, sampleRate) {
  const fadeFrames = Math.round(sampleRate * 0.012);
  for (const silence of silenceWindows) {
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

function mixAudios(audios) {
  assert(audios.length > 0, "audio mix: at least one source required");
  const frames = audios[0].audio.left.length;
  const mixed = { left: new Float64Array(frames), right: new Float64Array(frames) };
  for (const { audio, gain = 1 } of audios) {
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
  for (const audio of audios) scale(audio, factor);
  scale(mixed, factor);
  return { mixed, factor, peakDBFS: 20 * Math.log10(peak(mixed)) };
}

function verifySilence(audio, silenceWindows, sampleRate, location) {
  for (const silence of silenceWindows) {
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
  const first = 0;
  const last = audio.left.length - 1;
  const leftDelta = Math.abs(audio.left[first] - audio.left[last]);
  const rightDelta = Math.abs(audio.right[first] - audio.right[last]);
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
  const rawName = `.${stem.id}-fluidsynth-raw.wav`;
  const midiPath = path.join(directory, midiName);
  const rawPath = path.join(directory, rawName);
  await writeFile(midiPath, midi);
  const result = spawnSync(fluidSynthPath, [
    "-ni", "-q", "-C", "0", "-R", "0", "-g", "2.5", "-r", "48000",
    "-o", "synth.cpu-cores=1", "-O", "s24", "-T", "wav", "-F", rawPath,
    soundFontPath, midiPath,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    fail(`FluidSynth ${plan.id}/${stem.id}: ${result.stderr?.trim() || result.stdout?.trim() || "render failed"}`);
  }
  const raw = await readFile(rawPath);
  const audio = decodePCM24StereoWAV(raw, targetFrames);
  await rm(rawPath, { force: true });
  return { midi, midiName, midiPath, audio };
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

async function renderScoreRegion(source, region, outputRoot, outputRecords) {
  const directory = path.join(outputRoot, region.id);
  await mkdir(directory, { recursive: true });
  const plan = scorePlan(source, region);
  const targetFrames = Math.round(region.durationSeconds * 48_000);
  const rendered = [];
  const soundRegion = source.__soundscape.regions.find(({ id }) => id === region.id);
  for (const stem of region.stems) {
    const result = await renderFluidStem(plan, stem, directory, targetFrames);
    if (region.loop) applyEdgeFade(result.audio, Math.round(48_000 * 0.4));
    else applyEdgeFade(result.audio, Math.round(48_000 * 0.025));
    applySilenceWindows(result.audio, soundRegion.silenceWindows, 48_000);
    rendered.push({ stem, ...result });
  }
  const normalized = normalizeGroup(rendered.map(({ audio }) => audio), -14);
  for (const item of rendered) {
    const wavName = `score-${item.stem.id}.wav`;
    const wavPath = path.join(directory, wavName);
    const wavRecord = await writeWAV(wavPath, item.audio);
    outputRecords.push(await outputRecord({
      regionID: region.id,
      role: "score-stem-midi",
      sourceID: item.stem.id,
      file: item.midiPath,
      root: outputRoot,
      lineage: "PROJECT_AUTHORED_SYMBOLIC_SCORE",
      rights: "PROJECT_OWNED_SOURCE",
    }));
    outputRecords.push(await outputRecord({
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
  const scoreMaster = normalized.mixed;
  const masterPath = path.join(directory, "score-master.wav");
  const masterRecord = await writeWAV(masterPath, scoreMaster);
  const packageAssetPath = `audio/first-farmers/harvest-responsive-v1/${region.id}/score-master.wav`;
  outputRecords.push(await outputRecord({
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
  return { path: masterPath, packageAssetPath, normalizationGain: normalized.factor };
}

async function renderSoundscapeRegion(source, region, outputRoot, outputRecords) {
  const directory = path.join(outputRoot, region.id);
  await mkdir(directory, { recursive: true });
  const renderedBuffers = renderProceduralSoundscapeLayers(soundscapePlan(source, region));
  const layerAudios = new Map();
  for (const layer of region.layers) {
    const audio = decodePCM24StereoWAV(renderedBuffers.get(layer.id));
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
    outputRecords.push(await outputRecord({
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
  const soundscapePackagePath = `audio/first-farmers/harvest-responsive-v1/${region.id}/soundscape-master.wav`;
  const spatialPackagePath = `audio/first-farmers/harvest-responsive-v1/${region.id}/spatial-detail-master.wav`;
  outputRecords.push(await outputRecord({
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
  outputRecords.push(await outputRecord({
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
  return {
    soundscapePath,
    spatialPath,
    soundscapePackagePath,
    spatialPackagePath,
    soundscapeNormalizationGain: broadNormalized.factor,
    spatialNormalizationGain: spatialNormalized.factor,
  };
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

async function renderPreview(region, assets, outputRoot, outputRecords) {
  const [scoreBytes, soundscapeBytes, spatialBytes] = await Promise.all([
    readFile(assets.score.path), readFile(assets.soundscapePath), readFile(assets.spatialPath),
  ]);
  const score = decodePCM24StereoWAV(scoreBytes);
  const soundscape = decodePCM24StereoWAV(soundscapeBytes);
  const spatial = decodePCM24StereoWAV(spatialBytes);
  const preview = mixAudios([
    { audio: score, gain: timelineGains.score },
    { audio: soundscape, gain: timelineGains.soundscape },
    { audio: spatial, gain: timelineGains.spatialDetail },
  ]);
  verifySilence(preview, region.silenceWindows, 48_000, `${region.id} preview`);
  const seam = region.loop ? verifyLoopSeam(preview, `${region.id} preview`) : null;
  const file = path.join(outputRoot, region.id, "program-preview.wav");
  const record = await writeWAV(file, preview);
  const metrics = analyseWithFFmpeg(file);
  assert(metrics.truePeakDBTP <= -1, `${region.id} preview true peak exceeds -1 dBTP`);
  outputRecords.push(await outputRecord({
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
    inputRecord("harvest-responsive-score-source", scoreSourcePath),
    inputRecord("harvest-responsive-soundscape-source", soundscapeSourcePath),
    inputRecord("harvest-manuscript-source", draftPath),
    inputRecord("harvest-scene-contract", sceneFixturePath),
    inputRecord("native-audio-bible", audioBiblePath),
    inputRecord("responsive-audio-program-spec", responsiveSpecPath),
    inputRecord("responsive-audio-program-runtime", responsiveRuntimePath),
    inputRecord("responsive-audio-program-controller", responsiveControllerPath),
    inputRecord("responsive-audio-timeline-planner", timelinePlaybackPlannerPath),
    inputRecord("responsive-audio-transport-contract", offlineAudioTransportContractPath),
    inputRecord("native-timeline-transport", nativeTimelineTransportPath),
    inputRecord("experience-audio-routing-policy", experienceAudioRoutingPolicyPath),
    inputRecord("experience-preferences-contract", experiencePreferencesContractPath),
    inputRecord("durable-audio-completion-runtime", durableAudioCompletionPath),
    inputRecord("semantic-haptic-runtime", hapticRuntimePath),
    inputRecord("audio-production-renderer", audioRendererPath),
    inputRecord("harvest-responsive-renderer", modulePath),
    inputRecord("score-soundscape-toolchain", toolchainPath),
    inputRecord("required-mit-notice", noticePath),
    inputRecord("zero-cost-license-registry", costRegistryPath),
  ]);
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

function timeline(region, scoreRegion, soundRegion) {
  const durationSamples = Math.round(region.durationSeconds * 48_000);
  const events = [
    {
      cueID: `${region.id}-score-master`, role: "score", startSample: 0, durationSamples,
      assetPath: `audio/first-farmers/harvest-responsive-v1/${region.id}/score-master.wav`,
      gain: timelineGains.score,
    },
    {
      cueID: `${region.id}-soundscape-master`, role: "soundscape", startSample: 0, durationSamples,
      assetPath: `audio/first-farmers/harvest-responsive-v1/${region.id}/soundscape-master.wav`,
      gain: timelineGains.soundscape,
    },
    {
      cueID: `${region.id}-spatial-detail-master`, role: "spatialDetail", startSample: 0, durationSamples,
      assetPath: `audio/first-farmers/harvest-responsive-v1/${region.id}/spatial-detail-master.wav`,
      gain: timelineGains.spatialDetail,
    },
    ...region.silenceWindows.map((silence) => ({
      cueID: `${region.id}-${silence.id}`,
      role: "silence",
      startSample: Math.round(silence.atSeconds * 48_000),
      durationSamples: Math.round(silence.durationSeconds * 48_000),
      assetPath: null,
      gain: 1,
    })),
  ];
  return {
    id: region.timelineID,
    sampleRate: 48_000,
    events,
    haptics: [],
    __scoreStateID: scoreRegion.scoreStateID,
    __soundscapeStateID: soundRegion.soundscapeStateID,
  };
}

function stripAuthoringFields(value) {
  const clone = structuredClone(value);
  for (const item of clone) {
    delete item.__scoreStateID;
    delete item.__soundscapeStateID;
  }
  return clone;
}

async function buildWorkObject({ scoreSource, soundscapeSource, draft, inputs, outputRecords, metrics }) {
  const draftDigest = inputs.find(({ id }) => id === "harvest-manuscript-source").sha256;
  const allocation = draft.arcs.flatMap(({ beats }) => beats)
    .find(({ beatID }) => beatID === "beat-first-farmers-harvest-allocation");
  const consequence = draft.arcs.flatMap(({ beats }) => beats)
    .find(({ beatID }) => beatID === "beat-first-farmers-stored-future");
  assert(allocation && consequence, "Harvest manuscript beats are missing");
  assert(allocation.interaction?.id === "interaction-first-farmers-the-harvest-had-to-last", "Harvest interaction ID drifted");
  assert(JSON.stringify(allocation.interaction.haptics) === JSON.stringify(activeHarvestHaptics), "Harvest haptic subset drifted");

  const authoredTimelines = soundscapeSource.regions.map((region, index) => timeline(
    region,
    scoreSource.regions[index],
    region,
  ));
  const metadata = outputRecords
    .filter(({ packageAssetPath }) => packageAssetPath)
    .map((output) => ({
      path: output.packageAssetPath,
      sampleRate: output.format.sampleRate,
      frameCount: output.format.frames,
      channelCount: output.format.channels,
    }));

  return {
    schemaVersion: 1,
    kind: "responsive-dramatic-audio-work-object",
    id: "harvest-responsive-audio-v1",
    status: "PROVISIONAL_NON_SHIPPING",
    shippingState: "PROHIBITED",
    trustDomain: "BACKSTAGE_AUDIO_PRODUCTION",
    scope: {
      chapterID: "first-farmers",
      arcID: "first-farmers-arc-02",
      beatID: "beat-first-farmers-harvest-allocation",
      interactionID: "interaction-first-farmers-the-harvest-had-to-last",
    },
    responsiveProgram: {
      id: "harvest-responsive-audio-v1",
      scope: {
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-02",
        beatID: "beat-first-farmers-harvest-allocation",
        interactionID: "interaction-first-farmers-the-harvest-had-to-last",
      },
      approachTimelineID: "harvest-approach-v1",
      interactionBeds: [
        {
          phase: "waiting",
          timelineID: "harvest-waiting-bed-v1",
          layerStates: { scoreStateID: "grain-suspended", soundscapeStateID: "field-waiting" },
        },
        {
          phase: "engaged",
          timelineID: "harvest-engaged-bed-v1",
          layerStates: { scoreStateID: "grain-in-motion", soundscapeStateID: "field-engaged" },
        },
        {
          phase: "resistance",
          timelineID: "harvest-resistance-bed-v1",
          layerStates: { scoreStateID: "grain-tension", soundscapeStateID: "field-resistance" },
        },
      ],
      consequenceTimelineID: "harvest-consequence-v1",
      exitPolicy: {
        kind: "bounded-fade",
        durationSamples: 9_600,
      },
    },
    timelines: stripAuthoringFields(authoredTimelines),
    audioAssetMetadata: metadata,
    narrationSlots: [
      manuscriptSlot(
        "harvest-approach-v1",
        "audio/first-farmers/harvest-responsive-v1/approach/narration-selected-master-required.wav",
        allocation,
        draftDigest,
      ),
      manuscriptSlot(
        "harvest-consequence-v1",
        "audio/first-farmers/harvest-responsive-v1/consequence/narration-selected-master-required.wav",
        consequence,
        draftDigest,
      ),
    ],
    hapticProgram: {
      vocabulary: canonicalHaptics,
      activeHarvestSemantics: activeHarvestHaptics,
      reservedForOtherGrammars: ["drag", "break"],
      runtimeBindings: [
        { trigger: "interaction-begin", semantic: "contact", durableCommitRequired: false },
        { trigger: "allocation-rejected", semantic: "resistance", durableCommitRequired: false },
        { trigger: "allocation-progress", semantic: "transfer", durableCommitRequired: false },
        { trigger: "durable-completion", semantic: "seal", durableCommitRequired: true }
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

async function pinnedRuntime(toolchain) {
  await validateAudioRendererRuntime({ toolchain, soundFontPath, fluidSynthPath });
  const ffmpeg = await hashFile(ffmpegPath).catch(() => fail("ffmpeg runtime missing"));
  assert(ffmpeg.sha256 === toolchain.ffmpeg.installedBinarySHA256, "ffmpeg binary hash drifted");
  const ffmpegVersion = spawnSync(ffmpegPath, ["-version"], { encoding: "utf8" });
  assert(ffmpegVersion.status === 0 && ffmpegVersion.stdout.includes(`ffmpeg version ${toolchain.ffmpeg.version}`), "ffmpeg version drifted");
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

async function validateZeroCostRegistry(registry) {
  const entries = new Map((registry.entries ?? []).map((entry) => [entry.id, entry]));
  for (const id of [
    "fluid-synth-local",
    "musescore-ms-basic-sf3",
    "audio-production-local",
    "harvest-responsive-audio-production",
    "authored-score-rendering",
    "soundscape-generation",
  ]) {
    const entry = entries.get(id);
    assert(entry, `zero-cost registry is missing '${id}'`);
    assert(entry.incrementalCostNOK === 0, `${id}: incremental cost must remain zero`);
    assert(entry.billingCredentialRequired === false, `${id}: billing credentials are forbidden`);
    assert(entry.commercialUse === "allowed", `${id}: commercial use must be explicit`);
    assert(typeof entry.license === "string" && entry.license.trim(), `${id}: licence record required`);
    assert(typeof entry.source === "string" && entry.source.trim(), `${id}: source record required`);
  }
  const renderer = await hashFile(modulePath);
  assert(
    entries.get("harvest-responsive-audio-production").version
      === `1; renderer SHA-256 ${renderer.sha256}`,
    "harvest responsive renderer cost/version binding drifted",
  );
}

async function readSources() {
  const [scoreBytes, soundscapeBytes, draftBytes, toolchainBytes, costBytes] = await Promise.all([
    readFile(scoreSourcePath), readFile(soundscapeSourcePath), readFile(draftPath), readFile(toolchainPath),
    readFile(costRegistryPath),
  ]);
  const scoreSource = validateScoreSource(JSON.parse(scoreBytes));
  const soundscapeSource = validateSoundscapeSource(JSON.parse(soundscapeBytes), scoreSource);
  const draft = JSON.parse(draftBytes);
  const toolchain = validateAudioToolchain(JSON.parse(toolchainBytes));
  await validateZeroCostRegistry(JSON.parse(costBytes));
  scoreSource.__soundscape = soundscapeSource;
  return { scoreSource, soundscapeSource, draft, toolchain };
}

async function renderAll(outputRoot) {
  const { scoreSource, soundscapeSource, draft, toolchain } = await readSources();
  const inputs = await productionInputs();
  const runtime = await pinnedRuntime(toolchain);
  await mkdir(outputRoot, { recursive: true });
  const outputRecords = [];
  const metrics = {};
  for (const regionID of regions) {
    const scoreRegion = scoreSource.regions.find(({ id }) => id === regionID);
    const soundRegion = soundscapeSource.regions.find(({ id }) => id === regionID);
    const score = await renderScoreRegion(scoreSource, scoreRegion, outputRoot, outputRecords);
    const sound = await renderSoundscapeRegion(soundscapeSource, soundRegion, outputRoot, outputRecords);
    metrics[regionID] = await renderPreview(soundRegion, { score, ...sound }, outputRoot, outputRecords);
  }
  outputRecords.sort((left, right) => left.path.localeCompare(right.path));
  const finalInputs = await productionInputs();
  assert(
    JSON.stringify(inputs) === JSON.stringify(finalInputs),
    "production inputs changed during the offline render",
  );
  const workObject = await buildWorkObject({
    scoreSource, soundscapeSource, draft, inputs, outputRecords, metrics,
  });
  return { workObject, outputRecords, inputs, runtime };
}

function outputIdentity(outputs) {
  return outputs.map(({ path: outputPath, bytes, sha256: digest, format }) => ({
    path: outputPath,
    bytes,
    sha256: digest,
    ...(format ? { format } : {}),
  }));
}

export async function renderHarvestResponsiveAudio({ verifyReproducibility = true } = {}) {
  await rm(cacheRoot, { recursive: true, force: true });
  const first = await renderAll(cacheRoot);
  let reproducibility = "NOT_RUN";
  if (verifyReproducibility) {
    const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-harvest-responsive-"));
    try {
      const second = await renderAll(temporary);
      assert(
        JSON.stringify(outputIdentity(first.outputRecords)) === JSON.stringify(outputIdentity(second.outputRecords)),
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
    id: "harvest-responsive-audio-render-v1",
    status: "PROVISIONAL_NON_SHIPPING",
    shippingState: "PROHIBITED",
    productionInputs: first.inputs,
    toolchain: first.runtime,
    outputs: first.outputRecords,
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
  await validateHarvestResponsiveAudio();
  return { workObject: first.workObject, receipt };
}

function validateWorkObject(work, scoreSource, soundscapeSource) {
  assert(work.schemaVersion === 1 && work.kind === "responsive-dramatic-audio-work-object", "work object identity drifted");
  assert(work.status === "PROVISIONAL_NON_SHIPPING" && work.shippingState === "PROHIBITED", "work object approval boundary drifted");
  assert(work.trustDomain === "BACKSTAGE_AUDIO_PRODUCTION", "work object trust domain drifted");
  assert(work.responsiveProgram.id === work.id, "responsive program identity drifted");
  assert(work.responsiveProgram.approachTimelineID === "harvest-approach-v1", "approach timeline drifted");
  assert(work.responsiveProgram.consequenceTimelineID === "harvest-consequence-v1", "consequence timeline drifted");
  assert(JSON.stringify(work.responsiveProgram.exitPolicy) === JSON.stringify({
    kind: "bounded-fade",
    durationSamples: 9_600,
  }), "authored exit policy drifted");
  assert(JSON.stringify(work.responsiveProgram.interactionBeds.map(({ phase }) => phase))
    === JSON.stringify(["waiting", "engaged", "resistance"]), "responsive bed phase set drifted");
  const timelineIDs = work.timelines.map(({ id }) => id);
  unique(timelineIDs, "work.timelines.id");
  assert(timelineIDs.length === 5, "work.timelines: exact five authored regions required");
  for (const timeline of work.timelines) {
    assert(timeline.sampleRate === 48_000, `${timeline.id}: 48 kHz required`);
    assert(Array.isArray(timeline.events) && timeline.events.length >= 4, `${timeline.id}: score, soundscape, spatial and silence required`);
    assert(timeline.haptics.length === 0, `${timeline.id}: timed haptics must not bypass semantic runtime commits`);
    const roles = new Set(timeline.events.map(({ role }) => role));
    for (const role of ["score", "soundscape", "spatialDetail", "silence"]) {
      assert(roles.has(role), `${timeline.id}: missing ${role}`);
    }
    assert(!roles.has("narration"), `${timeline.id}: unselected narration was inserted`);
  }
  const bedDurations = work.responsiveProgram.interactionBeds.map(({ timelineID }) => {
    const timeline = work.timelines.find(({ id }) => id === timelineID);
    return Math.max(...timeline.events.map(({ startSample, durationSamples }) => startSample + durationSamples));
  });
  assert(new Set(bedDurations).size === 1 && bedDurations[0] === 720_000, "phase beds are not sample-identical 15-second loops");
  assert(JSON.stringify(work.hapticProgram.vocabulary) === JSON.stringify(canonicalHaptics), "canonical haptic vocabulary drifted");
  assert(JSON.stringify(work.hapticProgram.activeHarvestSemantics) === JSON.stringify(activeHarvestHaptics), "Harvest haptic subset drifted");
  assert(work.hapticProgram.runtimeBindings.find(({ semantic }) => semantic === "seal")?.durableCommitRequired === true, "seal escaped durable completion");
  assert(work.narrationSlots.length === 2
    && work.narrationSlots.every(({ status, shippingBlock }) => status === "MISSING_EDITOR_SELECTED_NARRATION_MASTER" && shippingBlock), "narration placeholders drifted");
  assert(work.provenance.incrementalCostNOK === 0, "work object introduced incremental cost");
  assert(work.gates.artisticApproval === "OPEN" && work.gates.shippingApproval === "PROHIBITED", "work object fabricated approval");
  assert(scoreSource.regions.length === soundscapeSource.regions.length, "source region mismatch");
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
      const region = output.regionID;
      const expectedFrames = Math.round((region === "approach" ? 60 : region === "consequence" ? 50 : 15) * 48_000);
      assert(format.frames === expectedFrames, `${output.path}: exact frame duration drifted`);
    }
  }
  assert(receipt.reproducibility === "PASS_SECOND_COMPLETE_OFFLINE_RENDER", "receipt lacks complete second-render proof");
}

export async function validateHarvestResponsiveAudio() {
  const { scoreSource, soundscapeSource, toolchain } = await readSources();
  const [workBytes, receiptBytes] = await Promise.all([
    readFile(workObjectPath), readFile(receiptPath),
  ]).catch(() => fail("Harvest responsive work object and receipt are required"));
  const work = JSON.parse(workBytes);
  const receipt = JSON.parse(receiptBytes);
  validateWorkObject(work, scoreSource, soundscapeSource);
  assert(receipt.status === "PROVISIONAL_NON_SHIPPING" && receipt.shippingState === "PROHIBITED", "receipt approval boundary drifted");
  const expectedInputs = await productionInputs();
  assert(JSON.stringify(receipt.productionInputs) === JSON.stringify(expectedInputs), "receipt production inputs drifted");
  assert(JSON.stringify(work.provenance.productionInputs) === JSON.stringify(expectedInputs), "work provenance inputs drifted");
  await pinnedRuntime(toolchain);
  await validateOutputs(receipt);
  const outputByPackagePath = new Map(receipt.outputs.filter(({ packageAssetPath }) => packageAssetPath)
    .map((output) => [output.packageAssetPath, output]));
  assert(outputByPackagePath.size === 15, "exact fifteen runtime masters required");
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

export const harvestResponsiveAudioPaths = Object.freeze({
  repositoryRoot,
  sourceRoot,
  cacheRoot,
  scoreSourcePath,
  soundscapeSourcePath,
  workObjectPath,
  receiptPath,
});
