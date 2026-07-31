import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const modulePath = fileURLToPath(import.meta.url);
const repositoryRoot = path.resolve(path.dirname(modulePath), "../../..");
const audioProductionSchemaPath = path.join(repositoryRoot, "native", "schemas", "audio-production-plan.schema.json");

const stableIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/u;
const sha256Pattern = /^[a-f0-9]{64}$/u;
const notePattern = /^([A-G])([#b]?)(-1|[0-9])$/u;
const articulations = new Set(["legato", "tenuto", "detached", "accent"]);
const dynamics = new Set(["pp", "p", "mp", "mf", "f", "ff"]);
const generatorAlgorithms = new Set([
  "rain-on-earth-v1",
  "small-hearth-fire-v1",
  "dry-grain-contact-v1",
  "woven-fibre-friction-v1",
  "distant-material-work-v1",
  "herd-ground-movement-v1",
  "close-water-movement-v1",
  "distant-human-presence-v1",
]);
const materialAlgorithms = new Map([
  ["rain", "rain-on-earth-v1"],
  ["fire", "small-hearth-fire-v1"],
  ["grain", "dry-grain-contact-v1"],
  ["textile", "woven-fibre-friction-v1"],
  ["work", "distant-material-work-v1"],
  ["herd", "herd-ground-movement-v1"],
  ["water", "close-water-movement-v1"],
  ["human", "distant-human-presence-v1"],
]);
const dynamicVelocity = new Map([
  ["pp", 35],
  ["p", 47],
  ["mp", 59],
  ["mf", 74],
  ["f", 91],
  ["ff", 108],
]);
const articulationGate = new Map([
  ["legato", 1],
  ["tenuto", 0.92],
  ["detached", 0.58],
  ["accent", 0.76],
]);

export class AudioProductionError extends Error {
  constructor(issues) {
    super(issues.join("\n"));
    this.name = "AudioProductionError";
    this.issues = issues;
  }
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(record, required, location, issues) {
  if (!isRecord(record)) {
    issues.push(`${location}: object required`);
    return false;
  }
  const expected = new Set(required);
  for (const key of required) {
    if (!Object.hasOwn(record, key)) issues.push(`${location}.${key}: required`);
  }
  for (const key of Object.keys(record)) {
    if (!expected.has(key)) issues.push(`${location}.${key}: unsupported field`);
  }
  return true;
}

function stableID(value, location, issues) {
  if (typeof value !== "string" || !stableIDPattern.test(value)) {
    issues.push(`${location}: stable kebab-case ID required`);
  }
}

function finiteNumber(value, location, issues, minimum, maximum) {
  if (!Number.isFinite(value) || value < minimum || value > maximum) {
    issues.push(`${location}: number from ${minimum} through ${maximum} required`);
    return false;
  }
  return true;
}

function integer(value, location, issues, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    issues.push(`${location}: integer from ${minimum} through ${maximum} required`);
    return false;
  }
  return true;
}

function authoredString(value, location, issues) {
  if (typeof value !== "string" || value.trim().length === 0) {
    issues.push(`${location}: non-empty string required`);
    return false;
  }
  return true;
}

function requireUnique(values, location, issues) {
  if (new Set(values).size !== values.length) issues.push(`${location}: duplicate value`);
}

function requireOutputFormat(output, location, issues) {
  exactKeys(output, ["sampleRate", "bitDepth", "channels", "container"], location, issues);
  if (output?.sampleRate !== 48_000) issues.push(`${location}.sampleRate: expected 48000`);
  if (output?.bitDepth !== 24) issues.push(`${location}.bitDepth: expected 24`);
  if (output?.channels !== 2) issues.push(`${location}.channels: expected stereo`);
  if (output?.container !== "wav") issues.push(`${location}.container: expected wav`);
}

export function validateScoreProductionPlan(plan) {
  const issues = [];
  exactKeys(plan, [
    "schemaVersion", "kind", "id", "status", "output", "ppq", "durationBeats",
    "meter", "tempoMap", "motifs", "stems",
  ], "score", issues);
  if (plan?.schemaVersion !== 1) issues.push("score.schemaVersion: expected 1");
  if (plan?.kind !== "symbolic-score") issues.push("score.kind: expected symbolic-score");
  stableID(plan?.id, "score.id", issues);
  if (plan?.status !== "TECHNICAL_PROBE_NOT_APPROVED") {
    issues.push("score.status: technical, non-approved status required");
  }
  requireOutputFormat(plan?.output, "score.output", issues);
  integer(plan?.ppq, "score.ppq", issues, 96, 9_600);
  finiteNumber(plan?.durationBeats, "score.durationBeats", issues, 1, 10_000);

  exactKeys(plan?.meter, ["numerator", "denominator"], "score.meter", issues);
  integer(plan?.meter?.numerator, "score.meter.numerator", issues, 1, 32);
  if (![1, 2, 4, 8, 16, 32].includes(plan?.meter?.denominator)) {
    issues.push("score.meter.denominator: power of two from 1 through 32 required");
  }

  if (!Array.isArray(plan?.tempoMap) || plan.tempoMap.length === 0) {
    issues.push("score.tempoMap: non-empty array required");
  } else {
    let previousBeat = -1;
    for (const [index, tempo] of plan.tempoMap.entries()) {
      const location = `score.tempoMap[${index}]`;
      exactKeys(tempo, ["atBeat", "bpm"], location, issues);
      finiteNumber(tempo?.atBeat, `${location}.atBeat`, issues, 0, plan.durationBeats ?? 0);
      finiteNumber(tempo?.bpm, `${location}.bpm`, issues, 20, 240);
      if (tempo?.atBeat <= previousBeat) issues.push(`${location}.atBeat: strictly increasing beat required`);
      previousBeat = tempo?.atBeat;
    }
    if (plan.tempoMap[0]?.atBeat !== 0) issues.push("score.tempoMap[0].atBeat: must start at beat 0");
  }

  const motifIDs = [];
  if (!Array.isArray(plan?.motifs) || plan.motifs.length === 0) {
    issues.push("score.motifs: non-empty array required");
  } else {
    for (const [motifIndex, motif] of plan.motifs.entries()) {
      const location = `score.motifs[${motifIndex}]`;
      exactKeys(motif, ["id", "notes"], location, issues);
      stableID(motif?.id, `${location}.id`, issues);
      motifIDs.push(motif?.id);
      if (!Array.isArray(motif?.notes) || motif.notes.length === 0) {
        issues.push(`${location}.notes: non-empty array required`);
        continue;
      }
      for (const [noteIndex, note] of motif.notes.entries()) {
        const noteLocation = `${location}.notes[${noteIndex}]`;
        exactKeys(note, ["pitch", "atBeat", "durationBeats", "dynamic", "articulation"], noteLocation, issues);
        if (typeof note?.pitch !== "string" || !notePattern.test(note.pitch)) {
          issues.push(`${noteLocation}.pitch: scientific pitch such as D3 required`);
        }
        finiteNumber(note?.atBeat, `${noteLocation}.atBeat`, issues, 0, 1_000);
        finiteNumber(note?.durationBeats, `${noteLocation}.durationBeats`, issues, 0.01, 1_000);
        if (!dynamics.has(note?.dynamic)) issues.push(`${noteLocation}.dynamic: pp through ff required`);
        if (!articulations.has(note?.articulation)) {
          issues.push(`${noteLocation}.articulation: recognised articulation required`);
        }
      }
    }
  }
  requireUnique(motifIDs, "score.motifs.id", issues);

  const motifIDSet = new Set(motifIDs);
  const stemIDs = [];
  if (!Array.isArray(plan?.stems) || plan.stems.length < 2) {
    issues.push("score.stems: at least two independently renderable stems required");
  } else {
    for (const [stemIndex, stem] of plan.stems.entries()) {
      const location = `score.stems[${stemIndex}]`;
      exactKeys(stem, [
        "id", "role", "instrument", "gainDB", "pan", "phrases",
      ], location, issues);
      stableID(stem?.id, `${location}.id`, issues);
      stemIDs.push(stem?.id);
      authoredString(stem?.role, `${location}.role`, issues);
      exactKeys(stem?.instrument, ["bank", "program", "label"], `${location}.instrument`, issues);
      integer(stem?.instrument?.bank, `${location}.instrument.bank`, issues, 0, 16_383);
      integer(stem?.instrument?.program, `${location}.instrument.program`, issues, 0, 127);
      authoredString(stem?.instrument?.label, `${location}.instrument.label`, issues);
      finiteNumber(stem?.gainDB, `${location}.gainDB`, issues, -60, 0);
      finiteNumber(stem?.pan, `${location}.pan`, issues, -1, 1);
      if (!Array.isArray(stem?.phrases) || stem.phrases.length === 0) {
        issues.push(`${location}.phrases: non-empty array required`);
        continue;
      }
      for (const [phraseIndex, phrase] of stem.phrases.entries()) {
        const phraseLocation = `${location}.phrases[${phraseIndex}]`;
        exactKeys(phrase, ["motifID", "atBeat", "transposeSemitones", "dynamicOffset"], phraseLocation, issues);
        if (!motifIDSet.has(phrase?.motifID)) issues.push(`${phraseLocation}.motifID: known motif required`);
        finiteNumber(phrase?.atBeat, `${phraseLocation}.atBeat`, issues, 0, plan.durationBeats ?? 0);
        integer(phrase?.transposeSemitones, `${phraseLocation}.transposeSemitones`, issues, -36, 36);
        integer(phrase?.dynamicOffset, `${phraseLocation}.dynamicOffset`, issues, -40, 40);
      }
    }
  }
  requireUnique(stemIDs, "score.stems.id", issues);

  if (Array.isArray(plan?.motifs) && Array.isArray(plan?.stems)) {
    const motifs = new Map(plan.motifs.map((motif) => [motif.id, motif]));
    for (const stem of plan.stems) {
      for (const phrase of stem.phrases ?? []) {
        const motif = motifs.get(phrase.motifID);
        for (const note of motif?.notes ?? []) {
          const end = phrase.atBeat + note.atBeat + note.durationBeats;
          if (end > plan.durationBeats + Number.EPSILON) {
            issues.push(`score.stems.${stem.id}: phrase '${phrase.motifID}' exceeds durationBeats`);
          }
        }
      }
    }
  }

  if (issues.length) throw new AudioProductionError(issues);
  return plan;
}

export function validateSoundscapeProductionPlan(plan) {
  const issues = [];
  exactKeys(plan, [
    "schemaVersion", "kind", "id", "status", "output", "durationSeconds",
    "layers", "silenceWindows",
  ], "soundscape", issues);
  if (plan?.schemaVersion !== 1) issues.push("soundscape.schemaVersion: expected 1");
  if (plan?.kind !== "procedural-soundscape") {
    issues.push("soundscape.kind: expected procedural-soundscape");
  }
  stableID(plan?.id, "soundscape.id", issues);
  if (plan?.status !== "TECHNICAL_PROBE_NOT_APPROVED") {
    issues.push("soundscape.status: technical, non-approved status required");
  }
  requireOutputFormat(plan?.output, "soundscape.output", issues);
  finiteNumber(plan?.durationSeconds, "soundscape.durationSeconds", issues, 1, 600);

  const layerIDs = [];
  const materials = [];
  if (!Array.isArray(plan?.layers) || plan.layers.length < 5) {
    issues.push("soundscape.layers: at least five source-bound material layers required");
  } else {
    for (const [index, layer] of plan.layers.entries()) {
      const location = `soundscape.layers[${index}]`;
      exactKeys(layer, [
        "id", "material", "visibleSource", "generator", "gainDB", "pan", "loop",
      ], location, issues);
      stableID(layer?.id, `${location}.id`, issues);
      layerIDs.push(layer?.id);
      if (!materialAlgorithms.has(layer?.material)) {
        issues.push(`${location}.material: rain, fire, grain, textile, work, herd, water or human required`);
      }
      materials.push(layer?.material);
      authoredString(layer?.visibleSource, `${location}.visibleSource`, issues);
      exactKeys(layer?.generator, ["algorithm", "seed", "density", "colour"], `${location}.generator`, issues);
      if (!generatorAlgorithms.has(layer?.generator?.algorithm)) {
        issues.push(`${location}.generator.algorithm: recognised local generator required`);
      }
      integer(layer?.generator?.seed, `${location}.generator.seed`, issues, 1, 0xffff_ffff);
      finiteNumber(layer?.generator?.density, `${location}.generator.density`, issues, 0, 1);
      finiteNumber(layer?.generator?.colour, `${location}.generator.colour`, issues, 0, 1);
      finiteNumber(layer?.gainDB, `${location}.gainDB`, issues, -80, 0);
      finiteNumber(layer?.pan, `${location}.pan`, issues, -1, 1);
      if (typeof layer?.loop !== "boolean") issues.push(`${location}.loop: boolean required`);
      const expectedAlgorithm = materialAlgorithms.get(layer?.material);
      if (expectedAlgorithm && layer?.generator?.algorithm !== expectedAlgorithm) {
        issues.push(`${location}.generator.algorithm: material/algorithm mismatch`);
      }
    }
  }
  requireUnique(layerIDs, "soundscape.layers.id", issues);
  requireUnique(materials, "soundscape.layers.material", issues);

  const silenceIDs = [];
  if (!Array.isArray(plan?.silenceWindows) || plan.silenceWindows.length === 0) {
    issues.push("soundscape.silenceWindows: at least one authored silence required");
  } else {
    for (const [index, silence] of plan.silenceWindows.entries()) {
      const location = `soundscape.silenceWindows[${index}]`;
      exactKeys(silence, ["id", "atSeconds", "durationSeconds", "reason", "entry", "exit"], location, issues);
      stableID(silence?.id, `${location}.id`, issues);
      silenceIDs.push(silence?.id);
      finiteNumber(silence?.atSeconds, `${location}.atSeconds`, issues, 0, plan.durationSeconds ?? 0);
      finiteNumber(silence?.durationSeconds, `${location}.durationSeconds`, issues, 0.1, plan.durationSeconds ?? 0);
      if ((silence?.atSeconds ?? 0) + (silence?.durationSeconds ?? 0) > (plan.durationSeconds ?? 0)) {
        issues.push(`${location}: silence exceeds soundscape duration`);
      }
      authoredString(silence?.reason, `${location}.reason`, issues);
      if (silence?.entry !== "authored-cut" || silence?.exit !== "authored-return") {
        issues.push(`${location}: explicit authored-cut/authored-return boundary required`);
      }
    }
  }
  requireUnique(silenceIDs, "soundscape.silenceWindows.id", issues);

  if (issues.length) throw new AudioProductionError(issues);
  return plan;
}

function variableLength(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 0x0fff_ffff) {
    throw new AudioProductionError([`MIDI delta: unsupported value ${value}`]);
  }
  const bytes = [value & 0x7f];
  let remaining = value >>> 7;
  while (remaining > 0) {
    bytes.unshift((remaining & 0x7f) | 0x80);
    remaining >>>= 7;
  }
  return Buffer.from(bytes);
}

function midiChunk(type, data) {
  const header = Buffer.alloc(8);
  header.write(type, 0, 4, "ascii");
  header.writeUInt32BE(data.length, 4);
  return Buffer.concat([header, data]);
}

function encodeTrack(events) {
  const ordered = [...events].sort((left, right) =>
    left.tick - right.tick || left.priority - right.priority || Buffer.compare(left.data, right.data));
  const chunks = [];
  let previousTick = 0;
  for (const event of ordered) {
    chunks.push(variableLength(event.tick - previousTick), event.data);
    previousTick = event.tick;
  }
  chunks.push(Buffer.from([0x00, 0xff, 0x2f, 0x00]));
  return midiChunk("MTrk", Buffer.concat(chunks));
}

function textMeta(type, value) {
  const text = Buffer.from(value, "utf8");
  return Buffer.concat([Buffer.from([0xff, type]), variableLength(text.length), text]);
}

function pitchNumber(pitch) {
  const match = notePattern.exec(pitch);
  if (!match) throw new AudioProductionError([`pitch '${pitch}': invalid`]);
  const semitone = new Map([
    ["C", 0], ["D", 2], ["E", 4], ["F", 5], ["G", 7], ["A", 9], ["B", 11],
  ]).get(match[1]);
  const accidental = match[2] === "#" ? 1 : match[2] === "b" ? -1 : 0;
  const midi = (Number.parseInt(match[3], 10) + 1) * 12 + semitone + accidental;
  if (midi < 0 || midi > 127) throw new AudioProductionError([`pitch '${pitch}': outside MIDI range`]);
  return midi;
}

function scoreTempoTrack(plan) {
  const events = [
    { tick: 0, priority: 0, data: textMeta(0x03, `${plan.id}-tempo`) },
  ];
  const denominatorPower = Math.log2(plan.meter.denominator);
  events.push({
    tick: 0,
    priority: 1,
    data: Buffer.from([0xff, 0x58, 0x04, plan.meter.numerator, denominatorPower, 24, 8]),
  });
  for (const tempo of plan.tempoMap) {
    const micros = Math.round(60_000_000 / tempo.bpm);
    events.push({
      tick: Math.round(tempo.atBeat * plan.ppq),
      priority: 2,
      data: Buffer.from([0xff, 0x51, 0x03, (micros >>> 16) & 0xff, (micros >>> 8) & 0xff, micros & 0xff]),
    });
  }
  return encodeTrack(events);
}

function scoreStemTrack(plan, stem) {
  const events = [
    { tick: 0, priority: 0, data: textMeta(0x03, stem.id) },
    { tick: 0, priority: 1, data: Buffer.from([0xb0, 0x00, (stem.instrument.bank >>> 7) & 0x7f]) },
    { tick: 0, priority: 2, data: Buffer.from([0xb0, 0x20, stem.instrument.bank & 0x7f]) },
    { tick: 0, priority: 3, data: Buffer.from([0xc0, stem.instrument.program]) },
    { tick: 0, priority: 4, data: Buffer.from([0xb0, 0x0a, Math.round((stem.pan + 1) * 63.5)]) },
    { tick: 0, priority: 5, data: Buffer.from([0xb0, 0x07, Math.max(1, Math.round(127 * (10 ** (stem.gainDB / 40))))]) },
  ];
  const motifs = new Map(plan.motifs.map((motif) => [motif.id, motif]));
  for (const phrase of stem.phrases) {
    const motif = motifs.get(phrase.motifID);
    for (const note of motif.notes) {
      const pitch = pitchNumber(note.pitch) + phrase.transposeSemitones;
      if (pitch < 0 || pitch > 127) {
        throw new AudioProductionError([`${stem.id}/${phrase.motifID}: transposed note outside MIDI range`]);
      }
      const startTick = Math.round((phrase.atBeat + note.atBeat) * plan.ppq);
      const gate = articulationGate.get(note.articulation);
      const durationTicks = Math.max(1, Math.round(note.durationBeats * gate * plan.ppq));
      const velocity = Math.max(1, Math.min(127, dynamicVelocity.get(note.dynamic) + phrase.dynamicOffset));
      events.push({ tick: startTick, priority: 20, data: Buffer.from([0x90, pitch, velocity]) });
      events.push({ tick: startTick + durationTicks, priority: 10, data: Buffer.from([0x80, pitch, 0]) });
    }
  }
  return encodeTrack(events);
}

export function compileScoreStemMIDI(plan, stemID) {
  validateScoreProductionPlan(plan);
  const stem = plan.stems.find((candidate) => candidate.id === stemID);
  if (!stem) throw new AudioProductionError([`score.stems: unknown stem '${stemID}'`]);
  const header = Buffer.alloc(6);
  header.writeUInt16BE(1, 0);
  header.writeUInt16BE(2, 2);
  header.writeUInt16BE(plan.ppq, 4);
  return Buffer.concat([
    midiChunk("MThd", header),
    scoreTempoTrack(plan),
    scoreStemTrack(plan, stem),
  ]);
}

function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 0x1_0000_0000;
  };
}

