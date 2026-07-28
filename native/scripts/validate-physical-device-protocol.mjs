#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { validateFirstFarmersPhysicalEvidence } from "./validate-first-farmers-physical-evidence.mjs";

const nativeRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const execFileAsync = promisify(execFile);

export function validatePhysicalDeviceProtocol(protocol) {
  assert.equal(protocol.schemaVersion, 1, "unsupported physical-device protocol schema");
  assert.equal(protocol.protocolID, "port1-physical-device-v1", "physical-device protocol ID drifted");
  assert.equal(
    protocol.status,
    "LOCKED_PENDING_PHYSICAL_EXECUTION",
    "protocol cannot claim a physical result without a separate signed report",
  );
  assert.equal(protocol.device.minimumModel, "iPhone 15 Pro", "floor device drifted");
  assert.equal(protocol.device.minimumOSMajor, 26, "minimum iOS drifted");
  assert.equal(protocol.device.requiredOrientation, "portrait", "orientation drifted");
  assert.equal(protocol.device.physicalDeviceCount, 1, "single-device constraint drifted");

  assert.equal(protocol.build.configuration, "Release", "physical evidence requires a Release build");
  assert.equal(protocol.build.codeSigningRequired, true, "physical build must be signed");
  assert.equal(protocol.build.debuggerAttached, false, "debugger would invalidate performance evidence");
  assert.equal(protocol.build.airplaneModeAfterPackageInstall, true, "offline run is mandatory");

  assert.deepEqual(protocol.environment.ambientTemperatureCelsius, { minimum: 20, maximum: 24 });
  assert.equal(protocol.environment.acclimationMinutes, 20);
  assert.equal(protocol.environment.externalPowerConnected, false);
  assert.equal(protocol.environment.lowPowerMode, false);
  assert.equal(protocol.environment.screenBrightnessPercent, 50);
  assert.equal(protocol.environment.automaticBrightness, false);
  assert.equal(protocol.environment.outputVolumePercent, 40);
  assert.ok(protocol.environment.minimumFreeStorageGiB >= 10);

  assert.equal(
    protocol.instrumentation.localFrameCompletionProxy,
    "os-signpost-command-buffer-scheduled-and-completed-callbacks-plus-MTLCommandBuffer-GPUStartTime-and-GPUEndTime",
  );
  assert.equal(protocol.instrumentation.displayedFrameCadence, "retained-Metal-System-Trace");
  assert.equal(
    protocol.instrumentation.localInteractionCompletionProxy,
    "touch-or-accessibility-action-to-command-buffer-completed-callback",
  );
  assert.equal(
    protocol.instrumentation.inputToVisibleLatency,
    "retained-Metal-System-Trace-correlated-with-input-signposts",
  );
  assert.equal(
    protocol.instrumentation.localRestoreCompletionProxy,
    "process-start-to-restored-frame-command-buffer-completed-callback",
  );
  assert.equal(
    protocol.instrumentation.restoreToVisibleLatency,
    "retained-Metal-System-Trace-correlated-with-process-and-restore-signposts",
  );
  assert.equal(protocol.instrumentation.rawTraceRetentionRequired, true);

  const runs = new Map(protocol.runOrder.map((run) => [run.runID, run]));
  assert.equal(runs.size, protocol.runOrder.length, "duplicate physical run ID");
  assert.equal(runs.get("cold-restore")?.repetitions, 6);
  assert.deepEqual(runs.get("cold-restore")?.requiredInteractionIDs, [
    "interaction-first-farmers-a-household-crosses",
    "interaction-first-farmers-the-harvest-had-to-last",
    "interaction-first-farmers-at-the-iron-gates",
    "interaction-first-farmers-the-house-outlives",
    "interaction-first-farmers-more-mouths-more-land",
    "interaction-first-farmers-a-continent-remade",
  ]);
  assert.equal(runs.get("interaction-latency")?.repetitions, 20);
  assert.equal(runs.get("static-reference")?.repetitions, 3);
  assert.equal(runs.get("static-reference")?.durationMinutes, 30);
  assert.equal(runs.get("first-farmers-static-reference")?.repetitions, 3);
  assert.equal(runs.get("first-farmers-static-reference")?.durationMinutes, 30);
  assert.equal(runs.get("harvest-sustained")?.repetitions, 3);
  assert.equal(runs.get("harvest-sustained")?.durationMinutes, 30);
  assert.equal(runs.get("first-farmers-sustained")?.repetitions, 3);
  assert.equal(runs.get("first-farmers-sustained")?.durationMinutes, 30);
  assert.equal(runs.get("audio-restoration")?.repetitions, 10);
  assert.ok(runs.has("storage-pressure"));

  assert.equal(protocol.budgets.targetFramesPerSecond, 60);
  assert.equal(protocol.budgets.p99DisplayedFrameTimeMillisecondsMaximum, 25);
  assert.equal(protocol.budgets.inputToVisibleResponseMillisecondsMaximum, 50);
  assert.equal(protocol.budgets.sustainedPhysicalMemoryMiBMaximum, 500);
  assert.deepEqual(protocol.budgets.allowedThermalStates, ["nominal", "fair"]);
  assert.equal(protocol.budgets.restoreToVisibleFrameMillisecondsMaximum, 1500);
  assert.equal(protocol.budgets.fullInteractivityMillisecondsMaximum, 2000);
  assert.equal(protocol.budgets.controlledPauseAudioSampleErrorMaximum, 0);
  assert.equal(protocol.budgets.hardKillAudioMillisecondsErrorMaximum, 250);
  assert.equal(protocol.budgets.absoluteBatteryDropPercentagePointsMaximum, 8);
  assert.equal(
    protocol.budgets.incrementalBatteryDropOverStaticReferencePercentagePointsMaximum,
    3,
  );

  assert.equal(protocol.storagePressure.actualWholeDeviceFillProhibited, true);
  assert.equal(protocol.storagePressure.mustPreserveLastVerifiedGeneration, true);
  assert.equal(protocol.storagePressure.mustPreserveProgress, true);
  assert.deepEqual(protocol.storagePressure.requiredCases, [
    "capacity-one-byte-below-declared-requirement",
    "staging-write-failure",
    "activation-index-write-failure",
    "process-death-during-copy",
    "successful-retry-after-each-failure",
  ]);

  assert.equal(protocol.comparison.pairedBatteryRunsRequired, 3);
  assert.equal(protocol.comparison.medianDeterminesBatteryResult, true);
  assert.equal(protocol.comparison.appAndReferenceRunMustAlternate, true);
  assert.deepEqual(protocol.comparison.pairedRunSets, [
    {
      referenceRunID: "static-reference",
      appRunID: "harvest-sustained",
    },
    {
      referenceRunID: "first-farmers-static-reference",
      appRunID: "first-farmers-sustained",
    },
  ]);
  assert.equal(protocol.resultContract.notTestedIsFailure, true);
  assert.equal(protocol.resultContract.simulatorCannotSatisfyPhysicalGate, true);
  assert.equal(protocol.resultContract.localReportCannotSatisfyDisplayGates, true);
  assert.equal(
    protocol.resultContract.retainedMetalSystemTraceRequiredForDisplayGates,
    true,
  );
  assert.equal(protocol.resultContract.editorApprovalRequiredAfterTechnicalPass, true);
  assert.deepEqual(protocol.instrumentationReportContract, {
    schemaPath: "quality/schemas/physical-performance-report.schema.json",
    captureRequestPath:
      "Application Support/quality-gate-v1/performance-capture-request.json",
    reportDirectory: "Application Support/quality-gate-v1/performance-reports",
    appHashKind: "APP_BUNDLE_FILE_TREE_SHA256",
    packageHashKind: "SIGNED_MANIFEST_SHA256",
    simulatorClassification: "NON_DEVICE",
    rawDeviceClassification: "DEVICE_RAW_MEASUREMENTS_ONLY",
    localTimingScope: "COMMAND_BUFFER_AND_GPU_COMPLETION_PROXY_ONLY",
    actualDisplayGateSource: "RETAINED_METAL_SYSTEM_TRACE",
    networkingProhibited: true,
  });
  assert.deepEqual(protocol.firstFarmersEvidenceContract, {
    schemaPath: "quality/schemas/first-farmers-physical-evidence.schema.json",
    validatorPath: "scripts/validate-first-farmers-physical-evidence.mjs",
    evidencePath: "quality/physical-device-evidence/first-farmers.receipt.json",
    artifactsRoot: "quality/physical-device-evidence/artifacts",
    requiredStatus: "PASS",
    chapterID: "first-farmers",
    productionPackageID: "essential-free-v1",
    requiredBeatCount: 17,
    requiredInteractionCount: 6,
    requiredBatteryPairs: 3,
    requiredColdRestoreCases: 6,
    minimumSustainedDurationSeconds: 1800,
    traceArtifactHashKind: "RETAINED_TRACE_ARCHIVE_FILE_SHA256",
    missingEvidenceFails: true,
  });
  return protocol;
}

