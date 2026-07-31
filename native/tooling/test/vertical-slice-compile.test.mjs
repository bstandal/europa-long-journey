import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  mkdir,
  mkdtemp,
  readFile,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  readBlueprintProjectionDocuments,
  validateBlueprintProjection,
} from "../src/blueprint-projection.mjs";
import {
  compileFutureReleasePackage,
  compilePublicPackage,
} from "../src/compile.mjs";
import {
  chapter01ImmersiveReviewIdentity,
  verticalSliceDevelopmentIdentity,
} from "../src/development-trust.mjs";
import {
  compileDevelopmentVerticalSlice,
  createDevelopmentProjectionAuthority,
  verifyDevelopmentVerticalSlice,
} from "../src/vertical-slice-compile.mjs";

const nativeRoot = fileURLToPath(new URL("../../", import.meta.url));
const blueprintRoot = path.join(nativeRoot, "blueprint");
const version = { major: 1, minor: 0, patch: 0 };
const assetPaths = [
  "assets/landscape.heif",
  "assets/landscape-settled.heif",
  "assets/reduce-motion.heif",
  "assets/reduce-motion-foreground.heif",
  "assets/layer-alpha.png",
  "assets/layer-occlusion.png",
  "assets/layer-depth.png",
  "assets/layer-light.png",
  "assets/variant-alpha.png",
  "assets/variant-occlusion.png",
  "assets/variant-depth.png",
  "assets/variant-light.png",
  "audio/narration.m4a",
];

const local = (id, launchEnglish) => ({ id, launchEnglish });
const digest = (value) => createHash("sha256").update(value).digest("hex");

function baselineCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
    safeTextRegions: [{
      id: "opening-copy",
      rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
    }],
  };
}

function largestCrop() {
  return {
    id: "largest-430x932",
    viewport: { widthPoints: 430, heightPoints: 932 },
    sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
    safeTextRegions: [{
      id: "opening-copy",
      rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
    }],
  };
}

function launchCrops() {
  return [baselineCrop(), largestCrop()];
}

function masks(prefix = "layer") {
  return {
    alphaMaskAssetPath: `assets/${prefix}-alpha.png`,
    occlusionMaskAssetPath: `assets/${prefix}-occlusion.png`,
    depthMaskAssetPath: `assets/${prefix}-depth.png`,
    lightMaskAssetPath: `assets/${prefix}-light.png`,
  };
}

function layer(id, order, variants = []) {
  return {
    id,
    order,
    assetPath: "assets/landscape.heif",
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth: (order + 1) / 10,
    opacity: 1,
    blendMode: "normal",
    masks: masks(),
    motion: { parallaxFactor: 0, windResponse: 0, focusResponse: 0 },
    stateVariants: variants.map((variantID) => ({
      id: variantID,
      assetPath: "assets/landscape-settled.heif",
      masks: masks("variant"),
    })),
  };
}

function revealNode(id, nodeID, form) {
  return {
    id,
    mutation: "reveal-node",
    node: {
      id: nodeID,
      kind: "settlement",
      form,
      position: { x: 0.55, y: 0.48 },
      attributes: [{ key: "visible", value: true }],
    },
  };
}

function establishStoreEffect(id) {
  return {
    id,
    mutation: "establish-trace",
    trace: {
      id: "harvest-store-route",
      kind: "exchange",
      origin: "harvest-floor",
      destination: "winter-store",
      strength: 1,
    },
  };
}

function accessibilityElements() {
  const action = (kind, id, label, token) => ({ kind, label: local(id, label), token });
  return ["seed", "winter"].map((destination) => ({
    id: `allocate-${destination}`,
    role: "adjustable",
    label: local(`access-${destination}-label`, `Stores for ${destination}`),
    actions: [
      action("increment", `access-${destination}-increase`, `Increase ${destination}`, {
        command: "allocate", targetID: destination, unitsPerStep: 1,
      }),
      action("decrement", `access-${destination}-decrease`, `Decrease ${destination}`, {
        command: "allocate", targetID: destination, unitsPerStep: 1,
      }),
    ],
  })).concat({
    id: "commit-allocation",
    role: "action",
    label: local("access-commit-label", "Test the stores against winter"),
    actions: [action("activate", "access-commit-action", "Commit the stores", {
      command: "commit-allocation",
    })],
  });
}

