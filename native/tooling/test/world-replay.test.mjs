import assert from "node:assert/strict";
import test from "node:test";
import { validateWorldReplay } from "../src/world-replay.mjs";

function node(id) {
  return {
    id,
    kind: "settlement",
    form: `Hidden world anchor ${id}`,
    position: id === "western-anatolia" ? { x: 0.72, y: 0.48 } : { x: 0.51, y: 0.45 },
    attributes: [],
  };
}

function route() {
  return {
    id: "aegean-farming-route",
    kind: "seaRoute",
    origin: "western-anatolia",
    destination: "aegean-settlement",
    strength: 1,
  };
}

function payload() {
  return {
    worldSeed: {
      nodes: [node("western-anatolia"), node("aegean-settlement")],
      traces: [route()],
    },
    chapters: [{
      id: "first-farmers",
      arcs: [{
        beats: [{
          interaction: {
            completionEffects: [{
              id: "effect-crossing",
              mutation: "establish-trace",
              trace: route(),
            }],
          },
          completionEffects: [],
        }],
      }],
      completionEffects: [{
        id: "effect-settlement",
        mutation: "reveal-node",
        node: {
          ...node("aegean-settlement"),
          form: "Timber houses beside stored grain",
          attributes: [{ key: "inhabited", value: true }],
        },
      }],
    }],
  };
}

test("world replay is deterministic from hidden nodes and dormant traces", () => {
  const issues = [];
  const first = validateWorldReplay(payload(), "contentPackage", issues);
  const second = validateWorldReplay(payload(), "contentPackage", []);
  assert.deepEqual(issues, []);
  assert.match(first.cumulativeDigest, /^[a-f0-9]{64}$/);
  assert.equal(
    first.cumulativeDigest,
    "b4634fe480063e75098ded9ea2a5c0d7904217f6890425c9a97435a760811ea5",
  );
  assert.equal(first.perChapter[0].digest, second.perChapter[0].digest);
  assert.equal(first.cumulativeDigest, second.cumulativeDigest);
});

test("world replay rejects a route whose endpoint does not exist", () => {
  const invalid = payload();
  invalid.worldSeed.nodes = invalid.worldSeed.nodes.filter(({ id }) => id !== "western-anatolia");
  invalid.worldSeed.traces = [];
  const issues = [];
  validateWorldReplay(invalid, "contentPackage", issues);
  assert.match(issues.join("\n"), /missing origin node 'western-anatolia'/);
});

test("world replay rejects a transformation with no causal object", () => {
  const invalid = payload();
  invalid.chapters[0].arcs[0].beats[0].interaction.completionEffects = [{
    id: "effect-impossible-transform",
    mutation: "transform-node",
    nodeID: "absent-order",
    form: "A transformed order",
    attributes: [],
  }];
  const issues = [];
  validateWorldReplay(invalid, "contentPackage", issues);
  assert.match(issues.join("\n"), /transform-node is missing node 'absent-order'/);
});
