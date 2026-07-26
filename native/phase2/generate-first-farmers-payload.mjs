import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { validateContentPackagePayload } from "../tooling/src/validate.mjs";
import { validateFirstFarmersDraft } from "./validate-first-farmers-draft.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const scriptDirectory = path.dirname(scriptPath);
const repositoryRoot = path.resolve(scriptDirectory, "../..");
const generatedRoot = path.join(repositoryRoot, "native/phase2/generated");

const draftPath = path.join(
  repositoryRoot,
  "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json",
);
const chapterPath = path.join(generatedRoot, "first-farmers.chapter.json");
const worldSeedPath = path.join(generatedRoot, "first-farmers.world-seed.json");
const harvestFixturePath = path.join(
  repositoryRoot,
  "native/phase1/fixtures/harvest-option-1.scene.json",
);
const harvestResponsiveAudioPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/harvest-responsive-v1/work-object.json",
);
const longhouseResponsiveAudioPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/longhouse-responsive-v1/longhouse-responsive-work-object.json",
);
const continentRemadeResponsiveAudioPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/continent-remade-responsive-v1/continent-remade-responsive-work-object.json",
);
const moreMouthsResponsiveAudioPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/more-mouths-responsive-v1/more-mouths-responsive-work-object.json",
);
const householdCrossesResponsiveAudioPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/household-crosses-responsive-v1/household-crosses-responsive-work-object.json",
);
const threeRecordsResponsiveAudioPath = path.join(
  repositoryRoot,
  "native/audio/score-soundscape/three-records-responsive-v1/three-records-responsive-work-object.json",
);
const payloadPath = path.join(generatedRoot, "first-farmers.content-package.json");
const assetRequirementsPath = path.join(
  generatedRoot,
  "first-farmers.asset-requirements.json",
);
const receiptPath = path.join(generatedRoot, "first-farmers.payload-receipt.json");

const sampleRate = 48_000;
const narrationWordsPerMinute = 138;
const activationRule = "EVERY_PATH_MUST_BE_REPLACED_BY_A_VERIFIED_PACKAGE_ASSET_AND_EVERY_INTERACTIVE_BEAT_MUST_BIND_A_PRODUCTION_AUTHORED_VALIDATED_RESPONSIVE_AUDIO_PROGRAM_BEFORE_COMPILATION";
const allowedHapticSemantics = new Set([
  "contact",
  "drag",
  "resistance",
  "transfer",
  "break",
  "seal",
]);
const legacyHapticAliases = new Map([
  ["material-contact", "contact"],
  ["causal-threshold", "resistance"],
  ["historical-consequence", "seal"],
]);

const serialize = (value) => `${JSON.stringify(value, null, 2)}\n`;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const local = (id, launchEnglish) => ({ id, launchEnglish });
const deepClone = (value) => structuredClone(value);

function baselineCrop() {
  return {
    id: "baseline-393x852",
    viewport: { widthPoints: 393, heightPoints: 852 },
    sourceRect: { x: 0.15, y: 0.15, width: 0.7, height: 0.7 },
    safeTextRegions: [
      {
        id: "narrative-copy",
        rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.2 },
      },
      {
        id: "mechanism-caption",
        rect: { x: 0.12, y: 0.78, width: 0.76, height: 0.12 },
      },
    ],
  };
}

function requirementAssetPath(sceneID, role, filename) {
  return `requirements/first-farmers/scenes/${sceneID}/${role}/${filename}`;
}

function masks(sceneID, layerID, stateID = undefined) {
  const role = stateID ? `states/${layerID}/${stateID}` : `masks/${layerID}`;
  return {
    alphaMaskAssetPath: requirementAssetPath(sceneID, role, "alpha.png"),
    depthMaskAssetPath: requirementAssetPath(sceneID, role, "depth.png"),
    lightMaskAssetPath: requirementAssetPath(sceneID, role, "light.png"),
  };
}

function staticLayer(sceneID, id, order, depth, options = {}) {
  return {
    id,
    order,
    assetPath: requirementAssetPath(sceneID, `layers/${id}`, "master.heif"),
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth,
    opacity: options.opacity ?? 1,
    blendMode: options.blendMode ?? "normal",
    masks: masks(sceneID, id),
    motion: {
      parallaxFactor: options.parallaxFactor ?? 0,
      windResponse: options.windResponse ?? 0,
      focusResponse: options.focusResponse ?? 0,
    },
    stateVariants: [],
  };
}

function statefulLayer(sceneID, id, order, variantIDs) {
  return {
    id,
    order,
    assetPath: requirementAssetPath(sceneID, `layers/${id}`, "base.heif"),
    frame: { x: 0, y: 0, width: 1, height: 1 },
    depth: 0.58 + order * 0.01,
    opacity: 1,
    blendMode: "normal",
    masks: masks(sceneID, id),
    motion: {
      parallaxFactor: 0,
      windResponse: 0,
      focusResponse: 0.7,
    },
    stateVariants: variantIDs.map((variantID) => ({
      id: variantID,
      assetPath: requirementAssetPath(
        sceneID,
        `states/${id}/${variantID}`,
        "master.heif",
      ),
      masks: masks(sceneID, id, variantID),
    })),
  };
}

