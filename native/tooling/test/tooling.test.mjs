import assert from "node:assert/strict";
import { createHash, generateKeyPairSync } from "node:crypto";
import {
  cp,
  mkdtemp,
  mkdir,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  compilePublicPackage,
  launchPackageApprovalDigest,
  launchPublicSourceInventoryDigest,
  manifestIntegrityMaterial,
  phase0EditorialDigest,
  publicKeyX963Base64,
  requireInstalledByteBudget,
  requireMatchingCollectionPackageSpec,
  requireResponsiveAudioDecodedBufferBudget,
  responsiveAudioDecodedBufferEstimate,
  saveMigrationDescriptorInventoryDigest,
  saveMigrationGraphDigest,
  validateShippingAssetProvenance,
  validateBlueprintApprovals,
  validateEditorApprovalRecord,
  validateLaunchPackageApprovalRecord,
  validatePackageManifest,
  verifyCompiledPackage,
  verifyPackageManifest,
} from "../src/compile.mjs";
import {
  validateAppleServiceConfiguration,
  validateIOSPlist,
} from "../src/ios-config.mjs";
import {
  collectShippingAssetReferences,
  listFiles,
  ValidationError,
  validateCollectionAgainstLaunchConfiguration,
  validateCollectionManifest,
  validateCostRegistry,
  validateLaunchAppShellSpec,
  validatePublicDocument,
  validatePublicTree,
  validateReleaseDocument,
  validateSceneSpec,
} from "../src/validate.mjs";

const version = (major = 1, minor = 0, patch = 0) => ({ major, minor, patch });
const localized = (id, launchEnglish) => ({ id, launchEnglish });

const sceneLayerAssetPaths = [
  "assets/landscape.heif",
  "assets/landscape-settled.heif",
  "assets/reduce-motion.heif",
  "assets/reduce-motion-foreground.heif",
];
const sceneMaskAssetPaths = [
  "assets/layer-alpha.png",
  "assets/layer-occlusion.png",
  "assets/layer-depth.png",
  "assets/layer-light.png",
  "assets/variant-alpha.png",
  "assets/variant-occlusion.png",
  "assets/variant-depth.png",
  "assets/variant-light.png",
];
const shippingAssetFixtures = [
  ...sceneLayerAssetPaths.map((assetPath) => ({ assetPath, role: "scene-layer" })),
  ...sceneMaskAssetPaths.map((assetPath) => ({ assetPath, role: "scene-mask" })),
  { assetPath: "audio/narration.m4a", role: "narration" },
];

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

const nativeRoot = fileURLToPath(new URL("../../", import.meta.url));
const phase0EditorialFileNames = [
  "arc-matrix.json",
  "authored-interaction-effects-01-12.json",
  "authored-interaction-effects-13-24.json",
  "chapter-catalog.json",
  "chapter-contracts.json",
  "interaction-mapping.json",
  "world-traces.json",
];

const zeroCostEntry = (id, category = "tool") => ({
  id,
  category,
  version: "test-v1",
  costModel: "free-local",
  incrementalCostNOK: 0,
  billingCredentialRequired: false,
  commercialUse: "allowed",
  license: "Project-owned test fixture",
  source: "Local test fixture",
});

const validCostRegistry = () => ({
  policyVersion: 1,
  entries: [
    zeroCostEntry("test-tool"),
    zeroCostEntry("native-image-layer-production", "image"),
    zeroCostEntry("final-narration-synthesis", "audio"),
  ],
  unresolvedCapabilities: [],
});

function revealSettlementEffect(id = "effect-settlement") {
  return {
    id,
    mutation: "reveal-node",
    node: {
      id: "aegean-settlement",
      kind: "settlement",
      form: "Timber houses beside stored grain",
      position: { x: 0.58, y: 0.52 },
      attributes: [{ key: "inhabited", value: true }],
    },
  };
}

function establishRouteEffect(id = "effect-route") {
  return {
    id,
    mutation: "establish-trace",
    trace: {
      id: "aegean-farming-route",
      kind: "seaRoute",
      origin: "western-anatolia",
      destination: "aegean-settlement",
      strength: 1,
    },
  };
}

function validInteraction(grammar = "trace") {
  const configuration = {
    trace: { anchors: [{ x: 0.1, y: 0.8 }, { x: 0.8, y: 0.2 }], tolerance: 0.1 },
    allocate: {
      resourceName: localized("interaction-allocate-resource-name", "Stored grain"),
      totalUnits: 4,
      destinations: [{ id: "seed", minimumUnits: 1 }, { id: "winter", minimumUnits: 1 }],
    },
    assemble: {
      components: [
        { id: "posts", targetSlot: "frame", prerequisites: [] },
        { id: "roof", targetSlot: "shelter", prerequisites: ["posts"] },
      ],
    },
    pressure: {
      forces: [
        { id: "flood", direction: -1, initialMagnitude: 0.4, userControllable: false },
        { id: "embankment", direction: 1, initialMagnitude: 0, userControllable: true },
      ],
      stableRange: [-0.1, 0.25],
      requiredHoldMillis: 1200,
    },
    transform: { stages: [{ id: "clear-ground", controlID: "field-edge", requiredAmount: 0.7 }] },
  }[grammar];
  return {
    id: `interaction-${grammar}`,
    prompt: localized(
      `interaction-${grammar}-prompt`,
      "Carry the household along the viable crossing.",
    ),
    grammar,
    configuration,
    completionEffects: [establishRouteEffect()],
    accessibilityID: "access-crossing",
  };
}

function validAccessibilityElements(interaction) {
  const action = (id, kind, label, token) => ({
    kind,
    label: localized(id, label),
    token,
  });
  if (interaction.grammar === "trace") {
    return [{
      id: "route-control",
      role: "adjustable",
      label: localized("access-route-control-label", "Aegean crossing"),
      value: localized("access-route-control-value", "At the Anatolian shore"),
      hint: localized("access-route-control-hint", "Advance the household toward Europe."),
      actions: [action("access-route-control-advance", "increment", "Advance west", { command: "trace-next" })],
    }];
  }
  if (interaction.grammar === "allocate") {
    return interaction.configuration.destinations.map((destination) => ({
      id: `allocate-${destination.id}`,
      role: "adjustable",
      label: localized(`access-allocate-${destination.id}-label`, `Stores for ${destination.id}`),
      actions: [
        action(`access-allocate-${destination.id}-increase`, "increment", `Increase ${destination.id}`, {
          command: "allocate", targetID: destination.id, unitsPerStep: 1,
        }),
        action(`access-allocate-${destination.id}-decrease`, "decrement", `Decrease ${destination.id}`, {
          command: "allocate", targetID: destination.id, unitsPerStep: 1,
        }),
      ],
    })).concat({
      id: "commit-allocation",
      role: "action",
      label: localized("access-commit-allocation-label", "Test the stores against winter"),
      actions: [action("access-commit-allocation-action", "activate", "Commit the stores", { command: "commit-allocation" })],
    });
  }
  if (interaction.grammar === "assemble") {
    return interaction.configuration.components.map((component) => ({
      id: `place-${component.id}`,
      role: "action",
      label: localized(`access-place-${component.id}-label`, `Place ${component.id}`),
      actions: [action(`access-place-${component.id}-action`, "activate", `Place ${component.id}`, {
        command: "place-component", targetID: component.id,
      })],
    }));
  }
  if (interaction.grammar === "pressure") {
    return interaction.configuration.forces.filter((force) => force.userControllable).map((force) => ({
      id: `pressure-${force.id}`,
      role: "adjustable",
      label: localized(`access-pressure-${force.id}-label`, `Set ${force.id}`),
      actions: [
        action(`access-pressure-${force.id}-increase`, "increment", `Increase ${force.id}`, {
          command: "adjust-pressure", targetID: force.id, step: 0.1,
        }),
        action(`access-pressure-${force.id}-decrease`, "decrement", `Decrease ${force.id}`, {
          command: "adjust-pressure", targetID: force.id, step: 0.1,
        }),
      ],
    })).concat({
      id: "hold-pressure",
      role: "action",
      label: localized("access-hold-pressure-label", "Hold the line"),
      actions: [action("access-hold-pressure-action", "activate", "Hold the line", { command: "hold-pressure" })],
    });
  }
  return interaction.configuration.stages.map((stage) => ({
    id: `transform-${stage.id}`,
    role: "adjustable",
    label: localized(`access-transform-${stage.id}-label`, `Advance ${stage.id}`),
    actions: [action(`access-transform-${stage.id}-continue`, "increment", `Continue ${stage.id}`, {
      command: "advance-transform", targetID: stage.id, step: 0.1,
    })],
  }));
}

function bindResponsiveAudioPrograms(payload) {
  const previousTimelineIDs = new Set(
    (payload.responsiveAudioPrograms ?? []).flatMap((program) => [
      program.approachTimelineID,
      ...(program.interactionBeds ?? []).map((bed) => bed.timelineID),
      program.consequenceTimelineID,
    ]),
  );
  payload.audioTimelines = (payload.audioTimelines ?? [])
    .filter((timeline) => !previousTimelineIDs.has(timeline.id));
  payload.responsiveAudioPrograms = [];
  for (const chapter of payload.chapters) {
    for (const arc of chapter.arcs) {
      for (const beat of arc.beats) {
        if (!beat.interaction) continue;
        const timeline = (region, durationSamples) => ({
          id: `responsive-${beat.id}-${region}`,
          sampleRate: 48000,
          events: [{
            cueID: `cue-responsive-${beat.id}-${region}`,
            role: "silence",
            startSample: 0,
            durationSamples,
            gain: 1,
          }],
          haptics: [],
        });
        const approach = timeline("approach", 96000);
        const waiting = timeline("waiting", 48000);
        const engaged = timeline("engaged", 48000);
        const resistance = timeline("resistance", 48000);
        const consequence = timeline("consequence", 96000);
        payload.audioTimelines.push(approach, waiting, engaged, resistance, consequence);
        payload.responsiveAudioPrograms.push({
          id: `program-${beat.interaction.id}`,
          scope: {
            chapterID: chapter.id,
            arcID: arc.id,
            beatID: beat.id,
            interactionID: beat.interaction.id,
          },
          approachTimelineID: approach.id,
          interactionBeds: [
            { phase: "waiting", timelineID: waiting.id, layerStates: {} },
            { phase: "engaged", timelineID: engaged.id, layerStates: {} },
            { phase: "resistance", timelineID: resistance.id, layerStates: {} },
          ],
          consequenceTimelineID: consequence.id,
          exitPolicy: {
            kind: "bounded-fade",
            durationSamples: 9_600,
          },
        });
      }
    }
  }
  return payload;
}

function bindValidCausalMix(payload) {
  const program = payload.responsiveAudioPrograms[0];
  const sharedLayers = [
    {
      id: "river-current",
      assetPath: "audio/responsive/shared/river-current.wav",
      role: "soundscape",
      initialGain: 0.8,
    },
    {
      id: "household-work",
      assetPath: "audio/responsive/shared/household-work.wav",
      role: "spatialDetail",
      initialGain: 0,
    },
  ];
  for (const bed of program.interactionBeds) {
    const timeline = payload.audioTimelines.find(({ id }) => id === bed.timelineID);
    timeline.events = [
      {
        cueID: `causal-${bed.phase}-score`,
        role: "score",
        startSample: 0,
        durationSamples: 48_000,
        assetPath: `audio/responsive/${bed.phase}-score.wav`,
        gain: 0.5,
      },
      ...sharedLayers.map((layer) => ({
        cueID: `causal-${bed.phase}-${layer.id}`,
        role: layer.role,
        startSample: 0,
        durationSamples: 48_000,
        assetPath: layer.assetPath,
        gain: layer.initialGain,
      })),
    ];
    bed.layerStates = {
      scoreStateID: `${bed.phase}-score-state`,
      soundscapeStateID: `${bed.phase}-world-state`,
    };
  }
  program.causalMix = {
    rampDurationSamples: 9_600,
    layers: sharedLayers.map((layer) => ({
      id: layer.id,
      assetPath: layer.assetPath,
      cueIDs: Object.fromEntries(program.interactionBeds.map((bed) => [
        bed.phase,
        `causal-${bed.phase}-${layer.id}`,
      ])),
    })),
    states: [
      {
        completedStageCount: 0,
        layerGains: [
          { layerID: "river-current", gain: 0.8 },
          { layerID: "household-work", gain: 0 },
        ],
      },
      {
        completedStageCount: 1,
        layerGains: [
          { layerID: "river-current", gain: 0.8 },
          { layerID: "household-work", gain: 0.55 },
        ],
      },
    ],
  };
  return payload;
}

function validContentPackage(grammar = "allocate") {
  const interaction = validInteraction(grammar);
  const accessibilityElements = validAccessibilityElements(interaction);
  const interactionTargetID = {
    trace: "route-control",
    allocate: "seed",
    assemble: "posts",
    pressure: "embankment",
    transform: "clear-ground",
  }[grammar];
  const payload = {
    schemaVersion: version(),
    packageID: "essential-free-v1",
    worldSeed: {
      nodes: [
        {
          id: "western-anatolia",
          kind: "settlement",
          form: "Hidden western Anatolian shore",
          position: { x: 0.72, y: 0.48 },
          attributes: [],
        },
        {
          id: "aegean-settlement",
          kind: "settlement",
          form: "Hidden Aegean shore",
          position: { x: 0.58, y: 0.52 },
          attributes: [],
        },
      ],
      traces: [establishRouteEffect().trace],
    },
    chapters: [{
      schemaVersion: version(),
      id: "first-farmers",
      title: localized("chapter-first-farmers-title", "The First Farmers"),
      period: localized("chapter-first-farmers-period", "7000–3300 BC"),
      arcs: [{
        id: "river-to-field",
        title: localized("arc-river-to-field-title", "River to Field"),
        targetDurationMinutes: 10,
        situation: localized("arc-river-to-field-situation", "Farming households reach the Aegean shore."),
        mechanism: localized("arc-river-to-field-mechanism", "Seed, animals and learned routines move with people."),
        turn: localized("arc-river-to-field-turn", "A harvest must outlast the season."),
        consequence: localized("arc-river-to-field-consequence", "Fields and permanent houses remake the landscape."),
        handoff: localized("arc-river-to-field-handoff", "Settled stores become the inheritance the steppe can seize."),
        beats: [{
          id: "cross-the-water",
          sceneID: "aegean-crossing",
          narrative: {
            heading: localized("beat-cross-water-heading", "The crossing carries a complete way of life"),
            paragraphs: [localized(
              "beat-cross-water-paragraph-one",
              "Households carried seed, livestock and farming knowledge across the water.",
            )],
            actionPrompt: localized("beat-cross-water-action", "Find the crossing."),
          },
          narrationCueIDs: ["narration-crossing"],
          interaction,
          completionEffects: [],
          checkpoint: "afterInteraction",
        }],
      }],
      completionEffects: [revealSettlementEffect()],
    }],
    scenes: [{
      id: "aegean-crossing",
      sceneCanvas: {
        canvas: { width: 1200, height: 2600 },
        cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
        authoredOverscanFraction: 0.15,
        viewportCrops: [baselineCrop()],
      },
      layers: [{
        id: "landscape",
        order: 0,
        assetPath: "assets/landscape.heif",
        frame: { x: 0, y: 0, width: 1, height: 1 },
        depth: 0.2,
        opacity: 1,
        blendMode: "normal",
        masks: {
          alphaMaskAssetPath: "assets/layer-alpha.png",
          occlusionMaskAssetPath: "assets/layer-occlusion.png",
          depthMaskAssetPath: "assets/layer-depth.png",
          lightMaskAssetPath: "assets/layer-light.png",
        },
        motion: { parallaxFactor: 0.1, windResponse: 0, focusResponse: 0.1 },
        stateVariants: [{
          id: "settled",
          assetPath: "assets/landscape-settled.heif",
          masks: {
            alphaMaskAssetPath: "assets/variant-alpha.png",
            occlusionMaskAssetPath: "assets/variant-occlusion.png",
            depthMaskAssetPath: "assets/variant-depth.png",
            lightMaskAssetPath: "assets/variant-light.png",
          },
        }],
      }],
      cameraRail: {
        keyframes: [
          { progress: 0, center: { x: 0.45, y: 0.5 }, scale: 1 },
          { progress: 1, center: { x: 0.55, y: 0.45 }, scale: 1.08 },
        ],
      },
      atmosphere: [{
        kind: "mist",
        density: 0.2,
        velocity: { dx: -0.1, dy: 0 },
        deterministicSeed: 42,
      }],
      interactionTargets: [{
        interactionTargetID,
        layerID: "landscape",
        hitRegion: {
          path: [{ x: 0.25, y: 0.65 }, { x: 0.75, y: 0.55 }, { x: 0.65, y: 0.82 }],
        },
        accessibilityElementID: accessibilityElements[0].id,
      }],
      reduceMotionComposition: {
        canvas: { width: 1200, height: 2600 },
        strata: [
          { id: "static-underlay", kind: "staticPlate", assetPath: "assets/reduce-motion.heif" },
          { id: "landscape-state", kind: "stateOverlay", layerID: "landscape" },
          { id: "static-foreground", kind: "staticPlate", assetPath: "assets/reduce-motion-foreground.heif" },
        ],
        viewportCrops: [baselineCrop()],
      },
      mechanismFocus: localized("scene-aegean-crossing-mechanism", "The shortest viable crossing"),
      accessibilityID: "access-crossing",
    }],
    audioTimelines: [{
      id: "audio-crossing",
      sampleRate: 48000,
      events: [{
        cueID: "narration-crossing",
        role: "narration",
        startSample: 0,
        durationSamples: 96000,
        assetPath: "audio/narration.m4a",
        gain: 1,
        narrationBinding: {
          manuscriptSegmentID: "beat-cross-water-paragraph-one",
          manuscriptSegmentSHA256: createHash("sha256")
            .update("Households carried seed, livestock and farming knowledge across the water.", "utf8")
            .digest("hex"),
          scope: {
            chapterID: "first-farmers",
            arcID: "river-to-field",
            beatID: "cross-the-water",
          },
        },
      }],
      haptics: [{ sample: 48000, kind: "seal", intensity: 0.4, sharpness: 0.3 }],
    }],
    accessibility: [{
      id: "access-crossing",
      sceneSummary: localized(
        "access-crossing-summary",
        "A household crosses dark water with seed and livestock.",
      ),
      elements: accessibilityElements,
    }],
  };
  if (grammar === "allocate") applyCanonicalAllocateVisualBinding(payload);
  return bindResponsiveAudioPrograms(payload);
}

