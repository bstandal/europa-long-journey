import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  evaluateChapter01ReviewReady,
  chapter01ReviewFixtureTreeSHA256,
  chapter01ReviewSubjectSHA256,
  resolveChapter01ReviewGateStatus,
  validateChapter01ReviewEvidenceReceipt,
  validateChapter01ReviewGateDocument,
} from "./validate-chapter-01-review-ready.mjs";

const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const gatePath = path.join(
  repositoryRoot,
  "native/quality/chapter-01-review/review-ready-gate.json",
);

async function loadGate() {
  return JSON.parse(await readFile(gatePath, "utf8"));
}

function evidenceWithType(gate, type) {
  return gate.requiredEvidence.find((evidence) => evidence.type === type);
}

function commonReceipt(evidence, subjectSHA256) {
  return {
    schemaVersion: 1,
    receiptID: `${evidence.id}-chapter-01-review-v1`,
    type: evidence.type,
    milestone: "CHAPTER_01_REVIEW_READY",
    status: "PASS",
    chapterID: "first-farmers",
    shippingState: "PROHIBITED",
    subjectSHA256,
  };
}

async function prepareReviewSubjectRoot(root, gate) {
  const directoryFiles = [
    [gate.sources.runtimeFixture, "subject-fixture.txt"],
    ["native/ios/Sources", "Subject.swift"],
    ["native/ios/Tests", "SubjectTests.swift"],
    ["native/ios/UITests", "SubjectUITests.swift"],
    ["native/ios/Config", "Subject.xcconfig"],
  ];
  for (const [relativeDirectory, name] of directoryFiles) {
    const directory = path.join(root, relativeDirectory);
    await mkdir(directory, { recursive: true });
    await writeFile(path.join(directory, name), `${relativeDirectory}\n`);
  }
  for (const relativePath of [
    "native/ios/Package.swift",
    "native/ios/project.yml",
    "native/scripts/verify-native.sh",
    gate.sources.trustReceipt,
  ]) {
    const absolute = path.join(root, relativePath);
    await mkdir(path.dirname(absolute), { recursive: true });
    await writeFile(absolute, `${relativePath}\n`);
  }
}

async function writeEvidenceArtifact(root, role, contents) {
  const relativePath =
    `native/quality/chapter-01-review/evidence/artifacts/${role}.log`;
  const bytes = Buffer.from(contents, "utf8");
  const absolute = path.join(root, relativePath);
  await mkdir(path.dirname(absolute), { recursive: true });
  await writeFile(absolute, bytes);
  return {
    role,
    path: relativePath,
    bytes: bytes.length,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };
}

test("reports the current source gate with the exact review counts", async () => {
  const gate = await loadGate();
  const report = await evaluateChapter01ReviewReady({ repositoryRoot, gate });
  assert.equal(report.status, gate.status);
  assert.deepEqual(report.counts, {
    arcs: 3,
    beats: 17,
    interactions: 6,
    reviewWorlds: 6,
    narrationCues: 37,
    firstFarmersAudioTimelines: 47,
    reviewTransitions: 3,
  });
});

