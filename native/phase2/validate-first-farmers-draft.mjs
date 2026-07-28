import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

const draftRelativePath =
  "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json";

const leakagePatterns = [
  /scholars? (?:debate|disagree)/iu,
  /historians? (?:debate|disagree)/iu,
  /the picture is complex/iu,
  /this account is contested/iu,
  /from another perspective/iu,
  /it is important to note/iu,
  /the evidence (?:shows|suggests|indicates)/iu,
  /(?:researchers?|studies) (?:show|suggest|argue)/iu,
  /this (?:chapter|app|experience) (?:shows|explores|explains)/iu,
];

const expectedGrammarCounts = {
  trace: 1,
  allocate: 1,
  assemble: 1,
  transform: 3,
  pressure: 0,
};
const canonicalHapticSemantics = new Set([
  "contact",
  "drag",
  "resistance",
  "transfer",
  "break",
  "seal",
]);

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const words = (value) => value.trim().split(/\s+/u).filter(Boolean).length;

function publicDraftStrings(draft) {
  return draft.arcs.flatMap((arc) => [
    arc.title,
    arc.situation,
    arc.mechanism,
    arc.turn,
    arc.consequence,
    arc.handoff,
    ...arc.beats.flatMap((beat) => [
      beat.narrative.eyebrow,
      beat.narrative.heading,
      beat.narrative.actionPrompt,
      ...beat.narrative.segments.map(({ text }) => text),
    ].filter(Boolean)),
  ]).concat([
    draft.chapterContract.thesis,
    draft.chapterContract.governingJudgement,
    draft.chapterContract.ending,
    draft.chapterContract.handoff,
  ]).map(String);
}

function interactionProjection(draft) {
  return draft.arcs.flatMap((arc) => arc.beats
    .filter(({ interaction }) => interaction)
    .map(({ beatID, interaction }) => ({ arcID: arc.arcID, beatID, ...interaction })));
}

