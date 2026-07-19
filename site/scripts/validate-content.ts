import { access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { chapters } from "../src/data/chapters";
import { assetRecords, sources } from "../src/data/sources";
import { scenes } from "../src/data/scenes";

const errors: string[] = [];
const sceneIds = new Set<string>();
const hotspotIds = new Set<string>();
const sourceIds = new Set(sources.map((source) => source.id));
const allowedFamilies = new Set(["route", "network", "boundary", "compare"]);
const allowedScopes = new Set(["europe", "world"]);
const root = fileURLToPath(new URL("../public", import.meta.url));
const defensivePhrases = [
  "even so",
  "it is important to",
  "important to remember",
  "of course",
  "to be sure",
  "needless to say",
  "not simply",
  "not merely",
  "cannot be understood as",
  "later stories suggest",
  "later accounts suggest",
  "for all its",
];
const genericAiPhrases = [
  "rich tapestry",
  "stands as a testament",
  "serves as a testament",
  "delve into",
  "complex interplay",
  "multifaceted",
  "broader context",
  "cannot be overstated",
  "ever-evolving",
  "it is worth noting",
  "it should be noted",
  "the tradition never disappeared",
  "echoes to this day",
  "a new world was born",
  "everything changed",
];
const defensiveTurn = /(?:^|[.!?]\s+)(?:But|Yet|Still|However|Nevertheless|Nonetheless)\b/;
const forbiddenChapterMetaCopy = [
  {
    pattern: /\bexplore (?:the )?(?:full )?chapter\b/i,
    description: 'application invitation such as "Explore the full chapter"',
  },
  {
    pattern: /\b(?:chapter|journey|reading)\s+progress\b/i,
    description: "application progress language",
  },
  {
    pattern: /\b(?:estimated\s+)?(?:reading|exploration)\s+time\b/i,
    description: "a reading-time estimate",
  },
  {
    pattern: /\b(?:about\s+)?\d+\s*(?:-|–|—|to)\s*\d+\s*(?:min|mins|minutes)\b/i,
    description: "a duration estimate",
  },
  {
    pattern: /\b\d+\s*(?:min|mins|minutes)\s+(?:read|journey|chapter|experience)\b/i,
    description: "a duration estimate",
  },
  {
    pattern: /\bchapter\s+\d+\s+(?:of|\/)\s+\d+\b/i,
    description: "application chapter-count language",
  },
  {
    pattern: /\b(?:start|continue|finish)\s+(?:the\s+)?chapter\b/i,
    description: "application-state language",
  },
  {
    pattern: /\b(?:mark|marked)\s+(?:this\s+)?(?:chapter\s+)?complete\b/i,
    description: "application-completion language",
  },
  {
    pattern: /\b(?:click|tap|scroll)\s+to\b/i,
    description: "device-level interaction instructions",
  },
];

type PublicCopyField = {
  label: string;
  value: string | undefined;
};

type IdentifiedInteractionItem = {
  id: string;
  label: string;
  detail: string;
};

function hasPublicText(value: string | undefined): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function validateChapterCopy(
  chapterSlug: string,
  fields: PublicCopyField[],
  narrativeLabels: Set<string>,
) {
  for (const field of fields) {
    if (!hasPublicText(field.value)) continue;

    const lowerCopy = field.value.toLocaleLowerCase("en");
    if (narrativeLabels.has(field.label)) {
      for (const phrase of defensivePhrases) {
        if (lowerCopy.includes(phrase)) {
          errors.push(
            `Chapter "${chapterSlug}" ${field.label} uses the defensive phrase "${phrase}"; rewrite the claim directly.`,
          );
        }
      }
      if (defensiveTurn.test(field.value)) {
        errors.push(
          `Chapter "${chapterSlug}" ${field.label} turns aside to answer an implied objection; state the historical claim directly.`,
        );
      }
    }

    for (const phrase of genericAiPhrases) {
      if (lowerCopy.includes(phrase)) {
        errors.push(
          `Chapter "${chapterSlug}" ${field.label} uses the generic AI phrase "${phrase}"; replace it with concrete historical language.`,
        );
      }
    }

    for (const forbidden of forbiddenChapterMetaCopy) {
      if (forbidden.pattern.test(field.value)) {
        errors.push(
          `Chapter "${chapterSlug}" ${field.label} contains ${forbidden.description}; keep public copy inside the historical world.`,
        );
      }
    }
  }
}

function validateInteractionItems(
  movementId: string,
  collectionName: string,
  items: IdentifiedInteractionItem[],
) {
  if (!items.length) {
    errors.push(`Movement "${movementId}" ${collectionName} must contain at least one item.`);
    return;
  }

  const itemIds = new Set<string>();
  for (const [index, item] of items.entries()) {
    const itemName = item.id || `item ${index + 1}`;
    if (!hasPublicText(item.id)) {
      errors.push(`Movement "${movementId}" ${collectionName} item ${index + 1} needs a nonempty id.`);
    } else if (itemIds.has(item.id)) {
      errors.push(
        `Movement "${movementId}" ${collectionName} repeats interaction item id "${item.id}"; ids must be unique within the interaction.`,
      );
    }
    itemIds.add(item.id);

    if (!hasPublicText(item.label)) {
      errors.push(`Movement "${movementId}" ${collectionName} "${itemName}" needs a public label.`);
    }
    if (!hasPublicText(item.detail)) {
      errors.push(`Movement "${movementId}" ${collectionName} "${itemName}" needs public detail text.`);
    }
  }
}

function validateFiniteRange(
  context: string,
  field: string,
  value: number,
  minimum: number,
  maximum: number,
  requireInteger = false,
) {
  if (!Number.isFinite(value)) {
    errors.push(`${context} has a non-finite ${field}; expected ${minimum}–${maximum}.`);
    return;
  }
  if (value < minimum || value > maximum) {
    errors.push(`${context} has ${field} ${value}; expected ${minimum}–${maximum}.`);
  }
  if (requireInteger && !Number.isInteger(value)) {
    errors.push(`${context} has non-integer ${field} ${value}; expected a whole number.`);
  }
}

function chapterSlugFromHref(href: string): string | undefined {
  const match = href.trim().match(/^\/?chapters\/([^/?#]+)\/?(?:[?#].*)?$/);
  return match?.[1];
}

for (const [index, scene] of scenes.entries()) {
  if (!scene.id || sceneIds.has(scene.id)) errors.push(`Scene ${index + 1} has a missing or duplicate id.`);
  sceneIds.add(scene.id);

  if (scene.order !== index + 1) {
    errors.push(`Scene "${scene.id}" has order ${scene.order}; expected ${index + 1}.`);
  }
  if (scene.period.end !== undefined && scene.period.start > scene.period.end) {
    errors.push(`Scene "${scene.id}" has an invalid period.`);
  }
  if (!scene.title || !scene.thesis || !scene.body || !scene.landmark) {
    errors.push(`Scene "${scene.id}" is missing required public content.`);
  }
  const narrativeCopy = `${scene.thesis} ${scene.body}`;
  const publicCopy = [
    scene.title,
    scene.kicker,
    narrativeCopy,
    scene.landmark,
    scene.interaction.prompt,
    scene.interaction.accessibleSummary,
    ...scene.interaction.steps.map((step) => `${step.label} ${step.summary}`),
    ...scene.hotspots.map((hotspot) => `${hotspot.label} ${hotspot.detail}`),
  ]
    .join(" ")
    .toLocaleLowerCase("en");
  for (const phrase of defensivePhrases) {
    if (narrativeCopy.toLocaleLowerCase("en").includes(phrase)) {
      errors.push(`Scene "${scene.id}" uses the defensive phrase "${phrase}".`);
    }
  }
  for (const phrase of genericAiPhrases) {
    if (publicCopy.includes(phrase)) {
      errors.push(`Scene "${scene.id}" uses the generic AI phrase "${phrase}".`);
    }
  }
  if (defensiveTurn.test(narrativeCopy)) {
    errors.push(`Scene "${scene.id}" turns aside to answer an implied objection.`);
  }
  if (!scene.era) errors.push(`Scene "${scene.id}" needs a narrative era.`);
  if (!allowedFamilies.has(scene.interaction.family)) {
    errors.push(`Scene "${scene.id}" has an invalid interaction family.`);
  }
  if (!allowedScopes.has(scene.interaction.mapScope)) {
    errors.push(`Scene "${scene.id}" has an invalid map scope.`);
  }
  if (
    !scene.interaction.prompt ||
    !scene.interaction.accessibleSummary ||
    scene.interaction.steps.length < 2 ||
    scene.interaction.steps.length > 4
  ) {
    errors.push(`Scene "${scene.id}" needs a prompt, accessible summary and 2–4 interaction steps.`);
  }
  const interactionStepIds = new Set<string>();
  for (const step of scene.interaction.steps) {
    if (!step.id || interactionStepIds.has(step.id) || !step.label || !step.summary) {
      errors.push(`Scene "${scene.id}" has an incomplete or duplicate interaction step.`);
    }
    interactionStepIds.add(step.id);
    if (!step.points.length) {
      errors.push(`Interaction step "${scene.id}:${step.id}" needs at least one map point.`);
    }
    for (const point of step.points) {
      if (
        !Number.isFinite(point.latitude) ||
        !Number.isFinite(point.longitude) ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180
      ) {
        errors.push(`Interaction step "${scene.id}:${step.id}" has invalid coordinates.`);
      }
    }
    for (const [from, to] of step.links ?? []) {
      if (from < 0 || to < 0 || from >= step.points.length || to >= step.points.length) {
        errors.push(`Interaction step "${scene.id}:${step.id}" links an unknown map point.`);
      }
    }
  }
  if (!scene.hotspots.length) {
    errors.push(`Scene "${scene.id}" needs at least one interactive map place.`);
  }
  for (const hotspot of scene.hotspots) {
    const qualifiedId = `${scene.id}:${hotspot.id}`;
    if (!hotspot.id || hotspotIds.has(qualifiedId)) {
      errors.push(`Scene "${scene.id}" has a missing or duplicate hotspot id.`);
    }
    hotspotIds.add(qualifiedId);
    if (!hotspot.label || !hotspot.detail) {
      errors.push(`Hotspot "${qualifiedId}" is missing its public label or detail.`);
    }
    if (
      !Number.isFinite(hotspot.latitude) ||
      !Number.isFinite(hotspot.longitude) ||
      hotspot.latitude < -90 ||
      hotspot.latitude > 90 ||
      hotspot.longitude < -180 ||
      hotspot.longitude > 180
    ) {
      errors.push(`Hotspot "${qualifiedId}" has invalid coordinates.`);
    }
  }
  if (scene.body.split(/\s+/).length < 75 || scene.body.split(/\s+/).length > 125) {
    errors.push(`Scene "${scene.id}" body should contain 75–125 words.`);
  }
  for (const sourceId of scene.sourceIds) {
    if (!sourceIds.has(sourceId)) errors.push(`Scene "${scene.id}" references unknown source "${sourceId}".`);
  }
}

for (const source of sources) {
  if (!source.id || !source.author || !source.title || !source.year) {
    errors.push(`Source "${source.id || "unknown"}" has incomplete metadata.`);
  }
}

const chapterIds = new Set<string>();
const movementIds = new Set<string>();
const allowedChapterInteractions = new Set([
  "route",
  "seasons",
  "harvest",
  "inspect",
  "lineage",
  "growth",
  "compare",
  "mobility",
  "turnover",
  "inheritance",
  "inscription",
  "citizen-body",
  "civic-path",
  "war-timeline",
  "roman-constitution",
  "roman-network",
  "roman-command",
  "roman-citizenship",
  "roman-trace",
]);

for (const chapter of chapters) {
  if (!hasPublicText(chapter.slug) || chapterIds.has(chapter.slug)) {
    errors.push(`Chapter "${chapter.slug || "unknown"}" has a missing or duplicate slug.`);
  }
  chapterIds.add(chapter.slug);

  const requiredChapterMetadata: PublicCopyField[] = [
    { label: "number", value: chapter.number },
    { label: "title", value: chapter.title },
    { label: "period", value: chapter.period },
    { label: "claim", value: chapter.claim },
    { label: "theme id", value: chapter.theme.id },
    { label: "theme label", value: chapter.theme.label },
    { label: "openingAction", value: chapter.openingAction },
    { label: "mapLabel", value: chapter.mapLabel },
    { label: "sourcesEyebrow", value: chapter.sourcesEyebrow },
    { label: "ending period", value: chapter.ending.period },
    { label: "ending title", value: chapter.ending.title },
    { label: "ending detail", value: chapter.ending.detail },
    { label: "ending nextPeriod", value: chapter.ending.nextPeriod },
    { label: "returnHash", value: chapter.returnHash },
    { label: "nextHash", value: chapter.nextHash },
    { label: "nextTitle", value: chapter.nextTitle },
  ];
  for (const field of requiredChapterMetadata) {
    if (!hasPublicText(field.value)) {
      errors.push(`Chapter "${chapter.slug}" needs a nonempty ${field.label}.`);
    }
  }
  validateChapterCopy(
    chapter.slug,
    requiredChapterMetadata.filter(
      (field) => field.label !== "returnHash" && field.label !== "nextHash",
    ),
    new Set(["claim"]),
  );

  if (hasPublicText(chapter.returnHash) && !sceneIds.has(chapter.returnHash)) {
    errors.push(
      `Chapter "${chapter.slug}" returnHash "${chapter.returnHash}" does not match a main-journey scene id.`,
    );
  }
  if (hasPublicText(chapter.nextHash) && !sceneIds.has(chapter.nextHash)) {
    errors.push(
      `Chapter "${chapter.slug}" nextHash "${chapter.nextHash}" does not match a main-journey scene id.`,
    );
  }
  if (chapter.movements.length < 2) {
    errors.push(`Chapter "${chapter.slug}" needs at least two movements.`);
  }

  const actsById = new Map((chapter.acts ?? []).map((act) => [act.id, act]));
  if (chapter.acts) {
    if (actsById.size !== chapter.acts.length) {
      errors.push(`Chapter "${chapter.slug}" act ids must be unique.`);
    }
    for (const act of chapter.acts) {
      const actFields: PublicCopyField[] = [
        { label: `act "${act.id}" id`, value: act.id },
        { label: `act "${act.id}" number`, value: act.number },
        { label: `act "${act.id}" label`, value: act.label },
        { label: `act "${act.id}" period`, value: act.period },
        { label: `act "${act.id}" title`, value: act.title },
        { label: `act "${act.id}" detail`, value: act.detail },
      ];
      for (const field of actFields) {
        if (!hasPublicText(field.value)) {
          errors.push(`Chapter "${chapter.slug}" needs a nonempty ${field.label}.`);
        }
      }
      validateChapterCopy(chapter.slug, actFields, new Set([`act "${act.id}" detail`]));
    }
    let currentActId: string | undefined;
    const closedActs = new Set<string>();
    for (const movement of chapter.movements) {
      if (!movement.actId || !actsById.has(movement.actId)) {
        errors.push(
          `Movement "${chapter.slug}:${movement.id}" must reference a declared chapter act.`,
        );
        continue;
      }
      if (movement.actId !== currentActId) {
        if (currentActId) closedActs.add(currentActId);
        if (closedActs.has(movement.actId)) {
          errors.push(
            `Chapter "${chapter.slug}" act "${movement.actId}" is not a contiguous movement block.`,
          );
        }
        currentActId = movement.actId;
      }
    }
  }

  for (const [index, movement] of chapter.movements.entries()) {
    const qualifiedId = `${chapter.slug}:${movement.id}`;
    if (!movement.id || movementIds.has(qualifiedId)) {
      errors.push(`Chapter movement "${qualifiedId}" has a missing or duplicate id.`);
    }
    movementIds.add(qualifiedId);

    if (movement.order !== index + 1) {
      errors.push(`Movement "${qualifiedId}" has order ${movement.order}; expected ${index + 1}.`);
    }
    const requiredMovementMetadata: PublicCopyField[] = [
      { label: `movement "${movement.id}" period`, value: movement.period },
      { label: `movement "${movement.id}" place`, value: movement.place },
      { label: `movement "${movement.id}" title`, value: movement.title },
      { label: `movement "${movement.id}" thesis`, value: movement.thesis },
      { label: `movement "${movement.id}" image alt text`, value: movement.imageAlt },
    ];
    const interaction = movement.interaction;
    const interactionMetadata: PublicCopyField[] = interaction
      ? [
          {
            label: `movement "${movement.id}" interaction prompt`,
            value: interaction.prompt,
          },
          {
            label: `movement "${movement.id}" interaction accessible summary`,
            value: interaction.accessibleSummary,
          },
        ]
      : [];
    for (const field of [...requiredMovementMetadata, ...interactionMetadata]) {
      if (!hasPublicText(field.value)) {
        errors.push(`Chapter "${chapter.slug}" ${field.label} must not be empty.`);
      }
    }
    if (!hasPublicText(movement.image)) {
      errors.push(`Movement "${qualifiedId}" needs an image path.`);
    }
    if (!movement.body.length) {
      errors.push(`Movement "${qualifiedId}" needs at least one body paragraph.`);
    }
    for (const [paragraphIndex, paragraph] of movement.body.entries()) {
      if (!hasPublicText(paragraph)) {
        errors.push(`Movement "${qualifiedId}" body paragraph ${paragraphIndex + 1} must not be empty.`);
      }
    }
    if (movement.titleLines !== undefined) {
      if (!movement.titleLines.length) {
        errors.push(`Movement "${qualifiedId}" titleLines must contain at least one line when provided.`);
      }
      for (const [lineIndex, line] of movement.titleLines.entries()) {
        if (!hasPublicText(line)) {
          errors.push(`Movement "${qualifiedId}" titleLines entry ${lineIndex + 1} must not be empty.`);
        }
      }
    }
    if (!movement.sourceIds.length) {
      errors.push(`Movement "${qualifiedId}" needs at least one source id.`);
    }
    if (!movement.evidence.length) {
      errors.push(`Movement "${qualifiedId}" needs at least one scene-level evidence statement.`);
    }
    for (const [evidenceIndex, evidence] of movement.evidence.entries()) {
      if (!hasPublicText(evidence)) {
        errors.push(
          `Movement "${qualifiedId}" evidence statement ${evidenceIndex + 1} must not be empty.`,
        );
      }
    }
    validateFiniteRange(`Movement "${qualifiedId}" map position`, "x position", movement.map.x, 0, 100);
    validateFiniteRange(`Movement "${qualifiedId}" map position`, "y position", movement.map.y, 0, 100);
    if (interaction && !allowedChapterInteractions.has(interaction.kind)) {
      errors.push(`Movement "${qualifiedId}" has an invalid interaction kind.`);
    }

    const interactionCopy: PublicCopyField[] = [
      ...requiredMovementMetadata,
      ...interactionMetadata,
      ...movement.body.map((paragraph, paragraphIndex) => ({
        label: `movement "${movement.id}" body paragraph ${paragraphIndex + 1}`,
        value: paragraph,
      })),
      ...movement.evidence.map((evidence, evidenceIndex) => ({
        label: `movement "${movement.id}" evidence statement ${evidenceIndex + 1}`,
        value: evidence,
      })),
      ...(movement.titleLines ?? []).map((line, lineIndex) => ({
        label: `movement "${movement.id}" title line ${lineIndex + 1}`,
        value: line,
      })),
    ];

    if (interaction) switch (interaction.kind) {
      case "route": {
        const { points } = interaction;
        validateInteractionItems(qualifiedId, "route points", points);
        for (const [pointIndex, point] of points.entries()) {
          const pointId = point.id || `item ${pointIndex + 1}`;
          const context = `Movement "${qualifiedId}" route point "${pointId}"`;
          validateFiniteRange(context, "x position", point.x, 0, 100);
          validateFiniteRange(context, "y position", point.y, 0, 100);
          interactionCopy.push(
            { label: `movement "${movement.id}" route point "${pointId}" label`, value: point.label },
            { label: `movement "${movement.id}" route point "${pointId}" detail`, value: point.detail },
          );
        }
        break;
      }
      case "seasons": {
        const { stages, initialIndex } = interaction;
        validateInteractionItems(qualifiedId, "season stages", stages);
        if (
          initialIndex !== undefined &&
          (!Number.isInteger(initialIndex) || initialIndex < 0 || initialIndex >= stages.length)
        ) {
          errors.push(
            `Movement "${qualifiedId}" seasons initialIndex ${initialIndex} is out of bounds; expected an integer from 0 to ${Math.max(stages.length - 1, 0)}.`,
          );
        }
        for (const [stageIndex, stage] of stages.entries()) {
          const stageId = stage.id || `item ${stageIndex + 1}`;
          if (!hasPublicText(stage.landscape)) {
            errors.push(
              `Movement "${qualifiedId}" season stage "${stageId}" needs a landscape description.`,
            );
          }
          if (!stage.resources.length || stage.resources.some((resource) => !hasPublicText(resource))) {
            errors.push(
              `Movement "${qualifiedId}" season stage "${stageId}" needs named resources.`,
            );
          }
          if (!["spring", "summer", "autumn", "winter"].includes(stage.tone)) {
            errors.push(
              `Movement "${qualifiedId}" season stage "${stageId}" has invalid tone "${stage.tone}".`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" season stage "${stageId}" label`, value: stage.label },
            { label: `movement "${movement.id}" season stage "${stageId}" detail`, value: stage.detail },
            {
              label: `movement "${movement.id}" season stage "${stageId}" landscape`,
              value: stage.landscape,
            },
            ...stage.resources.map((resource, resourceIndex) => ({
              label: `movement "${movement.id}" season stage "${stageId}" resource ${resourceIndex + 1}`,
              value: resource,
            })),
          );
        }
        break;
      }
      case "harvest": {
        const { allocations, total } = interaction;
        validateInteractionItems(qualifiedId, "harvest allocations", allocations);
        validateFiniteRange(
          `Movement "${qualifiedId}" harvest`,
          "total illustrative shares",
          total,
          1,
          100,
          true,
        );
        const requiredAllocationIds = new Set<"food" | "reserve" | "seed">([
          "food",
          "reserve",
          "seed",
        ]);
        const actualAllocationIds = new Set(allocations.map((allocation) => allocation.id));
        if (
          allocations.length !== requiredAllocationIds.size ||
          [...requiredAllocationIds].some((id) => !actualAllocationIds.has(id))
        ) {
          errors.push(
            `Movement "${qualifiedId}" harvest allocations must contain food, reserve and seed exactly once.`,
          );
        }
        let initialTotal = 0;
        for (const allocation of allocations) {
          const context = `Movement "${qualifiedId}" harvest allocation "${allocation.id}"`;
          validateFiniteRange(context, "initial share", allocation.initial, 0, total, true);
          validateFiniteRange(context, "minimum share", allocation.minimum, 0, total, true);
          initialTotal += allocation.initial;
          interactionCopy.push(
            {
              label: `movement "${movement.id}" harvest allocation "${allocation.id}" label`,
              value: allocation.label,
            },
            {
              label: `movement "${movement.id}" harvest allocation "${allocation.id}" detail`,
              value: allocation.detail,
            },
          );
        }
        if (initialTotal !== total) {
          errors.push(
            `Movement "${qualifiedId}" harvest initial shares total ${initialTotal}; expected ${total}.`,
          );
        }
        break;
      }
      case "inspect": {
        const { items } = interaction;
        validateInteractionItems(qualifiedId, "inspection items", items);
        for (const [itemIndex, item] of items.entries()) {
          const itemId = item.id || `item ${itemIndex + 1}`;
          const context = `Movement "${qualifiedId}" inspection item "${itemId}"`;
          validateFiniteRange(context, "x position", item.x, 0, 100);
          validateFiniteRange(context, "y position", item.y, 0, 100);
          interactionCopy.push(
            { label: `movement "${movement.id}" inspection item "${itemId}" label`, value: item.label },
            { label: `movement "${movement.id}" inspection item "${itemId}" detail`, value: item.detail },
          );
        }
        break;
      }
      case "lineage": {
        const { snapshots } = interaction;
        validateInteractionItems(qualifiedId, "lineage snapshots", snapshots);
        for (const [snapshotIndex, snapshot] of snapshots.entries()) {
          const snapshotId = snapshot.id || `item ${snapshotIndex + 1}`;
          if (!hasPublicText(snapshot.period) || !hasPublicText(snapshot.evidence)) {
            errors.push(
              `Movement "${qualifiedId}" lineage snapshot "${snapshotId}" needs period and evidence text.`,
            );
          }
          interactionCopy.push(
            {
              label: `movement "${movement.id}" lineage snapshot "${snapshotId}" label`,
              value: snapshot.label,
            },
            {
              label: `movement "${movement.id}" lineage snapshot "${snapshotId}" detail`,
              value: snapshot.detail,
            },
            {
              label: `movement "${movement.id}" lineage snapshot "${snapshotId}" period`,
              value: snapshot.period,
            },
            {
              label: `movement "${movement.id}" lineage snapshot "${snapshotId}" evidence`,
              value: snapshot.evidence,
            },
          );
        }
        break;
      }
      case "growth": {
        const { stages } = interaction;
        validateInteractionItems(qualifiedId, "growth stages", stages);
        for (const [stageIndex, stage] of stages.entries()) {
          const stageId = stage.id || `item ${stageIndex + 1}`;
          if (
            !hasPublicText(stage.settlement) ||
            !hasPublicText(stage.landscape) ||
            !hasPublicText(stage.image)
          ) {
            errors.push(
              `Movement "${qualifiedId}" growth stage "${stageId}" needs settlement, landscape and image values.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" growth stage "${stageId}" label`, value: stage.label },
            { label: `movement "${movement.id}" growth stage "${stageId}" detail`, value: stage.detail },
            {
              label: `movement "${movement.id}" growth stage "${stageId}" settlement`,
              value: stage.settlement,
            },
            {
              label: `movement "${movement.id}" growth stage "${stageId}" landscape`,
              value: stage.landscape,
            },
          );
          try {
            await access(`${root}/${stage.image}`);
          } catch {
            errors.push(
              `Movement "${qualifiedId}" growth stage "${stageId}" is missing its image at /${stage.image}.`,
            );
          }
        }
        break;
      }
      case "compare": {
        const { layers, before, after } = interaction;
        validateInteractionItems(qualifiedId, "comparison layers", layers);
        for (const [worldLabel, world] of [
          ["before", before],
          ["after", after],
        ] as const) {
          if (
            !hasPublicText(world.label) ||
            !hasPublicText(world.period) ||
            !hasPublicText(world.image)
          ) {
            errors.push(
              `Movement "${qualifiedId}" comparison ${worldLabel} world needs label, period and image.`,
            );
          }
          try {
            await access(`${root}/${world.image}`);
          } catch {
            errors.push(
              `Movement "${qualifiedId}" comparison ${worldLabel} image is missing at /${world.image}.`,
            );
          }
          interactionCopy.push(
            {
              label: `movement "${movement.id}" comparison ${worldLabel} label`,
              value: world.label,
            },
            {
              label: `movement "${movement.id}" comparison ${worldLabel} period`,
              value: world.period,
            },
          );
        }
        for (const [layerIndex, layer] of layers.entries()) {
          const layerId = layer.id || `item ${layerIndex + 1}`;
          interactionCopy.push(
            { label: `movement "${movement.id}" comparison layer "${layerId}" label`, value: layer.label },
            { label: `movement "${movement.id}" comparison layer "${layerId}" detail`, value: layer.detail },
          );
        }
        break;
      }
      case "mobility": {
        const { states } = interaction;
        validateInteractionItems(qualifiedId, "mobility states", states);
        if (states.length !== 3) {
          errors.push(`Movement "${qualifiedId}" mobility interaction needs exactly three states.`);
        }
        for (const state of states) {
          if (!hasPublicText(state.reach) || !hasPublicText(state.load)) {
            errors.push(
              `Movement "${qualifiedId}" mobility state "${state.id}" needs reach and load text.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" mobility "${state.id}" label`, value: state.label },
            { label: `movement "${movement.id}" mobility "${state.id}" detail`, value: state.detail },
            { label: `movement "${movement.id}" mobility "${state.id}" reach`, value: state.reach },
            { label: `movement "${movement.id}" mobility "${state.id}" load`, value: state.load },
          );
        }
        break;
      }
      case "turnover": {
        const { regions } = interaction;
        validateInteractionItems(qualifiedId, "turnover regions", regions);
        if (regions.length !== 3) {
          errors.push(`Movement "${qualifiedId}" turnover interaction needs exactly three regions.`);
        }
        for (const region of regions) {
          const measureIds = new Set(region.measures.map((measure) => measure.id));
          if (
            region.measures.length !== 3 ||
            !["ancestry", "local-paternal", "incoming-paternal"].every((id) =>
              measureIds.has(id as "ancestry" | "local-paternal" | "incoming-paternal"),
            )
          ) {
            errors.push(
              `Movement "${qualifiedId}" turnover region "${region.id}" must separate ancestry, local paternal and incoming paternal measures.`,
            );
          }
          if (!sourceIds.has(region.sourceId)) {
            errors.push(
              `Movement "${qualifiedId}" turnover region "${region.id}" references unknown source "${region.sourceId}".`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" turnover "${region.id}" label`, value: region.label },
            { label: `movement "${movement.id}" turnover "${region.id}" detail`, value: region.detail },
            { label: `movement "${movement.id}" turnover "${region.id}" period`, value: region.period },
          );
          for (const measure of region.measures) {
            interactionCopy.push(
              {
                label: `movement "${movement.id}" turnover "${region.id}" ${measure.id} label`,
                value: measure.label,
              },
              {
                label: `movement "${movement.id}" turnover "${region.id}" ${measure.id} value`,
                value: measure.value,
              },
              {
                label: `movement "${movement.id}" turnover "${region.id}" ${measure.id} note`,
                value: measure.note,
              },
            );
          }
        }
        break;
      }
      case "inheritance": {
        const { layers, mapImage } = interaction;
        validateInteractionItems(qualifiedId, "inheritance layers", layers);
        if (
          layers.length !== 3 ||
          layers.map((layer) => layer.id).join(",") !== "people,language,religion"
        ) {
          errors.push(
            `Movement "${qualifiedId}" inheritance layers must be people, language and religion in that order.`,
          );
        }
        try {
          await access(`${root}/${mapImage}`);
        } catch {
          errors.push(
            `Movement "${qualifiedId}" inheritance map is missing at /${mapImage}.`,
          );
        }
        for (const layer of layers) {
          if (!layer.routes.length) {
            errors.push(
              `Movement "${qualifiedId}" inheritance layer "${layer.id}" needs at least one route.`,
            );
          }
          for (const route of layer.routes) {
            if (!hasPublicText(route.id) || !hasPublicText(route.label) || route.points.length < 2) {
              errors.push(
                `Movement "${qualifiedId}" inheritance route "${route.id}" is incomplete.`,
              );
            }
            for (const point of route.points) {
              validateFiniteRange(
                `Movement "${qualifiedId}" inheritance route "${route.id}"`,
                "x position",
                point.x,
                0,
                100,
              );
              validateFiniteRange(
                `Movement "${qualifiedId}" inheritance route "${route.id}"`,
                "y position",
                point.y,
                0,
                100,
              );
            }
          }
          interactionCopy.push(
            {
              label: `movement "${movement.id}" inheritance "${layer.id}" label`,
              value: layer.label,
            },
            {
              label: `movement "${movement.id}" inheritance "${layer.id}" detail`,
              value: layer.detail,
            },
          );
          for (const correspondence of layer.correspondences ?? []) {
            interactionCopy.push(
              {
                label: `movement "${movement.id}" inheritance correspondence reconstructed`,
                value: correspondence.reconstructed,
              },
              {
                label: `movement "${movement.id}" inheritance correspondence west`,
                value: correspondence.west,
              },
              {
                label: `movement "${movement.id}" inheritance correspondence east`,
                value: correspondence.east,
              },
              {
                label: `movement "${movement.id}" inheritance correspondence note`,
                value: correspondence.note,
              },
            );
          }
        }
        break;
      }
      case "inscription": {
        const { states } = interaction;
        validateInteractionItems(qualifiedId, "inscription states", states);
        if (
          states.length !== 3 ||
          states.map((state) => state.mode).join(",") !==
            "surface,reading,consequence"
        ) {
          errors.push(
            `Movement "${qualifiedId}" inscription states must be surface, reading and consequence in that order.`,
          );
        }
        for (const state of states) {
          if (!hasPublicText(state.heading) || !hasPublicText(state.annotation)) {
            errors.push(
              `Movement "${qualifiedId}" inscription state "${state.id}" needs a heading and annotation.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" inscription "${state.id}" label`, value: state.label },
            { label: `movement "${movement.id}" inscription "${state.id}" detail`, value: state.detail },
            { label: `movement "${movement.id}" inscription "${state.id}" heading`, value: state.heading },
            { label: `movement "${movement.id}" inscription "${state.id}" excerpt`, value: state.excerpt },
            { label: `movement "${movement.id}" inscription "${state.id}" annotation`, value: state.annotation },
          );
        }
        break;
      }
      case "citizen-body": {
        const { mapImage, states } = interaction;
        validateInteractionItems(qualifiedId, "citizen-body states", states);
        if (states.length !== 4) {
          errors.push(`Movement "${qualifiedId}" citizen-body interaction needs exactly four states.`);
        }
        try {
          await access(`${root}/${mapImage}`);
        } catch {
          errors.push(`Movement "${qualifiedId}" citizen-body map is missing at /${mapImage}.`);
        }
        for (const state of states) {
          if (!hasPublicText(state.measure) || !hasPublicText(state.overlayImage)) {
            errors.push(
              `Movement "${qualifiedId}" citizen-body state "${state.id}" needs a measure and overlay image.`,
            );
          }
          try {
            await access(`${root}/${state.overlayImage}`);
          } catch {
            errors.push(
              `Movement "${qualifiedId}" citizen-body state "${state.id}" is missing its overlay at /${state.overlayImage}.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" citizen body "${state.id}" label`, value: state.label },
            { label: `movement "${movement.id}" citizen body "${state.id}" detail`, value: state.detail },
            { label: `movement "${movement.id}" citizen body "${state.id}" measure`, value: state.measure },
          );
        }
        break;
      }
      case "civic-path": {
        const { paths } = interaction;
        validateInteractionItems(qualifiedId, "civic paths", paths);
        if (
          paths.length !== 3 ||
          paths.map((path) => path.id).join(",") !== "council,jury,assembly"
        ) {
          errors.push(
            `Movement "${qualifiedId}" civic paths must be council, jury and assembly in that order.`,
          );
        }
        for (const path of paths) {
          if (
            !hasPublicText(path.role) ||
            !hasPublicText(path.result) ||
            path.steps.length < 2
          ) {
            errors.push(
              `Movement "${qualifiedId}" civic path "${path.id}" needs a role, steps and final responsibility.`,
            );
          }
          const stepIds = new Set(path.steps.map((step) => step.id));
          if (
            stepIds.size !== path.steps.length ||
            path.steps.some(
              (step) =>
                !hasPublicText(step.id) ||
                !hasPublicText(step.label) ||
                !hasPublicText(step.detail),
            )
          ) {
            errors.push(
              `Movement "${qualifiedId}" civic path "${path.id}" has an incomplete or duplicate step.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" civic path "${path.id}" label`, value: path.label },
            { label: `movement "${movement.id}" civic path "${path.id}" detail`, value: path.detail },
            { label: `movement "${movement.id}" civic path "${path.id}" role`, value: path.role },
            { label: `movement "${movement.id}" civic path "${path.id}" result`, value: path.result },
            ...path.steps.flatMap((step) => [
              { label: `movement "${movement.id}" civic step "${step.id}" label`, value: step.label },
              { label: `movement "${movement.id}" civic step "${step.id}" detail`, value: step.detail },
            ]),
          );
        }
        break;
      }
      case "war-timeline": {
        const { mapImage, states } = interaction;
        validateInteractionItems(qualifiedId, "war timeline states", states);
        if (states.length !== 9) {
          errors.push(`Movement "${qualifiedId}" war timeline needs exactly nine states.`);
        }
        try {
          await access(`${root}/${mapImage}`);
        } catch {
          errors.push(`Movement "${qualifiedId}" war timeline map is missing at /${mapImage}.`);
        }
        for (const state of states) {
          if (
            !hasPublicText(state.period) ||
            !hasPublicText(state.athens) ||
            !hasPublicText(state.sparta) ||
            !hasPublicText(state.turningPoint) ||
            !hasPublicText(state.overlayImage)
          ) {
            errors.push(
              `Movement "${qualifiedId}" war state "${state.id}" needs date, both systems, change and overlay.`,
            );
          }
          try {
            await access(`${root}/${state.overlayImage}`);
          } catch {
            errors.push(
              `Movement "${qualifiedId}" war state "${state.id}" is missing its overlay at /${state.overlayImage}.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" war state "${state.id}" label`, value: state.label },
            { label: `movement "${movement.id}" war state "${state.id}" detail`, value: state.detail },
            { label: `movement "${movement.id}" war state "${state.id}" period`, value: state.period },
            { label: `movement "${movement.id}" war state "${state.id}" Athens`, value: state.athens },
            { label: `movement "${movement.id}" war state "${state.id}" Sparta`, value: state.sparta },
            { label: `movement "${movement.id}" war state "${state.id}" change`, value: state.turningPoint },
          );
        }
        break;
      }
      case "roman-constitution": {
        const { institutions } = interaction;
        validateInteractionItems(qualifiedId, "Roman constitution institutions", institutions);
        if (
          institutions.length !== 3 ||
          institutions.map((institution) => institution.id).join(",") !==
            "people,magistrates,senate"
        ) {
          errors.push(
            `Movement "${qualifiedId}" Roman constitution institutions must be people, magistrates and senate in that order.`,
          );
        }
        for (const institution of institutions) {
          if (
            !hasPublicText(institution.authority) ||
            !hasPublicText(institution.limit) ||
            !hasPublicText(institution.consequence)
          ) {
            errors.push(
              `Movement "${qualifiedId}" Roman institution "${institution.id}" needs authority, limit and consequence text.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" Roman institution "${institution.id}" label`, value: institution.label },
            { label: `movement "${movement.id}" Roman institution "${institution.id}" detail`, value: institution.detail },
            { label: `movement "${movement.id}" Roman institution "${institution.id}" authority`, value: institution.authority },
            { label: `movement "${movement.id}" Roman institution "${institution.id}" limit`, value: institution.limit },
            { label: `movement "${movement.id}" Roman institution "${institution.id}" consequence`, value: institution.consequence },
          );
        }
        break;
      }
      case "roman-network": {
        const { mapImage, states } = interaction;
        validateInteractionItems(qualifiedId, "Roman network states", states);
        try {
          await access(`${root}/${mapImage}`);
        } catch {
          errors.push(`Movement "${qualifiedId}" Roman network map is missing at /${mapImage}.`);
        }
        for (const state of states) {
          if (!hasPublicText(state.period) || !hasPublicText(state.measure)) {
            errors.push(
              `Movement "${qualifiedId}" Roman network state "${state.id}" needs period and measure text.`,
            );
          }
          validateInteractionItems(
            qualifiedId,
            `Roman network state "${state.id}" points`,
            state.points,
          );
          for (const point of state.points) {
            validateFiniteRange(
              `Movement "${qualifiedId}" Roman network point "${point.id}"`,
              "x position",
              point.x,
              0,
              100,
            );
            validateFiniteRange(
              `Movement "${qualifiedId}" Roman network point "${point.id}"`,
              "y position",
              point.y,
              0,
              100,
            );
          }
          for (const [from, to] of state.links) {
            if (
              from < 0 ||
              to < 0 ||
              from >= state.points.length ||
              to >= state.points.length
            ) {
              errors.push(
                `Movement "${qualifiedId}" Roman network state "${state.id}" links an unknown point.`,
              );
            }
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" Roman network "${state.id}" label`, value: state.label },
            { label: `movement "${movement.id}" Roman network "${state.id}" detail`, value: state.detail },
            { label: `movement "${movement.id}" Roman network "${state.id}" period`, value: state.period },
            { label: `movement "${movement.id}" Roman network "${state.id}" measure`, value: state.measure },
            ...state.points.flatMap((point) => [
              { label: `movement "${movement.id}" Roman network point "${point.id}" label`, value: point.label },
              { label: `movement "${movement.id}" Roman network point "${point.id}" detail`, value: point.detail },
            ]),
          );
        }
        break;
      }
      case "roman-command": {
        const { states } = interaction;
        validateInteractionItems(qualifiedId, "Roman command states", states);
        if (states.length !== 4) {
          errors.push(`Movement "${qualifiedId}" Roman command interaction needs four states.`);
        }
        for (const state of states) {
          if (
            !hasPublicText(state.period) ||
            !hasPublicText(state.commander) ||
            !hasPublicText(state.command) ||
            !hasPublicText(state.institutionalChange)
          ) {
            errors.push(
              `Movement "${qualifiedId}" Roman command state "${state.id}" needs period, commander, command and institutional change text.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" Roman command "${state.id}" label`, value: state.label },
            { label: `movement "${movement.id}" Roman command "${state.id}" detail`, value: state.detail },
            { label: `movement "${movement.id}" Roman command "${state.id}" period`, value: state.period },
            { label: `movement "${movement.id}" Roman command "${state.id}" commander`, value: state.commander },
            { label: `movement "${movement.id}" Roman command "${state.id}" command`, value: state.command },
            { label: `movement "${movement.id}" Roman command "${state.id}" change`, value: state.institutionalChange },
          );
        }
        break;
      }
      case "roman-citizenship": {
        const { paths } = interaction;
        validateInteractionItems(qualifiedId, "Roman citizenship paths", paths);
        if (paths.length !== 4) {
          errors.push(`Movement "${qualifiedId}" Roman citizenship interaction needs four paths.`);
        }
        for (const path of paths) {
          if (
            !hasPublicText(path.startingStatus) ||
            !hasPublicText(path.route) ||
            !hasPublicText(path.rights) ||
            !hasPublicText(path.limit)
          ) {
            errors.push(
              `Movement "${qualifiedId}" Roman citizenship path "${path.id}" needs starting status, route, rights and limit text.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" Roman citizenship "${path.id}" label`, value: path.label },
            { label: `movement "${movement.id}" Roman citizenship "${path.id}" detail`, value: path.detail },
            { label: `movement "${movement.id}" Roman citizenship "${path.id}" starting status`, value: path.startingStatus },
            { label: `movement "${movement.id}" Roman citizenship "${path.id}" route`, value: path.route },
            { label: `movement "${movement.id}" Roman citizenship "${path.id}" rights`, value: path.rights },
            { label: `movement "${movement.id}" Roman citizenship "${path.id}" limit`, value: path.limit },
          );
        }
        break;
      }
      case "roman-trace": {
        const { stops } = interaction;
        validateInteractionItems(qualifiedId, "Roman trace stops", stops);
        if (stops.length !== 3) {
          errors.push(`Movement "${qualifiedId}" Roman trace interaction needs three stops.`);
        }
        for (const stop of stops) {
          if (
            !hasPublicText(stop.period) ||
            !hasPublicText(stop.mechanism) ||
            !hasPublicText(stop.consequence)
          ) {
            errors.push(
              `Movement "${qualifiedId}" Roman trace stop "${stop.id}" needs period, mechanism and consequence text.`,
            );
          }
          interactionCopy.push(
            { label: `movement "${movement.id}" Roman trace "${stop.id}" label`, value: stop.label },
            { label: `movement "${movement.id}" Roman trace "${stop.id}" detail`, value: stop.detail },
            { label: `movement "${movement.id}" Roman trace "${stop.id}" period`, value: stop.period },
            { label: `movement "${movement.id}" Roman trace "${stop.id}" mechanism`, value: stop.mechanism },
            { label: `movement "${movement.id}" Roman trace "${stop.id}" consequence`, value: stop.consequence },
          );
        }
        break;
      }
    }

    validateChapterCopy(
      chapter.slug,
      interactionCopy,
      new Set([
        `movement "${movement.id}" thesis`,
        ...movement.body.map(
          (_paragraph, paragraphIndex) => `movement "${movement.id}" body paragraph ${paragraphIndex + 1}`,
        ),
      ]),
    );

    for (const sourceId of movement.sourceIds) {
      if (!sourceIds.has(sourceId)) {
        errors.push(`Movement "${qualifiedId}" references unknown source "${sourceId}".`);
      }
    }

    try {
      await access(`${root}/${movement.image}`);
    } catch {
      errors.push(`Movement "${qualifiedId}" is missing its image at /${movement.image}.`);
    }
    if (movement.mobileImage) {
      try {
        await access(`${root}/${movement.mobileImage}`);
      } catch {
        errors.push(
          `Movement "${qualifiedId}" is missing its mobile image at /${movement.mobileImage}.`,
        );
      }
    }
  }

  for (const [label, asset] of [
    ["route image", chapter.routeImage],
    ["opening route image", chapter.openingRouteImage],
    ["ending image", chapter.ending.image],
    ["ending mobile image", chapter.ending.mobileImage],
  ] as const) {
    if (!asset) continue;
    try {
      await access(`${root}/${asset}`);
    } catch {
      errors.push(`Chapter "${chapter.slug}" is missing its ${label} at /${asset}.`);
    }
  }

  if (chapter.slug === "greece-and-the-citizen") {
    const bodyWords = chapter.movements.reduce(
      (sum, movement) =>
        sum +
        movement.body.reduce(
          (movementSum, paragraph) =>
            movementSum + paragraph.trim().split(/\s+/).length,
          0,
        ),
      0,
    );
    if (bodyWords < 3200 || bodyWords > 3800) {
      errors.push(
        `Chapter "${chapter.slug}" continuous body should contain 3,200–3,800 words; found ${bodyWords}.`,
      );
    }
  }
  if (chapter.slug === "rome-gathers-europe") {
    const bodyWords = chapter.movements.reduce(
      (sum, movement) =>
        sum +
        movement.body.reduce(
          (movementSum, paragraph) =>
            movementSum + paragraph.trim().split(/\s+/).length,
          0,
        ),
      0,
    );
    if (bodyWords < 3200 || bodyWords > 3900) {
      errors.push(
        `Chapter "${chapter.slug}" continuous body should contain 3,200–3,900 words; found ${bodyWords}.`,
      );
    }
  }
}

for (const chapter of chapters) {
  const returnScene = scenes.find((scene) => scene.id === chapter.returnHash);
  if (!returnScene) continue;

  if (!returnScene.chronicle) {
    errors.push(
      `Chapter "${chapter.slug}" return scene "${returnScene.id}" needs a chronicle link to "chapters/${chapter.slug}/".`,
    );
    continue;
  }

  const linkedSlug = chapterSlugFromHref(returnScene.chronicle.href);
  if (linkedSlug !== chapter.slug) {
    errors.push(
      `Chapter "${chapter.slug}" return scene "${returnScene.id}" links to "${returnScene.chronicle.href}"; expected "chapters/${chapter.slug}/".`,
    );
  }
}

const linkedChapterSlugs = new Set<string>();
for (const scene of scenes) {
  if (!scene.chronicle) continue;

  if (!hasPublicText(scene.chronicle.href) || !hasPublicText(scene.chronicle.label)) {
    errors.push(`Scene "${scene.id}" chronicle link needs a nonempty href and historical label.`);
    continue;
  }

  const linkedSlug = chapterSlugFromHref(scene.chronicle.href);
  validateChapterCopy(
    linkedSlug ?? scene.id,
    [{ label: `chronicle label on scene "${scene.id}"`, value: scene.chronicle.label }],
    new Set(),
  );
  if (!linkedSlug) {
    errors.push(
      `Scene "${scene.id}" chronicle href "${scene.chronicle.href}" must use the local form "chapters/<slug>/".`,
    );
    continue;
  }
  if (!chapterIds.has(linkedSlug)) {
    errors.push(
      `Scene "${scene.id}" chronicle href "${scene.chronicle.href}" references unknown deep chapter "${linkedSlug}".`,
    );
    continue;
  }
  if (linkedChapterSlugs.has(linkedSlug)) {
    errors.push(`Deep chapter "${linkedSlug}" is linked from more than one main-journey scene.`);
  }
  linkedChapterSlugs.add(linkedSlug);

  const linkedChapter = chapters.find((chapter) => chapter.slug === linkedSlug);
  if (linkedChapter && linkedChapter.returnHash !== scene.id) {
    errors.push(
      `Scene "${scene.id}" links to chapter "${linkedSlug}", but that chapter returnHash is "${linkedChapter.returnHash}".`,
    );
  }
}

for (const asset of assetRecords) {
  if (
    !asset.creator ||
    !asset.institution ||
    !asset.sourceUrl ||
    !asset.license ||
    !asset.requiredCredit ||
    !asset.localPath
  ) {
    errors.push(`Asset "${asset.id}" has incomplete license metadata.`);
  }

  try {
    await access(`${root}${asset.localPath}`);
  } catch {
    errors.push(`Asset "${asset.id}" is missing at ${asset.localPath}.`);
  }
}

if (scenes.length !== 24) errors.push(`Expected 24 scenes; found ${scenes.length}.`);

const totalWords = scenes.reduce(
  (sum, scene) => sum + `${scene.thesis} ${scene.body}`.split(/\s+/).length,
  0,
);

if (totalWords < 2400 || totalWords > 3000) {
  errors.push(`Narrative should contain 2,400–3,000 words; found ${totalWords}.`);
}

if (errors.length) {
  console.error(`Content validation failed:\n${errors.map((error) => `- ${error}`).join("\n")}`);
  process.exit(1);
}

console.log(
  `Validated ${scenes.length} scenes, ${chapters.length} deep chapter, ${hotspotIds.size} interactive places, ${sources.length} sources and ${assetRecords.length} assets.`,
);
console.log(`Narrative length: ${totalWords} words.`);