function canonicalVisualLayer(id, order, variantIDs = []) {
  return {
    id,
    order,
    assetPath: "assets/landscape.heif",
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth: (order + 1) / 10,
    opacity: 1,
    blendMode: "normal",
    masks: {
      alphaMaskAssetPath: "assets/layer-alpha.png",
      occlusionMaskAssetPath: "assets/layer-occlusion.png",
      depthMaskAssetPath: "assets/layer-depth.png",
      lightMaskAssetPath: "assets/layer-light.png",
    },
    motion: { parallaxFactor: 0, windResponse: 0, focusResponse: 0 },
    stateVariants: variantIDs.map((variantID) => ({
      id: variantID,
      assetPath: "assets/landscape-settled.heif",
      masks: {
        alphaMaskAssetPath: "assets/variant-alpha.png",
        occlusionMaskAssetPath: "assets/variant-occlusion.png",
        depthMaskAssetPath: "assets/variant-depth.png",
        lightMaskAssetPath: "assets/variant-light.png",
      },
    })),
  };
}

function canonicalAllocateTarget(interactionTargetID, layerID, accessibilityElementID, minimumX, maximumX) {
  return {
    interactionTargetID,
    layerID,
    hitRegion: {
      path: [
        { x: minimumX, y: 0.52 },
        { x: maximumX, y: 0.52 },
        { x: maximumX, y: 0.72 },
        { x: minimumX, y: 0.72 },
      ],
    },
    accessibilityElementID,
  };
}

function rectangularHitRegion(minimumX, maximumX, minimumY, maximumY) {
  return {
    path: [
      { x: minimumX, y: minimumY },
      { x: maximumX, y: minimumY },
      { x: maximumX, y: maximumY },
      { x: minimumX, y: maximumY },
    ],
  };
}

function applyCanonicalAllocateVisualBinding(payload) {
  const scene = payload.scenes[0];
  scene.layers = [
    canonicalVisualLayer("harvest", 0, ["exhausted", "full"]),
    canonicalVisualLayer("grain-transfer", 1),
    canonicalVisualLayer("seed-store", 2, ["empty", "receiving", "committed"]),
    canonicalVisualLayer("winter-store", 3, ["empty", "receiving", "provisioned"]),
  ];
  scene.interactionTargets = [
    canonicalAllocateTarget("seed-target", "seed-store", "allocate-seed", 0.22, 0.42),
    canonicalAllocateTarget("winter-target", "winter-store", "allocate-winter", 0.58, 0.78),
  ];
  scene.interactionVisualBinding = {
    grammar: "allocate",
    configuration: {
      interactionID: "interaction-allocate",
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
      destinations: [
        {
          destinationID: "seed",
          interactionTargetID: "seed-target",
          layerID: "seed-store",
          emptyVariantID: "empty",
          receivingVariantID: "receiving",
          completedVariantID: "committed",
          transferPath: [{ x: 0.5, y: 0.78 }, { x: 0.32, y: 0.62 }],
        },
        {
          destinationID: "winter",
          interactionTargetID: "winter-target",
          layerID: "winter-store",
          emptyVariantID: "empty",
          receivingVariantID: "receiving",
          completedVariantID: "provisioned",
          transferPath: [{ x: 0.5, y: 0.78 }, { x: 0.68, y: 0.62 }],
        },
      ],
    },
  };
  scene.reduceMotionComposition.strata = [
    { id: "static-underlay", kind: "staticPlate", assetPath: "assets/reduce-motion.heif" },
    { id: "harvest-state", kind: "stateOverlay", layerID: "harvest" },
    { id: "seed-store-state", kind: "stateOverlay", layerID: "seed-store" },
    { id: "winter-store-state", kind: "stateOverlay", layerID: "winter-store" },
    { id: "static-foreground", kind: "staticPlate", assetPath: "assets/reduce-motion-foreground.heif" },
  ];
}

function setLaboratoryVisualLayers(scene, layers) {
  scene.layers = layers;
  scene.reduceMotionComposition.strata = [
    { id: "static-underlay", kind: "staticPlate", assetPath: "assets/reduce-motion.heif" },
    ...layers
      .filter((layer) => layer.stateVariants.length > 0)
      .map((layer) => ({
        id: `${layer.id}-state`,
        kind: "stateOverlay",
        layerID: layer.id,
      })),
    { id: "static-foreground", kind: "staticPlate", assetPath: "assets/reduce-motion-foreground.heif" },
  ];
}

function validLaboratoryVisualScene(grammar) {
  if (grammar === "allocate") return validContentPackage("allocate").scenes[0];
  const scene = structuredClone(validContentPackage(grammar).scenes[0]);

  if (grammar === "trace") {
    setLaboratoryVisualLayers(scene, [
      canonicalVisualLayer("road", 0, ["idle", "tracing", "completed"]),
    ]);
    scene.interactionTargets[0].layerID = "road";
    scene.interactionVisualBinding = {
      grammar,
      configuration: {
        interactionID: "interaction-trace",
        interactionTargetID: "route-control",
        layerID: "road",
        idleVariantID: "idle",
        tracingVariantID: "tracing",
        completedVariantID: "completed",
      },
    };
  } else if (grammar === "assemble") {
    setLaboratoryVisualLayers(scene, [
      canonicalVisualLayer("posts", 0, ["available", "resisted", "placed"]),
      canonicalVisualLayer("roof", 1, ["available", "resisted", "placed"]),
    ]);
    scene.interactionTargets = [
      {
        interactionTargetID: "posts-source",
        layerID: "posts",
        hitRegion: rectangularHitRegion(0.22, 0.42, 0.34, 0.48),
        accessibilityElementID: "place-posts",
      },
      {
        interactionTargetID: "posts-slot",
        layerID: "posts",
        hitRegion: rectangularHitRegion(0.22, 0.42, 0.62, 0.76),
        accessibilityElementID: "place-posts",
      },
      {
        interactionTargetID: "roof-source",
        layerID: "roof",
        hitRegion: rectangularHitRegion(0.58, 0.78, 0.34, 0.48),
        accessibilityElementID: "place-roof",
      },
      {
        interactionTargetID: "roof-slot",
        layerID: "roof",
        hitRegion: rectangularHitRegion(0.58, 0.78, 0.62, 0.76),
        accessibilityElementID: "place-roof",
      },
    ];
    scene.interactionVisualBinding = {
      grammar,
      configuration: {
        interactionID: "interaction-assemble",
        components: [
          {
            componentID: "posts",
            sourceInteractionTargetID: "posts-source",
            slotInteractionTargetID: "posts-slot",
            layerID: "posts",
            availableVariantID: "available",
            resistedVariantID: "resisted",
            placedVariantID: "placed",
          },
          {
            componentID: "roof",
            sourceInteractionTargetID: "roof-source",
            slotInteractionTargetID: "roof-slot",
            layerID: "roof",
            availableVariantID: "available",
            resistedVariantID: "resisted",
            placedVariantID: "placed",
          },
        ],
      },
    };
  } else if (grammar === "pressure") {
    setLaboratoryVisualLayers(scene, [
      canonicalVisualLayer("flood-force", 0),
      canonicalVisualLayer("embankment-force", 1),
      canonicalVisualLayer(
        "frontier-system",
        2,
        ["resting", "resisting", "stable", "broken"],
      ),
    ]);
    scene.interactionTargets[0].layerID = "embankment-force";
    scene.interactionVisualBinding = {
      grammar,
      configuration: {
        interactionID: "interaction-pressure",
        forces: [
          { forceID: "flood", layerID: "flood-force" },
          {
            forceID: "embankment",
            layerID: "embankment-force",
            interactionTargetID: "embankment",
          },
        ],
        systemLayerID: "frontier-system",
        restingVariantID: "resting",
        resistingVariantID: "resisting",
        stableVariantID: "stable",
        brokenVariantID: "broken",
      },
    };
  } else {
    setLaboratoryVisualLayers(scene, [
      canonicalVisualLayer("field", 0, ["before", "active", "completed"]),
    ]);
    scene.interactionTargets[0].layerID = "field";
    scene.interactionVisualBinding = {
      grammar,
      configuration: {
        interactionID: "interaction-transform",
        stages: [{
          stageID: "clear-ground",
          interactionTargetID: "clear-ground",
          layerID: "field",
          beforeVariantID: "before",
          activeVariantID: "active",
          completedVariantID: "completed",
        }],
      },
    };
  }
  return scene;
}

function validShippingVisualPackage(grammar) {
  const payload = validContentPackage(grammar);
  if (grammar !== "allocate") payload.scenes[0] = validLaboratoryVisualScene(grammar);
  return payload;
}

function validAllocateVisualPackage() {
  const payload = validContentPackage("allocate");
  return payload;
}

function validCollection() {
  const free = new Set(["first-farmers", "europe-holds-the-line", "european-world"]);
  const chapterIDs = ["first-farmers", ...Array.from({ length: 11 }, (_, index) => `chapter-${String(index + 2).padStart(2, "0")}`),
    "europe-holds-the-line", ...Array.from({ length: 7 }, (_, index) => `chapter-${String(index + 14).padStart(2, "0")}`),
    "european-world", ...Array.from({ length: 3 }, (_, index) => `chapter-${index + 22}`)];
  const paid = chapterIDs.filter((id) => !free.has(id));
  const groups = Array.from({ length: 7 }, (_, index) => paid.slice(index * 3, index * 3 + 3));
  const packageFor = new Map([["first-farmers", "essential-free-v1"], ["europe-holds-the-line", "essential-free-v1"], ["european-world", "essential-free-v1"]]);
  groups.forEach((group, index) => group.forEach((id) => packageFor.set(id, `paid-wave-${index + 1}`)));
  return {
    schemaVersion: version(),
    collectionID: "journey-collection-v1",
    locale: { identifier: "en" },
    product: { franchiseName: "The Long West", workTitle: "EUROCENTRIC" },
    chapters: chapterIDs.map((id, index) => ({
      id,
      sequence: index + 1,
      title: localized(`collection-chapter-${index + 1}-title`, `Chapter ${index + 1}`),
      period: localized(`collection-chapter-${index + 1}-period`, `Period ${index + 1}`),
      packageID: packageFor.get(id),
      access: free.has(id) ? { kind: "included" } : { kind: "entitlement", entitlementID: "launch-complete-work" },
    })),
    packages: [{
      id: "essential-free-v1",
      version: version(),
      chapterIDs: [...free],
      maximumInstalledBytes: 750_000_000,
      minimumRuntime: version(),
      isEssentialInstall: true,
    }, ...groups.map((chapterGroup, index) => ({
      id: `paid-wave-${index + 1}`,
      version: version(),
      chapterIDs: chapterGroup,
      maximumInstalledBytes: 750_000_000,
      minimumRuntime: version(),
      isEssentialInstall: false,
    }))],
    entitlements: [{ id: "launch-complete-work", storeProductID: "com.thelongwest.complete", kind: "nonConsumable" }],
  };
}

function validRelease() {
  return {
    id: "release-first-farmers-v1",
    contentID: "first-farmers",
    packageID: "essential-free-v1",
    version: version(),
    chapterIDs: ["first-farmers"],
    maximumInstalledBytes: 750_000_000,
    publishedAtUnixMillis: 1_800_000_000_000,
    minimumRuntime: version(),
  };
}

function validAppShell(locale = { identifier: "en" }) {
  const chapterIDs = [...validCollection().chapters]
    .sort((left, right) => left.sequence - right.sequence)
    .map((chapter) => chapter.id);
  return {
    schemaVersion: version(),
    id: "launch-app-shell",
    locale,
    prologue: {
      id: "wake-long-road",
      sceneID: "long-road-prologue",
      narrative: {
        heading: localized("prologue-heading", "The road is waiting"),
        paragraphs: [localized(
          "prologue-paragraph-one",
          "Draw the first movement west across the dark water.",
        )],
        actionPrompt: localized("prologue-action", "Wake the road."),
      },
      interaction: {
        ...validInteraction("trace"),
        id: "wake-long-road",
        prompt: localized("prologue-trace-prompt", "Trace the first crossing"),
        accessibilityID: "wake-long-road-accessibility",
      },
      checkpoint: "afterInteraction",
    },
    livingWorld: {
      id: "cumulative-europe",
      sceneID: "living-world",
      accessibilityID: "living-world-accessibility",
      currentPlaceLayerID: "current-place",
      nextPressureLayerID: "next-pressure",
      chapters: chapterIDs.map((chapterID, index) => ({
        chapterID,
        worldNodeID: `living-world-node-${index + 1}`,
        position: {
          x: 0.15 + (index % 6) * 0.13,
          y: 0.12 + Math.floor(index / 6) * 0.24,
        },
        historicalInvitation: localized(
          `living-world-${chapterID}-invitation`,
          `Enter chapter ${index + 1}`,
        ),
      })),
      traces: [{ worldTraceID: "long-road", layerID: "long-road-layer" }],
    },
  };
}

async function createPublicSource() {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-tooling-"));
  const source = path.join(temporary, "public");
  await mkdir(path.join(source, "chapters"), { recursive: true });
  await mkdir(path.join(source, "assets"), { recursive: true });
  await mkdir(path.join(source, "audio"), { recursive: true });
  await writeFile(path.join(source, "chapters", "essential-free-v1.json"), `${JSON.stringify(validContentPackage(), null, 2)}\n`);
  for (const { assetPath } of shippingAssetFixtures) {
    await writeFile(path.join(source, assetPath), Buffer.from(`fixture:${assetPath}`));
  }
  return { temporary, source };
}

async function createSaveMigrationDescriptor(
  temporary,
  relativePath = "save-migrations/save-zero-to-one.json",
  bytes = Buffer.from("{\"migration\":\"save-zero-to-one\",\"version\":1}\n", "utf8"),
) {
  const descriptorRoot = path.join(temporary, "backstage", "save-migration-descriptors");
  const descriptorPath = path.join(descriptorRoot, ...relativePath.split("/"));
  await mkdir(path.dirname(descriptorPath), { recursive: true });
  await writeFile(descriptorPath, bytes);
  return {
    descriptorRoot,
    descriptorPath,
    relativePath,
    bytes,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };
}

