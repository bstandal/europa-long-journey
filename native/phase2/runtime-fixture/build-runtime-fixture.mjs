#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import {
  copyFile,
  mkdir,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  readBlueprintProjectionDocuments,
  validateBlueprintProjection,
} from "../../tooling/src/blueprint-projection.mjs";
import {
  compileDevelopmentVerticalSlice,
  createDevelopmentProjectionAuthority,
} from "../../tooling/src/vertical-slice-compile.mjs";
import { verticalSliceDevelopmentIdentity } from "../../tooling/src/development-trust.mjs";

const execFileAsync = promisify(execFile);
const fixtureRoot = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.resolve(fixtureRoot, "../..");
const repositoryRoot = path.resolve(nativeRoot, "..");
const blueprintRoot = path.join(nativeRoot, "blueprint");
const sourceRoot = path.join(fixtureRoot, "source");
const packageRoot = path.join(
  fixtureRoot,
  "compiled",
  "vertical-slice-development-v1.runtimefixture",
);
const backstageRoot = path.join(fixtureRoot, "backstage");
const authorityPath = path.join(backstageRoot, "projection-authority.json");
const trustReceiptPath = path.join(
  fixtureRoot,
  "vertical-slice-development-trust-receipt.json",
);
const lineagePath = path.join(fixtureRoot, "fixture-lineage.json");
const version = Object.freeze({ major: 1, minor: 0, patch: 0 });

const experienceLabPath = path.join(nativeRoot, "phase1/experience-lab.json");
const visualSources = Object.freeze({
  "lab-first-farmers-harvest-allocation": path.join(
    nativeRoot,
    "design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
  ),
  "lab-first-farmers-house-assembly": path.join(
    repositoryRoot,
    "site/assets/source/first-farmers/house-outlives-builders.png",
  ),
  "lab-first-farmers-land-transformation": path.join(
    repositoryRoot,
    "site/public/assets/chapters/first-farmers/more-mouths-more-land-v2.webp",
  ),
  "lab-frontiers-northern-valleys-pressure": path.join(
    repositoryRoot,
    "site/public/assets/chapters/europe-holds-the-line/02-northern-valleys-keep-crown.avif",
  ),
  "lab-european-world-ocean-schedule": path.join(
    repositoryRoot,
    "site/public/assets/chapters/european-world/02-steam-keeps-the-appointment.avif",
  ),
});
const audioSource = path.join(
  nativeRoot,
  "audio/score-soundscape/cache/harvest-responsive-v1/approach/soundscape-master.wav",
);
const sourcePayloadPath = path.join(
  nativeRoot,
  "phase2/generated/first-farmers.content-package.json",
);
const harvestProofSceneID = "lab-first-farmers-harvest-v26-parallax-proof";
const harvestProofAccessibilityID =
  "accessibility-lab-first-farmers-harvest-v26-parallax-proof";
const harvestProofRoot = path.join(
  nativeRoot,
  "content/backstage/harvest/parallax-halo-qa-v26.provisional",
);
const harvestProofInputs = Object.freeze({
  source: path.join(
    nativeRoot,
    "design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
  ),
  diagnosticUnderlay: path.join(harvestProofRoot, "diagnostic-clean-base.png"),
  peopleAlpha: path.join(harvestProofRoot, "alpha-people.png"),
  grainAlpha: path.join(harvestProofRoot, "alpha-grain.png"),
  foregroundAlpha: path.join(harvestProofRoot, "alpha-foreground.png"),
  reduceMotionStatic: path.join(harvestProofRoot, "reduce-motion-static-crop.png"),
  review: path.join(
    nativeRoot,
    "content/backstage/harvest/parallax-halo-qa-v26.review.json",
  ),
  segmentationReceipt: path.join(
    nativeRoot,
    "content/backstage/harvest/semantic-masks-v26.provisional/segmentation-receipt.json",
  ),
});
const harvestProofAssetPaths = Object.freeze({
  source: "assets/harvest-v26-parallax-development-source.png",
  diagnosticUnderlay:
    "assets/harvest-v26-parallax-diagnostic-underlay.png",
  peopleAlpha: "assets/harvest-v26-parallax-alpha-people.png",
  grainAlpha: "assets/harvest-v26-parallax-alpha-grain.png",
  foregroundAlpha: "assets/harvest-v26-parallax-alpha-foreground.png",
  reduceMotionStatic:
    "assets/harvest-v26-parallax-reduce-motion-static.png",
});

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function fileRecord(file) {
  const bytes = await readFile(file);
  return {
    path: path.relative(repositoryRoot, file).split(path.sep).join("/"),
    bytes: bytes.byteLength,
    sha256: sha256(bytes),
  };
}

