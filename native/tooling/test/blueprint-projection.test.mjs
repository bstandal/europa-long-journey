import assert from "node:assert/strict";
import test from "node:test";
import {
  approvedBlueprintProjectionRecord,
  developmentBlueprintProjectionAuthorityRecord,
  validateBlueprintProjection,
  validateDevelopmentBlueprintProjectionAuthority,
} from "../src/blueprint-projection.mjs";
import { verticalSliceDevelopmentIdentity } from "../src/development-trust.mjs";

function effect(id, form = "Approved consequence") {
  return {
    id,
    mutation: "reveal-node",
    node: {
      id: `${id}-node`,
      kind: "settlement",
      form,
      position: { x: 0.5, y: 0.5 },
      attributes: [],
    },
  };
}

function fixture() {
  const contract = {
    contractID: "contract-chapter-one",
    contentID: "chapter-one",
    title: "Chapter One",
    period: "7000–3300 BC",
    thesis: "Farming binds the household to a stored future.",
    causalSpine: ["Households carry a complete farming system."],
    requiredEmphases: ["Migration of people."],
    governingJudgement: "Stored futures remake the inhabited ground.",
    ending: { period: "By 3300 BC", title: "Fields remain", consequence: "The settlement endures." },
    handoff: "The settled inheritance meets mobile power.",
    editorApproval: "APPROVED",
    lockedOnApproval: [
      "thesis", "causalSpine", "requiredEmphases", "governingJudgement", "ending", "handoff",
    ],
  };
  const approvedArc = {
    arcID: "chapter-one-arc-one",
    title: "The Stored Future",
    targetDurationMinutes: 9,
    movementIDs: ["divide-the-store"],
    situation: "One finite harvest lies on the floor.",
    mechanism: "Food and seed compete inside one store.",
    turn: "Grain eaten now cannot return to the soil.",
    consequence: "The household defers use into spring.",
    handoff: "The store makes a permanent settlement possible.",
    principalNativeInteractionIDs: ["interaction-divide-the-store"],
    supportingSourceInteractionIDs: [],
    worldTraceIDs: ["trace-seasonal-store"],
    worldEffectIDs: ["effect-divide-the-store"],
  };
  const documents = {
    contracts: { status: "APPROVED_BY_EDITOR_IN_CHIEF", contracts: [contract] },
    arcs: {
      status: "APPROVED_BY_EDITOR_IN_CHIEF",
      chapters: [{
        contentID: "chapter-one",
        editorApproval: "APPROVED",
        arcs: [approvedArc],
      }],
    },
    interactions: {
      status: "APPROVED_BY_EDITOR_IN_CHIEF",
      items: [{
        sourceInteractionID: "chapter-one/divide-the-store",
        chapterID: "chapter-one",
        arcID: "chapter-one-arc-one",
        nativeInteractionID: "interaction-divide-the-store",
        nativeGrammar: "allocate",
        nativeRole: "principal",
        disposition: "KEEP",
        worldTraceID: "trace-seasonal-store",
        worldEffectID: "effect-divide-the-store",
      }],
    },
    effectLedgers: [{
      status: "AUTHORED_APPROVED_BY_EDITOR_IN_CHIEF",
      effects: [{
        sourceInteractionID: "chapter-one/divide-the-store",
        nativeInteractionID: "interaction-divide-the-store",
        effectID: "effect-divide-the-store",
        worldTraceID: "trace-seasonal-store",
        operation: "establish",
        beforeState: "The harvest is undivided.",
        afterState: "Food and seed occupy separate stores.",
      }],
      beatEffects: [],
    }, {
      status: "AUTHORED_APPROVED_BY_EDITOR_IN_CHIEF",
      effects: [],
      beatEffects: [],
    }],
    world: {
      status: "APPROVED_BY_EDITOR_IN_CHIEF",
      traces: [{
        traceID: "trace-seasonal-store",
        state: "Food and seed occupy separate stores.",
        introducedBy: {
          contentID: "chapter-one",
          arcID: "chapter-one-arc-one",
          effectID: "effect-chapter-settlement",
        },
        arcEffects: [{
          effectID: "effect-divide-the-store",
          contentID: "chapter-one",
          arcID: "chapter-one-arc-one",
          nativeInteractionID: "interaction-divide-the-store",
          operation: "establish",
          beforeState: "The harvest is undivided.",
          afterState: "Food and seed occupy separate stores.",
        }],
        laterActivations: [],
      }],
    },
  };
  const payload = {
    schemaVersion: { major: 1, minor: 0, patch: 0 },
    packageID: "vertical-slice-development-v1",
    worldSeed: { nodes: [], traces: [] },
    chapters: [{
      schemaVersion: { major: 1, minor: 0, patch: 0 },
      id: "chapter-one",
      title: "Chapter One",
      period: "7000–3300 BC",
      arcs: [{
        id: "chapter-one-arc-one",
        title: "The Stored Future",
        targetDurationMinutes: 9,
        situation: "One finite harvest lies on the floor.",
        mechanism: "Food and seed compete inside one store.",
        turn: "Grain eaten now cannot return to the soil.",
        consequence: "The household defers use into spring.",
        handoff: "The store makes a permanent settlement possible.",
        beats: [{
          id: "divide-the-store",
          interaction: {
            id: "interaction-divide-the-store",
            grammar: "allocate",
            completionEffects: [effect("effect-divide-the-store")],
          },
          completionEffects: [],
        }],
      }],
      completionEffects: [effect("effect-chapter-settlement")],
    }],
    scenes: [],
    audioTimelines: [],
    accessibility: [],
  };
  return { documents, payload };
}