async function readJSON(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

async function writeJSON(file, value) {
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

async function approveTemporaryBlueprint(realBlueprintRoot, temporaryRoot) {
  const blueprintRoot = path.join(temporaryRoot, "blueprint");
  await cp(realBlueprintRoot, blueprintRoot, { recursive: true });

  const catalog = await readJSON(path.join(blueprintRoot, "chapter-catalog.json"));
  catalog.status = "CANONICAL_PHASE_0_APPROVED";
  catalog.chapters.forEach((chapter) => {
    chapter.thesisStatus = "LOCKED_NATIVE_CONTRACT_APPROVED";
  });
  await writeJSON(path.join(blueprintRoot, "chapter-catalog.json"), catalog);

  const contracts = await readJSON(path.join(blueprintRoot, "chapter-contracts.json"));
  contracts.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  contracts.contracts.forEach((contract) => {
    contract.editorApproval = "APPROVED";
  });
  await writeJSON(path.join(blueprintRoot, "chapter-contracts.json"), contracts);

  const arcs = await readJSON(path.join(blueprintRoot, "arc-matrix.json"));
  arcs.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  arcs.chapters.forEach((chapter) => {
    chapter.editorApproval = "APPROVED";
  });
  await writeJSON(path.join(blueprintRoot, "arc-matrix.json"), arcs);

  for (const fileName of ["interaction-mapping.json", "world-traces.json"]) {
    const document = await readJSON(path.join(blueprintRoot, fileName));
    document.status = "APPROVED_BY_EDITOR_IN_CHIEF";
    await writeJSON(path.join(blueprintRoot, fileName), document);
  }

  for (const fileName of [
    "authored-interaction-effects-01-12.json",
    "authored-interaction-effects-13-24.json",
  ]) {
    const ledger = await readJSON(path.join(blueprintRoot, fileName));
    ledger.status = "AUTHORED_APPROVED_BY_EDITOR_IN_CHIEF";
    await writeJSON(path.join(blueprintRoot, fileName), ledger);
  }

  const editorialBytes = Object.fromEntries(await Promise.all(
    phase0EditorialFileNames.map(async (fileName) => [
      fileName,
      await readFile(path.join(blueprintRoot, fileName)),
    ]),
  ));
  const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
  const approvalPath = path.join(blueprintRoot, "editor-approval.json");
  const approval = await readJSON(approvalPath);
  Object.assign(approval, {
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T19:00:00Z",
    decisionReference: "tooling-production-launch-fixture",
    chapterContractsSHA256: digest(editorialBytes["chapter-contracts.json"]),
    arcMatrixSHA256: digest(editorialBytes["arc-matrix.json"]),
    phase0EditorialSHA256: phase0EditorialDigest(editorialBytes),
  });
  await writeJSON(approvalPath, approval);
  return { blueprintRoot, catalog, approval, editorialBytes };
}

function canonicalLaunchCollection(product, catalog, delivery) {
  const packageForChapter = new Map(delivery.packages.flatMap((packageSpec) =>
    packageSpec.chapterIDs.map((chapterID) => [chapterID, packageSpec.packageID])));
  const maximumContentBytes = delivery.budgets.completeInstalledWorkBytes
    - delivery.budgets.shellAndEngineBytes;
  const packageBudgets = delivery.packages.map((packageSpec) => packageSpec.maximumInstalledBytes);
  const declaredBytes = packageBudgets.reduce((sum, bytes) => sum + bytes, 0);
  packageBudgets[packageBudgets.length - 1] -= declaredBytes - maximumContentBytes;
  const freeIDs = new Set(catalog.freeContentIDs);

  return {
    schemaVersion: version(),
    collectionID: catalog.collectionID,
    locale: { identifier: product.launchLanguage },
    product: {
      franchiseName: product.franchiseName,
      workTitle: product.workTitle,
    },
    chapters: [...catalog.chapters]
      .sort((left, right) => left.ordinal - right.ordinal)
      .map((chapter) => ({
        id: chapter.contentID,
        sequence: chapter.ordinal,
        title: localized(`collection-${chapter.contentID}-title`, chapter.title),
        period: localized(`collection-${chapter.contentID}-period`, chapter.period),
        packageID: packageForChapter.get(chapter.contentID),
        access: freeIDs.has(chapter.contentID)
          ? { kind: "included" }
          : { kind: "entitlement", entitlementID: delivery.entitlement.entitlementID },
      })),
    packages: delivery.packages.map((packageSpec, index) => ({
      id: packageSpec.packageID,
      version: version(),
      chapterIDs: [...packageSpec.chapterIDs],
      maximumInstalledBytes: packageBudgets[index],
      minimumRuntime: version(),
      isEssentialInstall: packageSpec.isEssentialInstall,
    })),
    entitlements: [{
      id: delivery.entitlement.entitlementID,
      storeProductID: delivery.entitlement.storeProductID,
      kind: "nonConsumable",
    }],
  };
}

function validEssentialLaunchContentPackage(catalog, delivery) {
  const payload = validContentPackage();
  const chapterTemplate = payload.chapters[0];
  const sceneTemplate = payload.scenes[0];
  const accessibilityTemplate = payload.accessibility[0];
  const essential = delivery.packages.find((packageSpec) => packageSpec.isEssentialInstall);
  const catalogByID = new Map(catalog.chapters.map((chapter) => [chapter.contentID, chapter]));

  payload.chapters = essential.chapterIDs.map((chapterID) => {
    const chapter = structuredClone(chapterTemplate);
    const metadata = catalogByID.get(chapterID);
    const arc = chapter.arcs[0];
    const beat = arc.beats[0];
    chapter.id = chapterID;
    chapter.title = localized(`chapter-${chapterID}-title`, metadata.title);
    chapter.period = localized(`chapter-${chapterID}-period`, metadata.period);
    arc.id = `${chapterID}-arc`;
    beat.id = `${chapterID}-beat`;
    beat.narrationCueIDs = [`narration-${chapterID}`];
    beat.interaction.id = `interaction-${chapterID}`;
    beat.interaction.accessibilityID = `access-${chapterID}`;
    beat.interaction.completionEffects[0].id = `effect-${chapterID}-route`;
    chapter.completionEffects[0].id = `effect-${chapterID}-settlement`;
    return chapter;
  });
  payload.accessibility = payload.chapters.map((chapter) => {
    const specification = structuredClone(accessibilityTemplate);
    const interaction = chapter.arcs[0].beats[0].interaction;
    specification.id = interaction.accessibilityID;
    specification.elements = validAccessibilityElements(interaction);
    return specification;
  });
  payload.scenes = payload.chapters.map((chapter) => {
    const scene = structuredClone(sceneTemplate);
    const beat = chapter.arcs[0].beats[0];
    scene.id = `${chapter.id}-scene`;
    scene.accessibilityID = beat.interaction.accessibilityID;
    scene.interactionVisualBinding.configuration.interactionID = beat.interaction.id;
    scene.sceneCanvas.viewportCrops = [baselineCrop(), largestCrop()];
    scene.reduceMotionComposition.viewportCrops = [baselineCrop(), largestCrop()];
    beat.sceneID = scene.id;
    return scene;
  });
  const audioTemplate = payload.audioTimelines[0];
  payload.audioTimelines = payload.chapters.map((chapter) => {
    const timeline = structuredClone(audioTemplate);
    const beat = chapter.arcs[0].beats[0];
    timeline.id = `audio-${chapter.id}`;
    timeline.events[0].cueID = beat.narrationCueIDs[0];
    timeline.events[0].narrationBinding.scope = {
      chapterID: chapter.id,
      arcID: chapter.arcs[0].id,
      beatID: beat.id,
    };
    return timeline;
  });
  return bindResponsiveAudioPrograms(payload);
}

async function createCanonicalLaunchSource(temporaryRoot, product, catalog, delivery) {
  const source = path.join(temporaryRoot, "public");
  await mkdir(path.join(source, "chapters"), { recursive: true });
  await mkdir(path.join(source, "assets"), { recursive: true });
  await mkdir(path.join(source, "audio"), { recursive: true });
  const collection = canonicalLaunchCollection(product, catalog, delivery);
  const payload = validEssentialLaunchContentPackage(catalog, delivery);
  await writeJSON(path.join(source, "collection.json"), collection);
  await writeJSON(path.join(source, "chapters", "essential-free-v1.json"), payload);
  for (const { assetPath } of shippingAssetFixtures) {
    await writeFile(path.join(source, assetPath), Buffer.from(`fixture:${assetPath}`));
  }
  return { source, collection, payload };
}

async function writeClearedProductionRegistries(temporaryRoot, source) {
  const backstage = path.join(temporaryRoot, "backstage");
  await mkdir(backstage, { recursive: true });
  const assets = await Promise.all(shippingAssetFixtures.map(async ({ assetPath, role }, index) => {
    const bytes = await readFile(path.join(source, assetPath));
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    return {
      assetPath,
      bytes: bytes.byteLength,
      sha256,
      sourceLineage: [{
        lineageType: "GENERATED_ORIGINAL",
        sourceID: `source-fixture-${index}`,
        bytes: bytes.byteLength,
        sha256,
        rightsBasis: "PROJECT_OWNED",
        license: "Project-owned test fixture",
      }],
      toolLineage: [{ toolID: "test-tool" }],
      shippingRoles: [role],
      metadataPolicy: "STRIPPED_AND_INSPECTED",
      rightsStatus: "COMMERCIAL_USE_CLEARED",
      incrementalCostNOK: 0,
      approvedForShipping: true,
    };
  }));
  const assetProvenancePath = path.join(backstage, "native-asset-provenance.json");
  const costRegistryPath = path.join(backstage, "cost-license.json");
  await writeJSON(assetProvenancePath, { schemaVersion: 3, status: "ACTIVE", assets });
  await writeJSON(costRegistryPath, validCostRegistry());
  return { assetProvenancePath, costRegistryPath };
}

async function launchPublicInventoryRecords(source) {
  return Promise.all((await listFiles(source)).map(async (file) => {
    const bytes = await readFile(file);
    return {
      path: path.relative(source, file).split(path.sep).join("/"),
      bytes: bytes.byteLength,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    };
  }));
}

async function writeSyntheticLaunchPackageApproval(
  temporaryRoot,
  source,
  collection,
  payload,
  { approvalPath, overrides = {} } = {},
) {
  const resolvedApprovalPath = approvalPath
    ?? path.join(temporaryRoot, "backstage", "launch-package-approval.json");
  await mkdir(path.dirname(resolvedApprovalPath), { recursive: true });
  const collectionBytes = await readFile(path.join(source, "collection.json"));
  const payloadBytes = await readFile(path.join(source, "chapters", `${payload.packageID}.json`));
  const publicSourceInventorySHA256 = launchPublicSourceInventoryDigest(
    await launchPublicInventoryRecords(source),
  );
  const packageVersion = collection.packages.find(({ id }) => id === payload.packageID).version;
  const saveMigrationGraphSHA256 = saveMigrationGraphDigest(packageVersion);
  const saveMigrationDescriptorInventorySHA256 = saveMigrationDescriptorInventoryDigest();
  const approval = {
    schemaVersion: 2,
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T20:00:00Z",
    decisionReference: "test-only-launch-package-decision",
    collectionID: collection.collectionID,
    packageID: payload.packageID,
    chapterIDs: payload.chapters.map(({ id }) => id),
    collectionSHA256: createHash("sha256").update(collectionBytes).digest("hex"),
    payloadSHA256: createHash("sha256").update(payloadBytes).digest("hex"),
    publicSourceInventorySHA256,
    saveMigrationGraphSHA256,
    saveMigrationDescriptorInventorySHA256,
    launchPackageApprovalSHA256: launchPackageApprovalDigest(
      collectionBytes,
      payloadBytes,
      publicSourceInventorySHA256,
      saveMigrationGraphSHA256,
      saveMigrationDescriptorInventorySHA256,
    ),
    ...overrides,
  };
  await writeJSON(resolvedApprovalPath, approval);
  return {
    approvalPath: resolvedApprovalPath,
    approval,
    collectionBytes,
    payloadBytes,
    publicSourceInventorySHA256,
    saveMigrationGraphSHA256,
    saveMigrationDescriptorInventorySHA256,
  };
}

const compileOptions = (privateKey) => ({
  packageVersion: version(),
  minimumRuntime: version(),
  keyID: "test-signing-key",
  signingPrivateKey: privateKey,
  testOnlyAllowUnapprovedBlueprint: true,
});

test("accepts the exact Swift ContentPackagePayload wire model", () => {
  assert.equal(validatePublicDocument(validContentPackage()).packageID, "essential-free-v1");
});

test("accepts the public app shell and keeps the launch descriptor exactly English", () => {
  const shell = validAppShell();
  const chapterOrder = shell.livingWorld.chapters.map((chapter) => chapter.chapterID);
  assert.equal(validatePublicDocument(shell).id, "launch-app-shell");
  assert.deepEqual(validateLaunchAppShellSpec(shell, chapterOrder), []);

  const norwegian = validAppShell({ identifier: "nb-NO", fallbackIdentifier: "en" });
  assert.equal(validatePublicDocument(norwegian).locale.identifier, "nb-NO");
  assert.match(
    validateLaunchAppShellSpec(norwegian, chapterOrder).join("\n"),
    /launch app shell must use the exact English descriptor/,
  );
});

test("app shell rejects copy-key drift, backstage fields and non-canonical locale tags", () => {
  const conflictingCopy = validAppShell();
  conflictingCopy.livingWorld.chapters[0].historicalInvitation.id
    = conflictingCopy.prologue.narrative.heading.id;
  assert.throws(
    () => validatePublicDocument(conflictingCopy),
    /conflicting English launch values/,
  );

  const backstage = validAppShell();
  backstage.livingWorld.researchNotes = ["private"];
  assert.throws(() => validatePublicDocument(backstage), /forbidden backstage\/research field/);

  const malformedLocale = validAppShell({ identifier: "nb_no" });
  assert.throws(() => validatePublicDocument(malformedLocale), /canonical BCP-47/);
});

test("public copy requires stable localization keys instead of raw launch strings", () => {
  const payload = validContentPackage();
  payload.chapters[0].title = "The First Farmers";
  assert.throws(() => validatePublicDocument(payload), /chapters\[0\]\.title: object required/);
});

test("narration cues bind exact manuscript bytes and chapter-arc-beat scope", () => {
  const wrongHash = validContentPackage();
  wrongHash.audioTimelines[0].events[0].narrationBinding.manuscriptSegmentSHA256
    = "0".repeat(64);
  assert.throws(
    () => validatePublicDocument(wrongHash),
    /does not match editor-approved English manuscript bytes/,
  );

  const wrongScope = validContentPackage();
  wrongScope.audioTimelines[0].events[0].narrationBinding.scope.beatID = "another-beat";
  assert.throws(
    () => validatePublicDocument(wrongScope),
    /must equal 'first-farmers\/river-to-field\/cross-the-water'/,
  );

  const orphan = validContentPackage();
  orphan.chapters[0].arcs[0].beats[0].narrationCueIDs = [];
  assert.throws(
    () => validatePublicDocument(orphan),
    /narration cue is not referenced by its scoped beat/,
  );
});

test("the haptic contract accepts only the six authored response semantics", () => {
  for (const kind of ["contact", "drag", "resistance", "transfer", "break", "seal"]) {
    const payload = validContentPackage();
    payload.audioTimelines[0].haptics[0].kind = kind;
    assert.equal(validatePublicDocument(payload).audioTimelines[0].haptics[0].kind, kind);
  }
  const legacy = validContentPackage();
  legacy.audioTimelines[0].haptics[0].kind = "impact";
  assert.throws(() => validatePublicDocument(legacy), /expected one of contact/);
});

for (const grammar of ["trace", "allocate", "assemble", "pressure", "transform"]) {
  test(`standalone ${grammar} scene accepts its typed visual-binding wire case`, () => {
    assert.equal(validateSceneSpec(validLaboratoryVisualScene(grammar)).id, "aegean-crossing");
  });
}

for (const grammar of ["trace", "allocate", "assemble", "pressure", "transform"]) {
  test(`accepts a shipping ${grammar} interaction with its exact runtime visual binding`, () => {
    assert.equal(
      validatePublicDocument(validShippingVisualPackage(grammar))
        .chapters[0].arcs[0].beats[0].interaction.grammar,
      grammar,
    );
  });
}

for (const grammar of ["trace", "allocate", "assemble", "pressure", "transform"]) {
  test(`requires every shipping ${grammar} beat to carry an authored visual binding`, () => {
    const payload = validShippingVisualPackage(grammar);
    delete payload.scenes[0].interactionVisualBinding;
    assert.throws(
      () => validatePublicDocument(payload),
      /interactive shipping beat requires an authored visual binding/,
    );
  });
}

for (const grammar of ["trace", "allocate", "assemble", "pressure", "transform"]) {
  test(`rejects shipping ${grammar} visual binding interaction-ID drift`, () => {
    const payload = validShippingVisualPackage(grammar);
    payload.scenes[0].interactionVisualBinding.configuration.interactionID = "interaction-forged";
    assert.throws(
      () => validatePublicDocument(payload),
      new RegExp(`interactionID: must equal 'interaction-${grammar}'`),
    );
  });

  test(`rejects a shipping ${grammar} binding that leaves one stateful layer unresolved`, () => {
    const payload = validShippingVisualPackage(grammar);
    const scene = payload.scenes[0];
    scene.layers.push(canonicalVisualLayer("unbound-runtime-state", scene.layers.length, ["idle"]));
    scene.reduceMotionComposition.strata.splice(-1, 0, {
      id: "unbound-runtime-state-overlay",
      kind: "stateOverlay",
      layerID: "unbound-runtime-state",
    });
    assert.throws(
      () => validatePublicDocument(payload),
      /must bind every and only stateful scene layer resolved by its runtime adapter/,
    );
  });
}

test("rejects assembly component-set and runtime-layer alias drift", () => {
  const missingComponent = validShippingVisualPackage("assemble");
  missingComponent.scenes[0].interactionVisualBinding.configuration.components.pop();
  assert.throws(
    () => validatePublicDocument(missingComponent),
    /must bind every and only authored assembly component/,
  );

  const aliasedLayer = validShippingVisualPackage("assemble");
  const configuration = aliasedLayer.scenes[0].interactionVisualBinding.configuration;
  configuration.components[1].layerID = configuration.components[0].layerID;
  aliasedLayer.scenes[0].interactionTargets[2].layerID = configuration.components[0].layerID;
  aliasedLayer.scenes[0].interactionTargets[3].layerID = configuration.components[0].layerID;
  assert.throws(
    () => validatePublicDocument(aliasedLayer),
    /each assembly component requires its own stateful runtime layer/,
  );
});

test("requires distinct, globally unique assembly source and slot targets", () => {
  const legacy = validShippingVisualPackage("assemble");
  const legacyComponent = legacy.scenes[0].interactionVisualBinding.configuration.components[0];
  legacyComponent.interactionTargetID = legacyComponent.sourceInteractionTargetID;
  delete legacyComponent.sourceInteractionTargetID;
  delete legacyComponent.slotInteractionTargetID;
  assert.throws(
    () => validatePublicDocument(legacy),
    /sourceInteractionTargetID.*required|unexpected fields interactionTargetID/,
  );

  const sameTarget = validShippingVisualPackage("assemble");
  const sameComponent = sameTarget.scenes[0].interactionVisualBinding.configuration.components[0];
  sameComponent.slotInteractionTargetID = sameComponent.sourceInteractionTargetID;
  assert.throws(
    () => validatePublicDocument(sameTarget),
    /source and slot targets must be distinct/,
  );

  const crossAliased = validShippingVisualPackage("assemble");
  const crossComponents = crossAliased.scenes[0].interactionVisualBinding.configuration.components;
  crossComponents[1].sourceInteractionTargetID = crossComponents[0].slotInteractionTargetID;
  assert.throws(
    () => validatePublicDocument(crossAliased),
    /sourceAndSlotInteractionTargetID: duplicate identifier/,
  );

  const unknownSlot = validShippingVisualPackage("assemble");
  unknownSlot.scenes[0].interactionVisualBinding.configuration
    .components[0].slotInteractionTargetID = "unknown-slot";
  assert.throws(
    () => validatePublicDocument(unknownSlot),
    /requires real layer-bound source and slot targets/,
  );
});

test("rejects pressure force-set and transform stage-set binding drift", () => {
  const pressure = validShippingVisualPackage("pressure");
  pressure.scenes[0].interactionVisualBinding.configuration.forces.pop();
  assert.throws(
    () => validatePublicDocument(pressure),
    /must bind every force and only controllable forces to targets/,
  );

  const transform = validShippingVisualPackage("transform");
  transform.scenes[0].interactionVisualBinding.configuration.stages[0].stageID = "invented-stage";
  assert.throws(
    () => validatePublicDocument(transform),
    /must bind every and only authored transformation stage/,
  );
});

test("keeps standalone laboratory SceneSpec validation permissive", () => {
  const scene = validContentPackage("allocate").scenes[0];
  delete scene.interactionVisualBinding;
  assert.equal(validateSceneSpec(scene).id, "aegean-crossing");
});

test("requires typed, grammar-bound accessibility action tokens", () => {
  const opaque = validContentPackage();
  opaque.accessibility[0].elements[0].actions[0].token = "advance";
  assert.throws(() => validatePublicDocument(opaque), /typed semantic action token object required/);

  const unbound = validContentPackage("assemble");
  unbound.accessibility[0].elements[0].actions[0].token.targetID = "invented-component";
  assert.throws(() => validatePublicDocument(unbound), /unbound to assemble/);
});

test("requires a complete operable VoiceOver path for every interaction", () => {
  const incomplete = validContentPackage("allocate");
  incomplete.accessibility[0].elements[0].actions = incomplete.accessibility[0].elements[0].actions
    .filter((action) => action.kind !== "decrement");
  assert.throws(() => validatePublicDocument(incomplete), /requires exactly one decrement allocate/);

  const unreachable = validContentPackage("pressure");
  unreachable.chapters[0].arcs[0].beats[0].interaction.configuration.stableRange = [0.05, 0.05];
  const adjustable = unreachable.accessibility[0].elements.find((element) => element.role === "adjustable");
  adjustable.actions.forEach((action) => { action.token.step = 0.2; });
  assert.throws(
    () => validatePublicDocument(unreachable),
    /VoiceOver parity failed: discrete VoiceOver pressure path cannot reach the stable range/,
  );
});

test("a documentary beat may own a world effect without inventing player control", () => {
  const payload = validContentPackage();
  const beat = payload.chapters[0].arcs[0].beats[0];
  delete beat.interaction;
  beat.completionEffects = [revealSettlementEffect("documentary-effect")];
  beat.checkpoint = "onExit";
  payload.accessibility[0].elements = [{
    id: "documentary-mechanism",
    role: "mechanism",
    label: localized("access-documentary-mechanism-label", "The settlement becomes permanent"),
    actions: [],
  }];
  payload.scenes[0].interactionTargets = [];
  delete payload.scenes[0].interactionVisualBinding;
  bindResponsiveAudioPrograms(payload);
  assert.equal(validatePublicDocument(payload).chapters[0].arcs[0].beats[0].completionEffects.length, 1);

  const invalid = validContentPackage();
  invalid.chapters[0].arcs[0].beats[0].completionEffects = [revealSettlementEffect("misplaced-effect")];
  assert.throws(
    () => validatePublicDocument(invalid),
    /interactive beats keep effects on the interaction/,
  );
});

test("pressure uses Swift ClosedRange's two-element wire array", () => {
  const payload = validContentPackage("pressure");
  payload.chapters[0].arcs[0].beats[0].interaction.configuration.stableRange = {
    lowerBound: -0.1,
    upperBound: 0.25,
  };
  assert.throws(() => validatePublicDocument(payload), /array required/);
});

test("accepts canonical CollectionManifest and Release wire models", () => {
  assert.equal(validateCollectionManifest(validCollection()).length, 0);
  assert.equal(validatePublicDocument(validCollection()).chapters.length, 24);
  assert.equal(validateReleaseDocument(validRelease()).length, 0);
  assert.equal(validatePublicDocument(validRelease()).packageID, "essential-free-v1");
});

test("binds a launch collection to central product, catalog and delivery metadata", () => {
  const collection = validCollection();
  collection.packages.at(-1).maximumInstalledBytes -= 100_000_000;
  const catalog = {
    collectionID: collection.collectionID,
    freeContentIDs: collection.chapters.filter((chapter) => chapter.access.kind === "included").map((chapter) => chapter.id),
    chapters: collection.chapters.map((chapter) => ({
      ordinal: chapter.sequence,
      contentID: chapter.id,
      title: chapter.title.launchEnglish,
      period: chapter.period.launchEnglish,
    })),
  };
  const delivery = {
    budgets: {
      shellAndEngineBytes: 100_000_000,
      completeInstalledWorkBytes: 6_000_000_000,
    },
    entitlement: {
      entitlementID: collection.entitlements[0].id,
      storeProductID: collection.entitlements[0].storeProductID,
    },
    packages: collection.packages.map((item) => ({
      packageID: item.id,
      chapterIDs: item.chapterIDs,
      maximumInstalledBytes: item.maximumInstalledBytes,
      isEssentialInstall: item.isEssentialInstall,
    })),
  };
  const launchConfiguration = { product: collection.product, catalog, delivery };
  assert.deepEqual(validateCollectionAgainstLaunchConfiguration(collection, launchConfiguration), []);

  const contentConsumesShellReservation = structuredClone(collection);
  contentConsumesShellReservation.packages.at(-1).maximumInstalledBytes += 100_000_000;
  assert.match(
    validateCollectionAgainstLaunchConfiguration(contentConsumesShellReservation, launchConfiguration).join("\n"),
    /exceeds the complete installed-work budget/,
  );

  const drifted = structuredClone(collection);
  drifted.product.workTitle = "A different product";
  assert.match(
    validateCollectionAgainstLaunchConfiguration(drifted, launchConfiguration).join("\n"),
    /must match native\/product\.json/,
  );
});

test("installed package bytes include the signed manifest and cannot consume the shell reservation", () => {
  assert.equal(
    requireInstalledByteBudget([{ bytes: 70 }, { bytes: 20 }], 10, 100),
    100,
  );
  assert.throws(
    () => requireInstalledByteBudget([{ bytes: 70 }, { bytes: 21 }], 10, 100),
    /exceeds declared package maximum/,
  );
});

test("responsive audio decoded buffers reject a three-branch non-causal transition peak", () => {
  const payload = bindResponsiveAudioPrograms(validContentPackage("transform"));
  const program = payload.responsiveAudioPrograms[0];
  for (const bed of program.interactionBeds) {
    const timeline = payload.audioTimelines.find(({ id }) => id === bed.timelineID);
    timeline.events = Array.from({ length: 8 }, (_, index) => ({
      cueID: `decoded-layer-${bed.phase}-${index}`,
      role: index === 0 ? "score" : "soundscape",
      startSample: 0,
      durationSamples: 720_000,
      assetPath: `audio/${bed.phase}-layer-${index}.m4a`,
      gain: index === 0 ? 0.7 : 0,
    }));
  }

  const estimate = responsiveAudioDecodedBufferEstimate(payload);
  assert.equal(estimate.steady.bytes, 97_920_000);
  assert.equal(estimate.transition.bytes, 276_480_000);
  assert.throws(
    () => requireResponsiveAudioDecodedBufferBudget(
      payload,
      100_000_000,
      200_000_000,
    ),
    /transition 276480000 bytes/,
  );
  assert.deepEqual(
    requireResponsiveAudioDecodedBufferBudget(payload, 100_000_000, 300_000_000),
    estimate,
  );
  assert.throws(
    () => requireResponsiveAudioDecodedBufferBudget(
      payload,
      97_919_999,
      300_000_000,
    ),
    /steady 97920000 bytes/,
  );
  assert.throws(
    () => requireResponsiveAudioDecodedBufferBudget(
      payload,
      100_000_000,
      276_479_999,
    ),
    /transition 276480000 bytes/,
  );
});

test("responsive audio decoded buffers count causal layers once across three branches", () => {
  const payload = bindValidCausalMix(
    bindResponsiveAudioPrograms(validContentPackage("transform")),
  );
  const estimate = responsiveAudioDecodedBufferEstimate(payload);

  assert.equal(estimate.steady.bytes, 2_688_000);
  assert.equal(estimate.transition.bytes, 3_840_000);
  assert.deepEqual(
    requireResponsiveAudioDecodedBufferBudget(payload, 3_000_000, 4_000_000),
    estimate,
  );
});

test("package signing metadata exactly matches the owning collection package", () => {
  const collection = validCollection();
  assert.equal(
    requireMatchingCollectionPackageSpec(
      collection,
      "essential-free-v1",
      version(),
      version(),
    ).id,
    "essential-free-v1",
  );
  assert.throws(
    () => requireMatchingCollectionPackageSpec(
      collection,
      "essential-free-v1",
      version(2),
      version(),
    ),
    /packageVersion: must exactly match/,
  );
  assert.throws(
    () => requireMatchingCollectionPackageSpec(
      collection,
      "essential-free-v1",
      version(),
      version(1, 1),
    ),
    /minimumRuntime: must exactly match/,
  );
});

test("rejects the superseded web-shaped chapter document", () => {
  assert.throws(() => validatePublicDocument({ contentID: "first-farmers", arcs: [] }), /expected CollectionManifest/);
});

test("rejects missing required payload fields and unknown fields", () => {
  const payload = validContentPackage();
  delete payload.audioTimelines;
  payload.locale = "en";
  assert.throws(() => validatePublicDocument(payload), /audioTimelines: required/);
  assert.throws(() => validatePublicDocument(payload), /locale: unknown public field/);
});

test("accepts optional causal mix while preserving phase-only responsive programs", () => {
  assert.doesNotThrow(() => validatePublicDocument(validShippingVisualPackage("transform")));

  const payload = bindValidCausalMix(validShippingVisualPackage("transform"));
  const validated = validatePublicDocument(payload);
  const mix = validated.responsiveAudioPrograms[0].causalMix;
  assert.equal(mix.rampDurationSamples, 9_600);
  assert.deepEqual(mix.layers.map(({ id }) => id), ["river-current", "household-work"]);
  assert.deepEqual(mix.states.map(({ completedStageCount }) => completedStageCount), [0, 1]);
});

test("audio event gains share the native linear 0...4 transport bound", () => {
  for (const invalidGain of [-0.01, 4.01]) {
    const payload = validContentPackage();
    payload.audioTimelines[0].events[0].gain = invalidGain;
    assert.throws(
      () => validatePublicDocument(payload),
      /gain: linear gain must be between zero and four/,
    );
  }
});

test("responsive beds reject zero-length audible cues and loops beyond UInt32.max", () => {
  const zeroLength = bindValidCausalMix(validShippingVisualPackage("transform"));
  const waitingID = zeroLength.responsiveAudioPrograms[0].interactionBeds
    .find(({ phase }) => phase === "waiting").timelineID;
  zeroLength.audioTimelines.find(({ id }) => id === waitingID).events
    .find(({ role }) => role === "score").durationSamples = 0;
  assert.throws(
    () => validatePublicDocument(zeroLength),
    /audible event 'causal-waiting-score' must have positive duration/,
  );

  const oversized = validShippingVisualPackage("transform");
  for (const bed of oversized.responsiveAudioPrograms[0].interactionBeds) {
    const timeline = oversized.audioTimelines.find(({ id }) => id === bed.timelineID);
    timeline.events[0].durationSamples = 4_294_967_296;
  }
  assert.throws(
    () => validatePublicDocument(oversized),
    /loop duration must not exceed UInt32\.max samples/,
  );
});

test("zero-length finite legacy cues remain decodable outside responsive beds", () => {
  const payload = validContentPackage();
  payload.audioTimelines[0].events[0].durationSamples = 0;
  assert.doesNotThrow(() => validatePublicDocument(payload));
});

test("causal mix fails closed on backstage fields, identity and irreversible-state defects", () => {
  const backstage = bindValidCausalMix(validShippingVisualPackage("transform"));
  backstage.responsiveAudioPrograms[0].causalMix.transportStatus = "backstage-only";
  assert.throws(
    () => validatePublicDocument(backstage),
    /causalMix\.transportStatus: unknown public field/,
  );

  const duplicateLayer = bindValidCausalMix(validShippingVisualPackage("transform"));
  duplicateLayer.responsiveAudioPrograms[0].causalMix.layers[1].id = "river-current";
  assert.throws(() => validatePublicDocument(duplicateLayer), /causalMix\.layers\.id: duplicate/);

  const duplicateCue = bindValidCausalMix(validShippingVisualPackage("transform"));
  duplicateCue.responsiveAudioPrograms[0].causalMix.layers[1].cueIDs.waiting
    = duplicateCue.responsiveAudioPrograms[0].causalMix.layers[0].cueIDs.waiting;
  assert.throws(
    () => validatePublicDocument(duplicateCue),
    /causalMix\.layers\.cueIDs\.waiting: duplicate/,
  );

  const noncontiguous = bindValidCausalMix(validShippingVisualPackage("transform"));
  noncontiguous.responsiveAudioPrograms[0].causalMix.states[1].completedStageCount = 2;
  assert.throws(
    () => validatePublicDocument(noncontiguous),
    /states\.completedStageCount: states must be ordered and contiguous from zero/,
  );

  const incompleteCoverage = bindValidCausalMix(validShippingVisualPackage("transform"));
  incompleteCoverage.responsiveAudioPrograms[0].causalMix.states[1].layerGains.pop();
  assert.throws(
    () => validatePublicDocument(incompleteCoverage),
    /every state must cover every layer exactly once in authored layer order/,
  );

  const excessGain = bindValidCausalMix(validShippingVisualPackage("transform"));
  excessGain.responsiveAudioPrograms[0].causalMix.states[1].layerGains[1].gain = 4.01;
  assert.throws(
    () => validatePublicDocument(excessGain),
    /linear gain must be between zero and four/,
  );
});

test("causal mix fails closed on cue, geometry, state-zero and Transform binding drift", () => {
  const missingCue = bindValidCausalMix(validShippingVisualPackage("transform"));
  missingCue.responsiveAudioPrograms[0].causalMix.layers[0].cueIDs.engaged
    = "unbound-engaged-river";
  assert.throws(() => validatePublicDocument(missingCue), /missing audio cue/);

  const wrongAsset = bindValidCausalMix(validShippingVisualPackage("transform"));
  wrongAsset.responsiveAudioPrograms[0].causalMix.layers[0].assetPath
    = "audio/responsive/shared/another-river.wav";
  assert.throws(
    () => validatePublicDocument(wrongAsset),
    /mapped cues must be material roles using the explicit shared asset path and state-zero gain/,
  );

  const wrongInitialGain = bindValidCausalMix(validShippingVisualPackage("transform"));
  wrongInitialGain.responsiveAudioPrograms[0].causalMix.states[0].layerGains[0].gain = 0.7;
  assert.throws(
    () => validatePublicDocument(wrongInitialGain),
    /mapped cues must be material roles using the explicit shared asset path and state-zero gain/,
  );

  const clippedGeometry = bindValidCausalMix(validShippingVisualPackage("transform"));
  const engagedID = clippedGeometry.responsiveAudioPrograms[0].interactionBeds
    .find(({ phase }) => phase === "engaged").timelineID;
  clippedGeometry.audioTimelines.find(({ id }) => id === engagedID).events
    .find(({ cueID }) => cueID === "causal-engaged-river-current").durationSamples = 47_999;
  assert.throws(
    () => validatePublicDocument(clippedGeometry),
    /all phase cues must share role, start, duration and asset path/,
  );

  const excessiveRamp = bindValidCausalMix(validShippingVisualPackage("transform"));
  excessiveRamp.responsiveAudioPrograms[0].causalMix.rampDurationSamples = 48_001;
  assert.throws(
    () => validatePublicDocument(excessiveRamp),
    /be no longer than the shared interaction loop/,
  );

  const wrongGrammar = bindValidCausalMix(validShippingVisualPackage("transform"));
  wrongGrammar.chapters[0].arcs[0].beats[0].interaction.grammar = "trace";
  wrongGrammar.chapters[0].arcs[0].beats[0].interaction.configuration = {
    anchors: [{ x: 0.1, y: 0.8 }, { x: 0.8, y: 0.2 }],
    tolerance: 0.1,
  };
  assert.throws(
    () => validatePublicDocument(wrongGrammar),
    /causalMix: requires the exact scoped Transform interaction/,
  );

  const wrongStateCount = bindValidCausalMix(validShippingVisualPackage("transform"));
  wrongStateCount.chapters[0].arcs[0].beats[0].interaction.configuration.stages.push({
    id: "plant-ground",
    controlID: "field-edge",
    requiredAmount: 1,
  });
  assert.throws(
    () => validatePublicDocument(wrongStateCount),
    /requires state zero plus exactly one state per Transform stage/,
  );
});

test("public JSON Schema exposes authored exit policy and optional causal mix through shipping-safe shapes", async () => {
  const schema = JSON.parse(await readFile(
    path.join(nativeRoot, "schemas/public-content.schema.json"),
    "utf8",
  ));
  const program = schema.$defs.ResponsiveAudioProgramSpec;
  assert.equal(program.required.includes("exitPolicy"), true);
  assert.equal(program.required.includes("causalMix"), false);
  assert.deepEqual(program.properties.exitPolicy, {
    $ref: "#/$defs/ResponsiveAudioExitPolicy",
  });
  assert.deepEqual(program.properties.causalMix, {
    $ref: "#/$defs/ResponsiveAudioCausalMixSpec",
  });
  for (const definitionName of [
    "ResponsiveAudioPhaseCueIDs",
    "ResponsiveAudioMaterialLayerSpec",
    "ResponsiveAudioLayerGainSpec",
    "ResponsiveAudioCausalMixStateSpec",
    "ResponsiveAudioCausalMixSpec",
  ]) {
    assert.equal(schema.$defs[definitionName].additionalProperties, false);
  }
  assert.deepEqual(
    schema.$defs.ResponsiveAudioCausalMixSpec.required,
    ["rampDurationSamples", "layers", "states"],
  );
  assert.equal(schema.$defs.ResponsiveAudioExitPolicy.additionalProperties, false);
  assert.deepEqual(
    schema.$defs.ResponsiveAudioExitPolicy.required,
    ["kind", "durationSamples"],
  );
  assert.deepEqual(schema.$defs.ResponsiveAudioExitPolicy.properties.kind, {
    const: "bounded-fade",
  });
  assert.deepEqual(schema.$defs.AudioEvent.properties.gain, {
    type: "number",
    minimum: 0,
    maximum: 4,
  });
  assert.deepEqual(schema.$defs.AudioEvent.properties.durationSamples, {
    type: "integer",
    minimum: 0,
  });
});

test("responsive audio exit policy is explicit, bounded and no longer than its consequence", () => {
  const missing = validShippingVisualPackage();
  delete missing.responsiveAudioPrograms[0].exitPolicy;
  assert.throws(
    () => validatePublicDocument(missing),
    /exitPolicy: required/,
  );

  const unknownKind = validShippingVisualPackage();
  unknownKind.responsiveAudioPrograms[0].exitPolicy.kind = "global-default";
  assert.throws(
    () => validatePublicDocument(unknownKind),
    /exitPolicy\.kind: expected one of bounded-fade/,
  );

  const zero = validShippingVisualPackage();
  zero.responsiveAudioPrograms[0].exitPolicy.durationSamples = 0;
  assert.throws(
    () => validatePublicDocument(zero),
    /exitPolicy\.durationSamples: integer >= 1 required/,
  );

  const oversizedRamp = validShippingVisualPackage();
  oversizedRamp.responsiveAudioPrograms[0].exitPolicy.durationSamples = 4_294_967_296;
  assert.throws(
    () => validatePublicDocument(oversizedRamp),
    /exitPolicy\.durationSamples: must fit one sample-accurate audio-unit ramp/,
  );

  const beyondConsequence = validShippingVisualPackage();
  const program = beyondConsequence.responsiveAudioPrograms[0];
  const consequence = beyondConsequence.audioTimelines.find(
    ({ id }) => id === program.consequenceTimelineID,
  );
  program.exitPolicy.durationSamples = consequence.events[0].durationSamples + 1;
  assert.throws(
    () => validatePublicDocument(beyondConsequence),
    /exitPolicy\.durationSamples: must not exceed the full authored consequence timeline/,
  );
});

test("rejects package IDs that the Swift verifier cannot trust", () => {
  const payload = validContentPackage();
  payload.packageID = "01-essential";
  assert.throws(() => validatePublicDocument(payload), /package ID must start/);
});

for (const forbiddenKey of ["researchNotes", "research_notes", "source_ids", "sourceMaterial", "citation_list", "verifierFinding", "verifier-finding"]) {
  test(`rejects normalised backstage alias ${forbiddenKey}`, () => {
    const payload = validContentPackage();
    payload.chapters[0][forbiddenKey] = ["private"];
    assert.throws(() => validatePublicDocument(payload), /forbidden backstage\/research field/);
  });
}

test("rejects academic leakage", () => {
  const payload = validContentPackage();
  payload.chapters[0].arcs[0].beats[0].narrative.paragraphs[0].launchEnglish = "Historians disagree about what this means.";
  assert.throws(() => validatePublicDocument(payload), /editorial regression/);
});

test("rejects unsupported interaction grammar and mismatched configuration", () => {
  const payload = validContentPackage();
  payload.chapters[0].arcs[0].beats[0].interaction.grammar = "quiz";
  assert.throws(() => validatePublicDocument(payload), /expected one of trace/);
  const mismatch = validContentPackage("trace");
  mismatch.chapters[0].arcs[0].beats[0].interaction.configuration = { stages: [] };
  assert.throws(() => validatePublicDocument(mismatch), /anchors: required/);
});

test("rejects incomplete or cyclic grammar configurations", () => {
  const allocate = validContentPackage("allocate");
  for (const destination of allocate.chapters[0].arcs[0].beats[0]
    .interaction.configuration.destinations) destination.minimumUnits = 2;
  assert.throws(() => validatePublicDocument(allocate), /leave authored surplus/);
  const assemble = validContentPackage("assemble");
  assemble.chapters[0].arcs[0].beats[0].interaction.configuration.components[0].prerequisites = ["roof"];
  assert.throws(() => validatePublicDocument(assemble), /acyclic/);
});

test("rejects missing package cross-references", () => {
  const missingScene = validContentPackage();
  missingScene.chapters[0].arcs[0].beats[0].sceneID = "absent-scene";
  assert.throws(() => validatePublicDocument(missingScene), /missing scene/);
  const missingCue = validContentPackage();
  missingCue.chapters[0].arcs[0].beats[0].narrationCueIDs = ["absent-cue"];
  assert.throws(() => validatePublicDocument(missingCue), /missing narration cue/);
  const missingAccess = validContentPackage();
  missingAccess.scenes[0].accessibilityID = "absent-accessibility";
  assert.throws(() => validatePublicDocument(missingAccess), /missing accessibility spec/);
});

test("binds every interactive scene to the same operable accessibility reducer path", () => {
  const missingTargets = validContentPackage();
  missingTargets.scenes[0].interactionTargets = [];
  assert.throws(() => validatePublicDocument(missingTargets), /interactive scene requires at least one real hit region/);

  const mismatchedSpec = validContentPackage();
  const alternateSpec = structuredClone(mismatchedSpec.accessibility[0]);
  alternateSpec.id = "alternate-accessibility";
  mismatchedSpec.accessibility.push(alternateSpec);
  mismatchedSpec.scenes[0].accessibilityID = alternateSpec.id;
  assert.throws(() => validatePublicDocument(mismatchedSpec), /must equal interaction accessibilityID/);

  const descriptiveTarget = validContentPackage();
  descriptiveTarget.accessibility[0].elements.push({
    id: "route-description",
    role: "mechanism",
    label: localized("access-route-description-label", "The crossing route"),
    actions: [],
  });
  descriptiveTarget.scenes[0].interactionTargets[0].accessibilityElementID = "route-description";
  assert.throws(() => validatePublicDocument(descriptiveTarget), /must bind to an operable action or adjustable element/);
});

test("enforces the portrait scene canvas, baseline crop and authored overscan", () => {
  const landscapeCanvas = validContentPackage();
  landscapeCanvas.scenes[0].sceneCanvas.canvas = { width: 2600, height: 1200 };
  assert.throws(() => validatePublicDocument(landscapeCanvas), /portrait dimensions required/);

  const missingBaseline = validContentPackage();
  missingBaseline.scenes[0].sceneCanvas.viewportCrops[0].id = "compact-393x852";
  assert.throws(() => validatePublicDocument(missingBaseline), /baseline-393x852/);

  const insufficientOverscan = validContentPackage();
  insufficientOverscan.scenes[0].sceneCanvas.authoredOverscanFraction = 0.149;
  assert.throws(() => validatePublicDocument(insufficientOverscan), /must be between 0.15 and 0.5/);

  const clippedTravel = validContentPackage();
  clippedTravel.scenes[0].sceneCanvas.cameraTravelBounds = {
    x: 0.01, y: 0.2, width: 0.6, height: 0.6,
  };
  assert.throws(() => validatePublicDocument(clippedTravel), /preserve authored overscan/);
});

test("rejects invalid scene rectangles, crop aspect and layer ordering", () => {
  const escapedFrame = validContentPackage();
  escapedFrame.scenes[0].layers[0].frame = { x: 0.8, y: 0, width: 0.3, height: 1 };
  assert.throws(() => validatePublicDocument(escapedFrame), /positive normalized rect/);

  const wrongAspect = validContentPackage();
  wrongAspect.scenes[0].sceneCanvas.viewportCrops[0].sourceRect = {
    x: 0, y: 0, width: 0.5, height: 1,
  };
  assert.throws(() => validatePublicDocument(wrongAspect), /must match the authored viewport aspect/);

  const wrongOrder = validContentPackage();
  wrongOrder.scenes[0].layers[0].order = 1;
  assert.throws(() => validatePublicDocument(wrongOrder), /must equal authored array order 0/);
});

test("rejects duplicate camera progress and every non-finite scene scalar", () => {
  const duplicateProgress = validContentPackage();
  duplicateProgress.scenes[0].cameraRail.keyframes = [
    { progress: 0, center: { x: 0.45, y: 0.5 }, scale: 1 },
    { progress: 0.5, center: { x: 0.5, y: 0.5 }, scale: 1 },
    { progress: 0.5, center: { x: 0.52, y: 0.48 }, scale: 1.02 },
    { progress: 1, center: { x: 0.55, y: 0.45 }, scale: 1.08 },
  ];
  assert.throws(() => validatePublicDocument(duplicateProgress), /strictly increasing and unique/);

  const nonFiniteVelocity = validContentPackage();
  nonFiniteVelocity.scenes[0].atmosphere[0].velocity.dx = Number.NaN;
  assert.throws(() => validatePublicDocument(nonFiniteVelocity), /finite number required/);

  const nonFiniteLayer = validContentPackage();
  nonFiniteLayer.scenes[0].layers[0].motion.parallaxFactor = Number.POSITIVE_INFINITY;
  assert.throws(() => validatePublicDocument(nonFiniteLayer), /finite number required/);
});

test("requires real scene targets bound to a layer and accessibility element", () => {
  const degenerateHitRegion = validContentPackage();
  degenerateHitRegion.scenes[0].interactionTargets[0].hitRegion.path = [
    { x: 0.2, y: 0.2 }, { x: 0.4, y: 0.4 }, { x: 0.6, y: 0.6 },
  ];
  assert.throws(() => validatePublicDocument(degenerateHitRegion), /non-zero polygon area required/);

  const missingLayer = validContentPackage();
  missingLayer.scenes[0].interactionTargets[0].layerID = "absent-layer";
  assert.throws(() => validatePublicDocument(missingLayer), /missing scene layer 'absent-layer'/);

  const missingElement = validContentPackage();
  missingElement.scenes[0].interactionTargets[0].accessibilityElementID = "absent-element";
  assert.throws(() => validatePublicDocument(missingElement), /missing accessibility element 'absent-element'/);

  const tinyTarget = validContentPackage();
  tinyTarget.scenes[0].interactionTargets[0].hitRegion.path = [
    { x: 0.25, y: 0.65 }, { x: 0.27, y: 0.65 }, { x: 0.26, y: 0.67 },
  ];
  assert.throws(() => validatePublicDocument(tinyTarget), /at least 44 by 44 points/);

  const clippedByCrop = validContentPackage();
  clippedByCrop.scenes[0].sceneCanvas.viewportCrops[0].sourceRect = {
    x: 0.2, y: 0.2, width: 0.6, height: 0.6,
  };
  assert.throws(() => validatePublicDocument(clippedByCrop), /must be wholly visible/);
});

test("requires bounded signed atmosphere vectors and deterministic 32-bit seeds", () => {
  const oversizedVector = validContentPackage();
  oversizedVector.scenes[0].atmosphere[0].velocity = { dx: 0.9, dy: 0.9 };
  assert.throws(() => validatePublicDocument(oversizedVector), /signed unit vector required/);

  const oversizedSeed = validContentPackage();
  oversizedSeed.scenes[0].atmosphere[0].deterministicSeed = 4_294_967_296;
  assert.throws(() => validatePublicDocument(oversizedSeed), /32-bit seed required/);
});

test("requires an independent safe Reduce Motion asset and matching baseline crop", () => {
  const remoteAsset = validContentPackage();
  remoteAsset.scenes[0].reduceMotionComposition.strata[0].assetPath = "https://example.com/reduce.heif";
  assert.throws(() => validatePublicDocument(remoteAsset), /package-relative asset path required/);

  const missingBaseline = validContentPackage();
  missingBaseline.scenes[0].reduceMotionComposition.viewportCrops[0].id = "compact-393x852";
  assert.throws(() => validatePublicDocument(missingBaseline), /baseline-393x852/);

  const reusedLayer = validContentPackage();
  reusedLayer.scenes[0].reduceMotionComposition.strata[0].assetPath = reusedLayer.scenes[0].layers[0].assetPath;
  assert.throws(() => validatePublicDocument(reusedLayer), /not reused by dynamic layers/);

  const mismatchedCropSet = validContentPackage();
  const compactCrop = baselineCrop();
  compactCrop.id = "compact-390x845";
  compactCrop.viewport = { widthPoints: 390, heightPoints: 845 };
  mismatchedCropSet.scenes[0].sceneCanvas.viewportCrops.push(compactCrop);
  assert.throws(() => validatePublicDocument(mismatchedCropSet), /must match the normal crop IDs and viewport dimensions/);

  const remoteVariantMask = validContentPackage();
  remoteVariantMask.scenes[0].layers[0].stateVariants[0].masks.lightMaskAssetPath = "../light.png";
  assert.throws(() => validatePublicDocument(remoteVariantMask), /package-relative asset path required/);

  const controlCharacterPath = validContentPackage();
  controlCharacterPath.scenes[0].layers[0].masks.depthMaskAssetPath = "assets/depth\u0000.png";
  assert.throws(() => validatePublicDocument(controlCharacterPath), /package-relative asset path required/);
});

test("validates an allocate visual binding against its exact interaction", () => {
  const payload = validAllocateVisualPackage();
  assert.equal(
    validatePublicDocument(payload).scenes[0].interactionVisualBinding.grammar,
    "allocate",
  );
});

test("rejects allocate visual binding interaction and destination drift", () => {
  const wrongInteraction = validAllocateVisualPackage();
  wrongInteraction.scenes[0].interactionVisualBinding.configuration.interactionID = "interaction-other";
  assert.throws(
    () => validatePublicDocument(wrongInteraction),
    /interactionID: must equal 'interaction-allocate'/,
  );

  const missingDestination = validAllocateVisualPackage();
  missingDestination.scenes[0].interactionVisualBinding.configuration.destinations.pop();
  assert.throws(
    () => validatePublicDocument(missingDestination),
    /must bind every and only authored allocation destination/,
  );

  const differentDestination = validAllocateVisualPackage();
  differentDestination.chapters[0].arcs[0].beats[0].interaction.configuration.destinations = [
    { id: "seed", minimumUnits: 1 },
    { id: "reserve", minimumUnits: 1 },
  ];
  assert.throws(
    () => validatePublicDocument(differentDestination),
    /must bind every and only authored allocation destination/,
  );
});

test("rejects allocate resource thresholds that do not end at totalUnits", () => {
  const payload = validAllocateVisualPackage();
  payload.scenes[0].interactionVisualBinding.configuration
    .resource.variantsByRemainingUnits[1].maximumRemainingUnits = 3;
  assert.throws(
    () => validatePublicDocument(payload),
    /must end at the interaction's finite resource total/,
  );
});

test("rejects unknown allocate visual variants and targets", () => {
  const unknownVariant = validAllocateVisualPackage();
  unknownVariant.scenes[0].interactionVisualBinding.configuration
    .destinations[0].completedVariantID = "unknown-state";
  assert.throws(
    () => validateSceneSpec(unknownVariant.scenes[0]),
    /visual variants must exist on the destination layer/,
  );

  const unknownTarget = validAllocateVisualPackage();
  unknownTarget.scenes[0].interactionVisualBinding.configuration
    .destinations[0].interactionTargetID = "unknown-target";
  assert.throws(
    () => validateSceneSpec(unknownTarget.scenes[0]),
    /must bind a real target on the same known layer/,
  );
});

test("requires Reduce Motion overlays for every stateful scene layer", () => {
  const payload = validAllocateVisualPackage();
  payload.scenes[0].reduceMotionComposition.strata.splice(-2, 1);
  assert.throws(
    () => validateSceneSpec(payload.scenes[0]),
    /must place every and only stateful layer/,
  );
});

test("rejects target overlap and an active camera source outside the master", () => {
  const overlappingTargets = validAllocateVisualPackage();
  overlappingTargets.scenes[0].interactionTargets[1].hitRegion = structuredClone(
    overlappingTargets.scenes[0].interactionTargets[0].hitRegion,
  );
  assert.throws(
    () => validateSceneSpec(overlappingTargets.scenes[0]),
    /targets 'seed-target' and 'winter-target' overlap/,
  );

  const escapingCamera = validAllocateVisualPackage();
  escapingCamera.scenes[0].cameraRail.keyframes[0].center = { x: 0.2, y: 0.2 };
  assert.throws(
    () => validateSceneSpec(escapingCamera.scenes[0]),
    /active camera source must stay inside the authored master/,
  );
});

test("rejects a target clipped only between camera anchors", () => {
  const scene = validContentPackage().scenes[0];
  scene.layers[0].motion.parallaxFactor = 0;
  scene.interactionTargets[0].hitRegion = rectangularHitRegion(0.22, 0.33, 0.46, 0.54);
  scene.cameraRail.keyframes = [
    { progress: 0, center: { x: 0.3, y: 0.5 }, scale: 3 },
    { progress: 1, center: { x: 0.58, y: 0.5 }, scale: 1.1 },
  ];
  assert.throws(
    () => validateSceneSpec(scene),
    /must be wholly visible.*complete camera rail/,
  );
});

test("rejects targets that cross only between camera anchors", () => {
  const scene = validContentPackage().scenes[0];
  scene.cameraRail.keyframes = [
    { progress: 0, center: { x: 0.4, y: 0.5 }, scale: 1.5 },
    { progress: 1, center: { x: 0.6, y: 0.5 }, scale: 1.5 },
  ];
  scene.layers[0].motion.parallaxFactor = 1;
  scene.interactionTargets[0].hitRegion = rectangularHitRegion(0.34, 0.46, 0.46, 0.54);
  const crossingLayer = structuredClone(scene.layers[0]);
  crossingLayer.id = "crossing-layer";
  crossingLayer.order = 1;
  crossingLayer.motion.parallaxFactor = -1;
  crossingLayer.stateVariants = [];
  scene.layers.push(crossingLayer);
  scene.interactionTargets.push({
    interactionTargetID: "crossing-target",
    layerID: crossingLayer.id,
    hitRegion: rectangularHitRegion(0.54, 0.66, 0.46, 0.54),
    accessibilityElementID: "crossing-action",
  });
  assert.throws(
    () => validateSceneSpec(scene),
    /targets .*overlap or lose the required clearance.*camera rail/,
  );
});

test("rejects target near-contact inside the normalized rail clearance", () => {
  const scene = validContentPackage().scenes[0];
  scene.interactionTargets[0].hitRegion = rectangularHitRegion(0.25, 0.4, 0.55, 0.7);
  const adjacentLayer = structuredClone(scene.layers[0]);
  adjacentLayer.id = "adjacent-layer";
  adjacentLayer.order = 1;
  adjacentLayer.stateVariants = [];
  scene.layers.push(adjacentLayer);
  scene.interactionTargets.push({
    interactionTargetID: "adjacent-target",
    layerID: adjacentLayer.id,
    hitRegion: rectangularHitRegion(0.40000000005, 0.55, 0.55, 0.7),
    accessibilityElementID: "adjacent-action",
  });
  assert.throws(
    () => validateSceneSpec(scene),
    /overlap or lose the required clearance/,
  );
});

test("checks the allocation source across the exact camera rail", () => {
  const payload = validAllocateVisualPackage();
  const scene = payload.scenes[0];
  scene.cameraRail.keyframes = [
    { progress: 0, center: { x: 0.5, y: 0.5 }, scale: 3.95 },
    { progress: 1, center: { x: 0.69, y: 0.5 }, scale: 1.55 },
  ];
  scene.interactionVisualBinding.configuration.resource.hitRegion
    = rectangularHitRegion(0.43, 0.57, 0.46, 0.54);
  for (const destination of scene.interactionVisualBinding.configuration.destinations) {
    destination.transferPath[0] = { x: 0.5, y: 0.5 };
  }
  assert.throws(
    () => validateSceneSpec(scene),
    /source region must remain visible.*complete camera rail/,
  );
});

test("requires safe attached allocation transfer geometry", () => {
  const duplicate = validAllocateVisualPackage();
  const duplicatePath = duplicate.scenes[0].interactionVisualBinding
    .configuration.destinations[0].transferPath;
  duplicatePath.splice(1, 0, structuredClone(duplicatePath[0]));
  assert.throws(
    () => validateSceneSpec(duplicate.scenes[0]),
    /adjacent control points must be distinct/,
  );

  const clipped = validAllocateVisualPackage();
  clipped.scenes[0].interactionVisualBinding.configuration
    .destinations[0].transferPath.splice(1, 0, { x: 0.99, y: 0.7 });
  assert.throws(
    () => validateSceneSpec(clipped.scenes[0]),
    /control point must remain visible/,
  );

  const detached = validAllocateVisualPackage();
  detached.scenes[0].interactionVisualBinding.configuration
    .destinations[0].transferPath[0] = { x: 0.2, y: 0.78 };
  assert.throws(
    () => validateSceneSpec(detached.scenes[0]),
    /must begin in the resource hit region/,
  );

  const escapedLayer = validAllocateVisualPackage();
  escapedLayer.scenes[0].layers.find((layer) => layer.id === "seed-store").frame
    = { x: 0.2, y: 0.5, width: 0.2, height: 0.3 };
  assert.throws(
    () => validateSceneSpec(escapedLayer.scenes[0]),
    /every target point must remain inside its bound layer frame/,
  );
});

test("keeps allocation regions separated in Reduce Motion", () => {
  const payload = validAllocateVisualPackage();
  payload.scenes[0].interactionTargets[0].hitRegion
    = rectangularHitRegion(0.22, 0.42999999995, 0.52, 0.72);
  assert.throws(
    () => validateSceneSpec(payload.scenes[0]),
    /lose the required clearance in Reduce Motion/,
  );
});

test("collects every scene layer, state, mask and Reduce Motion shipping asset", () => {
  const references = collectShippingAssetReferences(validContentPackage());
  for (const assetPath of sceneLayerAssetPaths) {
    assert.deepEqual([...references.get(assetPath)], ["scene-layer"]);
  }
  for (const assetPath of sceneMaskAssetPaths) {
    assert.deepEqual([...references.get(assetPath)], ["scene-mask"]);
  }
  assert.deepEqual([...references.get("audio/narration.m4a")], ["narration"]);
  assert.equal([...references.keys()].some((assetPath) => assetPath.includes("master")), false);
});

test("validates standalone laboratory scenes through the exact public scene gate", () => {
  const scene = validContentPackage().scenes[0];
  assert.equal(validateSceneSpec(scene).id, "aegean-crossing");
  const tiny = structuredClone(scene);
  tiny.interactionTargets[0].hitRegion.path = [
    { x: 0.25, y: 0.65 }, { x: 0.27, y: 0.65 }, { x: 0.26, y: 0.67 },
  ];
  assert.throws(() => validateSceneSpec(tiny), /at least 44 by 44 points/);
});

test("rejects a chapter schema version that differs from its package", () => {
  const payload = validContentPackage();
  payload.chapters[0].schemaVersion.patch = 1;
  assert.throws(() => validatePublicDocument(payload), /must match contentPackage\.schemaVersion/);
});

test("accepts chapter completion carried entirely by authored beat effects", () => {
  const payload = validContentPackage();
  payload.chapters[0].completionEffects = [];
  assert.equal(validatePublicDocument(payload).chapters[0].completionEffects.length, 0);
});

test("rejects globally duplicated effect and cue IDs", () => {
  const duplicateEffect = validContentPackage();
  duplicateEffect.chapters[0].completionEffects[0].id = "effect-route";
  assert.throws(() => validatePublicDocument(duplicateEffect), /duplicate identifier 'effect-route'/);
  const duplicateCue = validContentPackage();
  duplicateCue.audioTimelines.push({ ...duplicateCue.audioTimelines[0], id: "audio-second" });
  assert.throws(() => validatePublicDocument(duplicateCue), /audioTimelines.events.cueID: duplicate/);
});

test("rejects invalid world-effect variant fields", () => {
  const payload = validContentPackage();
  payload.chapters[0].completionEffects[0].sourceID = "private";
  assert.throws(() => validatePublicDocument(payload), /unknown public field/);
});

test("rejects a malformed launch collection", () => {
  const collection = validCollection();
  collection.chapters[0].access = { kind: "entitlement", entitlementID: "launch-complete-work" };
  assert.throws(() => validatePublicDocument(collection), /included chapters must equal/);
});

test("rejects a cost-bearing tool", () => {
  assert.throws(() => validateCostRegistry({
    policyVersion: 1,
    entries: [{ id: "paid", incrementalCostNOK: 1, billingCredentialRequired: true, commercialUse: "allowed", license: "x", source: "x" }],
    unresolvedCapabilities: [],
  }), /incremental cost/);
});

test("cost registry requires typed, exclusive resolution records", () => {
  const missingCategory = validCostRegistry();
  delete missingCategory.entries[0].category;
  assert.throws(() => validateCostRegistry(missingCategory), /entries\[0\]\.category: required/);

  const contradictory = validCostRegistry();
  contradictory.unresolvedCapabilities.push({
    id: "native-image-layer-production",
    category: "image",
    status: "BLOCKED_UNTIL_ZERO_COST_COMMERCIAL_TOOL_PASSES",
    incrementalCostNOKMaximum: 0,
    billingCredentialPermitted: false,
    requiredOutcome: "Produce cleared image layers.",
    releaseGate: "No image ships until the capability passes.",
  });
  assert.throws(() => validateCostRegistry(contradictory), /cannot be both resolved and unresolved/);
});

test("public tree requires referenced offline assets", async () => {
  const { source } = await createPublicSource();
  await assert.doesNotReject(() => validatePublicTree(source));
  const payloadPath = path.join(source, "chapters", "essential-free-v1.json");
  const payload = JSON.parse(await readFile(payloadPath, "utf8"));
  payload.scenes[0].layers[0].assetPath = "assets/missing.heif";
  await writeFile(payloadPath, JSON.stringify(payload));
  await assert.rejects(() => validatePublicTree(source), /missing offline asset/);
});

test("public tree rejects unreferenced and opaque binary payloads", async () => {
  const unreferenced = await createPublicSource();
  await writeFile(path.join(unreferenced.source, "assets", "unused.heif"), Buffer.from("unused"));
  await assert.rejects(
    () => validatePublicTree(unreferenced.source),
    /binary file is not referenced by a typed shipping asset field/,
  );

  const opaque = await createPublicSource();
  await writeFile(path.join(opaque.source, "assets", "opaque.bin"), Buffer.from("opaque"));
  await assert.rejects(
    () => validatePublicTree(opaque.source),
    /file type is not in the public package allowlist/,
  );
});

test("shipping assets require exact cleared backstage provenance", async () => {
  const { temporary, source } = await createPublicSource();
  const files = await validatePublicTree(source);
  const webSourceInventoryPath = path.join(nativeRoot, "blueprint", "source-asset-provenance.json");
  const webSourceInventory = await readJSON(webSourceInventoryPath);
  const eligibleWebSource = webSourceInventory.assets.find(
    (asset) => asset.allowedAsNativeRawMaterial === true,
  );
  const assets = await Promise.all(shippingAssetFixtures.map(async ({ assetPath, role }, index) => {
    const data = await readFile(path.join(source, assetPath));
    const digest = createHash("sha256").update(data).digest("hex");
    return {
      assetPath,
      bytes: data.byteLength,
      sha256: digest,
      sourceLineage: index === 0 ? [{
        lineageType: "WEB_SOURCE_DERIVATIVE",
        sourceID: `web-${eligibleWebSource.sha256.slice(0, 16)}`,
        webSourcePath: eligibleWebSource.localPath,
        bytes: eligibleWebSource.bytes,
        sha256: eligibleWebSource.sha256,
        acknowledgedObligations: [...eligibleWebSource.obligations],
      }] : [{
        lineageType: "GENERATED_ORIGINAL",
        sourceID: `source-fixture-${index}`,
        bytes: data.byteLength,
        sha256: digest,
        rightsBasis: "PROJECT_OWNED",
        license: "Project-owned test fixture",
      }],
      toolLineage: [{ toolID: "test-tool" }],
      shippingRoles: [role],
      metadataPolicy: "STRIPPED_AND_INSPECTED",
      rightsStatus: "COMMERCIAL_USE_CLEARED",
      incrementalCostNOK: 0,
      approvedForShipping: true,
    };
  }));
  const registryPath = path.join(temporary, "asset-provenance.json");
  const costRegistryPath = path.join(temporary, "cost-license.json");
  const costs = validCostRegistry();
  await writeFile(registryPath, JSON.stringify({ schemaVersion: 3, status: "ACTIVE", assets }));
  await writeFile(costRegistryPath, JSON.stringify(costs));
  await assert.rejects(
    () => validateShippingAssetProvenance(source, files, registryPath, costRegistryPath),
    /authoritative web source inventory required/,
  );
  await assert.doesNotReject(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath,
    ),
  );

  const projectSourceRoot = path.join(temporary, "project-sources");
  const authoredNarrationPath = "native/audio/narration/locked-cue.txt";
  const authoredNarration = Buffer.from("Locked narration source bytes.\n");
  await mkdir(path.join(projectSourceRoot, "native", "audio", "narration"), { recursive: true });
  await writeFile(path.join(projectSourceRoot, authoredNarrationPath), authoredNarration);
  const narrationAsset = assets.find(({ shippingRoles }) => shippingRoles.includes("narration"));
  const originalNarrationLineage = narrationAsset.sourceLineage;
  narrationAsset.sourceLineage = [{
    lineageType: "PROJECT_AUTHORED_AUDIO",
    sourceID: "locked-narration-cue",
    sourceKind: "PROJECT_AUDIO_EDIT",
    sourcePath: authoredNarrationPath,
    bytes: authoredNarration.byteLength,
    sha256: createHash("sha256").update(authoredNarration).digest("hex"),
    rightsBasis: "PROJECT_OWNED",
    license: "Project-owned authored audio source",
  }];
  await writeFile(registryPath, JSON.stringify({ schemaVersion: 3, status: "ACTIVE", assets }));
  await assert.rejects(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath,
    ),
    /projectSourceRoot/,
  );
  await assert.doesNotReject(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath, projectSourceRoot,
    ),
  );
  await writeFile(path.join(projectSourceRoot, authoredNarrationPath), Buffer.from("drifted\n"));
  await assert.rejects(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath, projectSourceRoot,
    ),
    /does not match actual project bytes/,
  );
  await writeFile(path.join(projectSourceRoot, authoredNarrationPath), authoredNarration);
  narrationAsset.sourceLineage = originalNarrationLineage;
  await writeFile(registryPath, JSON.stringify({ schemaVersion: 3, status: "ACTIVE", assets }));

  const landscapeDigest = assets[0].sha256;
  assets[0].sha256 = "0".repeat(64);
  await writeFile(registryPath, JSON.stringify({ schemaVersion: 3, status: "ACTIVE", assets }));
  await assert.rejects(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath,
    ),
    /hash or byte count drifted/,
  );

  assets[0].sha256 = landscapeDigest;
  assets[0].toolLineage = [{ toolID: "unknown-tool" }];
  await writeFile(registryPath, JSON.stringify({ schemaVersion: 3, status: "ACTIVE", assets }));
  await assert.rejects(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath,
    ),
    /unknown zero-cost tool 'unknown-tool'/,
  );

  assets[0].toolLineage = [{ toolID: "test-tool" }];
  costs.entries = costs.entries.filter(({ id }) => id !== "native-image-layer-production");
  costs.unresolvedCapabilities.push({
    id: "native-image-layer-production",
    category: "image",
    status: "BLOCKED_UNTIL_ZERO_COST_COMMERCIAL_TOOL_PASSES",
    incrementalCostNOKMaximum: 0,
    billingCredentialPermitted: false,
    requiredOutcome: "Produce cleared native image layers.",
    releaseGate: "No native image layer ships before the capability passes.",
  });
  await writeFile(costRegistryPath, JSON.stringify(costs));
  await writeFile(registryPath, JSON.stringify({ schemaVersion: 3, status: "ACTIVE", assets }));
  await assert.rejects(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath,
    ),
    /required capability 'native-image-layer-production' remains unresolved/,
  );

  await writeFile(costRegistryPath, JSON.stringify(validCostRegistry()));
  const leakedData = Buffer.from("image bytes with research_notes embedded");
  await writeFile(path.join(source, assets[0].assetPath), leakedData);
  assets[0].bytes = leakedData.byteLength;
  assets[0].sha256 = createHash("sha256").update(leakedData).digest("hex");
  await writeFile(registryPath, JSON.stringify({ schemaVersion: 3, status: "ACTIVE", assets }));
  await assert.rejects(
    () => validateShippingAssetProvenance(
      source, files, registryPath, costRegistryPath, webSourceInventoryPath,
    ),
    /contains forbidden backstage metadata 'researchnotes'/,
  );
});

