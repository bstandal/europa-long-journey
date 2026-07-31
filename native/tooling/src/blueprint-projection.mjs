import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { ValidationError } from "./validate.mjs";

const projectionKind = "BLUEPRINT_PROJECTION_APPROVAL";
const projectionHeader = "long-west-blueprint-projection-v1";
const approvalScopes = new Set(["COMPLETE_CHAPTERS", "VERTICAL_SLICE"]);
const provisionalClaimsExcluded = Object.freeze([
  "EDITOR_APPROVAL",
  "SHIPPING_APPROVAL",
  "RELEASE_AUTHORITY",
]);
const requiredBlueprintFiles = [
  "chapter-contracts.json",
  "arc-matrix.json",
  "interaction-mapping.json",
  "authored-interaction-effects-01-12.json",
  "authored-interaction-effects-13-24.json",
  "world-traces.json",
];

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]));
  }
  return value;
}

function canonicalBytes(value) {
  return Buffer.from(JSON.stringify(canonicalValue(value)), "utf8");
}

function sameArray(left, right) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => value === right[index]);
}

function exactKeys(value, keys, location, issues) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    issues.push(`${location}: object required`);
    return false;
  }
  const allowed = new Set(keys);
  for (const key of keys) {
    if (!Object.hasOwn(value, key)) issues.push(`${location}.${key}: required`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) issues.push(`${location}.${key}: unknown field`);
  }
  return true;
}

function launchEnglish(value) {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && typeof value.launchEnglish === "string") {
    return value.launchEnglish;
  }
  return undefined;
}

function publicInteractions(arc) {
  return (arc?.beats ?? []).flatMap((beat) => beat?.interaction ? [beat.interaction] : []);
}

function publicArcEffects(arc) {
  return (arc?.beats ?? []).flatMap((beat) => beat?.interaction
    ? (beat.interaction.completionEffects ?? [])
    : (beat?.completionEffects ?? []));
}

function publicChapterEffects(chapter) {
  return (chapter?.arcs ?? []).flatMap(publicArcEffects).concat(chapter?.completionEffects ?? []);
}

function approvedEffectUniverse(documents, issues) {
  const records = new Map();
  const mappingsByNativeID = new Map((documents.interactions?.items ?? [])
    .map((item) => [item.nativeInteractionID, item]));
  const add = (effectID, record, location) => {
    if (typeof effectID !== "string" || !effectID) {
      issues.push(`${location}: stable effectID required`);
      return;
    }
    if (!records.has(effectID)) records.set(effectID, { effectID, ...record });
  };

  for (const ledger of documents.effectLedgers) {
    for (const effect of ledger.effects ?? []) {
      const mapping = mappingsByNativeID.get(effect.nativeInteractionID);
      add(mapping?.worldEffectID, {
        worldTraceID: effect.worldTraceID,
        operation: effect.operation,
        beforeState: effect.beforeState,
        afterState: effect.afterState,
        nativeInteractionID: effect.nativeInteractionID,
      }, "authored interaction effect");
    }
    for (const effect of ledger.beatEffects ?? []) {
      add(effect.effectID, {
        worldTraceID: effect.worldTraceID,
        operation: effect.operation,
        beforeState: effect.beforeState,
        afterState: effect.afterState,
        sourceMovementID: effect.sourceMovementID,
      }, "authored beat effect");
    }
  }

  for (const trace of documents.world.traces ?? []) {
    const traceID = trace.traceID;
    if (trace.introducedBy?.effectID) {
      add(trace.introducedBy.effectID, {
        worldTraceID: traceID,
        operation: "introduce",
        afterState: trace.state,
        contentID: trace.introducedBy.contentID,
        arcID: trace.introducedBy.arcID,
      }, `world trace '${traceID}'.introducedBy`);
    }
    for (const effect of trace.arcEffects ?? []) {
      add(effect.effectID, {
        worldTraceID: traceID,
        operation: effect.operation,
        beforeState: effect.beforeState,
        afterState: effect.afterState,
        contentID: effect.contentID,
        arcID: effect.arcID,
        nativeInteractionID: effect.nativeInteractionID,
      }, `world trace '${traceID}'.arcEffects`);
    }
    for (const effect of trace.laterActivations ?? []) {
      add(effect.effectID, {
        worldTraceID: traceID,
        operation: effect.operation,
        beforeState: effect.beforeState,
        afterState: effect.afterState,
        contentID: effect.target?.contentID,
        arcID: effect.target?.arcID,
      }, `world trace '${traceID}'.laterActivations`);
    }
  }
  return records;
}