function hitRegion(minimumX, maximumX) {
  return {
    path: [
      { x: minimumX, y: 0.52 },
      { x: maximumX, y: 0.52 },
      { x: maximumX, y: 0.72 },
      { x: minimumX, y: 0.72 },
    ],
  };
}

async function buildPayload(packageID = verticalSliceDevelopmentIdentity.packageID) {
  const blueprint = await readBlueprintProjectionDocuments(blueprintRoot);
  const contract = blueprint.contracts.contracts.find(({ contentID }) => contentID === "first-farmers");
  const arc = blueprint.arcs.chapters.find(({ contentID }) => contentID === "first-farmers")
    .arcs.find(({ arcID }) => arcID === "first-farmers-arc-02");
  const interactionID = "interaction-first-farmers-the-harvest-had-to-last";
  const mapping = blueprint.interactions.items.find((item) => item.nativeInteractionID === interactionID);
  const manuscript = "One finite harvest must feed winter and preserve seed for spring.";
  const interaction = {
    id: interactionID,
    prompt: local("interaction-harvest-prompt", "Divide the store"),
    grammar: "allocate",
    configuration: {
      resourceName: local("interaction-harvest-resource", "Stored grain"),
      totalUnits: 4,
      destinations: [
        { id: "seed", minimumUnits: 1 },
        { id: "winter", minimumUnits: 1 },
      ],
    },
    completionEffects: [establishStoreEffect(mapping.worldEffectID)],
    accessibilityID: "access-harvest",
  };
  const payload = {
    schemaVersion: version,
    packageID,
    worldSeed: {
      nodes: [{
        id: "harvest-floor",
        kind: "object",
        form: "One finite harvest",
        position: { x: 0.5, y: 0.72 },
        attributes: [],
      }, {
        id: "winter-store",
        kind: "object",
        form: "An empty winter store",
        position: { x: 0.68, y: 0.56 },
        attributes: [],
      }],
      traces: [],
    },
    chapters: [{
      schemaVersion: version,
      id: "first-farmers",
      title: local("chapter-first-farmers-title", contract.title),
      period: local("chapter-first-farmers-period", contract.period),
      arcs: [{
        id: arc.arcID,
        title: local("arc-harvest-title", arc.title),
        targetDurationMinutes: arc.targetDurationMinutes,
        situation: local("arc-harvest-situation", arc.situation),
        mechanism: local("arc-harvest-mechanism", arc.mechanism),
        turn: local("arc-harvest-turn", arc.turn),
        consequence: local("arc-harvest-consequence", arc.consequence),
        handoff: local("arc-harvest-handoff", arc.handoff),
        beats: [{
          id: "harvest-had-to-last",
          sceneID: "harvest-allocation",
          narrative: {
            heading: local("manuscript-harvest-heading", "The harvest had to last"),
            paragraphs: [local("manuscript-harvest-paragraph", manuscript)],
            actionPrompt: local("manuscript-harvest-action", "Set grain aside for winter and spring"),
          },
          narrationCueIDs: ["narration-harvest"],
          interaction,
          completionEffects: [],
          checkpoint: "afterInteraction",
        }],
      }],
      completionEffects: [revealNode(
        "effect-first-farmers-at-the-iron-gates",
        "iron-gates-store",
        "Stores and households persist beside the river",
      )],
    }],
    scenes: [{
      id: "harvest-allocation",
      sceneCanvas: {
        canvas: { width: 1200, height: 2600 },
        cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
        authoredOverscanFraction: 0.16,
        viewportCrops: launchCrops(),
      },
      layers: [
        layer("harvest", 0, ["exhausted", "full"]),
        layer("grain-transfer", 1),
        layer("seed-store", 2, ["empty", "receiving", "committed"]),
        layer("winter-store-layer", 3, ["empty", "receiving", "provisioned"]),
      ],
      cameraRail: {
        keyframes: [
          { progress: 0, center: { x: 0.45, y: 0.5 }, scale: 1 },
          { progress: 1, center: { x: 0.55, y: 0.45 }, scale: 1.08 },
        ],
      },
      atmosphere: [{
        kind: "rain",
        density: 0.2,
        velocity: { dx: -0.1, dy: 0.1 },
        deterministicSeed: 42,
      }],
      interactionTargets: [{
        interactionTargetID: "seed-target",
        layerID: "seed-store",
        hitRegion: hitRegion(0.22, 0.42),
        accessibilityElementID: "allocate-seed",
      }, {
        interactionTargetID: "winter-target",
        layerID: "winter-store-layer",
        hitRegion: hitRegion(0.58, 0.78),
        accessibilityElementID: "allocate-winter",
      }],
      interactionVisualBinding: {
        grammar: "allocate",
        configuration: {
          interactionID,
          resource: {
            layerID: "harvest",
            hitRegion: {
              path: [
                { x: 0.43, y: 0.68 },
                { x: 0.57, y: 0.68 },
                { x: 0.57, y: 0.8 },
                { x: 0.43, y: 0.8 },
              ],
            },
            hitTest: "selectedVariantAlpha",
            variantsByRemainingUnits: [
              { maximumRemainingUnits: 0, variantID: "exhausted" },
              { maximumRemainingUnits: 4, variantID: "full" },
            ],
          },
          transferLayerID: "grain-transfer",
          destinations: [{
            destinationID: "seed",
            interactionTargetID: "seed-target",
            layerID: "seed-store",
            emptyVariantID: "empty",
            receivingVariantID: "receiving",
            completedVariantID: "committed",
            transferPath: [{ x: 0.5, y: 0.78 }, { x: 0.32, y: 0.62 }],
          }, {
            destinationID: "winter",
            interactionTargetID: "winter-target",
            layerID: "winter-store-layer",
            emptyVariantID: "empty",
            receivingVariantID: "receiving",
            completedVariantID: "provisioned",
            transferPath: [{ x: 0.5, y: 0.78 }, { x: 0.68, y: 0.62 }],
          }],
        },
      },
      reduceMotionComposition: {
        canvas: { width: 1200, height: 2600 },
        strata: [
          { id: "static-underlay", kind: "staticPlate", assetPath: "assets/reduce-motion.heif" },
          { id: "harvest-state", kind: "stateOverlay", layerID: "harvest" },
          { id: "seed-state", kind: "stateOverlay", layerID: "seed-store" },
          { id: "winter-state", kind: "stateOverlay", layerID: "winter-store-layer" },
          { id: "static-foreground", kind: "staticPlate", assetPath: "assets/reduce-motion-foreground.heif" },
        ],
        viewportCrops: launchCrops(),
      },
      mechanismFocus: local("scene-harvest-mechanism", "One finite harvest divided across time"),
      accessibilityID: "access-harvest",
    }],
    audioTimelines: [{
      id: "audio-harvest",
      sampleRate: 48000,
      events: [{
        cueID: "narration-harvest",
        role: "narration",
        startSample: 0,
        durationSamples: 96000,
        assetPath: "audio/narration.m4a",
        gain: 1,
        narrationBinding: {
          manuscriptSegmentID: "manuscript-harvest-paragraph",
          manuscriptSegmentSHA256: digest(manuscript),
          scope: {
            chapterID: "first-farmers",
            arcID: arc.arcID,
            beatID: "harvest-had-to-last",
          },
        },
      }],
      haptics: [{ sample: 48000, kind: "transfer", intensity: 0.4, sharpness: 0.3 }],
    }, {
      id: "responsive-harvest-approach",
      sampleRate: 48000,
      events: [{
        cueID: "cue-responsive-harvest-approach",
        role: "silence",
        startSample: 0,
        durationSamples: 96000,
        gain: 1,
      }],
      haptics: [],
    }, {
      id: "responsive-harvest-waiting",
      sampleRate: 48000,
      events: [{
        cueID: "cue-responsive-harvest-waiting",
        role: "silence",
        startSample: 0,
        durationSamples: 48000,
        gain: 1,
      }],
      haptics: [],
    }, {
      id: "responsive-harvest-engaged",
      sampleRate: 48000,
      events: [{
        cueID: "cue-responsive-harvest-engaged",
        role: "silence",
        startSample: 0,
        durationSamples: 48000,
        gain: 1,
      }],
      haptics: [],
    }, {
      id: "responsive-harvest-resistance",
      sampleRate: 48000,
      events: [{
        cueID: "cue-responsive-harvest-resistance",
        role: "silence",
        startSample: 0,
        durationSamples: 48000,
        gain: 1,
      }],
      haptics: [],
    }, {
      id: "responsive-harvest-consequence",
      sampleRate: 48000,
      events: [{
        cueID: "cue-responsive-harvest-consequence",
        role: "silence",
        startSample: 0,
        durationSamples: 96000,
        gain: 1,
      }],
      haptics: [],
    }],
    responsiveAudioPrograms: [{
      id: "program-harvest-allocation",
      scope: {
        chapterID: "first-farmers",
        arcID: arc.arcID,
        beatID: "harvest-had-to-last",
        interactionID,
      },
      approachTimelineID: "responsive-harvest-approach",
      interactionBeds: [{
        phase: "waiting",
        timelineID: "responsive-harvest-waiting",
        layerStates: {},
      }, {
        phase: "engaged",
        timelineID: "responsive-harvest-engaged",
        layerStates: {},
      }, {
        phase: "resistance",
        timelineID: "responsive-harvest-resistance",
        layerStates: {},
      }],
      consequenceTimelineID: "responsive-harvest-consequence",
      exitPolicy: {
        kind: "bounded-fade",
        durationSamples: 9_600,
      },
    }],
    accessibility: [{
      id: "access-harvest",
      sceneSummary: local("access-harvest-summary", "Grain lies between two empty stores."),
      elements: accessibilityElements(),
    }],
  };
  return { blueprint, payload };
}

