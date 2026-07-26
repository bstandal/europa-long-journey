import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import test from "node:test";

const execFileAsync = promisify(execFile);
const cliPath = fileURLToPath(new URL("../src/launch-assembly-cli.mjs", import.meta.url));
const version = { major: 1, minor: 0, patch: 0 };
const freeChapterIDs = ["first-farmers", "europe-holds-the-line", "european-world"];

function localized(id, launchEnglish) {
  return { id, launchEnglish };
}

function validLaunchDocuments() {
  const chapterIDs = [
    "first-farmers",
    ...Array.from({ length: 11 }, (_, index) => `chapter-${String(index + 2).padStart(2, "0")}`),
    "europe-holds-the-line",
    ...Array.from({ length: 7 }, (_, index) => `chapter-${String(index + 14).padStart(2, "0")}`),
    "european-world",
    ...Array.from({ length: 3 }, (_, index) => `chapter-${index + 22}`),
  ];
  const paidChapterIDs = chapterIDs.filter((id) => !freeChapterIDs.includes(id));
  const packages = [{
    id: "essential-free-v1",
    version,
    chapterIDs: freeChapterIDs,
    maximumInstalledBytes: 750_000_000,
    minimumRuntime: version,
    isEssentialInstall: true,
  }, ...Array.from({ length: 7 }, (_, index) => ({
    id: `paid-wave-${index + 1}`,
    version,
    chapterIDs: paidChapterIDs.slice(index * 3, index * 3 + 3),
    maximumInstalledBytes: 750_000_000,
    minimumRuntime: version,
    isEssentialInstall: false,
  }))];
  const packageForChapter = new Map(
    packages.flatMap((packageSpec) => packageSpec.chapterIDs.map((chapterID) => [chapterID, packageSpec.id])),
  );
  const collection = {
    schemaVersion: version,
    collectionID: "journey-collection-v1",
    locale: { identifier: "en" },
    product: { franchiseName: "The Long West", workTitle: "EUROCENTRIC" },
    chapters: chapterIDs.map((id, index) => ({
      id,
      sequence: index + 1,
      title: localized(`${id}-title`, `Chapter ${index + 1}`),
      period: localized(`${id}-period`, `Period ${index + 1}`),
      packageID: packageForChapter.get(id),
      access: freeChapterIDs.includes(id)
        ? { kind: "included" }
        : { kind: "entitlement", entitlementID: "launch-complete-work" },
    })),
    packages,
    entitlements: [{
      id: "launch-complete-work",
      storeProductID: "com.thelongwest.complete",
      kind: "nonConsumable",
    }],
  };
  const worldSeed = {
    nodes: [{
      id: "european-world-anchor",
      kind: "institution",
      form: "The hidden cumulative world",
      position: { x: 0.5, y: 0.5 },
      attributes: [],
    }],
    traces: [],
  };
  const chapterByID = new Map(chapterIDs.map((id, index) => [id, {
    schemaVersion: version,
    id,
    title: localized(`${id}-title`, `Chapter ${index + 1}`),
    period: localized(`${id}-period`, `Period ${index + 1}`),
    arcs: [{
      id: `arc-${id}`,
      title: localized(`${id}-arc-title`, `Arc ${index + 1}`),
      targetDurationMinutes: 8,
      situation: localized(`${id}-arc-situation`, "A historical order stands in a defined place."),
      mechanism: localized(`${id}-arc-mechanism`, "Named institutions carry action into the world."),
      turn: localized(`${id}-arc-turn`, "The established arrangement changes under pressure."),
      consequence: localized(`${id}-arc-consequence`, "The changed order remains visible in the world."),
      handoff: localized(`${id}-arc-handoff`, "The next chapter inherits the altered ground."),
      beats: [{
        id: `beat-${id}`,
        sceneID: `scene-${packageForChapter.get(id)}`,
        narrative: {
          heading: localized(`${id}-beat-heading`, `The world changes in chapter ${index + 1}`),
          paragraphs: [localized(
            `${id}-beat-paragraph-1`,
            "People act through the material order around them.",
          )],
        },
        narrationCueIDs: [],
        completionEffects: [],
        checkpoint: "onExit",
      }],
    }],
    completionEffects: [{
      id: `effect-${id}`,
      mutation: "transform-node",
      nodeID: "european-world-anchor",
      form: `The world after chapter ${index + 1}`,
      attributes: [{ key: `completed-${index + 1}`, value: true }],
    }],
  }]));
  const payloads = packages.map((packageSpec) => ({
    schemaVersion: version,
    packageID: packageSpec.id,
    worldSeed: structuredClone(worldSeed),
    chapters: packageSpec.chapterIDs.map((chapterID) => chapterByID.get(chapterID)),
    scenes: [{
      id: `scene-${packageSpec.id}`,
      sceneCanvas: {
        canvas: { width: 1200, height: 2600 },
        cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
        authoredOverscanFraction: 0.15,
        viewportCrops: [{
          id: "baseline-393x852",
          viewport: { widthPoints: 393, heightPoints: 852 },
          sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
          safeTextRegions: [{
            id: "opening-copy",
            rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
          }],
        }],
      },
      layers: [{
        id: "landscape",
        order: 0,
        assetPath: "assets/world.heif",
        frame: { x: 0, y: 0, width: 1, height: 1 },
        depth: 0.2,
        opacity: 1,
        blendMode: "normal",
        masks: {},
        motion: { parallaxFactor: 0.1, windResponse: 0.1, focusResponse: 0.1 },
        stateVariants: [],
      }],
      cameraRail: {
        keyframes: [
          { progress: 0, center: { x: 0.45, y: 0.5 }, scale: 1 },
          { progress: 1, center: { x: 0.55, y: 0.45 }, scale: 1.05 },
        ],
      },
      atmosphere: [],
      interactionTargets: [],
      reduceMotionComposition: {
        canvas: { width: 1200, height: 2600 },
        strata: [
          { id: "static-world", kind: "staticPlate", assetPath: "assets/world-reduce.heif" },
        ],
        viewportCrops: [{
          id: "baseline-393x852",
          viewport: { widthPoints: 393, heightPoints: 852 },
          sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
          safeTextRegions: [{
            id: "opening-copy",
            rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
          }],
        }],
      },
      mechanismFocus: localized("living-world-mechanism-focus", "The changed institution"),
      accessibilityID: `access-${packageSpec.id}`,
    }],
    audioTimelines: [{
      id: `audio-${packageSpec.id}`,
      sampleRate: 48_000,
      events: [{
        cueID: `silence-${packageSpec.id}`,
        role: "silence",
        startSample: 0,
        durationSamples: 48_000,
        gain: 0,
      }],
      haptics: [],
    }],
    responsiveAudioPrograms: [],
    accessibility: [{
      id: `access-${packageSpec.id}`,
      sceneSummary: localized(
        "living-world-scene-summary",
        "A historical institution changes in the landscape.",
      ),
      elements: [{
        id: `image-${packageSpec.id}`,
        role: "image",
        label: localized("living-world-image-label", "The changing historical world"),
        actions: [],
      }],
    }],
  }));
  return { collection, payloads };
}