function panGains(pan) {
  const angle = (pan + 1) * Math.PI / 4;
  return [Math.cos(angle), Math.sin(angle)];
}

function boundedPan(pan) {
  return Math.max(-1, Math.min(1, pan));
}

function synthesizeHerdGroundMovement(layer, sampleRate, frameCount) {
  const left = new Float64Array(frameCount);
  const right = new Float64Array(frameCount);
  const density = layer.generator.density;
  const colour = layer.generator.colour;
  const gain = 10 ** (layer.gainDB / 20);
  const voiceCount = Math.min(7, 3 + Math.floor(density * 5));
  const voiceGain = gain / Math.sqrt(voiceCount);
  const twoPiOverRate = 2 * Math.PI / sampleRate;
  const voices = Array.from({ length: voiceCount }, (_, index) => {
    const derivedSeed = (layer.generator.seed + Math.imul(index + 1, 0x9e3779b9)) >>> 0;
    const random = seededRandom(derivedSeed || index + 1);
    const spread = voiceCount === 1 ? 0 : index / (voiceCount - 1) - 0.5;
    const pan = boundedPan(layer.pan + spread * 0.52 + (random() * 2 - 1) * 0.08);
    const [leftPan, rightPan] = panGains(pan);
    return {
      random,
      nextEventFrame: Math.round((0.18 + random() * 0.9) * sampleRate),
      clusterRemaining: 0,
      eventEnvelope: 0,
      eventPhase: 0,
      secondaryPhase: 0,
      low: 0,
      previousNoise: 0,
      breathPhase: random() * Math.PI * 2,
      leftPan,
      rightPan,
      targetLeftPan: leftPan,
      targetRightPan: rightPan,
    };
  });

  for (let frame = 0; frame < frameCount; frame += 1) {
    let leftSample = 0;
    let rightSample = 0;
    for (const voice of voices) {
      if (frame >= voice.nextEventFrame) {
        if (voice.clusterRemaining === 0) {
          voice.clusterRemaining = 2 + Math.floor(voice.random() * 4);
        }
        voice.eventEnvelope = 0.72 + voice.random() * 0.28;
        voice.eventPhase = 0;
        voice.secondaryPhase = 0;
        voice.clusterRemaining -= 1;
        const targetPan = boundedPan(layer.pan + (voice.random() * 2 - 1) * (0.18 + density * 0.2));
        [voice.targetLeftPan, voice.targetRightPan] = panGains(targetPan);
        const gapSeconds = voice.clusterRemaining > 0
          ? 0.17 + voice.random() * (0.2 + (1 - colour) * 0.08)
          : 0.85 + (1 - density) * 2.1 + voice.random() * 1.35;
        voice.nextEventFrame = frame + Math.max(1, Math.round(gapSeconds * sampleRate));
      }

      voice.leftPan += (voice.targetLeftPan - voice.leftPan) * 0.00035;
      voice.rightPan += (voice.targetRightPan - voice.rightPan) * 0.00035;
      const white = voice.random() * 2 - 1;
      voice.low += (white - voice.low) * (0.0012 + colour * 0.0024);
      const high = white - voice.previousNoise;
      voice.previousNoise = white;
      voice.eventEnvelope *= 0.99918 - colour * 0.00018;
      voice.eventPhase += (88 - colour * 38) * twoPiOverRate;
      voice.secondaryPhase += (172 - colour * 52) * twoPiOverRate;
      voice.breathPhase += (0.18 + density * 0.13 + colour * 0.04) * twoPiOverRate;
      const breathing = 0.5 + Math.sin(voice.breathPhase) * 0.5;
      const impact = voice.eventEnvelope * (
        Math.sin(voice.eventPhase) * 0.3
        + Math.sin(voice.secondaryPhase) * 0.075
        + high * 0.045
      );
      const bodyAndBreath = voice.low * (0.045 + density * 0.035) * (0.35 + breathing * 0.65);
      const sample = Math.tanh((impact + bodyAndBreath) * 1.55) * voiceGain;
      leftSample += sample * voice.leftPan;
      rightSample += sample * voice.rightPan;
    }
    left[frame] = leftSample;
    right[frame] = rightSample;
  }
  return { left, right };
}