async function writeJSON(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

async function renderRaster(source, destination, tailFilter) {
  const common = "scale=393:852:force_original_aspect_ratio=increase,crop=393:852";
  const filter = tailFilter ? `${common},${tailFilter}` : common;
  await execFileAsync("ffmpeg", [
    "-hide_banner",
    "-loglevel", "error",
    "-y",
    "-i", source,
    "-vf", filter,
    "-frames:v", "1",
    "-map_metadata", "-1",
    destination,
  ]);
}

async function renderAssets() {
  const assetRoot = path.join(sourceRoot, "assets");
  const audioRoot = path.join(sourceRoot, "audio");
  await mkdir(assetRoot, { recursive: true });
  await mkdir(audioRoot, { recursive: true });

  const rasterSpecifications = [
    ["base", "eq=contrast=1.02:brightness=-0.025:saturation=0.92"],
    ["state-before", "eq=contrast=0.9:brightness=-0.14:saturation=0.52"],
    ["state-active", "eq=contrast=1.06:brightness=0.015:saturation=0.98"],
    ["state-completed", "eq=contrast=1.12:brightness=0.035:saturation=1.08"],
    ["reduce-motion-underlay", "eq=contrast=0.94:brightness=-0.06:saturation=0.76"],
    ["reduce-motion-foreground", "eq=contrast=1.18:brightness=-0.18:saturation=0.64"],
    ["alpha", "format=gray,eq=contrast=0.22:brightness=0.72"],
    ["occlusion", "format=gray,negate,eq=contrast=0.55:brightness=0.18"],
    ["depth", "format=gray,eq=contrast=0.72:brightness=0.08"],
    ["light", "format=gray,eq=contrast=1.65:brightness=-0.12"],
  ];
  for (const [sceneID, source] of Object.entries(visualSources)) {
    for (const [suffix, filter] of rasterSpecifications) {
      await renderRaster(
        source,
        path.join(assetRoot, `${sceneID}-${suffix}.png`),
        filter,
      );
    }
  }

  const audioFilters = [
    "highpass=f=35,lowpass=f=9000,volume=0.80",
    "highpass=f=50,lowpass=f=7200,volume=0.76",
    "highpass=f=45,lowpass=f=8400,volume=0.78",
    "highpass=f=60,lowpass=f=6600,volume=0.74",
    "highpass=f=40,lowpass=f=9600,volume=0.77",
  ];
  for (const [index, sceneID] of Object.keys(visualSources).entries()) {
    await execFileAsync("ffmpeg", [
      "-hide_banner",
      "-loglevel", "error",
      "-y",
      "-i", audioSource,
      "-t", "60",
      "-af", audioFilters[index],
      "-map_metadata", "-1",
      "-fflags", "+bitexact",
      "-flags:a", "+bitexact",
      "-c:a", "aac",
      "-b:a", "128k",
      "-ar", "48000",
      "-ac", "2",
      path.join(audioRoot, `${sceneID}-soundscape.m4a`),
    ]);
  }

  for (const [role, packagePath] of Object.entries(harvestProofAssetPaths)) {
    await copyFile(
      harvestProofInputs[role],
      path.join(sourceRoot, ...packagePath.split("/")),
    );
  }
}

function localizedEnglish(value) {
  return value?.launchEnglish;
}

function local(id, launchEnglish) {
  return { id, launchEnglish };
}

function assetPath(sceneID, suffix) {
  return `assets/${sceneID}-${suffix}.png`;
}

function audioPath(sceneID) {
  return `audio/${sceneID}-soundscape.m4a`;
}

function technicalMasks(sceneID) {
  return {
    alphaMaskAssetPath: assetPath(sceneID, "alpha"),
    occlusionMaskAssetPath: assetPath(sceneID, "occlusion"),
    depthMaskAssetPath: assetPath(sceneID, "depth"),
    lightMaskAssetPath: assetPath(sceneID, "light"),
  };
}

function variantAssetPath(sceneID, variantID) {
  if ([
    "available", "before", "broken", "empty", "exhausted", "idle",
    "resting", "scarce",
  ].includes(variantID)) {
    return assetPath(sceneID, "state-before");
  }
  if ([
    "active", "receiving", "reduced", "resisted", "resisting", "tracing",
  ].includes(variantID)) {
    return assetPath(sceneID, "state-active");
  }
  return assetPath(sceneID, "state-completed");
}

function rewriteMasks(masks, sceneID) {
  const paths = technicalMasks(sceneID);
  for (const key of Object.keys(paths)) {
    if (masks[key]) masks[key] = paths[key];
  }
}

function rewriteAuthoredSceneAssets(scene, sceneID) {
  scene.id = sceneID;
  for (const layer of scene.layers) {
    layer.assetPath = assetPath(sceneID, "base");
    rewriteMasks(layer.masks, sceneID);
    for (const variant of layer.stateVariants) {
      variant.assetPath = variantAssetPath(sceneID, variant.id);
      rewriteMasks(variant.masks, sceneID);
    }
  }
  const staticStrata = scene.reduceMotionComposition.strata.filter(
    ({ kind }) => kind === "staticPlate",
  );
  for (const [index, stratum] of staticStrata.entries()) {
    stratum.assetPath = index === 0
      ? assetPath(sceneID, "reduce-motion-underlay")
      : assetPath(sceneID, "reduce-motion-foreground");
  }
  return scene;
}

function baselineCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: { x: 0.15, y: 0.15, width: 0.7, height: 0.7 },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function targetRegion(x, y, width = 0.15, height = 0.12) {
  return {
    path: [
      { x, y },
      { x: x + width, y },
      { x: x + width, y: y + height },
      { x, y: y + height },
    ],
  };
}

function technicalLayer(sceneID, id, order, variants = [], options = {}) {
  return {
    id,
    order,
    assetPath: assetPath(sceneID, "base"),
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth: options.depth ?? Math.min(0.96, 0.08 + order * 0.12),
    opacity: options.opacity ?? 1,
    blendMode: options.blendMode ?? "normal",
    masks: technicalMasks(sceneID),
    motion: {
      parallaxFactor: options.parallaxFactor ?? 0,
      windResponse: 0,
      focusResponse: options.focusResponse ?? 0.2,
    },
    stateVariants: variants.map((id) => ({
      id,
      assetPath: variantAssetPath(sceneID, id),
      masks: technicalMasks(sceneID),
    })),
  };
}

function technicalScene({
  sceneID,
  accessibilityID,
  mechanism,
  layers,
  interactionTargets,
  interactionVisualBinding,
  atmosphere,
}) {
  const statefulLayers = layers.filter(({ stateVariants }) => stateVariants.length > 0);
  return {
    id: sceneID,
    sceneCanvas: {
      canvas: { width: 1179, height: 2556 },
      cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
      authoredOverscanFraction: 0.15,
      viewportCrops: [baselineCrop()],
    },
    layers,
    cameraRail: {
      keyframes: [
        { progress: 0, center: { x: 0.5, y: 0.5 }, scale: 1 },
        { progress: 1, center: { x: 0.5, y: 0.5 }, scale: 1 },
      ],
    },
    atmosphere: [atmosphere],
    interactionTargets,
    interactionVisualBinding,
    reduceMotionComposition: {
      canvas: { width: 1179, height: 2556 },
      viewportCrops: [baselineCrop()],
      strata: [
        {
          id: "static-underlay",
          kind: "staticPlate",
          assetPath: assetPath(sceneID, "reduce-motion-underlay"),
        },
        ...statefulLayers.map(({ id }) => ({
          id: `${id}-state`,
          kind: "stateOverlay",
          layerID: id,
        })),
        {
          id: "static-foreground",
          kind: "staticPlate",
          assetPath: assetPath(sceneID, "reduce-motion-foreground"),
        },
      ],
    },
    mechanismFocus: mechanism,
    accessibilityID,
  };
}

function harvestProofCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: {
      x: 103 / 1290,
      y: 224 / 2796,
      width: 1084 / 1290,
      height: 2348 / 2796,
    },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function harvestProofStaticCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: { x: 0, y: 0, width: 1, height: 1 },
    safeTextRegions: [
      { id: "narrative-copy", rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 } },
      { id: "mechanism-caption", rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 } },
    ],
  };
}