async function writeLaunchDocuments(t, documents) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "long-west-launch-assembly-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const collectionPath = path.join(directory, "collection.json");
  const payloadPaths = documents.payloads.map((_, index) => path.join(directory, `payload-${index + 1}.json`));
  await Promise.all([
    writeFile(collectionPath, `${JSON.stringify(documents.collection)}\n`),
    ...documents.payloads.map((payload, index) =>
      writeFile(payloadPaths[index], `${JSON.stringify(payload)}\n`)),
  ]);
  return { collectionPath, payloadPaths };
}

test("CLI validates eight extracted payloads and prints the final world SHA-256", async (t) => {
  const paths = await writeLaunchDocuments(t, validLaunchDocuments());
  const { stdout, stderr } = await execFileAsync(
    process.execPath,
    [cliPath, paths.collectionPath, ...paths.payloadPaths.reverse()],
  );
  assert.equal(stderr, "");
  assert.match(stdout, /^Validated launch assembly: 8 packages, 24 chapters, final world SHA-256 [a-f0-9]{64}\.\n$/);
});

test("CLI reaches the cross-package seed gate after document validation", async (t) => {
  const documents = validLaunchDocuments();
  documents.payloads[4].worldSeed.nodes[0].form = "A divergent but structurally valid seed";
  const paths = await writeLaunchDocuments(t, documents);
  await assert.rejects(
    execFileAsync(process.execPath, [cliPath, paths.collectionPath, ...paths.payloadPaths]),
    (error) => error.code === 1
      && /worldSeed: must be identical across all launch packages/.test(error.stderr),
  );
});

test("CLI fails closed unless collection plus exactly eight payload paths are supplied", async () => {
  await assert.rejects(
    execFileAsync(process.execPath, [cliPath, "collection.json"]),
    (error) => error.code === 1
      && /Usage: launch-assembly-cli\.mjs/.test(error.stderr),
  );
});
