import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const read = (name) => JSON.parse(fs.readFileSync(path.join(root, name), "utf8"));

const catalog = read("chapter-catalog.json");
const contracts = read("chapter-contracts.json");
const matrix = read("arc-matrix.json");
const interactions = read("interaction-mapping.json");
const world = read("world-traces.json");
const approval = read("editor-approval.json");
const phase0IsApproved = approval.status === "APPROVED_BY_EDITOR_IN_CHIEF";
const authoredEffectLedgers = [
  read("authored-interaction-effects-01-12.json"),
  read("authored-interaction-effects-13-24.json")
];

const stableID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const allowedGrammars = new Set(["trace", "allocate", "assemble", "pressure", "transform"]);
const allowedDispositions = new Set(["KEEP", "MERGE", "REWRITE", "REMOVE"]);
const allowedActivationOperations = new Set(["reactivate", "transform", "contest", "supersede"]);
const allowedArcEffectOperations = new Set(["prepare", "establish", "transform"]);
const completeProse = /[.!?]$/;
const mechanicalActivationPhrases = [
  /becomes operative again:/i,
  /takes a new form:/i,
  /remains visible under direct pressure:/i,
  /is displaced but retained as an earlier world state:/i
];

function unique(values, label) {
  assert.equal(new Set(values).size, values.length, `${label} must be unique`);
}

function countBy(values) {
  return Object.fromEntries(
    [...new Set(values)].sort().map((value) => [
      value,
      values.filter((candidate) => candidate === value).length
    ])
  );
}

assert.equal(catalog.chapters.length, 24, "catalog must contain 24 chapters");
assert.equal(contracts.contracts.length, 24, "must contain 24 chapter contracts");
assert.equal(matrix.chapters.length, 24, "arc matrix must contain 24 chapters");
assert.equal(interactions.items.length, 122, "must map all 122 source interactions");
assert.equal(world.traces.length, 48, "world model must retain its 48 selected traces");

const authoredEffects = [];
const authoredBeatEffects = [];
const authoredPromotions = [];
for (const [ledgerIndex, ledger] of authoredEffectLedgers.entries()) {
  const ordinalStart = ledgerIndex === 0 ? 1 : 13;
  const ordinalEnd = ledgerIndex === 0 ? 12 : 24;
  assert.equal(ledger.schemaVersion, 2, `authored effect ledger ${ledgerIndex + 1} schema changed`);
  assert.equal(
    ledger.status,
    phase0IsApproved
      ? "AUTHORED_APPROVED_BY_EDITOR_IN_CHIEF"
      : "AUTHORED_PENDING_EDITOR_APPROVAL",
    `authored effect ledger ${ledgerIndex + 1} status changed`
  );
  assert.deepEqual(
    ledger.scope,
    { ordinalStart, ordinalEnd, chapters: 12 },
    `authored effect ledger ${ledgerIndex + 1} scope changed`
  );
  assert.ok(Array.isArray(ledger.effects), `authored effect ledger ${ledgerIndex + 1} lacks effects`);
  assert.ok(Array.isArray(ledger.beatEffects), `authored effect ledger ${ledgerIndex + 1} lacks beat effects`);
  assert.ok(
    Array.isArray(ledger.requiredMappingPromotions),
    `authored effect ledger ${ledgerIndex + 1} lacks its promotion register`
  );

  const interactiveChapters = ledger.effects.map(({ sourceInteractionID }) =>
    sourceInteractionID.split("/")[0]
  );
  const beatChapters = ledger.beatEffects.map(({ sourceMovementID }) =>
    sourceMovementID.split("/")[0]
  );
  const effectChapterOrdinals = [...interactiveChapters, ...beatChapters].map((contentID) =>
    catalog.chapters.find(({ contentID: candidate }) => candidate === contentID)?.ordinal
  );
  assert.ok(
    effectChapterOrdinals.every((ordinal) => ordinal >= ordinalStart && ordinal <= ordinalEnd),
    `authored effect ledger ${ledgerIndex + 1} contains a chapter outside its scope`
  );
  const allLedgerEffects = [...ledger.effects, ...ledger.beatEffects];
  assert.equal(ledger.counts.interactiveEffects, ledger.effects.length, `ledger ${ledgerIndex + 1} interactive count mismatch`);
  assert.equal(ledger.counts.beatEffects, ledger.beatEffects.length, `ledger ${ledgerIndex + 1} beat count mismatch`);
  assert.equal(ledger.counts.totalWorldEffects, allLedgerEffects.length, `ledger ${ledgerIndex + 1} total effect count mismatch`);
  assert.equal(
    ledger.counts.principalInteractions,
    ledger.effects.length,
    `ledger ${ledgerIndex + 1} principal count mismatch`
  );
  assert.equal(
    ledger.counts.mappingPromotionsRequired,
    ledger.requiredMappingPromotions.length,
    `ledger ${ledgerIndex + 1} promotion count mismatch`
  );
  assert.equal(
    ledger.counts.worldTraces,
    new Set(allLedgerEffects.map(({ worldTraceID }) => worldTraceID)).size,
    `ledger ${ledgerIndex + 1} trace count mismatch`
  );
  assert.deepEqual(
    ledger.counts.byOperation,
    countBy(allLedgerEffects.map(({ operation }) => operation)),
    `ledger ${ledgerIndex + 1} operation counts mismatch`
  );
  assert.deepEqual(
    ledger.counts.interactiveByOperation,
    countBy(ledger.effects.map(({ operation }) => operation)),
    `ledger ${ledgerIndex + 1} interactive operation counts mismatch`
  );
  assert.deepEqual(
    ledger.counts.beatByOperation,
    {
      prepare: ledger.beatEffects.filter(({ operation }) => operation === "prepare").length,
      establish: ledger.beatEffects.filter(({ operation }) => operation === "establish").length,
      transform: ledger.beatEffects.filter(({ operation }) => operation === "transform").length
    },
    `ledger ${ledgerIndex + 1} beat operation counts mismatch`
  );
  assert.deepEqual(
    ledger.counts.interactiveByChapter,
    countBy(interactiveChapters),
    `ledger ${ledgerIndex + 1} interactive chapter counts mismatch`
  );
  authoredEffects.push(...ledger.effects);
  authoredBeatEffects.push(...ledger.beatEffects);
  authoredPromotions.push(...ledger.requiredMappingPromotions);
}