function region(x, y, width, height) {
  return {
    path: [
      { x, y },
      { x: x + width, y },
      { x: x + width, y: y + height },
      { x, y: y + height },
    ],
  };
}

function distributedRegion(index, count) {
  if (count === 1) return region(0.24, 0.42, 0.52, 0.18);
  if (count === 4) {
    const placements = [
      [0.22, 0.28],
      [0.64, 0.28],
      [0.22, 0.62],
      [0.64, 0.62],
    ];
    const [x, y] = placements[index];
    return region(x, y, 0.14, 0.14);
  }
  const width = 0.13;
  const available = 0.58;
  const gap = (available - width * count) / (count - 1);
  return region(0.21 + index * (width + gap), 0.46, width, 0.15);
}

function distributedAssembleRegion(index, count, y) {
  const width = 0.1;
  if (count === 4) return region(0.2 + index * 0.16, y, width, 0.1);
  const occupiedWidth = count === 1 ? width : 0.58;
  const gap = count === 1 ? 0 : (occupiedWidth - width * count) / (count - 1);
  const x = 0.5 - occupiedWidth / 2 + index * (width + gap);
  return region(x, y, width, 0.1);
}

function target(interactionTargetID, layerID, hitRegion, accessibilityElementID) {
  return {
    interactionTargetID,
    layerID,
    hitRegion,
    accessibilityElementID,
  };
}

function interactionVisualProjection(sceneID, interaction, firstStatefulOrder) {
  if (interaction.grammar === "trace") {
    const layerID = "route-system";
    const interactionTargetID = "trace-route-target";
    const reachedAnchorVariants = interaction.anchors.slice(0, -1).map((anchor) => ({
      anchorID: anchor.id,
      variantID: anchor.reachedVariantID,
    }));
    return {
      layers: [statefulLayer(sceneID, layerID, firstStatefulOrder, [
        "idle",
        "tracing",
        ...reachedAnchorVariants.map(({ variantID }) => variantID),
        "completed",
      ])],
      targets: [target(
        interactionTargetID,
        layerID,
        region(0.2, 0.16, 0.62, 0.66),
        "trace-route",
      )],
      binding: {
        grammar: "trace",
        configuration: {
          interactionID: interaction.id,
          interactionTargetID,
          layerID,
          idleVariantID: "idle",
          tracingVariantID: "tracing",
          reachedAnchorVariants,
          completedVariantID: "completed",
        },
      },
    };
  }

  if (interaction.grammar === "assemble") {
    const layers = [];
    const targets = [];
    const components = [];
    for (const [index, component] of interaction.components.entries()) {
      const layerID = `component-${component.id}`;
      const sourceInteractionTargetID = `component-${component.id}-source`;
      const slotInteractionTargetID = `component-${component.id}-slot`;
      layers.push(statefulLayer(sceneID, layerID, firstStatefulOrder + index, [
        "available",
        "resisted",
        "placed",
      ]));
      targets.push(target(
        sourceInteractionTargetID,
        layerID,
        distributedAssembleRegion(index, interaction.components.length, 0.36),
        `assemble-${component.id}`,
      ));
      targets.push(target(
        slotInteractionTargetID,
        layerID,
        distributedAssembleRegion(index, interaction.components.length, 0.64),
        `assemble-${component.id}`,
      ));
      components.push({
        componentID: component.id,
        sourceInteractionTargetID,
        slotInteractionTargetID,
        layerID,
        availableVariantID: "available",
        resistedVariantID: "resisted",
        placedVariantID: "placed",
      });
    }
    return {
      layers,
      targets,
      binding: {
        grammar: "assemble",
        configuration: { interactionID: interaction.id, components },
      },
    };
  }

  if (interaction.grammar === "transform") {
    const layers = [];
    const targets = [];
    const stages = [];
    for (const [index, stage] of interaction.stages.entries()) {
      const layerID = `stage-${stage.id}`;
      const interactionTargetID = `stage-${stage.id}-target`;
      layers.push(statefulLayer(sceneID, layerID, firstStatefulOrder + index, [
        "before",
        "active",
        "completed",
      ]));
      targets.push(target(
        interactionTargetID,
        layerID,
        distributedRegion(index, interaction.stages.length),
        `transform-${stage.id}`,
      ));
      stages.push({
        stageID: stage.id,
        interactionTargetID,
        layerID,
        beforeVariantID: "before",
        activeVariantID: "active",
        completedVariantID: "completed",
      });
    }
    return {
      layers,
      targets,
      binding: {
        grammar: "transform",
        configuration: { interactionID: interaction.id, stages },
      },
    };
  }

  throw new Error(`No generic visual projection exists for ${interaction.grammar}`);
}

function atmosphereFor(beat) {
  const motion = beat.sceneDirection.livingMotion.join(" ").toLowerCase();
  const sound = beat.sceneDirection.sound.toLowerCase();
  let kind = "dust";
  let velocity = { dx: 0.06, dy: -0.03 };
  if (motion.includes("rain")) {
    kind = "rain";
    velocity = { dx: -0.08, dy: 0.54 };
  } else if (motion.includes("mist") || motion.includes("water") || sound.includes("water")) {
    kind = "mist";
    velocity = { dx: 0.05, dy: 0 };
  } else if (motion.includes("smoke") || sound.includes("hearth")) {
    kind = "smoke";
    velocity = { dx: 0.04, dy: -0.08 };
  }
  return [{
    kind,
    density: 0.18,
    velocity,
    deterministicSeed: Number.parseInt(sha256(beat.sceneID).slice(0, 8), 16),
  }];
}