function harvestProofLayer(id, order, depth, parallaxFactor, alphaMaskAssetPath = null) {
  return {
    id,
    order,
    assetPath: id === "diagnostic-underlay"
      ? harvestProofAssetPaths.diagnosticUnderlay
      : harvestProofAssetPaths.source,
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth,
    opacity: 1,
    blendMode: "normal",
    masks: alphaMaskAssetPath ? { alphaMaskAssetPath } : {},
    motion: { parallaxFactor, windResponse: 0, focusResponse: 0 },
    stateVariants: [],
  };
}

function makeHarvestParallaxProof() {
  const mechanism = local(
    `${harvestProofSceneID}-mechanism-focus`,
    "Hands, grain and foreground material separate by bounded depth while the settlement remains fixed beneath them.",
  );
  const scene = {
    id: harvestProofSceneID,
    sceneCanvas: {
      canvas: { width: 1290, height: 2796 },
      cameraTravelBounds: { x: 0.42, y: 0.44, width: 0.16, height: 0.12 },
      authoredOverscanFraction: 0.15,
      viewportCrops: [harvestProofCrop()],
    },
    layers: [
      harvestProofLayer("diagnostic-underlay", 0, 0.08, 0),
      harvestProofLayer(
        "people",
        1,
        0.42,
        3 / (0.01 * 1290),
        harvestProofAssetPaths.peopleAlpha,
      ),
      harvestProofLayer(
        "grain",
        2,
        0.64,
        8 / (0.01 * 1290),
        harvestProofAssetPaths.grainAlpha,
      ),
      harvestProofLayer(
        "foreground",
        3,
        0.9,
        10 / (0.01 * 1290),
        harvestProofAssetPaths.foregroundAlpha,
      ),
    ],
    // The rail begins at the frozen crop. Its two extrema keep every relative
    // layer displacement at or below the exact v26 PARTIAL_PASS stress bound.
    cameraRail: {
      keyframes: [
        { progress: 0, center: { x: 0.5, y: 0.5 }, scale: 1 },
        { progress: 0.5, center: { x: 0.49, y: 0.5015379113018598 }, scale: 1 },
        { progress: 1, center: { x: 0.51, y: 0.4984620886981402 }, scale: 1 },
      ],
    },
    atmosphere: [],
    interactionTargets: [],
    reduceMotionComposition: {
      canvas: { width: 786, height: 1704 },
      viewportCrops: [harvestProofStaticCrop()],
      strata: [{
        id: "frozen-static-crop",
        kind: "staticPlate",
        assetPath: harvestProofAssetPaths.reduceMotionStatic,
      }],
    },
    mechanismFocus: mechanism,
    accessibilityID: harvestProofAccessibilityID,
  };
  const accessibility = {
    id: harvestProofAccessibilityID,
    sceneSummary: local(
      `${harvestProofSceneID}-scene-summary`,
      "A harvest settlement held at the exact approved static crop.",
    ),
    elements: [
      {
        id: "scene-heading",
        role: "heading",
        label: local(
          `${harvestProofSceneID}-heading`,
          "The Harvest Had to Last",
        ),
        actions: [],
      },
      {
        id: "historical-mechanism",
        role: "mechanism",
        label: mechanism,
        actions: [],
      },
    ],
  };
  return { scene, accessibility };
}

function descriptiveAccessibilityElements(beat, mechanism) {
  return [
    {
      id: "scene-heading",
      role: "heading",
      label: beat.narrative.heading,
      actions: [],
    },
    ...beat.narrative.paragraphs.map((paragraph, index) => ({
      id: `narration-${index + 1}`,
      role: "narration",
      label: paragraph,
      actions: [],
    })),
    {
      id: "historical-mechanism",
      role: "mechanism",
      label: mechanism,
      actions: [],
    },
  ];
}

function action(kind, id, label, token) {
  return { kind, label: local(id, label), token };
}

function makeAccessibility(beat, mechanism, controls) {
  return {
    id: beat.interaction.accessibilityID,
    sceneSummary: local(
      `${beat.id}-scene-summary`,
      `${beat.narrative.heading.launchEnglish}. ${mechanism.launchEnglish}`,
    ),
    elements: descriptiveAccessibilityElements(beat, mechanism).concat(controls),
  };
}

function makeResponsiveAudio(chapterID, arcID, beat, sceneID) {
  const regions = [
    ["approach", 144000],
    ["waiting", 96000],
    ["engaged", 96000],
    ["resistance", 96000],
    ["consequence", 144000],
  ];
  const timelineID = (region) => `responsive-${beat.id}-${region}`;
  return {
    program: {
      id: `responsive-program-${beat.id}`,
      scope: {
        chapterID,
        arcID,
        beatID: beat.id,
        interactionID: beat.interaction.id,
      },
      approachTimelineID: timelineID("approach"),
      interactionBeds: ["waiting", "engaged", "resistance"].map((phase) => ({
        phase,
        timelineID: timelineID(phase),
        layerStates: {
          soundscapeStateID: `${sceneID}-${phase}-world`,
        },
      })),
      consequenceTimelineID: timelineID("consequence"),
      exitPolicy: {
        kind: "bounded-fade",
        durationSamples: 9_600,
      },
    },
    timelines: regions.map(([region, durationSamples]) => ({
      id: timelineID(region),
      sampleRate: 48000,
      events: [{
        cueID: `cue-${beat.id}-${region}-soundscape`,
        role: "soundscape",
        startSample: 0,
        durationSamples,
        assetPath: audioPath(sceneID),
        gain: 0.72,
      }],
      haptics: [],
    })),
  };
}

function approvedArc(documents, contentID, arcID) {
  const chapter = documents.arcs.chapters.find((item) => item.contentID === contentID);
  const arc = chapter?.arcs.find((item) => item.arcID === arcID);
  if (!arc) throw new Error(`Missing approved arc ${contentID}/${arcID}`);
  return arc;
}

function approvedContract(documents, contentID) {
  const contract = documents.contracts.contracts.find((item) => item.contentID === contentID);
  if (!contract) throw new Error(`Missing approved contract ${contentID}`);
  return contract;
}