const approvalMetadata = {
  status: "APPROVED_BY_EDITOR_IN_CHIEF",
  authority: "editor-in-chief",
  approvedAt: "2026-07-24T10:00:00Z",
  decisionReference: "projection-test-editor-decision",
};

test("binds an exact public projection to approved thesis, arc, interaction and effects", () => {
  const { documents, payload } = fixture();
  const payloadBytes = Buffer.from(`${JSON.stringify(payload, null, 2)}\n`);
  const evidence = validateBlueprintProjection(payload, documents, {
    scope: "COMPLETE_CHAPTERS",
    payloadBytes,
  });
  const approval = approvedBlueprintProjectionRecord(evidence, approvalMetadata);
  assert.equal(validateBlueprintProjection(payload, documents, {
    scope: "COMPLETE_CHAPTERS",
    payloadBytes,
    approval,
  }).projectionSHA256, evidence.projectionSHA256);
  assert.deepEqual(evidence.interactionIDs, ["interaction-divide-the-store"]);
  assert.deepEqual(evidence.effectIDs, ["effect-divide-the-store", "effect-chapter-settlement"]);
});

test("development authority binds exact bytes without fabricating editor approval", () => {
  const { documents, payload } = fixture();
  const payloadBytes = Buffer.from(`${JSON.stringify(payload, null, 2)}\n`);
  const evidence = validateBlueprintProjection(payload, documents, {
    scope: "VERTICAL_SLICE",
    payloadBytes,
  });
  const authority = developmentBlueprintProjectionAuthorityRecord(
    evidence,
    verticalSliceDevelopmentIdentity,
  );
  assert.equal(
    validateDevelopmentBlueprintProjectionAuthority(
      authority,
      evidence,
      verticalSliceDevelopmentIdentity,
    ),
    true,
  );
  assert.equal(
    authority.status,
    "CODEX_PROVISIONAL_NON_SHIPPING_BLUEPRINT_PROJECTION",
  );
  assert.equal(authority.authority, "codex-local-production");
  assert.equal(authority.shippingState, "PROHIBITED");
  assert.equal(Object.hasOwn(authority, "decisionReference"), false);
  assert.equal(Object.hasOwn(authority, "approvedAt"), false);
});