function synthesizeCloseWaterMovement(layer, sampleRate, frameCount) {
  const left = new Float64Array(frameCount);
  const right = new Float64Array(frameCount);
  const random = seededRandom(layer.generator.seed);
  const density = layer.generator.density;
  const colour = layer.generator.colour;
  const gain = 10 ** (layer.gainDB / 20);
  const twoPiOverRate = 2 * Math.PI / sampleRate;
  let mass = 0;
  let body = 0;
  let surface = 0;
  let previousSurface = 0;
  let lapProgress = 1;
  let lapLengthFrames = sampleRate;
  let lapPhase = 0;
  let nextLapFrame = Math.round((0.55 + random() * 1.4) * sampleRate);
  let currentPan = boundedPan(layer.pan + (random() * 2 - 1) * 0.08);
  let targetPan = currentPan;
  let nextPanFrame = Math.round((1.5 + random() * 2.8) * sampleRate);

  for (let frame = 0; frame < frameCount; frame += 1) {
    const white = random() * 2 - 1;
    mass += (white - mass) * (0.00012 + density * 0.00016);
    body += (white - body) * (0.0011 + colour * 0.0028);
    surface += (white - surface) * (0.007 + colour * 0.012);
    const surfaceMovement = surface - previousSurface;
    previousSurface = surface;

    if (frame >= nextLapFrame) {
      lapProgress = 0;
      lapLengthFrames = Math.max(
        1,
        Math.round((0.72 + (1 - density) * 0.9 + random() * 1.35) * sampleRate),
      );
      lapPhase = random() * Math.PI * 0.35;
      const gapSeconds = 0.62 + (1 - density) * 1.7 + random() * 1.65;
      nextLapFrame = frame + Math.max(1, Math.round(gapSeconds * sampleRate));
    }

    if (frame >= nextPanFrame) {
      targetPan = boundedPan(layer.pan + (random() * 2 - 1) * (0.12 + density * 0.13));
      nextPanFrame = frame + Math.max(1, Math.round((1.8 + random() * 3.6) * sampleRate));
    }
    currentPan += (targetPan - currentPan) * 0.00009;
    const [leftPan, rightPan] = panGains(currentPan);

    let lapEnvelope = 0;
    if (lapProgress < 1) {
      const shaped = Math.sin(Math.PI * lapProgress);
      lapEnvelope = shaped * shaped;
      lapProgress += 1 / lapLengthFrames;
      lapPhase += (21 + colour * 17) * twoPiOverRate;
    }

    const flow = mass * (0.48 + density * 0.2) + body * (0.16 + colour * 0.08);
    const closeSurface = surfaceMovement * (0.45 + colour * 0.75);
    const lap = lapEnvelope * (
      body * (0.28 + density * 0.12)
      + Math.sin(lapPhase) * (0.025 + colour * 0.018)
    );
    const bounded = Math.tanh((flow + closeSurface + lap) * 1.35) * gain;
    left[frame] = bounded * leftPan;
    right[frame] = bounded * rightPan;
  }
  return { left, right };
}