function projectArc(arc, beats, prefix) {
  return {
    id: arc.arcID,
    title: local(`${prefix}-title`, arc.title),
    targetDurationMinutes: arc.targetDurationMinutes,
    situation: local(`${prefix}-situation`, arc.situation),
    mechanism: local(`${prefix}-mechanism`, arc.mechanism),
    turn: local(`${prefix}-turn`, arc.turn),
    consequence: local(`${prefix}-consequence`, arc.consequence),
    handoff: local(`${prefix}-handoff`, arc.handoff),
    beats,
  };
}

function revealNodeEffect(id, nodeID, kind, form, position, attributes = []) {
  return {
    id,
    mutation: "reveal-node",
    node: { id: nodeID, kind, form, position, attributes },
  };
}

function makeAssembleProjection(source) {
  const sceneID = "lab-first-farmers-house-assembly";
  const sourceBeat = source.chapters[0].arcs
    .flatMap(({ beats }) => beats)
    .find(({ interaction }) => interaction?.id === "interaction-first-farmers-the-house-outlives");
  if (!sourceBeat) throw new Error("Missing authored house assembly beat");
  const beat = structuredClone(sourceBeat);
  beat.id = "beat-first-farmers-house-assembly";
  beat.sceneID = sceneID;
  beat.narrationCueIDs = [];
  beat.interaction.accessibilityID = "accessibility-lab-first-farmers-house-assembly";
  const mechanism = local(
    `${sceneID}-mechanism-focus`,
    "Posts, hearth, storage and roof make one house; rebuilding fixes the household to remembered ground.",
  );
  const sourcePositions = [
    [0.2, 0.36], [0.36, 0.36], [0.52, 0.36], [0.68, 0.36],
  ];
  const slotPositions = [
    [0.2, 0.64], [0.36, 0.64], [0.52, 0.64], [0.68, 0.64],
  ];
  const components = beat.interaction.configuration.components;
  const componentLayers = components.map(({ id }, index) =>
    technicalLayer(sceneID, `component-${id}`, index + 1, ["available", "resisted", "placed"]));
  const targets = components.flatMap(({ id }, index) => [
    {
      interactionTargetID: `component-${id}-source`,
      layerID: `component-${id}`,
      hitRegion: targetRegion(...sourcePositions[index], 0.1, 0.1),
      accessibilityElementID: `assemble-${id}`,
    },
    {
      interactionTargetID: `component-${id}-slot`,
      layerID: `component-${id}`,
      hitRegion: targetRegion(...slotPositions[index], 0.1, 0.1),
      accessibilityElementID: `assemble-${id}`,
    },
  ]);
  const scene = technicalScene({
    sceneID,
    accessibilityID: beat.interaction.accessibilityID,
    mechanism,
    layers: [
      technicalLayer(sceneID, "background", 0, [], { depth: 0.08, parallaxFactor: 0.02 }),
      ...componentLayers,
      technicalLayer(sceneID, "foreground", components.length + 1, [], {
        depth: 0.92,
        parallaxFactor: 0.08,
      }),
    ],
    interactionTargets: targets,
    interactionVisualBinding: {
      grammar: "assemble",
      configuration: {
        interactionID: beat.interaction.id,
        components: components.map(({ id }) => ({
          componentID: id,
          sourceInteractionTargetID: `component-${id}-source`,
          slotInteractionTargetID: `component-${id}-slot`,
          layerID: `component-${id}`,
          availableVariantID: "available",
          resistedVariantID: "resisted",
          placedVariantID: "placed",
        })),
      },
    },
    atmosphere: {
      kind: "smoke",
      density: 0.13,
      velocity: { dx: 0.03, dy: -0.08 },
      deterministicSeed: 19910411,
    },
  });
  const controls = components.map(({ id }) => ({
    id: `assemble-${id}`,
    role: "action",
    label: local(`${beat.id}-${id}-label`, id.replaceAll("-", " ")),
    actions: [action(
      "activate",
      `${beat.id}-${id}-place-label`,
      `Place ${id.replaceAll("-", " ")}`,
      { command: "place-component", targetID: id },
    )],
  }));
  return { beat, scene, accessibility: makeAccessibility(beat, mechanism, controls) };
}

function makeTransformProjection(source) {
  const sceneID = "lab-first-farmers-land-transformation";
  const sourceBeat = source.chapters[0].arcs
    .flatMap(({ beats }) => beats)
    .find(({ interaction }) => interaction?.id === "interaction-first-farmers-more-mouths-more-land");
  if (!sourceBeat) throw new Error("Missing authored land transformation beat");
  const beat = structuredClone(sourceBeat);
  beat.id = "beat-first-farmers-land-transformation";
  beat.sceneID = sceneID;
  beat.narrationCueIDs = [];
  beat.interaction.accessibilityID = "accessibility-lab-first-farmers-land-transformation";
  beat.interaction.configuration.stages = [
    { id: "new-hearths", controlID: "settlement-pressure", requiredAmount: 1 },
    { id: "field-edges", controlID: "settlement-pressure", requiredAmount: 1 },
    { id: "herd-lanes", controlID: "settlement-pressure", requiredAmount: 1 },
    { id: "daughter-settlements", controlID: "settlement-pressure", requiredAmount: 1 },
  ];
  const mechanism = local(
    `${sceneID}-mechanism-focus`,
    "New hearths, field edges, herd lanes and daughter settlements remain cut into the same ground.",
  );
  const positions = [
    [0.24, 0.46], [0.61, 0.46], [0.24, 0.66], [0.61, 0.66],
  ];
  const stages = beat.interaction.configuration.stages;
  const stageLayers = stages.map(({ id }, index) =>
    technicalLayer(sceneID, `stage-${id}`, index + 1, ["before", "active", "completed"]));
  const targets = stages.map(({ id }, index) => ({
    interactionTargetID: `stage-${id}-target`,
    layerID: `stage-${id}`,
    hitRegion: targetRegion(...positions[index]),
    accessibilityElementID: `transform-${id}`,
  }));
  const scene = technicalScene({
    sceneID,
    accessibilityID: beat.interaction.accessibilityID,
    mechanism,
    layers: [
      technicalLayer(sceneID, "background", 0, [], { depth: 0.08, parallaxFactor: 0.02 }),
      ...stageLayers,
      technicalLayer(sceneID, "foreground", stages.length + 1, [], {
        depth: 0.92,
        parallaxFactor: 0.08,
      }),
    ],
    interactionTargets: targets,
    interactionVisualBinding: {
      grammar: "transform",
      configuration: {
        interactionID: beat.interaction.id,
        stages: stages.map(({ id }) => ({
          stageID: id,
          interactionTargetID: `stage-${id}-target`,
          layerID: `stage-${id}`,
          beforeVariantID: "before",
          activeVariantID: "active",
          completedVariantID: "completed",
        })),
      },
    },
    atmosphere: {
      kind: "dust",
      density: 0.12,
      velocity: { dx: 0.05, dy: -0.02 },
      deterministicSeed: 19910412,
    },
  });
  const controls = stages.map(({ id }) => ({
    id: `transform-${id}`,
    role: "adjustable",
    label: local(`${beat.id}-${id}-label`, id.replaceAll("-", " ")),
    actions: [action(
      "increment",
      `${beat.id}-${id}-advance-label`,
      `Advance ${id.replaceAll("-", " ")}`,
      { command: "advance-transform", targetID: id, step: 1 },
    )],
  }));
  return { beat, scene, accessibility: makeAccessibility(beat, mechanism, controls) };
}