unique(authoredEffects.map(({ sourceInteractionID }) => sourceInteractionID), "authored effect source IDs");
unique(authoredEffects.map(({ nativeInteractionID }) => nativeInteractionID), "authored native interaction IDs");
unique(authoredBeatEffects.map(({ sourceMovementID }) => sourceMovementID), "authored beat movement IDs");
unique(authoredBeatEffects.map(({ effectID }) => effectID), "authored beat effect IDs");
unique(authoredPromotions.map(({ sourceInteractionID }) => sourceInteractionID), "authored promotion source IDs");
const authoredBySourceID = new Map(
  authoredEffects.map((effect) => [effect.sourceInteractionID, effect])
);
const authoredByNativeID = new Map(
  authoredEffects.map((effect) => [effect.nativeInteractionID, effect])
);
const authoredBeatByEffectID = new Map(
  authoredBeatEffects.map((effect) => [effect.effectID, effect])
);
const promotionBySourceID = new Map(
  authoredPromotions.map((promotion) => [promotion.sourceInteractionID, promotion])
);
for (const effect of authoredEffects) {
  assert.ok(stableID.test(effect.nativeInteractionID), `unstable authored native ID ${effect.nativeInteractionID}`);
  assert.ok(stableID.test(effect.worldTraceID), `unstable authored trace ID ${effect.worldTraceID}`);
  assert.ok(allowedArcEffectOperations.has(effect.operation), `invalid authored operation ${effect.sourceInteractionID}`);
  assert.ok(effect.beforeState.length >= 60, `authored before-state is too thin ${effect.sourceInteractionID}`);
  assert.ok(effect.afterState.length >= 60, `authored after-state is too thin ${effect.sourceInteractionID}`);
  assert.match(effect.beforeState, completeProse, `authored before-state is incomplete ${effect.sourceInteractionID}`);
  assert.match(effect.afterState, completeProse, `authored after-state is incomplete ${effect.sourceInteractionID}`);
  assert.notEqual(effect.beforeState, effect.afterState, `authored effect changes nothing ${effect.sourceInteractionID}`);
}
for (const effect of authoredBeatEffects) {
  assert.match(
    effect.sourceMovementID,
    /^[a-z0-9]+(?:-[a-z0-9]+)*\/[a-z0-9]+(?:-[a-z0-9]+)*$/,
    `unstable authored beat movement ID ${effect.sourceMovementID}`
  );
  assert.ok(stableID.test(effect.effectID), `unstable authored beat effect ID ${effect.effectID}`);
  assert.ok(stableID.test(effect.worldTraceID), `unstable authored beat trace ID ${effect.worldTraceID}`);
  assert.ok(allowedArcEffectOperations.has(effect.operation), `invalid authored beat operation ${effect.sourceMovementID}`);
  assert.ok(effect.beforeState.length >= 60, `authored beat before-state is too thin ${effect.sourceMovementID}`);
  assert.ok(effect.afterState.length >= 60, `authored beat after-state is too thin ${effect.sourceMovementID}`);
  assert.match(effect.beforeState, completeProse, `authored beat before-state is incomplete ${effect.sourceMovementID}`);
  assert.match(effect.afterState, completeProse, `authored beat after-state is incomplete ${effect.sourceMovementID}`);
  assert.notEqual(effect.beforeState, effect.afterState, `authored beat effect changes nothing ${effect.sourceMovementID}`);
}
unique(
  [
    ...authoredEffects.map(({ nativeInteractionID }) =>
      `effect-${nativeInteractionID.replace(/^interaction-/, "")}`
    ),
    ...authoredBeatEffects.map(({ effectID }) => effectID)
  ],
  "all authored world effect IDs"
);
for (const promotion of authoredPromotions) {
  assert.ok(authoredBySourceID.has(promotion.sourceInteractionID), `promotion lacks authored effect ${promotion.sourceInteractionID}`);
  assert.equal(promotion.fromDisposition, "MERGE", `promotion source must be MERGE ${promotion.sourceInteractionID}`);
  assert.ok(["KEEP", "REWRITE"].includes(promotion.toDisposition), `invalid promotion target ${promotion.sourceInteractionID}`);
  assert.equal(promotion.nativeRole, "principal", `promotion must become principal ${promotion.sourceInteractionID}`);
  assert.equal(
    promotion.worldTraceID,
    authoredBySourceID.get(promotion.sourceInteractionID).worldTraceID,
    `promotion trace mismatch ${promotion.sourceInteractionID}`
  );
}