function synthesizeDistantHumanPresence(layer, sampleRate, frameCount) {
  const left = new Float64Array(frameCount);
  const right = new Float64Array(frameCount);
  const density = layer.generator.density;
  const colour = layer.generator.colour;
  const gain = 10 ** (layer.gainDB / 20);
  const voiceCount = Math.min(7, 3 + Math.floor(density * 5));
  const voiceGain = gain / Math.sqrt(voiceCount);
  const twoPiOverRate = 2 * Math.PI / sampleRate;
  const voices = Array.from({ length: voiceCount }, (_, index) => {
    const derivedSeed = (layer.generator.seed + Math.imul(index + 1, 0x85ebca6b)) >>> 0;
    const random = seededRandom(derivedSeed || index + 1);
    const spread = voiceCount === 1 ? 0 : index / (voiceCount - 1) - 0.5;
    const pan = boundedPan(layer.pan + spread * 0.6 + (random() * 2 - 1) * 0.08);
    const [leftPan, rightPan] = panGains(pan);
    return {
      random,
      phase: random() * Math.PI * 2,
      secondPhase: random() * Math.PI * 2,
      breath: 0,
      envelope: 0,
      targetEnvelope: 0,
      nextEnvelopeFrame: Math.round((0.35 + random() * 1.8) * sampleRate),
      baseFrequency: 92 + random() * 76,
      driftPhase: random() * Math.PI * 2,
      leftPan,
      rightPan,
      targetLeftPan: leftPan,
      targetRightPan: rightPan,
      nextPanFrame: Math.round((1.4 + random() * 3.5) * sampleRate),
    };
  });

  for (let frame = 0; frame < frameCount; frame += 1) {
    let leftSample = 0;
    let rightSample = 0;
    for (const voice of voices) {
      if (frame >= voice.nextEnvelopeFrame) {
        voice.targetEnvelope = voice.targetEnvelope > 0
          ? 0
          : 0.34 + voice.random() * (0.36 + density * 0.18);
        const intervalSeconds = voice.targetEnvelope > 0
          ? 0.55 + voice.random() * (1.2 + density * 1.1)
          : 0.38 + (1 - density) * 1.8 + voice.random() * 1.7;
        voice.nextEnvelopeFrame = frame + Math.max(1, Math.round(intervalSeconds * sampleRate));
      }
      if (frame >= voice.nextPanFrame) {
        const targetPan = boundedPan(layer.pan + (voice.random() * 2 - 1) * 0.32);
        [voice.targetLeftPan, voice.targetRightPan] = panGains(targetPan);
        voice.nextPanFrame = frame + Math.max(
          1,
          Math.round((1.6 + voice.random() * 4.2) * sampleRate),
        );
      }
      voice.envelope += (voice.targetEnvelope - voice.envelope) * 0.00018;
      voice.leftPan += (voice.targetLeftPan - voice.leftPan) * 0.00008;
      voice.rightPan += (voice.targetRightPan - voice.rightPan) * 0.00008;
      voice.driftPhase += (0.025 + density * 0.018) * twoPiOverRate;
      const drift = Math.sin(voice.driftPhase) * (2.5 + colour * 3.5);
      const frequency = voice.baseFrequency + drift;
      voice.phase += frequency * twoPiOverRate;
      voice.secondPhase += frequency * (1.82 + colour * 0.22) * twoPiOverRate;
      const white = voice.random() * 2 - 1;
      voice.breath += (white - voice.breath) * (0.006 + colour * 0.008);
      const glottal = Math.tanh(Math.sin(voice.phase) * 2.1) * 0.075;
      const broadResonance = Math.sin(voice.secondPhase) * (0.018 + colour * 0.012);
      const breath = voice.breath * (0.035 + colour * 0.025);
      const sample = Math.tanh((glottal + broadResonance + breath) * 1.35)
        * voice.envelope
        * voiceGain;
      leftSample += sample * voice.leftPan;
      rightSample += sample * voice.rightPan;
    }
    left[frame] = leftSample;
    right[frame] = rightSample;
  }
  return { left, right };
}

