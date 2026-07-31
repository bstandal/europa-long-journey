#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { forbiddenReleaseBasenames } from "./validate-release-app-boundary.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultRepositoryRoot = path.resolve(scriptDirectory, "../..");
const backstageRoot = "native/content/backstage/harvest";

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function exactSet(actual, expected, label) {
  requireCondition(Array.isArray(actual), `${label}: array required`);
  requireCondition(
    JSON.stringify([...actual].sort()) === JSON.stringify([...expected].sort()),
    `${label}: exact scope drifted`,
  );
}

async function readBound(repositoryRoot, relativePath, expectedHash, label) {
  requireCondition(/^[a-f0-9]{64}$/u.test(expectedHash), `${label}: SHA-256 required`);
  const bytes = await readFile(path.join(repositoryRoot, relativePath));
  requireCondition(sha256(bytes) === expectedHash, `${label}: bytes drifted`);
  return bytes;
}

export async function validateHarvestParallaxQA({
  repositoryRoot = defaultRepositoryRoot,
  reviewOverride,
  receiptOverride,
  runtimeReceiptOverride,
} = {}) {
  const reviewPath = `${backstageRoot}/parallax-halo-qa-v26.review.json`;
  const reviewBytes = await readFile(path.join(repositoryRoot, reviewPath));
  const review = reviewOverride ?? JSON.parse(reviewBytes);
  requireCondition(review.schemaVersion === 1, "review schema drifted");
  requireCondition(
    review.status === "BACKSTAGE_PARALLAX_HALO_PROOF_PARTIAL_PASS"
      && review.shippingState === "PROHIBITED",
    "review must remain a non-shipping partial pass",
  );
  requireCondition(
    review.source.sha256 === "e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca"
      && JSON.stringify(review.source.pixelSize) === JSON.stringify([1290, 2796]),
    "review source authority drifted",
  );

  await readBound(
    repositoryRoot,
    review.source.path,
    review.source.sha256,
    "v26 source",
  );
  await readBound(
    repositoryRoot,
    review.specification.path,
    review.specification.sha256,
    "QA specification",
  );
  await readBound(
    repositoryRoot,
    review.builder.path,
    review.builder.sha256,
    "QA builder",
  );

  const receiptBytes = await readBound(
    repositoryRoot,
    review.frozenProof.receiptPath,
    review.frozenProof.receiptSha256,
    "frozen QA receipt",
  );
  const receipt = receiptOverride ?? JSON.parse(receiptBytes);
  requireCondition(
    receipt.status === "BACKSTAGE_COMBINED_VISUAL_QA_REQUIRES_CODEX_REVIEW"
      && receipt.shippingState === "PROHIBITED",
    "frozen receipt cannot claim visual or shipping authority",
  );
  requireCondition(
    receipt.specification.sha256 === review.specification.sha256
      && receipt.builder.sha256 === review.builder.sha256,
    "receipt implementation binding drifted",
  );

  const frozenDirectory = review.frozenProof.directory;
  for (const [name, expectedHash] of Object.entries(receipt.outputs)) {
    await readBound(repositoryRoot, `${frozenDirectory}/${name}`, expectedHash, `frozen output ${name}`);
  }

  exactSet(
    receipt.construction.testScope.includedMovingLayers,
    ["people", "grain", "foreground"],
    "included moving layers",
  );
  exactSet(
    receipt.construction.testScope.excludedAfterRejectedDiagnostic,
    ["winter-food-vessel", "protected-reserve-bin", "spring-seed-store"],
    "rejected destination scope",
  );
  exactSet(
    receipt.construction.testScope.excludedPendingProductionCleanPlate,
    ["settlement-shelter", "allocation-cloth"],
    "unproven clean-plate scope",
  );
  exactSet(
    review.passedScope.map(({ layer }) => layer),
    ["people", "grain", "foreground"],
    "reviewed passing scope",
  );

  const reduceMotion = receipt.metrics.reduceMotionAgainstV26;
  requireCondition(
    reduceMotion.changedPixelCount === 0
      && reduceMotion.changedPixelFraction === 0
      && reduceMotion.maximumChannelDifference === 0
      && reduceMotion.meanAbsoluteChannelDifference === 0,
    "Reduce Motion pixel parity drifted",
  );
  requireCondition(
    receipt.outputs["v26-reference-crop.png"]
      === receipt.outputs["reduce-motion-static-crop.png"]
      && review.reduceMotion.referenceSha256 === receipt.outputs["v26-reference-crop.png"]
      && review.reduceMotion.reduceMotionSha256 === receipt.outputs["reduce-motion-static-crop.png"],
    "Reduce Motion and reference bytes must remain identical",
  );
  requireCondition(
    receipt.metrics.positiveAgainstNegativeParallax.changedPixelCount > 0,
    "parallax extrema must retain a measurable visual signal",
  );

  const requiredReceiptDenials = [
    "CLEAN_PLATE",
    "LAYER_DAG",
    "STATE_VARIANT",
    "PRODUCTION_MASTER",
    "SHIPPING_ASSET",
  ];
  for (const denial of requiredReceiptDenials) {
    requireCondition(
      receipt.authorityLimits.mayNotApprove.includes(denial),
      `receipt lost required authority denial: ${denial}`,
    );
  }
  for (const denial of [
    "CLEAN_PLATE",
    "COMPLETE_LAYER_DAG",
    "STATE_VARIANT",
    "PRODUCTION_MASTER",
    "RUNTIME_RENDERER",
    "SHIPPING_ASSET",
  ]) {
    requireCondition(
      review.authority.mayNotApprove.includes(denial),
      `review lost required authority denial: ${denial}`,
    );
  }
  requireCondition(
    review.deterministicReplay.allFilesByteIdentical === true
      && review.deterministicReplay.firstReceiptSha256
        === review.deterministicReplay.replayReceiptSha256
      && review.deterministicReplay.firstReceiptSha256 === review.frozenProof.receiptSha256,
    "deterministic replay evidence drifted",
  );

  const reviewSidecar = await readFile(
    path.join(repositoryRoot, `${backstageRoot}/parallax-halo-qa-v26.review.sha256`),
    "utf8",
  );
  requireCondition(
    reviewSidecar.trim() === `${sha256(reviewBytes)}  parallax-halo-qa-v26.review.json`,
    "review sidecar drifted",
  );

  const runtimeDirectory = `${backstageRoot}/runtime-metal-parallax-v26.provisional`;
  const runtimeReceiptPath = `${runtimeDirectory}/receipt.json`;
  const runtimeReceiptBytes = await readFile(
    path.join(repositoryRoot, runtimeReceiptPath),
  );
  const runtimeReceipt = runtimeReceiptOverride ?? JSON.parse(runtimeReceiptBytes);
  requireCondition(
    runtimeReceipt.schemaVersion === 1
      && runtimeReceipt.status
        === "BACKSTAGE_RUNTIME_METAL_V26_RESTRICTED_PARTIAL_PASS"
      && runtimeReceipt.shippingState === "PROHIBITED",
    "runtime proof must remain a prohibited restricted partial pass",
  );
  requireCondition(
    runtimeReceipt.sourceAuthority.reviewSha256 === sha256(reviewBytes)
      && runtimeReceipt.sourceAuthority.frozenProofReceiptSha256
        === review.frozenProof.receiptSha256,
    "runtime proof source authority drifted",
  );
  await readBound(
    repositoryRoot,
    runtimeReceipt.signedDevelopmentFixture.manifestPath,
    runtimeReceipt.signedDevelopmentFixture.manifestSha256,
    "runtime fixture manifest",
  );
  await readBound(
    repositoryRoot,
    runtimeReceipt.signedDevelopmentFixture.lineagePath,
    runtimeReceipt.signedDevelopmentFixture.lineageSha256,
    "runtime fixture lineage",
  );
  await readBound(
    repositoryRoot,
    runtimeReceipt.signedDevelopmentFixture.trustReceiptPath,
    runtimeReceipt.signedDevelopmentFixture.trustReceiptSha256,
    "runtime fixture trust receipt",
  );
  requireCondition(
    runtimeReceipt.signedDevelopmentFixture.sceneIsUnreferencedByJourneyBeat === true
      && runtimeReceipt.signedDevelopmentFixture.releaseBundleState === "EXCLUDED",
    "runtime proof escaped its unreferenced development-only boundary",
  );

  const packageRoot =
    "native/phase2/runtime-fixture/compiled/vertical-slice-development-v1.runtimefixture";
  for (const input of [
    runtimeReceipt.runtimeInputs.source,
    runtimeReceipt.runtimeInputs.diagnosticUnderlay,
    ...runtimeReceipt.runtimeInputs.alphaMasksBackToFront,
  ]) {
    const bytes = await readBound(
      repositoryRoot,
      `${packageRoot}/${input.packagePath}`,
      input.sha256,
      `runtime proof asset ${input.packagePath}`,
    );
    requireCondition(bytes.byteLength === input.bytes, `${input.packagePath}: size drifted`);
  }
  const reduceMotionInput = runtimeReceipt.runtimeInputs.reduceMotionStatic;
  const reduceMotionBytes = await readBound(
    repositoryRoot,
    `${packageRoot}/${reduceMotionInput.packagePath}`,
    reduceMotionInput.pngSha256,
    "runtime Reduce Motion asset",
  );
  requireCondition(
    reduceMotionBytes.byteLength === reduceMotionInput.bytes,
    "runtime Reduce Motion asset size drifted",
  );
  exactSet(
    runtimeReceipt.runtimeInputs.alphaMasksBackToFront.map(({ layerID }) => layerID),
    ["people", "grain", "foreground"],
    "runtime moving layers",
  );
  requireCondition(
    runtimeReceipt.runtimeInputs.diagnosticUnderlay.authority
      === "DIAGNOSTIC_ONLY_NOT_A_CLEAN_PLATE",
    "diagnostic underlay acquired false clean-plate authority",
  );
  requireCondition(
    runtimeReceipt.runtimePath.productionMTKViewFramebufferOnly === true
      && runtimeReceipt.runtimePath.normalComposition === "PRODUCTION_SHADER_PATH"
      && runtimeReceipt.runtimePath.reduceMotionComposition === "PRODUCTION_SHADER_PATH"
      && runtimeReceipt.runtimePath.exactStaticCopy
        === "DEBUG_OFFSCREEN_DIAGNOSTIC_ONLY",
    "runtime renderer boundary drifted",
  );
  await readBound(
    repositoryRoot,
    runtimeReceipt.runtimePath.sourcePath,
    runtimeReceipt.runtimePath.sourceSha256,
    "runtime renderer source",
  );
  await readBound(
    repositoryRoot,
    runtimeReceipt.deterministicProof.testPath,
    runtimeReceipt.deterministicProof.testSha256,
    "runtime proof test",
  );
  requireCondition(
    runtimeReceipt.deterministicProof.metalReplay
      === "PASS_BYTE_IDENTICAL_AT_BOTH_EXTREMA_AND_REDUCE_MOTION"
      && runtimeReceipt.deterministicProof.saveSnapshotRoundTrip
        === "PASS_IDENTICAL_FRAME_PLAN_NORMAL_AND_REDUCE_MOTION"
      && runtimeReceipt.deterministicProof.normalSceneBypass
        === "REJECTED_PRODUCTION_SHADER_USED"
      && runtimeReceipt.deterministicProof.staticCopyNegativeResult
        === "PASS_ALL_REMAIN_ON_SHADER_PATH",
    "runtime determinism or bypass proof drifted",
  );
  requireCondition(
    runtimeReceipt.deterministicProof.viewportCropID === "baseline-393x852",
    "runtime proof viewport scope drifted",
  );
  exactSet(
    runtimeReceipt.deterministicProof.staticCopyNegativeCases,
    ["opacity", "blend-mode", "mask", "viewport-transform", "pixel-dimension-mismatch"],
    "static-copy negative cases",
  );
  requireCondition(
    runtimeReceipt.renderedFrames.referenceTopDownBGRA8Sha256
      === runtimeReceipt.renderedFrames.reduceMotionProductionShaderTopDownBGRA8Sha256
      && runtimeReceipt.renderedFrames.reduceMotionChangedPixelCount === 0,
    "runtime Reduce Motion pixel parity drifted",
  );
  await readBound(
    repositoryRoot,
    runtimeReceipt.renderedFrames.comparisonPath,
    runtimeReceipt.renderedFrames.comparisonSha256,
    "runtime Metal comparison",
  );
  requireCondition(
    runtimeReceipt.simulator.result === "PASS"
      && runtimeReceipt.simulator.passedTests === 1
      && runtimeReceipt.simulator.failedTests === 0,
    "runtime simulator evidence drifted",
  );
  requireCondition(
    runtimeReceipt.visualReview.result === "PASS_RESTRICTED_RUNTIME_PARTIAL_SCOPE",
    "runtime visual review lost its restricted pass",
  );
  for (const denial of [
    "clean plate",
    "allocation destinations",
    "settlement shelter",
    "allocation cloth",
    "complete layer DAG",
    "state variants",
    "complete scene",
    "production master",
    "artistic approval",
    "editor approval",
    "shipping asset",
    "physical-device performance",
    "chapter completion",
  ]) {
    requireCondition(
      runtimeReceipt.claimsExcluded.includes(denial),
      `runtime receipt lost required authority denial: ${denial}`,
    );
  }
  for (const basename of runtimeReceipt.releaseBoundary.releaseScannerBasenames) {
    requireCondition(
      forbiddenReleaseBasenames.includes(basename),
      `runtime proof asset is absent from release scanner: ${basename}`,
    );
  }
  const runtimeSidecar = await readFile(
    path.join(repositoryRoot, `${runtimeDirectory}/receipt.sha256`),
    "utf8",
  );
  requireCondition(
    runtimeSidecar.trim() === `${sha256(runtimeReceiptBytes)}  receipt.json`,
    "runtime receipt sidecar drifted",
  );

  return {
    status: review.status,
    receiptSHA256: review.frozenProof.receiptSha256,
    includedMovingLayers: receipt.construction.testScope.includedMovingLayers,
    reduceMotionChangedPixelCount: reduceMotion.changedPixelCount,
    shippingState: review.shippingState,
    runtimeStatus: runtimeReceipt.status,
    runtimeReceiptSHA256: sha256(runtimeReceiptBytes),
    simulatorResult: runtimeReceipt.simulator.result,
    runtimeReduceMotionChangedPixelCount:
      runtimeReceipt.renderedFrames.reduceMotionChangedPixelCount,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  validateHarvestParallaxQA()
    .then((result) => process.stdout.write(`${JSON.stringify(result)}\n`))
    .catch((error) => {
      process.stderr.write(`validate-harvest-parallax-qa: ${error.message}\n`);
      process.exitCode = 1;
    });
}