const chapterIDs = catalog.chapters.map(({ contentID }) => contentID);
unique(chapterIDs, "chapter content IDs");
assert.deepEqual(
  catalog.freeContentIDs,
  ["first-farmers", "europe-holds-the-line", "european-world"],
  "free launch selection must use the three locked stable IDs"
);
const chapterOrdinalByID = new Map(
  catalog.chapters.map(({ contentID, ordinal }) => [contentID, ordinal])
);
assert.deepEqual(
  contracts.contracts.map(({ contentID }) => contentID),
  chapterIDs,
  "contracts must follow catalog order"
);
assert.deepEqual(
  matrix.chapters.map(({ contentID }) => contentID),
  chapterIDs,
  "arc matrix must follow catalog order"
);
const contractApprovalStates = new Set(contracts.contracts.map(({ editorApproval }) => editorApproval));
const arcApprovalStates = new Set(matrix.chapters.map(({ editorApproval }) => editorApproval));
assert.equal(contractApprovalStates.size, 1, "contract approval cannot be mixed");
assert.equal(arcApprovalStates.size, 1, "arc approval cannot be mixed");
const [editorApprovalState] = contractApprovalStates;
assert.ok(["DRAFT_PENDING", "APPROVED"].includes(editorApprovalState), "unknown contract approval state");
assert.deepEqual(arcApprovalStates, contractApprovalStates, "contract and arc approval must move together");
if (editorApprovalState === "DRAFT_PENDING") {
  assert.equal(catalog.status, "CANONICAL_PHASE_0_DRAFT", "draft catalog status mismatch");
  assert.equal(contracts.status, "DRAFT_PENDING_EDITOR_IN_CHIEF", "draft contract status mismatch");
  assert.equal(matrix.status, "DRAFT_PENDING_EDITOR_IN_CHIEF", "draft arc status mismatch");
  assert.equal(interactions.status, "DRAFT", "draft interaction mapping status mismatch");
  assert.equal(world.status, "DRAFT", "draft world model status mismatch");
  assert.equal(approval.status, "PENDING_EDITOR_IN_CHIEF", "draft files require pending editor approval record");
  assert.ok(
    catalog.chapters.every(({ thesisStatus }) => thesisStatus === "LOCKED_PENDING_NATIVE_CONTRACT_APPROVAL"),
    "draft catalog thesis status mismatch"
  );
  for (const field of ["approvedAt", "decisionReference", "chapterContractsSHA256", "arcMatrixSHA256", "phase0EditorialSHA256"]) {
    assert.equal(approval[field], null, `pending approval cannot set ${field}`);
  }
} else {
  assert.equal(catalog.status, "CANONICAL_PHASE_0_APPROVED", "approved catalog status mismatch");
  assert.equal(contracts.status, "APPROVED_BY_EDITOR_IN_CHIEF", "approved contract status mismatch");
  assert.equal(matrix.status, "APPROVED_BY_EDITOR_IN_CHIEF", "approved arc status mismatch");
  assert.equal(interactions.status, "APPROVED_BY_EDITOR_IN_CHIEF", "approved interaction mapping status mismatch");
  assert.equal(world.status, "APPROVED_BY_EDITOR_IN_CHIEF", "approved world model status mismatch");
  assert.equal(approval.status, "APPROVED_BY_EDITOR_IN_CHIEF", "approved files require editor approval record");
  assert.ok(
    catalog.chapters.every(({ thesisStatus }) => thesisStatus === "LOCKED_NATIVE_CONTRACT_APPROVED"),
    "approved catalog thesis status mismatch"
  );
  assert.equal(approval.authority, "editor-in-chief", "approval authority changed");
  assert.match(approval.approvedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/, "approval time must be UTC ISO-8601");
  assert.ok(typeof approval.decisionReference === "string" && approval.decisionReference.length >= 12, "approval decision reference required");
  const sha256 = (name) => createHash("sha256").update(fs.readFileSync(path.join(root, name))).digest("hex");
  assert.equal(approval.chapterContractsSHA256, sha256("chapter-contracts.json"), "approved contract digest drifted");
  assert.equal(approval.arcMatrixSHA256, sha256("arc-matrix.json"), "approved arc digest drifted");
  const editorialFiles = [
    "chapter-catalog.json",
    "chapter-contracts.json",
    "arc-matrix.json",
    "authored-interaction-effects-01-12.json",
    "authored-interaction-effects-13-24.json",
    "interaction-mapping.json",
    "world-traces.json"
  ].sort();
  const aggregateMaterial = editorialFiles
    .map((name) => `${name}\0${sha256(name)}\n`)
    .join("");
  assert.equal(
    approval.phase0EditorialSHA256,
    createHash("sha256").update(aggregateMaterial).digest("hex"),
    "approved Phase 0 editorial world drifted"
  );
}