function synthesizeLayer(layer, sampleRate, frameCount) {
  if (layer.generator.algorithm === "herd-ground-movement-v1") {
    return synthesizeHerdGroundMovement(layer, sampleRate, frameCount);
  }
  if (layer.generator.algorithm === "close-water-movement-v1") {
    return synthesizeCloseWaterMovement(layer, sampleRate, frameCount);
  }
  if (layer.generator.algorithm === "distant-human-presence-v1") {
    return synthesizeDistantHumanPresence(layer, sampleRate, frameCount);
  }
  const random = seededRandom(layer.generator.seed);
  const left = new Float64Array(frameCount);
  const right = new Float64Array(frameCount);
  const [leftPan, rightPan] = panGains(layer.pan);
  const gain = 10 ** (layer.gainDB / 20);
  const density = layer.generator.density;
  const colour = layer.generator.colour;
  let low = 0;
  let previousNoise = 0;
  let eventEnvelope = 0;
  let eventPhase = 0;
  let secondaryPhase = 0;
  const lowCoefficient = 0.002 + colour * 0.025;

  for (let frame = 0; frame < frameCount; frame += 1) {
    const white = random() * 2 - 1;
    low += (white - low) * lowCoefficient;
    const high = white - previousNoise;
    previousNoise = white;
    let sample = 0;

    switch (layer.generator.algorithm) {
      case "rain-on-earth-v1": {
        if (random() < (0.00015 + density * 0.0012)) eventEnvelope = 1;
        eventEnvelope *= 0.992 - colour * 0.002;
        sample = low * 0.32 + white * 0.055 + high * eventEnvelope * 0.12;
        break;
      }
      case "small-hearth-fire-v1": {
        if (random() < (0.00004 + density * 0.00035)) eventEnvelope = 1;
        eventEnvelope *= 0.965;
        sample = low * 0.42 + high * eventEnvelope * 0.5 + white * 0.018;
        break;
      }
      case "dry-grain-contact-v1": {
        if (random() < (0.00004 + density * 0.00025)) {
          eventEnvelope = 1;
          eventPhase = 0;
        }
        eventEnvelope *= 0.955;
        eventPhase += (1_100 + colour * 1_500) * (2 * Math.PI / sampleRate);
        sample = eventEnvelope * (Math.sin(eventPhase) * 0.14 + high * 0.34);
        break;
      }
      case "woven-fibre-friction-v1": {
        if (random() < (0.000015 + density * 0.00008)) eventEnvelope = 1;
        eventEnvelope = Math.max(0, eventEnvelope - (0.00003 + colour * 0.00003));
        sample = (white - low) * eventEnvelope * 0.22;
        break;
      }
      case "distant-material-work-v1": {
        if (random() < (0.000008 + density * 0.000035)) {
          eventEnvelope = 1;
          eventPhase = 0;
          secondaryPhase = 0;
        }
        eventEnvelope *= 0.9992 - colour * 0.00025;
        eventPhase += (105 + colour * 55) * (2 * Math.PI / sampleRate);
        secondaryPhase += (235 + colour * 110) * (2 * Math.PI / sampleRate);
        sample = eventEnvelope * (Math.sin(eventPhase) * 0.22 + Math.sin(secondaryPhase) * 0.08 + low * 0.1);
        break;
      }
      default:
        throw new AudioProductionError([`soundscape generator '${layer.generator.algorithm}': unsupported`]);
    }

    const bounded = Math.tanh(sample * 1.4) * gain;
    left[frame] = bounded * leftPan;
    right[frame] = bounded * rightPan;
  }
  return { left, right };
}

