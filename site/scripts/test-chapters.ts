import assert from "node:assert/strict";
import { access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { bronzeEurope } from "../src/data/chapters/bronze-europe";
import { continentRebuilt } from "../src/data/chapters/continent-rebuilt";
import { dutchRepublic } from "../src/data/chapters/dutch-republic";
import { empireManyLiberties } from "../src/data/chapters/empire-many-liberties";
import { empireTakesCross } from "../src/data/chapters/empire-takes-cross";
import { enlightenmentPublicOpinion } from "../src/data/chapters/enlightenment-public-opinion";
import { europeHoldsTheLine } from "../src/data/chapters/europe-holds-the-line";
import { europeReborn } from "../src/data/chapters/europe-reborn";
import {
  europeAtWar,
  europeAtWarAssetContract,
} from "../src/data/chapters/europe-at-war";
import { europeReturns } from "../src/data/chapters/europe-returns";
import { europeTurnsSeaward } from "../src/data/chapters/europe-turns-seaward";
import { europeanWorld } from "../src/data/chapters/european-world";
import { firstFarmers } from "../src/data/chapters/first-farmers";
import { greeceAndTheCitizen } from "../src/data/chapters/greece-and-the-citizen";
import { habsburgEurope } from "../src/data/chapters/habsburg-europe";
import { hanseaticNorth } from "../src/data/chapters/hanseatic-north";
import { medievalCommercialRevolution } from "../src/data/chapters/medieval-commercial-revolution";
import { papalRevolution } from "../src/data/chapters/papal-revolution";
import { reformation } from "../src/data/chapters/reformation";
import { rivalryIndustrialBreakthrough } from "../src/data/chapters/rivalry-industrial-breakthrough";
import { romeGathersEurope } from "../src/data/chapters/rome-gathers-europe";
import { scientificRevolution } from "../src/data/chapters/scientific-revolution";
import { societyBeyondKin } from "../src/data/chapters/society-beyond-kin";
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
    assert.equal(
      movement.order,
      index + 1,
      `Movement ${movement.id} is out of order.`,
    );
    assert.ok(
      movement.body.length >= 2,
      `Movement ${movement.id} needs developed narrative copy.`,
    );
    assert.ok(
      movement.evidence.length > 0,
      `Movement ${movement.id} needs evidence statements.`,
    );
    assert.ok(
      movement.sourceIds.length > 0,
      `Movement ${movement.id} needs source references.`,
    );
    for (const sourceId of movement.sourceIds) {
      assert.ok(
        sourceIds.has(sourceId),
        `Movement ${movement.id} references unknown source ${sourceId}.`,
      );
    }
    await access(`${publicRoot}${movement.image}`);
    if (movement.mobileImage)
      await access(`${publicRoot}${movement.mobileImage}`);
  }

  if (chapter.ending.image)
    await access(`${publicRoot}${chapter.ending.image}`);
  if (chapter.ending.mobileImage) {
    await access(`${publicRoot}${chapter.ending.mobileImage}`);
  }
  if (chapter.hero?.image) await access(`${publicRoot}${chapter.hero.image}`);
  if (chapter.hero?.mobileImage) {
    await access(`${publicRoot}${chapter.hero.mobileImage}`);
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
assert.ok(
  harvest?.kind === "harvest",
  "The Farmers harvest interaction is missing.",
);
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
  harvestMovement.body.some((paragraph) =>
    paragraph.includes("Georgian qvevri"),
  ),
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
assert.ok(
  growth?.kind === "growth",
  "The Farmers growth interaction is missing.",
);
assert.equal(
  growth.stages.length,
  3,
  "Growth needs three distinct landscape states.",
);
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
assert.ok(
  mobility?.kind === "mobility",
  "The mobility interaction is missing.",
);
assert.deepEqual(
  mobility.states.map((state) => state.id),
  ["herd", "wagon", "westward-household"],
  "Mobility should move from herd to wagon to westward household.",
);

const turnover = steppeComesWest.movements.find(
  (movement) => movement.interaction?.kind === "turnover",
)?.interaction;
assert.ok(
  turnover?.kind === "turnover",
  "The turnover interaction is missing.",
);
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
assert.ok(
  inheritance?.kind === "inheritance",
  "The inheritance interaction is missing.",
);
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
    greeceAndTheCitizen.movements.filter(
      (movement) => movement.actId === act.id,
    ).length,
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
assert.ok(
  inscription?.kind === "inscription",
  "Greece needs the inscription interaction.",
);
assert.equal(
  inscription.states.length,
  3,
  "The inscription needs three states.",
);
assert.deepEqual(
  inscription.states.map((state) => state.id),
  ["surface", "reading", "consequence"],
  "The inscription should move from surface to rule to consequence.",
);

const citizenBody = greeceAndTheCitizen.movements[4].interaction;
assert.ok(
  citizenBody?.kind === "citizen-body",
  "Greece needs the Attic citizen-body interaction.",
);
assert.equal(
  citizenBody.states.length,
  4,
  "The Attic citizen body needs four layers.",
);
await access(`${publicRoot}${citizenBody.mapImage}`);
for (const state of citizenBody.states) {
  await access(`${publicRoot}${state.overlayImage}`);
}

const civicPath = greeceAndTheCitizen.movements[7].interaction;
assert.ok(
  civicPath?.kind === "civic-path",
  "Greece needs the civic-path interaction.",
);
assert.equal(
  civicPath.paths.length,
  3,
  "The civic path needs three public responsibilities.",
);
assert.deepEqual(
  civicPath.paths.map((path) => path.id),
  ["council", "jury", "assembly"],
  "The civic path should offer council, jury and assembly.",
);

const warTimeline = greeceAndTheCitizen.movements[10].interaction;
assert.ok(
  warTimeline?.kind === "war-timeline",
  "Greece needs the war timeline.",
);
assert.equal(
  warTimeline.states.length,
  9,
  "The war timeline needs nine dated states.",
);
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
const greeceScene = scenes.find(
  (scene) => scene.id === "greece-and-the-citizen",
);
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
    romeGathersEurope.movements.filter((movement) => movement.actId === act.id)
      .length,
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
      movement.interaction &&
      principalRomanInteractionKinds.has(movement.interaction.kind)
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
assert.ok(
  romanNetwork?.kind === "roman-network",
  "Rome needs the Italian network interaction.",
);
assert.deepEqual(
  romanNetwork.states.map((state) => state.id),
  ["settlements-338", "via-appia-312", "peninsula-275", "mobilisation-218"],
  "The Italian engine should move from settlement to road, peninsula and wartime mobilisation.",
);
await access(`${publicRoot}${romanNetwork.mapImage}`);

const romanCommand = romeGathersEurope.movements[8].interaction;
assert.ok(
  romanCommand?.kind === "roman-command",
  "Rome needs the command-crisis interaction.",
);
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
      (movementSum, paragraph) =>
        movementSum + paragraph.trim().split(/\s+/).length,
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
  (empireTakesCross.acts ?? []).map(
    (act) =>
      empireTakesCross.movements.filter((movement) => movement.actId === act.id)
        .length,
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
      movement.interaction?.kind === "christian-trace" ? index + 1 : null,
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
      (movementSum, paragraph) =>
        movementSum + paragraph.trim().split(/\s+/).length,
      0,
    ),
  0,
);
assert.ok(
  christianEmpireWords >= 2500 && christianEmpireWords <= 3100,
  `The Christian Empire should contain 2,500–3,100 words of continuous narrative; found ${christianEmpireWords}.`,
);
const christianEmpireScene = scenes.find(
  (scene) => scene.id === "christian-empire",
);
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
const europeRebornScene = scenes.find(
  (scene) => scene.id === empireTakesCross.nextHash,
);
assert.ok(
  europeRebornScene,
  "The Christian Empire ending needs a real next scene.",
);
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
  [
    "survival",
    "frankish-order",
    "imperial-inheritance",
    "widening-commonwealth",
  ],
  "Europe Reborn should preserve the four-act progression.",
);
assert.deepEqual(
  (europeReborn.acts ?? []).map(
    (act) =>
      europeReborn.movements.filter((movement) => movement.actId === act.id)
        .length,
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
        : null,
    )
    .filter(Boolean),
  [2, 7, 9, 13],
  "Europe Reborn principal interactions should remain in movements 2, 7, 9 and 13.",
);
assert.deepEqual(
  europeReborn.movements
    .map((movement) => movement.interaction?.kind)
    .filter((kind) => kind && principalCommonwealthInteractionKinds.has(kind)),
  [
    "commonwealth-city",
    "written-network",
    "realm-partition",
    "conversion-roads",
  ],
  "Europe Reborn should preserve its city, writing, partition and conversion sequence.",
);
assert.deepEqual(
  europeReborn.movements
    .map((movement, index) =>
      movement.interaction?.kind === "commonwealth-trace" ? index + 1 : null,
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
      (movementSum, paragraph) =>
        movementSum + paragraph.trim().split(/\s+/).length,
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
const papalRevolutionScene = scenes.find(
  (scene) => scene.id === europeReborn.nextHash,
);
assert.ok(
  papalRevolutionScene,
  "Europe Reborn ending needs a real next scene.",
);
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

await checkCommonChapter(papalRevolution, 12);
assert.deepEqual(
  papalRevolution.acts?.map((act) => act.id),
  ["reform-rome", "two-burdens", "broken-communion", "divided-ceremony"],
  "The Papal Revolution should preserve its four-act jurisdictional progression.",
);
assert.deepEqual(
  (papalRevolution.acts ?? []).map(
    (act) =>
      papalRevolution.movements.filter((movement) => movement.actId === act.id)
        .length,
  ),
  [3, 3, 3, 3],
  "The Papal Revolution acts should contain three movements each.",
);
const principalPapalInteractionKinds = new Set([
  "papal-court",
  "bishop-burden",
  "canossa-sequence",
  "investiture-settlement",
]);
assert.deepEqual(
  papalRevolution.movements
    .map((movement, index) =>
      movement.interaction &&
      principalPapalInteractionKinds.has(movement.interaction.kind)
        ? index + 1
        : null,
    )
    .filter(Boolean),
  [2, 5, 8, 12],
  "The Papal Revolution principal interactions should remain in movements 2, 5, 8 and 12.",
);
assert.deepEqual(
  papalRevolution.movements
    .map((movement, index) =>
      movement.interaction?.kind === "papal-trace" ? index + 1 : null,
    )
    .filter(Boolean),
  [3, 4, 6, 9, 11],
  "The Papal Revolution lighter traces should remain in movements 3, 4, 6, 9 and 11.",
);
for (const movement of papalRevolution.movements) {
  if (movement.interaction?.kind !== "papal-trace") continue;
  assert.equal(
    movement.interaction.stops.length,
    3,
    `Papal trace ${movement.id} should have three thumb-friendly stops.`,
  );
}
const papalRevolutionWords = papalRevolution.movements.reduce(
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
  papalRevolutionWords >= 2000 && papalRevolutionWords <= 2500,
  `The Papal Revolution should contain 2,000–2,500 words of continuous narrative; found ${papalRevolutionWords}.`,
);
assert.equal(
  papalRevolutionScene?.chronicle?.href,
  "chapters/papal-revolution/",
  "The main journey needs a working Papal Revolution chapter link.",
);
assert.equal(
  papalRevolutionScene?.chronicle?.label,
  "Enter the contested order",
  "The Papal Revolution chapter link needs its historical invitation.",
);
const societyBeyondKinScene = scenes.find(
  (scene) => scene.id === papalRevolution.nextHash,
);
assert.ok(
  societyBeyondKinScene,
  "The Papal Revolution ending needs a real next scene.",
);
assert.equal(
  papalRevolution.nextTitle,
  societyBeyondKinScene.title,
  "The Papal Revolution ending title must match its actual next scene.",
);
assert.equal(
  papalRevolution.ending.nextPeriod,
  `AD ${societyBeyondKinScene.period.label}`,
  "The Papal Revolution ending period must match its actual next scene.",
);

await checkCommonChapter(societyBeyondKin, 12);
assert.deepEqual(
  societyBeyondKin.acts?.map((act) => act.id),
  ["break-clan", "chosen-brothers", "city-swears", "body-endures"],
  "A Society Beyond Kin should preserve its four-act blood-to-oath progression.",
);
assert.deepEqual(
  (societyBeyondKin.acts ?? []).map(
    (act) =>
      societyBeyondKin.movements.filter((movement) => movement.actId === act.id)
        .length,
  ),
  [3, 3, 3, 3],
  "A Society Beyond Kin acts should contain three movements each.",
);
const principalKinInteractionKinds = new Set([
  "kin-marriage",
  "chosen-house",
  "sworn-commune",
  "immortal-body",
]);
assert.deepEqual(
  societyBeyondKin.movements
    .map((movement, index) =>
      movement.interaction &&
      principalKinInteractionKinds.has(movement.interaction.kind)
        ? index + 1
        : null,
    )
    .filter(Boolean),
  [2, 5, 8, 12],
  "A Society Beyond Kin principal interactions should remain in movements 2, 5, 8 and 12.",
);
assert.deepEqual(
  societyBeyondKin.movements
    .map((movement) => movement.interaction?.kind)
    .filter((kind) => kind && principalKinInteractionKinds.has(kind)),
  ["kin-marriage", "chosen-house", "sworn-commune", "immortal-body"],
  "A Society Beyond Kin should preserve its marriage, house, commune and corporate-body sequence.",
);
assert.deepEqual(
  societyBeyondKin.movements
    .map((movement, index) =>
      movement.interaction?.kind === "kin-trace" ? index + 1 : null,
    )
    .filter(Boolean),
  [3, 6, 9, 11],
  "A Society Beyond Kin lighter traces should remain in movements 3, 6, 9 and 11.",
);
for (const movement of societyBeyondKin.movements) {
  if (movement.interaction?.kind !== "kin-trace") continue;
  assert.equal(
    movement.interaction.stops.length,
    3,
    `Kin trace ${movement.id} should have three thumb-friendly stops.`,
  );
}
const societyBeyondKinWords = societyBeyondKin.movements.reduce(
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
  societyBeyondKinWords >= 2100 && societyBeyondKinWords <= 3000,
  `A Society Beyond Kin should contain 2,100–3,000 words of continuous narrative; found ${societyBeyondKinWords}.`,
);
assert.equal(
  societyBeyondKinScene?.chronicle?.href,
  "chapters/society-beyond-kin/",
  "The main journey needs a working A Society Beyond Kin chapter link.",
);
assert.equal(
  societyBeyondKinScene?.chronicle?.label,
  "Cross the forbidden line",
  "The A Society Beyond Kin chapter link needs its historical invitation.",
);
const commercialRevolutionScene = scenes.find(
  (scene) => scene.id === societyBeyondKin.nextHash,
);
assert.ok(
  commercialRevolutionScene,
  "A Society Beyond Kin ending needs a real next scene.",
);
assert.equal(
  societyBeyondKin.nextTitle,
  commercialRevolutionScene.title,
  "A Society Beyond Kin ending title must match its actual next scene.",
);
assert.equal(
  societyBeyondKin.ending.nextPeriod,
  `AD ${commercialRevolutionScene.period.label}`,
  "A Society Beyond Kin ending period must match its actual next scene.",
);

await checkCommonChapter(medievalCommercialRevolution, 12);
assert.deepEqual(
  medievalCommercialRevolution.acts?.map((act) => act.id),
  [
    "market-keeps-appointment",
    "risk-acquires-boundary",
    "promise-travels",
    "enterprise-remembers",
  ],
  "The Medieval Commercial Revolution should preserve its four-act progression.",
);
for (const act of medievalCommercialRevolution.acts ?? []) {
  assert.equal(
    medievalCommercialRevolution.movements.filter(
      (movement) => movement.actId === act.id,
    ).length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  medievalCommercialRevolution.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [3, 6, 9, 11],
  "The Medieval Commercial Revolution interactions should appear in movements 3, 6, 9 and 11.",
);
assert.deepEqual(
  medievalCommercialRevolution.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "ledger-voyage", "chapter-v2", "chapter-v2"],
  "The Medieval Commercial Revolution should preserve its fair, voyage, settlement and insurance sequence.",
);
const ledgerVoyage = medievalCommercialRevolution.movements[5].interaction;
assert.ok(
  ledgerVoyage?.kind === "ledger-voyage",
  "The Medieval Commercial Revolution needs its financed-voyage interaction.",
);
assert.equal(
  ledgerVoyage.allocations.reduce(
    (sum, allocation) => sum + allocation.amount,
    0,
  ),
  ledgerVoyage.capital,
  "The voyage allocations must equal subscribed capital.",
);
for (const outcome of ledgerVoyage.outcomes) {
  assert.ok(
    outcome.loss >= 0 && outcome.loss <= ledgerVoyage.capital,
    `Voyage loss ${outcome.id} must stay within subscribed capital.`,
  );
}
const medievalCommercialRevolutionWords =
  medievalCommercialRevolution.movements.reduce(
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
  medievalCommercialRevolutionWords >= 2800 &&
    medievalCommercialRevolutionWords <= 3400,
  `The Medieval Commercial Revolution should contain 2,800–3,400 words of continuous narrative; found ${medievalCommercialRevolutionWords}.`,
);
assert.equal(
  commercialRevolutionScene?.chronicle?.href,
  "chapters/medieval-commercial-revolution/",
  "The main journey needs a working Medieval Commercial Revolution chapter link.",
);
assert.equal(
  commercialRevolutionScene?.chronicle?.label,
  "Follow the written road",
  "The Medieval Commercial Revolution chapter link needs its historical invitation.",
);
const hanseaticNorthScene = scenes.find(
  (scene) => scene.id === medievalCommercialRevolution.nextHash,
);
assert.ok(
  hanseaticNorthScene,
  "The Medieval Commercial Revolution ending needs a real next scene.",
);
assert.equal(
  medievalCommercialRevolution.nextTitle,
  hanseaticNorthScene.title,
  "The Medieval Commercial Revolution ending title must match its actual next scene.",
);
assert.equal(
  medievalCommercialRevolution.ending.nextPeriod,
  `AD ${hanseaticNorthScene.period.label}`,
  "The Medieval Commercial Revolution ending period must match its actual next scene.",
);
assert.equal(
  medievalCommercialRevolution.nextSlug,
  hanseaticNorth.slug,
  "The Medieval Commercial Revolution ending should continue into the Hanseatic chapter.",
);

await checkCommonChapter(hanseaticNorth, 12);
assert.deepEqual(
  hanseaticNorth.acts?.map((act) => act.id),
  [
    "harbour-feeds-north",
    "privilege-builds-house",
    "cities-act-together",
    "edges-hold-league",
  ],
  "The Hanseatic North should preserve its harbour-to-league progression.",
);
for (const act of hanseaticNorth.acts ?? []) {
  assert.equal(
    hanseaticNorth.movements.filter((movement) => movement.actId === act.id)
      .length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  hanseaticNorth.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 5, 8, 11],
  "The Hanseatic North interactions should appear in movements 2, 5, 8 and 11.",
);
assert.deepEqual(
  hanseaticNorth.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Hanseatic North should use the northern year, Bryggen yard, covenant and Kontor sequence.",
);
const hanseaticNorthWords = hanseaticNorth.movements.reduce(
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
  hanseaticNorthWords >= 2800 && hanseaticNorthWords <= 3400,
  `The Hanseatic North should contain 2,800–3,400 words of continuous narrative; found ${hanseaticNorthWords}.`,
);
assert.equal(
  hanseaticNorthScene?.chronicle?.href,
  "chapters/hanseatic-north/",
  "The main journey needs a working Hanseatic North chapter link.",
);
assert.equal(
  hanseaticNorthScene?.chronicle?.label,
  "Enter the northern harbour",
  "The Hanseatic North chapter link needs its historical invitation.",
);
const empireManyLibertiesScene = scenes.find(
  (scene) => scene.id === hanseaticNorth.nextHash,
);
assert.ok(
  empireManyLibertiesScene,
  "The Hanseatic North ending needs a real next scene.",
);
assert.equal(
  hanseaticNorth.nextTitle,
  empireManyLibertiesScene.title,
  "The Hanseatic North ending title must match its actual next scene.",
);
assert.equal(
  hanseaticNorth.ending.nextPeriod,
  `AD ${empireManyLibertiesScene.period.label}`,
  "The Hanseatic North ending period must match its actual next scene.",
);
assert.equal(
  hanseaticNorth.nextSlug,
  empireManyLiberties.slug,
  "The Hanseatic North ending should continue into the Empire of Many Liberties chapter.",
);

await checkCommonChapter(empireManyLiberties, 12);
assert.deepEqual(
  empireManyLiberties.acts?.map((act) => act.id),
  [
    "crown-travels",
    "liberty-becomes-right",
    "realm-reforms-itself",
    "difference-inside-peace",
  ],
  "The Empire of Many Liberties should preserve its crown-to-constitutional-peace progression.",
);
assert.deepEqual(
  empireManyLiberties.acts?.map(
    (act) =>
      empireManyLiberties.movements.filter(
        (movement) => movement.actId === act.id,
      ).length,
  ),
  [2, 4, 3, 3],
  "The Empire of Many Liberties should move from the travelling crown through an expanded account of accumulated rights, then into reform and constitutional peace.",
);
assert.deepEqual(
  empireManyLiberties.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 6, 8, 11],
  "The Empire of Many Liberties interactions should appear in movements 2, 6, 8 and 11.",
);
assert.deepEqual(
  empireManyLiberties.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Empire of Many Liberties should use the itinerary, election, Diet and Westphalian-constitution sequence.",
);
const empireManyLibertiesWords = empireManyLiberties.movements.reduce(
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
  empireManyLibertiesWords >= 3000 && empireManyLibertiesWords <= 3500,
  `The Empire of Many Liberties should contain 3,000–3,500 words of continuous narrative; found ${empireManyLibertiesWords}.`,
);
assert.equal(
  empireManyLibertiesScene?.chronicle?.href,
  "chapters/empire-many-liberties/",
  "The main journey needs a working Empire of Many Liberties chapter link.",
);
assert.equal(
  empireManyLibertiesScene?.chronicle?.label,
  "Enter the imperial assembly",
  "The Empire of Many Liberties chapter link needs its historical invitation.",
);
const frontiersHoldScene = scenes.find(
  (scene) => scene.id === empireManyLiberties.nextHash,
);
assert.ok(
  frontiersHoldScene,
  "The Empire of Many Liberties ending needs a real next scene.",
);
assert.equal(
  empireManyLiberties.nextTitle,
  frontiersHoldScene.title,
  "The Empire of Many Liberties ending title must match its actual next scene.",
);
assert.equal(
  empireManyLiberties.ending.nextPeriod,
  `AD ${frontiersHoldScene.period.label}`,
  "The Empire of Many Liberties ending period must match its actual next scene.",
);
assert.equal(
  empireManyLiberties.nextSlug,
  europeHoldsTheLine.slug,
  "The Empire of Many Liberties ending should continue into The Frontiers Hold chapter.",
);

await checkCommonChapter(europeHoldsTheLine, 14);
assert.deepEqual(
  europeHoldsTheLine.acts?.map((act) => act.id),
  [
    "western-edge-survives",
    "eastern-wall-calls",
    "europe-becomes-fortress",
    "coalition-turns-line",
  ],
  "The Frontiers Hold should preserve its Iberian-survival-to-coalition-recovery progression.",
);
assert.deepEqual(
  europeHoldsTheLine.acts?.map(
    (act) =>
      europeHoldsTheLine.movements.filter(
        (movement) => movement.actId === act.id,
      ).length,
  ),
  [4, 4, 3, 3],
  "The Frontiers Hold should give full weight to the western and eastern frontiers before the coalition turns the line.",
);
assert.deepEqual(
  europeHoldsTheLine.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 6, 10, 14],
  "The Frontiers Hold interactions should appear in movements 2, 6, 10 and 14.",
);
assert.deepEqual(
  europeHoldsTheLine.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Frontiers Hold should use four frontier-hinge interactions.",
);
const europeHoldsTheLineWords = europeHoldsTheLine.movements.reduce(
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
  europeHoldsTheLineWords >= 3300 && europeHoldsTheLineWords <= 3800,
  `The Frontiers Hold should contain 3,300–3,800 words of continuous narrative; found ${europeHoldsTheLineWords}.`,
);
assert.equal(
  frontiersHoldScene?.chronicle?.href,
  "chapters/europe-holds-the-line/",
  "The main journey needs a working Frontiers Hold chapter link.",
);
assert.equal(
  frontiersHoldScene?.chronicle?.label,
  "Hold the line",
  "The Frontiers Hold chapter link needs its historical invitation.",
);
const europeTurnsSeawardScene = scenes.find(
  (scene) => scene.id === europeHoldsTheLine.nextHash,
);
assert.ok(
  europeTurnsSeawardScene,
  "The Frontiers Hold ending needs a real next scene.",
);
assert.equal(
  europeHoldsTheLine.nextTitle,
  europeTurnsSeawardScene.title,
  "The Frontiers Hold ending title must match its actual next scene.",
);
assert.equal(
  europeHoldsTheLine.ending.nextPeriod,
  `AD ${europeTurnsSeawardScene.period.label}`,
  "The Frontiers Hold ending period must match its actual next scene.",
);
assert.equal(
  europeHoldsTheLine.nextSlug,
  europeTurnsSeaward.slug,
  "The Frontiers Hold ending should continue into Europe Turns Seaward.",
);