test("development authority rejects launch, production-key and fabricated editor identity", () => {
  const { documents, payload } = fixture();
  const payloadBytes = Buffer.from(`${JSON.stringify(payload, null, 2)}\n`);
  const evidence = validateBlueprintProjection(payload, documents, {
    scope: "VERTICAL_SLICE",
    payloadBytes,
  });
  const baseline = developmentBlueprintProjectionAuthorityRecord(
    evidence,
    verticalSliceDevelopmentIdentity,
  );
  const mutations = [
    [
      "launch package",
      (authority) => { authority.packageID = "essential-free-v1"; },
      /exact development package, key and trust domain required/,
    ],
    [
      "production key",
      (authority) => { authority.keyID = "launch-2026-a"; },
      /exact development package, key and trust domain required/,
    ],
    [
      "editor identity",
      (authority) => {
        authority.status = "APPROVED_BY_EDITOR_IN_CHIEF";
        authority.authority = "editor-in-chief";
      },
      /exact provisional non-shipping authority required/,
    ],
  ];
  for (const [label, mutate, expected] of mutations) {
    const authority = structuredClone(baseline);
    mutate(authority);
    assert.throws(
      () => validateDevelopmentBlueprintProjectionAuthority(
        authority,
        evidence,
        verticalSliceDevelopmentIdentity,
      ),
      expected,
      label,
    );
  }
});

test("rejects locked arc, handoff, grammar, interaction and effect drift", () => {
  const mutations = [
    ["arc", (payload) => { payload.chapters[0].arcs[0].mechanism = "A different mechanism."; }],
    ["handoff", (payload) => { payload.chapters[0].arcs[0].handoff = "A different handoff."; }],
    ["grammar", (payload) => { payload.chapters[0].arcs[0].beats[0].interaction.grammar = "trace"; }],
    ["interaction", (payload) => { payload.chapters[0].arcs[0].beats[0].interaction.id = "interaction-invented"; }],
    ["effect", (payload) => { payload.chapters[0].arcs[0].beats[0].interaction.completionEffects[0].id = "effect-invented"; }],
  ];
  for (const [label, mutate] of mutations) {
    const { documents, payload } = fixture();
    mutate(payload);
    assert.throws(
      () => validateBlueprintProjection(payload, documents),
      new RegExp(label, "i"),
    );
  }
});

test("rejects thesis drift through the approved contract slice", () => {
  const { documents, payload } = fixture();
  const payloadBytes = Buffer.from(JSON.stringify(payload));
  const evidence = validateBlueprintProjection(payload, documents, { payloadBytes });
  const approval = approvedBlueprintProjectionRecord(evidence, approvalMetadata);
  documents.contracts.contracts[0].thesis = "A replacement thesis.";
  assert.throws(
    () => validateBlueprintProjection(payload, documents, { payloadBytes, approval }),
    /contractSliceSHA256: approved projection bytes drifted/,
  );
});

test("payload approval catches a causal WorldEffect body change under the same ID", () => {
  const { documents, payload } = fixture();
  const originalBytes = Buffer.from(JSON.stringify(payload));
  const evidence = validateBlueprintProjection(payload, documents, {
    scope: "VERTICAL_SLICE",
    payloadBytes: originalBytes,
  });
  const approval = approvedBlueprintProjectionRecord(evidence, {
    ...approvalMetadata,
    decisionReference: "vertical-slice-effect-approval",
  });
  payload.chapters[0].arcs[0].beats[0].interaction.completionEffects[0].node.form = "A different causal result";
  const changedBytes = Buffer.from(JSON.stringify(payload));
  assert.throws(
    () => validateBlueprintProjection(payload, documents, {
      scope: "VERTICAL_SLICE",
      payloadBytes: changedBytes,
      approval,
    }),
    /approved projection bytes drifted/,
  );
});

test("complete projection rejects omitted approved arcs while vertical-slice scope remains explicit", () => {
  const { documents, payload } = fixture();
  const secondArc = {
    ...structuredClone(documents.arcs.chapters[0].arcs[0]),
    arcID: "chapter-one-arc-two",
    title: "The Settlement Remains",
    principalNativeInteractionIDs: [],
    worldEffectIDs: [],
  };
  documents.arcs.chapters[0].arcs.push(secondArc);
  assert.throws(
    () => validateBlueprintProjection(payload, documents, { scope: "COMPLETE_CHAPTERS" }),
    /arc order\/coverage drift/,
  );
  assert.equal(
    validateBlueprintProjection(payload, documents, { scope: "VERTICAL_SLICE" }).arcIDs.length,
    1,
  );
});