function genericScene(beat, interaction) {
  const sceneID = beat.sceneID;
  const crop = baselineCrop();
  const baseLayers = [
    staticLayer(sceneID, "far-landscape", 0, 0.08, {
      parallaxFactor: 0.02,
      windResponse: 0.08,
    }),
    staticLayer(sceneID, "inhabited-world", 1, 0.34, {
      parallaxFactor: 0.06,
      focusResponse: 0.12,
    }),
  ];
  const visual = interaction
    ? interactionVisualProjection(sceneID, interaction, baseLayers.length)
    : { layers: [], targets: [], binding: undefined };
  const foregroundOrder = baseLayers.length + visual.layers.length;
  const layers = [
    ...baseLayers,
    ...visual.layers,
    staticLayer(sceneID, "foreground-occlusion", foregroundOrder, 0.91, {
      parallaxFactor: 0.1,
      focusResponse: 0.18,
    }),
    staticLayer(sceneID, "mechanism-light", foregroundOrder + 1, 0.98, {
      opacity: 0.72,
      blendMode: "screen",
      focusResponse: 1,
    }),
  ];
  const statefulLayerIDs = layers
    .filter(({ stateVariants }) => stateVariants.length > 0)
    .map(({ id }) => id);
  const reduceMotionStrata = statefulLayerIDs.length === 0
    ? [{
      id: "static-world",
      kind: "staticPlate",
      assetPath: requirementAssetPath(sceneID, "reduce-motion", "static-world.heif"),
    }]
    : [
      {
        id: "static-underlay",
        kind: "staticPlate",
        assetPath: requirementAssetPath(sceneID, "reduce-motion", "static-underlay.heif"),
      },
      ...statefulLayerIDs.map((layerID) => ({
        id: `${layerID}-state`,
        kind: "stateOverlay",
        layerID,
      })),
      {
        id: "static-foreground",
        kind: "staticPlate",
        assetPath: requirementAssetPath(sceneID, "reduce-motion", "static-foreground.heif"),
      },
    ];
  const mechanism = interaction?.causalContract.visibleMechanism
    ?? beat.sceneDirection.mechanismLight;

  return {
    id: sceneID,
    sceneCanvas: {
      canvas: { width: 1179, height: 2556 },
      cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
      authoredOverscanFraction: 0.15,
      viewportCrops: [crop],
    },
    layers,
    cameraRail: {
      keyframes: [
        { progress: 0, center: { x: 0.5, y: 0.5 }, scale: 1 },
        { progress: 1, center: { x: 0.5, y: 0.5 }, scale: 1.025 },
      ],
    },
    atmosphere: atmosphereFor(beat),
    interactionTargets: visual.targets,
    ...(visual.binding ? { interactionVisualBinding: visual.binding } : {}),
    reduceMotionComposition: {
      canvas: { width: 1179, height: 2556 },
      viewportCrops: [crop],
      strata: reduceMotionStrata,
    },
    mechanismFocus: local(`${sceneID}-mechanism-focus`, mechanism),
    accessibilityID: `accessibility-${beat.beatID}`,
  };
}

function harvestScene(beat, fixture) {
  assert.equal(fixture.status, "NON_SHIPPING_CONTRACT_FIXTURE");
  assert.equal(fixture.shippingState, "PROHIBITED_UNTIL_REBUILT_AND_APPROVED");
  assert.equal(fixture.assetState, "FUTURE_PACKAGE_PATHS_ONLY");
  assert.equal(fixture.scene.id, beat.sceneID);
  assert.equal(fixture.nativeInteractionID, beat.interaction.id);
  const scene = deepClone(fixture.scene);
  scene.accessibilityID = `accessibility-${beat.beatID}`;
  return scene;
}

function action(kind, labelID, launchEnglish, token) {
  return {
    kind,
    label: local(labelID, launchEnglish),
    token,
  };
}

function descriptiveAccessibilityElements(beat, mechanism) {
  return [
    {
      id: "scene-heading",
      role: "heading",
      label: local(`${beat.beatID}-heading`, beat.narrative.heading),
      actions: [],
    },
    ...beat.narrative.segments.map((segment, index) => ({
      id: `narration-${index + 1}`,
      role: "narration",
      label: local(segment.id, segment.text),
      actions: [],
    })),
    {
      id: "historical-mechanism",
      role: "mechanism",
      label: local(`${beat.sceneID}-mechanism-focus`, mechanism),
      actions: [],
    },
  ];
}