await checkCommonChapter(europeTurnsSeaward, 12);
assert.deepEqual(
  europeTurnsSeaward.acts?.map((act) => act.id),
  [
    "atlantic-becomes-school",
    "coast-opens-ocean",
    "routes-enclose-earth",
    "voyages-become-systems",
  ],
  "Europe Turns Seaward should preserve its Atlantic-school-to-ocean-system progression.",
);
for (const act of europeTurnsSeaward.acts ?? []) {
  assert.equal(
    europeTurnsSeaward.movements.filter(
      (movement) => movement.actId === act.id,
    ).length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  europeTurnsSeaward.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [3, 6, 8, 10],
  "Europe Turns Seaward interactions should appear in movements 3, 6, 8 and 10.",
);
assert.deepEqual(
  europeTurnsSeaward.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "Europe Turns Seaward should use four ocean-route interactions.",
);
const europeTurnsSeawardWords = europeTurnsSeaward.movements.reduce(
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
  europeTurnsSeawardWords >= 2900 && europeTurnsSeawardWords <= 3400,
  `Europe Turns Seaward should contain 2,900–3,400 words of continuous narrative; found ${europeTurnsSeawardWords}.`,
);
assert.equal(
  europeTurnsSeawardScene?.chronicle?.href,
  "chapters/europe-turns-seaward/",
  "The main journey needs a working Europe Turns Seaward chapter link.",
);
assert.equal(
  europeTurnsSeawardScene?.chronicle?.label,
  "Unroll the ocean",
  "The Europe Turns Seaward chapter link needs its historical invitation.",
);
const reformationScene = scenes.find(
  (scene) => scene.id === europeTurnsSeaward.nextHash,
);
assert.ok(
  reformationScene,
  "Europe Turns Seaward ending needs a real next scene.",
);
assert.equal(
  europeTurnsSeaward.nextTitle,
  reformationScene.title,
  "Europe Turns Seaward ending title must match its actual next scene.",
);
assert.equal(
  europeTurnsSeaward.ending.nextPeriod,
  `AD ${reformationScene.period.label}`,
  "Europe Turns Seaward ending period must match its actual next scene.",
);
assert.equal(
  europeTurnsSeaward.nextSlug,
  reformation.slug,
  "Europe Turns Seaward ending should continue into The Reformation.",
);

await checkCommonChapter(reformation, 14);
assert.deepEqual(
  reformation.acts?.map((act) => act.id),
  [
    "argument-escapes",
    "confessions-build-worlds",
    "empire-burns",
    "peace-in-ruins",
  ],
  "The Reformation should preserve its printed-argument-to-Westphalian-peace progression.",
);
assert.deepEqual(
  reformation.acts?.map(
    (act) =>
      reformation.movements.filter((movement) => movement.actId === act.id)
        .length,
  ),
  [3, 4, 4, 3],
  "The Reformation should give at least equal structural weight to the Thirty Years' War and its settlement.",
);
assert.deepEqual(
  reformation.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [1, 5, 9, 13],
  "The Reformation interactions should appear in movements 1, 5, 9 and 13.",
);
assert.deepEqual(
  reformation.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Reformation should use four burned-Empire interactions.",
);
const reformationMovementWords = reformation.movements.map((movement) =>
  movement.body.reduce(
    (sum, paragraph) => sum + paragraph.trim().split(/\s+/).length,
    0,
  ),
);
const reformationWords = reformationMovementWords.reduce(
  (sum, words) => sum + words,
  0,
);
assert.ok(
  reformationWords >= 3500 && reformationWords <= 4000,
  `The Reformation should contain 3,500–4,000 words of continuous narrative; found ${reformationWords}.`,
);
assert.ok(
  reformationMovementWords.slice(7).reduce((sum, words) => sum + words, 0) >=
    reformationMovementWords.slice(0, 7).reduce(
      (sum, words) => sum + words,
      0,
    ),
  "The Thirty Years' War and the peace must receive at least as much narrative space as the Reformation's first century.",
);
assert.equal(
  reformationScene?.chronicle?.href,
  "chapters/reformation/",
  "The main journey needs a working Reformation chapter link.",
);
assert.equal(
  reformationScene?.chronicle?.label,
  "Read the burned Empire",
  "The Reformation chapter link needs its historical invitation.",
);
const habsburgEuropeScene = scenes.find(
  (scene) => scene.id === reformation.nextHash,
);
assert.ok(
  habsburgEuropeScene,
  "The Reformation ending needs a real next scene.",
);
assert.equal(
  reformation.nextTitle,
  habsburgEuropeScene.title,
  "The Reformation ending title must match its actual next scene.",
);
assert.equal(
  reformation.ending.nextPeriod,
  `AD ${habsburgEuropeScene.period.label}`,
  "The Reformation ending period must match its actual next scene.",
);

await checkCommonChapter(habsburgEurope, 14);
assert.deepEqual(
  habsburgEurope.acts?.map((act) => act.id),
  [
    "three-crowns",
    "monarchy-learns-scale",
    "liberty-enters",
    "common-home",
  ],
  "Habsburg Europe should preserve its three-crowns-to-common-home progression.",
);
assert.deepEqual(
  habsburgEurope.acts?.map(
    (act) =>
      habsburgEurope.movements.filter(
        (movement) => movement.actId === act.id,
      ).length,
  ),
  [4, 4, 3, 3],
  "Habsburg Europe should build the composite monarchy fully before following liberty and common life into 1918.",
);
assert.deepEqual(
  habsburgEurope.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [1, 6, 10, 12],
  "Habsburg Europe interactions should appear in movements 1, 6, 10 and 12.",
);
assert.deepEqual(
  habsburgEurope.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "Habsburg Europe should use four braided-Danube interactions.",
);
const habsburgEuropeWords = habsburgEurope.movements.reduce(
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
  habsburgEuropeWords >= 4200 && habsburgEuropeWords <= 4700,
  `Habsburg Europe should contain 4,200–4,700 words of continuous narrative; found ${habsburgEuropeWords}.`,
);
assert.match(
  `${habsburgEurope.claim} ${habsburgEurope.ending.title} ${habsburgEurope.ending.detail}`,
  /common (?:political )?home|common home/i,
  "Habsburg Europe should leave the lost common home at the centre of its final memory.",
);
assert.equal(
  habsburgEuropeScene?.chronicle?.href,
  "chapters/habsburg-europe/",
  "The main journey needs a working Habsburg Europe chapter link.",
);
assert.equal(
  habsburgEuropeScene?.chronicle?.label,
  "Enter the braided current",
  "The Habsburg Europe chapter link needs its historical invitation.",
);
const scientificRevolutionScene = scenes.find(
  (scene) => scene.id === habsburgEurope.nextHash,
);
assert.ok(
  scientificRevolutionScene,
  "Habsburg Europe ending needs a real next scene.",
);
assert.equal(
  habsburgEurope.nextTitle,
  scientificRevolutionScene.title,
  "Habsburg Europe ending title must match its actual next scene.",
);
assert.equal(
  habsburgEurope.ending.nextPeriod,
  `AD ${scientificRevolutionScene.period.label}`,
  "Habsburg Europe ending period must match its actual next scene.",
);

await checkCommonChapter(scientificRevolution, 12);
assert.deepEqual(
  scientificRevolution.acts?.map((act) => act.id),
  [
    "ancient-page-on-trial",
    "nature-mathematical-voice",
    "experiment-becomes-instrument",
    "knowledge-learns-to-accumulate",
  ],
  "The Scientific Revolution should preserve its measured-page progression from inherited authority to cumulative knowledge.",
);
for (const act of scientificRevolution.acts ?? []) {
  assert.equal(
    scientificRevolution.movements.filter(
      (movement) => movement.actId === act.id,
    ).length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  scientificRevolution.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [1, 4, 7, 10],
  "The Scientific Revolution interactions should appear in movements 1, 4, 7 and 10.",
);
assert.deepEqual(
  scientificRevolution.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Scientific Revolution should use four measured-page interactions.",
);
const scientificRevolutionWords = scientificRevolution.movements.reduce(
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
  scientificRevolutionWords >= 2900 && scientificRevolutionWords <= 3350,
  `The Scientific Revolution should contain 2,900–3,350 words of continuous narrative; found ${scientificRevolutionWords}.`,
);
const scientificRevolutionPublicCopy = JSON.stringify(scientificRevolution);
assert.doesNotMatch(
  scientificRevolutionPublicCopy,
  /\bchurch(?:es)?\b/i,
  "The Scientific Revolution should keep the Church outside the chapter's foreground.",
);
assert.match(
  scientificRevolution.claim,
  /no earlier intellectual system|cumulative/i,
  "The Scientific Revolution should state the unmatched scale of Europe's cumulative achievement.",
);
assert.equal(
  scientificRevolutionScene?.chronicle?.href,
  "chapters/scientific-revolution/",
  "The main journey needs a working Scientific Revolution chapter link.",
);
assert.equal(
  scientificRevolutionScene?.chronicle?.label,
  "Set the measuring line",
  "The Scientific Revolution chapter link needs its historical invitation.",
);
const dutchRepublicScene = scenes.find(
  (scene) => scene.id === scientificRevolution.nextHash,
);
assert.ok(
  dutchRepublicScene,
  "The Scientific Revolution ending needs a real next scene.",
);
assert.equal(
  scientificRevolution.nextTitle,
  dutchRepublicScene.title,
  "The Scientific Revolution ending title must match its actual next scene.",
);
assert.equal(
  scientificRevolution.ending.nextPeriod,
  `AD ${dutchRepublicScene.period.label}`,
  "The Scientific Revolution ending period must match its actual next scene.",
);

await checkCommonChapter(dutchRepublic, 12);
assert.deepEqual(
  dutchRepublic.acts?.map((act) => act.id),
  [
    "republic-rises",
    "water-ships-system",
    "trust-machinery",
    "republic-commands-distance",
  ],
  "The Dutch Republic should preserve its exchange-hall progression from revolt to a system that commands distance.",
);
for (const act of dutchRepublic.acts ?? []) {
  assert.equal(
    dutchRepublic.movements.filter((movement) => movement.actId === act.id)
      .length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  dutchRepublic.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 5, 8, 11],
  "The Dutch Republic interactions should appear in movements 2, 5, 8 and 11.",
);
assert.deepEqual(
  dutchRepublic.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Dutch Republic should use four exchange-hall interactions.",
);
const dutchRepublicWords = dutchRepublic.movements.reduce(
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
  dutchRepublicWords >= 3050 && dutchRepublicWords <= 3500,
  `The Dutch Republic should contain 3,050–3,500 words of continuous narrative; found ${dutchRepublicWords}.`,
);
assert.match(
  `${dutchRepublic.claim} ${dutchRepublic.ending.detail}`,
  /ships|credit|exchange|capital/i,
  "The Dutch Republic should keep its great commercial and institutional achievements in the foreground.",
);
assert.equal(
  dutchRepublicScene?.chronicle?.href,
  "chapters/dutch-republic/",
  "The main journey needs a working Dutch Republic chapter link.",
);
assert.equal(
  dutchRepublicScene?.chronicle?.label,
  "Ring the exchange bell",
  "The Dutch Republic chapter link needs its historical invitation.",
);
const enlightenmentScene = scenes.find(
  (scene) => scene.id === dutchRepublic.nextHash,
);
assert.ok(
  enlightenmentScene,
  "The Dutch Republic ending needs a real next scene.",
);
assert.equal(
  dutchRepublic.nextTitle,
  enlightenmentScene.title,
  "The Dutch Republic ending title must match its actual next scene.",
);
assert.equal(
  dutchRepublic.ending.nextPeriod,
  `AD ${enlightenmentScene.period.label}`,
  "The Dutch Republic ending period must match its actual next scene.",
);

await checkCommonChapter(enlightenmentPublicOpinion, 12);
assert.deepEqual(
  enlightenmentPublicOpinion.acts?.map((act) => act.id),
  [
    "news-daily-appetite",
    "public-learns-to-judge",
    "continent-thinks-in-company",
    "opinion-enters-government",
  ],
  "The Enlightenment should preserve its continent-in-conversation progression from news to public authority.",
);
for (const act of enlightenmentPublicOpinion.acts ?? []) {
  assert.equal(
    enlightenmentPublicOpinion.movements.filter(
      (movement) => movement.actId === act.id,
    ).length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  enlightenmentPublicOpinion.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [1, 5, 7, 10],
  "The Enlightenment interactions should appear in movements 1, 5, 7 and 10.",
);
assert.deepEqual(
  enlightenmentPublicOpinion.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Enlightenment should use four continent-in-conversation interactions.",
);
const enlightenmentWords = enlightenmentPublicOpinion.movements.reduce(
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
  enlightenmentWords >= 2750 && enlightenmentWords <= 3200,
  `The Enlightenment should contain 2,750–3,200 words of continuous narrative; found ${enlightenmentWords}.`,
);
const russianEnlightenmentMovement = enlightenmentPublicOpinion.movements.find(
  (movement) => movement.id === "the-letter-stops-at-the-palace",
);
assert.ok(
  russianEnlightenmentMovement,
  "The Enlightenment needs its discreet Catherine–Novikov contrast.",
);
assert.match(
  russianEnlightenmentMovement.body.join(" "),
  /No comparably durable constellation of independent presses, corporate bodies and representative institutions/i,
  "The Russian passage should show why no equivalent independent public sphere became durable there.",
);
assert.equal(
  enlightenmentScene?.chronicle?.href,
  "chapters/enlightenment-public-opinion/",
  "The main journey needs a working Enlightenment chapter link.",
);
assert.equal(
  enlightenmentScene?.chronicle?.label,
  "Send the marked sentence",
  "The Enlightenment chapter link needs its historical invitation.",
);
const industrialBreakthroughScene = scenes.find(
  (scene) => scene.id === enlightenmentPublicOpinion.nextHash,
);
assert.ok(
  industrialBreakthroughScene,
  "The Enlightenment ending needs a real next scene.",
);
assert.equal(
  enlightenmentPublicOpinion.nextTitle,
  industrialBreakthroughScene.title,
  "The Enlightenment ending title must match its actual next scene.",
);
assert.equal(
  enlightenmentPublicOpinion.ending.nextPeriod,
  `AD ${industrialBreakthroughScene.period.label}`,
  "The Enlightenment ending period must match its actual next scene.",
);

await checkCommonChapter(rivalryIndustrialBreakthrough, 12);
assert.deepEqual(
  rivalryIndustrialBreakthrough.acts?.map((act) => act.id),
  [
    "power-from-stone",
    "machine-learns-to-multiply",
    "line-conquers-distance",
    "capital-becomes-institution",
  ],
  "The Industrial Breakthrough should preserve its capital-line progression from coal to the registered company.",
);
for (const act of rivalryIndustrialBreakthrough.acts ?? []) {
  assert.equal(
    rivalryIndustrialBreakthrough.movements.filter(
      (movement) => movement.actId === act.id,
    ).length,
    3,
    `Act ${act.id} should contain exactly three movements.`,
  );
}
assert.deepEqual(
  rivalryIndustrialBreakthrough.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 5, 8, 11],
  "The Industrial Breakthrough interactions should appear in movements 2, 5, 8 and 11.",
);
assert.deepEqual(
  rivalryIndustrialBreakthrough.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Industrial Breakthrough should use four capital-line interactions.",
);
const industrialBreakthroughWords =
  rivalryIndustrialBreakthrough.movements.reduce(
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
  industrialBreakthroughWords >= 2850 &&
    industrialBreakthroughWords <= 3250,
  `The Industrial Breakthrough should contain 2,850–3,250 words of continuous narrative; found ${industrialBreakthroughWords}.`,
);
const industrialBreakthroughPublicCopy = JSON.stringify(
  rivalryIndustrialBreakthrough,
);
for (const statutoryYear of ["1855", "1856", "1862"]) {
  assert.match(
    industrialBreakthroughPublicCopy,
    new RegExp(`\\b${statutoryYear}\\b`),
    `The limited-liability sequence must preserve the ${statutoryYear} statutory milestone.`,
  );
}
assert.match(
  rivalryIndustrialBreakthrough.claim,
  /limited-liability company/i,
  "The Industrial Breakthrough must make Europe's limited-liability invention part of its central claim.",
);
assert.equal(
  industrialBreakthroughScene?.chronicle?.href,
  "chapters/rivalry-industrial-breakthrough/",
  "The main journey needs a working Industrial Breakthrough chapter link.",
);
assert.equal(
  industrialBreakthroughScene?.chronicle?.label,
  "Set power in motion",
  "The Industrial Breakthrough chapter link needs its historical invitation.",
);
const europeanWorldScene = scenes.find(
  (scene) => scene.id === rivalryIndustrialBreakthrough.nextHash,
);
assert.ok(
  europeanWorldScene,
  "The Industrial Breakthrough ending needs a real next scene.",
);
assert.equal(
  rivalryIndustrialBreakthrough.nextTitle,
  europeanWorldScene.title,
  "The Industrial Breakthrough ending title must match its actual next scene.",
);
assert.equal(
  rivalryIndustrialBreakthrough.ending.nextPeriod,
  `AD ${europeanWorldScene.period.label}`,
  "The Industrial Breakthrough ending period must match its actual next scene.",
);

await checkCommonChapter(europeanWorld, 14);
assert.deepEqual(
  europeanWorld.acts?.map((act) => act.id),
  [
    "oceans-obey-schedule",
    "world-learns-protocols",
    "steel-enters-continents",
    "europe-takes-central-desk",
  ],
  "The European World should preserve its switchboard progression from scheduled oceans to the central desk.",
);
assert.deepEqual(
  europeanWorld.acts?.map(
    (act) =>
      europeanWorld.movements.filter(
        (movement) => movement.actId === act.id,
      ).length,
  ),
  [4, 3, 4, 3],
  "The European World should give the oceanic system and its inland institutional inheritance full structural weight.",
);
assert.deepEqual(
  europeanWorld.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 5, 8, 14],
  "The European World interactions should appear in movements 2, 5, 8 and 14.",
);
assert.deepEqual(
  europeanWorld.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The European World should use four world-switchboard interactions.",
);
const europeanWorldWords = europeanWorld.movements.reduce(
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
  europeanWorldWords >= 3450 && europeanWorldWords <= 3950,
  `The European World should contain 3,450–3,950 words of continuous narrative; found ${europeanWorldWords}.`,
);
const europeanWorldPublicCopy = JSON.stringify(europeanWorld);
for (const achievement of [
  "abolition",
  "railway",
  "sanitary",
  "administrative",
]) {
  assert.match(
    europeanWorldPublicCopy,
    new RegExp(achievement, "i"),
    `The European World should preserve ${achievement} as part of Europe's enduring institutional work.`,
  );
}
assert.doesNotMatch(
  europeanWorldPublicCopy,
  /\b(?:our narrative|this chapter|critics? (?:say|argue)|accused? of racism)\b/i,
  "The European World should tell its story directly without a defensive or meta-historical aside.",
);
assert.equal(
  europeanWorldScene?.chronicle?.href,
  "chapters/european-world/",
  "The main journey needs a working European World chapter link.",
);
assert.equal(
  europeanWorldScene?.chronicle?.label,
  "Open the Atlantic circuit",
  "The European World chapter link needs its historical invitation.",
);
const europeanCivilWarScene = scenes.find(
  (scene) => scene.id === europeanWorld.nextHash,
);
assert.ok(
  europeanCivilWarScene,
  "The European World ending needs a real next scene.",
);
assert.equal(
  europeanWorld.nextTitle,
  europeanCivilWarScene.title,
  "The European World ending title must match its actual next scene.",
);
assert.equal(
  europeanWorld.ending.nextPeriod,
  `AD ${europeanCivilWarScene.period.label}`,
  "The European World ending period must match its actual next scene.",
);

await checkCommonChapter(europeAtWar, 14);
assert.equal(
  europeAtWar.title,
  "The European Civil War",
  "Chapter 22 should keep its selected public title.",
);
assert.deepEqual(
  europeAtWar.acts?.map((act) => act.id),
  [
    "armed-peace",
    "industry-enters-battlefield",
    "peace-loses-authority",
    "total-dominion",
  ],
  "The European Civil War should preserve its split-continent progression from armed peace to total dominion.",
);
assert.deepEqual(
  europeAtWar.acts?.map(
    (act) =>
      europeAtWar.movements.filter((movement) => movement.actId === act.id)
        .length,
  ),
  [4, 3, 3, 4],
  "The European Civil War should frame the two wars through their political origins and totalitarian culmination.",
);
assert.deepEqual(
  europeAtWar.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [3, 8, 11, 14],
  "The European Civil War interactions should appear in movements 3, 8, 11 and 14.",
);
assert.deepEqual(
  europeAtWar.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The European Civil War should use four continent-split interactions.",
);
const europeanCivilWarWords = europeAtWar.movements.reduce(
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
  europeanCivilWarWords >= 3900 && europeanCivilWarWords <= 4400,
  `The European Civil War should contain 3,900–4,400 words of continuous narrative; found ${europeanCivilWarWords}.`,
);
const arendtMovements = europeAtWar.movements.filter((movement) =>
  movement.sourceIds.includes("arendt-totalitarianism-1951"),
);
assert.ok(
  arendtMovements.length >= 3,
  "Arendt's account of statelessness, ideology and total domination should structure more than one isolated passage.",
);
assert.equal(
  europeAtWarAssetContract.holocaust.generated,
  false,
  "The Holocaust sequence must never use generated imagery.",
);
assert.equal(
  europeAtWarAssetContract.holocaust.static,
  true,
  "The Holocaust sequence must remain static.",
);
assert.equal(
  europeAtWarAssetContract.holocaust.interactive,
  false,
  "The Holocaust sequence must not turn documentary evidence into an interaction.",
);
assert.deepEqual(
  europeAtWarAssetContract.holocaust.requiredProvenance,
  [
    "institution",
    "source URL",
    "date",
    "location",
    "subject",
    "rights decision",
  ],
  "Every Holocaust asset must retain the full archival provenance record.",
);
const holocaustMovement = europeAtWar.movements.find(
  (movement) => movement.id === "european-jewry-is-marked-for-murder",
);
assert.equal(
  holocaustMovement?.visualTone,
  "archival-only-static",
  "The Holocaust movement must retain its archival-only static treatment.",
);
assert.equal(
  holocaustMovement?.interaction,
  undefined,
  "The Holocaust movement must not contain an interaction.",
);
assert.equal(
  europeanCivilWarScene?.chronicle?.href,
  "chapters/europe-at-war/",
  "The main journey needs a working European Civil War chapter link.",
);
assert.equal(
  europeanCivilWarScene?.chronicle?.label,
  "Open the fault lines",
  "The European Civil War chapter link needs its historical invitation.",
);
const rebuiltContinentScene = scenes.find(
  (scene) => scene.id === europeAtWar.nextHash,
);
assert.ok(
  rebuiltContinentScene,
  "The European Civil War ending needs a real next scene.",
);
assert.equal(
  europeAtWar.nextTitle,
  rebuiltContinentScene.title,
  "The European Civil War ending title must match its actual next scene.",
);
assert.equal(
  europeAtWar.ending.nextPeriod,
  `AD ${rebuiltContinentScene.period.label}`,
  "The European Civil War ending period must match its actual next scene.",
);

await checkCommonChapter(continentRebuilt, 12);
assert.deepEqual(
  continentRebuilt.acts?.map((act) => act.id),
  [
    "two-orders-rise",
    "west-binds-power",
    "east-keeps-nations-alive",
    "roads-meet",
  ],
  "The Continent Rebuilt should preserve its paired-road progression from 1945 to 1989.",
);
assert.deepEqual(
  continentRebuilt.acts?.map(
    (act) =>
      continentRebuilt.movements.filter(
        (movement) => movement.actId === act.id,
      ).length,
  ),
  [3, 3, 4, 2],
  "The Continent Rebuilt should give the eastern nations and the approach to 1989 the required narrative weight.",
);
assert.deepEqual(
  continentRebuilt.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 5, 8, 11],
  "The Continent Rebuilt interactions should appear in movements 2, 5, 8 and 11.",
);
assert.deepEqual(
  continentRebuilt.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "The Continent Rebuilt should use four paired-road interactions.",
);
const continentRebuiltWords = continentRebuilt.movements.reduce(
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
  continentRebuiltWords >= 2950 && continentRebuiltWords <= 3400,
  `The Continent Rebuilt should contain 2,950–3,400 words of continuous narrative; found ${continentRebuiltWords}.`,
);
const polishPopeMovement = continentRebuilt.movements.find(
  (movement) => movement.id === "the-polish-pope-calls-a-nation-into-view",
);
assert.ok(
  polishPopeMovement,
  "The Continent Rebuilt must preserve the Polish pope as a full movement.",
);
assert.match(
  polishPopeMovement.body.join(" "),
  /John Paul II|Karol Wojtyła/,
  "The Polish road to 1989 must name John Paul II and his Polish identity.",
);
const solidarityMovement = continentRebuilt.movements.find(
  (movement) => movement.id === "solidarity-builds-a-public-body",
);
assert.ok(
  solidarityMovement,
  "The Continent Rebuilt must carry the papal opening into Solidarity's independent public body.",
);
assert.equal(
  rebuiltContinentScene?.chronicle?.href,
  "chapters/continent-rebuilt/",
  "The main journey needs a working Continent Rebuilt chapter link.",
);
assert.equal(
  rebuiltContinentScene?.chronicle?.label,
  "Walk the two roads",
  "The Continent Rebuilt chapter link needs its historical invitation.",
);
const europeReturnsScene = scenes.find(
  (scene) => scene.id === continentRebuilt.nextHash,
);
assert.ok(
  europeReturnsScene,
  "The Continent Rebuilt ending needs a real next scene.",
);
assert.equal(
  continentRebuilt.nextTitle,
  europeReturnsScene.title,
  "The Continent Rebuilt ending title must match its actual next scene.",
);
assert.equal(
  continentRebuilt.ending.nextPeriod,
  `AD ${europeReturnsScene.period.label.replace("PRESENT", "20 July 2026")}`,
  "The Continent Rebuilt ending period must match the current chapter's fact-lock range.",
);

