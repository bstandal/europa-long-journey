#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  firstFarmersBeatCoverage,
  firstFarmersInteractionCoverage,
  validateFirstFarmersPhysicalEvidence,
} from "./validate-first-farmers-physical-evidence.mjs";

const appBuildSHA256 = "a".repeat(64);
const packageManifestSHA256 = "b".repeat(64);

function hash(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function writeArtifact(root, relativePath, value) {
  const absolutePath = path.join(root, relativePath);
  await mkdir(path.dirname(absolutePath), { recursive: true });
  const bytes = Buffer.isBuffer(value)
    ? value
    : Buffer.from(typeof value === "string" ? value : `${JSON.stringify(value)}\n`);
  await writeFile(absolutePath, bytes);
  return { path: relativePath, sha256: hash(bytes) };
}

function frame(frameID, sceneID) {
  const base = frameID * 10_000_000;
  return {
    sequence: frameID,
    frameID,
    sceneID,
    commandBufferCommitRequestedNanosecondsSinceProcessStart: base,
    commandBufferScheduledCallbackNanosecondsSinceProcessStart: base + 1_000_000,
    commandBufferCompletedCallbackNanosecondsSinceProcessStart: base + 2_000_000,
    commitRequestToScheduledCallbackNanoseconds: 1_000_000,
    commitRequestToCompletedCallbackNanoseconds: 2_000_000,
    previousCommandBufferCompletionCallbackIntervalNanoseconds:
      frameID === 1 ? null : 10_000_000,
    gpuStartHostTimeNanoseconds: base + 1_100_000,
    gpuEndHostTimeNanoseconds: base + 1_900_000,
    gpuExecutionNanoseconds: 800_000,
  };
}

function action(actionID, completedFrameID) {
  return {
    sequence: 100 + actionID,
    actionID,
    source: "TOUCH",
    actionName: `physical-action-${actionID}`,
    beganNanosecondsSinceProcessStart: actionID * 10_000_000,
    firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart:
      actionID * 10_000_000 + 20_000_000,
    actionToCommandBufferCompletedCallbackNanoseconds: 20_000_000,
    completedFrameID,
  };
}

function audioCheckpoint(sequence, timelineID, kind, cursorSample, sampleRate = 48_000) {
  return {
    sequence,
    nanosecondsSinceProcessStart: (sequence - 202) * 100_000_000,
    timelineID,
    sampleRate,
    cursorSample,
    kind,
  };
}

function rawReport({
  runID,
  attemptID,
  repetition,
  scenes,
  actionSceneIDs = [],
  restore = false,
  captureDurationSeconds = 3,
  audioCursorCheckpoints = [],
}) {
  const frames = scenes.map((sceneID, index) => frame(index + 1, sceneID));
  const interactions = actionSceneIDs.map((sceneID, index) => {
    const completedFrame = frames.find((measurement) => measurement.sceneID === sceneID);
    assert.ok(completedFrame);
    return action(index + 1, completedFrame.frameID);
  });
  return {
    schemaVersion: 1,
    protocolID: "port1-physical-device-v1",
    runID,
    attemptID,
    repetition,
    gateClassification: "DEVICE_RAW_MEASUREMENTS_ONLY",
    localTimingScope: "COMMAND_BUFFER_AND_GPU_COMPLETION_PROXY_ONLY",
    platform: {
      captureClass: "PHYSICAL_DEVICE",
      hardwareModel: "iPhone16,1",
      operatingSystem: "iOS 26.0",
      buildConfiguration: "RELEASE",
    },
    appBuildHashKind: "APP_BUNDLE_FILE_TREE_SHA256",
    appBuildSHA256,
    packages: [
      {
        packageID: "essential-free-v1",
        manifestSHA256: packageManifestSHA256,
      },
    ],
    processStartMonotonicNanosecondsSinceBoot: 1_000_000_000,
    captureEndedNanosecondsSinceProcessStart:
      captureDurationSeconds * 1_000_000_000,
    launch: {
      restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart:
        restore ? 1_200_000_000 : null,
      firstActionReadyNanosecondsSinceProcessStart: restore ? 1_800_000_000 : null,
      firstActionReceivedNanosecondsSinceProcessStart: restore ? 1_900_000_000 : null,
    },
    frameCommandBufferCompletionProxies: frames,
    interactionCommandBufferCompletionProxies: interactions,
    physicalFootprint: [
      {
        sequence: 200,
        nanosecondsSinceProcessStart: 0,
        physicalFootprintBytes: 180 * 1_024 * 1_024,
        trigger: "CAPTURE_START",
      },
      {
        sequence: 201,
        nanosecondsSinceProcessStart: 900_000_000_000,
        physicalFootprintBytes: 220 * 1_024 * 1_024,
        trigger: "EXPLICIT_CHECKPOINT",
      },
    ],
    thermalTransitions: [
      {
        sequence: 202,
        nanosecondsSinceProcessStart: 0,
        from: null,
        to: "NOMINAL",
      },
    ],
    audioCursorCheckpoints,
    instrumentationFailures: [],
    rawTraceRetentionRequired: true,
  };
}

async function createRunArtifacts(root, prefix, report) {
  return {
    rawReport: await writeArtifact(root, `reports/${prefix}.json`, report),
    metalSystemTraceArchive: await writeArtifact(
      root,
      `traces/${prefix}-metal.trace.zip`,
      `metal-${prefix}`,
    ),
    energyTraceArchive: await writeArtifact(
      root,
      `traces/${prefix}-energy.trace.zip`,
      `energy-${prefix}`,
    ),
  };
}

async function createAudioRestorationArtifacts(root, prefix, report) {
  return {
    rawReport: await writeArtifact(root, `reports/${prefix}.json`, report),
    metalSystemTraceArchive: await writeArtifact(
      root,
      `traces/${prefix}-metal.trace.zip`,
      `metal-${prefix}`,
    ),
    audioTraceArchive: await writeArtifact(
      root,
      `traces/${prefix}-audio.trace.zip`,
      `audio-${prefix}`,
    ),
  };
}

async function buildPassingFixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), "first-farmers-physical-evidence-"));
  const batteryPairs = [];
  const sceneIDs = firstFarmersBeatCoverage.map((beat) => beat.sceneID);
  const interactionSceneIDs = firstFarmersInteractionCoverage.map(
    (interaction) => interaction.sceneID,
  );
  for (let repetition = 1; repetition <= 3; repetition += 1) {
    const referenceAttempt = `first-farmers-reference-r0${repetition}`;
    const chapterAttempt = `first-farmers-sustained-r0${repetition}`;
    const referenceArtifacts = await createRunArtifacts(
      root,
      referenceAttempt,
      rawReport({
        runID: "first-farmers-static-reference",
        attemptID: referenceAttempt,
        repetition,
        scenes: ["first-farmers-static-reference-frame"],
        captureDurationSeconds: 1_800,
      }),
    );
    const chapterArtifacts = await createRunArtifacts(
      root,
      chapterAttempt,
      rawReport({
        runID: "first-farmers-sustained",
        attemptID: chapterAttempt,
        repetition,
        scenes: sceneIDs,
        actionSceneIDs: interactionSceneIDs,
        captureDurationSeconds: 1_800,
      }),
    );
    batteryPairs.push({
      repetition,
      reference: {
        runID: "first-farmers-static-reference",
        attemptID: referenceAttempt,
        rawReport: referenceArtifacts.rawReport,
        durationSeconds: 1_800,
        startingBatteryPercent: 90,
        endingBatteryPercent: 88,
        metalSystemTraceArchive: referenceArtifacts.metalSystemTraceArchive,
        energyTraceArchive: referenceArtifacts.energyTraceArchive,
      },
      chapter: {
        runID: "first-farmers-sustained",
        attemptID: chapterAttempt,
        rawReport: chapterArtifacts.rawReport,
        durationSeconds: 1_800,
        startingBatteryPercent: 90,
        endingBatteryPercent: 85,
        displayedFrameP99Milliseconds: 20,
        inputToVisibleP99Milliseconds: 40,
        metalSystemTraceArchive: chapterArtifacts.metalSystemTraceArchive,
        energyTraceArchive: chapterArtifacts.energyTraceArchive,
      },
    });
  }

  const coldRestoreRuns = [];
  for (const [index, interaction] of firstFarmersInteractionCoverage.entries()) {
    const repetition = index + 1;
    const attemptID = `first-farmers-cold-r0${repetition}`;
    const artifacts = await createRunArtifacts(
      root,
      attemptID,
      rawReport({
        runID: "cold-restore",
        attemptID,
        repetition,
        scenes: [interaction.sceneID],
        actionSceneIDs: [interaction.sceneID],
        restore: true,
      }),
    );
    coldRestoreRuns.push({
      runID: "cold-restore",
      repetition,
      attemptID,
      interactionID: interaction.interactionID,
      rawReport: artifacts.rawReport,
      metalSystemTraceArchive: artifacts.metalSystemTraceArchive,
    });
    await rm(path.join(root, artifacts.energyTraceArchive.path));
  }

  const audioRestorationRuns = [];
  for (let repetition = 1; repetition <= 10; repetition += 1) {
    const attemptID = `first-farmers-audio-r${String(repetition).padStart(2, "0")}`;
    const timelineID = "first-farmers-narration-v1";
    const controlledPauseSample = repetition * 48_000;
    const hardKillRenderedSample = 960_000 + repetition * 48_000;
    const artifacts = await createAudioRestorationArtifacts(
      root,
      attemptID,
      rawReport({
        runID: "audio-restoration",
        attemptID,
        repetition,
        scenes: ["scene-first-farmers-aegean-crossing"],
        audioCursorCheckpoints: [
          audioCheckpoint(203, timelineID, "CONTROLLED_PAUSE", controlledPauseSample),
          audioCheckpoint(204, timelineID, "RESTORATION", controlledPauseSample),
          audioCheckpoint(205, timelineID, "SNAPSHOT", hardKillRenderedSample),
          audioCheckpoint(206, timelineID, "RESTORATION", hardKillRenderedSample - 12_000),
        ],
      }),
    );
    audioRestorationRuns.push({
      runID: "audio-restoration",
      repetition,
      attemptID,
      timelineID,
      sampleRate: 48_000,
      controlledPause: {
        pauseCheckpointSequence: 203,
        restorationCheckpointSequence: 204,
      },
      hardKill: {
        lastRenderedCheckpointSequence: 205,
        restorationCheckpointSequence: 206,
      },
      rawReport: artifacts.rawReport,
      metalSystemTraceArchive: artifacts.metalSystemTraceArchive,
      audioTraceArchive: artifacts.audioTraceArchive,
    });
  }

  return {
    root,
    evidence: {
      schemaVersion: 1,
      kind: "FIRST_FARMERS_PHYSICAL_IPHONE_EVIDENCE",
      status: "PASS",
      protocolID: "port1-physical-device-v1",
      chapterID: "first-farmers",
      appBuild: {
        hashKind: "APP_BUNDLE_FILE_TREE_SHA256",
        sha256: appBuildSHA256,
      },
      signedProductionPackage: {
        packageID: "essential-free-v1",
        hashKind: "SIGNED_MANIFEST_SHA256",
        manifestSHA256: packageManifestSHA256,
      },
      batteryPairs,
      coldRestoreRuns,
      audioRestorationRuns,
    },
  };
}

