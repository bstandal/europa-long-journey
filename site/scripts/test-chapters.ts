import assert from "node:assert/strict";
import { access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { bronzeEurope } from "../src/data/chapters/bronze-europe";
import { empireTakesCross } from "../src/data/chapters/empire-takes-cross";
import { europeReborn } from "../src/data/chapters/europe-reborn";
import { firstFarmers } from "../src/data/chapters/first-farmers";
import { greeceAndTheCitizen } from "../src/data/chapters/greece-and-the-citizen";
import { romeGathersEurope } from "../src/data/chapters/rome-gathers-europe";
import { steppeComesWest } from "../src/data/chapters/steppe-comes-west";
import { scenes } from "../src/data/scenes";
import { sources } from "../src/data/sources";
import type { ChapterDefinition } from "../src/types/chapter";

const publicRoot = fileURLToPath(new URL("../public/", import.meta.url));
const sourceIds = new Set(sources.map((source) => source.id));

async function checkCommonChapter(
  chapter: ChapterDefinition,
  expectedMovementCount: number,
) {
  assert.equal(
    chapter.movements.length,
    expectedMovementCount,
    `${chapter.slug} should contain ${expectedMovementCount} movements.`,
  );
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
  if (chapter.routeImage) await access(`${publicRoot}${chapter.routeImage}`);
  if (chapter.openingRouteImage) {
    await access(`${publicRoot}${chapter.openingRouteImage}`);
  }

  assert.doesNotMatch(
    JSON.stringify(chapter),
    /\b(?:explore the full chapter|chapter progress|\d+\s*(?:-|–|—|to)\s*\d+\s*(?:min|minutes))\b/i,
    "Public chapter copy should stay inside the historical world.",
  );
}

await checkCommonChapter(firstFarmers, 7);
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

await checkCommonChapter(steppeComesWest, 7);
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

await checkCommonChapter(bronzeEurope, 10);

await checkCommonChapter(greeceAndTheCitizen, 12);
assert.deepEqual(
  greeceAndTheCitizen.acts?.map((act) => act.id),
  ["public-light", "two-cities", "freedom-power", "greek-war"],
  "Greece should preserve the four-act progression.",
);
for (const act of greeceAndTheCitizen.acts ?? []) {
  assert.equal(
    greeceAndTheCitizen.movements.filter((movement) => movement.actId === act.id).length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  greeceAndTheCitizen.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 5, 8, 11],
  "Greece interactions should appear in movements 2, 5, 8 and 11.",
);
assert.deepEqual(
  greeceAndTheCitizen.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["inscription", "citizen-body", "civic-path", "war-timeline"],
  "Greece should preserve the inscription, citizen body, civic path and war timeline sequence.",
);

const inscription = greeceAndTheCitizen.movements[1].interaction;
assert.ok(inscription?.kind === "inscription", "Greece needs the inscription interaction.");
assert.equal(inscription.states.length, 3, "The inscription needs three states.");
assert.deepEqual(
  inscription.states.map((state) => state.id),
  ["surface", "reading", "consequence"],
  "The inscription should move from surface to rule to consequence.",
);

const citizenBody = greeceAndTheCitizen.movements[4].interaction;
assert.ok(citizenBody?.kind === "citizen-body", "Greece needs the Attic citizen-body interaction.");
assert.equal(citizenBody.states.length, 4, "The Attic citizen body needs four layers.");
await access(`${publicRoot}${citizenBody.mapImage}`);
for (const state of citizenBody.states) {
  await access(`${publicRoot}${state.overlayImage}`);
}

const civicPath = greeceAndTheCitizen.movements[7].interaction;
assert.ok(civicPath?.kind === "civic-path", "Greece needs the civic-path interaction.");
assert.equal(civicPath.paths.length, 3, "The civic path needs three public responsibilities.");
assert.deepEqual(
  civicPath.paths.map((path) => path.id),
  ["council", "jury", "assembly"],
  "The civic path should offer council, jury and assembly.",
);

const warTimeline = greeceAndTheCitizen.movements[10].interaction;
assert.ok(warTimeline?.kind === "war-timeline", "Greece needs the war timeline.");
assert.equal(warTimeline.states.length, 9, "The war timeline needs nine dated states.");
assert.equal(warTimeline.states[0].period, "431 BC");
assert.equal(warTimeline.states.at(-1)?.period, "403 BC");
await access(`${publicRoot}${warTimeline.mapImage}`);
for (const state of warTimeline.states) {
  await access(`${publicRoot}${state.overlayImage}`);
}

const greeceWords = greeceAndTheCitizen.movements.reduce(
  (sum, movement) =>
    sum +
    movement.body.reduce(
      (movementSum, paragraph) =>
        movementSum + paragraph.trim().split(/\s+/).length,
      0,
    ),
  0,
);
assert.ok(
  greeceWords >= 3200 && greeceWords <= 3800,
  `Greece should contain 3,200–3,800 words of continuous narrative; found ${greeceWords}.`,
);
const greeceScene = scenes.find((scene) => scene.id === "greece-and-the-citizen");
assert.equal(
  greeceScene?.chronicle?.href,
  "chapters/greece-and-the-citizen/",
  "The main journey needs a working Greece chapter link.",
);
assert.equal(
  greeceScene?.chronicle?.label,
  "Enter the public ground",
  "The Greece chapter link needs its historical invitation.",
);

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
rejectUnsupportedKeys(bronzeEurope);
rejectUnsupportedKeys(greeceAndTheCitizen);
rejectUnsupportedKeys(romeGathersEurope);
rejectUnsupportedKeys(empireTakesCross);
rejectUnsupportedKeys(europeReborn);

await checkCommonChapter(romeGathersEurope, 12);
assert.deepEqual(
  romeGathersEurope.acts?.map((act) => act.id),
  [
    "power-without-king",
    "italian-engine",
    "commands-break-republic",
    "provinces-enter-name",
  ],
  "Rome should preserve the four-act progression.",
);
for (const act of romeGathersEurope.acts ?? []) {
  assert.equal(
    romeGathersEurope.movements.filter((movement) => movement.actId === act.id).length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
const principalRomanInteractionKinds = new Set([
  "roman-constitution",
  "roman-network",
  "roman-command",
  "roman-citizenship",
]);
assert.deepEqual(
  romeGathersEurope.movements
    .map((movement, index) =>
      movement.interaction && principalRomanInteractionKinds.has(movement.interaction.kind)
        ? index + 1
        : null,
    )
    .filter(Boolean),
  [2, 5, 9, 11],
  "Rome's principal interactions should remain in movements 2, 5, 9 and 11.",
);
assert.deepEqual(
  romeGathersEurope.movements
    .map((movement) => movement.interaction?.kind)
    .filter((kind) => kind && principalRomanInteractionKinds.has(kind)),
  ["roman-constitution", "roman-network", "roman-command", "roman-citizenship"],
  "Rome should preserve the constitution, network, command and citizenship sequence.",
);
assert.deepEqual(
  romeGathersEurope.movements
    .map((movement, index) =>
      movement.interaction?.kind === "roman-trace" ? index + 1 : null,
    )
    .filter(Boolean),
  [3, 6, 8, 10, 12],
  "Rome's lighter active traces should appear in movements 3, 6, 8, 10 and 12.",
);
for (const movement of romeGathersEurope.movements) {
  if (movement.interaction?.kind !== "roman-trace") continue;
  assert.equal(
    movement.interaction.stops.length,
    3,
    `Roman trace ${movement.id} should have three thumb-friendly stops.`,
  );
}

const romanConstitution = romeGathersEurope.movements[1].interaction;
assert.ok(
  romanConstitution?.kind === "roman-constitution",
  "Rome needs the republican constitution interaction.",
);
assert.deepEqual(
  romanConstitution.institutions.map((institution) => institution.id),
  ["people", "magistrates", "senate"],
  "Republican authority should be divided among people, magistrates and Senate.",
);

const romanNetwork = romeGathersEurope.movements[4].interaction;
assert.ok(romanNetwork?.kind === "roman-network", "Rome needs the Italian network interaction.");
assert.deepEqual(
  romanNetwork.states.map((state) => state.id),
  ["settlements-338", "via-appia-312", "peninsula-275", "mobilisation-218"],
  "The Italian engine should move from settlement to road, peninsula and wartime mobilisation.",
);
await access(`${publicRoot}${romanNetwork.mapImage}`);

const romanCommand = romeGathersEurope.movements[8].interaction;
assert.ok(romanCommand?.kind === "roman-command", "Rome needs the command-crisis interaction.");
assert.deepEqual(
  romanCommand.states.map((state) => state.id),
  ["sulla-88", "caesar-49", "triumvirs-43", "augustus-27"],
  "The command crisis should end where permanent military pre-eminence settles.",
);

const romanCitizenship = romeGathersEurope.movements[10].interaction;
assert.ok(
  romanCitizenship?.kind === "roman-citizenship",
  "Rome needs the citizenship-path interaction.",
);
assert.deepEqual(
  romanCitizenship.paths.map((path) => path.id),
  ["auxiliary", "manumission", "municipal-office", "imperial-grant"],
  "Citizenship should show four historically distinct routes.",
);

const romeWords = romeGathersEurope.movements.reduce(
  (sum, movement) =>
    sum +
    movement.body.reduce(
      (movementSum, paragraph) => movementSum + paragraph.trim().split(/\s+/).length,
      0,
    ),
  0,
);
assert.ok(
  romeWords >= 3200 && romeWords <= 3900,
  `Rome should contain 3,200–3,900 words of continuous narrative; found ${romeWords}.`,
);
const romeScene = scenes.find((scene) => scene.id === "rome-gathers-europe");
assert.equal(
  romeScene?.chronicle?.href,
  "chapters/rome-gathers-europe/",
  "The main journey needs a working Rome chapter link.",
);
assert.equal(
  romeScene?.chronicle?.label,
  "Enter the forged road",
  "The Rome chapter link needs its historical invitation.",
);
assert.equal(
  romeGathersEurope.ending.nextPeriod,
  "AD 312–565",
  "Rome should hand the reader to the actual chronological range of Chapter 06.",
);

await checkCommonChapter(empireTakesCross, 14);
assert.deepEqual(
  empireTakesCross.acts?.map((act) => act.id),
  ["sign-and-crown", "imperial-faith", "christian-capital", "stone-and-law"],
  "The Christian Empire chapter should preserve the four-act progression.",
);
assert.deepEqual(
  (empireTakesCross.acts ?? []).map((act) =>
    empireTakesCross.movements.filter((movement) => movement.actId === act.id).length
  ),
  [4, 3, 4, 3],
  "The Christian Empire act lengths should remain 4, 3, 4 and 3 movements.",
);
const principalChristianInteractionKinds = new Set([
  "christian-policy",
  "christian-council",
  "christian-city",
  "sacred-space",
]);
assert.deepEqual(
  empireTakesCross.movements
    .map((movement, index) =>
      movement.interaction &&
      principalChristianInteractionKinds.has(movement.interaction.kind)
        ? index + 1
        : null,
    )
    .filter(Boolean),
  [2, 5, 8, 13],
  "The Christian Empire's principal interactions should remain in movements 2, 5, 8 and 13.",
);
assert.deepEqual(
  empireTakesCross.movements
    .map((movement) => movement.interaction?.kind)
    .filter((kind) => kind && principalChristianInteractionKinds.has(kind)),
  ["christian-policy", "christian-council", "christian-city", "sacred-space"],
  "The Christian Empire should preserve the policy, council, capital and sacred-space sequence.",
);
assert.deepEqual(
  empireTakesCross.movements
    .map((movement, index) =>
      movement.interaction?.kind === "christian-trace" ? index + 1 : null
    )
    .filter(Boolean),
  [3, 6, 9, 12, 14],
  "The Christian Empire's lighter traces should appear in movements 3, 6, 9, 12 and 14.",
);
for (const movement of empireTakesCross.movements) {
  if (movement.interaction?.kind !== "christian-trace") continue;
  assert.equal(
    movement.interaction.stops.length,
    3,
    `Christian trace ${movement.id} should have three thumb-friendly stops.`,
  );
}

const christianPolicy = empireTakesCross.movements[1].interaction;
assert.ok(christianPolicy?.kind === "christian-policy");
assert.deepEqual(
  christianPolicy.states.map((state) => state.id),
  ["persecution-303", "toleration-313", "council-325", "confession-380"],
  "Imperial policy should move from persecution to toleration, council and confession.",
);

const christianCouncil = empireTakesCross.movements[4].interaction;
assert.ok(christianCouncil?.kind === "christian-council");
assert.deepEqual(
  christianCouncil.states.map((state) => state.id),
  ["summons", "debate", "creed", "reception"],
  "Nicaea should move from summons through reception.",
);

const christianCity = empireTakesCross.movements[7].interaction;
assert.ok(christianCity?.kind === "christian-city");
await access(`${publicRoot}${christianCity.mapImage}`);
assert.deepEqual(
  christianCity.states.map((state) => state.id),
  ["foundation-324", "dedication-330", "wall-413", "capital-450"],
  "Constantinople should grow from foundation to mature capital.",
);

const sacredSpace = empireTakesCross.movements[12].interaction;
assert.ok(sacredSpace?.kind === "sacred-space");
assert.deepEqual(
  sacredSpace.states.map((state) => state.id),
  ["structure", "material", "liturgy", "emperor"],
  "Hagia Sophia should reveal structure, material, liturgy and emperor.",
);

const christianEmpireWords = empireTakesCross.movements.reduce(
  (sum, movement) =>
    sum +
    movement.body.reduce(
      (movementSum, paragraph) => movementSum + paragraph.trim().split(/\s+/).length,
      0,
    ),
  0,
);
assert.ok(
  christianEmpireWords >= 2500 && christianEmpireWords <= 3100,
  `The Christian Empire should contain 2,500–3,100 words of continuous narrative; found ${christianEmpireWords}.`,
);
const christianEmpireScene = scenes.find((scene) => scene.id === "christian-empire");
assert.equal(
  christianEmpireScene?.chronicle?.href,
  "chapters/empire-takes-cross/",
  "The main journey needs a working Christian Empire chapter link.",
);
assert.equal(
  christianEmpireScene?.chronicle?.label,
  "Enter the consecrated city",
  "The Christian Empire chapter link needs its historical invitation.",
);
const europeRebornScene = scenes.find((scene) => scene.id === empireTakesCross.nextHash);
assert.ok(europeRebornScene, "The Christian Empire ending needs a real next scene.");
assert.equal(
  empireTakesCross.nextTitle,
  europeRebornScene.title,
  "The Christian Empire ending title must match its actual next scene.",
);
assert.equal(
  empireTakesCross.ending.nextPeriod,
  `AD ${europeRebornScene.period.label}`,
  "The Christian Empire ending period must match its actual next scene.",
);

await checkCommonChapter(europeReborn, 14);
assert.deepEqual(
  europeReborn.acts?.map((act) => act.id),
  ["survival", "frankish-order", "imperial-inheritance", "widening-commonwealth"],
  "Europe Reborn should preserve the four-act progression.",
);
assert.deepEqual(
  (europeReborn.acts ?? []).map((act) =>
    europeReborn.movements.filter((movement) => movement.actId === act.id).length
  ),
  [2, 5, 4, 3],
  "Europe Reborn act lengths should remain 2, 5, 4 and 3 movements.",
);
const principalCommonwealthInteractionKinds = new Set([
  "commonwealth-city",
  "written-network",
  "realm-partition",
  "conversion-roads",
]);
assert.deepEqual(
  europeReborn.movements
    .map((movement, index) =>
      movement.interaction &&
      principalCommonwealthInteractionKinds.has(movement.interaction.kind)
        ? index + 1
        : null
    )
    .filter(Boolean),
  [2, 7, 9, 13],
  "Europe Reborn principal interactions should remain in movements 2, 7, 9 and 13.",
);
assert.deepEqual(
  europeReborn.movements
    .map((movement) => movement.interaction?.kind)
    .filter((kind) => kind && principalCommonwealthInteractionKinds.has(kind)),
  ["commonwealth-city", "written-network", "realm-partition", "conversion-roads"],
  "Europe Reborn should preserve its city, writing, partition and conversion sequence.",
);
assert.deepEqual(
  europeReborn.movements
    .map((movement, index) =>
      movement.interaction?.kind === "commonwealth-trace" ? index + 1 : null
    )
    .filter(Boolean),
  [3, 4, 6, 10, 14],
  "Europe Reborn lighter evidence traces should remain in movements 3, 4, 6, 10 and 14.",
);
for (const movement of europeReborn.movements) {
  if (movement.interaction?.kind !== "commonwealth-trace") continue;
  assert.equal(
    movement.interaction.stops.length,
    3,
    `Commonwealth trace ${movement.id} should have three thumb-friendly stops.`,
  );
}

const europeRebornWords = europeReborn.movements.reduce(
  (sum, movement) =>
    sum +
    movement.body.reduce(
      (movementSum, paragraph) => movementSum + paragraph.trim().split(/\s+/).length,
      0,
    ),
  0,
);
assert.ok(
  europeRebornWords >= 2500 && europeRebornWords <= 3300,
  `Europe Reborn should contain 2,500–3,300 words of continuous narrative; found ${europeRebornWords}.`,
);
assert.equal(
  europeRebornScene?.chronicle?.href,
  "chapters/europe-reborn/",
  "The main journey needs a working Europe Reborn chapter link.",
);
assert.equal(
  europeRebornScene?.chronicle?.label,
  "Follow the rebuilt road",
  "The Europe Reborn chapter link needs its historical invitation.",
);
const papalRevolutionScene = scenes.find((scene) => scene.id === europeReborn.nextHash);
assert.ok(papalRevolutionScene, "Europe Reborn ending needs a real next scene.");
assert.equal(
  europeReborn.nextTitle,
  papalRevolutionScene.title,
  "Europe Reborn ending title must match its actual next scene.",
);
assert.equal(
  europeReborn.ending.nextPeriod,
  `AD ${papalRevolutionScene.period.label}`,
  "Europe Reborn ending period must match its actual next scene.",
);

console.log(
  "Farmers, Steppe, Bronze, Greece, Rome, Christian Empire and Europe Reborn chapter checks passed.",
);