test("public tree cross-checks payload chapter ownership against collection.json", async () => {
  const { source } = await createPublicSource();
  await writeFile(path.join(source, "collection.json"), JSON.stringify(validCollection()));
  await assert.rejects(() => validatePublicTree(source), /payload chapters do not match collection package/);
});

test("rejects public trees without a canonical payload or outside the allowlist", async () => {
  const empty = await mkdtemp(path.join(os.tmpdir(), "long-west-empty-"));
  await writeFile(path.join(empty, "collection.json"), JSON.stringify(validCollection()));
  await assert.rejects(() => validatePublicTree(empty), /at least one ContentPackagePayload/);
  const outside = await mkdtemp(path.join(os.tmpdir(), "long-west-path-"));
  await writeFile(path.join(outside, "notes.json"), JSON.stringify(validContentPackage()));
  await assert.rejects(() => validatePublicTree(outside), /not in the public package allowlist/);
});

test("compiler binds metadata and files, signs with P-256 and verifies the installed tree", async () => {
  const { temporary, source } = await createPublicSource();
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const firstOutput = path.join(temporary, "first-package");
  const secondOutput = path.join(temporary, "second-package");
  const first = await compilePublicPackage(source, firstOutput, compileOptions(privateKey));
  const second = await compilePublicPackage(source, secondOutput, compileOptions(privateKey));
  assert.equal(first.manifestDigest, second.manifestDigest);
  assert.equal(first.minimumRuntime.major, 1);
  assert.equal(first.signature.algorithm, "P-256-SHA256");
  assert.equal(verifyPackageManifest(first, publicKey, "test-signing-key"), true);
  assert.equal((await verifyCompiledPackage(firstOutput, publicKey, "test-signing-key")).packageID, "essential-free-v1");
  const x963 = Buffer.from(publicKeyX963Base64(publicKey), "base64");
  assert.equal(x963.length, 65);
  assert.equal(x963[0], 0x04);
});