const contractByContentID = new Map(contracts.contracts.map((contract) => [contract.contentID, contract]));
for (const chapter of catalog.chapters) {
  const contract = contractByContentID.get(chapter.contentID);
  assert.ok(contract, `catalog chapter lacks contract ${chapter.contentID}`);
  assert.equal(chapter.title, contract.title, `catalog title drifted ${chapter.contentID}`);
  assert.equal(chapter.period, contract.period, `catalog period drifted ${chapter.contentID}`);
  assert.equal(chapter.lockedThesis, contract.thesis, `catalog thesis drifted ${chapter.contentID}`);
}

const chapterByID = new Map(matrix.chapters.map((chapter) => [chapter.contentID, chapter]));
const arcByID = new Map();
const movementPlacement = new Map();
const allMovementIDs = [];
for (const chapter of matrix.chapters) {
  assert.ok(chapter.arcs.length >= 1 && chapter.arcs.length <= 3, `${chapter.contentID} must have 1–3 arcs`);
  assert.equal(chapter.arcCount, chapter.arcs.length, `${chapter.contentID} arc count mismatch`);
  for (const arc of chapter.arcs) {
    assert.ok(stableID.test(arc.arcID), `unstable arc ID ${arc.arcID}`);
    assert.ok(arc.targetDurationMinutes >= 8 && arc.targetDurationMinutes <= 15, `${arc.arcID} duration outside gate`);
    assert.ok(arc.principalNativeInteractionIDs.length >= 1 && arc.principalNativeInteractionIDs.length <= 3, `${arc.arcID} must have 1–3 principal interactions`);
    unique(arc.principalNativeInteractionIDs, `${arc.arcID} principal IDs`);
    unique(arc.worldTraceIDs, `${arc.arcID} trace IDs`);
    unique(arc.worldEffectIDs, `${arc.arcID} effect IDs`);
    arcByID.set(arc.arcID, { chapterID: chapter.contentID, arc });
    arc.movementIDs.forEach((movementID, movementIndex) => {
      const key = `${chapter.contentID}/${movementID}`;
      assert.ok(!movementPlacement.has(key), `duplicate movement placement ${key}`);
      movementPlacement.set(key, { arcID: arc.arcID, movementIndex });
      allMovementIDs.push(key);
    });
  }
}
assert.equal(arcByID.size, 55, "must contain 55 unique arcs");
assert.equal(allMovementIDs.length, 290, "must place all 290 movements exactly once");
assert.equal(matrix.coveredMovementCount, 290, "declared movement count mismatch");
const interactionMovementIDs = new Set(
  interactions.items.map(({ chapterID, movementID }) => `${chapterID}/${movementID}`)
);
for (const effect of authoredBeatEffects) {
  assert.ok(movementPlacement.has(effect.sourceMovementID), `unknown authored beat movement ${effect.sourceMovementID}`);
  assert.ok(!interactionMovementIDs.has(effect.sourceMovementID), `authored beat effect is attached to an interaction ${effect.sourceMovementID}`);
}

