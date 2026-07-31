import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const measurementPath = resolve(
  root,
  "native/content/backstage/harvest/destination-rail-disocclusion-measurement-v26.provisional.json",
);
const expectedMeasurementSHA256 = "cfb6c98449ec5c234de1eb65f0eeb0d8f47183380498e5a2b91e1fe3f4d21058";

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function nearlyEqual(actual, expected) {
  assert.ok(Math.abs(actual - expected) < 1e-9, `${actual} != ${expected}`);
}

test("the destination rail measurement is byte-bound to its sidecar", async () => {
  const bytes = await readFile(measurementPath);
  const sidecar = (await readFile(`${measurementPath}.sha256`, "utf8")).trim();
  assert.equal(sha256(bytes), expectedMeasurementSHA256);
  assert.equal(sidecar, expectedMeasurementSHA256);
});

test("every destination displacement is derived from the bound scene rail", async () => {
  const measurement = JSON.parse(await readFile(measurementPath, "utf8"));
  const sceneBytes = await readFile(resolve(root, measurement.sceneFixture.path));
  const runtimeBytes = await readFile(resolve(root, measurement.runtimeFormula.path));
  assert.equal(sha256(sceneBytes), measurement.sceneFixture.sha256);
  assert.equal(sha256(runtimeBytes), measurement.runtimeFormula.sha256);

  const scene = JSON.parse(sceneBytes).scene;
  assert.deepEqual(scene.sceneCanvas.canvas, measurement.sceneFixture.canvasPixels);
  assert.deepEqual(scene.cameraRail.keyframes, measurement.sceneFixture.keyframes);
  assert.deepEqual(scene.cameraRail.keyframes[0].center, measurement.sceneFixture.railOrigin);

  const layers = new Map(scene.layers.map((layer) => [layer.id, layer]));
  for (const record of measurement.measurements) {
    const layer = layers.get(record.layerID);
    assert.ok(layer, record.layerID);
    assert.equal(layer.motion.parallaxFactor, record.parallaxFactor);
    assert.equal(layer.motion.windResponse, 0);
    assert.equal(record.keyframeMasterPixelOffsets.length, scene.cameraRail.keyframes.length);

    for (const [index, keyframe] of scene.cameraRail.keyframes.entries()) {
      const expectedDX = (keyframe.center.x - measurement.sceneFixture.railOrigin.x)
        * scene.sceneCanvas.canvas.width * layer.motion.parallaxFactor;
      const expectedDY = (keyframe.center.y - measurement.sceneFixture.railOrigin.y)
        * scene.sceneCanvas.canvas.height * layer.motion.parallaxFactor;
      const recorded = record.keyframeMasterPixelOffsets[index];
      assert.equal(recorded.progress, keyframe.progress);
      nearlyEqual(recorded.dx, expectedDX);
      nearlyEqual(recorded.dy, expectedDY);
    }

    const maximumX = Math.max(...record.keyframeMasterPixelOffsets.map(({ dx }) => Math.abs(dx)));
    const maximumY = Math.max(...record.keyframeMasterPixelOffsets.map(({ dy }) => Math.abs(dy)));
    assert.equal(record.maximumAbsoluteShiftPixelsCeil.x, Math.ceil(maximumX));
    assert.equal(record.maximumAbsoluteShiftPixelsCeil.y, Math.ceil(maximumY));
    assert.equal(
      record.minimumSymmetricAuthoringBandPixels.x,
      Math.ceil(maximumX) + record.sourceBuiltSeamRingPixels,
    );
    assert.equal(
      record.minimumSymmetricAuthoringBandPixels.y,
      Math.ceil(maximumY) + record.sourceBuiltSeamRingPixels,
    );
  }
});

test("the measurement remains a non-shipping technical input", async () => {
  const measurement = JSON.parse(await readFile(measurementPath, "utf8"));
  assert.equal(measurement.status, "CODEX_MEASURED_NON_SHIPPING_TECHNICAL_INPUT");
  assert.deepEqual(measurement.authorityLimits, {
    editorApproval: false,
    productionAssetAuthority: false,
    productionMasterAuthority: false,
    packageAuthority: false,
    shippingAllowed: false,
  });
  assert.equal(measurement.authoringRule.coverageMode, "RAIL_BOUNDED");
  assert.match(measurement.authoringRule.conservativeImplementation, /may not claim full-subject/);
});
