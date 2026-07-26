import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { validateHarvestEditorReview } from "./validate-harvest-editor-review.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const reviewPath = path.join(repositoryRoot, "native/phase1/editor-review/harvest/harvest-native-draft-v1.json");
const loadReview = async () => JSON.parse(await readFile(reviewPath, "utf8"));

test("Harvest review binds authority, real allocation choice and one historical consequence", async () => {
  const review = await validateHarvestEditorReview({ repositoryRoot });
  assert.equal(review.status, "DRAFT_AWAITING_EDITOR_APPROVAL");
  assert.equal(review.interactionRecommendation.surplusUnitsAfterObligations, 3);
});

test("Harvest review rejects false approval and a hidden exact allocation", async () => {
  const approved = await loadReview();
  approved.status = "APPROVED_BY_EDITOR_IN_CHIEF";
  await assert.rejects(
    () => validateHarvestEditorReview({ repositoryRoot, review: approved }),
    /cannot claim editor approval/,
  );

  const hiddenAnswer = await loadReview();
  hiddenAnswer.interactionRecommendation.destinations[0].requiredUnits = 5;
  await assert.rejects(
    () => validateHarvestEditorReview({ repositoryRoot, review: hiddenAnswer }),
    /hidden exact distribution/,
  );
});