const traceByID = new Map();
const definedArcEffectIDs = new Set();
const allLaterEffectIDs = new Set();
for (const trace of world.traces) {
  assert.ok(stableID.test(trace.traceID), `unstable trace ID ${trace.traceID}`);
  assert.ok(!traceByID.has(trace.traceID), `duplicate trace ID ${trace.traceID}`);
  traceByID.set(trace.traceID, trace);

  const originArc = arcByID.get(trace.introducedBy.arcID);
  assert.ok(originArc, `unknown origin arc for ${trace.traceID}`);
  assert.equal(originArc.chapterID, trace.introducedBy.contentID, `origin chapter mismatch for ${trace.traceID}`);
  assert.equal(trace.introducedBy.beatID, "UNASSIGNED", `origin beat must remain explicit for ${trace.traceID}`);

  unique(trace.arcEffects.map(({ effectID }) => effectID), `${trace.traceID} arc effect IDs`);
  assert.ok(trace.arcEffects.length >= 1, `${trace.traceID} has no authored causal effect`);
  const establishments = trace.arcEffects.filter(({ operation }) => operation === "establish");
  assert.equal(establishments.length, 1, `${trace.traceID} must be established exactly once`);
  assert.equal(
    establishments[0].arcID,
    trace.introducedBy.arcID,
    `${trace.traceID} must be established in its declared origin arc`
  );
  assert.equal(
    trace.introducedBy.effectID,
    establishments[0].effectID,
    `${trace.traceID} origin must point to its establishment effect`
  );
  let established = false;
  let previousArcAfterState;
  for (const effect of trace.arcEffects) {
    assert.ok(stableID.test(effect.effectID), `unstable effect ID ${effect.effectID}`);
    assert.ok(!definedArcEffectIDs.has(effect.effectID), `duplicate arc effect ${effect.effectID}`);
    definedArcEffectIDs.add(effect.effectID);
    assert.ok(allowedArcEffectOperations.has(effect.operation), `invalid arc effect operation ${effect.operation}`);
    const placement = arcByID.get(effect.arcID);
    assert.ok(placement, `unknown effect arc ${effect.arcID}`);
    assert.equal(placement.chapterID, effect.contentID, `effect chapter mismatch ${effect.effectID}`);
    assert.equal(effect.beatID, "UNASSIGNED", `effect beat must remain explicit ${effect.effectID}`);
    assert.equal(effect.contentID, trace.introducedBy.contentID, `effect leaves origin chapter ${effect.effectID}`);
    const hasNativeInteraction = Object.hasOwn(effect, "nativeInteractionID");
    const hasSourceMovement = Object.hasOwn(effect, "sourceMovementID");
    assert.notEqual(hasNativeInteraction, hasSourceMovement, `effect origin must be interaction xor beat ${effect.effectID}`);
    let authored;
    if (hasNativeInteraction) {
      assert.notEqual(effect.nativeInteractionID, "UNASSIGNED", `synthetic effect survived ${effect.effectID}`);
      assert.equal(
        effect.effectID,
        `effect-${effect.nativeInteractionID.replace(/^interaction-/, "")}`,
        `effect ID is not bound to its interaction ${effect.effectID}`
      );
      authored = authoredByNativeID.get(effect.nativeInteractionID);
      assert.ok(authored, `world effect lacks authored interaction entry ${effect.effectID}`);
      const mapping = interactions.items.find(({ nativeInteractionID }) =>
        nativeInteractionID === effect.nativeInteractionID
      );
      assert.ok(mapping, `world effect lacks interaction mapping ${effect.effectID}`);
      assert.equal(mapping.arcID, effect.arcID, `interaction effect arc drifted ${effect.effectID}`);
    } else {
      authored = authoredBeatByEffectID.get(effect.effectID);
      assert.ok(authored, `world effect lacks authored beat entry ${effect.effectID}`);
      assert.equal(effect.sourceMovementID, authored.sourceMovementID, `beat movement drifted ${effect.effectID}`);
      const beatPlacement = movementPlacement.get(effect.sourceMovementID);
      assert.ok(beatPlacement, `unknown effect movement ${effect.effectID}`);
      assert.equal(beatPlacement.arcID, effect.arcID, `beat effect arc drifted ${effect.effectID}`);
      assert.equal(effect.contentID, effect.sourceMovementID.split("/")[0], `beat effect chapter drifted ${effect.effectID}`);
    }
    assert.ok(effect.beforeState.length >= 60 && effect.afterState.length >= 60, `effect states too thin ${effect.effectID}`);
    assert.match(effect.beforeState, completeProse, `effect before-state is incomplete ${effect.effectID}`);
    assert.match(effect.afterState, completeProse, `effect after-state is incomplete ${effect.effectID}`);
    assert.notEqual(effect.beforeState, effect.afterState, `effect changes nothing ${effect.effectID}`);
    assert.notEqual(effect.beforeState, placement.arc.situation, `arc situation substituted for authored state ${effect.effectID}`);
    assert.notEqual(effect.beforeState, placement.arc.consequence, `arc consequence substituted for authored state ${effect.effectID}`);
    assert.notEqual(effect.afterState, placement.arc.situation, `arc situation substituted for authored state ${effect.effectID}`);
    assert.notEqual(effect.afterState, placement.arc.consequence, `arc consequence substituted for authored state ${effect.effectID}`);
    assert.equal(authored.worldTraceID, trace.traceID, `authored trace mismatch ${effect.effectID}`);
    assert.equal(authored.operation, effect.operation, `authored operation drifted ${effect.effectID}`);
    assert.equal(authored.beforeState, effect.beforeState, `authored before-state drifted ${effect.effectID}`);
    assert.equal(authored.afterState, effect.afterState, `authored after-state drifted ${effect.effectID}`);
    if (previousArcAfterState !== undefined) {
      assert.equal(effect.beforeState, previousArcAfterState, `broken authored state chain ${effect.effectID}`);
    }
    if (effect.operation === "prepare") {
      assert.ok(!established, `prepare follows establishment ${effect.effectID}`);
    } else if (effect.operation === "establish") {
      assert.ok(!established, `trace established twice ${trace.traceID}`);
      established = true;
    } else {
      assert.ok(established, `transform precedes establishment ${effect.effectID}`);
    }
    previousArcAfterState = effect.afterState;
  }
  assert.equal(previousArcAfterState, trace.state, `authored effects do not reach declared trace state ${trace.traceID}`);
  assert.ok(
    trace.arcEffects.some(({ effectID }) => effectID === trace.introducedBy.effectID),
    `origin effect is undefined for ${trace.traceID}`
  );

  unique(
    trace.laterActivations.map(({ target }) => target.contentID),
    `${trace.traceID} activation target chapters`
  );
  unique(
    trace.laterActivations.map(({ afterState }) => afterState),
    `${trace.traceID} activation result states`
  );
  let expectedBefore = trace.state;
  let previousOrdinal = chapterOrdinalByID.get(trace.introducedBy.contentID);
  for (const activation of trace.laterActivations) {
    assert.ok(stableID.test(activation.effectID), `unstable activation effect ${activation.effectID}`);
    assert.ok(!allLaterEffectIDs.has(activation.effectID), `duplicate activation effect ${activation.effectID}`);
    allLaterEffectIDs.add(activation.effectID);
    assert.ok(allowedActivationOperations.has(activation.operation), `invalid activation operation ${activation.operation}`);
    assert.equal(activation.beforeState, expectedBefore, `broken state chain at ${activation.effectID}`);
    assert.ok(activation.afterState.length >= 60, `activation state is not concrete enough ${activation.effectID}`);
    assert.notEqual(activation.afterState, activation.beforeState, `activation does not change visible state ${activation.effectID}`);
    assert.match(activation.afterState, /[.!?]$/, `activation state must be complete prose ${activation.effectID}`);
    for (const phrase of mechanicalActivationPhrases) {
      assert.doesNotMatch(activation.afterState, phrase, `mechanical continuity leaked into ${activation.effectID}`);
    }
    expectedBefore = activation.afterState;
    const targetChapter = chapterByID.get(activation.target.contentID);
    assert.ok(targetChapter, `unknown activation chapter ${activation.target.contentID}`);
    const targetOrdinal = chapterOrdinalByID.get(activation.target.contentID);
    assert.ok(targetOrdinal > previousOrdinal, `activation order moves backwards at ${activation.effectID}`);
    previousOrdinal = targetOrdinal;
    const targetArc = targetChapter.arcs.find(({ arcID }) => arcID === activation.target.arcID);
    assert.ok(targetArc, `activation arc outside target chapter ${activation.effectID}`);
    assert.notEqual(activation.afterState, targetArc.consequence, `arc consequence substituted for trace continuity ${activation.effectID}`);
    assert.ok(
      !activation.afterState.endsWith(`: ${targetArc.consequence}`),
      `generic arc consequence appended to trace continuity ${activation.effectID}`
    );
    assert.equal(activation.target.beatID, "UNASSIGNED", `activation beat must remain explicit ${activation.effectID}`);
  }
}
assert.equal(traceByID.get("trace-continent-split-open").introducedBy.arcID, "europe-at-war-arc-01", "1918 rupture must originate in the 1918 arc");
assert.deepEqual(
  [...new Set(world.traces.map(({ introducedBy }) => introducedBy.contentID))].sort(),
  [...chapterIDs].sort(),
  "every launch chapter must introduce at least one persistent trace"
);
for (const effectID of allLaterEffectIDs) {
  assert.ok(!definedArcEffectIDs.has(effectID), `activation and arc effect IDs collide at ${effectID}`);
}

