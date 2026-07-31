#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateSceneSpec } from "../tooling/src/validate.mjs";

const validatorPath = fileURLToPath(import.meta.url);
const phase1Root = path.dirname(validatorPath);
const nativeRoot = path.dirname(phase1Root);
const repositoryRoot = path.dirname(nativeRoot);
const fixturePath = path.join(phase1Root, "fixtures/harvest-option-1.scene.json");
const selectionPath = path.join(nativeRoot, "design/phase1/harvest/selection.json");
const laboratoryPath = path.join(phase1Root, "experience-lab.json");
const futureAssetRoot = "assets/phase1/harvest-option-1/";
const maskFields = [
  "alphaMaskAssetPath",
  "occlusionMaskAssetPath",
  "depthMaskAssetPath",
  "lightMaskAssetPath",
];

const readJSON = async (filePath) => JSON.parse(await readFile(filePath, "utf8"));
const clone = (value) => JSON.parse(JSON.stringify(value));
const maskPaths = (masks) => maskFields.flatMap((field) => masks[field] ? [masks[field]] : []);

function assertViewportContract(scene) {
  const expectedCrops = [
    ["baseline-393x852", 393, 852],
    ["largest-430x932", 430, 932],
  ];
  const normalCrops = scene.sceneCanvas.viewportCrops;
  const reducedCrops = scene.reduceMotionComposition.viewportCrops;

  assert.deepEqual(
    normalCrops.map((crop) => [crop.id, crop.viewport.widthPoints, crop.viewport.heightPoints]),
    expectedCrops,
    "Harvest fixture must author the baseline and largest portrait crops",
  );
  assert.deepEqual(reducedCrops, normalCrops, "Reduce Motion must preserve both authored crops and safe text regions");
  for (const crop of normalCrops) {
    assert.deepEqual(
      crop.safeTextRegions.map(({ id }) => id),
      ["chapter-heading", "allocation-prompt", "remaining-harvest"],
      `${crop.id} safe text contract drifted`,
    );
  }

  const overscan = scene.sceneCanvas.authoredOverscanFraction;
  const travel = scene.sceneCanvas.cameraTravelBounds;
  assert.ok(overscan >= 0.15, "Harvest scene requires at least fifteen percent authored overscan");
  assert.ok(travel.x >= travel.width * overscan, "left camera overscan is insufficient");
  assert.ok(1 - travel.x - travel.width >= travel.width * overscan, "right camera overscan is insufficient");
  assert.ok(travel.y >= travel.height * overscan, "top camera overscan is insufficient");
  assert.ok(1 - travel.y - travel.height >= travel.height * overscan, "bottom camera overscan is insufficient");
  assert.equal(Object.hasOwn(scene.sceneCanvas, "assetPath"), false, "the backstage composition master cannot become a shipping asset");
}

