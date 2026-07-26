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
const sourceRoot = path.join(audioRoot, "three-records-responsive-v1");
const cacheRoot = path.join(audioRoot, "cache/three-records-responsive-v1");
const scoreSourcePath = path.join(sourceRoot, "score-source.json");
const soundscapeSourcePath = path.join(sourceRoot, "soundscape-source.json");
const workObjectPath = path.join(sourceRoot, "three-records-responsive-work-object.json");
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
const contentPackagePayloadPath = path.join(
  repositoryRoot,
  "native/ios/Sources/ContentKit/ContentPackagePayload.swift",
);
const sceneAudioAccessibilityPath = path.join(
  repositoryRoot,
  "native/ios/Sources/ContentKit/SceneAudioAccessibility.swift",
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
const journeyReducerPath = path.join(
  repositoryRoot,
  "native/ios/Sources/JourneyDomain/JourneyReducer.swift",
);
const responsiveRuntimeTestsPath = path.join(
  repositoryRoot,
  "native/ios/Tests/DramaticAudioTests/ResponsiveAudioProgramRuntimeTests.swift",
);
const nativeCausalTransportTestsPath = path.join(
  repositoryRoot,
  "native/ios/Tests/DramaticAudioTests/ExperienceAudioRoutingPolicyTests.swift",
);
const threeRecordsSwiftTestsPath = path.join(
  repositoryRoot,
  "native/ios/Tests/DramaticAudioTests/ThreeRecordsResponsiveAudioWorkObjectTests.swift",
);
const journeyDomainTestsPath = path.join(
  repositoryRoot,
  "native/ios/Tests/JourneyDomainTests/JourneyDomainTests.swift",
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
const publicValidatorPath = path.join(
  repositoryRoot,
  "native/tooling/src/validate.mjs",
);
const publicContentSchemaPath = path.join(
  repositoryRoot,
  "native/schemas/public-content.schema.json",
);
const publicValidatorTestsPath = path.join(
  repositoryRoot,
  "native/tooling/test/tooling.test.mjs",
);

const fluidSynthPath = "/opt/homebrew/bin/fluidsynth";
const ffmpegPath = "/opt/homebrew/bin/ffmpeg";
const regions = ["approach", "waiting", "engaged", "resistance", "consequence"];
const loopRegions = new Set(["waiting", "engaged", "resistance"]);
const regionDurations = new Map([
  ["approach", 45],
  ["waiting", 15],
  ["engaged", 15],
  ["resistance", 15],
  ["consequence", 45],
]);
const timelineGains = { score: 0.72, soundscape: 0.82, spatialDetail: 0.9 };
const canonicalHaptics = ["contact", "drag", "resistance", "transfer", "break", "seal"];
const activeThreeRecordsHaptics = ["drag", "break", "seal"];
const routeStages = [
  { id: "river-communities", requiredAmount: 0.33 },
  { id: "contact-households", requiredAmount: 0.66 },
  { id: "later-settlements", requiredAmount: 1 },
];
const scoreStates = new Map([
  ["approach", "river-and-records-gather"],
  ["waiting", "river-record-held"],
  ["engaged", "records-move-through-time"],
  ["resistance", "time-layer-does-not-take"],
  ["consequence", "farming-enters-river-route"],
]);
const soundscapeStates = new Map([
  ["approach", "gorge-before-action"],
  ["waiting", "river-community-record-waits"],
  ["engaged", "time-layers-in-motion"],
  ["resistance", "same-gorge-refuses-false-layer"],
  ["consequence", "shared-river-settlement"],
]);
const silenceSamples = new Map([
  ["approach", { startSample: 0, durationSamples: 96_000 }],
  ["waiting", { startSample: 710_400, durationSamples: 9_600 }],
  ["engaged", { startSample: 710_400, durationSamples: 9_600 }],
  ["resistance", { startSample: 710_400, durationSamples: 9_600 }],
  ["consequence", { startSample: 0, durationSamples: 144_000 }],
]);
const materialLayerIDs = [
  "gorge-current",
  "river-gear",
  "landing-work",
  "settlement-hearths",
  "carried-grain",
  "domestic-herd",
  "household-voices",
];
const broadLayerIDs = [
  "gorge-current", "landing-work", "settlement-hearths", "domestic-herd", "household-voices",
];
const spatialLayerIDs = ["river-gear", "carried-grain"];
const interactionRegions = ["waiting", "engaged", "resistance"];
const packageRoot = "audio/first-farmers/three-records-responsive-v1";
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
  assert(source.meter?.numerator === 5 && source.meter?.denominator === 4, "scoreSource.meter: authored 5/4 required");
  assert(source.tempoBPM === 60, "scoreSource.tempoBPM: authored 60 BPM required");
  assert(typeof source.direction === "string" && source.direction.trim(), "scoreSource.direction required");
  assert(JSON.stringify(source.motifs?.map(({ id }) => id)) === JSON.stringify([
    "earth-fifth",
    "river-return",
    "river-record",
    "contact-record",
    "settlement-record",
    "resistance-knot",
    "returning-field",
  ]), "scoreSource.motifs: exact Three Records vocabulary required");
  assert(!source.motifs.some(({ id }) => id === "farming-belt-held"), "scoreSource.motifs: Continent Remade culmination is forbidden here");
  assert(JSON.stringify(source.prohibitedClaims) === JSON.stringify([
    "pseudo-Neolithic musical reconstruction",
    "primitive drums, flutes or chanting",
    "martial or triumphal scoring",
    "identical timing for all three records",
    "exact calendar meaning for interaction thresholds",
    "score tones represented as archaeological evidence",
  ]), "scoreSource prohibited claims drifted");
  assert(JSON.stringify(source.motifs.map(({ id, notes }) => ({ id, pitches: notes.map(({ pitch }) => pitch) }))) === JSON.stringify([
    { id: "earth-fifth", pitches: ["D2", "A2"] },
    { id: "river-return", pitches: ["D3", "E3", "D3"] },
    { id: "river-record", pitches: ["D4"] },
    { id: "contact-record", pitches: ["F4"] },
    { id: "settlement-record", pitches: ["A4"] },
    { id: "resistance-knot", pitches: ["Eb3", "D3"] },
    { id: "returning-field", pitches: ["D4", "E4", "F4", "A4"] },
  ]), "scoreSource motif pitches drifted");
  unique(source.motifs.map(({ id }) => id), "scoreSource.motifs.id");
  assert(JSON.stringify(source.regions?.map(({ id }) => id)) === JSON.stringify(regions), "scoreSource.regions order drifted");
  for (const region of source.regions) {
    stableID(region.timelineID, `${region.id}.timelineID`);
    stableID(region.scoreStateID, `${region.id}.scoreStateID`);
    assert(region.scoreStateID === scoreStates.get(region.id), `${region.id}: score state drifted`);
    assert(region.durationSeconds === regionDurations.get(region.id), `${region.id}: duration drifted`);
    assert(region.loop === loopRegions.has(region.id), `${region.id}: loop binding drifted`);
    assert(Array.isArray(region.stems) && region.stems.length === 3, `${region.id}: exact three editable score stems required`);
    const expectedInstruments = [
      { id: "ground", program: 43, label: "Contrabass" },
      { id: "river-route", program: 42, label: "Cello" },
      region.id === "resistance"
        ? { id: "record", program: 70, label: "Bassoon" }
        : { id: "record", program: 15, label: "Dulcimer" },
    ];
    assert(JSON.stringify(region.stems.map(({ id, instrument }) => ({
      id, program: instrument?.program, label: instrument?.label,
    }))) === JSON.stringify(expectedInstruments), `${region.id}: exact Three Records stem contract drifted`);
    const resistancePhrases = region.stems.flatMap(({ phrases }) => phrases)
      .filter(({ motifID }) => motifID === "resistance-knot");
    assert(region.id === "resistance" ? resistancePhrases.length > 0 : resistancePhrases.length === 0,
      `${region.id}: Bassoon resistance-knot boundary drifted`);
    const returningFieldPhrases = region.stems.flatMap(({ phrases }) => phrases)
      .filter(({ motifID }) => motifID === "returning-field");
    assert(region.id === "consequence" ? returningFieldPhrases.length > 0 : returningFieldPhrases.length === 0,
      `${region.id}: returning-field may enter only in consequence`);
    unique(region.stems.map(({ id }) => id), `${region.id}.stems.id`);
    validateScoreProductionPlan(scorePlan(source, region));
  }
  return source;
}

function validateCausalMixContract(contract) {
  assert(contract?.schemaVersion === 1, "causalMixContract.schemaVersion drifted");
  assert(contract.gainUnit === "linear", "causalMixContract.gainUnit drifted");
  assert(contract.rampDurationSamples === 9_600, "causalMixContract ramp must be exactly 200 ms");
  assert([
    "OPEN_NOT_APPLIED_TO_TIMELINE_SLICES",
    "PASS_COMMON_PLAYER_SAMPLE_TIME_GAIN_RAMPS",
  ].includes(contract.transportStatus), "causalMixContract transport status drifted");
  assert(contract.cueIDPattern === "{regionID}-{layerID}", "causalMixContract cue pattern drifted");
  assert(JSON.stringify(contract.interactionLayerAssets?.map(({ layerID, role, assetPath }) => ({
    layerID, role, assetPath,
  }))) === JSON.stringify(materialLayerIDs.map((layerID) => ({
    layerID,
    role: spatialLayerIDs.includes(layerID) ? "spatialDetail" : "soundscape",
    assetPath: `${packageRoot}/interaction/shared/${layerID}.wav`,
  }))), "causalMixContract shared 7-asset binding drifted");
  const expectedStates = [
    { completedStageCount: 0, stateID: "river-only", stageID: "before-river-communities", gains: [0.82, 0, 0, 0, 0, 0, 0] },
    { completedStageCount: 1, stateID: "river-communities-present", stageID: "river-communities", gains: [0.82, 0.32, 0.28, 0.18, 0, 0, 0.14] },
    { completedStageCount: 2, stateID: "contact-households-present", stageID: "contact-households", gains: [0.82, 0.42, 0.38, 0.28, 0.3, 0.24, 0.34] },
    { completedStageCount: 3, stateID: "later-settlements-present", stageID: "later-settlements", gains: [0.82, 0.48, 0.44, 0.34, 0.4, 0.32, 0.42] },
  ];
  assert(contract.states?.length === expectedStates.length, "causalMixContract requires four states");
  for (const [index, expected] of expectedStates.entries()) {
    const state = contract.states[index];
    assert(state.completedStageCount === expected.completedStageCount
      && state.stateID === expected.stateID
      && state.stageID === expected.stageID, `causalMixContract.states[${index}] identity drifted`);
    assert(JSON.stringify(state.layerGains?.map(({ layerID, gain }) => ({ layerID, gain })))
      === JSON.stringify(materialLayerIDs.map((layerID, gainIndex) => ({ layerID, gain: expected.gains[gainIndex] }))),
    `causalMixContract.states[${index}] gains drifted`);
    if (index > 0) {
      const previous = contract.states[index - 1].layerGains;
      state.layerGains.forEach(({ layerID, gain }, gainIndex) => {
        assert(layerID === previous[gainIndex].layerID && gain >= previous[gainIndex].gain,
          `causalMixContract '${layerID}' regressed at stage ${state.completedStageCount}`);
      });
    }
  }
  assert(contract.states.every(({ layerGains }) => layerGains[0].gain === 0.82), "gorge current must remain constant");
  assert(JSON.stringify(contract.consequenceState) === JSON.stringify({
    stateID: "later-settlements-retained", inheritsCompletedStageCount: 3,
  }), "causalMixContract consequence inheritance drifted");
  assert(contract.monotonicRule === "COMPLETED_LAYER_GAINS_NEVER_DECREASE_OR_DISAPPEAR", "causalMixContract monotonic rule drifted");
}

function validateSoundscapeSource(source, scoreSource) {
  assert(source?.schemaVersion === 1, "soundscapeSource.schemaVersion: 1 required");
  assert(source.kind === "responsive-procedural-soundscape", "soundscapeSource.kind drifted");
  stableID(source.id, "soundscapeSource.id");
  assert(source.status === "PROVISIONAL_NON_SHIPPING", "soundscapeSource.status drifted");
  assert(source.shippingState === "PROHIBITED", "soundscapeSource.shippingState drifted");
  validateOutput(source.output, "soundscapeSource.output");
  assert(JSON.stringify(source.mixGroups) === JSON.stringify({
    soundscape: broadLayerIDs,
    spatialDetail: spatialLayerIDs,
  }), "soundscapeSource.mixGroups drifted");
  assert(source.synthesisBoundaries?.water?.algorithm === "close-water-movement-v1", "water synthesis boundary drifted");
  assert(source.synthesisBoundaries?.human?.algorithm === "distant-human-presence-v1", "human synthesis boundary drifted");
  assert(source.synthesisBoundaries?.animal?.algorithm === "herd-ground-movement-v1", "animal synthesis boundary drifted");
  assert(JSON.stringify(source.scopedQuietPolicy) === JSON.stringify({
    preservedSoundscapeLayerID: "gorge-current",
    zeroedRoles: ["score", "spatialDetail"],
    zeroedSoundscapeLayerIDs: ["landing-work", "settlement-hearths", "domestic-herd", "household-voices"],
    timelineEventRole: "NONE_SCOPED_QUIET_IS_NOT_GLOBAL_SILENCE",
    loopTailRule: "FINAL_200_MS_ZEROES_EVERY_NON_RIVER_LAYER_WHILE_GORGE_CURRENT_REMAINS_SAMPLE_CONTINUOUS",
  }), "scoped quiet policy drifted");
  assert(JSON.stringify(source.prohibitedClaims) === JSON.stringify([
    "sudden replacement of river communities",
    "identical timing for all records",
    "universal adoption of farming",
    "exact calendar meaning for interaction thresholds",
    "invented dialogue, language or ethnic vocal timbre",
    "species calls, bells, tack or panic",
    "metal tools or martial conflict",
    "primitive drums, flutes or chanting",
    "academic evidence mode",
  ]), "soundscapeSource prohibited claims drifted");
  validateCausalMixContract(source.causalMixContract);
  assert(JSON.stringify(source.nonRenderedRegionIDs) === JSON.stringify(interactionRegions), "non-rendered phase source list drifted");
  assert(JSON.stringify(source.regions?.map(({ id }) => id)) === JSON.stringify(regions), "soundscapeSource.regions order drifted");
  for (const [index, region] of source.regions.entries()) {
    const scoreRegion = scoreSource.regions[index];
    assert(region.timelineID === scoreRegion.timelineID, `${region.id}: score timeline binding drifted`);
    assert(region.durationSeconds === scoreRegion.durationSeconds, `${region.id}: score duration binding drifted`);
    assert(region.loop === scoreRegion.loop, `${region.id}: score loop binding drifted`);
    stableID(region.soundscapeStateID, `${region.id}.soundscapeStateID`);
    assert(region.soundscapeStateID === soundscapeStates.get(region.id), `${region.id}: soundscape state drifted`);
    assert(region.layers?.length === 7, `${region.id}: exact seven source-bound layers required`);
    assert(JSON.stringify(region.layers.map(({ id, material, generator }) => ({
      id, material, algorithm: generator?.algorithm,
    }))) === JSON.stringify([
      { id: "gorge-current", material: "water", algorithm: "close-water-movement-v1" },
      { id: "river-gear", material: "textile", algorithm: "woven-fibre-friction-v1" },
      { id: "landing-work", material: "work", algorithm: "distant-material-work-v1" },
      { id: "settlement-hearths", material: "fire", algorithm: "small-hearth-fire-v1" },
      { id: "carried-grain", material: "grain", algorithm: "dry-grain-contact-v1" },
      { id: "domestic-herd", material: "herd", algorithm: "herd-ground-movement-v1" },
      { id: "household-voices", material: "human", algorithm: "distant-human-presence-v1" },
    ]), `${region.id}: exact causal material contract drifted`);
    assert(region.silenceWindows?.length === 1, `${region.id}: one named silence window required`);
    assert(JSON.stringify({
      startSample: Math.round(region.silenceWindows[0].atSeconds * 48_000),
      durationSamples: Math.round(region.silenceWindows[0].durationSeconds * 48_000),
    }) === JSON.stringify(silenceSamples.get(region.id)), `${region.id}: exact authored silence sample contract drifted`);
    validateSoundscapeProductionPlan(soundscapePlan(source, region));
  }
  const shared = source.interactionMaterialLoop;
  assert(shared?.id === "interaction-material-loop"
    && shared.soundscapeStateID === "shared-time-layer-material-clock"
    && shared.durationSeconds === 15
    && shared.loop === true, "shared interaction material loop identity drifted");
  assert(JSON.stringify(shared.layers?.map(({ id }) => id)) === JSON.stringify(materialLayerIDs), "shared material layer order drifted");
  assert(JSON.stringify({
    startSample: Math.round(shared.silenceWindows?.[0]?.atSeconds * 48_000),
    durationSamples: Math.round(shared.silenceWindows?.[0]?.durationSeconds * 48_000),
  }) === JSON.stringify(silenceSamples.get("waiting")), "shared loop tail quiet drifted");
  validateSoundscapeProductionPlan(soundscapePlan(source, shared));
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

async function renderFiniteSoundscapeRegion(source, region, outputRoot, outputs) {
  assert(!region.loop && ["approach", "consequence"].includes(region.id), `${region.id}: finite soundscape required`);
  const directory = path.join(outputRoot, region.id);
  await mkdir(directory, { recursive: true });
  const buffers = renderProceduralSoundscapeLayers(soundscapePlan(source, region));
  const layerAudios = new Map();
  for (const layer of region.layers) {
    const audio = decodePCM24StereoWAV(buffers.get(layer.id));
    if (layer.id !== source.scopedQuietPolicy.preservedSoundscapeLayerID) {
      applySilenceWindows(audio, region.silenceWindows, 48_000);
    }
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
  verifySilence(spatialNormalized.mixed, region.silenceWindows, 48_000, `${region.id} spatial detail`);
  const current = layerAudios.get("gorge-current");
  const currentWindow = silenceSamples.get(region.id);
  assert(peak({
    left: current.left.slice(currentWindow.startSample, currentWindow.startSample + currentWindow.durationSamples),
    right: current.right.slice(currentWindow.startSample, currentWindow.startSample + currentWindow.durationSamples),
  }) > 0, `${region.id}: gorge current vanished during scoped quiet`);
  for (let frame = currentWindow.startSample; frame < currentWindow.startSample + currentWindow.durationSamples; frame += 1) {
    assert(broadNormalized.mixed.left[frame] === current.left[frame]
      && broadNormalized.mixed.right[frame] === current.right[frame], `${region.id}: broad mix is not river-only during scoped quiet`);
  }
  const afterQuiet = currentWindow.startSample + currentWindow.durationSamples;
  for (const layerID of materialLayerIDs) {
    const audio = layerAudios.get(layerID);
    assert(peak({ left: audio.left.slice(afterQuiet), right: audio.right.slice(afterQuiet) }) > 0,
      `${region.id}/${layerID}: authored material never enters after scoped quiet`);
  }
  return { soundscapePath, spatialPath, layerAudios };
}

async function renderSharedInteractionMaterialLoop(source, outputRoot, outputs) {
  const region = source.interactionMaterialLoop;
  const directory = path.join(outputRoot, "interaction", "shared");
  await mkdir(directory, { recursive: true });
  const buffers = renderProceduralSoundscapeLayers(soundscapePlan(source, region));
  const layerAudios = new Map();
  for (const layer of region.layers) {
    const audio = decodePCM24StereoWAV(buffers.get(layer.id));
    makePeriodic(audio);
    if (layer.id === source.scopedQuietPolicy.preservedSoundscapeLayerID) {
      const last = audio.left.length - 1;
      audio.left[last] = audio.left[0];
      audio.right[last] = audio.right[0];
    } else {
      applyEdgeFade(audio, Math.round(48_000 * 0.03));
      applySilenceWindows(audio, region.silenceWindows, 48_000);
      verifySilence(audio, region.silenceWindows, 48_000, `shared ${layer.id}`);
      assert(peak({
        left: audio.left.slice(0, silenceSamples.get("waiting").startSample),
        right: audio.right.slice(0, silenceSamples.get("waiting").startSample),
      }) > 0, `shared ${layer.id}: material loop is silent before the scoped tail`);
    }
    layerAudios.set(layer.id, audio);
  }
  normalizeGroup(source.mixGroups.soundscape.map((id) => layerAudios.get(id)), -18);
  normalizeGroup(source.mixGroups.spatialDetail.map((id) => layerAudios.get(id)), -16);
  const layerPaths = new Map();
  for (const layer of region.layers) {
    const file = path.join(directory, `${layer.id}.wav`);
    const wavRecord = await writeWAV(file, layerAudios.get(layer.id));
    const packageAssetPath = `${packageRoot}/interaction/shared/${layer.id}.wav`;
    outputs.push(await outputRecord({
      regionID: region.id,
      role: source.mixGroups.soundscape.includes(layer.id) ? "interaction-soundscape-layer-master" : "interaction-spatial-layer-master",
      sourceID: layer.id,
      file,
      root: outputRoot,
      packageAssetPath,
      lineage: "PROJECT_AUTHORED_PROCEDURAL_AUDIO",
      rights: "PROJECT_OWNED_SOURCE_AND_OUTPUT",
      format: wavRecord.format,
    }));
    layerPaths.set(layer.id, file);
  }
  const current = layerAudios.get("gorge-current");
  const tail = silenceSamples.get("waiting");
  assert(peak({
    left: current.left.slice(tail.startSample),
    right: current.right.slice(tail.startSample),
  }) > 0, "shared gorge current vanished during loop-tail quiet");
  const seam = verifyLoopSeam(current, "shared gorge current");
  assert(seam.leftDelta === 0 && seam.rightDelta === 0, "shared gorge current is not sample-continuous at loop joint");
  return { layerPaths, layerAudios, seam };
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

async function writePreview(region, preview, outputRoot, outputs, seam = null) {
  const ceiling = 10 ** (-2 / 20);
  const previewPeak = peak(preview);
  if (previewPeak > ceiling) scale(preview, ceiling / previewPeak);
  const file = path.join(outputRoot, region.id, "program-preview.wav");
  await mkdir(path.dirname(file), { recursive: true });
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

async function renderFinitePreview(region, score, sound, outputRoot, outputs) {
  const [scoreBytes, soundscapeBytes, spatialBytes] = await Promise.all([
    readFile(score.path), readFile(sound.soundscapePath), readFile(sound.spatialPath),
  ]);
  const preview = mixAudios([
    { audio: decodePCM24StereoWAV(scoreBytes), gain: timelineGains.score },
    { audio: decodePCM24StereoWAV(soundscapeBytes), gain: timelineGains.soundscape },
    { audio: decodePCM24StereoWAV(spatialBytes), gain: timelineGains.spatialDetail },
  ]);
  return writePreview(region, preview, outputRoot, outputs);
}

async function renderInteractionPreview(region, score, shared, causalMixContract, outputRoot, outputs) {
  const scoreAudio = decodePCM24StereoWAV(await readFile(score.path));
  const completed = causalMixContract.states.at(-1);
  const items = [{ audio: scoreAudio, gain: timelineGains.score }];
  for (const { layerID, gain } of completed.layerGains) {
    items.push({ audio: shared.layerAudios.get(layerID), gain });
  }
  const preview = mixAudios(items);
  const seam = verifyLoopSeam(preview, `${region.id} preview`);
  return writePreview(region, preview, outputRoot, outputs, seam);
}

async function productionInputs() {
  return Promise.all([
    inputRecord("three-records-responsive-score-source", scoreSourcePath),
    inputRecord("three-records-responsive-soundscape-source", soundscapeSourcePath),
    inputRecord("first-farmers-manuscript-source", draftPath),
    inputRecord("native-audio-bible", audioBiblePath),
    inputRecord("responsive-audio-program-spec", responsiveSpecPath),
    inputRecord("responsive-audio-content-payload", contentPackagePayloadPath),
    inputRecord("native-audio-timeline-validation", sceneAudioAccessibilityPath),
    inputRecord("responsive-audio-program-runtime", responsiveRuntimePath),
    inputRecord("responsive-audio-program-controller", responsiveControllerPath),
    inputRecord("responsive-audio-timeline-planner", timelinePlannerPath),
    inputRecord("responsive-audio-transport-contract", offlineResolverPath),
    inputRecord("native-timeline-transport", nativeTransportPath),
    inputRecord("durable-audio-completion-runtime", durableCompletionPath),
    inputRecord("semantic-haptic-runtime", hapticRuntimePath),
    inputRecord("causal-stage-journey-reducer", journeyReducerPath),
    inputRecord("responsive-audio-runtime-tests", responsiveRuntimeTestsPath),
    inputRecord("native-causal-transport-tests", nativeCausalTransportTestsPath),
    inputRecord("three-records-responsive-swift-tests", threeRecordsSwiftTestsPath),
    inputRecord("causal-stage-journey-domain-tests", journeyDomainTestsPath),
    inputRecord("audio-production-renderer", audioRendererPath),
    inputRecord("three-records-responsive-renderer", modulePath),
    inputRecord("score-soundscape-toolchain", toolchainPath),
    inputRecord("required-mit-notice", noticePath),
    inputRecord("zero-cost-license-registry", costRegistryPath),
    inputRecord("shipping-public-content-validator", publicValidatorPath),
    inputRecord("shipping-public-content-schema", publicContentSchemaPath),
    inputRecord("shipping-public-content-validator-tests", publicValidatorTestsPath),
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

export async function validateThreeRecordsResponsiveAudioSources() {
  const { scoreSource, soundscapeSource, draft } = await readSources();
  const transformation = findBeat(draft, "beat-first-farmers-three-records");
  assert(transformation?.interaction?.grammar === "transform", "Three Records source lost its Transform mechanism");
  assert(transformation.interaction.id === "interaction-first-farmers-at-the-iron-gates", "Three Records interaction ID drifted");
  assert(JSON.stringify(transformation.interaction.stages) === JSON.stringify(routeStages.map(({ id, requiredAmount }) => ({
    id,
    controlID: "time-layer",
    requiredAmount,
  }))), "Three Records stage contract drifted");
  assert(JSON.stringify(transformation.interaction.haptics) === JSON.stringify(activeThreeRecordsHaptics), "Three Records haptic subset drifted");
  assert(transformation.interaction.completionEffectID === "effect-first-farmers-at-the-iron-gates", "Three Records completion effect drifted");
  assert(transformation.interaction.causalContract?.persistentTrace === "trace-european-farming-belt", "Three Records persistent trace drifted");
  return {
    scoreSourceID: scoreSource.id,
    soundscapeSourceID: soundscapeSource.id,
    regionCount: scoreSource.regions.length,
  };
}

function finiteTimeline(region, scoreRegion, soundRegion) {
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
    ],
    haptics: [],
    __scoreStateID: scoreRegion.scoreStateID,
    __soundscapeStateID: soundRegion.soundscapeStateID,
  };
}

function interactionTimeline(region, scoreRegion, soundscapeSource) {
  const durationSamples = Math.round(region.durationSeconds * 48_000);
  const stageZero = soundscapeSource.causalMixContract.states[0];
  return {
    id: region.timelineID,
    sampleRate: 48_000,
    events: [
      {
        cueID: `${region.id}-score-master`, role: "score", startSample: 0, durationSamples,
        assetPath: `${packageRoot}/${region.id}/score-master.wav`, gain: timelineGains.score,
      },
      ...soundscapeSource.causalMixContract.interactionLayerAssets.map(({ layerID, role, assetPath }) => ({
        cueID: `${region.id}-${layerID}`,
        role,
        startSample: 0,
        durationSamples,
        assetPath,
        gain: stageZero.layerGains.find((item) => item.layerID === layerID).gain,
      })),
    ],
    haptics: [],
    __scoreStateID: scoreRegion.scoreStateID,
    __soundscapeStateID: region.soundscapeStateID,
  };
}

function publicCausalMix(contract) {
  return {
    rampDurationSamples: contract.rampDurationSamples,
    layers: contract.interactionLayerAssets.map(({ layerID, assetPath }) => ({
      id: layerID,
      assetPath,
      cueIDs: Object.fromEntries(interactionRegions.map((phase) => [phase, `${phase}-${layerID}`])),
    })),
    states: contract.states.map(({ completedStageCount, layerGains }) => ({
      completedStageCount,
      layerGains,
    })),
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
  const transformation = findBeat(draft, "beat-first-farmers-three-records");
  const consequence = findBeat(draft, "beat-first-farmers-frontier-consequence");
  assert(transformation && consequence, "Three Records manuscript beats are missing");
  assert(transformation.interaction?.id === "interaction-first-farmers-at-the-iron-gates", "Three Records interaction ID drifted");
  assert(transformation.interaction.grammar === "transform", "Three Records interaction grammar drifted");
  assert(JSON.stringify(transformation.interaction.haptics) === JSON.stringify(activeThreeRecordsHaptics), "Three Records haptic subset drifted");
  const authored = soundscapeSource.regions.map((region, index) => (
    interactionRegions.includes(region.id)
      ? interactionTimeline(region, scoreSource.regions[index], soundscapeSource)
      : finiteTimeline(region, scoreSource.regions[index], region)
  ));
  const layerStates = (phase) => ({
    scoreStateID: scoreSource.regions.find(({ id }) => id === phase).scoreStateID,
    soundscapeStateID: soundscapeSource.regions.find(({ id }) => id === phase).soundscapeStateID,
  });
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
  })).sort((left, right) => left.path.localeCompare(right.path));
  const draftDigest = inputs.find(({ id }) => id === "first-farmers-manuscript-source").sha256;
  const stageTransportPassed = soundscapeSource.causalMixContract.transportStatus
    === "PASS_COMMON_PLAYER_SAMPLE_TIME_GAIN_RAMPS";
  const audioStageAccumulation = stageTransportPassed
    ? "RUNTIME_PERSISTS_CAUSAL_STAGE_AND_APPLIES_MONOTONIC_GAIN_TRANSPORT"
    : "RUNTIME_PERSISTS_CAUSAL_STAGE_STAGE_GAIN_TRANSPORT_OPEN";
  return {
    schemaVersion: 1,
    kind: "responsive-dramatic-audio-work-object",
    id: "three-records-responsive-audio-v1",
    status: "PROVISIONAL_NON_SHIPPING",
    shippingState: "PROHIBITED",
    trustDomain: "BACKSTAGE_AUDIO_PRODUCTION",
    scope: {
      chapterID: "first-farmers",
      arcID: "first-farmers-arc-02",
      beatID: "beat-first-farmers-three-records",
      interactionID: "interaction-first-farmers-at-the-iron-gates",
    },
    responsiveProgram: {
      id: "three-records-responsive-audio-v1",
      scope: {
        chapterID: "first-farmers",
        arcID: "first-farmers-arc-02",
        beatID: "beat-first-farmers-three-records",
        interactionID: "interaction-first-farmers-at-the-iron-gates",
      },
      approachTimelineID: "three-records-approach-v1",
      interactionBeds: [
        {
          phase: "waiting",
          timelineID: "three-records-waiting-bed-v1",
          layerStates: layerStates("waiting"),
        },
        {
          phase: "engaged",
          timelineID: "three-records-engaged-bed-v1",
          layerStates: layerStates("engaged"),
        },
        {
          phase: "resistance",
          timelineID: "three-records-resistance-bed-v1",
          layerStates: layerStates("resistance"),
        },
      ],
      consequenceTimelineID: "three-records-consequence-v1",
      exitPolicy: {
        kind: "bounded-fade",
        durationSamples: 9_600,
      },
      causalMix: publicCausalMix(soundscapeSource.causalMixContract),
    },
    causalBinding: {
      controlID: "time-layer",
      stages: routeStages,
      completionEffectID: transformation.interaction.completionEffectID,
      persistentTraceID: transformation.interaction.causalContract.persistentTrace,
      audioStageAccumulation,
    },
    timelines,
    audioAssetMetadata: metadata,
    narrationSlots: [
      manuscriptSlot(
        "three-records-approach-v1",
        `${packageRoot}/approach/narration-selected-master-required.wav`,
        transformation,
        draftDigest,
      ),
      manuscriptSlot(
        "three-records-consequence-v1",
        `${packageRoot}/consequence/narration-selected-master-required.wav`,
        consequence,
        draftDigest,
      ),
    ],
    hapticProgram: {
      vocabulary: canonicalHaptics,
      activeThreeRecordsSemantics: activeThreeRecordsHaptics,
      reservedForOtherGrammars: ["contact", "resistance", "transfer"],
      runtimeBindings: [
        { trigger: "transform-drag", semantic: "drag", durableCommitRequired: false },
        { trigger: "causal-threshold-crossed", completedStageCounts: [1, 2, 3], semantic: "break", durableCommitRequired: false },
        { trigger: "durable-completion", semantic: "seal", durableCommitRequired: true },
      ],
      loopedTimelineHaptics: "FORBIDDEN",
      accessibilityRule: "HAPTICS_NEVER_CARRY_THE_ONLY_CAUSAL_SIGNAL",
    },
    acousticBoundaries: {
      scoreProhibitedClaims: scoreSource.prohibitedClaims,
      soundscapeProhibitedClaims: soundscapeSource.prohibitedClaims,
    },
    authoredQuiet: soundscapeSource.regions.flatMap((region) => region.silenceWindows.map((quiet) => ({
      timelineID: region.timelineID,
      sampleRate: 48_000,
      startSample: Math.round(quiet.atSeconds * 48_000),
      durationSamples: Math.round(quiet.durationSeconds * 48_000),
      id: quiet.id,
      reason: quiet.reason,
      scope: "SOURCE_BOUND_QUIET_NOT_GLOBAL_TIMELINE_SILENCE",
      preservedCueIDs: interactionRegions.includes(region.id)
        ? [`${region.id}-gorge-current`]
        : [`${region.id}-soundscape-master`],
      zeroedCueIDs: interactionRegions.includes(region.id)
        ? [`${region.id}-score-master`, ...materialLayerIDs.filter((id) => id !== "gorge-current").map((id) => `${region.id}-${id}`)]
        : [`${region.id}-score-master`, `${region.id}-spatial-detail-master`],
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
      sharedInteractionMaterialAssets: "PASS_SEVEN_BYTE_IDENTICAL_ASSETS_REUSED_BY_ALL_PHASES",
      causalStagePersistence: "PASS_RUNTIME_TESTED",
      causalStageGainTransport: stageTransportPassed
        ? "PASS_RUNTIME_TESTED_9600_SAMPLE_RAMPS"
        : "OPEN_COMMON_PLAYER_GAIN_TRANSPORT",
      audibleCausalStageMix: stageTransportPassed
        ? "PASS_RUNTIME_CONTRACT_BOUND_TO_EXPLICIT_CUES"
        : "OPEN_NOT_YET_APPLIED_BY_TRANSPORT",
      scopedAuthoredQuiet: "PASS_RIVER_REMAINS_SAMPLE_CONTINUOUS",
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
  const scores = new Map();
  for (const regionID of regions) {
    const scoreRegion = scoreSource.regions.find(({ id }) => id === regionID);
    const score = await renderScoreRegion(scoreSource, soundscapeSource, scoreRegion, outputRoot, outputs);
    scores.set(regionID, score);
  }
  for (const regionID of ["approach", "consequence"]) {
    const soundRegion = soundscapeSource.regions.find(({ id }) => id === regionID);
    const sound = await renderFiniteSoundscapeRegion(soundscapeSource, soundRegion, outputRoot, outputs);
    metrics[regionID] = await renderFinitePreview(soundRegion, scores.get(regionID), sound, outputRoot, outputs);
  }
  const shared = await renderSharedInteractionMaterialLoop(soundscapeSource, outputRoot, outputs);
  for (const regionID of interactionRegions) {
    const soundRegion = soundscapeSource.regions.find(({ id }) => id === regionID);
    metrics[regionID] = await renderInteractionPreview(
      soundRegion,
      scores.get(regionID),
      shared,
      soundscapeSource.causalMixContract,
      outputRoot,
      outputs,
    );
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

export async function renderThreeRecordsResponsiveAudio({ verifyReproducibility = true } = {}) {
  await rm(cacheRoot, { recursive: true, force: true });
  const first = await renderAll(cacheRoot);
  let reproducibility = "NOT_RUN";
  if (verifyReproducibility) {
    const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-three-records-responsive-"));
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
    id: "three-records-responsive-audio-render-v1",
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
      sharedInteractionMaterialAssets: "PASS_SEVEN_BYTE_IDENTICAL_ASSETS_REUSED_BY_ALL_PHASES",
      loopSeams: "PASS_GORGE_CURRENT_SAMPLE_CONTINUOUS",
      scopedAuthoredQuiet: "PASS_NON_RIVER_ZERO_WINDOWS_CURRENT_RETAINED",
      causalStageMix: first.workObject.gates.causalStageGainTransport
        === "PASS_RUNTIME_TESTED_9600_SAMPLE_RAMPS"
        ? "PASS_RUNTIME_TRANSPORT_AND_MONOTONIC_STATIC_GATE"
        : "OPEN_COMMON_PLAYER_GAIN_TRANSPORT",
      truePeak: "PASS_ALL_PREVIEWS_AT_OR_BELOW_MINUS_1_DBTP",
      narration: "OPEN_MISSING_EDITOR_SELECTED_MASTER",
      artisticApproval: "OPEN",
      editorApproval: "OPEN",
      shippingApproval: "PROHIBITED",
    },
  };
  await writeFile(workObjectPath, `${JSON.stringify(first.workObject, null, 2)}\n`);
  await writeFile(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
  await validateThreeRecordsResponsiveAudio();
  return { workObject: first.workObject, receipt };
}

function validateWorkObject(work, soundscapeSource) {
  const stageTransportPassed = soundscapeSource.causalMixContract.transportStatus
    === "PASS_COMMON_PLAYER_SAMPLE_TIME_GAIN_RAMPS";
  assert(work.schemaVersion === 1 && work.kind === "responsive-dramatic-audio-work-object", "work object identity drifted");
  assert(work.id === "three-records-responsive-audio-v1", "work object ID drifted");
  assert(work.status === "PROVISIONAL_NON_SHIPPING" && work.shippingState === "PROHIBITED", "work object approval boundary drifted");
  assert(work.trustDomain === "BACKSTAGE_AUDIO_PRODUCTION", "work object trust domain drifted");
  assert(JSON.stringify(work.scope) === JSON.stringify({
    chapterID: "first-farmers",
    arcID: "first-farmers-arc-02",
    beatID: "beat-first-farmers-three-records",
    interactionID: "interaction-first-farmers-at-the-iron-gates",
  }), "work object scope drifted");
  assert(work.responsiveProgram.id === work.id, "responsive program identity drifted");
  assert(JSON.stringify(work.responsiveProgram.scope) === JSON.stringify(work.scope), "responsive program scope drifted");
  assert(work.responsiveProgram.approachTimelineID === "three-records-approach-v1", "approach timeline drifted");
  assert(work.responsiveProgram.consequenceTimelineID === "three-records-consequence-v1", "consequence timeline drifted");
  assert(JSON.stringify(work.responsiveProgram.exitPolicy) === JSON.stringify({
    kind: "bounded-fade",
    durationSamples: 9_600,
  }), "authored exit policy drifted");
  assert(JSON.stringify(work.responsiveProgram.interactionBeds.map(({ phase, timelineID }) => ({ phase, timelineID }))) === JSON.stringify([
    { phase: "waiting", timelineID: "three-records-waiting-bed-v1" },
    { phase: "engaged", timelineID: "three-records-engaged-bed-v1" },
    { phase: "resistance", timelineID: "three-records-resistance-bed-v1" },
  ]), "responsive bed phase set drifted");
  assert(JSON.stringify(work.responsiveProgram.causalMix) === JSON.stringify(publicCausalMix(soundscapeSource.causalMixContract)), "public causal mix drifted");
  assert(JSON.stringify(work.causalBinding) === JSON.stringify({
    controlID: "time-layer",
    stages: routeStages,
    completionEffectID: "effect-first-farmers-at-the-iron-gates",
    persistentTraceID: "trace-european-farming-belt",
    audioStageAccumulation: stageTransportPassed
      ? "RUNTIME_PERSISTS_CAUSAL_STAGE_AND_APPLIES_MONOTONIC_GAIN_TRANSPORT"
      : "RUNTIME_PERSISTS_CAUSAL_STAGE_STAGE_GAIN_TRANSPORT_OPEN",
  }), "Three Records causal binding drifted");

  unique(work.timelines.map(({ id }) => id), "work.timelines.id");
  assert(work.timelines.length === 5, "work.timelines: exact five authored regions required");
  assert(!work.timelines.some(({ events }) => events.some(({ role }) => role === "silence" || role === "narration" || role === "haptic")),
    "scoped quiet acquired a global silence, narration or haptic event");
  for (const phase of ["approach", "consequence"]) {
    const item = work.timelines.find(({ id }) => id === `three-records-${phase}-v1`);
    assert(item?.sampleRate === 48_000 && item.events.length === 3, `${phase}: exact finite timeline contract required`);
    assert(JSON.stringify(item.events.map(({ role }) => role)) === JSON.stringify(["score", "soundscape", "spatialDetail"]), `${phase}: finite role set drifted`);
  }
  const stageZero = soundscapeSource.causalMixContract.states[0];
  for (const phase of interactionRegions) {
    const item = work.timelines.find(({ id }) => id === `three-records-${phase}-bed-v1`);
    assert(item?.sampleRate === 48_000 && item.events.length === 8, `${phase}: score plus seven shared material cues required`);
    assert(item.haptics.length === 0, `${phase}: timed loop haptics are forbidden`);
    const score = item.events[0];
    assert(score.cueID === `${phase}-score-master` && score.role === "score"
      && score.assetPath === `${packageRoot}/${phase}/score-master.wav`, `${phase}: score cue drifted`);
    for (const { layerID, role, assetPath } of soundscapeSource.causalMixContract.interactionLayerAssets) {
      const event = item.events.find(({ cueID }) => cueID === `${phase}-${layerID}`);
      const expectedGain = stageZero.layerGains.find((gain) => gain.layerID === layerID).gain;
      assert(event?.role === role && event.assetPath === assetPath && event.startSample === 0
        && event.durationSamples === 720_000 && event.gain === expectedGain, `${phase}/${layerID}: shared causal material cue drifted`);
    }
  }

  assert(work.audioAssetMetadata.length === 16, "exact sixteen runtime metadata records required");
  assert(JSON.stringify(work.hapticProgram.runtimeBindings) === JSON.stringify([
    { trigger: "transform-drag", semantic: "drag", durableCommitRequired: false },
    { trigger: "causal-threshold-crossed", completedStageCounts: [1, 2, 3], semantic: "break", durableCommitRequired: false },
    { trigger: "durable-completion", semantic: "seal", durableCommitRequired: true },
  ]), "Three Records haptic runtime bindings drifted");
  assert(JSON.stringify(work.hapticProgram.vocabulary) === JSON.stringify(canonicalHaptics), "canonical haptic vocabulary drifted");
  assert(JSON.stringify(work.hapticProgram.activeThreeRecordsSemantics) === JSON.stringify(activeThreeRecordsHaptics), "Three Records haptic subset drifted");
  assert(work.hapticProgram.loopedTimelineHaptics === "FORBIDDEN", "looped timeline acquired haptics");

  assert(work.narrationSlots.length === 2
    && work.narrationSlots.every(({ status, shippingBlock }) => status === "MISSING_EDITOR_SELECTED_NARRATION_MASTER" && shippingBlock), "narration placeholders drifted");
  assert(JSON.stringify(work.narrationSlots.map(({ segments }) => segments.map(({ manuscriptSegmentID, manuscriptSegmentSHA256 }) => ({
    manuscriptSegmentID, manuscriptSegmentSHA256,
  })))) === JSON.stringify([
    [
      { manuscriptSegmentID: "ff-records-01", manuscriptSegmentSHA256: "2e0bb347d1c361da279ad76505fa9741e0e0026b82b06d81677a13bf9e258ac5" },
      { manuscriptSegmentID: "ff-records-02", manuscriptSegmentSHA256: "84f1d3f284fff9f26af1e53fa49f7ccf608a2ab827ce4168949e949c813569a8" },
    ],
    [
      { manuscriptSegmentID: "ff-frontier-consequence-01", manuscriptSegmentSHA256: "b00525cb8d6e7d560a7adfe0b1894976ae43ca38638fb22f51af0a5f7495781d" },
      { manuscriptSegmentID: "ff-frontier-consequence-02", manuscriptSegmentSHA256: "fc71f01cdd7f68107ec650d165940158323c86946ea8160386f8420ecfb833e5" },
    ],
  ]), "Three Records narration manuscript hashes drifted");
  assert(work.authoredQuiet.length === 5, "five scoped quiet bindings required");
  for (const quiet of work.authoredQuiet) {
    assert(quiet.scope === "SOURCE_BOUND_QUIET_NOT_GLOBAL_TIMELINE_SILENCE" && quiet.preservedCueIDs.length === 1,
      `${quiet.timelineID}: scoped quiet boundary drifted`);
  }
  assert(work.acousticBoundaries.scoreProhibitedClaims.length === 6
    && work.acousticBoundaries.soundscapeProhibitedClaims.length === 9, "acoustic prohibited-claim boundary drifted");
  assert(work.provenance.incrementalCostNOK === 0, "work object introduced incremental cost");
  assert(work.gates.causalStageGainTransport === (stageTransportPassed
    ? "PASS_RUNTIME_TESTED_9600_SAMPLE_RAMPS"
    : "OPEN_COMMON_PLAYER_GAIN_TRANSPORT"), "causal gain transport gate drifted");
  assert(work.gates.scopedAuthoredQuiet === "PASS_RIVER_REMAINS_SAMPLE_CONTINUOUS", "scoped quiet gate drifted");
  assert(work.gates.artisticApproval === "OPEN" && work.gates.shippingApproval === "PROHIBITED", "work object fabricated approval");
}

async function validateOutputs(receipt) {
  assert(receipt.outputs.length === 65, `receipt.outputs: expected 65, got ${receipt.outputs.length}`);
  assert(!receipt.outputs.some(({ regionID, role }) => interactionRegions.includes(regionID)
    && [
      "soundscape-layer-master",
      "spatial-layer-master",
      "soundscape-master",
      "spatial-detail-master",
    ].includes(role)), "interaction phase rendered a phase-specific material asset");
  for (const output of receipt.outputs) {
    const file = path.join(cacheRoot, output.path);
    const current = await hashFile(file).catch(() => fail(`missing rendered output: ${output.path}`));
    assert(current.bytes === output.bytes && current.sha256 === output.sha256, `${output.path}: rendered bytes drifted`);
    assert(output.incrementalCostNOK === 0, `${output.path}: incremental cost drifted`);
    if (output.format) {
      const format = inspectPCM24StereoWAV(await readFile(file));
      assert(JSON.stringify(format) === JSON.stringify(output.format), `${output.path}: WAV format drifted`);
      const duration = output.regionID === "interaction-material-loop" ? 15 : regionDurations.get(output.regionID);
      assert(format.frames === duration * 48_000, `${output.path}: exact frame duration drifted`);
    }
  }
  assert(receipt.reproducibility === "PASS_SECOND_COMPLETE_OFFLINE_RENDER", "receipt lacks complete second-render proof");
}

export async function validateThreeRecordsResponsiveAudio() {
  const { toolchain, soundscapeSource } = await readSources();
  const [workBytes, receiptBytes] = await Promise.all([
    readFile(workObjectPath), readFile(receiptPath),
  ]).catch(() => fail("Three Records responsive work object and receipt are required"));
  const work = JSON.parse(workBytes);
  const receipt = JSON.parse(receiptBytes);
  validateWorkObject(work, soundscapeSource);
  assert(receipt.id === "three-records-responsive-audio-render-v1", "receipt identity drifted");
  assert(receipt.status === "PROVISIONAL_NON_SHIPPING" && receipt.shippingState === "PROHIBITED", "receipt approval boundary drifted");
  assert(receipt.gates?.scopedAuthoredQuiet === "PASS_NON_RIVER_ZERO_WINDOWS_CURRENT_RETAINED", "receipt scoped quiet gate drifted");
  assert(receipt.gates?.causalStageMix === (soundscapeSource.causalMixContract.transportStatus
    === "PASS_COMMON_PLAYER_SAMPLE_TIME_GAIN_RAMPS"
    ? "PASS_RUNTIME_TRANSPORT_AND_MONOTONIC_STATIC_GATE"
    : "OPEN_COMMON_PLAYER_GAIN_TRANSPORT"), "receipt causal transport gate drifted");
  assert(receipt.gates?.shippingApproval === "PROHIBITED", "receipt fabricated shipping approval");
  const expectedInputs = await productionInputs();
  assert(JSON.stringify(receipt.productionInputs) === JSON.stringify(expectedInputs), "receipt production inputs drifted");
  assert(JSON.stringify(work.provenance.productionInputs) === JSON.stringify(expectedInputs), "work provenance inputs drifted");
  await pinnedRuntime(toolchain);
  await validateOutputs(receipt);
  const outputByPackagePath = new Map(receipt.outputs.filter(({ packageAssetPath }) => packageAssetPath)
    .map((output) => [output.packageAssetPath, output]));
  assert(outputByPackagePath.size === 16, "exact sixteen runtime masters required");
  assert(work.audioAssetMetadata.length === 16, "exact sixteen runtime metadata records required");
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
  const window = (startSample, durationSamples) => [{
    id: "validation-window",
    atSeconds: startSample / 48_000,
    durationSeconds: durationSamples / 48_000,
  }];
  for (const phase of ["approach", "consequence"]) {
    const quiet = silenceSamples.get(phase);
    for (const role of ["score-master", "spatial-detail-master"]) {
      const output = receipt.outputs.find((item) => item.regionID === phase && item.role === role);
      const audio = decodePCM24StereoWAV(await readFile(path.join(cacheRoot, output.path)));
      verifySilence(audio, window(quiet.startSample, quiet.durationSamples), 48_000, `${phase}/${role}`);
    }
    const soundscape = receipt.outputs.find((item) => item.regionID === phase && item.role === "soundscape-master");
    const audible = decodePCM24StereoWAV(await readFile(path.join(cacheRoot, soundscape.path)));
    const currentLayer = receipt.outputs.find((item) => item.regionID === phase
      && item.role === "soundscape-layer-master" && item.sourceID === "gorge-current");
    assert(currentLayer, `${phase}: rendered gorge-current layer missing`);
    const currentAudio = decodePCM24StereoWAV(await readFile(path.join(cacheRoot, currentLayer.path)));
    assert(peak({
      left: audible.left.slice(quiet.startSample, quiet.startSample + quiet.durationSamples),
      right: audible.right.slice(quiet.startSample, quiet.startSample + quiet.durationSamples),
    }) > 0, `${phase}: current missing from scoped quiet`);
    for (let frame = quiet.startSample; frame < quiet.startSample + quiet.durationSamples; frame += 1) {
      assert(audible.left[frame] === currentAudio.left[frame]
        && audible.right[frame] === currentAudio.right[frame], `${phase}: encoded broad master is not exactly current-only`);
    }
    for (const layerID of materialLayerIDs.filter((id) => id !== "gorge-current")) {
      const layer = receipt.outputs.find((item) => item.regionID === phase && item.sourceID === layerID
        && ["soundscape-layer-master", "spatial-layer-master"].includes(item.role));
      assert(layer, `${phase}/${layerID}: rendered material layer missing`);
      verifySilence(
        decodePCM24StereoWAV(await readFile(path.join(cacheRoot, layer.path))),
        window(quiet.startSample, quiet.durationSamples),
        48_000,
        `${phase}/${layerID}`,
      );
    }
  }
  const loopQuiet = silenceSamples.get("waiting");
  for (const phase of interactionRegions) {
    const score = receipt.outputs.find((item) => item.regionID === phase && item.role === "score-master");
    verifySilence(
      decodePCM24StereoWAV(await readFile(path.join(cacheRoot, score.path))),
      window(loopQuiet.startSample, loopQuiet.durationSamples),
      48_000,
      `${phase}/score-master`,
    );
  }
  for (const layerID of materialLayerIDs) {
    const output = outputByPackagePath.get(`${packageRoot}/interaction/shared/${layerID}.wav`);
    assert(output, `${layerID}: shared interaction material missing`);
    const audio = decodePCM24StereoWAV(await readFile(path.join(cacheRoot, output.path)));
    if (layerID === "gorge-current") {
      assert(audio.left[0] === audio.left.at(-1) && audio.right[0] === audio.right.at(-1), "gorge current loop joint drifted");
      assert(peak({ left: audio.left.slice(loopQuiet.startSample), right: audio.right.slice(loopQuiet.startSample) }) > 0,
        "gorge current vanished during loop-tail quiet");
    } else {
      verifySilence(audio, window(loopQuiet.startSample, loopQuiet.durationSamples), 48_000, `shared/${layerID}`);
    }
  }
  const notice = await hashFile(noticePath);
  assert(notice.sha256 === toolchain.soundFont.noticeSHA256 && notice.bytes === toolchain.soundFont.noticeBytes, "required MIT notice drifted");
  return { work, receipt, workObjectSHA256: sha256(workBytes), receiptSHA256: sha256(receiptBytes) };
}

export const threeRecordsResponsiveAudioPaths = Object.freeze({
  repositoryRoot,
  sourceRoot,
  cacheRoot,
  scoreSourcePath,
  soundscapeSourcePath,
  workObjectPath,
  receiptPath,
});