const sourceIDs = interactions.items.map(({ sourceInteractionID }) => sourceInteractionID);
const nativeIDs = interactions.items.map(({ nativeInteractionID }) => nativeInteractionID);
unique(sourceIDs, "source interaction IDs");
unique(nativeIDs, "native interaction mapping IDs");
const principalItems = interactions.items.filter(({ nativeRole }) => nativeRole === "principal");
const supportingItems = interactions.items.filter(({ nativeRole }) => nativeRole === "supporting");
const principalByID = new Map(principalItems.map((item) => [item.nativeInteractionID, item]));

for (const item of interactions.items) {
  assert.ok(stableID.test(item.nativeInteractionID), `unstable native interaction ID ${item.nativeInteractionID}`);
  assert.ok(allowedGrammars.has(item.nativeGrammar), `invalid grammar ${item.nativeGrammar}`);
  assert.ok(allowedDispositions.has(item.disposition), `invalid disposition ${item.disposition}`);
  assert.equal(item.beatID, "UNASSIGNED", `interaction beat must remain explicit ${item.nativeInteractionID}`);
  const placement = movementPlacement.get(`${item.chapterID}/${item.movementID}`);
  assert.ok(placement, `unplaced interaction movement ${item.sourceInteractionID}`);
  assert.equal(item.arcID, placement.arcID, `wrong arc for ${item.sourceInteractionID}`);
  assert.equal(item.movementIndex, placement.movementIndex, `wrong movement index for ${item.sourceInteractionID}`);
  const trace = traceByID.get(item.worldTraceID);
  assert.ok(trace, `unknown world trace on ${item.nativeInteractionID}`);
  assert.ok(trace.arcEffects.some(({ effectID }) => effectID === item.worldEffectID), `world effect does not belong to trace on ${item.nativeInteractionID}`);

  const authored = authoredBySourceID.get(item.sourceInteractionID);
  const promotion = promotionBySourceID.get(item.sourceInteractionID);
  if (!authored) {
    assert.equal(item.disposition, "MERGE", `supporting interaction must remain MERGE ${item.nativeInteractionID}`);
    assert.equal(item.nativeRole, "supporting", `MERGE must be supporting ${item.nativeInteractionID}`);
    assert.ok(stableID.test(item.mergeGroupID), `MERGE needs stable group ${item.nativeInteractionID}`);
    const target = principalByID.get(item.mergeTargetNativeInteractionID);
    assert.ok(target, `MERGE target must be principal ${item.nativeInteractionID}`);
    assert.equal(target.arcID, item.arcID, `MERGE target must remain in arc ${item.nativeInteractionID}`);
    assert.equal(target.worldTraceID, item.worldTraceID, `MERGE trace mismatch ${item.nativeInteractionID}`);
    assert.equal(target.worldEffectID, item.worldEffectID, `MERGE effect mismatch ${item.nativeInteractionID}`);
  } else {
    assert.notEqual(item.disposition, "MERGE", `authored interaction cannot remain MERGE ${item.nativeInteractionID}`);
    assert.equal(item.nativeRole, "principal", `authored interaction must be principal ${item.nativeInteractionID}`);
    assert.equal(item.mergeGroupID, undefined, `principal cannot carry merge group ${item.nativeInteractionID}`);
    assert.equal(item.mergeTargetNativeInteractionID, undefined, `principal cannot carry merge target ${item.nativeInteractionID}`);
    assert.equal(item.nativeInteractionID, authored.nativeInteractionID, `authored native ID drifted ${item.sourceInteractionID}`);
    assert.equal(item.worldTraceID, authored.worldTraceID, `authored trace drifted ${item.sourceInteractionID}`);
    assert.equal(
      item.worldEffectID,
      `effect-${authored.nativeInteractionID.replace(/^interaction-/, "")}`,
      `authored effect binding drifted ${item.sourceInteractionID}`
    );
    if (promotion) {
      assert.equal(item.disposition, promotion.toDisposition, `mapping promotion not applied ${item.sourceInteractionID}`);
    }
  }
}

