#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const nativeRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

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
  assert.equal(runs.get("cold-restore")?.repetitions, 5);
  assert.equal(runs.get("interaction-latency")?.repetitions, 20);
  assert.equal(runs.get("static-reference")?.repetitions, 3);
  assert.equal(runs.get("static-reference")?.durationMinutes, 30);
  assert.equal(runs.get("harvest-sustained")?.repetitions, 3);
  assert.equal(runs.get("harvest-sustained")?.durationMinutes, 30);
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
  return protocol;
}

async function main() {
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
