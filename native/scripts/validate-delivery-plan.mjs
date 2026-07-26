#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const readJSON = (relativePath) => readFile(path.join(repositoryRoot, relativePath), "utf8").then(JSON.parse);
const stableID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;

function equal(left, right) {
  return JSON.stringify([...left].sort()) === JSON.stringify([...right].sort());
}

async function main() {
  const [plan, catalog] = await Promise.all([
    readJSON("native/blueprint/delivery-plan.json"),
    readJSON("native/blueprint/chapter-catalog.json"),
  ]);
  const issues = [];
  if (plan.schemaVersion !== 1 || plan.status !== "LOCKED_NATIVE_LAUNCH") {
    issues.push("delivery plan: locked schema/status required");
  }
  const budgets = plan.budgets ?? {};
  if (!["shellAndEngineBytes", "essentialInstallBytes", "perPaidPackageBytes", "completeInstalledWorkBytes"]
    .every((key) => Number.isSafeInteger(budgets[key]) && budgets[key] > 0)) {
    issues.push("delivery plan: every size budget must be a positive safe integer");
  } else if (budgets.shellAndEngineBytes > 100_000_000
      || budgets.essentialInstallBytes > 750_000_000
      || budgets.perPaidPackageBytes > 750_000_000
      || budgets.completeInstalledWorkBytes > 6_000_000_000
      || budgets.completeInstalledWorkBytes <= budgets.shellAndEngineBytes) {
    issues.push("delivery plan: a locked size budget was exceeded");
  }
  if (plan.entitlement?.kind !== "NON_CONSUMABLE"
      || plan.entitlement?.entitlementID !== "launch-complete-work"
      || plan.entitlement?.storeProductID !== "com.thelongwest.ios.unlock.collection01") {
    issues.push("delivery plan: one permanent launch entitlement is required");
  }
  const packages = Array.isArray(plan.packages) ? plan.packages : [];
  if (packages.length !== 8 || new Set(packages.map((item) => item.packageID)).size !== 8) {
    issues.push("delivery plan: exactly eight unique packages required");
  }
  const chapterIDs = catalog.chapters.map((chapter) => chapter.contentID);
  const declaredChapterIDs = packages.flatMap((item) => item.chapterIDs ?? []);
  if (!equal(declaredChapterIDs, chapterIDs) || new Set(declaredChapterIDs).size !== 24) {
    issues.push("delivery plan: every launch chapter must belong to exactly one package");
  }
  const freeIDSet = new Set(catalog.freeContentIDs);
  for (const chapter of catalog.chapters) {
    const shouldBeFree = freeIDSet.has(chapter.contentID);
    if (chapter.freeAtLaunch !== shouldBeFree
        || chapter.access !== (shouldBeFree ? "FREE" : "UNLOCKED_BY_COLLECTION_PURCHASE")) {
      issues.push(`delivery plan: access drift for ${chapter.contentID}`);
    }
  }
  for (const item of packages) {
    if (!stableID.test(item.packageID ?? "")) issues.push(`delivery plan: invalid packageID ${item.packageID}`);
    if (item.maximumInstalledBytes > 750_000_000 || item.maximumInstalledBytes <= 0) {
      issues.push(`delivery plan: invalid size budget for ${item.packageID}`);
    }
    if (!Array.isArray(item.chapterIDs) || item.chapterIDs.length !== 3) {
      issues.push(`delivery plan: ${item.packageID} must contain three chapters`);
    }
  }
  const essential = packages.filter((item) => item.isEssentialInstall === true);
  if (essential.length !== 1 || essential[0].delivery !== "BASE_INSTALL"
      || !equal(essential[0].chapterIDs, catalog.freeContentIDs)) {
    issues.push("delivery plan: the base install must contain exactly the stable free triad");
  }
  const expectedPaidGroups = [
    [2, 3, 4], [5, 6, 7], [8, 9, 10], [11, 12, 14],
    [15, 16, 17], [18, 19, 20], [22, 23, 24],
  ].map((group) => group.map((ordinal) =>
    catalog.chapters.find((chapter) => chapter.ordinal === ordinal)?.contentID));
  const paid = packages.filter((item) => item.isEssentialInstall === false);
  if (paid.length !== 7 || paid.some((item) => item.delivery !== "APPLE_HOSTED_BACKGROUND_ASSETS")) {
    issues.push("delivery plan: seven Apple-hosted paid packages required");
  }
  expectedPaidGroups.forEach((expected, index) => {
    if (!paid[index] || !equal(paid[index].chapterIDs, expected)) {
      issues.push(`delivery plan: paid package ${index + 1} does not match the locked chapter group`);
    }
  });
  // Per-package ceilings are independent guardrails. The compiled package
  // aggregate is checked against the complete installed-work ceiling minus
  // the reserved shell budget once real assets exist.
  if (plan.activation?.manifestDigest !== "SHA-256"
      || plan.activation?.manifestSignature !== "P-256-SHA256"
      || plan.activation?.fileDigest !== "SHA-256"
      || plan.activation?.strategy !== "VERIFY_THEN_ATOMIC_RENAME"
      || plan.activation?.rollback !== "KEEP_LAST_VERIFIED_PACKAGE") {
    issues.push("delivery plan: signed atomic activation contract changed");
  }
  if (issues.length) throw new Error(issues.join("\n"));
  process.stdout.write("Delivery locked: 1 essential + 7 paid packages, 24 unique chapters, 6 GB ceiling.\n");
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