function requireApprovedProjectionDocuments(documents, issues) {
  if (documents.contracts?.status !== "APPROVED_BY_EDITOR_IN_CHIEF") {
    issues.push("blueprint projection: approved chapter-contracts required");
  }
  if (documents.arcs?.status !== "APPROVED_BY_EDITOR_IN_CHIEF") {
    issues.push("blueprint projection: approved arc-matrix required");
  }
  if (documents.interactions?.status !== "APPROVED_BY_EDITOR_IN_CHIEF") {
    issues.push("blueprint projection: approved interaction-mapping required");
  }
  if (documents.world?.status !== "APPROVED_BY_EDITOR_IN_CHIEF") {
    issues.push("blueprint projection: approved world-traces required");
  }
  for (const [index, ledger] of documents.effectLedgers.entries()) {
    if (ledger?.status !== "AUTHORED_APPROVED_BY_EDITOR_IN_CHIEF") {
      issues.push(`blueprint projection: approved authored effect ledger ${index + 1} required`);
    }
  }
}

function digestSlice(value) {
  return sha256(canonicalBytes(value));
}

function projectionDigest(evidence) {
  return sha256(Buffer.from([
    projectionHeader,
    `scope=${evidence.scope}`,
    `payloadSHA256=${evidence.payloadSHA256}`,
    `contractSliceSHA256=${evidence.contractSliceSHA256}`,
    `arcSliceSHA256=${evidence.arcSliceSHA256}`,
    `interactionSliceSHA256=${evidence.interactionSliceSHA256}`,
    `worldEffectSliceSHA256=${evidence.worldEffectSliceSHA256}`,
    `chapters=${evidence.chapterIDs.join(",")}`,
    `arcs=${evidence.arcIDs.join(",")}`,
    `interactions=${evidence.interactionIDs.join(",")}`,
    `effects=${evidence.effectIDs.join(",")}`,
    "",
  ].join("\n"), "utf8"));
}

export async function readBlueprintProjectionDocuments(blueprintRoot) {
  const root = path.resolve(blueprintRoot);
  const entries = await Promise.all(requiredBlueprintFiles.map(async (fileName) => [
    fileName,
    JSON.parse(await readFile(path.join(root, fileName), "utf8")),
  ]));
  const byName = Object.fromEntries(entries);
  return {
    contracts: byName["chapter-contracts.json"],
    arcs: byName["arc-matrix.json"],
    interactions: byName["interaction-mapping.json"],
    effectLedgers: [
      byName["authored-interaction-effects-01-12.json"],
      byName["authored-interaction-effects-13-24.json"],
    ],
    world: byName["world-traces.json"],
  };
}