function iPhoneHardwareGeneration(productType) {
  const match = /^iPhone(\d+),(\d+)$/u.exec(productType ?? "");
  return match ? Number(match[1]) : null;
}

function iOSMajorVersion(version) {
  const match = /^(\d+)(?:\.|$)/u.exec(version ?? "");
  return match ? Number(match[1]) : null;
}

export function validateConnectedPhysicalIPhoneInventory(inventory) {
  const devices = inventory?.result?.devices;
  assert.ok(
    Array.isArray(devices),
    "PHYSICAL_DEVICE_PREFLIGHT=FAIL CoreDevice returned no device inventory",
  );
  const registeredIPhones = devices.filter((device) => (
    device.hardwareProperties?.deviceType === "iPhone"
      && device.hardwareProperties?.reality === "physical"
      && device.hardwareProperties?.platform === "iOS"
  ));
  const readyIPhones = registeredIPhones.filter((device) => (
    device.connectionProperties?.tunnelState !== "unavailable"
      && device.deviceProperties?.ddiServicesAvailable === true
      && device.deviceProperties?.developerModeStatus === "enabled"
      && (iPhoneHardwareGeneration(device.hardwareProperties?.productType) ?? 0) >= 16
      && (iOSMajorVersion(device.deviceProperties?.osVersionNumber) ?? 0) >= 26
  ));
  if (readyIPhones.length === 0) {
    const registeredState = registeredIPhones.length === 0
      ? "no physical iPhone is registered"
      : registeredIPhones.map((device) => (
        `${device.deviceProperties?.name ?? "unnamed iPhone"}: `
          + `connection=${device.connectionProperties?.tunnelState ?? "unknown"}, `
          + `developerMode=${device.deviceProperties?.developerModeStatus ?? "unknown"}, `
          + `ddi=${device.deviceProperties?.ddiServicesAvailable === true ? "available" : "unavailable"}`
      )).join("; ");
    assert.fail(
      "PHYSICAL_DEVICE_PREFLIGHT=FAIL no connected, developer-ready physical "
        + `iPhone 15 Pro-class or newer is available (${registeredState}). `
        + "An iOS Simulator cannot satisfy this gate.",
    );
  }
  assert.equal(
    readyIPhones.length,
    1,
    "PHYSICAL_DEVICE_PREFLIGHT=FAIL exactly one eligible physical iPhone must be connected",
  );
  const device = readyIPhones[0];
  return {
    identifier: device.identifier,
    name: device.deviceProperties.name,
    productType: device.hardwareProperties.productType,
    marketingName: device.hardwareProperties.marketingName,
    osVersion: device.deviceProperties.osVersionNumber,
  };
}