function writeSigned24LE(buffer, offset, value) {
  let encoded = value < 0 ? value + 0x1_000000 : value;
  buffer[offset] = encoded & 0xff;
  buffer[offset + 1] = (encoded >>> 8) & 0xff;
  buffer[offset + 2] = (encoded >>> 16) & 0xff;
}

export function encodePCM24StereoWAV(left, right, sampleRate = 48_000) {
  if (!(left instanceof Float64Array) || !(right instanceof Float64Array) || left.length !== right.length) {
    throw new AudioProductionError(["WAV encode: equal Float64Array channels required"]);
  }
  const blockAlign = 6;
  const dataBytes = left.length * blockAlign;
  const buffer = Buffer.alloc(44 + dataBytes);
  buffer.write("RIFF", 0, 4, "ascii");
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write("WAVE", 8, 4, "ascii");
  buffer.write("fmt ", 12, 4, "ascii");
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(2, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * blockAlign, 28);
  buffer.writeUInt16LE(blockAlign, 32);
  buffer.writeUInt16LE(24, 34);
  buffer.write("data", 36, 4, "ascii");
  buffer.writeUInt32LE(dataBytes, 40);
  for (let index = 0; index < left.length; index += 1) {
    const leftValue = Math.max(-1, Math.min(0.9999998807907104, left[index]));
    const rightValue = Math.max(-1, Math.min(0.9999998807907104, right[index]));
    writeSigned24LE(buffer, 44 + index * blockAlign, Math.round(leftValue * 8_388_607));
    writeSigned24LE(buffer, 47 + index * blockAlign, Math.round(rightValue * 8_388_607));
  }
  return buffer;
}

export function renderProceduralSoundscapeLayers(plan) {
  validateSoundscapeProductionPlan(plan);
  const frames = Math.round(plan.durationSeconds * plan.output.sampleRate);
  return new Map(plan.layers.map((layer) => {
    const rendered = synthesizeLayer(layer, plan.output.sampleRate, frames);
    return [layer.id, encodePCM24StereoWAV(rendered.left, rendered.right, plan.output.sampleRate)];
  }));
}