function makePressureProjection(documents) {
  const sceneID = "lab-frontiers-northern-valleys-pressure";
  const accessibilityID = "accessibility-lab-frontiers-northern-valleys-pressure";
  const interaction = {
    id: "interaction-europe-holds-the-line-northern-valleys-keep-crown",
    prompt: local(`${sceneID}-prompt`, "Hold the northern valleys"),
    grammar: "pressure",
    configuration: {
      forces: [
        { id: "conquest-pressure", direction: 1, initialMagnitude: 0.85, userControllable: false },
        { id: "mountain-depth", direction: -1, initialMagnitude: 0.15, userControllable: false },
        { id: "inhabited-stores", direction: -1, initialMagnitude: 0.2, userControllable: true },
      ],
      stableRange: [-0.05, 0.05],
      requiredHoldMillis: 1000,
    },
    completionEffects: [revealNodeEffect(
      "effect-europe-holds-the-line-northern-valleys-keep-crown",
      "trace-christian-frontier",
      "frontier",
      "Held passes, Oviedo, monastic stores and defended fields reaching toward León",
      { x: 0.32, y: 0.44 },
      [
        { key: "inhabitedCorridor", value: true },
        { key: "heldPasses", value: 1 },
      ],
    )],
    accessibilityID,
  };
  const beat = {
    id: "beat-frontiers-northern-valleys-pressure",
    sceneID,
    narrative: {
      eyebrow: local(`${sceneID}-eyebrow`, "c. AD 718–910 · Asturias"),
      heading: local(`${sceneID}-heading`, "The Northern Valleys Keep a Crown"),
      paragraphs: [
        local(
          `${sceneID}-paragraph-1`,
          "Rain crossed the Cantabrian ridges, paths narrowed above wooded ravines and an army accustomed to open country lost the advantage of numbers. Pelagius and a small Christian following preserved an armed centre beyond Córdoba’s dependable control.",
        ),
        local(
          `${sceneID}-paragraph-2`,
          "Asturian kings turned endurance into government. A court at Oviedo, churches, monasteries, defended routes and stored grain carried the crown toward León and the Duero basin.",
        ),
      ],
      actionPrompt: local(`${sceneID}-action`, "Hold the inhabited line"),
    },
    narrationCueIDs: [],
    interaction,
    completionEffects: [],
    checkpoint: "continuous",
  };
  const mechanism = local(
    `${sceneID}-mechanism-focus`,
    "Terrain buys refuge; court, stores and defended fields turn refuge into a frontier that can advance.",
  );
  const layers = [
    technicalLayer(sceneID, "background", 0, [], { depth: 0.08, parallaxFactor: 0.02 }),
    technicalLayer(sceneID, "conquest-force", 1),
    technicalLayer(sceneID, "mountain-depth", 2),
    technicalLayer(sceneID, "inhabited-stores", 3),
    technicalLayer(sceneID, "frontier-system", 4, ["resting", "resisting", "stable", "broken"]),
    technicalLayer(sceneID, "foreground", 5, [], { depth: 0.92, parallaxFactor: 0.08 }),
  ];
  const scene = technicalScene({
    sceneID,
    accessibilityID,
    mechanism,
    layers,
    interactionTargets: [{
      interactionTargetID: "inhabited-stores-target",
      layerID: "inhabited-stores",
      hitRegion: targetRegion(0.42, 0.56, 0.16, 0.16),
      accessibilityElementID: "pressure-inhabited-stores",
    }],
    interactionVisualBinding: {
      grammar: "pressure",
      configuration: {
        interactionID: interaction.id,
        forces: [
          { forceID: "conquest-pressure", layerID: "conquest-force" },
          { forceID: "mountain-depth", layerID: "mountain-depth" },
          {
            forceID: "inhabited-stores",
            layerID: "inhabited-stores",
            interactionTargetID: "inhabited-stores-target",
          },
        ],
        systemLayerID: "frontier-system",
        restingVariantID: "resting",
        resistingVariantID: "resisting",
        stableVariantID: "stable",
        brokenVariantID: "broken",
      },
    },
    atmosphere: {
      kind: "rain",
      density: 0.18,
      velocity: { dx: -0.08, dy: 0.18 },
      deterministicSeed: 19910413,
    },
  });
  const controls = [{
    id: "pressure-inhabited-stores",
    role: "adjustable",
    label: local(`${sceneID}-stores-label`, "The inhabited corridor"),
    hint: local(`${sceneID}-stores-hint`, "Strengthen the stores, fields and defended routes."),
    actions: [
      action("increment", `${sceneID}-stores-increase`, "Strengthen the corridor", {
        command: "adjust-pressure", targetID: "inhabited-stores", step: 0.5,
      }),
      action("decrement", `${sceneID}-stores-decrease`, "Release the corridor", {
        command: "adjust-pressure", targetID: "inhabited-stores", step: 0.5,
      }),
    ],
  }, {
    id: "pressure-hold-line",
    role: "action",
    label: local(`${sceneID}-hold-label`, "Hold the line"),
    actions: [action("activate", `${sceneID}-hold-action`, "Hold the line", {
      command: "hold-pressure",
    })],
  }];
  const contract = approvedContract(documents, "europe-holds-the-line");
  const arc = approvedArc(documents, "europe-holds-the-line", "europe-holds-the-line-arc-01");
  const chapter = {
    schemaVersion: version,
    id: "europe-holds-the-line",
    title: local("lab-frontiers-title", contract.title),
    period: local("lab-frontiers-period", contract.period),
    arcs: [projectArc(arc, [beat], "lab-frontiers-arc-01")],
    completionEffects: [revealNodeEffect(
      "effect-europe-holds-the-line-europe-answers-clermont",
      "trace-coalition-defence",
      "institution",
      "A coalition route able to carry armed aid across Christian Europe",
      { x: 0.49, y: 0.47 },
    )],
  };
  return { chapter, beat, scene, accessibility: makeAccessibility(beat, mechanism, controls) };
}