test("compiler carries a reviewed save-migration graph into the signed manifest", async () => {
  const { temporary, source } = await createPublicSource();
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const descriptor = await createSaveMigrationDescriptor(temporary);
  const saveMigrations = [{
    id: "save-zero-to-one",
    fromContentVersion: version(0),
    toContentVersion: version(1),
    requiredSaveFormatVersion: 1,
    requiredStateSchemaVersion: 3,
    fields: ["beatIdentity", "narrationAndAudioPosition"],
    worldOwnershipDelta: {
      oldEffectIDs: [], newEffectIDs: [], oldNodeIDs: [],
      newNodeIDs: [], oldTraceIDs: [], newTraceIDs: [],
    },
    implementationSHA256: descriptor.sha256,
  }];
  const saveMigrationDescriptorInventory = [{
    id: "save-zero-to-one",
    path: descriptor.relativePath,
    sha256: descriptor.sha256,
  }];
  const output = path.join(temporary, "migration-package");
  const manifest = await compilePublicPackage(source, output, {
    ...compileOptions(privateKey),
    saveMigrations,
    saveMigrationSupportedSourceVersions: [version(0)],
    saveMigrationDescriptorInventory,
    saveMigrationDescriptorRoot: descriptor.descriptorRoot,
  });
  assert.deepEqual(manifest.saveMigrations, saveMigrations);
  assert.deepEqual(manifest.saveMigrationSupportedSourceVersions, [version(0)]);
  assert.equal(
    manifest.saveMigrationDescriptorInventorySHA256,
    saveMigrationDescriptorInventoryDigest(saveMigrationDescriptorInventory),
  );
  assert.equal(verifyPackageManifest(manifest, publicKey, "test-signing-key"), true);
  assert.deepEqual(
    (await verifyCompiledPackage(output, publicKey, "test-signing-key")).saveMigrations,
    saveMigrations,
  );
});