await checkCommonChapter(europeReturns, 12);
assert.deepEqual(
  europeReturns.acts?.map((act) => act.id),
  [
    "return-made-by-choice",
    "russia-tests-settlement",
    "war-returns",
    "europe-holds-line",
  ],
  "Europe Returns should preserve its eastern-line progression from voluntary return to defended order.",
);
assert.deepEqual(
  europeReturns.acts?.map(
    (act) =>
      europeReturns.movements.filter((movement) => movement.actId === act.id)
        .length,
  ),
  [4, 3, 3, 2],
  "Europe Returns should give Russia's challenge from Georgia onward and Europe's institutional response full structural weight.",
);
assert.deepEqual(
  europeReturns.movements
    .map((movement, index) => (movement.interaction ? index + 1 : null))
    .filter(Boolean),
  [2, 7, 10, 12],
  "Europe Returns interactions should appear in movements 2, 7, 10 and 12.",
);
assert.deepEqual(
  europeReturns.movements
    .map((movement) => movement.interaction?.kind)
    .filter(Boolean),
  ["chapter-v2", "chapter-v2", "chapter-v2", "chapter-v2"],
  "Europe Returns should use four eastern-line interactions.",
);
const europeReturnsWords = europeReturns.movements.reduce(
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
  europeReturnsWords >= 3150 && europeReturnsWords <= 3600,
  `Europe Returns should contain 3,150–3,600 words of continuous narrative; found ${europeReturnsWords}.`,
);
assert.equal(
  europeReturns.ending.period,
  "As of 20 July 2026",
  "The final chapter must state its exact fact-lock date.",
);
const georgiaMovement = europeReturns.movements.find(
  (movement) => movement.id === "russia-crosses-into-georgia",
);
assert.ok(
  georgiaMovement,
  "Europe Returns must begin Russia's antagonist role with Georgia in 2008.",
);
assert.match(
  georgiaMovement.body.join(" "),
  /Georgia|Tskhinvali|Russia/i,
  "The Georgia passage must preserve the immediate fighting sequence while identifying Russia's larger revisionist project.",
);
assert.match(
  `${europeReturns.claim} ${europeReturns.mapLabel}`,
  /European Union[\s\S]*NATO|NATO[\s\S]*European Union/i,
  "Europe Returns must keep European Union accession and NATO collective defence distinct.",
);
const europeReturnsPublicCopy = JSON.stringify(europeReturns);
assert.match(
  europeReturnsPublicCopy,
  /full-scale invasion/i,
  "Europe Returns must identify Russia's full-scale invasion of Ukraine.",
);
assert.equal(
  europeReturnsScene?.chronicle?.href,
  "chapters/europe-returns/",
  "The main journey needs a working Europe Returns chapter link.",
);
assert.equal(
  europeReturnsScene?.chronicle?.label,
  "Carry the line east",
  "Europe Returns needs its historical invitation in the main journey.",
);

console.log(
  "All twenty-four chapter checks passed.",
);