async function writeSource(temporary, payload) {
  const source = path.join(temporary, "public");
  await mkdir(path.join(source, "chapters"), { recursive: true });
  await mkdir(path.join(source, "assets"), { recursive: true });
  await mkdir(path.join(source, "audio"), { recursive: true });
  const payloadPath = path.join(source, "chapters", "vertical-slice-development-v1.json");
  const payloadBytes = Buffer.from(`${JSON.stringify(payload, null, 2)}\n`);
  await writeFile(payloadPath, payloadBytes);
  for (const assetPath of assetPaths) {
    await writeFile(path.join(source, assetPath), Buffer.from(`fixture:${assetPath}`));
  }
  return { source, payloadPath, payloadBytes };
}

async function readLaunchConfiguration() {
  const readJSON = (file) => readFile(file, "utf8").then(JSON.parse);
  const [product, catalog, delivery] = await Promise.all([
    readJSON(path.join(nativeRoot, "product.json")),
    readJSON(path.join(blueprintRoot, "chapter-catalog.json")),
    readJSON(path.join(blueprintRoot, "delivery-plan.json")),
  ]);
  return { product, catalog, delivery };
}

async function createFixture(context) {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-vertical-slice-"));
  context.after(async () => {
    const { rm } = await import("node:fs/promises");
    await rm(temporary, { recursive: true, force: true });
  });
  const { blueprint, payload } = await buildPayload();
  const sourceRecord = await writeSource(temporary, payload);
  const evidence = validateBlueprintProjection(payload, blueprint, {
    scope: "VERTICAL_SLICE",
    payloadBytes: sourceRecord.payloadBytes,
  });
  const authority = createDevelopmentProjectionAuthority(evidence);
  const authorityPath = path.join(temporary, "backstage", "projection-authority.json");
  await mkdir(path.dirname(authorityPath), { recursive: true });
  await writeFile(authorityPath, `${JSON.stringify(authority, null, 2)}\n`);
  const launchConfiguration = await readLaunchConfiguration();
  return {
    temporary,
    payload,
    ...sourceRecord,
    authority,
    authorityPath,
    launchConfiguration,
    options: {
      blueprintRoot,
      launchConfiguration,
      projectionAuthorityPath: authorityPath,
      packageVersion: version,
      minimumRuntime: version,
      maximumInstalledBytes: 750_000_000,
    },
  };
}

