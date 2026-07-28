import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { validateFirstFarmersDraft } from "./validate-first-farmers-draft.mjs";

const scriptDirectory = path.dirname(new URL(import.meta.url).pathname);
const repositoryRoot = path.resolve(scriptDirectory, "../..");
const generatedRoot = path.join(repositoryRoot, "native/phase2/generated");
const draftPath = path.join(
  repositoryRoot,
  "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json",
);
const chapterPath = path.join(generatedRoot, "first-farmers.chapter.json");
const worldSeedPath = path.join(generatedRoot, "first-farmers.world-seed.json");
const receiptPath = path.join(generatedRoot, "first-farmers.projection-receipt.json");
const version = { major: 1, minor: 0, patch: 0 };

const bytes = (value) => `${JSON.stringify(value, null, 2)}\n`;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const local = (id, launchEnglish) => ({ id, launchEnglish });

function worldSeed() {
  return {
    nodes: [
      {
        id: "western-anatolia",
        kind: "settlement",
        form: "A hidden eastern Aegean point of departure",
        position: { x: 0.76, y: 0.78 },
        attributes: [],
      },
      {
        id: "iron-gates",
        kind: "frontier",
        form: "A hidden inhabited Danube riverbank",
        position: { x: 0.33, y: 0.2 },
        attributes: [],
      },
      {
        id: "trace-seasonal-store",
        kind: "institution",
        form: "An undivided hidden harvest",
        position: { x: 0.56, y: 0.62 },
        attributes: [],
      },
      {
        id: "trace-european-farming-belt",
        kind: "landscape",
        form: "Hidden European farming ground",
        position: { x: 0.5, y: 0.48 },
        attributes: [],
      },
    ],
    traces: [{
      id: "route-aegean-danube",
      kind: "seaRoute",
      origin: "western-anatolia",
      destination: "iron-gates",
      strength: 1,
    }],
  };
}

function effect(effectID) {
  switch (effectID) {
    case "effect-first-farmers-a-household-crosses":
      return {
        id: effectID,
        mutation: "establish-trace",
        trace: {
          id: "route-aegean-danube",
          kind: "seaRoute",
          origin: "western-anatolia",
          destination: "iron-gates",
          strength: 1,
        },
      };
    case "effect-first-farmers-the-harvest-had-to-last":
      return {
        id: effectID,
        mutation: "reveal-node",
        node: {
          id: "trace-seasonal-store",
          kind: "institution",
          form: "A divided store binding winter food, reserve and seed grain",
          position: { x: 0.56, y: 0.62 },
          attributes: [
            { key: "obligations", value: 3 },
            { key: "yearBound", value: true },
          ],
        },
      };
    case "effect-first-farmers-at-the-iron-gates":
      return {
        id: effectID,
        mutation: "set-node-attribute",
        nodeID: "trace-european-farming-belt",
        value: { key: "ironGatesContact", value: true },
      };
    case "effect-first-farmers-the-house-outlives":
      return {
        id: effectID,
        mutation: "reveal-node",
        node: {
          id: "trace-european-farming-belt",
          kind: "landscape",
          form: "A rebuilt longhouse plot anchored to inherited ground",
          position: { x: 0.5, y: 0.48 },
          attributes: [
            { key: "ironGatesContact", value: true },
            { key: "rebuiltHousePlots", value: 1 },
          ],
        },
      };
    case "effect-first-farmers-more-mouths-more-land":
      return {
        id: effectID,
        mutation: "transform-node",
        nodeID: "trace-european-farming-belt",
        form: "New hearths, fields, herd lanes and daughter settlements",
        attributes: [
          { key: "settlementGrowth", value: "expanding" },
          { key: "daughterSettlements", value: true },
        ],
      };
    case "effect-first-farmers-a-continent-remade":
      return {
        id: effectID,
        mutation: "transform-node",
        nodeID: "trace-european-farming-belt",
        form: "Fields, herds, longhouses and inherited ground across the Danube and loess plains",
        attributes: [
          { key: "continental", value: true },
          { key: "readyForSteppeHandoff", value: true },
        ],
      };
    case "effect-first-farmers-chapter-complete":
      return {
        id: effectID,
        mutation: "set-node-attribute",
        nodeID: "trace-european-farming-belt",
        value: { key: "chapterComplete", value: true },
      };
    default:
      throw new Error(`No runtime WorldEffect projection exists for ${effectID}`);
  }
}

function interactionConfiguration(interaction) {
  if (interaction.grammar === "trace") {
    return {
      anchors: interaction.anchors.map(({ x, y }) => ({ x, y })),
      anchorIDs: interaction.anchors.map(({ id }) => id),
      tolerance: interaction.tolerance,
    };
  }
  if (interaction.grammar === "allocate") {
    return {
      resourceName: local(
        `interaction-${interaction.id}-resource-name`,
        interaction.resourceName,
      ),
      totalUnits: interaction.totalUnits,
      destinations: interaction.destinations.map(({ id, minimumUnits }) => ({
        id,
        minimumUnits,
      })),
    };
  }
  if (interaction.grammar === "assemble") {
    return {
      components: interaction.components.map(({ id, targetSlot, prerequisites }) => ({
        id,
        targetSlot,
        prerequisites,
      })),
    };
  }
  if (interaction.grammar === "transform") {
    return {
      stages: interaction.stages.map(({ id, controlID, requiredAmount }) => ({
        id,
        controlID,
        requiredAmount,
      })),
    };
  }
  throw new Error(`Unsupported First Farmers grammar: ${interaction.grammar}`);
}

