import assert from "node:assert/strict";
import test from "node:test";
import {
  LaunchAssemblyError,
  validateLaunchAssembly,
} from "../src/launch-assembly.mjs";

const freeChapterIDs = ["chapter-01", "chapter-13", "chapter-21"];

function launchFixture() {
  const chapterIDs = Array.from({ length: 24 }, (_, index) => `chapter-${String(index + 1).padStart(2, "0")}`);
  const paidChapterIDs = chapterIDs.filter((id) => !freeChapterIDs.includes(id));
  const packages = [{
    id: "essential-free-v1",
    chapterIDs: freeChapterIDs,
  }, ...Array.from({ length: 7 }, (_, index) => ({
    id: `paid-wave-${index + 1}`,
    chapterIDs: paidChapterIDs.slice(index * 3, index * 3 + 3),
  }))];
  const packageForChapter = new Map(
    packages.flatMap((packageSpec) => packageSpec.chapterIDs.map((chapterID) => [chapterID, packageSpec.id])),
  );
  const collection = {
    chapters: chapterIDs.map((id, index) => ({
      id,
      sequence: index + 1,
      packageID: packageForChapter.get(id),
    })),
    packages,
  };
  const worldSeed = {
    nodes: [{
      id: "european-world",
      kind: "institution",
      form: "The hidden cumulative world",
      position: { x: 0.5, y: 0.5 },
      attributes: [],
    }],
    traces: [],
  };
  const chapterByID = new Map(chapterIDs.map((id, index) => [id, {
    id,
    arcs: [],
    completionEffects: [{
      id: `effect-${id}`,
      mutation: "transform-node",
      nodeID: "european-world",
      form: `The world after chapter ${String(index + 1).padStart(2, "0")}`,
      attributes: [{ key: `completed-${String(index + 1).padStart(2, "0")}`, value: true }],
    }],
  }]));
  const payloads = packages.map((packageSpec) => ({
    packageID: packageSpec.id,
    worldSeed: structuredClone(worldSeed),
    chapters: packageSpec.chapterIDs.map((chapterID) => chapterByID.get(chapterID)),
  })).reverse();
  return { collection, payloads };
}

function packagePayload(fixture, packageID) {
  return fixture.payloads.find((payload) => payload.packageID === packageID);
}

test("assembles eight packages and returns a deterministic final world SHA-256", () => {
  const fixture = launchFixture();
  const first = validateLaunchAssembly(fixture.collection, fixture.payloads);
  const second = validateLaunchAssembly(
    structuredClone(fixture.collection),
    structuredClone(fixture.payloads).reverse(),
  );
  assert.deepEqual(first, second);
  assert.deepEqual(first, {
    packageCount: 8,
    chapterCount: 24,
    finalWorldSHA256: first.finalWorldSHA256,
  });
  assert.match(first.finalWorldSHA256, /^[a-f0-9]{64}$/);
});

test("replays chapters by collection sequence rather than payload order", () => {
  const fixture = launchFixture();
  const chronological = validateLaunchAssembly(fixture.collection, fixture.payloads);
  const reorderedCollection = structuredClone(fixture.collection);
  const chapter23 = reorderedCollection.chapters.find((chapter) => chapter.id === "chapter-23");
  const chapter24 = reorderedCollection.chapters.find((chapter) => chapter.id === "chapter-24");
  [chapter23.sequence, chapter24.sequence] = [chapter24.sequence, chapter23.sequence];
  const reordered = validateLaunchAssembly(reorderedCollection, fixture.payloads);
  assert.notEqual(chronological.finalWorldSHA256, reordered.finalWorldSHA256);
});

test("rejects a missing launch package payload", () => {
  const fixture = launchFixture();
  fixture.payloads = fixture.payloads.filter((payload) => payload.packageID !== "paid-wave-7");
  assert.throws(
    () => validateLaunchAssembly(fixture.collection, fixture.payloads),
    (error) => error instanceof LaunchAssemblyError
      && /missing payload for 'paid-wave-7'/.test(error.message),
  );
});

test("rejects world-seed drift between packages", () => {
  const fixture = launchFixture();
  packagePayload(fixture, "paid-wave-3").worldSeed.nodes[0].form = "A divergent seed";
  assert.throws(
    () => validateLaunchAssembly(fixture.collection, fixture.payloads),
    /paid-wave-3\.worldSeed: must be identical across all launch packages/,
  );
});

test("rejects an impossible consequence across package boundaries", () => {
  const fixture = launchFixture();
  const chapter = packagePayload(fixture, "paid-wave-1").chapters[0];
  chapter.completionEffects[0] = {
    id: "effect-impossible-cross-package-transform",
    mutation: "transform-node",
    nodeID: "missing-world-object",
    form: "An impossible order",
    attributes: [],
  };
  assert.throws(
    () => validateLaunchAssembly(fixture.collection, fixture.payloads),
    /transform-node is missing node 'missing-world-object'/,
  );
});

test("rejects duplicate world-effect IDs even when definitions are identical", () => {
  const fixture = launchFixture();
  const firstEffect = packagePayload(fixture, "essential-free-v1").chapters[0].completionEffects[0];
  packagePayload(fixture, "paid-wave-1").chapters[0].completionEffects[0] = structuredClone(firstEffect);
  assert.throws(
    () => validateLaunchAssembly(fixture.collection, fixture.payloads),
    /duplicate world-effect 'effect-chapter-01'/,
  );
});

test("rejects package chapter order that differs from the collection manifest", () => {
  const fixture = launchFixture();
  packagePayload(fixture, "paid-wave-4").chapters.reverse();
  assert.throws(
    () => validateLaunchAssembly(fixture.collection, fixture.payloads),
    /paid-wave-4\.chapters: ownership and order must exactly match collection package/,
  );
});