function assertLayerAndVariantContract(fixture) {
  const { scene, interactionContract } = fixture;
  const expectedLayerIDs = [
    "storm-sky",
    "farming-landscape",
    "settlement",
    "people-and-work",
    "allocation-ground",
    "winter-store",
    "protected-reserve",
    "spring-seed",
    "central-harvest",
    "hands-and-grain",
    "foreground-occluders",
    "mechanism-light",
  ];
  assert.deepEqual(scene.layers.map(({ id }) => id), expectedLayerIDs, "ordered Harvest layer inventory drifted");
  assert.deepEqual(scene.layers.map(({ order }) => order), expectedLayerIDs.map((_, index) => index), "layer order must remain explicit and contiguous");

  const requiredVariants = new Map([
    ["winter-store", ["empty", "receiving", "provisioned"]],
    ["protected-reserve", ["empty", "receiving", "sealed"]],
    ["spring-seed", ["empty", "receiving", "committed"]],
    ["central-harvest", ["full", "reduced", "scarce", "exhausted"]],
  ]);
  const layerByID = new Map(scene.layers.map((layer) => [layer.id, layer]));
  for (const [layerID, variantIDs] of requiredVariants) {
    assert.deepEqual(layerByID.get(layerID)?.stateVariants.map(({ id }) => id), variantIDs, `${layerID} state contract drifted`);
  }
  for (const [layerID, variantID] of Object.entries(interactionContract.initialLayerVariants)) {
    assert.ok(layerByID.get(layerID)?.stateVariants.some(({ id }) => id === variantID), `missing initial state ${layerID}.${variantID}`);
  }
  for (const [layerID, variantID] of Object.entries(interactionContract.completionLayerVariants)) {
    assert.ok(layerByID.get(layerID)?.stateVariants.some(({ id }) => id === variantID), `missing completion state ${layerID}.${variantID}`);
  }

  const assetPaths = [];
  for (const layer of scene.layers) {
    const layerMasks = maskPaths(layer.masks);
    assert.ok(layerMasks.length > 0, `${layer.id} requires an authored mask inventory`);
    assetPaths.push(layer.assetPath, ...layerMasks);
    for (const variant of layer.stateVariants) {
      const variantMasks = maskPaths(variant.masks);
      assert.ok(variantMasks.length > 0, `${layer.id}.${variant.id} requires its own mask inventory`);
      assetPaths.push(variant.assetPath, ...variantMasks);
    }
  }
  assetPaths.push(
    ...scene.reduceMotionComposition.strata
      .filter(({ kind }) => kind === "staticPlate")
      .map(({ assetPath }) => assetPath),
  );
  assert.ok(assetPaths.every((assetPath) => assetPath.startsWith(futureAssetRoot)), "fixture asset paths must remain inside the future Harvest package root");
  assert.equal(new Set(assetPaths).size, assetPaths.length, "future Harvest asset paths must be unambiguous");
}

function assertInteractionContract(fixture) {
  const { scene, interactionContract } = fixture;
  assert.equal(interactionContract.grammar, "allocate", "Harvest must remain an Allocate interaction");
  assert.equal(interactionContract.totalUnits, 12, "the established Harvest interaction must retain twelve runtime shares");
  assert.equal(
    interactionContract.unitSemantics,
    "EQUAL_ILLUSTRATIVE_RUNTIME_SHARES_NOT_HISTORICAL_MEASUREMENT",
    "Harvest runtime shares cannot become a historical measurement claim",
  );
  assert.equal(
    interactionContract.interactionSpecApproval,
    "SEPARATE_EDITOR_APPROVAL_REQUIRED",
    "the laboratory fixture cannot approve the final InteractionSpec",
  );
  assert.deepEqual(
    scene.interactionTargets.map(({ interactionTargetID }) => interactionTargetID),
    interactionContract.directTargetIDs,
    "the three selected direct destinations drifted",
  );
  assert.deepEqual(
    scene.interactionTargets.map(({ layerID, accessibilityElementID }) => [layerID, accessibilityElementID]),
    [
      ["winter-store", "allocate-winter-food"],
      ["protected-reserve", "allocate-protected-reserve"],
      ["spring-seed", "allocate-spring-seed"],
    ],
    "Harvest target bindings drifted",
  );

  const crops = [
    ...scene.sceneCanvas.viewportCrops,
    ...scene.reduceMotionComposition.viewportCrops,
  ];
  const targetBounds = scene.interactionTargets.map((target) => {
    const xs = target.hitRegion.path.map(({ x }) => x);
    const ys = target.hitRegion.path.map(({ y }) => y);
    return {
      id: target.interactionTargetID,
      minX: Math.min(...xs),
      maxX: Math.max(...xs),
      minY: Math.min(...ys),
      maxY: Math.max(...ys),
    };
  });
  for (const bounds of targetBounds) {
    for (const crop of crops) {
      const widthPoints = (bounds.maxX - bounds.minX) / crop.sourceRect.width
        * crop.viewport.widthPoints;
      const heightPoints = (bounds.maxY - bounds.minY) / crop.sourceRect.height
        * crop.viewport.heightPoints;
      assert.ok(widthPoints >= 44 && heightPoints >= 44, `${bounds.id} is smaller than 44 points in ${crop.id}`);
    }
  }
  for (let leftIndex = 0; leftIndex < targetBounds.length; leftIndex += 1) {
    for (let rightIndex = leftIndex + 1; rightIndex < targetBounds.length; rightIndex += 1) {
      const left = targetBounds[leftIndex];
      const right = targetBounds[rightIndex];
      const boundsOverlap = left.minX < right.maxX && right.minX < left.maxX
        && left.minY < right.maxY && right.minY < left.maxY;
      assert.equal(boundsOverlap, false, `${left.id} and ${right.id} hit bounds overlap`);
      const horizontalGap = Math.max(left.minX, right.minX) - Math.min(left.maxX, right.maxX);
      assert.ok(horizontalGap > 0, `${left.id} and ${right.id} require a visible gap`);
      for (const crop of crops) {
        const gapPoints = horizontalGap / crop.sourceRect.width * crop.viewport.widthPoints;
        assert.ok(gapPoints >= 12, `${left.id} and ${right.id} are separated by less than 12 points in ${crop.id}`);
      }
    }
  }
}