test("compiles and verifies a development-only vertical slice through the package boundary", async (context) => {
  const fixture = await createFixture(context);
  const output = path.join(fixture.temporary, "compiled", "vertical-slice");
  const result = await compileDevelopmentVerticalSlice(fixture.source, output, fixture.options);
  assert.equal(result.manifest.packageID, verticalSliceDevelopmentIdentity.packageID);
  assert.equal(result.manifest.signature.keyID, verticalSliceDevelopmentIdentity.keyID);
  assert.equal(result.trustReceipt.trustDomain, verticalSliceDevelopmentIdentity.trustDomain);
  assert.equal(
    result.trustReceipt.projectionAuthorityStatus,
    verticalSliceDevelopmentIdentity.projectionAuthorityStatus,
  );
  assert.equal(result.trustReceipt.shippingState, "PROHIBITED");
  assert.equal(
    (await verifyDevelopmentVerticalSlice(output, result.trustReceipt, fixture.options)).manifestDigest,
    result.manifest.manifestDigest,
  );

  await writeFile(path.join(output, "audio", "narration.m4a"), "tampered");
  await assert.rejects(
    () => verifyDevelopmentVerticalSlice(output, result.trustReceipt, fixture.options),
    /size or SHA-256 mismatch/,
  );
});

test("rejects a development slice without the largest launch viewport crop", async (context) => {
  const fixture = await createFixture(context);
  fixture.payload.scenes[0].sceneCanvas.viewportCrops.pop();
  fixture.payload.scenes[0].reduceMotionComposition.viewportCrops.pop();
  await writeFile(fixture.payloadPath, `${JSON.stringify(fixture.payload, null, 2)}\n`);

  await assert.rejects(
    () => compileDevelopmentVerticalSlice(
      fixture.source,
      path.join(fixture.temporary, "compiled"),
      fixture.options,
    ),
    /exactly baseline-393x852 and largest-430x932 are required/u,
  );
});