test("rejects a Chapter 01 source payload without the largest portrait crop", async () => {
  const gate = await loadGate();
  const source = JSON.parse(await readFile(
    path.join(repositoryRoot, gate.sources.contentPackage),
    "utf8",
  ));
  source.scenes[0].sceneCanvas.viewportCrops =
    source.scenes[0].sceneCanvas.viewportCrops.filter(
      ({ id }) => id !== "largest-430x932",
    );
  source.scenes[0].reduceMotionComposition.viewportCrops =
    source.scenes[0].reduceMotionComposition.viewportCrops.filter(
      ({ id }) => id !== "largest-430x932",
    );

  const buildRoot = path.join(repositoryRoot, "native/.build");
  await mkdir(buildRoot, { recursive: true });
  const temporaryRoot = await mkdtemp(path.join(
    repositoryRoot,
    "native/.build/chapter-01-crop-gate-",
  ));
  try {
    const relativePayload = path.relative(repositoryRoot, path.join(
      temporaryRoot,
      "first-farmers.content-package.json",
    )).split(path.sep).join("/");
    await writeFile(
      path.join(repositoryRoot, relativePayload),
      `${JSON.stringify(source, null, 2)}\n`,
    );
    gate.sources.contentPackage = relativePayload;

    await assert.rejects(
      evaluateChapter01ReviewReady({ repositoryRoot, gate }),
      /exactly baseline-393x852 and largest-430x932 are required/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("keeps the gate at CANDIDATE and rejects a premature PASS declaration", () => {
  const blockers = ["simulator-traversal: missing PASS receipt"];
  assert.equal(resolveChapter01ReviewGateStatus({
    gateStatus: "CANDIDATE",
    blockers,
  }), "CANDIDATE");
  assert.throws(
    () => resolveChapter01ReviewGateStatus({ gateStatus: "PASS", blockers }),
    /cannot declare PASS/u,
  );
  assert.throws(
    () => resolveChapter01ReviewGateStatus({
      gateStatus: "CANDIDATE", blockers, requirePass: true,
    }),
    /remains CANDIDATE/u,
  );
});

test("locks canonical beat, scene and save identities", async () => {
  const gate = await loadGate();
  gate.canonical.beatSaveAnchors[8].sceneID = "scene-first-farmers-invented";
  await assert.rejects(
    evaluateChapter01ReviewReady({ repositoryRoot, gate }),
    /save identities drifted/u,
  );

  const duplicate = await loadGate();
  duplicate.canonical.beatSaveAnchors[1].beatID =
    duplicate.canonical.beatSaveAnchors[0].beatID;
  assert.throws(
    () => validateChapter01ReviewGateDocument(duplicate),
    /must be unique/u,
  );
});

test("rejects evidence that tries to promote shipping or weakens audio restore", async () => {
  const gate = await loadGate();
  const evidence = evidenceWithType(gate, "AUDIO_RESTORE");
  const temporaryRoot = await mkdtemp(path.join(tmpdir(), "chapter-01-audio-evidence-"));
  try {
    await prepareReviewSubjectRoot(temporaryRoot, gate);
    const subjectSHA256 = await chapter01ReviewSubjectSHA256(temporaryRoot, gate);
    const log = [
      "testPeriodicCursorWritesContinueWhileMainActorIsBusy passed",
      "testPauseQuiescesRenderThreadBeforeReadingFinalCursor passed",
      "testSilenceContinuesAcrossEverySameChapterBinding passed",
      "testColdRestoredActiveSessionRequiresExplicitResume passed",
      "testAllSixResponsiveProgramsColdRestoreTheirExactLoopPositionPaused passed",
    ].join("\n");
    const receipt = {
      ...commonReceipt(evidence, subjectSHA256),
      sampleRate: 48_000,
      controlledPauseSampleDelta: 0,
      rapidTraceMaximumCursorWriteMilliseconds: 249,
      hardKillMaximumCursorWriteMilliseconds: 250,
      sameProcessBackgroundPreservesActivePhase: true,
      coldRestorePhaseNormalization: { engaged: "waiting", resistance: "waiting" },
      coldReturnStartsPaused: true,
      loopCursorPreserved: true,
      silenceSurvivesChapterLifecycle: true,
      silenceLeaksAcrossChapters: false,
      artifacts: [await writeEvidenceArtifact(temporaryRoot, "audio-restore-log", log)],
    };
    await validateChapter01ReviewEvidenceReceipt({
      repositoryRoot: temporaryRoot, gate, evidence, receipt,
    });

    receipt.rapidTraceMaximumCursorWriteMilliseconds = 251;
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /exceeded 250 ms/u,
    );
    receipt.rapidTraceMaximumCursorWriteMilliseconds = 249;
    receipt.shippingState = "APPROVED";
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /cannot authorize shipping/u,
    );
    receipt.shippingState = "PROHIBITED";
    receipt.subjectSHA256 = "b".repeat(64);
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /does not bind the current fixture and native implementation/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("requires identical touch, VoiceOver and Reduce Motion outcomes", async () => {
  const gate = await loadGate();
  const evidence = evidenceWithType(gate, "ACCESSIBILITY");
  const interactionIDs = gate.canonical.beatSaveAnchors
    .flatMap(({ interactionID }) => interactionID ? [interactionID] : []);
  const finalHash = "a".repeat(64);
  const temporaryRoot = await mkdtemp(path.join(tmpdir(), "chapter-01-ax-evidence-"));
  try {
    await prepareReviewSubjectRoot(temporaryRoot, gate);
    const subjectSHA256 = await chapter01ReviewSubjectSHA256(temporaryRoot, gate);
    const accessibilityMarker = `CHAPTER_01_SYSTEM_ACCESSIBILITY=${JSON.stringify({
      touchFinalStateSHA256: finalHash,
      voiceOverFinalStateSHA256: finalHash,
      reduceMotionFinalStateSHA256: finalHash,
      systemVoiceOverRunCompleted: true,
      systemReduceMotionRunCompleted: true,
      systemDynamicTypeRunCompleted: true,
      systemIncreasedContrastRunCompleted: true,
      simulatorSettingsRestored: true,
    })}\n`;
    const receipt = {
      ...commonReceipt(evidence, subjectSHA256),
      minimumTouchTargetPoints: 44,
      touchFinalStateSHA256: finalHash,
      voiceOverFinalStateSHA256: finalHash,
      reduceMotionFinalStateSHA256: finalHash,
      interactionIDs,
      systemVoiceOverRunCompleted: true,
      systemReduceMotionRunCompleted: true,
      systemDynamicTypeRunCompleted: true,
      systemIncreasedContrastRunCompleted: true,
      simulatorSettingsRestored: true,
      dynamicTypeHidesRequiredInformation: false,
      dynamicTypeHidesRequiredActions: false,
      increasedContrastHidesRequiredInformation: false,
      increasedContrastHidesRequiredActions: false,
      artifacts: [
        await writeEvidenceArtifact(
          temporaryRoot,
          "system-accessibility-log",
          accessibilityMarker,
        ),
        await writeEvidenceArtifact(temporaryRoot, "system-voiceover-recording", "video\n"),
      ],
    };
    await validateChapter01ReviewEvidenceReceipt({
      repositoryRoot: temporaryRoot, gate, evidence, receipt,
    });
    receipt.voiceOverFinalStateSHA256 = "b".repeat(64);
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /same historical result/u,
    );
    receipt.voiceOverFinalStateSHA256 = finalHash;
    await writeFile(
      path.join(temporaryRoot, receipt.artifacts[0].path),
      "tampered evidence\n",
    );
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /(?:byte count|hash) drifted/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("requires all 17 entry and exit restores plus all six mid-interaction restores", async () => {
  const gate = await loadGate();
  const evidence = evidenceWithType(gate, "RESTORE_MATRIX");
  const beatIDs = gate.canonical.beatSaveAnchors.map(({ beatID }) => beatID);
  const interactionIDs = gate.canonical.beatSaveAnchors
    .flatMap(({ interactionID }) => interactionID ? [interactionID] : []);
  const temporaryRoot = await mkdtemp(path.join(tmpdir(), "chapter-01-restore-evidence-"));
  try {
    await prepareReviewSubjectRoot(temporaryRoot, gate);
    const subjectSHA256 = await chapter01ReviewSubjectSHA256(temporaryRoot, gate);
    const finalStateSHA256 = "a".repeat(64);
    const checkpoints = [
      ...beatIDs.map((beatID) => ({ beatID, phase: "entry" })),
      ...beatIDs.map((beatID) => ({ beatID, phase: "exit" })),
      ...interactionIDs.map((interactionID) => ({
        beatID: gate.canonical.beatSaveAnchors.find(
          (anchor) => anchor.interactionID === interactionID,
        ).beatID,
        interactionID,
        phase: "mid-interaction",
      })),
    ];
    const marker = `CHAPTER_01_RESTORE_MATRIX=${JSON.stringify({
      checkpoints,
      finalStateSHA256,
    })}\n`;
    const receipt = {
      ...commonReceipt(evidence, subjectSHA256),
      beatEntry: beatIDs.map((beatID) => ({ beatID, passed: true })),
      beatExit: beatIDs.map((beatID) => ({ beatID, passed: true })),
      midInteraction: interactionIDs.map((interactionID) => ({ interactionID, passed: true })),
      coldReturnStartsPaused: true,
      loopCursorPreserved: true,
      finalStateSHA256,
      artifacts: [
        await writeEvidenceArtifact(temporaryRoot, "restore-matrix-log", marker),
      ],
    };
    await validateChapter01ReviewEvidenceReceipt({
      repositoryRoot: temporaryRoot, gate, evidence, receipt,
    });
    receipt.midInteraction.pop();
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /all six interactions/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("binds the required non-XCTest simulator round to its log and recording", async () => {
  const gate = await loadGate();
  const evidence = evidenceWithType(gate, "SIMULATOR_TRAVERSAL");
  const beatIDs = gate.canonical.beatSaveAnchors.map(({ beatID }) => beatID);
  const interactionIDs = gate.canonical.beatSaveAnchors
    .flatMap(({ interactionID }) => interactionID ? [interactionID] : []);
  const temporaryRoot = await mkdtemp(path.join(tmpdir(), "chapter-01-manual-evidence-"));
  try {
    await prepareReviewSubjectRoot(temporaryRoot, gate);
    const subjectSHA256 = await chapter01ReviewSubjectSHA256(temporaryRoot, gate);
    const marker = `CHAPTER_01_MANUAL_TRAVERSAL=${JSON.stringify({
      operationMode: "CODEX_COMPUTER_USE",
      beatIDs,
      interactionIDs,
      finalRoute: "world",
      deliberateEntryAction: "Begin",
      authoredSoundStartedAfterEntry: true,
      soundControlStayedVisible: true,
      playingControlLabel: "Turn sound off",
      mutePausedAuthoredSound: true,
      mutedControlLabel: "Turn sound on",
      unmuteResumedAuthoredSound: true,
      interruptionControlLabel: "Resume sound",
      interruptionRestartedSoundSpontaneously: false,
      coldRestoreControlLabel: "Resume sound",
      coldRestoreRestartedSoundSpontaneously: false,
    })}\n`;
    const receipt = {
      ...commonReceipt(evidence, subjectSHA256),
      operationMode: "CODEX_COMPUTER_USE",
      device: {
        platform: "iOS Simulator",
        model: "iPhone 17 Pro",
        osVersion: "26.5",
      },
      directLaunchBeatID: beatIDs[0],
      finalBeatID: beatIDs.at(-1),
      completedCounts: {
        arcs: 3,
        beats: 17,
        interactions: 6,
        worlds: 6,
        narrationCues: 37,
        audioTimelines: 47,
      },
      fullTraversalCompleted: true,
      deliberateEntryAction: "Begin",
      authoredSoundStartedAfterEntry: true,
      soundControlStayedVisible: true,
      playingControlLabel: "Turn sound off",
      mutePausedAuthoredSound: true,
      mutedControlLabel: "Turn sound on",
      unmuteResumedAuthoredSound: true,
      interruptionControlLabel: "Resume sound",
      interruptionRestartedSoundSpontaneously: false,
      coldRestoreControlLabel: "Resume sound",
      coldRestoreRestartedSoundSpontaneously: false,
      accountSurfaceShown: false,
      purchaseSurfaceShown: false,
      debugControlsShown: false,
      visibleReviewMarksShown: false,
      artifacts: [
        await writeEvidenceArtifact(temporaryRoot, "manual-traversal-log", marker),
        await writeEvidenceArtifact(
          temporaryRoot,
          "manual-traversal-recording",
          "recording\n",
        ),
      ],
    };
    await validateChapter01ReviewEvidenceReceipt({
      repositoryRoot: temporaryRoot, gate, evidence, receipt,
    });
    receipt.operationMode = "XCTEST";
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /must be operated outside XCTest/u,
    );
    receipt.operationMode = "CODEX_COMPUTER_USE";
    receipt.authoredSoundStartedAfterEntry = false;
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /did not start authored sound/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("binds offline PASS to 100 percent packet loss and a zero-request log", async () => {
  const gate = await loadGate();
  const evidence = evidenceWithType(gate, "OFFLINE");
  const temporaryRoot = await mkdtemp(path.join(tmpdir(), "chapter-01-offline-evidence-"));
  try {
    await prepareReviewSubjectRoot(temporaryRoot, gate);
    const subjectSHA256 = await chapter01ReviewSubjectSHA256(temporaryRoot, gate);
    const networkObservationMethods = [
      "NETTOP_EXTERNAL_SOCKET_SAMPLING",
      "CFNETWORK_DIAGNOSTICS_UNIFIED_LOG",
      "COMPILED_NON_SHIPPING_APPLE_SERVICE_BYPASS",
    ];
    const marker = `CHAPTER_01_OFFLINE=${JSON.stringify({
      networkCondition: "100_PERCENT_PACKET_LOSS",
      networkObservationMethods,
      networkRequestsObserved: 0,
      fullTraversalCompleted: true,
      restoreCompleted: true,
      assetsLoadedFromInstalledPackageOnly: true,
      simulatorNetworkSettingsRestored: true,
    })}\n`;
    const receipt = {
      ...commonReceipt(evidence, subjectSHA256),
      networkDeniedAfterInstall: true,
      fullTraversalCompleted: true,
      restoreCompleted: true,
      assetsLoadedFromInstalledPackageOnly: true,
      networkRequestsObserved: 0,
      networkCondition: "100_PERCENT_PACKET_LOSS",
      networkObservationMethods,
      simulatorNetworkSettingsRestored: true,
      artifacts: [
        await writeEvidenceArtifact(temporaryRoot, "network-denial-log", marker),
        await writeEvidenceArtifact(
          temporaryRoot,
          "offline-traversal-recording",
          "recording\n",
        ),
      ],
    };
    await validateChapter01ReviewEvidenceReceipt({
      repositoryRoot: temporaryRoot, gate, evidence, receipt,
    });
    receipt.networkRequestsObserved = 1;
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /Expected values to be strictly equal/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("requires byte-identical signed fixtures and ordinary Release rejection", async () => {
  const gate = await loadGate();
  const evidence = evidenceWithType(gate, "FIXTURE_DETERMINISM");
  const temporaryRoot = await mkdtemp(path.join(tmpdir(), "chapter-01-review-gate-"));
  try {
    const fixtureRoot = path.join(temporaryRoot, gate.sources.runtimeFixture);
    await mkdir(path.join(fixtureRoot, "chapters"), { recursive: true });
    await writeFile(path.join(fixtureRoot, "package-manifest.json"), "fixture-manifest\n");
    await writeFile(path.join(fixtureRoot, "chapters", "chapter.json"), "fixture-chapter\n");
    await prepareReviewSubjectRoot(temporaryRoot, gate);
    const trustBytes = Buffer.from("fixture-trust\n", "utf8");
    await writeFile(path.join(temporaryRoot, gate.sources.trustReceipt), trustBytes);
    const digest = await chapter01ReviewFixtureTreeSHA256(
      temporaryRoot, gate.sources.runtimeFixture,
    );
    const receipt = {
      ...commonReceipt(
        evidence,
        await chapter01ReviewSubjectSHA256(temporaryRoot, gate),
      ),
      firstBuildSHA256: digest,
      secondBuildSHA256: digest,
      trustReceiptSHA256: createHash("sha256").update(trustBytes).digest("hex"),
      byteIdentical: true,
      signatureVerified: true,
      trustBoundaryUnchanged: true,
      ordinaryReleaseRejectsReviewResources: true,
    };
    await validateChapter01ReviewEvidenceReceipt({
      repositoryRoot: temporaryRoot, gate, evidence, receipt,
    });
    receipt.secondBuildSHA256 = "d".repeat(64);
    await assert.rejects(
      validateChapter01ReviewEvidenceReceipt({
        repositoryRoot: temporaryRoot, gate, evidence, receipt,
      }),
      /not byte-identical/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});