function interactionAccessibilityElements(beat) {
  const interaction = beat.interaction;
  if (!interaction) return [];
  if (interaction.grammar === "trace") {
    return [{
      id: "trace-route",
      role: "adjustable",
      label: local(`${beat.beatID}-trace-label`, "The household route"),
      hint: local(
        `${beat.beatID}-trace-hint`,
        "Advance the household through each viable crossing.",
      ),
      actions: [action(
        "increment",
        `${beat.beatID}-trace-next-label`,
        "Advance the household",
        { command: "trace-next" },
      )],
    }];
  }
  if (interaction.grammar === "allocate") {
    const elementIDs = {
      food: "allocate-winter-food",
      reserve: "allocate-protected-reserve",
      seed: "allocate-spring-seed",
    };
    const elements = interaction.destinations.map((destination) => ({
      id: elementIDs[destination.id],
      role: "adjustable",
      label: local(`${beat.beatID}-${destination.id}-label`, destination.title),
      value: local(
        `${beat.beatID}-${destination.id}-value`,
        `Minimum obligation: ${destination.minimumUnits} shares`,
      ),
      actions: [
        action(
          "increment",
          `${beat.beatID}-${destination.id}-increment-label`,
          `Move one share to ${destination.title.toLowerCase()}`,
          { command: "allocate", targetID: destination.id, unitsPerStep: 1 },
        ),
        action(
          "decrement",
          `${beat.beatID}-${destination.id}-decrement-label`,
          `Return one share from ${destination.title.toLowerCase()}`,
          { command: "allocate", targetID: destination.id, unitsPerStep: 1 },
        ),
      ],
    }));
    elements.push({
      id: "commit-allocation",
      role: "action",
      label: local(`${beat.beatID}-commit-label`, "Set the stores"),
      actions: [action(
        "activate",
        `${beat.beatID}-commit-action-label`,
        "Commit the harvest",
        { command: "commit-allocation" },
      )],
    });
    return elements;
  }
  if (interaction.grammar === "assemble") {
    return interaction.components.map((component) => ({
      id: `assemble-${component.id}`,
      role: "action",
      label: local(
        `${beat.beatID}-${component.id}-label`,
        `${component.id.replaceAll("-", " ")} for the ${component.targetSlot.replaceAll("-", " ")}`,
      ),
      actions: [action(
        "activate",
        `${beat.beatID}-${component.id}-place-label`,
        `Place ${component.id.replaceAll("-", " ")}`,
        { command: "place-component", targetID: component.id },
      )],
    }));
  }
  if (interaction.grammar === "transform") {
    return interaction.stages.map((stage) => ({
      id: `transform-${stage.id}`,
      role: "adjustable",
      label: local(
        `${beat.beatID}-${stage.id}-label`,
        stage.id.replaceAll("-", " "),
      ),
      actions: [action(
        "increment",
        `${beat.beatID}-${stage.id}-advance-label`,
        `Advance ${stage.id.replaceAll("-", " ")}`,
        {
          command: "advance-transform",
          targetID: stage.id,
          step: stage.requiredAmount,
        },
      )],
    }));
  }
  throw new Error(`No accessibility projection exists for ${interaction.grammar}`);
}

function accessibilitySpec(beat) {
  const mechanism = beat.interaction?.causalContract.visibleMechanism
    ?? beat.sceneDirection.mechanismLight;
  return {
    id: `accessibility-${beat.beatID}`,
    sceneSummary: local(
      `${beat.beatID}-scene-summary`,
      `${beat.narrative.heading}. ${mechanism}`,
    ),
    elements: [
      ...descriptiveAccessibilityElements(beat, mechanism),
      ...interactionAccessibilityElements(beat),
    ],
  };
}

function normalizeHapticSemantic(value) {
  const normalized = legacyHapticAliases.get(value) ?? value;
  assert.ok(
    allowedHapticSemantics.has(normalized),
    `Unsupported haptic semantic '${value}' in First Farmers draft`,
  );
  return normalized;
}

function hapticProfile(kind) {
  switch (kind) {
    case "contact": return { intensity: 0.36, sharpness: 0.62 };
    case "drag": return { intensity: 0.24, sharpness: 0.26 };
    case "resistance": return { intensity: 0.58, sharpness: 0.34 };
    case "transfer": return { intensity: 0.44, sharpness: 0.48 };
    case "break": return { intensity: 0.72, sharpness: 0.78 };
    case "seal": return { intensity: 0.64, sharpness: 0.52 };
    default: throw new Error(`Missing haptic profile for ${kind}`);
  }
}

function wordCount(text) {
  return text.trim().split(/\s+/u).filter(Boolean).length;
}