assert.deepEqual(
  principalItems.map(({ sourceInteractionID }) => sourceInteractionID).sort(),
  authoredEffects.map(({ sourceInteractionID }) => sourceInteractionID).sort(),
  "principal interaction set must equal the authored effect ledgers"
);

for (const { arc } of arcByID.values()) {
  const arcItems = interactions.items.filter(({ arcID }) => arcID === arc.arcID);
  const authoredWorldEffects = world.traces.flatMap((trace) =>
    trace.arcEffects
      .filter(({ arcID }) => arcID === arc.arcID)
      .map((effect) => ({ traceID: trace.traceID, effect }))
  ).sort((left, right) => {
    const movementIndex = ({ effect }) => {
      if (effect.nativeInteractionID) {
        return principalByID.get(effect.nativeInteractionID)?.movementIndex;
      }
      return movementPlacement.get(effect.sourceMovementID)?.movementIndex;
    };
    return movementIndex(left) - movementIndex(right)
      || left.effect.effectID.localeCompare(right.effect.effectID);
  });
  assert.deepEqual(
    arc.principalNativeInteractionIDs,
    arcItems.filter(({ nativeRole }) => nativeRole === "principal").map(({ nativeInteractionID }) => nativeInteractionID),
    `principal references mismatch ${arc.arcID}`
  );
  assert.deepEqual(
    arc.supportingSourceInteractionIDs,
    arcItems.filter(({ nativeRole }) => nativeRole === "supporting").map(({ sourceInteractionID }) => sourceInteractionID),
    `supporting references mismatch ${arc.arcID}`
  );
  assert.deepEqual(
    arc.worldTraceIDs,
    [...new Set(authoredWorldEffects.map(({ traceID }) => traceID))],
    `trace references mismatch ${arc.arcID}`
  );
  assert.deepEqual(
    arc.worldEffectIDs,
    authoredWorldEffects.map(({ effect }) => effect.effectID),
    `effect references mismatch ${arc.arcID}`
  );
}