export function validateBlueprintProjection(
  payload,
  documents,
  { scope = "COMPLETE_CHAPTERS", payloadBytes = undefined, approval = undefined } = {},
) {
  const issues = [];
  if (!approvalScopes.has(scope)) {
    throw new ValidationError([`blueprint projection.scope: expected one of ${[...approvalScopes].join(", ")}`]);
  }
  requireApprovedProjectionDocuments(documents, issues);

  const contractsByID = new Map((documents.contracts?.contracts ?? []).map((item) => [item.contentID, item]));
  const arcChaptersByID = new Map((documents.arcs?.chapters ?? []).map((item) => [item.contentID, item]));
  const mappingsByNativeID = new Map();
  for (const mapping of documents.interactions?.items ?? []) {
    if (mappingsByNativeID.has(mapping.nativeInteractionID)) {
      issues.push(`interaction mapping: duplicate nativeInteractionID '${mapping.nativeInteractionID}'`);
    }
    mappingsByNativeID.set(mapping.nativeInteractionID, mapping);
  }
  const ledgerEffects = new Map();
  const beatEffects = new Map();
  for (const ledger of documents.effectLedgers ?? []) {
    for (const effect of ledger.effects ?? []) {
      const mapping = mappingsByNativeID.get(effect.nativeInteractionID);
      if (mapping?.worldEffectID) ledgerEffects.set(mapping.worldEffectID, effect);
    }
    for (const effect of ledger.beatEffects ?? []) beatEffects.set(effect.effectID, effect);
  }
  const effectUniverse = approvedEffectUniverse(documents, issues);

  const chapters = Array.isArray(payload?.chapters) ? payload.chapters : [];
  if (!chapters.length) issues.push("blueprint projection: public payload requires at least one chapter");
  const chapterIDs = chapters.map((chapter) => chapter?.id);
  if (new Set(chapterIDs).size !== chapterIDs.length) {
    issues.push("blueprint projection: duplicate public chapter ID");
  }

  const contractSlice = [];
  const arcSlice = [];
  const interactionSlice = [];
  const worldEffectSlice = [];
  const arcIDs = [];
  const interactionIDs = [];
  const effectIDs = [];

  for (const [chapterIndex, chapter] of chapters.entries()) {
    const chapterLocation = `payload.chapters[${chapterIndex}]`;
    const contract = contractsByID.get(chapter?.id);
    const arcChapter = arcChaptersByID.get(chapter?.id);
    if (!contract || contract.editorApproval !== "APPROVED") {
      issues.push(`${chapterLocation}: thesis binding requires one approved chapter contract for '${chapter?.id}'`);
      continue;
    }
    if (!arcChapter || arcChapter.editorApproval !== "APPROVED") {
      issues.push(`${chapterLocation}: approved arc matrix entry required for '${chapter?.id}'`);
      continue;
    }
    contractSlice.push({
      contractID: contract.contractID,
      contentID: contract.contentID,
      title: contract.title,
      period: contract.period,
      thesis: contract.thesis,
      causalSpine: contract.causalSpine,
      requiredEmphases: contract.requiredEmphases,
      governingJudgement: contract.governingJudgement,
      ending: contract.ending,
      handoff: contract.handoff,
      lockedOnApproval: contract.lockedOnApproval,
    });
    if (launchEnglish(chapter.title) !== contract.title) {
      issues.push(`${chapterLocation}.title: thesis projection drift from approved contract`);
    }
    if (launchEnglish(chapter.period) !== contract.period) {
      issues.push(`${chapterLocation}.period: thesis projection drift from approved contract`);
    }
    if (Object.hasOwn(chapter, "thesis") && launchEnglish(chapter.thesis) !== contract.thesis) {
      issues.push(`${chapterLocation}.thesis: locked thesis drift`);
    }

    const authoredArcs = Array.isArray(chapter.arcs) ? chapter.arcs : [];
    const expectedArcsByID = new Map((arcChapter.arcs ?? []).map((arc) => [arc.arcID, arc]));
    const actualArcIDs = authoredArcs.map((arc) => arc?.id);
    const expectedArcIDs = (arcChapter.arcs ?? []).map((arc) => arc.arcID);
    if (scope === "COMPLETE_CHAPTERS" && !sameArray(actualArcIDs, expectedArcIDs)) {
      issues.push(`${chapterLocation}.arcs: locked arc order/coverage drift`);
    }

    for (const [arcIndex, arc] of authoredArcs.entries()) {
      const arcLocation = `${chapterLocation}.arcs[${arcIndex}]`;
      const expectedArc = expectedArcsByID.get(arc?.id);
      arcIDs.push(arc?.id);
      if (!expectedArc) {
        issues.push(`${arcLocation}.id: arc '${arc?.id}' is outside the approved matrix`);
        continue;
      }
      const projectedArc = {
        contentID: chapter.id,
        arcID: expectedArc.arcID,
        title: expectedArc.title,
        targetDurationMinutes: expectedArc.targetDurationMinutes,
        situation: expectedArc.situation,
        mechanism: expectedArc.mechanism,
        turn: expectedArc.turn,
        consequence: expectedArc.consequence,
        handoff: expectedArc.handoff,
        movementIDs: expectedArc.movementIDs,
        principalNativeInteractionIDs: expectedArc.principalNativeInteractionIDs,
        worldEffectIDs: expectedArc.worldEffectIDs,
      };
      arcSlice.push(projectedArc);
      for (const field of ["title", "situation", "mechanism", "turn", "consequence", "handoff"]) {
        if (launchEnglish(arc[field]) !== expectedArc[field]) {
          issues.push(`${arcLocation}.${field}: locked arc/${field === "handoff" ? "handoff" : "causal"} drift`);
        }
      }
      if (arc.targetDurationMinutes !== expectedArc.targetDurationMinutes) {
        issues.push(`${arcLocation}.targetDurationMinutes: locked arc duration drift`);
      }

      const interactions = publicInteractions(arc);
      const actualInteractionIDs = interactions.map((interaction) => interaction?.id);
      if (scope === "COMPLETE_CHAPTERS"
          && !sameArray(actualInteractionIDs, expectedArc.principalNativeInteractionIDs)) {
        issues.push(`${arcLocation}: principal interaction order/coverage drift`);
      }
      for (const [interactionIndex, interaction] of interactions.entries()) {
        const interactionLocation = `${arcLocation}.interactions[${interactionIndex}]`;
        interactionIDs.push(interaction?.id);
        const mapping = mappingsByNativeID.get(interaction?.id);
        if (!mapping || mapping.nativeRole !== "principal"
            || mapping.chapterID !== chapter.id || mapping.arcID !== arc.id
            || !expectedArc.principalNativeInteractionIDs.includes(interaction.id)) {
          issues.push(`${interactionLocation}.id: interaction '${interaction?.id}' is outside the approved chapter/arc mapping`);
          continue;
        }
        if (interaction.grammar !== mapping.nativeGrammar) {
          issues.push(`${interactionLocation}.grammar: '${interaction.grammar}' drifts from approved '${mapping.nativeGrammar}'`);
        }
        const authoredEffect = ledgerEffects.get(mapping.worldEffectID);
        if (!authoredEffect || authoredEffect.nativeInteractionID !== interaction.id
            || authoredEffect.worldTraceID !== mapping.worldTraceID) {
          issues.push(`${interactionLocation}: approved authored WorldEffect mapping is missing or inconsistent`);
        }
        const actualInteractionEffectIDs = (interaction.completionEffects ?? []).map((effect) => effect?.id);
        if (!sameArray(actualInteractionEffectIDs, [mapping.worldEffectID])) {
          issues.push(`${interactionLocation}.completionEffects: effect drift; expected '${mapping.worldEffectID}'`);
        }
        interactionSlice.push({
          contentID: chapter.id,
          arcID: arc.id,
          nativeInteractionID: mapping.nativeInteractionID,
          sourceInteractionID: mapping.sourceInteractionID,
          nativeGrammar: mapping.nativeGrammar,
          disposition: mapping.disposition,
          worldTraceID: mapping.worldTraceID,
          worldEffectID: mapping.worldEffectID,
        });
      }

      const actualArcEffects = publicArcEffects(arc);
      const actualArcEffectIDs = actualArcEffects.map((effect) => effect?.id);
      if (scope === "COMPLETE_CHAPTERS" && !sameArray(actualArcEffectIDs, expectedArc.worldEffectIDs)) {
        issues.push(`${arcLocation}: WorldEffect order/coverage drift from approved arc`);
      }
      for (const effect of actualArcEffects) {
        effectIDs.push(effect?.id);
        const approved = effectUniverse.get(effect?.id);
        if (!approved || !expectedArc.worldEffectIDs.includes(effect.id)) {
          issues.push(`${arcLocation}.effects: effect '${effect?.id}' is outside the approved arc`);
          continue;
        }
        const beatEffect = beatEffects.get(effect.id);
        if (beatEffect) {
          const movementID = beatEffect.sourceMovementID?.split("/").at(-1);
          if (!expectedArc.movementIDs.includes(movementID)) {
            issues.push(`${arcLocation}.effects: documentary effect '${effect.id}' belongs to another movement`);
          }
        }
        worldEffectSlice.push({
          ...approved,
          runtimeEffectSHA256: digestSlice(effect),
        });
      }
    }

    for (const [effectIndex, effect] of (chapter.completionEffects ?? []).entries()) {
      const effectLocation = `${chapterLocation}.completionEffects[${effectIndex}]`;
      effectIDs.push(effect?.id);
      const approved = effectUniverse.get(effect?.id);
      if (!approved) {
        issues.push(`${effectLocation}: chapter-level effect '${effect?.id}' is outside the approved world-effect universe`);
        continue;
      }
      worldEffectSlice.push({ ...approved, runtimeEffectSHA256: digestSlice(effect) });
    }
  }

  if (new Set(arcIDs).size !== arcIDs.length) issues.push("blueprint projection: duplicate public arc ID");
  if (new Set(interactionIDs).size !== interactionIDs.length) issues.push("blueprint projection: duplicate public interaction ID");
  if (new Set(effectIDs).size !== effectIDs.length) issues.push("blueprint projection: duplicate public WorldEffect ID");

  if (issues.length) throw new ValidationError(issues);

  const evidence = {
    scope,
    chapterIDs,
    arcIDs,
    interactionIDs,
    effectIDs,
    payloadSHA256: sha256(payloadBytes ?? canonicalBytes(payload)),
    contractSliceSHA256: digestSlice(contractSlice),
    arcSliceSHA256: digestSlice(arcSlice),
    interactionSliceSHA256: digestSlice(interactionSlice),
    worldEffectSliceSHA256: digestSlice(worldEffectSlice),
  };
  evidence.projectionSHA256 = projectionDigest(evidence);
  if (approval !== undefined) validateBlueprintProjectionApproval(approval, evidence);
  return evidence;
}

