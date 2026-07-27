#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstat, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SHA256_PATTERN = /^[0-9a-f]{64}$/u;
const ATTEMPT_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/u;
const MAXIMUM_PHYSICAL_FOOTPRINT_BYTES = 500 * 1_024 * 1_024;
const MAXIMUM_RESTORE_FRAME_NANOSECONDS = 1_500_000_000;
const MAXIMUM_FULL_INTERACTIVITY_NANOSECONDS = 2_000_000_000;
const REQUIRED_AUDIO_SAMPLE_RATE = 48_000;
const MAXIMUM_HARD_KILL_AUDIO_ERROR_SAMPLES = 12_000;

export const firstFarmersBeatCoverage = Object.freeze([
  {
    beatID: "beat-first-farmers-river-world",
    sceneID: "scene-first-farmers-iron-gates-dawn",
  },
  {
    beatID: "beat-first-farmers-household-crosses",
    sceneID: "scene-first-farmers-aegean-crossing",
    interactionID: "interaction-first-farmers-a-household-crosses",
  },
  {
    beatID: "beat-first-farmers-living-system",
    sceneID: "scene-first-farmers-thessaly-landing",
  },
  {
    beatID: "beat-first-farmers-european-ground",
    sceneID: "scene-first-farmers-thessaly-first-season",
  },
  {
    beatID: "beat-first-farmers-inhabited-frontier",
    sceneID: "scene-first-farmers-danube-arrival",
  },
  {
    beatID: "beat-first-farmers-harvest-allocation",
    sceneID: "harvest-allocation-option-1",
    interactionID: "interaction-first-farmers-the-harvest-had-to-last",
  },
  {
    beatID: "beat-first-farmers-stored-future",
    sceneID: "scene-first-farmers-store-committed",
  },
  {
    beatID: "beat-first-farmers-gorge-contact",
    sceneID: "scene-first-farmers-iron-gates-contact",
  },
  {
    beatID: "beat-first-farmers-three-records",
    sceneID: "scene-first-farmers-iron-gates-transformation",
    interactionID: "interaction-first-farmers-at-the-iron-gates",
  },
  {
    beatID: "beat-first-farmers-frontier-consequence",
    sceneID: "scene-first-farmers-danube-to-loess",
  },
  {
    beatID: "beat-first-farmers-raise-longhouse",
    sceneID: "scene-first-farmers-longhouse-assembly",
    interactionID: "interaction-first-farmers-the-house-outlives",
  },
  {
    beatID: "beat-first-farmers-plot-remains",
    sceneID: "scene-first-farmers-longhouse-rebuilt",
  },
  {
    beatID: "beat-first-farmers-paternal-lines",
    sceneID: "scene-first-farmers-household-descent",
  },
  {
    beatID: "beat-first-farmers-more-mouths",
    sceneID: "scene-first-farmers-settlement-growth",
    interactionID: "interaction-first-farmers-more-mouths-more-land",
  },
  {
    beatID: "beat-first-farmers-growth-breaks",
    sceneID: "scene-first-farmers-local-contraction",
  },
  {
    beatID: "beat-first-farmers-continent-remade",
    sceneID: "scene-first-farmers-europe-transformation",
    interactionID: "interaction-first-farmers-a-continent-remade",
  },
  {
    beatID: "beat-first-farmers-before-steppe",
    sceneID: "scene-first-farmers-steppe-handoff",
  },
]);

export const firstFarmersInteractionCoverage = Object.freeze(
  firstFarmersBeatCoverage
    .filter((beat) => beat.interactionID)
    .map((beat) => Object.freeze({
      interactionID: beat.interactionID,
      sceneID: beat.sceneID,
    })),
);

function assertExactKeys(value, keys, label) {
  assert.ok(value && typeof value === "object" && !Array.isArray(value), `${label} must be an object`);
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), `${label} fields drifted`);
}

function assertSHA256(value, label) {
  assert.match(value, SHA256_PATTERN, `${label} must be a lowercase SHA-256`);
}

function assertAttemptID(value, label) {
  assert.match(value, ATTEMPT_ID_PATTERN, `${label} is not a safe attempt ID`);
}

function assertFiniteNumber(value, label) {
  assert.equal(typeof value, "number", `${label} must be numeric`);
  assert.ok(Number.isFinite(value), `${label} must be finite`);
}