test("rebuilds the complete development package and trust receipt byte-for-byte", async (context) => {
  const fixture = await createFixture(context);
  const firstOutput = path.join(fixture.temporary, "compiled-a", "vertical-slice");
  const secondOutput = path.join(fixture.temporary, "compiled-b", "vertical-slice");
  const first = await compileDevelopmentVerticalSlice(
    fixture.source,
    firstOutput,
    fixture.options,
  );
  const second = await compileDevelopmentVerticalSlice(
    fixture.source,
    secondOutput,
    fixture.options,
  );
  assert.deepEqual(second, first);
  assert.deepEqual(
    await readFile(path.join(secondOutput, "package-manifest.json")),
    await readFile(path.join(firstOutput, "package-manifest.json")),
  );
  assert.equal(first.manifest.signature.value, second.manifest.signature.value);
  assert.equal(
    first.trustReceipt.trustedPublicKeySPKIBase64,
    second.trustReceipt.trustedPublicKeySPKIBase64,
  );
});

test("rejects every locked launch package ID before development signing", async (context) => {
  const fixture = await createFixture(context);
  const launchIDs = fixture.launchConfiguration.delivery.packages.map(({ packageID }) => packageID);
  assert.equal(launchIDs.length, 8);
  for (const launchID of launchIDs) {
    fixture.payload.packageID = launchID;
    await writeFile(fixture.payloadPath, `${JSON.stringify(fixture.payload, null, 2)}\n`);
    await assert.rejects(
      () => compileDevelopmentVerticalSlice(
        fixture.source,
        path.join(fixture.temporary, "outputs", launchID),
        fixture.options,
      ),
      new RegExp(`launch package ID '${launchID}' is forbidden`),
    );
  }
});

test("development compiler accepts no caller-supplied production signing identity", async (context) => {
  const fixture = await createFixture(context);
  await assert.rejects(
    () => compileDevelopmentVerticalSlice(
      fixture.source,
      path.join(fixture.temporary, "compiled"),
      { ...fixture.options, keyID: "production-key-01", signingPrivateKey: Buffer.from("secret") },
    ),
    /signingPrivateKey: forbidden or unknown option/,
  );
});

