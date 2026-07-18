import assert from "node:assert/strict";
import { access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { firstFarmers } from "../src/data/chapters/first-farmers";
import { steppeComesWest } from "../src/data/chapters/steppe-comes-west";
import { sources } from "../src/data/sources";
import type { ChapterDefinition } from "../src/types/chapter";

const publicRoot = fileURLToPath(new URL("../public/", import.meta.url));
const sourceIds = new Set(sources.map((source) => source.id));

async function checkCommonChapter(chapter: ChapterDefinition) {
  assert.equal(chapter.movements.length, 7, `${chapter.slug} should contain seven movements.`);
  assert.equal(
    new Set(chapter.movements.map((movement) => movement.id)).size,
    chapter.movements.length,
    `${chapter.slug} movement ids must be unique.`,
  );

  for (const [index, movement] of chapter.movements.entries()) {
    assert.equal(movement.order, index + 1, `Movement ${movement.id} is out of order.`);
    assert.ok(movement.body.length >= 2, `Movement ${movement.id} needs developed narrative copy.`);
    assert.ok(movement.evidence.length > 0, `Movement ${movement.id} needs evidence statements.`);
    assert.ok(movement.sourceIds.length > 0, `Movement ${movement.id} needs source references.`);
    for (const sourceId of movement.sourceIds) {
      assert.ok(
        sourceIds.has(sourceId),
        `Movement ${movement.id} references unknown source ${sourceId}.`,
      );
    }
    await access(`${publicRoot}${movement.image}`);
    if (movement.mobileImage) await access(`${publicRoot}${movement.mobileImage}`);
  }

  if (chapter.ending.image) await access(`${publicRoot}${chapter.ending.image}`);
  if (chapter.ending.mobileImage) {
    await access(`${publicRoot}${chapter.ending.mobileImage}`);
  }

  assert.doesNotMatch(
    JSON.stringify(chapter),
    /\b(?:explore the full chapter|chapter progress|\d+\s*(?:-|–|—|to)\s*\d+\s*(?:min|minutes))\b/i,
    "Public chapter copy should stay inside the historical world.",
  );
}

await checkCommonChapter(firstFarmers);
assert.deepEqual(
  firstFarmers.movements.map((movement) => movement.interaction?.kind),
  ["seasons", "route", "harvest", "lineage", "inspect", "growth", "compare"],
  "The Farmers interaction sequence changed unexpectedly.",
);

const harvestMovement = firstFarmers.movements.find(
  (movement) => movement.interaction?.kind === "harvest",
);
assert.ok(harvestMovement, "The Farmers harvest movement is missing.");
const harvest = harvestMovement?.interaction;
assert.ok(harvest?.kind === "harvest", "The Farmers harvest interaction is missing.");
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
assert.ok(
  harvestMovement.body.some((paragraph) => paragraph.includes("Georgian qvevri")),
  "The harvest movement should connect Georgian Neolithic wine to the qvevri tradition.",
);
assert.ok(
  harvestMovement.sourceIds.includes("mcgovern-2017") &&
    harvestMovement.sourceIds.includes("unesco-qvevri-2013"),
  "The Georgian wine passage needs archaeological and living-tradition sources.",
);

const growth = firstFarmers.movements.find(
  (movement) => movement.interaction?.kind === "growth",
)?.interaction;
assert.ok(growth?.kind === "growth", "The Farmers growth interaction is missing.");
assert.equal(growth.stages.length, 3, "Growth needs three distinct landscape states.");
assert.equal(
  new Set(growth.stages.map((stage) => stage.image)).size,
  growth.stages.length,
  "Each growth state needs a distinct visual asset.",
);
for (const stage of growth.stages) await access(`${publicRoot}${stage.image}`);

const comparison = firstFarmers.movements.find(
  (movement) => movement.interaction?.kind === "compare",
)?.interaction;
assert.ok(comparison?.kind === "compare", "The Farmers comparison is missing.");
await access(`${publicRoot}${comparison.before.image}`);
await access(`${publicRoot}${comparison.after.image}`);

await checkCommonChapter(steppeComesWest);
assert.equal(
  steppeComesWest.movements.filter((movement) => movement.interaction).length,
  3,
  "Steppe should contain exactly three major interactions.",
);
assert.deepEqual(
  steppeComesWest.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["mobility", "turnover", "inheritance"],
  "Steppe should preserve the locked interaction rhythm.",
);

const mobility = steppeComesWest.movements.find(
  (movement) => movement.interaction?.kind === "mobility",
)?.interaction;
assert.ok(mobility?.kind === "mobility", "The mobility interaction is missing.");
assert.deepEqual(
  mobility.states.map((state) => state.id),
  ["herd", "wagon", "westward-household"],
  "Mobility should move from herd to wagon to westward household.",
);

const turnover = steppeComesWest.movements.find(
  (movement) => movement.interaction?.kind === "turnover",
)?.interaction;
assert.ok(turnover?.kind === "turnover", "The turnover interaction is missing.");
assert.deepEqual(
  turnover.regions.map((region) => region.id),
  ["central-europe", "bohemia", "iberia"],
  "Turnover should retain the three sourced regional views.",
);
for (const region of turnover.regions) {
  assert.deepEqual(
    region.measures.map((measure) => measure.id),
    ["ancestry", "local-paternal", "incoming-paternal"],
    `${region.id} should separate total ancestry from paternal-line evidence.`,
  );
}

const inheritance = steppeComesWest.movements.find(
  (movement) => movement.interaction?.kind === "inheritance",
)?.interaction;
assert.ok(inheritance?.kind === "inheritance", "The inheritance interaction is missing.");
assert.deepEqual(
  inheritance.layers.map((layer) => layer.id),
  ["people", "language", "religion"],
  "Inheritance should reveal people, language and religion.",
);
await access(`${publicRoot}${inheritance.mapImage}`);

const unsupportedQuantitativeKeys = new Set([
  "europeanTurnover",
  "combinedReplacement",
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
rejectUnsupportedKeys(steppeComesWest);

console.log("Farmers regression and Steppe chapter checks passed.");