function audioTimeline(chapterID, arcID, beat) {
  let narrationCursor = 0;
  const narrationEvents = beat.narrative.segments.map((segment) => {
    const durationSamples = Math.max(
      sampleRate,
      Math.round(wordCount(segment.text) * 60 / narrationWordsPerMinute * sampleRate),
    );
    const event = {
      cueID: `narration-${segment.id}`,
      role: "narration",
      startSample: narrationCursor,
      durationSamples,
      assetPath: `requirements/first-farmers/audio/narration/${segment.id}.m4a`,
      gain: 1,
      narrationBinding: {
        manuscriptSegmentID: segment.id,
        manuscriptSegmentSHA256: sha256(segment.text),
        scope: {
          chapterID,
          arcID,
          beatID: beat.beatID,
        },
      },
    };
    narrationCursor += durationSamples + Math.round(0.35 * sampleRate);
    return event;
  });
  const beatDurationSamples = beat.estimatedSeconds * sampleRate;
  const scoreStart = beat.sceneDirection.sound.toLowerCase()
    .includes("no score for the first twelve seconds") ? 12 * sampleRate : 0;
  const nonNarrationEvents = [
    {
      cueID: `score-${beat.beatID}`,
      role: "score",
      startSample: scoreStart,
      durationSamples: Math.max(0, beatDurationSamples - scoreStart),
      assetPath: `requirements/first-farmers/audio/score/${beat.beatID}.m4a`,
      gain: 0.52,
    },
    {
      cueID: `soundscape-${beat.beatID}`,
      role: "soundscape",
      startSample: 0,
      durationSamples: beatDurationSamples,
      assetPath: `requirements/first-farmers/audio/soundscape/${beat.beatID}.m4a`,
      gain: 0.76,
    },
    {
      cueID: `spatial-detail-${beat.beatID}`,
      role: "spatialDetail",
      startSample: 0,
      durationSamples: beatDurationSamples,
      assetPath: `requirements/first-farmers/audio/spatial-detail/${beat.beatID}.m4a`,
      gain: 0.68,
    },
  ];
  const semantics = (beat.interaction?.haptics ?? []).map(normalizeHapticSemantic);
  const haptics = semantics.map((kind, index) => ({
    sample: Math.round(beatDurationSamples * (index + 1) / (semantics.length + 1)),
    kind,
    ...hapticProfile(kind),
  }));
  return {
    id: `audio-${beat.beatID}`,
    sampleRate,
    events: [...narrationEvents, ...nonNarrationEvents],
    haptics,
  };
}

function placeholderResponsiveTimeline(beat, region, durationSamples) {
  const stem = `responsive-${beat.beatID}-${region}`;
  return {
    id: stem,
    sampleRate,
    events: [
      {
        cueID: `${stem}-score`,
        role: "score",
        startSample: 0,
        durationSamples,
        assetPath: `requirements/first-farmers/audio/responsive/${beat.beatID}/${region}/score-master.wav`,
        gain: 0.5,
      },
      {
        cueID: `${stem}-soundscape`,
        role: "soundscape",
        startSample: 0,
        durationSamples,
        assetPath: `requirements/first-farmers/audio/responsive/${beat.beatID}/${region}/soundscape-master.wav`,
        gain: 0.72,
      },
      {
        cueID: `${stem}-spatial-detail`,
        role: "spatialDetail",
        startSample: 0,
        durationSamples,
        assetPath: `requirements/first-farmers/audio/responsive/${beat.beatID}/${region}/spatial-detail-master.wav`,
        gain: 0.64,
      },
    ],
    haptics: [],
  };
}

function placeholderResponsiveAudio(arcID, beat) {
  const approach = placeholderResponsiveTimeline(beat, "approach", 144_000);
  const waiting = placeholderResponsiveTimeline(beat, "waiting", 96_000);
  const engaged = placeholderResponsiveTimeline(beat, "engaged", 96_000);
  const resistance = placeholderResponsiveTimeline(beat, "resistance", 96_000);
  const consequence = placeholderResponsiveTimeline(beat, "consequence", 144_000);
  return {
    program: {
      id: `responsive-program-${beat.beatID}`,
      scope: {
        chapterID: "first-farmers",
        arcID,
        beatID: beat.beatID,
        interactionID: beat.interaction.id,
      },
      approachTimelineID: approach.id,
      interactionBeds: [
        {
          phase: "waiting",
          timelineID: waiting.id,
          layerStates: {
            scoreStateID: "placeholder-waiting-score",
            soundscapeStateID: "placeholder-waiting-world",
          },
        },
        {
          phase: "engaged",
          timelineID: engaged.id,
          layerStates: {
            scoreStateID: "placeholder-engaged-score",
            soundscapeStateID: "placeholder-engaged-world",
          },
        },
        {
          phase: "resistance",
          timelineID: resistance.id,
          layerStates: {
            scoreStateID: "placeholder-resistance-score",
            soundscapeStateID: "placeholder-resistance-world",
          },
        },
      ],
      consequenceTimelineID: consequence.id,
      exitPolicy: {
        kind: "bounded-fade",
        durationSamples: 9_600,
      },
    },
    timelines: [approach, waiting, engaged, resistance, consequence],
  };
}

function publicResponsiveTimelines(workObject) {
  return deepClone(workObject.timelines).map((timeline) => ({
    ...timeline,
    events: timeline.events.map((event) => {
      const namespacedEvent = {
        ...event,
        cueID: `${workObject.id}-${event.cueID}`,
      };
      if (event.role !== "silence") return namespacedEvent;
      const { assetPath: _nonShippingNull, ...publicEvent } = namespacedEvent;
      return publicEvent;
    }),
  }));
}

function publicResponsiveProgram(workObject) {
  const program = deepClone(workObject.responsiveProgram);
  if (!program.causalMix) return program;
  for (const layer of program.causalMix.layers) {
    for (const phase of ["waiting", "engaged", "resistance"]) {
      layer.cueIDs[phase] = `${workObject.id}-${layer.cueIDs[phase]}`;
    }
  }
  return program;
}

function collectAssetPaths(value, owner = "contentPackage", output = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => collectAssetPaths(item, `${owner}[${index}]`, output));
    return output;
  }
  if (!value || typeof value !== "object") return output;
  for (const [key, item] of Object.entries(value)) {
    const itemOwner = `${owner}.${key}`;
    if (key.toLowerCase().endsWith("assetpath") && typeof item === "string") {
      output.push({ path: item, owner: itemOwner });
    } else {
      collectAssetPaths(item, itemOwner, output);
    }
  }
  return output;
}

