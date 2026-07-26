import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

const reviewRelativePath = "native/phase1/editor-review/harvest/harvest-native-draft-v1.json";
const leakagePatterns = [
  /scholars? (?:debate|disagree)/iu,
  /historians? (?:debate|disagree)/iu,
  /the picture is complex/iu,
  /this account is contested/iu,
  /from another perspective/iu,
  /it is important to note/iu,
];

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function publicDraftStrings(review) {
  return [
    review.manuscript.period,
    review.manuscript.place,
    review.manuscript.title,
    ...review.manuscript.cues.map(({ text }) => text),
    ...Object.values(review.interfaceCopy),
    ...review.destinationCopy.flatMap(({ standard, focused }) => [standard, focused]),
    review.accessibility.sceneSummary,
    review.accessibility.sourceLabel,
  ].map(String);
}

export async function validateHarvestEditorReview({ repositoryRoot, review = undefined } = {}) {
  assert.ok(repositoryRoot, "Harvest editor review requires the repository root");
  const reviewPath = path.resolve(repositoryRoot, reviewRelativePath);
  const record = review ?? JSON.parse(await readFile(reviewPath, "utf8"));
  assert.equal(record.schemaVersion, 1, "Harvest editor review schema drifted");
  assert.equal(record.status, "DRAFT_AWAITING_EDITOR_APPROVAL", "Harvest draft cannot claim editor approval");
  assert.equal(record.shippingState, "PROHIBITED", "Harvest draft cannot become shipping content");
  assert.equal(record.chapterID, "first-farmers", "Harvest draft left Chapter 01");
  assert.equal(record.arcID, "first-farmers-arc-02", "Harvest draft left its approved arc");
  assert.equal(record.movementID, "the-harvest-had-to-last", "Harvest movement drifted");
  assert.equal(record.interactionID, "interaction-first-farmers-the-harvest-had-to-last", "Harvest interaction drifted");
  assert.equal(record.worldTraceID, "trace-seasonal-store", "Harvest world trace drifted");
  assert.equal(record.worldEffectID, "effect-first-farmers-the-harvest-had-to-last", "Harvest world effect drifted");

  assert.equal(record.authorityBindings.length, 5, "Harvest draft requires five exact authority bindings");
  for (const binding of record.authorityBindings) {
    const file = path.resolve(repositoryRoot, binding.path);
    assert.ok(file.startsWith(`${path.resolve(repositoryRoot)}${path.sep}`), "Harvest authority path escaped the repository");
    assert.equal(sha256(await readFile(file)), binding.sha256, `Harvest authority bytes drifted: ${binding.path}`);
  }

  const recommendation = record.interactionRecommendation;
  assert.equal(recommendation.grammar, "allocate", "Harvest must remain Allocate");
  assert.equal(recommendation.totalRuntimeShares, 12, "Harvest runtime share count drifted");
  assert.equal(recommendation.completionRule, "SOURCE_EXHAUSTED_AND_EVERY_MINIMUM_MET", "Harvest completion became a hidden exact answer");
  assert.equal(recommendation.destinations.length, 3, "Harvest requires three material obligations");
  assert.deepEqual(
    recommendation.destinations.map(({ id }) => id),
    ["food", "reserve", "seed"],
    "Harvest destination order drifted",
  );
  const minimumTotal = recommendation.destinations.reduce((sum, destination) => {
    assert.ok(Number.isSafeInteger(destination.minimumUnits) && destination.minimumUnits > 0, "Harvest minimum must be a positive integer");
    return sum + destination.minimumUnits;
  }, 0);
  assert.equal(recommendation.surplusUnitsAfterObligations, recommendation.totalRuntimeShares - minimumTotal, "Harvest surplus arithmetic drifted");
  assert.ok(recommendation.surplusUnitsAfterObligations >= 2, "Harvest needs a real allocation choice after obligations");
  assert.equal(recommendation.reversalPermittedUntilCommit, true, "Harvest allocation must remain reversible before commit");
  assert.equal(recommendation.persistentWorldEffect, "ONE_SHARED_DOCUMENTED_EFFECT_FOR_EVERY_VALID_DISTRIBUTION", "Harvest local choice cannot create alternative history");
  assert.ok(!JSON.stringify(recommendation).includes("requiredUnits"), "Harvest recommendation reintroduced one hidden exact distribution");

  const authoredEffects = JSON.parse(await readFile(
    path.resolve(repositoryRoot, "native/blueprint/authored-interaction-effects-01-12.json"),
    "utf8",
  ));
  const effect = authoredEffects.effects.find(({ nativeInteractionID }) => nativeInteractionID === record.interactionID);
  assert.ok(effect, "Harvest approved effect is missing");
  assert.equal(recommendation.worldBefore, effect.beforeState, "Harvest before-state drifted from the approved effect");
  assert.equal(recommendation.worldAfter, effect.afterState, "Harvest after-state drifted from the approved effect");

  assert.equal(record.manuscript.locale, "en", "Harvest launch manuscript must remain English");
  assert.equal(record.manuscript.cues.length, 6, "Harvest draft requires its six authored dramatic cues");
  assert.equal(new Set(record.manuscript.cues.map(({ id }) => id)).size, 6, "Harvest cue IDs must be unique");
  for (const value of publicDraftStrings(record)) {
    assert.ok(value.trim(), "Harvest public draft contains empty copy");
    for (const pattern of leakagePatterns) {
      assert.ok(!pattern.test(value), `Harvest public draft leaked academic meta-language: ${pattern}`);
    }
  }
  assert.equal(record.accessibility.commitUsesSameReducer, true, "VoiceOver must use the same Harvest reducer");
  assert.equal(record.accessibility.completionConsequenceMatchesTouch, true, "VoiceOver consequence drifted from touch");
  assert.equal(record.factCheck.status, "PASS", "Harvest backstage F1–F7 check is not closed");
  assert.equal(record.factCheck.findingCount, 0, "Harvest draft still has factual findings");
  assert.equal(record.factCheck.publicCaveatsAdded, 0, "Harvest fact check added public caveats");
  assert.ok(record.claimsExcluded.includes("editor approval"), "Harvest draft must exclude editor approval");
  assert.ok(record.claimsExcluded.includes("shipping approval"), "Harvest draft must exclude shipping approval");
  return record;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  const repositoryRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
  await validateHarvestEditorReview({ repositoryRoot });
  process.stdout.write("Harvest native editor-review draft validated without editor or shipping approval.\n");
}