assert.equal(principalItems.length, authoredEffects.length, "principal interaction total changed");
assert.equal(supportingItems.length, interactions.items.length - authoredEffects.length, "supporting interaction total changed");
assert.deepEqual(interactions.counts.byGrammar, countBy(interactions.items.map(({ nativeGrammar }) => nativeGrammar)), "grammar counts mismatch");
assert.deepEqual(interactions.counts.byDisposition, countBy(interactions.items.map(({ disposition }) => disposition)), "disposition counts mismatch");
assert.deepEqual(interactions.counts.byRole, countBy(interactions.items.map(({ nativeRole }) => nativeRole)), "role counts mismatch");
assert.equal(world.counts.arcEffects, definedArcEffectIDs.size, "arc effect count mismatch");
assert.equal(
  definedArcEffectIDs.size,
  authoredEffects.length + authoredBeatEffects.length,
  "every authored interaction and beat must have one world effect"
);
assert.equal(world.counts.laterActivations, allLaterEffectIDs.size, "activation count mismatch");
assert.equal(world.counts.laterActivations, 152, "curated activation set changed without continuity review");
assert.deepEqual(
  world.counts.byActivationOperation,
  countBy(world.traces.flatMap(({ laterActivations }) => laterActivations.map(({ operation }) => operation))),
  "activation operation counts mismatch"
);

const destroyedJewry = traceByID.get("trace-european-jewry-destroyed");
assert.equal(destroyedJewry.laterActivations.length, 1, "the permanent absence must have one authored post-war continuation");
assert.equal(destroyedJewry.laterActivations[0].operation, "reactivate", "the post-war scene may reveal the absence but never transform it");
assert.match(destroyedJewry.laterActivations[0].afterState, /do not return/i, "the permanent absence cannot be softened during reconstruction");

const review = fs.readFileSync(path.join(root, "editor-review.md"), "utf8");
for (const contentID of ["first-farmers", "bronze-europe", "empire-takes-cross", "empire-many-liberties"]) {
  assert.ok(review.includes(`\`${contentID}\``), `editor review is missing ${contentID}`);
}

console.log(
  `Blueprint valid: 24 contracts, 55 arcs, 290 movements, `
  + `${principalItems.length} principal + ${supportingItems.length} supporting interaction mappings, `
  + `48 traces, ${definedArcEffectIDs.size} arc effects and ${allLaterEffectIDs.size} later activations.`
);