function assertVisualBindingContract(fixture) {
  const { scene, interactionContract, nativeInteractionID } = fixture;
  const binding = scene.interactionVisualBinding;
  assert.equal(binding.grammar, "allocate", "Harvest visual binding must remain Allocate");
  assert.equal(binding.configuration.interactionID, nativeInteractionID, "visual state must bind the selected native interaction");
  assert.equal(binding.configuration.resource.layerID, "central-harvest", "finite harvest must remain the visual resource");
  assert.equal(
    binding.configuration.resource.hitTest,
    "selectedVariantAlpha",
    "contact must resolve against the selected harvest silhouette",
  );
  assert.deepEqual(binding.configuration.resource.hitRegion.path, [
    { x: 0.27, y: 0.69 },
    { x: 0.73, y: 0.69 },
    { x: 0.79, y: 0.84 },
    { x: 0.69, y: 0.875 },
    { x: 0.31, y: 0.875 },
    { x: 0.21, y: 0.84 },
  ], "the direct source region must remain on visible foreground grain");
  assert.equal(binding.configuration.transferLayerID, "hands-and-grain", "direct transfer must remain bound to authored hands and grain");
  const layerByID = new Map(scene.layers.map((layer) => [layer.id, layer]));
  assert.equal(
    layerByID.get(binding.configuration.resource.layerID)?.motion.windResponse,
    0,
    "the direct resource cannot drift under wind",
  );
  assert.equal(
    layerByID.get(binding.configuration.transferLayerID)?.motion.windResponse,
    0,
    "carried grain cannot drift away from its authored path",
  );
  assert.deepEqual(
    binding.configuration.resource.variantsByRemainingUnits,
    [
      { maximumRemainingUnits: 0, variantID: "exhausted" },
      { maximumRemainingUnits: 4, variantID: "scarce" },
      { maximumRemainingUnits: 8, variantID: "reduced" },
      { maximumRemainingUnits: 12, variantID: "full" },
    ],
    "resource depletion thresholds drifted",
  );
  assert.equal(
    binding.configuration.resource.variantsByRemainingUnits.at(-1).maximumRemainingUnits,
    interactionContract.totalUnits,
    "visual resource thresholds must consume the complete illustrative runtime store",
  );
  assert.deepEqual(
    binding.configuration.destinations.map(({ destinationID, interactionTargetID, layerID }) => [
      destinationID,
      interactionTargetID,
      layerID,
    ]),
    [
      ["food", "winter-food-target", "winter-store"],
      ["reserve", "protected-reserve-target", "protected-reserve"],
      ["seed", "spring-seed-target", "spring-seed"],
    ],
    "allocation destination visual bindings drifted",
  );
  for (const destination of binding.configuration.destinations) {
    assert.deepEqual(destination.transferPath[0], { x: 0.5, y: 0.74 }, `${destination.destinationID} transfer must begin in visible grain`);
    assert.ok(destination.transferPath.length >= 2, `${destination.destinationID} requires an authored material path`);
    assert.equal(
      layerByID.get(destination.layerID)?.motion.windResponse,
      0,
      `${destination.destinationID} cannot move away from its transfer endpoint under wind`,
    );
    for (let index = 1; index < destination.transferPath.length; index += 1) {
      assert.notDeepEqual(
        destination.transferPath[index],
        destination.transferPath[index - 1],
        `${destination.destinationID} cannot contain coincident transfer points`,
      );
    }
  }
  assert.deepEqual(scene.reduceMotionComposition.strata, [
    {
      id: "world-underlay",
      kind: "staticPlate",
      assetPath: "assets/phase1/harvest-option-1/reduce-motion/harvest-allocation-static-underlay.heif",
    },
    { id: "winter-store-state", kind: "stateOverlay", layerID: "winter-store" },
    { id: "protected-reserve-state", kind: "stateOverlay", layerID: "protected-reserve" },
    { id: "spring-seed-state", kind: "stateOverlay", layerID: "spring-seed" },
    { id: "central-harvest-state", kind: "stateOverlay", layerID: "central-harvest" },
    {
      id: "foreground-occlusion",
      kind: "staticPlate",
      assetPath: "assets/phase1/harvest-option-1/reduce-motion/harvest-allocation-static-foreground.heif",
    },
  ], "Reduce Motion must preserve causal layers between authored underlay and foreground occlusion");
}