function makeTraceProjection(documents) {
  const sceneID = "lab-european-world-ocean-schedule";
  const accessibilityID = "accessibility-lab-european-world-ocean-schedule";
  const interaction = {
    id: "interaction-european-world-steam-keeps-the-appointment",
    prompt: local(`${sceneID}-prompt`, "Put the ocean on schedule"),
    grammar: "trace",
    configuration: {
      anchors: [
        { x: 0.3, y: 0.54 },
        { x: 0.43, y: 0.52 },
        { x: 0.57, y: 0.5 },
        { x: 0.7, y: 0.48 },
      ],
      tolerance: 0.08,
    },
    completionEffects: [{
      id: "effect-european-world-steam-keeps-the-appointment",
      mutation: "establish-trace",
      trace: {
        id: "trace-global-schedule",
        kind: "seaRoute",
        origin: "bristol-packet-office",
        destination: "new-york-packet-office",
        strength: 1,
      },
    }],
    accessibilityID,
  };
  const beat = {
    id: "beat-european-world-ocean-schedule",
    sceneID,
    narrative: {
      eyebrow: local(`${sceneID}-eyebrow`, "AD 1838–1840 · North Atlantic"),
      heading: local(`${sceneID}-heading`, "Steam Keeps the Appointment"),
      paragraphs: [
        local(
          `${sceneID}-paragraph-1`,
          "In April 1838, Sirius and Great Western reached New York from Britain under steam. A purpose-built steamship could carry enough coal for the North Atlantic and retain motive power when the wind failed.",
        ),
        local(
          `${sceneID}-paragraph-2`,
          "From 1840, Cunard packets left Liverpool on announced dates. Coal bunkers, engineering watches, shore agents and mail offices made repeated appointments reliable enough for other institutions to attach their work to the ship.",
        ),
      ],
      actionPrompt: local(`${sceneID}-action`, "Carry the appointment across the ocean"),
    },
    narrationCueIDs: [],
    interaction,
    completionEffects: [],
    checkpoint: "continuous",
  };
  const mechanism = local(
    `${sceneID}-mechanism-focus`,
    "Steam power, coal capacity, machinery watches and mail offices turn a crossing into a repeatable appointment.",
  );
  const scene = technicalScene({
    sceneID,
    accessibilityID,
    mechanism,
    layers: [
      technicalLayer(sceneID, "background", 0, [], { depth: 0.08, parallaxFactor: 0.02 }),
      technicalLayer(sceneID, "route-system", 1, ["idle", "tracing", "completed"], {
        depth: 0.56,
        focusResponse: 0.8,
      }),
      technicalLayer(sceneID, "foreground", 2, [], { depth: 0.92, parallaxFactor: 0.08 }),
    ],
    interactionTargets: [{
      interactionTargetID: "trace-ocean-route-target",
      layerID: "route-system",
      hitRegion: targetRegion(0.25, 0.4, 0.5, 0.24),
      accessibilityElementID: "trace-ocean-route",
    }],
    interactionVisualBinding: {
      grammar: "trace",
      configuration: {
        interactionID: interaction.id,
        interactionTargetID: "trace-ocean-route-target",
        layerID: "route-system",
        idleVariantID: "idle",
        tracingVariantID: "tracing",
        completedVariantID: "completed",
      },
    },
    atmosphere: {
      kind: "mist",
      density: 0.14,
      velocity: { dx: 0.08, dy: -0.01 },
      deterministicSeed: 19910414,
    },
  });
  const controls = [{
    id: "trace-ocean-route",
    role: "adjustable",
    label: local(`${sceneID}-route-label`, "The North Atlantic appointment"),
    hint: local(`${sceneID}-route-hint`, "Advance through power, coal, watches and connected mail."),
    actions: [action("increment", `${sceneID}-route-next`, "Advance the packet", {
      command: "trace-next",
    })],
  }];
  const contract = approvedContract(documents, "european-world");
  const arc = approvedArc(documents, "european-world", "european-world-arc-01");
  const chapter = {
    schemaVersion: version,
    id: "european-world",
    title: local("lab-european-world-title", contract.title),
    period: local("lab-european-world-period", contract.period),
    arcs: [projectArc(arc, [beat], "lab-european-world-arc-01")],
    completionEffects: [revealNodeEffect(
      "effect-european-world-twenty-states-agree-on-the-signal",
      "trace-common-protocols",
      "institution",
      "A common technical protocol carried through permanent international offices",
      { x: 0.58, y: 0.43 },
    )],
  };
  return { chapter, beat, scene, accessibility: makeAccessibility(beat, mechanism, controls) };
}

function validateExperienceLabCoverage(payload, experienceLab) {
  const issues = [];
  if (experienceLab.status !== "LOCKED_IMPLEMENTATION_SET") {
    issues.push("experience lab is not locked");
  }
  const grammarSet = new Set();
  const authoredEffectIDs = new Set(payload.chapters.flatMap((chapter) => [
    ...chapter.completionEffects.map(({ id }) => id),
    ...chapter.arcs.flatMap(({ beats }) => beats).flatMap((beat) =>
      (beat.interaction?.completionEffects ?? beat.completionEffects).map(({ id }) => id)),
  ]));
  for (const expected of experienceLab.scenes) {
    const chapter = payload.chapters.find(({ id }) => id === expected.contentID);
    const arc = chapter?.arcs.find(({ id }) => id === expected.arcID);
    const beat = arc?.beats.find(({ id }) => id === expected.beatID);
    const scene = payload.scenes.find(({ id }) => id === expected.labSceneID);
    if (!chapter || !arc || !beat || !scene) {
      issues.push(`${expected.labSceneID}: chapter, arc, beat and scene are required`);
      continue;
    }
    if (beat.sceneID !== expected.labSceneID
        || beat.interaction?.id !== expected.nativeInteractionID
        || beat.interaction?.grammar !== expected.grammar
        || beat.interaction?.completionEffects?.map(({ id }) => id).join(",")
          !== expected.worldEffectID) {
      issues.push(`${expected.labSceneID}: locked interaction projection drifted`);
    }
    if (scene.interactionVisualBinding?.grammar !== expected.grammar
        || scene.accessibilityID !== beat.interaction?.accessibilityID) {
      issues.push(`${expected.labSceneID}: visual/accessibility grammar drifted`);
    }
    for (const seedEffectID of expected.seedEffectIDs ?? []) {
      if (!authoredEffectIDs.has(seedEffectID)) {
        issues.push(`${expected.labSceneID}: seed effect ${seedEffectID} is unavailable`);
      }
    }
    grammarSet.add(expected.grammar);
  }
  if (payload.chapters.map(({ id }) => id).join(",")
      !== "first-farmers,europe-holds-the-line,european-world") {
    issues.push("experience lab requires the exact three free chapter slices");
  }
  if ([...grammarSet].sort().join(",") !== [...experienceLab.requiredGrammars].sort().join(",")) {
    issues.push("experience lab does not cover all five locked grammars");
  }
  const interactions = payload.chapters.flatMap(({ arcs }) => arcs)
    .flatMap(({ beats }) => beats)
    .flatMap(({ interaction }) => interaction ? [interaction] : []);
  if (interactions.length !== 5) issues.push("experience lab must contain exactly five interactions");
  if (issues.length) throw new Error(issues.join("\n"));
}

