import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateHarvestParallaxQA } from "./validate-harvest-parallax-qa.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const reviewPath = path.join(
  repositoryRoot,
  "native/content/backstage/harvest/parallax-halo-qa-v26.review.json",
);
const receiptPath = path.join(
  repositoryRoot,
  "native/content/backstage/harvest/parallax-halo-qa-v26.provisional/receipt.json",
);
const runtimeReceiptPath = path.join(
  repositoryRoot,
  "native/content/backstage/harvest/runtime-metal-parallax-v26.provisional/receipt.json",
);
const [review, receipt, runtimeReceipt] = await Promise.all([
  readFile(reviewPath, "utf8").then(JSON.parse),
  readFile(receiptPath, "utf8").then(JSON.parse),
  readFile(runtimeReceiptPath, "utf8").then(JSON.parse),
]);

test("accepts only the frozen non-shipping restricted Harvest parallax proof", async () => {
  const result = await validateHarvestParallaxQA({ repositoryRoot });
  assert.equal(result.status, "BACKSTAGE_PARALLAX_HALO_PROOF_PARTIAL_PASS");
  assert.equal(result.shippingState, "PROHIBITED");
  assert.deepEqual(result.includedMovingLayers, ["people", "grain", "foreground"]);
  assert.equal(result.reduceMotionChangedPixelCount, 0);
  assert.equal(
    result.runtimeStatus,
    "BACKSTAGE_RUNTIME_METAL_V26_RESTRICTED_PARTIAL_PASS",
  );
  assert.equal(result.simulatorResult, "PASS");
  assert.equal(result.runtimeReduceMotionChangedPixelCount, 0);
});

test("rejects runtime promotion, broadened scope and renderer-boundary drift", async () => {
  const promoted = structuredClone(runtimeReceipt);
  promoted.shippingState = "APPROVED";
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, runtimeReceiptOverride: promoted }),
    /runtime proof must remain a prohibited restricted partial pass/u,
  );

  const broadened = structuredClone(runtimeReceipt);
  broadened.runtimeInputs.alphaMasksBackToFront.push({
    ...broadened.runtimeInputs.alphaMasksBackToFront[0],
    layerID: "destinations",
  });
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, runtimeReceiptOverride: broadened }),
    /runtime moving layers: exact scope drifted/u,
  );

  const framebufferDrift = structuredClone(runtimeReceipt);
  framebufferDrift.runtimePath.productionMTKViewFramebufferOnly = false;
  await assert.rejects(
    validateHarvestParallaxQA({
      repositoryRoot,
      runtimeReceiptOverride: framebufferDrift,
    }),
    /runtime renderer boundary drifted/u,
  );
});

test("rejects runtime frame parity drift and lost authority denials", async () => {
  const parityDrift = structuredClone(runtimeReceipt);
  parityDrift.renderedFrames.reduceMotionChangedPixelCount = 1;
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, runtimeReceiptOverride: parityDrift }),
    /runtime Reduce Motion pixel parity drifted/u,
  );

  const authorityDrift = structuredClone(runtimeReceipt);
  authorityDrift.claimsExcluded = authorityDrift.claimsExcluded.filter(
    (claim) => claim !== "complete layer DAG",
  );
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, runtimeReceiptOverride: authorityDrift }),
    /runtime receipt lost required authority denial: complete layer DAG/u,
  );
});

test("rejects any promotion to shipping or full visual authority", async () => {
  const promoted = structuredClone(review);
  promoted.shippingState = "APPROVED";
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, reviewOverride: promoted }),
    /must remain a non-shipping partial pass/u,
  );

  const broadened = structuredClone(review);
  broadened.authority.mayNotApprove = broadened.authority.mayNotApprove.filter(
    (value) => value !== "COMPLETE_LAYER_DAG",
  );
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, reviewOverride: broadened }),
    /lost required authority denial: COMPLETE_LAYER_DAG/u,
  );
});

test("rejects Reduce Motion drift and any broadened moving-layer scope", async () => {
  const motionDrift = structuredClone(receipt);
  motionDrift.metrics.reduceMotionAgainstV26.changedPixelCount = 1;
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, receiptOverride: motionDrift }),
    /Reduce Motion pixel parity drifted/u,
  );

  const scopeDrift = structuredClone(receipt);
  scopeDrift.construction.testScope.includedMovingLayers.push("destinations");
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, receiptOverride: scopeDrift }),
    /included moving layers: exact scope drifted/u,
  );
});

test("rejects frozen output hash drift before accepting review claims", async () => {
  const hashDrift = structuredClone(receipt);
  hashDrift.outputs["halo-edge-inspection.png"] = "0".repeat(64);
  await assert.rejects(
    validateHarvestParallaxQA({ repositoryRoot, receiptOverride: hashDrift }),
    /frozen output halo-edge-inspection.png: bytes drifted/u,
  );
});