function assertMotionContract(scene) {
  const keyframes = scene.cameraRail.keyframes;
  assert.equal(keyframes[0].progress, 0, "camera rail must start at zero");
  assert.equal(keyframes.at(-1).progress, 1, "camera rail must end at one");
  assert.equal(keyframes.length, 4, "Harvest camera rail requires its four authored beats");
  const totalCameraTravel = keyframes.slice(1).reduce((distance, keyframe, index) => {
    const previous = keyframes[index];
    return distance + Math.hypot(
      keyframe.center.x - previous.center.x,
      keyframe.center.y - previous.center.y,
    );
  }, 0);
  assert.ok(totalCameraTravel <= 0.12, "Harvest camera centre travel exceeds the twelve-percent laboratory limit");
  assert.ok(Math.max(...keyframes.map(({ scale }) => scale)) <= 1.08, "Harvest camera zoom exceeds the restrained 1.08 laboratory limit");
  const railOrigin = keyframes[0].center;
  for (const crop of scene.sceneCanvas.viewportCrops) {
    for (const layer of scene.layers) {
      const worstDisplacement = Math.max(...keyframes.map(({ center }) => Math.hypot(
        (center.x - railOrigin.x) / crop.sourceRect.width * crop.viewport.widthPoints,
        (center.y - railOrigin.y) / crop.sourceRect.height * crop.viewport.heightPoints,
      ) * Math.abs(layer.motion.parallaxFactor)));
      assert.ok(
        worstDisplacement <= 24,
        `${layer.id} parallax exceeds 24 points in ${crop.id}`,
      );
    }
  }
  assert.deepEqual(scene.atmosphere.map(({ kind }) => kind), ["rain", "smoke"], "Harvest atmosphere must remain rain and hearth smoke");
  assert.equal(new Set(scene.atmosphere.map(({ deterministicSeed }) => deterministicSeed)).size, 2, "rain and smoke require distinct deterministic seeds");

  const dynamicAssets = new Set(scene.layers.flatMap((layer) => [
    layer.assetPath,
    ...layer.stateVariants.map(({ assetPath }) => assetPath),
  ]));
  const staticAssets = scene.reduceMotionComposition.strata
    .filter(({ kind }) => kind === "staticPlate")
    .map(({ assetPath }) => assetPath);
  assert.ok(
    staticAssets.every((assetPath) => !dynamicAssets.has(assetPath)),
    "Reduce Motion static strata require independent assets",
  );
}