export function inspectPCM24StereoWAV(buffer) {
  const issues = [];
  if (!Buffer.isBuffer(buffer) || buffer.length < 44) issues.push("WAV: at least 44 bytes required");
  if (buffer?.toString("ascii", 0, 4) !== "RIFF" || buffer?.toString("ascii", 8, 12) !== "WAVE") {
    issues.push("WAV: RIFF/WAVE header required");
  }
  if (buffer?.toString("ascii", 12, 16) !== "fmt " || buffer?.toString("ascii", 36, 40) !== "data") {
    issues.push("WAV: canonical PCM fmt/data layout required");
  }
  const format = buffer?.readUInt16LE(20);
  const channels = buffer?.readUInt16LE(22);
  const sampleRate = buffer?.readUInt32LE(24);
  const bitDepth = buffer?.readUInt16LE(34);
  const dataBytes = buffer?.readUInt32LE(40);
  if (format !== 1) issues.push("WAV: integer PCM required");
  if (channels !== 2) issues.push("WAV: stereo required");
  if (sampleRate !== 48_000) issues.push("WAV: 48000 Hz required");
  if (bitDepth !== 24) issues.push("WAV: 24-bit required");
  if (dataBytes !== buffer?.length - 44 || dataBytes % 6 !== 0) issues.push("WAV: exact stereo data length required");
  if (issues.length) throw new AudioProductionError(issues);
  return { sampleRate, bitDepth, channels, frames: dataBytes / 6 };
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

async function hashFile(file) {
  const bytes = await readFile(file);
  return { bytes: bytes.length, sha256: sha256(bytes) };
}

async function exactProductionInput(id, file) {
  const record = await hashFile(file);
  const relative = path.relative(repositoryRoot, path.resolve(file)).split(path.sep).join("/");
  if (!relative || relative.startsWith("../")) {
    throw new AudioProductionError([`${id}: production input escaped the repository`]);
  }
  return { id, path: relative, ...record };
}

export function validateAudioToolchain(toolchain) {
  const issues = [];
  exactKeys(toolchain, ["schemaVersion", "status", "fluidSynth", "soundFont", "ffmpeg"], "toolchain", issues);
  if (toolchain?.schemaVersion !== 1) issues.push("toolchain.schemaVersion: expected 1");
  if (toolchain?.status !== "PINNED_ZERO_COST_CANDIDATE") {
    issues.push("toolchain.status: pinned candidate status required");
  }
  exactKeys(toolchain?.fluidSynth, [
    "version", "sourceCommit", "sourceArchiveSHA256", "installedBinarySHA256", "license", "sourceURL",
  ], "toolchain.fluidSynth", issues);
  exactKeys(toolchain?.soundFont, [
    "version", "repositoryCommit", "repositoryBlobSHA1", "bytes", "sha256", "license", "sourceURL", "licenseURL", "requiredNotice",
    "noticePath", "noticeBytes", "noticeSHA256",
  ], "toolchain.soundFont", issues);
  exactKeys(toolchain?.ffmpeg, ["version", "installedBinarySHA256", "license", "source"], "toolchain.ffmpeg", issues);
  for (const [location, value] of [
    ["toolchain.fluidSynth.sourceArchiveSHA256", toolchain?.fluidSynth?.sourceArchiveSHA256],
    ["toolchain.fluidSynth.installedBinarySHA256", toolchain?.fluidSynth?.installedBinarySHA256],
    ["toolchain.soundFont.sha256", toolchain?.soundFont?.sha256],
    ["toolchain.soundFont.noticeSHA256", toolchain?.soundFont?.noticeSHA256],
    ["toolchain.ffmpeg.installedBinarySHA256", toolchain?.ffmpeg?.installedBinarySHA256],
  ]) {
    if (typeof value !== "string" || !sha256Pattern.test(value)) issues.push(`${location}: lowercase SHA-256 required`);
  }
  if (typeof toolchain?.fluidSynth?.sourceCommit !== "string"
      || !/^[a-f0-9]{40}$/u.test(toolchain.fluidSynth.sourceCommit)) {
    issues.push("toolchain.fluidSynth.sourceCommit: full Git commit required");
  }
  if (typeof toolchain?.soundFont?.repositoryCommit !== "string"
      || !/^[a-f0-9]{40}$/u.test(toolchain.soundFont.repositoryCommit)) {
    issues.push("toolchain.soundFont.repositoryCommit: full Git commit required");
  }
  if (typeof toolchain?.soundFont?.repositoryBlobSHA1 !== "string"
      || !/^[a-f0-9]{40}$/u.test(toolchain.soundFont.repositoryBlobSHA1)) {
    issues.push("toolchain.soundFont.repositoryBlobSHA1: Git blob SHA-1 required");
  }
  integer(toolchain?.soundFont?.bytes, "toolchain.soundFont.bytes", issues, 1, Number.MAX_SAFE_INTEGER);
  integer(toolchain?.soundFont?.noticeBytes, "toolchain.soundFont.noticeBytes", issues, 1, Number.MAX_SAFE_INTEGER);
  for (const location of [
    "toolchain.fluidSynth.license", "toolchain.fluidSynth.sourceURL",
    "toolchain.soundFont.license", "toolchain.soundFont.sourceURL",
    "toolchain.soundFont.licenseURL", "toolchain.soundFont.requiredNotice",
    "toolchain.soundFont.noticePath",
    "toolchain.ffmpeg.license", "toolchain.ffmpeg.source",
  ]) {
    const value = location.split(".").slice(1).reduce((record, key) => record?.[key], toolchain);
    authoredString(value, location, issues);
  }
  if (!/^https:\/\/github\.com\/FluidSynth\/fluidsynth\/tree\/[a-f0-9]{40}$/u
    .test(toolchain?.fluidSynth?.sourceURL ?? "")) {
    issues.push("toolchain.fluidSynth.sourceURL: pinned official FluidSynth commit URL required");
  }
  const pinnedMuseScorePrefix = `https://raw.githubusercontent.com/musescore/MuseScore/${toolchain?.soundFont?.repositoryCommit}/share/sound/`;
  if (!(toolchain?.soundFont?.sourceURL ?? "").startsWith(pinnedMuseScorePrefix)
      || !(toolchain?.soundFont?.licenseURL ?? "").startsWith(pinnedMuseScorePrefix)) {
    issues.push("toolchain.soundFont: bytes and licence must share the pinned official MuseScore commit");
  }
  if (!/^LGPL-2\.1-or-later\b/u.test(toolchain?.fluidSynth?.license ?? "")) {
    issues.push("toolchain.fluidSynth.license: LGPL-2.1-or-later record required");
  }
  if (toolchain?.soundFont?.license !== "MIT") {
    issues.push("toolchain.soundFont.license: MIT record required");
  }
  if (!/^licenses\/[A-Za-z0-9._-]+\.md$/u.test(toolchain?.soundFont?.noticePath ?? "")) {
    issues.push("toolchain.soundFont.noticePath: confined Markdown notice path required");
  }
  if (issues.length) throw new AudioProductionError(issues);
  return toolchain;
}

async function verifyPinnedNotice(toolchain, toolchainPath) {
  const noticePath = path.resolve(path.dirname(toolchainPath), toolchain.soundFont.noticePath);
  const audioRoot = `${path.resolve(path.dirname(toolchainPath))}${path.sep}`;
  if (!noticePath.startsWith(audioRoot)) {
    throw new AudioProductionError(["toolchain.soundFont.noticePath: path escaped the audio production tree"]);
  }
  const notice = await hashFile(noticePath).catch(() => undefined);
  if (!notice
      || notice.bytes !== toolchain.soundFont.noticeBytes
      || notice.sha256 !== toolchain.soundFont.noticeSHA256) {
    throw new AudioProductionError(["toolchain.soundFont: required MIT notice bytes are missing or changed"]);
  }
  return {
    path: toolchain.soundFont.noticePath,
    bytes: notice.bytes,
    sha256: notice.sha256,
  };
}

export async function validateAudioRendererRuntime({
  toolchain,
  soundFontPath,
  fluidSynthPath = "/opt/homebrew/bin/fluidsynth",
}) {
  validateAudioToolchain(toolchain);
  const [soundFont, fluidSynth] = await Promise.all([
    hashFile(soundFontPath),
    hashFile(fluidSynthPath),
  ]).catch(() => {
    throw new AudioProductionError(["audio renderer preflight: pinned FluidSynth binary and SoundFont are both required"]);
  });
  if (soundFont.bytes !== toolchain.soundFont.bytes || soundFont.sha256 !== toolchain.soundFont.sha256) {
    throw new AudioProductionError(["toolchain.soundFont: cached bytes do not match the pinned official source"]);
  }
  if (fluidSynth.sha256 !== toolchain.fluidSynth.installedBinarySHA256) {
    throw new AudioProductionError(["toolchain.fluidSynth: installed binary hash differs from the pinned toolchain"]);
  }
  const version = spawnSync(fluidSynthPath, ["--version"], { encoding: "utf8" });
  const versionText = `${version.stdout ?? ""}\n${version.stderr ?? ""}`;
  if (version.status !== 0 || !versionText.includes(`FluidSynth runtime version ${toolchain.fluidSynth.version}`)) {
    throw new AudioProductionError(["toolchain.fluidSynth: executable version does not match the pinned toolchain"]);
  }
  return { soundFont, fluidSynth };
}

export async function renderAudioTechnicalProbe({
  scorePlan,
  soundscapePlan,
  toolchain,
  outputDirectory,
  soundFontPath,
  fluidSynthPath = "/opt/homebrew/bin/fluidsynth",
  noticeRecord = undefined,
  productionInputs = undefined,
  nodeRuntime = undefined,
}) {
  validateScoreProductionPlan(scorePlan);
  validateSoundscapeProductionPlan(soundscapePlan);
  const { soundFont, fluidSynth } = await validateAudioRendererRuntime({
    toolchain,
    soundFontPath,
    fluidSynthPath,
  });
  await mkdir(outputDirectory, { recursive: true });

  const outputs = [];
  for (const stem of scorePlan.stems) {
    const midi = compileScoreStemMIDI(scorePlan, stem.id);
    const midiName = `score-${stem.id}.mid`;
    const wavName = `score-${stem.id}.wav`;
    const midiPath = path.join(outputDirectory, midiName);
    const wavPath = path.join(outputDirectory, wavName);
    await writeFile(midiPath, midi);
    const render = spawnSync(fluidSynthPath, [
      "-ni", "-q", "-C", "0", "-R", "0", "-g", "2.5", "-r", "48000",
      "-o", "synth.cpu-cores=1", "-O", "s24", "-T", "wav", "-F", wavPath,
      soundFontPath, midiPath,
    ], { encoding: "utf8" });
    if (render.status !== 0) {
      throw new AudioProductionError([
        `FluidSynth ${stem.id}: render failed`,
        render.stderr?.trim() || render.stdout?.trim() || "no diagnostic",
      ]);
    }
    const wav = await readFile(wavPath);
    const format = inspectPCM24StereoWAV(wav);
    outputs.push({ role: "score", stemID: stem.id, path: midiName, ...await hashFile(midiPath) });
    outputs.push({ role: "score", stemID: stem.id, path: wavName, ...await hashFile(wavPath), format });
  }

  for (const [layerID, wav] of renderProceduralSoundscapeLayers(soundscapePlan)) {
    const fileName = `soundscape-${layerID}.wav`;
    const file = path.join(outputDirectory, fileName);
    await writeFile(file, wav);
    outputs.push({
      role: "soundscape",
      layerID,
      path: fileName,
      bytes: wav.length,
      sha256: sha256(wav),
      format: inspectPCM24StereoWAV(wav),
    });
  }

  return {
    schemaVersion: 1,
    status: "TECHNICAL_PROBE_NOT_APPROVED",
    inputs: productionInputs,
    toolchain: {
      fluidSynthVersion: toolchain.fluidSynth.version,
      fluidSynthBinarySHA256: fluidSynth.sha256,
      soundFontVersion: toolchain.soundFont.version,
      soundFontSHA256: soundFont.sha256,
      notice: noticeRecord,
      nodeRuntime,
    },
    authoredSilence: soundscapePlan.silenceWindows,
    outputs,
    gates: {
      technicalFormat: "PASS",
      symbolicEditability: "PASS",
      independentStems: "PASS",
      commercialRights: "PASS_WITH_RECORDED_MIT_NOTICE",
      artisticHarvestApproval: "OPEN",
      seamAndTruePeakAudit: "OPEN",
    },
  };
}

export async function readAudioProductionFiles(scorePath, soundscapePath, toolchainPath) {
  const [scoreBytes, soundscapeBytes, toolchainBytes] = await Promise.all([
    readFile(scorePath),
    readFile(soundscapePath),
    readFile(toolchainPath),
  ]);
  const scorePlan = JSON.parse(scoreBytes.toString("utf8"));
  const soundscapePlan = JSON.parse(soundscapeBytes.toString("utf8"));
  const toolchain = JSON.parse(toolchainBytes.toString("utf8"));
  validateScoreProductionPlan(scorePlan);
  validateSoundscapeProductionPlan(soundscapePlan);
  validateAudioToolchain(toolchain);
  const noticeRecord = await verifyPinnedNotice(toolchain, toolchainPath);
  const [scoreInput, soundscapeInput, toolchainInput, rendererInput, schemaInput, nodeBinary] = await Promise.all([
    exactProductionInput(scorePlan.id, scorePath),
    exactProductionInput(soundscapePlan.id, soundscapePath),
    exactProductionInput("score-soundscape-toolchain", toolchainPath),
    exactProductionInput("audio-production-renderer", modulePath),
    exactProductionInput("audio-production-schema", audioProductionSchemaPath),
    hashFile(process.execPath),
  ]);
  const productionInputs = [scoreInput, soundscapeInput, toolchainInput, rendererInput, schemaInput];
  const nodeRuntime = {
    version: process.version,
    executableSHA256: nodeBinary.sha256,
    executableBytes: nodeBinary.bytes,
  };
  return {
    scorePlan,
    soundscapePlan,
    toolchain,
    noticeRecord,
    productionInputs,
    nodeRuntime,
  };
}

export async function validateAudioProductionEvidence({
  files,
  costRegistryPath,
  receiptPath,
}) {
  const [costBytes, receiptBytes] = await Promise.all([
    readFile(costRegistryPath),
    readFile(receiptPath),
  ]).catch(() => {
    throw new AudioProductionError(["audio evidence: cost registry and technical receipt are required"]);
  });
  const costRegistry = JSON.parse(costBytes.toString("utf8"));
  const receipt = JSON.parse(receiptBytes.toString("utf8"));
  const entries = new Map((costRegistry.entries ?? []).map((entry) => [entry.id, entry]));
  const requiredEntry = (id) => {
    const entry = entries.get(id);
    if (!entry) throw new AudioProductionError([`audio evidence: cost registry is missing '${id}'`]);
    return entry;
  };
  const inputByID = new Map(files.productionInputs.map((input) => [input.id, input]));
  const renderer = inputByID.get("audio-production-renderer");
  const schema = inputByID.get("audio-production-schema");
  const expectedProductionVersion = [
    "1",
    `renderer SHA-256 ${renderer.sha256}`,
    `authoring schema SHA-256 ${schema.sha256}`,
    `Node ${files.nodeRuntime.version} executable SHA-256 ${files.nodeRuntime.executableSHA256}`,
  ].join("; ");
  if (requiredEntry("audio-production-local").version !== expectedProductionVersion) {
    throw new AudioProductionError(["audio evidence: audio-production-local version/hash binding drifted"]);
  }
  const expectedFluidSynthVersion = [
    files.toolchain.fluidSynth.version,
    `source ${files.toolchain.fluidSynth.sourceCommit}`,
    `source archive SHA-256 ${files.toolchain.fluidSynth.sourceArchiveSHA256}`,
    `installed binary SHA-256 ${files.toolchain.fluidSynth.installedBinarySHA256}`,
  ].join("; ");
  if (requiredEntry("fluid-synth-local").version !== expectedFluidSynthVersion) {
    throw new AudioProductionError(["audio evidence: FluidSynth cost/evidence binding drifted"]);
  }
  const expectedSoundFontVersion = [
    files.toolchain.soundFont.version.replace(/^MS Basic\s+/u, ""),
    `repository commit ${files.toolchain.soundFont.repositoryCommit}`,
    `blob ${files.toolchain.soundFont.repositoryBlobSHA1}`,
    `${files.toolchain.soundFont.bytes} bytes`,
    `SHA-256 ${files.toolchain.soundFont.sha256}`,
    `notice SHA-256 ${files.toolchain.soundFont.noticeSHA256}`,
  ].join("; ");
  if (requiredEntry("musescore-ms-basic-sf3").version !== expectedSoundFontVersion) {
    throw new AudioProductionError(["audio evidence: MS Basic bank/notice cost binding drifted"]);
  }
  if (receipt.status !== "TECHNICAL_PROBE_NOT_APPROVED"
      || JSON.stringify(receipt.inputs) !== JSON.stringify(files.productionInputs)
      || receipt.toolchain?.fluidSynthVersion !== files.toolchain.fluidSynth.version
      || receipt.toolchain?.fluidSynthBinarySHA256 !== files.toolchain.fluidSynth.installedBinarySHA256
      || receipt.toolchain?.soundFontVersion !== files.toolchain.soundFont.version
      || receipt.toolchain?.soundFontSHA256 !== files.toolchain.soundFont.sha256
      || JSON.stringify(receipt.toolchain?.notice) !== JSON.stringify(files.noticeRecord)
      || JSON.stringify(receipt.toolchain?.nodeRuntime) !== JSON.stringify(files.nodeRuntime)) {
    throw new AudioProductionError(["audio evidence: technical receipt no longer binds the exact production cause"]);
  }
  const receiptSHA256 = sha256(receiptBytes);
  for (const id of ["authored-score-rendering", "soundscape-generation"]) {
    const version = requiredEntry(id).version;
    if (!version.endsWith(`technical receipt SHA-256 ${receiptSHA256}`)) {
      throw new AudioProductionError([`audio evidence: ${id} receipt binding drifted`]);
    }
  }
  return { receiptSHA256, receipt };
}
