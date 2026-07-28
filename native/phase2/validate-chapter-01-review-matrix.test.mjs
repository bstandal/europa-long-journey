import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { validateChapter01ReviewMatrix } from "./validate-chapter-01-review-matrix.mjs";

const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const matrixPath = path.join(
  repositoryRoot,
  "native/phase2/runtime-fixture/chapter-01-review-matrix.json",
);
const loadMatrix = async () => JSON.parse(await readFile(matrixPath, "utf8"));

test("validates six shared review worlds across all 17 stable scenes", async () => {
  const matrix = await validateChapter01ReviewMatrix({ repositoryRoot });
  assert.equal(matrix.worlds.length, 6);
  assert.equal(matrix.beats.length, 17);
  assert.equal(new Set(matrix.beats.map(({ sceneID }) => sceneID)).size, 17);
});

test("rejects shipping escalation and public-schema leakage", async () => {
  const shipping = await loadMatrix();
  shipping.shippingAllowed = true;
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: shipping }),
    /cannot ship/u,
  );

  const publicMutation = await loadMatrix();
  publicMutation.publicContentSchemaMutation = true;
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: publicMutation }),
    /cannot enter public content/u,
  );
});

test("rejects a seventh world, a changed restore anchor and a thin touch target", async () => {
  const seventh = await loadMatrix();
  seventh.worlds.push(structuredClone(seventh.worlds[0]));
  seventh.worlds[6].id = "review-world-invented";
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: seventh }),
    /exactly six shared worlds/u,
  );

  const scene = await loadMatrix();
  scene.beats[0].sceneID = "scene-invented";
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: scene }),
    /scene and restore anchors drifted/u,
  );

  const touch = await loadMatrix();
  touch.portraitContract.minimumEffectiveTargetPoints = 43;
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: touch }),
    /at least 44 points/u,
  );

  const canvas = await loadMatrix();
  canvas.portraitContract.masterCanvasPixels = { width: 393, height: 852 };
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: canvas }),
    /real portrait-master raster size/u,
  );

  const overscan = await loadMatrix();
  overscan.portraitContract.baselineSourceRect = {
    x: 0,
    y: 0,
    width: 1,
    height: 1,
  };
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: overscan }),
    /consume the declared overscan exactly/u,
  );

  const layers = await loadMatrix();
  layers.portraitContract.transparentOverlayLayers = ["foreground"];
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: layers }),
    /transparent overlays/u,
  );
});

test("rejects a missing interaction state and weak Reduce Motion parity", async () => {
  const state = await loadMatrix();
  const aegean = state.worlds.find(({ id }) => id === "review-world-aegean-crossing");
  aegean.interactionStateIDs = aegean.interactionStateIDs.filter((id) => id !== "thessaly");
  aegean.reduceMotion.consequenceStateIDs = aegean.reduceMotion.consequenceStateIDs
    .filter((id) => id !== "thessaly");
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: state }),
    /missing interaction states/u,
  );

  const reduceMotion = await loadMatrix();
  reduceMotion.worlds[0].reduceMotion.consequenceStateIDs = [];
  await assert.rejects(
    validateChapter01ReviewMatrix({ repositoryRoot, matrix: reduceMotion }),
    /loses its consequence under Reduce Motion/u,
  );
});