function assertSceneGateFailsClosed(scene) {
  const insufficientOverscan = clone(scene);
  insufficientOverscan.sceneCanvas.authoredOverscanFraction = 0.149;
  assert.throws(() => validateSceneSpec(insufficientOverscan), /must be between 0.15 and 0.5/);

  const tinyTarget = clone(scene);
  tinyTarget.interactionTargets[0].hitRegion.path = [
    { x: 0.2, y: 0.5 },
    { x: 0.21, y: 0.5 },
    { x: 0.21, y: 0.51 },
    { x: 0.2, y: 0.51 },
  ];
  assert.throws(() => validateSceneSpec(tinyTarget), /at least 44 by 44 points/);

  const missingReducedCrop = clone(scene);
  missingReducedCrop.reduceMotionComposition.viewportCrops.pop();
  assert.throws(() => validateSceneSpec(missingReducedCrop), /must match the normal crop IDs and viewport dimensions/);

  const missingForegroundStratum = clone(scene);
  missingForegroundStratum.reduceMotionComposition.strata.pop();
  assert.throws(() => validateSceneSpec(missingForegroundStratum), /static underlay and foreground strata/);

  const remoteVariantMask = clone(scene);
  remoteVariantMask.layers.find(({ id }) => id === "central-harvest")
    .stateVariants[0].masks.alphaMaskAssetPath = "../central-harvest-alpha.png";
  assert.throws(() => validateSceneSpec(remoteVariantMask), /package-relative asset path required/);

  const shippingMaster = clone(scene);
  shippingMaster.sceneCanvas.assetPath = "assets/phase1/harvest-option-1/master.heif";
  assert.throws(() => validateSceneSpec(shippingMaster), /unknown public field/);
}

export async function validateHarvestFixture() {
  const [fixture, selection, laboratory] = await Promise.all([
    readJSON(fixturePath),
    readJSON(selectionPath),
    readJSON(laboratoryPath),
  ]);
  assert.equal(fixture.fixtureSchemaVersion, 1, "unsupported Harvest fixture schema");
  assert.equal(fixture.status, "NON_SHIPPING_CONTRACT_FIXTURE", "Harvest fixture cannot become an approval record");
  assert.equal(fixture.role, "PHASE1_HARVEST_LABORATORY", "Harvest fixture escaped the laboratory");
  assert.equal(fixture.shippingState, "PROHIBITED_UNTIL_REBUILT_AND_APPROVED", "Harvest fixture cannot become shipping content");
  assert.equal(fixture.assetState, "FUTURE_PACKAGE_PATHS_ONLY", "Harvest fixture cannot claim nonexistent assets");
  assert.equal(fixture.selectedOption, 1, "Harvest fixture must encode selected option 1");
  assert.equal(path.resolve(repositoryRoot, fixture.selectionReference), selectionPath, "Harvest selection reference drifted");

  const selectedLaboratoryScene = laboratory.scenes.find(({ selectedVisual }) => selectedVisual);
  assert.ok(selectedLaboratoryScene, "the laboratory has no selected Harvest scene");
  for (const field of ["contentID", "arcID", "movementID", "nativeInteractionID"]) {
    assert.equal(fixture[field], selection[field], `Harvest fixture ${field} disagrees with the selected direction`);
    assert.equal(fixture[field], selectedLaboratoryScene[field], `Harvest fixture ${field} disagrees with the laboratory`);
  }

  assert.equal(validateSceneSpec(fixture.scene, "harvestFixture.scene"), fixture.scene);
  assertViewportContract(fixture.scene);
  assertLayerAndVariantContract(fixture);
  assertInteractionContract(fixture);
  assertVisualBindingContract(fixture);
  assertMotionContract(fixture.scene);
  assertSceneGateFailsClosed(fixture.scene);

  return {
    sceneID: fixture.scene.id,
    cropCount: fixture.scene.sceneCanvas.viewportCrops.length,
    layerCount: fixture.scene.layers.length,
    targetCount: fixture.scene.interactionTargets.length,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === validatorPath) {
  const result = await validateHarvestFixture();
  process.stdout.write(`Harvest contract fixture valid: ${result.sceneID}, ${result.cropCount} crops, ${result.layerCount} layers, ${result.targetCount} direct targets.\n`);
}