function projectInteraction(beat) {
  if (!beat.interaction) return undefined;
  return {
    id: beat.interaction.id,
    prompt: local(
      `interaction-${beat.interaction.id}-prompt`,
      beat.narrative.actionPrompt,
    ),
    grammar: beat.interaction.grammar,
    configuration: interactionConfiguration(beat.interaction),
    completionEffects: [effect(beat.interaction.completionEffectID)],
    accessibilityID: `accessibility-${beat.beatID}`,
  };
}

function projectBeat(beat) {
  return {
    id: beat.beatID,
    sceneID: beat.sceneID,
    narrative: {
      eyebrow: local(`${beat.beatID}-eyebrow`, beat.narrative.eyebrow),
      heading: local(`${beat.beatID}-heading`, beat.narrative.heading),
      paragraphs: beat.narrative.segments.map(({ id, text }) => local(id, text)),
      ...(beat.narrative.actionPrompt
        ? { actionPrompt: local(`${beat.beatID}-action-prompt`, beat.narrative.actionPrompt) }
        : {}),
    },
    narrationCueIDs: beat.narrative.segments.map(({ id }) => `narration-${id}`),
    ...(beat.interaction ? { interaction: projectInteraction(beat) } : {}),
    completionEffects: [],
    checkpoint: beat.checkpoint,
  };
}

function projectChapter(draft) {
  return {
    schemaVersion: version,
    id: draft.chapterID,
    title: local("chapter-first-farmers-title", draft.title),
    period: local("chapter-first-farmers-period", draft.period),
    arcs: draft.arcs.map((arc) => ({
      id: arc.arcID,
      title: local(`${arc.arcID}-title`, arc.title),
      targetDurationMinutes: arc.targetDurationMinutes,
      situation: local(`${arc.arcID}-situation`, arc.situation),
      mechanism: local(`${arc.arcID}-mechanism`, arc.mechanism),
      turn: local(`${arc.arcID}-turn`, arc.turn),
      consequence: local(`${arc.arcID}-consequence`, arc.consequence),
      handoff: local(`${arc.arcID}-handoff`, arc.handoff),
      beats: arc.beats.map(projectBeat),
    })),
    completionEffects: [effect("effect-first-farmers-chapter-complete")],
  };
}

async function projectedDocuments() {
  const draftBytes = await readFile(draftPath);
  const draft = JSON.parse(draftBytes);
  await validateFirstFarmersDraft({ repositoryRoot, draft });
  const chapter = projectChapter(draft);
  const seed = worldSeed();
  const chapterBytes = bytes(chapter);
  const seedBytes = bytes(seed);
  const segmentProjection = draft.arcs.flatMap(({ beats }) => beats.flatMap(
    ({ narrative }) => narrative.segments.map(({ id, text }) => `${id}\0${text}`),
  )).join("\n");
  const receipt = {
    schemaVersion: 1,
    status: "NON_SHIPPING_DEVELOPMENT_PROJECTION",
    shippingState: "PROHIBITED",
    chapterID: draft.chapterID,
    sourceDraftPath: path.relative(repositoryRoot, draftPath),
    sourceDraftSHA256: sha256(draftBytes),
    chapterPath: path.relative(repositoryRoot, chapterPath),
    chapterSHA256: sha256(chapterBytes),
    worldSeedPath: path.relative(repositoryRoot, worldSeedPath),
    worldSeedSHA256: sha256(seedBytes),
    manuscriptSHA256: sha256(segmentProjection),
    counts: {
      arcs: chapter.arcs.length,
      beats: chapter.arcs.flatMap(({ beats }) => beats).length,
      interactions: chapter.arcs.flatMap(({ beats }) => beats)
        .filter(({ interaction }) => interaction).length,
      narrationCues: chapter.arcs.flatMap(({ beats }) => beats)
        .flatMap(({ narrationCueIDs }) => narrationCueIDs).length,
      worldEffects: chapter.arcs.flatMap(({ beats }) => beats)
        .flatMap(({ interaction }) => interaction?.completionEffects ?? []).length
        + chapter.completionEffects.length,
    },
    claimsExcluded: [
      "editor approval",
      "final visual assets",
      "final audio assets",
      "launch-package approval",
      "shipping approval",
    ],
  };
  return {
    chapterBytes,
    seedBytes,
    receiptBytes: bytes(receipt),
  };
}

async function checkFile(file, expected) {
  const actual = await readFile(file);
  assert.equal(
    actual.equals(Buffer.from(expected)),
    true,
    `${path.relative(repositoryRoot, file)} drifted; rerun the First Farmers projection generator`,
  );
}

const mode = process.argv[2] ?? "write";
assert.ok(["write", "--check"].includes(mode), "Use write or --check");
const projected = await projectedDocuments();
if (mode === "--check") {
  await Promise.all([
    checkFile(chapterPath, projected.chapterBytes),
    checkFile(worldSeedPath, projected.seedBytes),
    checkFile(receiptPath, projected.receiptBytes),
  ]);
  process.stdout.write("First Farmers non-shipping chapter projection is current.\n");
} else {
  await Promise.all([
    writeFile(chapterPath, projected.chapterBytes),
    writeFile(worldSeedPath, projected.seedBytes),
    writeFile(receiptPath, projected.receiptBytes),
  ]);
  process.stdout.write("Generated First Farmers non-shipping chapter projection.\n");
}
