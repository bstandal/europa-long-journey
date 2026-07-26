#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { validatePhysicalDeviceProtocol } from "./validate-physical-device-protocol.mjs";

const nativeRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const protocol = JSON.parse(
  await readFile(path.join(nativeRoot, "quality", "physical-device-protocol.json"), "utf8"),
);
const reportSchema = JSON.parse(
  await readFile(
    path.join(nativeRoot, protocol.instrumentationReportContract.schemaPath),
    "utf8",
  ),
);

test("locked physical-device protocol passes", () => {
  assert.doesNotThrow(() => validatePhysicalDeviceProtocol(structuredClone(protocol)));
});

test("simulator evidence cannot replace the physical floor", () => {
  const drifted = structuredClone(protocol);
  drifted.resultContract.simulatorCannotSatisfyPhysicalGate = false;
  assert.throws(() => validatePhysicalDeviceProtocol(drifted));
});

test("performance budgets cannot loosen silently", () => {
  const drifted = structuredClone(protocol);
  drifted.budgets.p99DisplayedFrameTimeMillisecondsMaximum = 30;
  assert.throws(() => validatePhysicalDeviceProtocol(drifted));
});

test("local completion proxies cannot replace retained display traces", () => {
  const drifted = structuredClone(protocol);
  drifted.resultContract.localReportCannotSatisfyDisplayGates = false;
  assert.throws(() => validatePhysicalDeviceProtocol(drifted));

  const traceDrift = structuredClone(protocol);
  traceDrift.instrumentation.displayedFrameCadence =
    "command-buffer-completed-callback";
  assert.throws(() => validatePhysicalDeviceProtocol(traceDrift));
});

test("storage test cannot consume unrelated device capacity", () => {
  const drifted = structuredClone(protocol);
  drifted.storagePressure.actualWholeDeviceFillProhibited = false;
  assert.throws(() => validatePhysicalDeviceProtocol(drifted));
});

test("simulator report classification and local-only instrumentation cannot drift", () => {
  const drifted = structuredClone(protocol);
  drifted.instrumentationReportContract.simulatorClassification =
    "DEVICE_RAW_MEASUREMENTS_ONLY";
  assert.throws(() => validatePhysicalDeviceProtocol(drifted));

  const networked = structuredClone(protocol);
  networked.instrumentationReportContract.networkingProhibited = false;
  assert.throws(() => validatePhysicalDeviceProtocol(networked));
});

test("backstage report schema is closed and cannot encode a pass claim", () => {
  assert.equal(reportSchema.additionalProperties, false);
  assert.equal(reportSchema.$defs.frameCompletionProxy.additionalProperties, false);
  assert.equal(reportSchema.$defs.audio.properties.sampleRate.const, 48_000);
  assert.deepEqual(reportSchema.properties.gateClassification.enum, [
    "NON_DEVICE",
    "DEVICE_RAW_MEASUREMENTS_ONLY",
  ]);
  assert.equal(
    reportSchema.properties.localTimingScope.const,
    "COMMAND_BUFFER_AND_GPU_COMPLETION_PROXY_ONLY",
  );
  assert.equal(
    JSON.stringify(reportSchema).includes("firstVisibleFrameNanosecondsSinceProcessStart"),
    false,
  );
  assert.equal(
    JSON.stringify(reportSchema).includes("metalPresentedTimeNanosecondsSinceBoot"),
    false,
  );
});

test("performance instrumentation has no analytics or network dependency", async () => {
  const sourceRoot = path.join(nativeRoot, "ios", "Sources", "QualityInstrumentation");
  const sourceNames = (await readdir(sourceRoot)).filter((name) => name.endsWith(".swift"));
  const source = (
    await Promise.all(sourceNames.map((name) => readFile(path.join(sourceRoot, name), "utf8")))
  ).join("\n");
  for (const forbidden of [
    "URLSession",
    "import Network",
    "NWConnection",
    "CloudKit",
    "MetricKit",
    "analytics",
    "telemetry",
  ]) {
    assert.equal(source.includes(forbidden), false, `forbidden instrumentation edge: ${forbidden}`);
  }
});
