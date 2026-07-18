import assert from "node:assert/strict";
import { access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { firstFarmers } from "../src/data/chapters/first-farmers";
import { sources } from "../src/data/sources";

const publicRoot = fileURLToPath(new URL("../public/", import.meta.url));
const expectedKinds = [
  "seasons",
  "route",
  "harvest",
  "lineage",
  "inspect",
  "growth",
  "compare",
];
const sourceIds = new Set(sources.map((source) => source.id));

assert.equal(firstFarmers.movements.length, 7, "The chapter should retain seven movements.");
assert.deepEqual(
  firstFarmers.movements.map((movement) => movement.interaction.kind),
  expectedKinds,
  "The chapter interaction sequence changed unexpectedly.",
);
assert.equal(
  new Set(firstFarmers.movements.map((movement) => movement.id)).size,
  firstFarmers.movements.length,
  "Movement ids must be unique.",
);

for (const [index, movement] of firstFarmers.movements.entries()) {
  assert.equal(movement.order, index + 1, `Movement ${movement.id} is out of order.`);
  assert.ok(movement.body.length >= 2, `Movement ${movement.id} needs developed narrative copy.`);
  assert.ok(movement.evidence.length > 0, `Movement ${movement.id} needs evidence statements.`);
  assert.ok(movement.sourceIds.length > 0, `Movement ${movement.id} needs source references.`);
  for (const sourceId of movement.sourceIds) {
    assert.ok(sourceIds.has(sourceId), `Movement ${movement.id} references unknown source ${sourceId}.`);
  }
  await access(`${publicRoot}${movement.image}`);
}

const harvest = firstFarmers.movements.find(
  (movement) => movement.interaction.kind === "harvest",
)?.interaction;
assert.ok(harvest?.kind === "harvest", "The harvest interaction is missing.");
assert.equal(
  harvest.allocations.reduce((sum, allocation) => sum + allocation.initial, 0),
  harvest.total,
  "Initial harvest shares must fill the store exactly.",
);
assert.deepEqual(
  harvest.allocations.map((allocation) => allocation.id).sort(),
  ["food", "reserve", "seed"],
  "The store must preserve food, reserve and seed choices.",
);

const growth = firstFarmers.movements.find(
  (movement) => movement.interaction.kind === "growth",
)?.interaction;
assert.ok(growth?.kind === "growth", "The growth interaction is missing.");
assert.equal(growth.stages.length, 3, "Growth needs three distinct landscape states.");
assert.equal(
  new Set(growth.stages.map((stage) => stage.image)).size,
  growth.stages.length,
  "Each growth state needs a distinct visual asset.",
);
for (const stage of growth.stages) await access(`${publicRoot}${stage.image}`);

const comparison = firstFarmers.movements.find(
  (movement) => movement.interaction.kind === "compare",
)?.interaction;
assert.ok(comparison?.kind === "compare", "The final comparison is missing.");
await access(`${publicRoot}${comparison.before.image}`);
await access(`${publicRoot}${comparison.after.image}`);

const unsupportedQuantitativeKeys = new Set([
  "riverAncestry",
  "farmingAncestry",
  "households",
  "woodland",
]);
function rejectUnsupportedKeys(value: unknown): void {
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    assert.ok(
      !unsupportedQuantitativeKeys.has(key),
      `Unsupported pseudo-quantitative field returned: ${key}.`,
    );
    rejectUnsupportedKeys(child);
  }
}
rejectUnsupportedKeys(firstFarmers);

const publicCopy = JSON.stringify(firstFarmers);
assert.doesNotMatch(
  publicCopy,
  /\b(?:explore the full chapter|chapter progress|\d+\s*(?:-|–|—|to)\s*\d+\s*(?:min|minutes))\b/i,
  "Public chapter copy should stay inside the historical world.",
);

console.log("First Farmers regression checks passed.");