function assetRequirements(
  payload,
  harvestFixture,
  harvestResponsiveAudio,
  longhouseResponsiveAudio,
  continentRemadeResponsiveAudio,
  moreMouthsResponsiveAudio,
  householdCrossesResponsiveAudio,
  threeRecordsResponsiveAudio,
) {
  const harvestPaths = new Set(collectAssetPaths(harvestFixture.scene).map((item) => item.path));
  const harvestResponsivePaths = new Set(
    collectAssetPaths(harvestResponsiveAudio.timelines).map((item) => item.path),
  );
  const longhouseResponsivePaths = new Set(
    collectAssetPaths(longhouseResponsiveAudio.timelines).map((item) => item.path),
  );
  const continentRemadeResponsivePaths = new Set(
    collectAssetPaths(continentRemadeResponsiveAudio.timelines).map((item) => item.path),
  );
  const moreMouthsResponsivePaths = new Set(
    collectAssetPaths(moreMouthsResponsiveAudio.timelines).map((item) => item.path),
  );
  const householdCrossesResponsivePaths = new Set(
    collectAssetPaths(householdCrossesResponsiveAudio.timelines).map((item) => item.path),
  );
  const threeRecordsResponsivePaths = new Set(
    collectAssetPaths(threeRecordsResponsiveAudio.timelines).map((item) => item.path),
  );
  const ownersByPath = new Map();
  for (const requirement of collectAssetPaths(payload)) {
    const owners = ownersByPath.get(requirement.path) ?? [];
    owners.push(requirement.owner);
    ownersByPath.set(requirement.path, owners);
  }
  return {
    schemaVersion: 1,
    status: "NON_SHIPPING_FUTURE_ASSET_REQUIREMENTS",
    shippingState: "PROHIBITED",
    packageID: payload.packageID,
    requirements: [...ownersByPath.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([assetPath, owners]) => ({
        assetPath,
        state: "FUTURE_PRODUCTION_ASSET_NOT_PRESENT",
        sourceContract: harvestPaths.has(assetPath)
          ? "HARVEST_PHASE1_CONTRACT"
          : harvestResponsivePaths.has(assetPath)
            ? "HARVEST_RESPONSIVE_AUDIO_WORK_OBJECT"
            : longhouseResponsivePaths.has(assetPath)
              ? "LONGHOUSE_RESPONSIVE_AUDIO_WORK_OBJECT"
              : continentRemadeResponsivePaths.has(assetPath)
                ? "CONTINENT_REMADE_RESPONSIVE_AUDIO_WORK_OBJECT"
                : moreMouthsResponsivePaths.has(assetPath)
                  ? "MORE_MOUTHS_RESPONSIVE_AUDIO_WORK_OBJECT"
                  : householdCrossesResponsivePaths.has(assetPath)
                    ? "HOUSEHOLD_CROSSES_RESPONSIVE_AUDIO_WORK_OBJECT"
                    : threeRecordsResponsivePaths.has(assetPath)
                      ? "THREE_RECORDS_RESPONSIVE_AUDIO_WORK_OBJECT"
                      : "FIRST_FARMERS_PAYLOAD_PROJECTION",
        owners: owners.sort(),
      })),
    activationRule,
  };
}

function assertHarvestSceneReuse(payload, harvestFixture, beat) {
  const projected = payload.scenes.find(({ id }) => id === beat.sceneID);
  assert.ok(projected, "Harvest scene was not projected");
  const expected = deepClone(harvestFixture.scene);
  expected.accessibilityID = `accessibility-${beat.beatID}`;
  assert.deepEqual(
    projected,
    expected,
    "Harvest projection must reuse the validated Phase 1 SceneSpec with only the package accessibility binding rebound",
  );
}