export async function readConnectedPhysicalIPhone() {
  let stdout;
  try {
    ({ stdout } = await execFileAsync(
      "xcrun",
      ["devicectl", "list", "devices", "--json-output", "/dev/stdout"],
      { encoding: "utf8", maxBuffer: 4 * 1_024 * 1_024 },
    ));
  } catch (error) {
    throw new Error(
      "PHYSICAL_DEVICE_PREFLIGHT=FAIL CoreDevice inventory could not be read",
      { cause: error },
    );
  }
  const jsonStart = stdout.indexOf("{");
  assert.ok(
    jsonStart >= 0,
    "PHYSICAL_DEVICE_PREFLIGHT=FAIL CoreDevice returned no JSON inventory",
  );
  let inventory;
  try {
    inventory = JSON.parse(stdout.slice(jsonStart));
  } catch (error) {
    throw new Error(
      "PHYSICAL_DEVICE_PREFLIGHT=FAIL CoreDevice returned malformed JSON inventory",
      { cause: error },
    );
  }
  return validateConnectedPhysicalIPhoneInventory(inventory);
}

export async function validateRequiredPhysicalEvidence(
  protocol,
  { nativeRootPath = nativeRoot } = {},
) {
  const contract = protocol.firstFarmersEvidenceContract;
  const evidencePath = path.resolve(nativeRootPath, contract.evidencePath);
  const artifactsRoot = path.resolve(nativeRootPath, contract.artifactsRoot);
  let evidenceBytes;
  try {
    evidenceBytes = await readFile(evidencePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      throw new Error(
        "PHYSICAL_DEVICE_GATE=FAIL MISSING_DEVICE_EVIDENCE: "
          + `${contract.evidencePath}. A simulator result or a locked protocol `
          + "cannot satisfy the physical iPhone gate.",
      );
    }
    throw error;
  }
  let evidence;
  try {
    evidence = JSON.parse(evidenceBytes);
  } catch (error) {
    throw new Error(
      `PHYSICAL_DEVICE_GATE=FAIL invalid evidence JSON: ${contract.evidencePath}`,
      { cause: error },
    );
  }
  await validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot });
  return { evidencePath, artifactsRoot };
}