export async function validateFirstFarmersDraft({ repositoryRoot, draft } = {}) {
  assert.ok(repositoryRoot, "First Farmers draft validation requires the repository root");
  const root = path.resolve(repositoryRoot);
  const file = path.resolve(root, draftRelativePath);
  const record = draft ?? JSON.parse(await readFile(file, "utf8"));

  assert.equal(record.schemaVersion, 1, "First Farmers draft schema drifted");
  assert.equal(
    record.status,
    "CHAPTER_01_REVIEW_TEXT_FROZEN",
    "First Farmers draft cannot claim editor approval",
  );
  assert.equal(record.shippingState, "PROHIBITED", "First Farmers draft cannot ship");
  assert.equal(record.chapterID, "first-farmers", "First Farmers draft changed chapter");
  assert.equal(record.locale, "en", "Launch draft must remain English");
  assert.equal(record.arcs.length, 3, "First Farmers requires its three approved arcs");
  for (const value of publicDraftStrings(record)) {
    assert.ok(value.trim(), "First Farmers public draft contains empty copy");
    for (const pattern of leakagePatterns) {
      assert.ok(!pattern.test(value), `First Farmers leaked academic or meta language: ${pattern}`);
    }
  }

  for (const binding of record.authorityBindings) {
    const authorityPath = path.resolve(root, binding.path);
    assert.ok(
      authorityPath.startsWith(`${root}${path.sep}`),
      "First Farmers authority binding escaped the repository",
    );
    assert.equal(
      sha256(await readFile(authorityPath)),
      binding.sha256,
      `First Farmers authority bytes drifted: ${binding.path}`,
    );
  }

  const [contracts, arcMatrix, mapping, effects] = await Promise.all([
    readFile(path.join(root, "native/blueprint/chapter-contracts.json"), "utf8")
      .then(JSON.parse),
    readFile(path.join(root, "native/blueprint/arc-matrix.json"), "utf8")
      .then(JSON.parse),
    readFile(path.join(root, "native/blueprint/interaction-mapping.json"), "utf8")
      .then(JSON.parse),
    readFile(
      path.join(root, "native/blueprint/authored-interaction-effects-01-12.json"),
      "utf8",
    ).then(JSON.parse),
  ]);

  const contract = contracts.contracts.find(({ contentID }) => contentID === record.chapterID);
  assert.ok(contract, "Approved First Farmers contract is missing");
  assert.equal(contract.editorApproval, "APPROVED", "First Farmers contract is not approved");
  assert.deepEqual(record.chapterContract, {
    thesis: contract.thesis,
    governingJudgement: contract.governingJudgement,
    ending: contract.ending.title,
    handoff: contract.handoff,
  }, "First Farmers draft drifted from the approved editorial contract");

  const approvedChapter = arcMatrix.chapters.find(
    ({ contentID }) => contentID === record.chapterID,
  );
  assert.ok(approvedChapter, "Approved First Farmers arc matrix is missing");
  assert.deepEqual(
    record.arcs.map(({ arcID }) => arcID),
    approvedChapter.arcs.map(({ arcID }) => arcID),
    "First Farmers arc order drifted",
  );

  const beatIDs = [];
  const sceneIDs = [];
  const segmentIDs = [];
  let calculatedWords = 0;
  for (const [index, arc] of record.arcs.entries()) {
    const approvedArc = approvedChapter.arcs[index];
    for (const field of [
      "title",
      "targetDurationMinutes",
      "situation",
      "mechanism",
      "turn",
      "consequence",
      "handoff",
    ]) assert.deepEqual(arc[field], approvedArc[field], `Approved arc field drifted: ${arc.arcID}.${field}`);

    assert.ok(arc.beats.length >= 4, `Arc ${arc.arcID} has no sustained dramatic structure`);
    assert.equal(
      arc.beats.reduce((sum, beat) => sum + beat.estimatedSeconds, 0),
      arc.targetDurationMinutes * 60,
      `Arc ${arc.arcID} pacing does not equal its approved session duration`,
    );
    assert.deepEqual(
      [...new Set(arc.beats.flatMap(({ movementIDs }) => movementIDs))],
      approvedArc.movementIDs,
      `Arc ${arc.arcID} movement coverage drifted`,
    );
    for (const beat of arc.beats) {
      beatIDs.push(beat.beatID);
      sceneIDs.push(beat.sceneID);
      assert.ok(
        ["onEntry", "onExit", "continuous"].includes(beat.checkpoint),
        `Beat ${beat.beatID} has no durable checkpoint policy`,
      );
      assert.ok(beat.estimatedSeconds >= 45, `Beat ${beat.beatID} is too thin to carry a scene`);
      assert.ok(beat.narrative.heading.trim(), `Beat ${beat.beatID} has no heading`);
      assert.ok(beat.narrative.segments.length >= 1, `Beat ${beat.beatID} has no manuscript`);
      assert.ok(beat.sceneDirection.camera.trim(), `Beat ${beat.beatID} has no camera direction`);
      assert.ok(beat.sceneDirection.livingMotion.length >= 3, `Beat ${beat.beatID} is not alive`);
      assert.ok(beat.sceneDirection.mechanismLight.trim(), `Beat ${beat.beatID} has no mechanism light`);
      assert.ok(beat.sceneDirection.sound.trim(), `Beat ${beat.beatID} has no sound direction`);
      for (const segment of beat.narrative.segments) {
        segmentIDs.push(segment.id);
        assert.ok(segment.text.trim(), `Narration segment ${segment.id} is empty`);
        calculatedWords += words(segment.text);
      }
      if (beat.interaction) {
        assert.equal(
          beat.checkpoint,
          "continuous",
          `Interactive beat ${beat.beatID} must persist continuously`,
        );
        for (const field of [
          "immediateResponse",
          "visibleMechanism",
          "historicalConsequence",
          "persistentTrace",
        ]) assert.ok(
          beat.interaction.causalContract[field]?.trim(),
          `Interaction ${beat.interaction.id} is missing ${field}`,
        );
        assert.equal(
          new Set(beat.interaction.haptics).size,
          beat.interaction.haptics.length,
          `Interaction ${beat.interaction.id} repeats a haptic semantic`,
        );
        assert.ok(
          beat.interaction.haptics.every((semantic) => canonicalHapticSemantics.has(semantic)),
          `Interaction ${beat.interaction.id} uses a non-canonical haptic semantic`,
        );
        assert.ok(
          beat.interaction.haptics.includes("seal"),
          `Interaction ${beat.interaction.id} has no consequence seal`,
        );
        assert.ok(beat.interaction.reduceMotion.trim(), `Interaction ${beat.interaction.id} has no Reduce Motion form`);
        if (beat.interaction.grammar === "trace") {
          const { anchors, tolerance } = beat.interaction;
          assert.ok(
            Array.isArray(anchors) && anchors.length >= 2 && anchors.length <= 64,
            `Trace interaction ${beat.interaction.id} must have between 2 and 64 anchors`,
          );
          assert.equal(
            new Set(anchors.map(({ id }) => id)).size,
            anchors.length,
            `Trace interaction ${beat.interaction.id} repeats an anchor ID`,
          );
          const nonterminalAnchors = anchors.slice(0, -1);
          assert.equal(
            new Set(nonterminalAnchors.map(({ reachedVariantID }) => reachedVariantID)).size,
            nonterminalAnchors.length,
            `Trace interaction ${beat.interaction.id} repeats a reached-anchor variant ID`,
          );
          for (const [index, anchor] of anchors.entries()) {
            assert.match(
              anchor.id,
              /^[a-z0-9]+(?:-[a-z0-9]+)*$/u,
              `Trace interaction ${beat.interaction.id} has an unstable anchor ID`,
            );
            if (index < anchors.length - 1) {
              assert.match(
                anchor.reachedVariantID,
                /^[a-z0-9]+(?:-[a-z0-9]+)*$/u,
                `Trace interaction ${beat.interaction.id} has an unstable reached-anchor variant ID`,
              );
            } else {
              assert.equal(
                anchor.reachedVariantID,
                undefined,
                `Trace interaction ${beat.interaction.id} must use its completed variant at the terminal anchor`,
              );
            }
            assert.ok(
              Number.isFinite(anchor.x) && anchor.x >= 0 && anchor.x <= 1
                && Number.isFinite(anchor.y) && anchor.y >= 0 && anchor.y <= 1,
              `Trace interaction ${beat.interaction.id} has an anchor outside normalized scene space`,
            );
          }
          assert.ok(
            Number.isFinite(tolerance) && tolerance > 0 && tolerance <= 0.25,
            `Trace interaction ${beat.interaction.id} has an invalid tolerance`,
          );
        }
      }
    }
  }
  assert.equal(new Set(beatIDs).size, beatIDs.length, "First Farmers beat IDs are not unique");
  assert.equal(new Set(sceneIDs).size, sceneIDs.length, "First Farmers scene IDs are not unique");
  assert.equal(new Set(segmentIDs).size, segmentIDs.length, "First Farmers segment IDs are not unique");
  assert.equal(beatIDs.length, 17, "First Farmers review requires exactly 17 beats");
  assert.equal(segmentIDs.length, 37, "First Farmers review requires exactly 37 frozen segments");
  assert.equal(record.accessibilityContract.sceneSummariesRequired, sceneIDs.length);
  assert.equal(calculatedWords, record.pacing.estimatedNarratedWords, "Narrated word budget drifted");
  assert.equal(
    Number((calculatedWords / record.pacing.narrationRateWordsPerMinute).toFixed(1)),
    record.pacing.estimatedNarrationMinutes,
    "Narration duration arithmetic drifted",
  );
  assert.equal(
    record.pacing.estimatedNarrationMinutes
      + record.pacing.estimatedInteractionMinutes
      + record.pacing.estimatedAuthoredSilenceAndTransitionsMinutes,
    record.targetDurationMinutes,
    "Chapter pacing components do not reach the 28-minute authored whole",
  );
  assert.ok(
    record.pacing.firstMeaningfulActionSeconds <= 90,
    "The user must act inside the first 90 seconds",
  );
  assert.equal(record.pacing.maximumPermittedPassiveIntervalSeconds, 90);

  const interactions = interactionProjection(record);
  assert.equal(interactions.length, 6, "First Farmers requires six principal native interactions");
  assert.equal(new Set(interactions.map(({ id }) => id)).size, 6, "Interaction IDs are not unique");
  const grammarCounts = Object.fromEntries(Object.keys(expectedGrammarCounts).map((grammar) => [
    grammar,
    interactions.filter((interaction) => interaction.grammar === grammar).length,
  ]));
  assert.deepEqual(grammarCounts, expectedGrammarCounts, "First Farmers grammar mix drifted");
  assert.deepEqual(record.interactionCoverage.byGrammar, expectedGrammarCounts);
  assert.equal(record.interactionCoverage.principalCount, interactions.length);

  const chapterMappings = mapping.items.filter(({ chapterID }) => chapterID === record.chapterID);
  for (const interaction of interactions) {
    const source = chapterMappings.find(({ nativeInteractionID, nativeRole }) =>
      nativeInteractionID === interaction.id && nativeRole === "principal");
    assert.ok(source, `Interaction ${interaction.id} has no approved mapping`);
    assert.equal(interaction.arcID, source.arcID, `Interaction ${interaction.id} left its arc`);
    assert.equal(interaction.grammar, source.nativeGrammar, `Interaction ${interaction.id} changed grammar`);
    assert.equal(
      interaction.completionEffectID,
      source.worldEffectID,
      `Interaction ${interaction.id} changed its world effect`,
    );
    assert.equal(
      interaction.causalContract.persistentTrace,
      source.worldTraceID,
      `Interaction ${interaction.id} changed its persistent trace`,
    );
    assert.ok(
      effects.effects.some(({ nativeInteractionID }) => nativeInteractionID === interaction.id),
      `Interaction ${interaction.id} has no authored before/after effect`,
    );
  }

  const harvest = interactions.find(({ grammar }) => grammar === "allocate");
  assert.equal(harvest.totalUnits, 12);
  assert.deepEqual(
    harvest.destinations.map(({ id, minimumUnits }) => ({ id, minimumUnits })),
    [
      { id: "food", minimumUnits: 4 },
      { id: "reserve", minimumUnits: 2 },
      { id: "seed", minimumUnits: 3 },
    ],
  );
  assert.deepEqual(
    harvest.destinations.map(({ title }) => title),
    ["Winter food", "Protected reserve", "Seed grain"],
    "Harvest public obligations drifted from the approved review wording",
  );
  const minimumTotal = harvest.destinations.reduce((sum, item) => sum + item.minimumUnits, 0);
  assert.equal(harvest.surplusUnits, harvest.totalUnits - minimumTotal);
  assert.ok(harvest.surplusUnits >= 2, "Harvest needs a real surplus choice");
  assert.equal(harvest.completionRule, "SOURCE_EXHAUSTED_AND_EVERY_MINIMUM_MET");
  assert.ok(!JSON.stringify(harvest).includes("requiredUnits"), "Harvest reintroduced a hidden exact answer");

  const beatsByID = new Map(record.arcs.flatMap(({ beats }) => beats)
    .map((beat) => [beat.beatID, beat]));
  assert.equal(
    record.arcs.find(({ arcID }) => arcID === "first-farmers-arc-02")?.situation,
    "A farming household faces winter, spoilage and the obligation to reserve seed for the next sowing.",
    "Arc 02 seasonal obligation drifted from the approved next-sowing wording",
  );
  const segmentText = (beatID, segmentID) => beatsByID.get(beatID).narrative.segments
    .find(({ id }) => id === segmentID).text;
  assert.ok(
    segmentText("beat-first-farmers-harvest-allocation", "ff-harvest-04")
      .includes("Seed grain is food refused in winter: the next field held inside the present harvest."),
    "Seed-grain factual repair drifted",
  );
  assert.ok(
    segmentText("beat-first-farmers-frontier-consequence", "ff-frontier-consequence-02")
      .includes("The next house plot must outlast its first timbers."),
    "Longhouse-plot factual repair drifted",
  );
  assert.ok(
    segmentText("beat-first-farmers-before-steppe", "ff-ending-01")
      .startsWith("Their voices were never written down. Their structure remains."),
    "First Farmers ending factual repair drifted",
  );
  const longhouse = beatsByID.get("beat-first-farmers-raise-longhouse").interaction;
  assert.deepEqual(
    longhouse.components.map(({ id, prerequisites }) => ({ id, prerequisites })),
    [
      { id: "posts", prerequisites: [] },
      { id: "hearth", prerequisites: ["posts"] },
      { id: "storage", prerequisites: ["posts"] },
      { id: "roof", prerequisites: ["posts"] },
    ],
    "Longhouse must require posts first and permit the remaining three parts in any order",
  );
  const deprecatedSeasonalPhrases = [
    "what must remain untouched for spring",
    "placed next spring",
    "Spring seed",
    "spring sowing",
    "reserve seed for spring",
    "snow then thaw",
    "first thaw",
  ];
  const draftBytes = JSON.stringify(record);
  for (const phrase of deprecatedSeasonalPhrases) {
    assert.ok(!draftBytes.includes(phrase), `Deprecated Chapter 01 seasonal wording returned: ${phrase}`);
  }

  assert.equal(record.editorialRegression.publicResearchApparatus, false);
  assert.equal(record.editorialRegression.publicCaveatsAdded, 0);
  assert.equal(record.editorialRegression.rivalNarrativesAdded, 0);
  assert.ok(record.approvalBoundary.notClaimed.includes("final public wording"));
  assert.ok(record.approvalBoundary.notClaimed.includes("shipping approval"));
  return record;
}

if (process.argv[1]
    && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
  await validateFirstFarmersDraft({ repositoryRoot });
  process.stdout.write(
    "First Farmers native production draft validated without editor or shipping approval.\n",
  );
}