function assertCheckpointSequence(value, label) {
  assert.ok(Number.isSafeInteger(value) && value > 0, `${label} must be a positive sequence`);
}

function assertSafeRelativePath(relativePath, label) {
  assert.equal(typeof relativePath, "string", `${label} path must be a string`);
  assert.ok(relativePath.length > 0, `${label} path is empty`);
  assert.equal(path.isAbsolute(relativePath), false, `${label} path must be relative`);
  assert.equal(relativePath.includes("\\"), false, `${label} path must use forward slashes`);
  const segments = relativePath.split("/");
  assert.equal(segments.includes(""), false, `${label} path contains an empty segment`);
  assert.equal(segments.includes("."), false, `${label} path contains a current-directory segment`);
  assert.equal(segments.includes(".."), false, `${label} path escapes the artifact root`);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function readBoundArtifact(artifact, label, context) {
  assertExactKeys(artifact, ["path", "sha256"], label);
  assertSafeRelativePath(artifact.path, label);
  assertSHA256(artifact.sha256, `${label}.sha256`);
  const absolutePath = path.resolve(context.artifactsRoot, artifact.path);
  const relativeToRoot = path.relative(context.artifactsRoot, absolutePath);
  assert.ok(
    relativeToRoot && !relativeToRoot.startsWith(`..${path.sep}`) && relativeToRoot !== "..",
    `${label} resolved outside the artifact root`,
  );
  const fileInfo = await lstat(absolutePath);
  assert.equal(fileInfo.isSymbolicLink(), false, `${label} cannot be a symbolic link`);
  assert.equal(fileInfo.isFile(), true, `${label} must be a retained regular-file archive`);
  assert.equal(context.usedArtifactPaths.has(absolutePath), false, `${label} reuses another run artifact`);
  context.usedArtifactPaths.add(absolutePath);
  const bytes = await readFile(absolutePath);
  assert.ok(bytes.length > 0, `${label} is empty`);
  assert.equal(sha256(bytes), artifact.sha256, `${label} bytes do not match their SHA-256`);
  return bytes;
}

async function readRawReport(artifact, label, context) {
  const bytes = await readBoundArtifact(artifact, label, context);
  let report;
  try {
    report = JSON.parse(bytes);
  } catch {
    assert.fail(`${label} is not valid JSON`);
  }
  return report;
}

function validateRawReportIdentity(report, expected, identity, label) {
  assert.equal(report.schemaVersion, 1, `${label} schema drifted`);
  assert.equal(report.protocolID, "port1-physical-device-v1", `${label} protocol drifted`);
  assert.equal(report.runID, expected.runID, `${label} run ID drifted`);
  assert.equal(report.attemptID, expected.attemptID, `${label} attempt ID drifted`);
  assert.equal(report.repetition, expected.repetition, `${label} repetition drifted`);
  assert.equal(
    report.gateClassification,
    "DEVICE_RAW_MEASUREMENTS_ONLY",
    `${label} is not raw physical-device evidence`,
  );
  assert.equal(
    report.localTimingScope,
    "COMMAND_BUFFER_AND_GPU_COMPLETION_PROXY_ONLY",
    `${label} local timing scope drifted`,
  );
  assert.equal(report.platform?.captureClass, "PHYSICAL_DEVICE", `${label} is not from an iPhone`);
  assert.equal(report.platform?.buildConfiguration, "RELEASE", `${label} is not a Release build`);
  const hardwareMatch = /^iPhone(\d+),(\d+)$/u.exec(report.platform?.hardwareModel ?? "");
  assert.ok(
    hardwareMatch && Number(hardwareMatch[1]) >= 16,
    `${label} is not from the iPhone 15 Pro performance class or newer`,
  );
  const operatingSystemMatch = /(?:iOS|Version)\s+(\d+)/u.exec(
    report.platform?.operatingSystem ?? "",
  );
  assert.ok(
    operatingSystemMatch && Number(operatingSystemMatch[1]) >= 26,
    `${label} is not from the required iOS generation`,
  );
  assert.equal(report.appBuildHashKind, "APP_BUNDLE_FILE_TREE_SHA256", `${label} app hash kind drifted`);
  assert.equal(report.appBuildSHA256, identity.appBuildSHA256, `${label} app build does not match`);
  assert.deepEqual(report.packages, [
    {
      packageID: "essential-free-v1",
      manifestSHA256: identity.packageManifestSHA256,
    },
  ], `${label} does not bind the exact signed production package`);
  assert.equal(report.rawTraceRetentionRequired, true, `${label} did not retain raw traces`);
  assert.ok(
    Number.isSafeInteger(report.captureEndedNanosecondsSinceProcessStart)
      && report.captureEndedNanosecondsSinceProcessStart > 0,
    `${label} capture end is missing`,
  );
  assert.deepEqual(report.instrumentationFailures, [], `${label} contains instrumentation failures`);
  for (const [property, description] of [
    ["frameCommandBufferCompletionProxies", "frame measurements"],
    ["interactionCommandBufferCompletionProxies", "interaction measurements"],
    ["physicalFootprint", "memory measurements"],
    ["thermalTransitions", "thermal measurements"],
  ]) {
    assert.ok(Array.isArray(report[property]), `${label} ${description} are missing`);
  }
  assert.ok(report.frameCommandBufferCompletionProxies.length > 0, `${label} has no frame measurements`);
  assert.ok(report.physicalFootprint.length > 0, `${label} has no memory measurements`);
  assert.ok(report.thermalTransitions.length > 0, `${label} has no thermal measurements`);

  const maximumFootprint = Math.max(
    ...report.physicalFootprint.map((measurement) => measurement.physicalFootprintBytes),
  );
  assert.ok(
    Number.isSafeInteger(maximumFootprint) && maximumFootprint > 0,
    `${label} memory measurements are invalid`,
  );
  assert.ok(
    maximumFootprint <= MAXIMUM_PHYSICAL_FOOTPRINT_BYTES,
    `${label} exceeds the 500 MiB physical-footprint budget`,
  );
  const thermalStates = report.thermalTransitions.map((measurement) => measurement.to);
  assert.ok(
    thermalStates.every((state) => state === "NOMINAL" || state === "FAIR"),
    `${label} entered a prohibited thermal state`,
  );
}

function validateBatteryMeasurement(run, report, label) {
  assert.ok(Number.isSafeInteger(run.durationSeconds), `${label} duration must be whole seconds`);
  assert.ok(run.durationSeconds >= 1_800, `${label} did not run for 30 minutes`);
  const captureStarts = report.physicalFootprint.filter(
    (measurement) => measurement.trigger === "CAPTURE_START",
  );
  assert.equal(captureStarts.length, 1, `${label} must contain one capture-start sample`);
  const captureStart = captureStarts[0].nanosecondsSinceProcessStart;
  assert.ok(
    Number.isSafeInteger(captureStart)
      && report.captureEndedNanosecondsSinceProcessStart >= captureStart,
    `${label} capture window is invalid`,
  );
  const measuredDurationNanoseconds =
    report.captureEndedNanosecondsSinceProcessStart - captureStart;
  assert.ok(
    measuredDurationNanoseconds >= run.durationSeconds * 1_000_000_000,
    `${label} raw report does not prove its declared duration`,
  );
  assert.ok(
    Number.isSafeInteger(run.startingBatteryPercent)
      && run.startingBatteryPercent >= 80
      && run.startingBatteryPercent <= 100,
    `${label} starting battery is outside the protocol range`,
  );
  assert.ok(
    Number.isSafeInteger(run.endingBatteryPercent)
      && run.endingBatteryPercent >= 0
      && run.endingBatteryPercent <= run.startingBatteryPercent,
    `${label} ending battery is invalid`,
  );
  return run.startingBatteryPercent - run.endingBatteryPercent;
}

function validateChapterCoverage(report, label) {
  const frames = report.frameCommandBufferCompletionProxies;
  let frameCursor = -1;
  for (const beat of firstFarmersBeatCoverage) {
    const nextIndex = frames.findIndex(
      (frame, index) => index > frameCursor && frame.sceneID === beat.sceneID,
    );
    assert.ok(nextIndex > frameCursor, `${label} has no ordered frame evidence for ${beat.beatID}`);
    frameCursor = nextIndex;
  }

  const frameScenesByID = new Map(frames.map((frame) => [frame.frameID, frame.sceneID]));
  const actionScenes = new Set(
    report.interactionCommandBufferCompletionProxies.map(
      (measurement) => frameScenesByID.get(measurement.completedFrameID),
    ),
  );
  for (const interaction of firstFarmersInteractionCoverage) {
    assert.ok(
      actionScenes.has(interaction.sceneID),
      `${label} has no completed action measurement for ${interaction.interactionID}`,
    );
  }
  assert.ok(report.physicalFootprint.length >= 2, `${label} lacks sustained memory sampling`);
}

function median(values) {
  const ordered = [...values].sort((left, right) => left - right);
  return ordered[Math.floor(ordered.length / 2)];
}

async function validateReferenceRun(run, repetition, identity, context, label) {
  assertExactKeys(run, [
    "runID",
    "attemptID",
    "rawReport",
    "durationSeconds",
    "startingBatteryPercent",
    "endingBatteryPercent",
    "metalSystemTraceArchive",
    "energyTraceArchive",
  ], label);
  assert.equal(run.runID, "first-farmers-static-reference", `${label} run ID drifted`);
  assertAttemptID(run.attemptID, `${label}.attemptID`);
  const report = await readRawReport(run.rawReport, `${label}.rawReport`, context);
  validateRawReportIdentity(
    report,
    { runID: run.runID, attemptID: run.attemptID, repetition },
    identity,
    `${label}.rawReport`,
  );
  const batteryDrop = validateBatteryMeasurement(run, report, label);
  await readBoundArtifact(
    run.metalSystemTraceArchive,
    `${label}.metalSystemTraceArchive`,
    context,
  );
  await readBoundArtifact(run.energyTraceArchive, `${label}.energyTraceArchive`, context);
  return batteryDrop;
}

async function validateChapterRun(run, repetition, identity, context, label) {
  assertExactKeys(run, [
    "runID",
    "attemptID",
    "rawReport",
    "durationSeconds",
    "startingBatteryPercent",
    "endingBatteryPercent",
    "displayedFrameP99Milliseconds",
    "inputToVisibleP99Milliseconds",
    "metalSystemTraceArchive",
    "energyTraceArchive",
  ], label);
  assert.equal(run.runID, "first-farmers-sustained", `${label} run ID drifted`);
  assertAttemptID(run.attemptID, `${label}.attemptID`);
  const report = await readRawReport(run.rawReport, `${label}.rawReport`, context);
  validateRawReportIdentity(
    report,
    { runID: run.runID, attemptID: run.attemptID, repetition },
    identity,
    `${label}.rawReport`,
  );
  validateChapterCoverage(report, label);
  assertFiniteNumber(run.displayedFrameP99Milliseconds, `${label} displayed-frame p99`);
  assert.ok(
    run.displayedFrameP99Milliseconds > 0 && run.displayedFrameP99Milliseconds <= 25,
    `${label} exceeds the displayed-frame p99 budget`,
  );
  assertFiniteNumber(run.inputToVisibleP99Milliseconds, `${label} input-to-visible p99`);
  assert.ok(
    run.inputToVisibleP99Milliseconds > 0 && run.inputToVisibleP99Milliseconds <= 50,
    `${label} exceeds the input-to-visible budget`,
  );
  const batteryDrop = validateBatteryMeasurement(run, report, label);
  assert.ok(batteryDrop <= 8, `${label} exceeds the absolute battery budget`);
  await readBoundArtifact(
    run.metalSystemTraceArchive,
    `${label}.metalSystemTraceArchive`,
    context,
  );
  await readBoundArtifact(run.energyTraceArchive, `${label}.energyTraceArchive`, context);
  return batteryDrop;
}

async function validateColdRestoreRun(run, index, identity, context) {
  const label = `coldRestoreRuns[${index}]`;
  assertExactKeys(run, [
    "runID",
    "repetition",
    "attemptID",
    "interactionID",
    "rawReport",
    "metalSystemTraceArchive",
  ], label);
  const expected = firstFarmersInteractionCoverage[index];
  assert.equal(run.runID, "cold-restore", `${label} run ID drifted`);
  assert.equal(run.repetition, index + 1, `${label} repetition drifted`);
  assert.equal(run.interactionID, expected.interactionID, `${label} interaction coverage drifted`);
  assertAttemptID(run.attemptID, `${label}.attemptID`);
  const report = await readRawReport(run.rawReport, `${label}.rawReport`, context);
  validateRawReportIdentity(
    report,
    { runID: run.runID, attemptID: run.attemptID, repetition: run.repetition },
    identity,
    `${label}.rawReport`,
  );
  assert.ok(
    report.frameCommandBufferCompletionProxies.some((frame) => frame.sceneID === expected.sceneID),
    `${label} did not restore the scene for ${expected.interactionID}`,
  );
  const frameScenesByID = new Map(
    report.frameCommandBufferCompletionProxies.map((frame) => [frame.frameID, frame.sceneID]),
  );
  assert.ok(
    report.interactionCommandBufferCompletionProxies.some(
      (measurement) => frameScenesByID.get(measurement.completedFrameID) === expected.sceneID,
    ),
    `${label} did not exercise ${expected.interactionID} after restoration`,
  );
  const restoredFrame =
    report.launch?.restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart;
  assert.ok(
    Number.isSafeInteger(restoredFrame)
      && restoredFrame >= 0
      && restoredFrame <= MAXIMUM_RESTORE_FRAME_NANOSECONDS,
    `${label} did not restore a frame within 1.5 seconds`,
  );
  const firstActionReady = report.launch?.firstActionReadyNanosecondsSinceProcessStart;
  assert.ok(
    Number.isSafeInteger(firstActionReady)
      && firstActionReady >= 0
      && firstActionReady <= MAXIMUM_FULL_INTERACTIVITY_NANOSECONDS,
    `${label} did not become fully interactive within 2 seconds`,
  );
  await readBoundArtifact(
    run.metalSystemTraceArchive,
    `${label}.metalSystemTraceArchive`,
    context,
  );
}

function audioCheckpoint(report, sequence, label) {
  assertCheckpointSequence(sequence, `${label}.sequence`);
  const matches = report.audioCursorCheckpoints.filter(
    (checkpoint) => checkpoint.sequence === sequence,
  );
  assert.equal(matches.length, 1, `${label} does not identify one raw audio checkpoint`);
  return matches[0];
}

function validateBoundAudioCheckpoint(checkpoint, expectedKind, run, label) {
  assertExactKeys(checkpoint, [
    "sequence",
    "nanosecondsSinceProcessStart",
    "timelineID",
    "sampleRate",
    "cursorSample",
    "kind",
  ], label);
  assertCheckpointSequence(checkpoint.sequence, `${label}.sequence`);
  assert.ok(
    Number.isSafeInteger(checkpoint.nanosecondsSinceProcessStart)
      && checkpoint.nanosecondsSinceProcessStart >= 0,
    `${label} has an invalid timestamp`,
  );
  assert.equal(checkpoint.kind, expectedKind, `${label} kind drifted`);
  assert.equal(checkpoint.timelineID, run.timelineID, `${label} timeline identity drifted`);
  assert.equal(checkpoint.sampleRate, run.sampleRate, `${label} sample-rate identity drifted`);
  assert.equal(
    checkpoint.sampleRate,
    REQUIRED_AUDIO_SAMPLE_RATE,
    `${label} is not an authored 48 kHz checkpoint`,
  );
  assert.ok(
    Number.isSafeInteger(checkpoint.cursorSample) && checkpoint.cursorSample >= 0,
    `${label} cursor sample is invalid`,
  );
}

async function validateAudioRestorationRun(run, index, identity, context) {
  const label = `audioRestorationRuns[${index}]`;
  assertExactKeys(run, [
    "runID",
    "repetition",
    "attemptID",
    "timelineID",
    "sampleRate",
    "controlledPause",
    "hardKill",
    "rawReport",
    "metalSystemTraceArchive",
    "audioTraceArchive",
  ], label);
  assert.equal(run.runID, "audio-restoration", `${label} run ID drifted`);
  assert.equal(run.repetition, index + 1, `${label} repetition drifted`);
  assertAttemptID(run.attemptID, `${label}.attemptID`);
  assert.equal(typeof run.timelineID, "string", `${label}.timelineID must be a string`);
  assert.ok(run.timelineID.length > 0, `${label}.timelineID is empty`);
  assert.equal(run.sampleRate, REQUIRED_AUDIO_SAMPLE_RATE, `${label} must use authored 48 kHz audio`);
  assertExactKeys(run.controlledPause, [
    "pauseCheckpointSequence",
    "restorationCheckpointSequence",
  ], `${label}.controlledPause`);
  assertExactKeys(run.hardKill, [
    "lastRenderedCheckpointSequence",
    "restorationCheckpointSequence",
  ], `${label}.hardKill`);

  const checkpointSequences = [
    run.controlledPause.pauseCheckpointSequence,
    run.controlledPause.restorationCheckpointSequence,
    run.hardKill.lastRenderedCheckpointSequence,
    run.hardKill.restorationCheckpointSequence,
  ];
  checkpointSequences.forEach((sequence, checkpointIndex) => {
    assertCheckpointSequence(sequence, `${label}.checkpointSequences[${checkpointIndex}]`);
  });
  assert.equal(
    new Set(checkpointSequences).size,
    checkpointSequences.length,
    `${label} must bind four distinct raw audio checkpoints`,
  );
  assert.deepEqual(
    [...checkpointSequences].sort((left, right) => left - right),
    checkpointSequences,
    `${label} audio checkpoint order drifted`,
  );

  const report = await readRawReport(run.rawReport, `${label}.rawReport`, context);
  validateRawReportIdentity(
    report,
    { runID: run.runID, attemptID: run.attemptID, repetition: run.repetition },
    identity,
    `${label}.rawReport`,
  );
  assert.ok(
    Array.isArray(report.audioCursorCheckpoints),
    `${label}.rawReport audio checkpoints are missing`,
  );

  const controlledPause = audioCheckpoint(
    report,
    run.controlledPause.pauseCheckpointSequence,
    `${label}.controlledPause.pauseCheckpoint`,
  );
  const controlledRestoration = audioCheckpoint(
    report,
    run.controlledPause.restorationCheckpointSequence,
    `${label}.controlledPause.restorationCheckpoint`,
  );
  const hardKillReference = audioCheckpoint(
    report,
    run.hardKill.lastRenderedCheckpointSequence,
    `${label}.hardKill.lastRenderedCheckpoint`,
  );
  const hardKillRestoration = audioCheckpoint(
    report,
    run.hardKill.restorationCheckpointSequence,
    `${label}.hardKill.restorationCheckpoint`,
  );
  validateBoundAudioCheckpoint(
    controlledPause,
    "CONTROLLED_PAUSE",
    run,
    `${label}.controlledPause.pauseCheckpoint`,
  );
  validateBoundAudioCheckpoint(
    controlledRestoration,
    "RESTORATION",
    run,
    `${label}.controlledPause.restorationCheckpoint`,
  );
  validateBoundAudioCheckpoint(
    hardKillReference,
    "SNAPSHOT",
    run,
    `${label}.hardKill.lastRenderedCheckpoint`,
  );
  validateBoundAudioCheckpoint(
    hardKillRestoration,
    "RESTORATION",
    run,
    `${label}.hardKill.restorationCheckpoint`,
  );
  assert.equal(
    controlledRestoration.cursorSample,
    controlledPause.cursorSample,
    `${label} controlled-pause restoration drifted by one or more samples`,
  );
  const hardKillErrorSamples = Math.abs(
    hardKillRestoration.cursorSample - hardKillReference.cursorSample,
  );
  assert.ok(
    hardKillErrorSamples <= MAXIMUM_HARD_KILL_AUDIO_ERROR_SAMPLES,
    `${label} hard-kill restoration exceeds 250 ms at 48 kHz`,
  );

  await readBoundArtifact(
    run.metalSystemTraceArchive,
    `${label}.metalSystemTraceArchive`,
    context,
  );
  await readBoundArtifact(run.audioTraceArchive, `${label}.audioTraceArchive`, context);
}

export async function validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot }) {
  assertExactKeys(evidence, [
    "schemaVersion",
    "kind",
    "status",
    "protocolID",
    "chapterID",
    "appBuild",
    "signedProductionPackage",
    "batteryPairs",
    "coldRestoreRuns",
    "audioRestorationRuns",
  ], "evidence");
  assert.equal(evidence.schemaVersion, 1, "unsupported evidence schema");
  assert.equal(evidence.kind, "FIRST_FARMERS_PHYSICAL_IPHONE_EVIDENCE", "evidence kind drifted");
  assert.equal(evidence.status, "PASS", "NOT_TESTED or incomplete evidence fails the physical gate");
  assert.equal(evidence.protocolID, "port1-physical-device-v1", "evidence protocol drifted");
  assert.equal(evidence.chapterID, "first-farmers", "evidence chapter drifted");

  assertExactKeys(evidence.appBuild, ["hashKind", "sha256"], "appBuild");
  assert.equal(evidence.appBuild.hashKind, "APP_BUNDLE_FILE_TREE_SHA256");
  assertSHA256(evidence.appBuild.sha256, "appBuild.sha256");
  assertExactKeys(
    evidence.signedProductionPackage,
    ["packageID", "hashKind", "manifestSHA256"],
    "signedProductionPackage",
  );
  assert.equal(evidence.signedProductionPackage.packageID, "essential-free-v1");
  assert.equal(evidence.signedProductionPackage.hashKind, "SIGNED_MANIFEST_SHA256");
  assertSHA256(
    evidence.signedProductionPackage.manifestSHA256,
    "signedProductionPackage.manifestSHA256",
  );
  assert.ok(Array.isArray(evidence.batteryPairs), "batteryPairs must be an array");
  assert.equal(evidence.batteryPairs.length, 3, "three paired battery runs are required");
  assert.ok(Array.isArray(evidence.coldRestoreRuns), "coldRestoreRuns must be an array");
  assert.equal(evidence.coldRestoreRuns.length, 6, "six cold-restore interaction cases are required");
  assert.ok(Array.isArray(evidence.audioRestorationRuns), "audioRestorationRuns must be an array");
  assert.equal(
    evidence.audioRestorationRuns.length,
    10,
    "ten paired audio-restoration repetitions are required",
  );

  const resolvedArtifactsRoot = path.resolve(artifactsRoot);
  const rootInfo = await lstat(resolvedArtifactsRoot);
  assert.equal(rootInfo.isDirectory(), true, "artifact root must be a directory");
  const context = {
    artifactsRoot: resolvedArtifactsRoot,
    usedArtifactPaths: new Set(),
  };
  const identity = {
    appBuildSHA256: evidence.appBuild.sha256,
    packageManifestSHA256: evidence.signedProductionPackage.manifestSHA256,
  };

  const referenceDrops = [];
  const chapterDrops = [];
  for (const [index, pair] of evidence.batteryPairs.entries()) {
    const label = `batteryPairs[${index}]`;
    assertExactKeys(pair, ["repetition", "reference", "chapter"], label);
    assert.equal(pair.repetition, index + 1, `${label} repetition drifted`);
    const referenceDrop = await validateReferenceRun(
      pair.reference,
      pair.repetition,
      identity,
      context,
      `${label}.reference`,
    );
    const chapterDrop = await validateChapterRun(
      pair.chapter,
      pair.repetition,
      identity,
      context,
      `${label}.chapter`,
    );
    assert.ok(
      Math.abs(
        pair.reference.startingBatteryPercent - pair.chapter.startingBatteryPercent,
      ) <= 2,
      `${label} starting battery differs by more than two percentage points`,
    );
    referenceDrops.push(referenceDrop);
    chapterDrops.push(chapterDrop);
  }
  assert.ok(
    median(chapterDrops) - median(referenceDrops) <= 3,
    "First Farmers exceeds the three-point battery delta over its static reference",
  );

  for (const [index, run] of evidence.coldRestoreRuns.entries()) {
    await validateColdRestoreRun(run, index, identity, context);
  }
  for (const [index, run] of evidence.audioRestorationRuns.entries()) {
    await validateAudioRestorationRun(run, index, identity, context);
  }
  return evidence;
}

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function main() {
  const evidenceArgument = valueAfter("--evidence");
  assert.ok(evidenceArgument, "usage: validate-first-farmers-physical-evidence.mjs --evidence <receipt.json> [--artifacts-root <directory>]");
  const evidencePath = path.resolve(evidenceArgument);
  const artifactsRoot = path.resolve(valueAfter("--artifacts-root") ?? path.dirname(evidencePath));
  const evidence = JSON.parse(await readFile(evidencePath, "utf8"));
  await validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot });
  process.stdout.write("First Farmers physical iPhone evidence passes all measured gates.\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