async function main() {
  const argumentsSet = new Set(process.argv.slice(2));
  const supportedArguments = new Set([
    "--preflight-device",
    "--require-evidence",
    "--require-pass",
  ]);
  for (const argument of argumentsSet) {
    assert.ok(supportedArguments.has(argument), `unsupported argument: ${argument}`);
  }
  const protocolPath = path.join(nativeRoot, "quality", "physical-device-protocol.json");
  const protocol = JSON.parse(await readFile(protocolPath, "utf8"));
  validatePhysicalDeviceProtocol(protocol);
  const reportSchema = JSON.parse(
    await readFile(path.join(nativeRoot, protocol.instrumentationReportContract.schemaPath), "utf8"),
  );
  assert.equal(reportSchema.additionalProperties, false);
  assert.equal(reportSchema.properties.gateClassification.enum.includes("PASS"), false);
  assert.equal(
    reportSchema.properties.localTimingScope.const,
    "COMMAND_BUFFER_AND_GPU_COMPLETION_PROXY_ONLY",
  );
  assert.equal(reportSchema.$defs.audio.properties.sampleRate.const, 48_000);
  assert.equal(reportSchema.$defs.sha256.pattern, "^[0-9a-f]{64}$");
  const chapterEvidenceSchema = JSON.parse(
    await readFile(
      path.join(nativeRoot, protocol.firstFarmersEvidenceContract.schemaPath),
      "utf8",
    ),
  );
  assert.equal(chapterEvidenceSchema.additionalProperties, false);
  assert.equal(chapterEvidenceSchema.properties.status.const, "PASS");
  assert.equal(chapterEvidenceSchema.properties.batteryPairs.minItems, 3);
  assert.equal(chapterEvidenceSchema.properties.coldRestoreRuns.minItems, 6);
  const requiresDevice = argumentsSet.has("--preflight-device")
    || argumentsSet.has("--require-pass");
  const requiresEvidence = argumentsSet.has("--require-evidence")
    || argumentsSet.has("--require-pass");
  let device;
  if (requiresDevice) {
    device = await readConnectedPhysicalIPhone();
    process.stdout.write(
      `PHYSICAL_DEVICE_PREFLIGHT=PASS model=${device.marketingName ?? device.productType} os=${device.osVersion}\n`,
    );
  }
  if (requiresEvidence) {
    await validateRequiredPhysicalEvidence(protocol);
    process.stdout.write(
      `PHYSICAL_DEVICE_EVIDENCE=PASS path=${protocol.firstFarmersEvidenceContract.evidencePath}\n`,
    );
  }
  if (argumentsSet.has("--require-pass")) {
    process.stdout.write("PHYSICAL_DEVICE_GATE=PASS\n");
    return;
  }
  process.stdout.write(
    `Physical-device protocol locked: ${protocol.runOrder.length} run classes; physical execution remains pending.\n`,
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
  });
}