function buildPayload(source, documents, experienceLab) {
  const sourceChapter = source.chapters.find(({ id }) => id === "first-farmers");
  const sourceArc02 = sourceChapter?.arcs.find(({ id }) => id === "first-farmers-arc-02");
  const sourceArc03 = sourceChapter?.arcs.find(({ id }) => id === "first-farmers-arc-03");
  const harvestSourceBeat = sourceArc02?.beats.find(
    ({ id }) => id === "beat-first-farmers-harvest-allocation",
  );
  const harvestSourceScene = source.scenes.find(({ id }) => id === "harvest-allocation-option-1");
  if (!sourceChapter || !sourceArc02 || !sourceArc03 || !harvestSourceBeat || !harvestSourceScene) {
    throw new Error("First Farmers experience-lab source projection is incomplete");
  }

  const harvestBeat = structuredClone(harvestSourceBeat);
  const harvestSceneID = "lab-first-farmers-harvest-allocation";
  harvestBeat.sceneID = harvestSceneID;
  harvestBeat.narrationCueIDs = [];
  harvestBeat.interaction.accessibilityID = "accessibility-lab-first-farmers-harvest-allocation";
  const harvestScene = rewriteAuthoredSceneAssets(structuredClone(harvestSourceScene), harvestSceneID);
  harvestScene.accessibilityID = harvestBeat.interaction.accessibilityID;
  const harvestAccessibility = structuredClone(source.accessibility.find(
    ({ id }) => id === harvestSourceBeat.interaction.accessibilityID,
  ));
  if (!harvestAccessibility) throw new Error("Harvest accessibility source is missing");
  harvestAccessibility.id = harvestBeat.interaction.accessibilityID;

  const assemble = makeAssembleProjection(source);
  const transform = makeTransformProjection(source);
  const firstFarmers = structuredClone(sourceChapter);
  firstFarmers.arcs = [
    { ...structuredClone(sourceArc02), beats: [harvestBeat] },
    { ...structuredClone(sourceArc03), beats: [assemble.beat, transform.beat] },
  ];
  const chapterExitEffect = sourceChapter.arcs.flatMap(({ beats }) => beats)
    .find(({ id }) => id === "beat-first-farmers-three-records")
    ?.interaction?.completionEffects[0];
  if (!chapterExitEffect) throw new Error("First Farmers chapter exit effect is missing");
  firstFarmers.completionEffects = [structuredClone(chapterExitEffect)];

  const pressure = makePressureProjection(documents);
  const trace = makeTraceProjection(documents);
  const harvestParallaxProof = makeHarvestParallaxProof();
  const interactiveRecords = [
    { chapterID: "first-farmers", arcID: "first-farmers-arc-02", beat: harvestBeat, sceneID: harvestSceneID },
    { chapterID: "first-farmers", arcID: "first-farmers-arc-03", beat: assemble.beat, sceneID: assemble.scene.id },
    { chapterID: "first-farmers", arcID: "first-farmers-arc-03", beat: transform.beat, sceneID: transform.scene.id },
    { chapterID: "europe-holds-the-line", arcID: "europe-holds-the-line-arc-01", beat: pressure.beat, sceneID: pressure.scene.id },
    { chapterID: "european-world", arcID: "european-world-arc-01", beat: trace.beat, sceneID: trace.scene.id },
  ];
  const audio = interactiveRecords.map(({ chapterID, arcID, beat, sceneID }) =>
    makeResponsiveAudio(chapterID, arcID, beat, sceneID));
  const worldSeed = structuredClone(source.worldSeed);
  worldSeed.nodes.push(
    {
      id: "bristol-packet-office",
      kind: "institution",
      form: "A hidden packet office on the British shore",
      position: { x: 0.38, y: 0.48 },
      attributes: [],
    },
    {
      id: "new-york-packet-office",
      kind: "institution",
      form: "A hidden receiving office beyond the Atlantic",
      position: { x: 0.69, y: 0.48 },
      attributes: [],
    },
  );

  const payload = {
    schemaVersion: version,
    packageID: verticalSliceDevelopmentIdentity.packageID,
    worldSeed,
    chapters: [firstFarmers, pressure.chapter, trace.chapter],
    scenes: [
      harvestScene,
      assemble.scene,
      transform.scene,
      pressure.scene,
      trace.scene,
      harvestParallaxProof.scene,
    ],
    audioTimelines: audio.flatMap(({ timelines }) => timelines),
    responsiveAudioPrograms: audio.map(({ program }) => program),
    accessibility: [
      harvestAccessibility,
      assemble.accessibility,
      transform.accessibility,
      pressure.accessibility,
      trace.accessibility,
      harvestParallaxProof.accessibility,
    ],
  };
  validateExperienceLabCoverage(payload, experienceLab);
  if (localizedEnglish(firstFarmers.title) !== "The First Farmers"
      || localizedEnglish(firstFarmers.arcs[0].title) !== "The Harvest Had to Last"
      || localizedEnglish(pressure.chapter.title) !== "The Frontiers Hold"
      || localizedEnglish(trace.chapter.title) !== "The European World") {
    throw new Error("Experience-lab editorial contracts drifted before fixture projection");
  }
  return payload;
}