test("compiler binds migration authority to real backstage descriptor bytes", async () => {
  const { temporary, source } = await createPublicSource();
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const descriptor = await createSaveMigrationDescriptor(temporary);
  const optionsFor = ({
    descriptorRoot = descriptor.descriptorRoot,
    descriptorPath = descriptor.relativePath,
    digest = descriptor.sha256,
    includeDescriptorRoot = true,
  } = {}) => {
    const migration = {
      id: "save-zero-to-one",
      fromContentVersion: version(0),
      toContentVersion: version(1),
      requiredSaveFormatVersion: 1,
      requiredStateSchemaVersion: 3,
      fields: ["beatIdentity"],
      worldOwnershipDelta: {
        oldEffectIDs: [], newEffectIDs: [], oldNodeIDs: [],
        newNodeIDs: [], oldTraceIDs: [], newTraceIDs: [],
      },
      implementationSHA256: digest,
    };
    return {
      ...compileOptions(privateKey),
      saveMigrations: [migration],
      saveMigrationSupportedSourceVersions: [version(0)],
      saveMigrationDescriptorInventory: [{
        id: migration.id,
        path: descriptorPath,
        sha256: digest,
      }],
      ...(includeDescriptorRoot ? { saveMigrationDescriptorRoot: descriptorRoot } : {}),
    };
  };

  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "descriptor-root-absent"),
      optionsFor({ includeDescriptorRoot: false }),
    ),
    /saveMigrationDescriptorRoot: explicit absolute backstage directory required/,
  );

  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "descriptor-file-absent"),
      optionsFor({ descriptorPath: "save-migrations/absent.json" }),
    ),
    /does not exist under the backstage descriptor root/,
  );

  await writeFile(descriptor.descriptorPath, Buffer.from("tampered descriptor\n", "utf8"));
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "descriptor-tampered"),
      optionsFor(),
    ),
    /exact bytes do not match inventory and graph implementation digest/,
  );

  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "descriptor-path-escape"),
      optionsFor({ descriptorPath: "../outside-descriptor.json" }),
    ),
    /safe POSIX package-relative path required/,
  );

  const symlinkRoot = path.join(temporary, "descriptor-root-symlink");
  await symlink(descriptor.descriptorRoot, symlinkRoot);
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "descriptor-root-is-symlink"),
      optionsFor({ descriptorRoot: symlinkRoot }),
    ),
    /real directory required; symbolic links are forbidden/,
  );

  const symlinkDirectoryTarget = path.join(
    temporary,
    "outside-descriptor-directory",
  );
  await mkdir(symlinkDirectoryTarget, { recursive: true });
  const symlinkDirectoryBytes = Buffer.from(
    "outside directory descriptor\n",
    "utf8",
  );
  await writeFile(
    path.join(symlinkDirectoryTarget, "descriptor.json"),
    symlinkDirectoryBytes,
  );
  const symlinkDirectoryRelativePath = "linked-directory/descriptor.json";
  await symlink(
    symlinkDirectoryTarget,
    path.join(descriptor.descriptorRoot, "linked-directory"),
  );
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "descriptor-directory-symlink"),
      optionsFor({
        descriptorPath: symlinkDirectoryRelativePath,
        digest: createHash("sha256")
          .update(symlinkDirectoryBytes)
          .digest("hex"),
      }),
    ),
    /symbolic links are forbidden/,
  );

  const symlinkTarget = path.join(temporary, "outside-descriptor.json");
  const symlinkBytes = Buffer.from("outside descriptor\n", "utf8");
  await writeFile(symlinkTarget, symlinkBytes);
  const symlinkRelativePath = "save-migrations/symlink.json";
  const symlinkPath = path.join(
    descriptor.descriptorRoot,
    ...symlinkRelativePath.split("/"),
  );
  await symlink(symlinkTarget, symlinkPath);
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "descriptor-symlink"),
      optionsFor({
        descriptorPath: symlinkRelativePath,
        digest: createHash("sha256").update(symlinkBytes).digest("hex"),
      }),
    ),
    /symbolic links are forbidden/,
  );
});