export function validateBlueprintProjectionApproval(approval, evidence) {
  const required = [
    "schemaVersion", "kind", "scope", "status", "authority", "approvedAt",
    "decisionReference", "chapterIDs", "arcIDs", "interactionIDs", "effectIDs",
    "payloadSHA256", "contractSliceSHA256", "arcSliceSHA256",
    "interactionSliceSHA256", "worldEffectSliceSHA256", "projectionSHA256",
  ];
  const issues = [];
  exactKeys(approval, required, "blueprint projection approval", issues);
  if (approval?.schemaVersion !== 1 || approval?.kind !== projectionKind
      || approval?.status !== "APPROVED_BY_EDITOR_IN_CHIEF"
      || approval?.authority !== "editor-in-chief") {
    issues.push("blueprint projection approval: explicit editor-in-chief approval required");
  }
  if (!approvalScopes.has(approval?.scope) || approval?.scope !== evidence.scope) {
    issues.push("blueprint projection approval.scope: exact compiler scope required");
  }
  if (typeof approval?.approvedAt !== "string"
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(approval.approvedAt)
      || typeof approval?.decisionReference !== "string"
      || approval.decisionReference.length < 12) {
    issues.push("blueprint projection approval: UTC time and decision reference required");
  }
  for (const key of ["chapterIDs", "arcIDs", "interactionIDs", "effectIDs"]) {
    if (!sameArray(approval?.[key], evidence[key])) {
      issues.push(`blueprint projection approval.${key}: approved projection coverage drifted`);
    }
  }
  for (const key of [
    "payloadSHA256", "contractSliceSHA256", "arcSliceSHA256",
    "interactionSliceSHA256", "worldEffectSliceSHA256", "projectionSHA256",
  ]) {
    if (approval?.[key] !== evidence[key]) {
      issues.push(`blueprint projection approval.${key}: approved projection bytes drifted`);
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

/// Validates exact byte authority for a local development projection without
/// claiming that the editor approved those derived bytes. The caller must
/// supply the isolated development identity; release compilers never call this
/// validator and continue to require editor-owned approval records.
export function validateDevelopmentBlueprintProjectionAuthority(
  authority,
  evidence,
  developmentIdentity,
) {
  const required = [
    "schemaVersion", "kind", "scope", "status", "authority", "shippingState",
    "packageID", "keyID", "trustDomain", "claimsExcluded", "chapterIDs",
    "arcIDs", "interactionIDs", "effectIDs", "payloadSHA256",
    "contractSliceSHA256", "arcSliceSHA256", "interactionSliceSHA256",
    "worldEffectSliceSHA256", "projectionSHA256",
  ];
  const issues = [];
  exactKeys(authority, required, "development blueprint projection authority", issues);
  if (authority?.schemaVersion !== 1
      || authority?.kind !== developmentIdentity?.projectionAuthorityKind
      || authority?.status !== developmentIdentity?.projectionAuthorityStatus
      || authority?.authority !== developmentIdentity?.projectionAuthority
      || authority?.shippingState !== developmentIdentity?.shippingState) {
    issues.push(
      "development blueprint projection authority: exact provisional non-shipping authority required",
    );
  }
  if (authority?.scope !== "VERTICAL_SLICE" || evidence?.scope !== "VERTICAL_SLICE") {
    issues.push(
      "development blueprint projection authority.scope: VERTICAL_SLICE required",
    );
  }
  if (authority?.packageID !== developmentIdentity?.packageID
      || authority?.keyID !== developmentIdentity?.keyID
      || authority?.trustDomain !== developmentIdentity?.trustDomain) {
    issues.push(
      "development blueprint projection authority: exact development package, key and trust domain required",
    );
  }
  if (!sameArray(authority?.claimsExcluded, provisionalClaimsExcluded)) {
    issues.push(
      "development blueprint projection authority.claimsExcluded: editor, shipping and release claims must remain excluded",
    );
  }
  for (const key of ["chapterIDs", "arcIDs", "interactionIDs", "effectIDs"]) {
    if (!sameArray(authority?.[key], evidence[key])) {
      issues.push(
        `development blueprint projection authority.${key}: provisional projection coverage drifted`,
      );
    }
  }
  for (const key of [
    "payloadSHA256", "contractSliceSHA256", "arcSliceSHA256",
    "interactionSliceSHA256", "worldEffectSliceSHA256", "projectionSHA256",
  ]) {
    if (authority?.[key] !== evidence[key]) {
      issues.push(
        `development blueprint projection authority.${key}: provisional projection bytes drifted`,
      );
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return true;
}

export function developmentBlueprintProjectionAuthorityRecord(
  evidence,
  developmentIdentity,
) {
  return {
    schemaVersion: 1,
    kind: developmentIdentity.projectionAuthorityKind,
    scope: evidence.scope,
    status: developmentIdentity.projectionAuthorityStatus,
    authority: developmentIdentity.projectionAuthority,
    shippingState: developmentIdentity.shippingState,
    packageID: developmentIdentity.packageID,
    keyID: developmentIdentity.keyID,
    trustDomain: developmentIdentity.trustDomain,
    claimsExcluded: [...provisionalClaimsExcluded],
    chapterIDs: [...evidence.chapterIDs],
    arcIDs: [...evidence.arcIDs],
    interactionIDs: [...evidence.interactionIDs],
    effectIDs: [...evidence.effectIDs],
    payloadSHA256: evidence.payloadSHA256,
    contractSliceSHA256: evidence.contractSliceSHA256,
    arcSliceSHA256: evidence.arcSliceSHA256,
    interactionSliceSHA256: evidence.interactionSliceSHA256,
    worldEffectSliceSHA256: evidence.worldEffectSliceSHA256,
    projectionSHA256: evidence.projectionSHA256,
  };
}

export function approvedBlueprintProjectionRecord(evidence, metadata) {
  return {
    schemaVersion: 1,
    kind: projectionKind,
    scope: evidence.scope,
    status: metadata.status,
    authority: metadata.authority,
    approvedAt: metadata.approvedAt,
    decisionReference: metadata.decisionReference,
    chapterIDs: [...evidence.chapterIDs],
    arcIDs: [...evidence.arcIDs],
    interactionIDs: [...evidence.interactionIDs],
    effectIDs: [...evidence.effectIDs],
    payloadSHA256: evidence.payloadSHA256,
    contractSliceSHA256: evidence.contractSliceSHA256,
    arcSliceSHA256: evidence.arcSliceSHA256,
    interactionSliceSHA256: evidence.interactionSliceSHA256,
    worldEffectSliceSHA256: evidence.worldEffectSliceSHA256,
    projectionSHA256: evidence.projectionSHA256,
  };
}
