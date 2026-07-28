import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { validateFirstFarmersDraft } from "./validate-first-farmers-draft.mjs";

const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const draftPath = path.join(
  repositoryRoot,
  "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json",
);

async function draft() {
  return JSON.parse(await readFile(draftPath, "utf8"));
}

test("validates the complete provisional First Farmers native chapter", async () => {
  const record = await validateFirstFarmersDraft({ repositoryRoot });
  assert.equal(record.status, "CHAPTER_01_REVIEW_TEXT_FROZEN");
  assert.equal(record.arcs.length, 3);
  assert.equal(record.arcs.flatMap(({ beats }) => beats).length, 17);
  assert.equal(record.arcs.flatMap(({ beats }) => beats)
    .flatMap(({ narrative }) => narrative.segments).length, 37);
});

test("rejects approval escalation and academic leakage", async () => {
  const approved = await draft();
  approved.status = "APPROVED";
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: approved }),
    /cannot claim editor approval/,
  );

  const leaked = await draft();
  leaked.arcs[0].beats[0].narrative.segments[0].text =
    "Historians disagree about what the river means.";
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: leaked }),
    /academic or meta language/,
  );
});

test("rejects editorial, arc, interaction and world-effect drift", async () => {
  const thesis = await draft();
  thesis.chapterContract.thesis = "Farming diffused without people.";
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: thesis }),
    /editorial contract/,
  );

  const arc = await draft();
  arc.arcs[0].targetDurationMinutes = 8;
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: arc }),
    /Approved arc field drifted/,
  );

  const grammar = await draft();
  grammar.arcs[1].beats[0].interaction.grammar = "pressure";
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: grammar }),
    /grammar mix drifted/,
  );

  const effect = await draft();
  effect.arcs[2].beats[3].interaction.completionEffectID = "effect-invented";
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: effect }),
    /changed its world effect/,
  );
});

test("rejects a hidden Harvest answer and broken session pacing", async () => {
  const harvest = await draft();
  harvest.arcs[1].beats[0].interaction.requiredUnits = [5, 4, 3];
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: harvest }),
    /hidden exact answer/,
  );

  const pacing = await draft();
  pacing.arcs[2].beats[0].estimatedSeconds += 1;
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: pacing }),
    /pacing does not equal/,
  );
});

test("rejects a second haptic vocabulary", async () => {
  const draftWithLegacySemantic = await draft();
  draftWithLegacySemantic.arcs[0].beats[1].interaction.haptics = [
    "material-contact",
    "historical-consequence",
  ];
  await assert.rejects(
    validateFirstFarmersDraft({
      repositoryRoot,
      draft: draftWithLegacySemantic,
    }),
    /non-canonical haptic semantic/,
  );
});

test("locks the four editor-approved Chapter 01 factual repairs", async () => {
  const arcSituation = await draft();
  arcSituation.arcs[1].situation =
    "A farming household faces winter, spoilage and the obligation to reserve seed for spring.";
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: arcSituation }),
    /Approved arc field drifted|seasonal obligation drifted/u,
  );

  const spring = await draft();
  spring.arcs[1].beats[0].interaction.destinations[2].title = "Spring seed";
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: spring }),
    /public obligations drifted/u,
  );

  const structure = await draft();
  structure.arcs[1].beats[4].narrative.segments[1].text =
    structure.arcs[1].beats[4].narrative.segments[1].text.replace(
      "The next house plot must outlast its first timbers.",
      "The next structure must outlast the first timber frame.",
    );
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: structure }),
    /Longhouse-plot factual repair drifted/u,
  );

  const order = await draft();
  order.arcs[2].beats[0].interaction.components[3].prerequisites = [
    "posts",
    "hearth",
    "storage",
  ];
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: order }),
    /remaining three parts in any order/u,
  );

  const ending = await draft();
  ending.arcs[2].beats[6].narrative.segments[0].text =
    ending.arcs[2].beats[6].narrative.segments[0].text.replace(
      "Their voices were never written down. Their structure remains.",
      "Their languages were never recorded here. Their structure remains.",
    );
  await assert.rejects(
    validateFirstFarmersDraft({ repositoryRoot, draft: ending }),
    /ending factual repair drifted/u,
  );
});