async function launchConfiguration() {
  const [product, catalog, delivery] = await Promise.all([
    readFile(path.join(nativeRoot, "product.json"), "utf8").then(JSON.parse),
    readFile(path.join(blueprintRoot, "chapter-catalog.json"), "utf8").then(JSON.parse),
    readFile(path.join(blueprintRoot, "delivery-plan.json"), "utf8").then(JSON.parse),
  ]);
  return { product, catalog, delivery };
}

async function main() {
  for (const target of [sourceRoot, path.dirname(packageRoot), backstageRoot]) {
    await rm(target, { recursive: true, force: true });
  }
  for (const target of [trustReceiptPath, lineagePath]) {
    await rm(target, { force: true });
  }
  await mkdir(path.join(sourceRoot, "chapters"), { recursive: true });
  await renderAssets();

  const [sourcePayload, blueprint, experienceLab] = await Promise.all([
    readFile(sourcePayloadPath, "utf8").then(JSON.parse),
    readBlueprintProjectionDocuments(blueprintRoot),
    readFile(experienceLabPath, "utf8").then(JSON.parse),
  ]);
  const payload = buildPayload(sourcePayload, blueprint, experienceLab);
  const payloadPath = path.join(
    sourceRoot,
    "chapters",
    "vertical-slice-development-v1.json",
  );
  const payloadBytes = Buffer.from(`${JSON.stringify(payload, null, 2)}\n`, "utf8");
  await writeFile(payloadPath, payloadBytes);

  const evidence = validateBlueprintProjection(payload, blueprint, {
    scope: "VERTICAL_SLICE",
    payloadBytes,
  });
  const authority = createDevelopmentProjectionAuthority(evidence);
  await writeJSON(authorityPath, authority);

  const result = await compileDevelopmentVerticalSlice(
    sourceRoot,
    packageRoot,
    {
      blueprintRoot,
      launchConfiguration: await launchConfiguration(),
      projectionAuthorityPath: authorityPath,
      packageVersion: version,
      minimumRuntime: version,
      maximumInstalledBytes: 750_000_000,
    },
  );
  await writeJSON(trustReceiptPath, result.trustReceipt);

  const compiledFiles = await Promise.all(result.manifest.files.map(async ({ path: file }) => {
    const fullPath = path.join(packageRoot, ...file.split("/"));
    const info = await stat(fullPath);
    return { path: file, bytes: info.size, sha256: sha256(await readFile(fullPath)) };
  }));
  await writeJSON(lineagePath, {
    schemaVersion: 1,
    status: "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_FIXTURE",
    authorityShape:
      "SINGLE_ATOMIC_FIVE_GRAMMAR_LAB_PACKAGE_WITH_UNREFERENCED_V26_PARTIAL_PASS_PROOF",
    chapterIDs: payload.chapters.map(({ id }) => id),
    labSceneIDs: experienceLab.scenes.map(({ labSceneID }) => labSceneID),
    interactionIDs: experienceLab.scenes.map(({ nativeInteractionID }) => nativeInteractionID),
    requiredGrammars: experienceLab.requiredGrammars,
    incrementalCostNOK: 0,
    trustDomain: verticalSliceDevelopmentIdentity.trustDomain,
    packageID: verticalSliceDevelopmentIdentity.packageID,
    keyID: verticalSliceDevelopmentIdentity.keyID,
    projectionAuthorityKind:
      verticalSliceDevelopmentIdentity.projectionAuthorityKind,
    projectionAuthorityStatus:
      verticalSliceDevelopmentIdentity.projectionAuthorityStatus,
    projectionAuthority: verticalSliceDevelopmentIdentity.projectionAuthority,
    shippingState: verticalSliceDevelopmentIdentity.shippingState,
    visualSources: await Promise.all(
      Object.entries(visualSources).map(async ([labSceneID, file]) => ({
        labSceneID,
        ...await fileRecord(file),
      })),
    ),
    visualSourceStatus: "CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_INPUT",
    runtimeVisualProof: {
      sceneID: harvestProofSceneID,
      status: "CODEX_PROVISIONAL_NON_SHIPPING_V26_PARTIAL_PASS_RUNTIME_PROOF",
      shippingState: "PROHIBITED",
      source: await fileRecord(harvestProofInputs.source),
      diagnosticUnderlay: await fileRecord(harvestProofInputs.diagnosticUnderlay),
      alphaMasksBackToFront: await Promise.all([
        ["people", harvestProofInputs.peopleAlpha],
        ["grain", harvestProofInputs.grainAlpha],
        ["foreground", harvestProofInputs.foregroundAlpha],
      ].map(async ([layerID, file]) => ({ layerID, ...await fileRecord(file) }))),
      reduceMotionStatic: await fileRecord(harvestProofInputs.reduceMotionStatic),
      frozenReview: await fileRecord(harvestProofInputs.review),
      segmentationReceipt: await fileRecord(harvestProofInputs.segmentationReceipt),
      packageAssetPaths: harvestProofAssetPaths,
      passedScope: ["people", "grain", "foreground"],
      excludedLayers: [
        "winter-food-vessel",
        "protected-reserve-bin",
        "spring-seed-store",
        "settlement-shelter",
        "allocation-cloth",
      ],
    },
    audioSource: await fileRecord(audioSource),
    audioRights: "PROJECT_OWNED_PROCEDURAL_AUDIO",
    audioDerivations: experienceLab.scenes.map(({ labSceneID }) => ({
      labSceneID,
      path: `source/audio/${labSceneID}-soundscape.m4a`,
    })),
    sourcePayload: await fileRecord(sourcePayloadPath),
    experienceLab: await fileRecord(experienceLabPath),
    payloadSHA256: sha256(payloadBytes),
    manifestDigest: result.manifest.manifestDigest,
    compiledFiles,
    claimsExcluded: [
      "editor approval",
      "shipping approval",
      "production visual approval",
      "production audio approval",
      "chapter completion",
      "physical-device approval",
      "clean-plate approval",
      "complete layer DAG",
      "state-variant approval",
      "production-master approval",
      "complete-scene approval",
      "artistic approval",
      "shipping asset approval",
    ],
  });

  process.stdout.write(
    `Built signed non-shipping runtime fixture ${result.manifest.manifestDigest}.\n`,
  );
}

main().catch((error) => {
  console.error(error?.stack ?? error);
  process.exitCode = 1;
});