test("save-migration graph gate rejects incomplete, ambiguous and implicit source coverage", () => {
  const edge = (id, fromContentVersion, toContentVersion) => ({
    id,
    fromContentVersion,
    toContentVersion,
    requiredSaveFormatVersion: 1,
    requiredStateSchemaVersion: 3,
    fields: ["beatIdentity"],
    worldOwnershipDelta: {
      oldEffectIDs: [], newEffectIDs: [], oldNodeIDs: [],
      newNodeIDs: [], oldTraceIDs: [], newTraceIDs: [],
    },
    implementationSHA256: "c".repeat(64),
  });
  assert.throws(
    () => saveMigrationGraphDigest(
      version(3),
      [version(1)],
      [edge("one-to-two", version(1), version(2))],
    ),
    /no complete path from 1\.0\.0 to 3\.0\.0/,
  );
  assert.throws(
    () => saveMigrationGraphDigest(
      version(3),
      [version(1), version(2)],
      [
        edge("direct-one-to-three", version(1), version(3)),
        edge("one-to-two", version(1), version(2)),
        edge("two-to-three", version(2), version(3)),
      ],
    ),
    /ambiguous paths from 1\.0\.0 to 3\.0\.0/,
  );
  assert.throws(
    () => saveMigrationGraphDigest(
      version(3),
      [version(1), version(2)],
      [edge("one-to-three", version(1), version(3))],
    ),
    /supported sources must exactly equal/,
  );
});

test("save-migration graph requires explicit canonical world ownership", () => {
  const base = {
    id: "world-one-to-two",
    fromContentVersion: version(1),
    toContentVersion: version(2),
    requiredSaveFormatVersion: 1,
    requiredStateSchemaVersion: 3,
    fields: ["cumulativeWorldState"],
    worldOwnershipDelta: {
      oldEffectIDs: [], newEffectIDs: [], oldNodeIDs: [],
      newNodeIDs: [], oldTraceIDs: [], newTraceIDs: [],
    },
    implementationSHA256: "c".repeat(64),
  };
  assert.throws(
    () => saveMigrationGraphDigest(version(2), [version(1)], [base]),
    /requires an explicit old\/new world ownership delta/,
  );
  const missing = structuredClone(base);
  delete missing.worldOwnershipDelta;
  assert.throws(
    () => saveMigrationGraphDigest(version(2), [version(1)], [missing]),
    /worldOwnershipDelta.*(?:required|object required)/,
  );
  const unknownCategory = structuredClone(base);
  unknownCategory.worldOwnershipDelta.newEffectIDs = ["effect-owned-world"];
  unknownCategory.worldOwnershipDelta.oldSettlementIDs = [];
  assert.throws(
    () => saveMigrationGraphDigest(version(2), [version(1)], [unknownCategory]),
    /oldSettlementIDs: unknown field/,
  );
  const unknown = structuredClone(base);
  unknown.worldOwnershipDelta.newEffectIDs = ["not a stable id"];
  assert.throws(
    () => saveMigrationGraphDigest(version(2), [version(1)], [unknown]),
    /canonical stable-ID array required/,
  );
  const undeclared = structuredClone(base);
  undeclared.fields = ["beatIdentity"];
  undeclared.worldOwnershipDelta.newEffectIDs = ["effect-owned-world"];
  assert.throws(
    () => saveMigrationGraphDigest(version(2), [version(1)], [undeclared]),
    /must be empty without cumulativeWorldState/,
  );
});

test("compiler rejects a descriptor inventory which does not exactly match the graph", async () => {
  const { temporary, source } = await createPublicSource();
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const declaration = {
    id: "save-zero-to-one",
    fromContentVersion: version(0),
    toContentVersion: version(1),
    requiredSaveFormatVersion: 1,
    requiredStateSchemaVersion: 3,
    fields: ["beatIdentity"],
    worldOwnershipDelta: {
      oldEffectIDs: [], newEffectIDs: [], oldNodeIDs: [],
      newNodeIDs: [], oldTraceIDs: [], newTraceIDs: [],
    },
    implementationSHA256: "c".repeat(64),
  };
  await assert.rejects(
    () => compilePublicPackage(source, path.join(temporary, "descriptor-mismatch"), {
      ...compileOptions(privateKey),
      saveMigrations: [declaration],
      saveMigrationSupportedSourceVersions: [version(0)],
      saveMigrationDescriptorInventory: [{
        id: declaration.id,
        path: "save-migrations/save-zero-to-one.json",
        sha256: "d".repeat(64),
      }],
    }),
    /does not match its graph implementation digest/,
  );
});

test("integrity material is deterministic, line-based and includes package metadata", () => {
  const manifest = {
    packageID: "essential-free-v1",
    packageVersion: version(2, 1, 3),
    schemaVersion: version(1, 4, 0),
    minimumRuntime: version(1, 2, 0),
    files: [
      { path: "z.bin", bytes: 2, sha256: "b".repeat(64) },
      { path: "a.bin", bytes: 1, sha256: "a".repeat(64) },
    ],
  };
  assert.equal(manifestIntegrityMaterial(manifest), [
    "long-west-package-v1",
    "packageID=essential-free-v1",
    "packageVersion=2.1.3",
    "schemaVersion=1.4.0",
    "minimumRuntime=1.2.0",
    `file=a.bin\t1\t${"a".repeat(64)}`,
    `file=z.bin\t2\t${"b".repeat(64)}`,
    "",
  ].join("\n"));
  assert.equal(
    createHash("sha256").update(manifestIntegrityMaterial(manifest)).digest("hex"),
    "3667b8afd9e0bf04e89e1a6bf89469b5a2ddde1f4ed7ed0301467cc0af8e3de2",
  );
});