async function mutateRawReport(root, artifact, mutation) {
  const absolutePath = path.join(root, artifact.path);
  const report = JSON.parse(await readFile(absolutePath, "utf8"));
  mutation(report);
  const bytes = Buffer.from(`${JSON.stringify(report)}\n`);
  await writeFile(absolutePath, bytes);
  artifact.sha256 = hash(bytes);
}

async function withFixture(body) {
  const fixture = await buildPassingFixture();
  try {
    await body(fixture);
  } finally {
    await rm(fixture.root, { recursive: true, force: true });
  }
}

test("complete measured First Farmers evidence passes", async () => {
  await withFixture(async ({ evidence, root }) => {
    await assert.doesNotReject(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
    );
  });
});

test("NOT_TESTED cannot satisfy the physical gate", async () => {
  await withFixture(async ({ evidence, root }) => {
    evidence.status = "NOT_TESTED";
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /NOT_TESTED or incomplete evidence fails/u,
    );
  });
});

test("all 17 beats and six measured interaction scenes are required", async () => {
  await withFixture(async ({ evidence, root }) => {
    const chapter = evidence.batteryPairs[0].chapter;
    await mutateRawReport(root, chapter.rawReport, (report) => {
      report.frameCommandBufferCompletionProxies.splice(7, 1);
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /has no ordered frame evidence/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const chapter = evidence.batteryPairs[0].chapter;
    await mutateRawReport(root, chapter.rawReport, (report) => {
      report.interactionCommandBufferCompletionProxies.pop();
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /has no completed action measurement/u,
    );
  });
});

test("short runs, battery overruns and missing trace bytes fail", async () => {
  await withFixture(async ({ evidence, root }) => {
    evidence.batteryPairs[0].chapter.durationSeconds = 1_799;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /did not run for 30 minutes/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const chapter = evidence.batteryPairs[0].chapter;
    await mutateRawReport(root, chapter.rawReport, (report) => {
      report.captureEndedNanosecondsSinceProcessStart = 1_799_000_000_000;
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /raw report does not prove its declared duration/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    evidence.batteryPairs[0].chapter.endingBatteryPercent = 80;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /exceeds the absolute battery budget/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    for (const pair of evidence.batteryPairs) {
      pair.reference.endingBatteryPercent = 89;
    }
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /three-point battery delta/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    evidence.batteryPairs[0].chapter.startingBatteryPercent = 87;
    evidence.batteryPairs[0].chapter.endingBatteryPercent = 82;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /starting battery differs by more than two/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    evidence.batteryPairs[0].chapter.metalSystemTraceArchive.sha256 = "c".repeat(64);
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /bytes do not match their SHA-256/u,
    );
  });
});

test("wrong app or signed-package identity cannot be substituted", async () => {
  await withFixture(async ({ evidence, root }) => {
    const reportArtifact = evidence.batteryPairs[0].chapter.rawReport;
    await mutateRawReport(root, reportArtifact, (report) => {
      report.appBuildSHA256 = "c".repeat(64);
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /app build does not match/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const reportArtifact = evidence.batteryPairs[0].chapter.rawReport;
    await mutateRawReport(root, reportArtifact, (report) => {
      report.packages[0].packageID = "first-farmers-development-v1";
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /exact signed production package/u,
    );
  });
});

test("serious thermal state, excess memory or failed display p99 fails", async () => {
  await withFixture(async ({ evidence, root }) => {
    const reportArtifact = evidence.batteryPairs[0].chapter.rawReport;
    await mutateRawReport(root, reportArtifact, (report) => {
      report.thermalTransitions[0].to = "SERIOUS";
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /prohibited thermal state/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const reportArtifact = evidence.batteryPairs[0].chapter.rawReport;
    await mutateRawReport(root, reportArtifact, (report) => {
      report.physicalFootprint[1].physicalFootprintBytes = 501 * 1_024 * 1_024;
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /exceeds the 500 MiB/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    evidence.batteryPairs[0].chapter.displayedFrameP99Milliseconds = 25.1;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /exceeds the displayed-frame p99/u,
    );
  });
});

test("cold restoration requires one measured run for every principal interaction", async () => {
  await withFixture(async ({ evidence, root }) => {
    evidence.coldRestoreRuns.pop();
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /six cold-restore interaction cases/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    evidence.coldRestoreRuns[5].interactionID =
      firstFarmersInteractionCoverage[0].interactionID;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /interaction coverage drifted/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const run = evidence.coldRestoreRuns[0];
    await mutateRawReport(root, run.rawReport, (report) => {
      report.launch.restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart =
        1_500_000_001;
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /within 1.5 seconds/u,
    );
  });
});

test("audio restoration requires ten exact paired repetitions", async () => {
  await withFixture(async ({ evidence, root }) => {
    evidence.audioRestorationRuns.pop();
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /ten paired audio-restoration repetitions/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    evidence.audioRestorationRuns[9].repetition = 9;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /audioRestorationRuns\[9\] repetition drifted/u,
    );
  });
});

test("controlled-pause restoration rejects one sample of drift", async () => {
  await withFixture(async ({ evidence, root }) => {
    const run = evidence.audioRestorationRuns[0];
    await mutateRawReport(root, run.rawReport, (report) => {
      const restoration = report.audioCursorCheckpoints.find(
        (checkpoint) => checkpoint.sequence
          === run.controlledPause.restorationCheckpointSequence,
      );
      restoration.cursorSample += 1;
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /controlled-pause restoration drifted/u,
    );
  });
});

test("hard-kill restoration rejects more than 12000 samples at 48 kHz", async () => {
  await withFixture(async ({ evidence, root }) => {
    const run = evidence.audioRestorationRuns[0];
    await mutateRawReport(root, run.rawReport, (report) => {
      const reference = report.audioCursorCheckpoints.find(
        (checkpoint) => checkpoint.sequence
          === run.hardKill.lastRenderedCheckpointSequence,
      );
      const restoration = report.audioCursorCheckpoints.find(
        (checkpoint) => checkpoint.sequence
          === run.hardKill.restorationCheckpointSequence,
      );
      restoration.cursorSample = reference.cursorSample - 12_001;
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /hard-kill restoration exceeds 250 ms at 48 kHz/u,
    );
  });
});

test("audio restoration rejects wrong sample rate and raw identity", async () => {
  await withFixture(async ({ evidence, root }) => {
    evidence.audioRestorationRuns[0].sampleRate = 44_100;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /must use authored 48 kHz audio/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const run = evidence.audioRestorationRuns[0];
    await mutateRawReport(root, run.rawReport, (report) => {
      const checkpoint = report.audioCursorCheckpoints.find(
        (candidate) => candidate.sequence
          === run.controlledPause.pauseCheckpointSequence,
      );
      checkpoint.sampleRate = 44_100;
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /sample-rate identity drifted/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const run = evidence.audioRestorationRuns[0];
    await mutateRawReport(root, run.rawReport, (report) => {
      report.attemptID = "foreign-audio-attempt";
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /attempt ID drifted/u,
    );
  });

  await withFixture(async ({ evidence, root }) => {
    const run = evidence.audioRestorationRuns[0];
    await mutateRawReport(root, run.rawReport, (report) => {
      const checkpoint = report.audioCursorCheckpoints.find(
        (candidate) => candidate.sequence
          === run.hardKill.lastRenderedCheckpointSequence,
      );
      checkpoint.timelineID = "foreign-audio-timeline";
    });
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /timeline identity drifted/u,
    );
  });
});

test("audio-restoration artifacts cannot be reused", async () => {
  await withFixture(async ({ evidence, root }) => {
    evidence.audioRestorationRuns[1].audioTraceArchive =
      evidence.audioRestorationRuns[0].audioTraceArchive;
    await assert.rejects(
      validateFirstFarmersPhysicalEvidence(evidence, { artifactsRoot: root }),
      /reuses another run artifact/u,
    );
  });
});