test("provisional authority cannot claim launch identity, production key or editor status", async (context) => {
  const mutations = [
    [
      "launch identity",
      (authority) => { authority.packageID = "essential-free-v1"; },
      /exact development package, key and trust domain required/,
    ],
    [
      "production key",
      (authority) => { authority.keyID = "launch-2026-a"; },
      /exact development package, key and trust domain required/,
    ],
    [
      "fabricated editor status",
      (authority) => {
        authority.status = "APPROVED_BY_EDITOR_IN_CHIEF";
        authority.authority = "editor-in-chief";
      },
      /exact provisional non-shipping authority required/,
    ],
  ];
  for (const [label, mutate, expected] of mutations) {
    const fixture = await createFixture(context);
    const authority = structuredClone(fixture.authority);
    mutate(authority);
    await writeFile(
      fixture.authorityPath,
      `${JSON.stringify(authority, null, 2)}\n`,
    );
    await assert.rejects(
      () => compileDevelopmentVerticalSlice(
        fixture.source,
        path.join(fixture.temporary, "compiled", label.replaceAll(" ", "-")),
        fixture.options,
      ),
      expected,
      label,
    );
  }
});

test("release compiler refuses every development-only signing key ID", async () => {
  for (const keyID of [
    verticalSliceDevelopmentIdentity.keyID,
    chapter01ImmersiveReviewIdentity.keyID,
  ]) {
    await assert.rejects(
      () => compilePublicPackage("/tmp/source-a", "/tmp/output-b", { keyID }),
      /vertical-slice development keys are forbidden for release packages/,
    );
  }
});

test("shipping compilers refuse the provisional development authority option", async () => {
  const options = {
    projectionAuthorityPath: "/tmp/provisional-development-authority.json",
  };
  await assert.rejects(
    () => compilePublicPackage("/tmp/source-a", "/tmp/output-b", options),
    /provisional development authority is forbidden for release packages/,
  );
  await assert.rejects(
    () => compileFutureReleasePackage("/tmp/source-a", "/tmp/output-b", options),
    /provisional development authority is forbidden for release packages/,
  );
});

test("debug verification refuses a changed trust domain", async (context) => {
  const fixture = await createFixture(context);
  const output = path.join(fixture.temporary, "compiled", "vertical-slice");
  const result = await compileDevelopmentVerticalSlice(fixture.source, output, fixture.options);
  const releaseLikeTrust = {
    ...result.trustReceipt,
    trustDomain: "the-long-west-release-v1",
  };
  await assert.rejects(
    () => verifyDevelopmentVerticalSlice(output, releaseLikeTrust, fixture.options),
    /exact non-release identity required/,
  );
});

test("an approved projection cannot be reused after public payload drift", async (context) => {
  const fixture = await createFixture(context);
  fixture.payload.chapters[0].arcs[0].handoff.launchEnglish = "A different handoff.";
  await writeFile(fixture.payloadPath, `${JSON.stringify(fixture.payload, null, 2)}\n`);
  await assert.rejects(
    () => compileDevelopmentVerticalSlice(
      fixture.source,
      path.join(fixture.temporary, "compiled"),
      fixture.options,
    ),
    /locked arc\/handoff drift/,
  );
});

test("repository runtime fixture contains no fabricated editor decision", async () => {
  const obsoleteDecision = [
    "phase0", "approved", "first", "farmers", "runtime", "fixture", "2026", "07", "25",
  ].join("-");
  const generatorPath = path.join(
    nativeRoot,
    "phase2/runtime-fixture/build-runtime-fixture.mjs",
  );
  const authorityPath = path.join(
    nativeRoot,
    "phase2/runtime-fixture/backstage/projection-authority.json",
  );
  const combined = `${await readFile(generatorPath, "utf8")}\n${await readFile(authorityPath, "utf8")}`;
  assert.doesNotMatch(combined, new RegExp(obsoleteDecision));
  assert.doesNotMatch(combined, /APPROVED_BY_EDITOR_IN_CHIEF/);
  assert.doesNotMatch(combined, /"authority"\s*:\s*"editor-in-chief"/);
  const schema = JSON.parse(await readFile(path.join(
    nativeRoot,
    "schemas/development-blueprint-projection-authority.schema.json",
  ), "utf8"));
  assert.equal(
    schema.properties.status.const,
    verticalSliceDevelopmentIdentity.projectionAuthorityStatus,
  );
  assert.equal(
    schema.properties.packageID.const,
    verticalSliceDevelopmentIdentity.packageID,
  );
  assert.equal(
    schema.properties.keyID.const,
    verticalSliceDevelopmentIdentity.keyID,
  );
  assert.equal(
    schema.properties.trustDomain.const,
    verticalSliceDevelopmentIdentity.trustDomain,
  );
});