test("package manifest integrity binds canonical save-migration graph edges", () => {
  const migration = {
    id: "save-one-to-two",
    fromContentVersion: version(1),
    toContentVersion: version(2),
    requiredSaveFormatVersion: 1,
    requiredStateSchemaVersion: 3,
    fields: [
      "beatIdentity",
      "cameraAndTextAnchors",
      "cumulativeWorldState",
      "interactionState",
      "narrationAndAudioPosition",
    ],
    worldOwnershipDelta: {
      oldEffectIDs: ["effect-old-world"],
      newEffectIDs: ["effect-new-world"],
      oldNodeIDs: ["old-world-node"],
      newNodeIDs: ["new-world-node"],
      oldTraceIDs: ["old-world-trace"],
      newTraceIDs: ["new-world-trace"],
    },
    implementationSHA256: "c".repeat(64),
  };
  const manifest = {
    packageID: "essential-free-v1",
    packageVersion: version(2),
    schemaVersion: version(1),
    minimumRuntime: version(1),
    saveMigrationSupportedSourceVersions: [version(1)],
    saveMigrationDescriptorInventorySHA256: "e".repeat(64),
    saveMigrations: [migration],
    files: [{ path: "payload.json", bytes: 1, sha256: "a".repeat(64) }],
  };
  const material = manifestIntegrityMaterial(manifest);
  assert.match(material, new RegExp(
    `saveMigration=save-one-to-two\\t1\\.0\\.0\\t2\\.0\\.0\\tsave=1\\tstate=3\\tfields=${migration.fields.join(",")}.*implementation=${"c".repeat(64)}`,
  ));
  const tampered = structuredClone(manifest);
  tampered.saveMigrations[0].implementationSHA256 = "d".repeat(64);
  assert.notEqual(
    createHash("sha256").update(material).digest("hex"),
    createHash("sha256").update(manifestIntegrityMaterial(tampered)).digest("hex"),
  );
  const noncanonical = structuredClone(manifest);
  noncanonical.saveMigrations[0].fields.reverse();
  assert.throws(() => manifestIntegrityMaterial(noncanonical), /canonical byte order/);
});

test("manifest validation rejects missing signatures and metadata tampering", async () => {
  const { temporary, source } = await createPublicSource();
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const manifest = await compilePublicPackage(source, path.join(temporary, "package"), compileOptions(privateKey));
  const unsigned = structuredClone(manifest);
  delete unsigned.signature;
  assert.throws(() => validatePackageManifest(unsigned), /signature: required/);
  const tampered = structuredClone(manifest);
  tampered.minimumRuntime.patch = 1;
  assert.throws(() => verifyPackageManifest(tampered, publicKey), /does not bind/);
  const unsorted = structuredClone(manifest);
  unsorted.files.reverse();
  assert.throws(() => validatePackageManifest(unsorted), /sorted by UTF-8 path bytes/);
  const recursive = structuredClone(manifest);
  recursive.files[0].path = "package-manifest.json";
  assert.throws(() => validatePackageManifest(recursive), /manifest cannot inventory itself/);
});

test("signature and file corruption fail closed", async () => {
  const { temporary, source } = await createPublicSource();
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const output = path.join(temporary, "package");
  const manifest = await compilePublicPackage(source, output, compileOptions(privateKey));
  const badSignature = structuredClone(manifest);
  badSignature.signature.value = Buffer.from("not a DER signature").toString("base64");
  assert.throws(() => verifyPackageManifest(badSignature, publicKey));
  await writeFile(path.join(output, "assets", "landscape.heif"), Buffer.from("corrupt"));
  await assert.rejects(() => verifyCompiledPackage(output, publicKey), /size or SHA-256 mismatch/);
});

test("production compile refuses a missing approved blueprint", async () => {
  const { temporary, source } = await createPublicSource();
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const options = compileOptions(privateKey);
  delete options.testOnlyAllowUnapprovedBlueprint;
  await assert.rejects(() => compilePublicPackage(source, path.join(temporary, "package"), options), /blueprintRoot/);
});

test("production launch compiler requires exact Phase 0 and package-specific approval", async (context) => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-production-launch-"));
  context.after(() => rm(temporary, { recursive: true, force: true }));
  const realBlueprintRoot = path.join(nativeRoot, "blueprint");
  const protectedFiles = [...phase0EditorialFileNames, "editor-approval.json"];
  const realBlueprintSnapshot = Object.fromEntries(await Promise.all(
    protectedFiles.map(async (fileName) => [
      fileName,
      await readFile(path.join(realBlueprintRoot, fileName)),
    ]),
  ));

  const approved = await approveTemporaryBlueprint(realBlueprintRoot, temporary);
  const product = await readJSON(path.join(nativeRoot, "product.json"));
  const delivery = await readJSON(path.join(approved.blueprintRoot, "delivery-plan.json"));
  const { source, collection, payload } = await createCanonicalLaunchSource(
    temporary,
    product,
    approved.catalog,
    delivery,
  );
  const registries = await writeClearedProductionRegistries(temporary, source);
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const packageSpec = collection.packages.find(({ id }) => id === "essential-free-v1");
  const baseOptions = {
    packageVersion: packageSpec.version,
    minimumRuntime: packageSpec.minimumRuntime,
    keyID: "production-launch-test-key",
    signingPrivateKey: privateKey,
    blueprintRoot: approved.blueprintRoot,
    launchConfiguration: { product, catalog: approved.catalog, delivery },
    testOnlyAllowUnprojectedPayload: true,
    ...registries,
  };
  assert.equal(Object.hasOwn(baseOptions, "testOnlyAllowUnapprovedBlueprint"), false);
  assert.equal(
    approved.approval.phase0EditorialSHA256,
    phase0EditorialDigest(approved.editorialBytes),
  );

  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "compiled-without-launch-approval"),
      baseOptions,
    ),
    /separate backstage approval record required/,
  );

  const launchApproval = await writeSyntheticLaunchPackageApproval(
    temporary,
    source,
    collection,
    payload,
  );
  assert.equal(validateLaunchPackageApprovalRecord(
    launchApproval.approval,
    collection,
    launchApproval.collectionBytes,
    payload,
    launchApproval.payloadBytes,
    launchApproval.publicSourceInventorySHA256,
    launchApproval.saveMigrationGraphSHA256,
    launchApproval.saveMigrationDescriptorInventorySHA256,
  ), true);
  assert.throws(
    () => validateLaunchPackageApprovalRecord(
      launchApproval.approval,
      collection,
      launchApproval.collectionBytes,
      payload,
      launchApproval.payloadBytes,
      launchApproval.publicSourceInventorySHA256,
      "f".repeat(64),
      launchApproval.saveMigrationDescriptorInventorySHA256,
    ),
    /save-migration authority digest does not match/,
  );
  assert.throws(
    () => validateLaunchPackageApprovalRecord(
      launchApproval.approval,
      collection,
      launchApproval.collectionBytes,
      payload,
      launchApproval.payloadBytes,
      launchApproval.publicSourceInventorySHA256,
      launchApproval.saveMigrationGraphSHA256,
      "f".repeat(64),
    ),
    /save-migration authority digest does not match/,
  );
  const options = {
    ...baseOptions,
    launchPackageApprovalPath: launchApproval.approvalPath,
  };

  const injectedDescriptor = await createSaveMigrationDescriptor(temporary);
  const injectedMigration = {
    id: "save-zero-to-one",
    fromContentVersion: version(0),
    toContentVersion: packageSpec.version,
    requiredSaveFormatVersion: 1,
    requiredStateSchemaVersion: 3,
    fields: ["beatIdentity"],
    worldOwnershipDelta: {
      oldEffectIDs: [], newEffectIDs: [], oldNodeIDs: [],
      newNodeIDs: [], oldTraceIDs: [], newTraceIDs: [],
    },
    implementationSHA256: injectedDescriptor.sha256,
  };
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "compiled-with-unapproved-migration"),
      {
        ...options,
        saveMigrations: [injectedMigration],
        saveMigrationSupportedSourceVersions: [version(0)],
        saveMigrationDescriptorInventory: [{
          id: injectedMigration.id,
          path: injectedDescriptor.relativePath,
          sha256: injectedMigration.implementationSHA256,
        }],
        saveMigrationDescriptorRoot: injectedDescriptor.descriptorRoot,
      },
    ),
    /save-migration authority digest does not match/,
  );

  const wrongApproval = await writeSyntheticLaunchPackageApproval(
    temporary,
    source,
    collection,
    payload,
    {
      approvalPath: path.join(temporary, "backstage", "wrong-package-approval.json"),
      overrides: { packageID: "paid-wave-1" },
    },
  );
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "compiled-with-wrong-package-approval"),
      { ...baseOptions, launchPackageApprovalPath: wrongApproval.approvalPath },
    ),
    /collection or package identity does not match/,
  );

  const payloadPath = path.join(source, "chapters", `${payload.packageID}.json`);
  await writeFile(payloadPath, Buffer.concat([
    launchApproval.payloadBytes,
    Buffer.from("\n"),
  ]));
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "compiled-after-payload-tamper"),
      options,
    ),
    /approved collection, payload, public inventory or save-migration authority digest does not match/,
  );
  await writeFile(payloadPath, launchApproval.payloadBytes);

  const approvedAssetPath = path.join(source, shippingAssetFixtures[0].assetPath);
  const approvedAssetBytes = await readFile(approvedAssetPath);
  await writeFile(approvedAssetPath, Buffer.concat([
    approvedAssetBytes,
    Buffer.from("CODEX_PROVISIONAL_NON_SHIPPING_PRODUCTION_MASTER"),
  ]));
  await assert.rejects(
    () => compilePublicPackage(
      source,
      path.join(temporary, "compiled-after-provisional-asset-tamper"),
      options,
    ),
    /approved collection, payload, public inventory or save-migration authority digest does not match/,
  );
  await writeFile(approvedAssetPath, approvedAssetBytes);

  const insideOutput = path.join(temporary, "compiled-with-inside-approval");
  const insideApproval = path.join(insideOutput, "backstage", "launch-package-approval.json");
  await mkdir(path.dirname(insideApproval), { recursive: true });
  await writeJSON(insideApproval, launchApproval.approval);
  await assert.rejects(
    () => compilePublicPackage(
      source,
      insideOutput,
      { ...baseOptions, launchPackageApprovalPath: insideApproval },
    ),
    /backstage approval cannot be placed in the package output/,
  );

  const output = path.join(temporary, "compiled-essential-launch");
  const manifest = await compilePublicPackage(source, output, options);
  assert.equal(manifest.packageID, "essential-free-v1");
  assert.equal(manifest.signature.algorithm, "P-256-SHA256");
  assert.equal(manifest.files.some(({ path: file }) => file.includes("approval")), false);
  assert.deepEqual(
    [...approved.catalog.freeContentIDs].sort(),
    validEssentialLaunchContentPackage(approved.catalog, delivery).chapters
      .map(({ id }) => id)
      .sort(),
  );
  await assert.doesNotReject(() => verifyCompiledPackage(
    output,
    publicKey,
    options.keyID,
    packageSpec,
  ));

  for (const fileName of protectedFiles) {
    assert.deepEqual(
      await readFile(path.join(realBlueprintRoot, fileName)),
      realBlueprintSnapshot[fileName],
      `production fixture changed native/blueprint/${fileName}`,
    );
  }
});

test("production approval gate rejects any pending contract or arc chapter", () => {
  assert.throws(() => validateBlueprintApprovals(
    { contracts: [{ editorApproval: "APPROVED" }, { editorApproval: "DRAFT_PENDING" }] },
    { chapters: [{ editorApproval: "APPROVED" }] },
  ), /APPROVED required for production/);
  assert.equal(validateBlueprintApprovals(
    { contracts: [{ editorApproval: "APPROVED" }] },
    { chapters: [{ editorApproval: "APPROVED" }] },
  ), true);
});

test("production approval record binds the complete Phase 0 editorial world", () => {
  const contractBytes = Buffer.from("approved contracts\n");
  const arcBytes = Buffer.from("approved arcs\n");
  const editorialFiles = {
    "arc-matrix.json": arcBytes,
    "authored-interaction-effects-01-12.json": Buffer.from("effects 1-12\n"),
    "authored-interaction-effects-13-24.json": Buffer.from("effects 13-24\n"),
    "chapter-catalog.json": Buffer.from("catalog\n"),
    "chapter-contracts.json": contractBytes,
    "interaction-mapping.json": Buffer.from("mapping\n"),
    "world-traces.json": Buffer.from("world\n"),
  };
  const editorialDigest = phase0EditorialDigest(editorialFiles);
  const digest = (value) => createHash("sha256").update(value).digest("hex");
  const approval = {
    schemaVersion: 1,
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T19:00:00Z",
    decisionReference: "codex-task-editor-approval",
    chapterContractsSHA256: digest(contractBytes),
    arcMatrixSHA256: digest(arcBytes),
    phase0EditorialSHA256: editorialDigest,
  };
  assert.equal(validateEditorApprovalRecord(approval, contractBytes, arcBytes, editorialDigest), true);
  assert.throws(
    () => validateEditorApprovalRecord(approval, Buffer.from("changed"), arcBytes, editorialDigest),
    /digest does not match/,
  );
});

test("test-only approval escape never bypasses mandatory P-256 signing", async () => {
  const { temporary, source } = await createPublicSource();
  const options = compileOptions(undefined);
  await assert.rejects(() => compilePublicPackage(source, path.join(temporary, "package"), options), /P-256 private key required/);
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "secp384r1" });
  await assert.rejects(() => compilePublicPackage(source, path.join(temporary, "package-384"), compileOptions(privateKey)), /P-256 key required/);
});

function validIOSPlist() {
  return {
    BAAppGroupID: "group.com.thelongwest.journey.assets",
    BAHasManagedAssetPacks: true,
    BAUsesAppleHosting: true,
    CFBundleDisplayName: "EUROCENTRIC",
    LSRequiresIPhoneOS: true,
    UIBackgroundModes: ["fetch", "remote-notification"],
    UILaunchScreen: {},
    UIRequiredDeviceCapabilities: ["arm64", "metal", "iphone-performance-gaming-tier"],
    UISupportedInterfaceOrientations: ["UIInterfaceOrientationPortrait"],
  };
}

test("accepts the locked native device and orientation contract", () => {
  assert.equal(validateIOSPlist(validIOSPlist(), "EUROCENTRIC").CFBundleDisplayName, "EUROCENTRIC");
});

test("rejects loss of the performance gaming tier", () => {
  const plist = validIOSPlist();
  plist.UIRequiredDeviceCapabilities.pop();
  assert.throws(() => validateIOSPlist(plist, "EUROCENTRIC"), /performance-gaming-tier/);
});

test("rejects landscape support", () => {
  const plist = validIOSPlist();
  plist.UISupportedInterfaceOrientations.push("UIInterfaceOrientationLandscapeLeft");
  assert.throws(() => validateIOSPlist(plist, "EUROCENTRIC"), /portrait only/);
});

test("rejects drift from managed Apple-hosted Background Assets", () => {
  const plist = validIOSPlist();
  plist.BAUsesAppleHosting = false;
  assert.throws(() => validateIOSPlist(plist, "EUROCENTRIC"), /Background Assets/);
});

test("rejects loss of a CloudKit silent-push background mode", () => {
  const plist = validIOSPlist();
  plist.UIBackgroundModes = ["remote-notification"];
  assert.throws(() => validateIOSPlist(plist, "EUROCENTRIC"), /fetch and remote-notification/);
});

function validAppleServiceConfiguration() {
  return {
    appEntitlements: {
      "aps-environment": "development",
      "com.apple.developer.icloud-container-identifiers": [
        "iCloud.com.thelongwest.journey",
      ],
      "com.apple.developer.icloud-services": ["CloudKit"],
      "com.apple.security.application-groups": [
        "group.com.thelongwest.journey.assets",
      ],
    },
    extensionEntitlements: {
      "com.apple.security.application-groups": [
        "group.com.thelongwest.journey.assets",
      ],
    },
    extensionPlist: {
      EXAppExtensionAttributes: {
        EXExtensionPointIdentifier: "com.apple.background-asset-downloader-extension",
      },
    },
  };
}

test("accepts the bound CloudKit, APNs and Background Assets capabilities", () => {
  assert.deepEqual(
    validateAppleServiceConfiguration(validAppleServiceConfiguration()),
    {
      assetAppGroupID: "group.com.thelongwest.journey.assets",
      cloudContainerID: "iCloud.com.thelongwest.journey",
      sourceAPSEnvironment: "development",
    },
  );
});

test("rejects an app-extension asset-group split", () => {
  const configuration = validAppleServiceConfiguration();
  configuration.extensionEntitlements["com.apple.security.application-groups"] = [
    "group.com.thelongwest.journey.wrong",
  ];
  assert.throws(
    () => validateAppleServiceConfiguration(configuration),
    /shared app group drifted/,
  );
});

test("rejects an unknown APNs entitlement environment", () => {
  const configuration = validAppleServiceConfiguration();
  configuration.appEntitlements["aps-environment"] = "staging";
  assert.throws(
    () => validateAppleServiceConfiguration(configuration),
    /aps-environment is missing or invalid/,
  );
});