export async function projectedPayloadDocuments() {
  const [
    draftBytes,
    chapterBytes,
    worldSeedBytes,
    harvestFixtureBytes,
    harvestResponsiveAudioBytes,
    longhouseResponsiveAudioBytes,
    continentRemadeResponsiveAudioBytes,
    moreMouthsResponsiveAudioBytes,
    householdCrossesResponsiveAudioBytes,
    threeRecordsResponsiveAudioBytes,
  ] = await Promise.all([
    readFile(draftPath),
    readFile(chapterPath),
    readFile(worldSeedPath),
    readFile(harvestFixturePath),
    readFile(harvestResponsiveAudioPath),
    readFile(longhouseResponsiveAudioPath),
    readFile(continentRemadeResponsiveAudioPath),
    readFile(moreMouthsResponsiveAudioPath),
    readFile(householdCrossesResponsiveAudioPath),
    readFile(threeRecordsResponsiveAudioPath),
  ]);
  const draft = JSON.parse(draftBytes);
  const chapter = JSON.parse(chapterBytes);
  const worldSeed = JSON.parse(worldSeedBytes);
  const harvestFixture = JSON.parse(harvestFixtureBytes);
  const harvestResponsiveAudio = JSON.parse(harvestResponsiveAudioBytes);
  const longhouseResponsiveAudio = JSON.parse(longhouseResponsiveAudioBytes);
  const continentRemadeResponsiveAudio = JSON.parse(continentRemadeResponsiveAudioBytes);
  const moreMouthsResponsiveAudio = JSON.parse(moreMouthsResponsiveAudioBytes);
  const householdCrossesResponsiveAudio = JSON.parse(householdCrossesResponsiveAudioBytes);
  const threeRecordsResponsiveAudio = JSON.parse(threeRecordsResponsiveAudioBytes);
  const authoredResponsiveAudioByBeatID = new Map([
    [harvestResponsiveAudio.scope.beatID, harvestResponsiveAudio],
    [longhouseResponsiveAudio.scope.beatID, longhouseResponsiveAudio],
    [continentRemadeResponsiveAudio.scope.beatID, continentRemadeResponsiveAudio],
    [moreMouthsResponsiveAudio.scope.beatID, moreMouthsResponsiveAudio],
    [householdCrossesResponsiveAudio.scope.beatID, householdCrossesResponsiveAudio],
    [threeRecordsResponsiveAudio.scope.beatID, threeRecordsResponsiveAudio],
  ]);
  await validateFirstFarmersDraft({ repositoryRoot, draft });

  assert.equal(chapter.id, draft.chapterID);
  const chapterBeats = chapter.arcs.flatMap(({ beats }) => beats);
  const draftScopedBeats = draft.arcs.flatMap((arc) => arc.beats.map((beat) => ({
    arcID: arc.arcID,
    beat,
  })));
  assert.deepEqual(
    chapterBeats.map(({ id, sceneID }) => ({ id, sceneID })),
    draftScopedBeats.map(({ beat }) => ({ id: beat.beatID, sceneID: beat.sceneID })),
    "Chapter projection and editor-review dossier must have identical beat and scene order",
  );

  const scenes = [];
  const timelines = [];
  const responsiveAudioPrograms = [];
  const accessibility = [];
  for (const { arcID, beat } of draftScopedBeats) {
    scenes.push(
      beat.sceneID === harvestFixture.scene.id
        ? harvestScene(beat, harvestFixture)
        : genericScene(beat, beat.interaction),
    );
    timelines.push(audioTimeline(draft.chapterID, arcID, beat));
    if (beat.interaction) {
      const authoredResponsiveAudio = authoredResponsiveAudioByBeatID.get(beat.beatID);
      if (authoredResponsiveAudio) {
        assert.equal(authoredResponsiveAudio.status, "PROVISIONAL_NON_SHIPPING");
        assert.equal(authoredResponsiveAudio.shippingState, "PROHIBITED");
        assert.equal(authoredResponsiveAudio.gates.responsiveProgramContract, "PASS_LOCAL_SPEC_VALIDATION_REQUIRED_BY_SWIFT_TEST");
        assert.equal(authoredResponsiveAudio.responsiveProgram.scope.chapterID, draft.chapterID);
        assert.equal(authoredResponsiveAudio.responsiveProgram.scope.arcID, arcID);
        assert.equal(authoredResponsiveAudio.responsiveProgram.scope.beatID, beat.beatID);
        assert.equal(authoredResponsiveAudio.responsiveProgram.scope.interactionID, beat.interaction.id);
        responsiveAudioPrograms.push(publicResponsiveProgram(authoredResponsiveAudio));
        timelines.push(...publicResponsiveTimelines(authoredResponsiveAudio));
      } else {
        const projection = placeholderResponsiveAudio(arcID, beat);
        responsiveAudioPrograms.push(projection.program);
        timelines.push(...projection.timelines);
      }
    }
    accessibility.push(accessibilitySpec(beat));
  }

  const payload = {
    schemaVersion: deepClone(chapter.schemaVersion),
    packageID: "first-farmers-development-v1",
    worldSeed,
    chapters: [chapter],
    scenes,
    audioTimelines: timelines,
    responsiveAudioPrograms,
    accessibility,
  };
  assertHarvestSceneReuse(
    payload,
    harvestFixture,
    draftScopedBeats.find(({ beat }) => beat.sceneID === harvestFixture.scene.id).beat,
  );

  const validationIssues = validateContentPackagePayload(payload);
  assert.deepEqual(
    validationIssues,
    [],
    `Generated First Farmers payload failed canonical validation:\n${validationIssues.join("\n")}`,
  );

  const assetRequirementDocument = assetRequirements(
    payload,
    harvestFixture,
    harvestResponsiveAudio,
    longhouseResponsiveAudio,
    continentRemadeResponsiveAudio,
    moreMouthsResponsiveAudio,
    householdCrossesResponsiveAudio,
    threeRecordsResponsiveAudio,
  );
  const payloadBytes = serialize(payload);
  const assetRequirementBytes = serialize(assetRequirementDocument);
  const manuscriptProjection = draftScopedBeats.flatMap(({ beat }) => beat.narrative.segments)
    .map(({ id, text }) => `${id}\0${text}`)
    .join("\n");
  const narrationEvents = timelines.flatMap(({ events }) => events)
    .filter(({ role }) => role === "narration");
  const visualBindings = scenes.filter(({ interactionVisualBinding }) => interactionVisualBinding);
  const hapticEvents = timelines.flatMap(({ haptics }) => haptics);
  const receipt = {
    schemaVersion: 1,
    status: "NON_SHIPPING_DEVELOPMENT_PAYLOAD_PROJECTION",
    shippingState: "PROHIBITED",
    packageID: payload.packageID,
    sourceBindings: [
      {
        path: path.relative(repositoryRoot, draftPath),
        sha256: sha256(draftBytes),
      },
      {
        path: path.relative(repositoryRoot, chapterPath),
        sha256: sha256(chapterBytes),
      },
      {
        path: path.relative(repositoryRoot, worldSeedPath),
        sha256: sha256(worldSeedBytes),
      },
      {
        path: path.relative(repositoryRoot, harvestFixturePath),
        sha256: sha256(harvestFixtureBytes),
      },
      {
        path: path.relative(repositoryRoot, harvestResponsiveAudioPath),
        sha256: sha256(harvestResponsiveAudioBytes),
      },
      {
        path: path.relative(repositoryRoot, longhouseResponsiveAudioPath),
        sha256: sha256(longhouseResponsiveAudioBytes),
      },
      {
        path: path.relative(repositoryRoot, continentRemadeResponsiveAudioPath),
        sha256: sha256(continentRemadeResponsiveAudioBytes),
      },
      {
        path: path.relative(repositoryRoot, moreMouthsResponsiveAudioPath),
        sha256: sha256(moreMouthsResponsiveAudioBytes),
      },
      {
        path: path.relative(repositoryRoot, householdCrossesResponsiveAudioPath),
        sha256: sha256(householdCrossesResponsiveAudioBytes),
      },
      {
        path: path.relative(repositoryRoot, threeRecordsResponsiveAudioPath),
        sha256: sha256(threeRecordsResponsiveAudioBytes),
      },
    ],
    payloadPath: path.relative(repositoryRoot, payloadPath),
    payloadSHA256: sha256(payloadBytes),
    assetRequirementsPath: path.relative(repositoryRoot, assetRequirementsPath),
    assetRequirementsSHA256: sha256(assetRequirementBytes),
    manuscriptSHA256: sha256(manuscriptProjection),
    assetPathSetSHA256: sha256(
      assetRequirementDocument.requirements.map(({ assetPath }) => assetPath).join("\n"),
    ),
    counts: {
      chapters: payload.chapters.length,
      arcs: chapter.arcs.length,
      beats: chapterBeats.length,
      scenes: scenes.length,
      interactions: chapterBeats.filter(({ interaction }) => interaction).length,
      runtimeVisualBindings: visualBindings.length,
      audioTimelines: timelines.length,
      responsiveAudioPrograms: responsiveAudioPrograms.length,
      provisionalResponsiveAudioPrograms: authoredResponsiveAudioByBeatID.size,
      placeholderResponsiveAudioPrograms: responsiveAudioPrograms.length
        - authoredResponsiveAudioByBeatID.size,
      narrationCues: narrationEvents.length,
      nonNarrationAudioCues: timelines.flatMap(({ events }) => events).length
        - narrationEvents.length,
      hapticEvents: hapticEvents.length,
      accessibilitySpecs: accessibility.length,
      assetRequirements: assetRequirementDocument.requirements.length,
    },
    wireProof: {
      canonicalValidator: "validateContentPackagePayload",
      harvestSceneReuse: "EXACT_PHASE1_SCENE_WITH_ACCESSIBILITY_ID_REBOUND",
      futureAssetState: "INTENTIONALLY_ABSENT_AND_COMPILATION_BLOCKING",
      interactiveAudioState: "SIX_PROVISIONAL_AUTHORED_PROGRAMS_WIRED_WITH_ZERO_REQUIREMENT_PLACEHOLDERS",
      hapticVocabulary: [...allowedHapticSemantics],
    },
    claimsExcluded: [
      "editor approval",
      "shipping approval",
      "finished visual assets",
      "finished narration",
      "finished score",
      "finished soundscape",
      "physical-device proof",
      "content-package activation",
      "finished responsive audio programs",
      "shipping responsive audio integration",
    ],
  };
  return {
    payloadBytes,
    assetRequirementBytes,
    receiptBytes: serialize(receipt),
  };
}

async function checkFile(file, expected) {
  const actual = await readFile(file);
  assert.equal(
    actual.equals(Buffer.from(expected)),
    true,
    `${path.relative(repositoryRoot, file)} drifted; rerun the First Farmers payload generator`,
  );
}

export async function runPayloadGenerator(mode = "write") {
  assert.ok(["write", "--check"].includes(mode), "Use write or --check");
  const projected = await projectedPayloadDocuments();
  if (mode === "--check") {
    await Promise.all([
      checkFile(payloadPath, projected.payloadBytes),
      checkFile(assetRequirementsPath, projected.assetRequirementBytes),
      checkFile(receiptPath, projected.receiptBytes),
    ]);
    process.stdout.write("First Farmers non-shipping payload projection is current.\n");
  } else {
    await Promise.all([
      writeFile(payloadPath, projected.payloadBytes),
      writeFile(assetRequirementsPath, projected.assetRequirementBytes),
      writeFile(receiptPath, projected.receiptBytes),
    ]);
    process.stdout.write("Generated First Farmers non-shipping payload projection.\n");
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  await runPayloadGenerator(process.argv[2] ?? "write");
}
