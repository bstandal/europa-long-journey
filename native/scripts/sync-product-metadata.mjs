#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.dirname(scriptDirectory);
const metadataPath = path.join(nativeRoot, "product.json");
const catalogPath = path.join(nativeRoot, "blueprint", "chapter-catalog.json");
const deliveryPath = path.join(nativeRoot, "blueprint", "delivery-plan.json");
const swiftPath = path.join(
  nativeRoot,
  "ios",
  "Sources",
  "ContentKit",
  "GeneratedProductMetadata.swift",
);
const launchSwiftPath = path.join(
  nativeRoot,
  "ios",
  "Sources",
  "ContentKit",
  "GeneratedLaunchConfiguration.swift",
);
const launchBudgetsSwiftPath = path.join(
  nativeRoot,
  "ios",
  "Sources",
  "ContentKit",
  "GeneratedLaunchBudgets.swift",
);
const xcconfigPath = path.join(nativeRoot, "ios", "Config", "Product.xcconfig");

function swiftLiteral(value) {
  return JSON.stringify(value)
    .replaceAll("\\u2028", "\\u{2028}")
    .replaceAll("\\u2029", "\\u{2029}");
}

function validate(metadata) {
  const issues = [];
  if (metadata.schemaVersion !== 1) issues.push("schemaVersion must be 1");
  for (const key of ["franchiseName", "workTitle", "displayName", "launchLanguage"]) {
    if (typeof metadata[key] !== "string" || !metadata[key].trim()) issues.push(`${key} is required`);
  }
  if (metadata.launchLanguage !== "en") issues.push("launchLanguage must remain en for launch");
  if (issues.length) throw new Error(issues.join("\n"));
}

function renderSwift(metadata) {
  return `// Generated from native/product.json. Do not edit by hand.\n\npublic extension ProductMetadata {\n    static let current = ProductMetadata(\n        franchiseName: ${swiftLiteral(metadata.franchiseName)},\n        workTitle: ${swiftLiteral(metadata.workTitle)}\n    )\n}\n`;
}

function renderXCConfig(metadata) {
  return `// Generated from native/product.json. Do not edit by hand.\nPRODUCT_DISPLAY_NAME = ${metadata.displayName}\n`;
}

function validateLaunchConfiguration(catalog, delivery) {
  const issues = [];
  const chapters = catalog.chapters ?? [];
  const packages = delivery.packages ?? [];
  if (catalog.schemaVersion !== 1 || chapters.length !== 24 || catalog.chapterCount !== 24) {
    issues.push("chapter catalog must contain the 24 launch chapters");
  }
  if (new Set(chapters.map((chapter) => chapter.contentID)).size !== 24
      || chapters.some((chapter, index) => chapter.ordinal !== index + 1)) {
    issues.push("chapter catalog IDs and ordinals must be unique and cover 1 through 24");
  }
  if (chapters.some((chapter) => typeof chapter.title !== "string" || !chapter.title.trim()
      || typeof chapter.period !== "string" || !chapter.period.trim())) {
    issues.push("every launch chapter requires a title and period");
  }
  const freeIDs = catalog.freeContentIDs ?? [];
  if (freeIDs.length !== 3 || new Set(freeIDs).size !== 3
      || freeIDs.some((id) => !chapters.some((chapter) => chapter.contentID === id))) {
    issues.push("chapter catalog must name exactly three unique free launch chapters");
  }
  if (chapters.some((chapter) => chapter.freeAtLaunch !== freeIDs.includes(chapter.contentID)
      || chapter.access !== (freeIDs.includes(chapter.contentID)
        ? "FREE"
        : "UNLOCKED_BY_COLLECTION_PURCHASE"))) {
    issues.push("chapter access must match the stable free triad and collection purchase");
  }
  if (delivery.schemaVersion !== 1 || delivery.status !== "LOCKED_NATIVE_LAUNCH" || packages.length !== 8) {
    issues.push("delivery plan must contain the eight locked launch packages");
  }
  if (packages.some((item) => !Number.isSafeInteger(item.maximumInstalledBytes)
      || item.maximumInstalledBytes <= 0)
      || !Number.isSafeInteger(delivery.budgets?.shellAndEngineBytes)
      || packages.at(-1)?.maximumInstalledBytes <= delivery.budgets.shellAndEngineBytes) {
    issues.push("every package needs a positive byte budget and the final package must reserve the shell");
  }
  const declared = packages.flatMap((item) => item.chapterIDs ?? []);
  if (declared.length !== 24 || new Set(declared).size !== 24
      || declared.some((id) => !chapters.some((chapter) => chapter.contentID === id))) {
    issues.push("delivery packages must own every catalog chapter exactly once");
  }
  const essential = packages.filter((item) => item.isEssentialInstall === true);
  if (essential.length !== 1) issues.push("exactly one essential launch package is required");
  if (essential.length === 1
      && (essential[0].chapterIDs.length !== freeIDs.length
        || essential[0].chapterIDs.some((id) => !freeIDs.includes(id)))) {
    issues.push("the essential package must contain exactly the free triad");
  }
  if (delivery.entitlement?.kind !== "NON_CONSUMABLE") {
    issues.push("the launch entitlement must be non-consumable");
  }
  if (!Number.isSafeInteger(delivery.budgets?.shellAndEngineBytes)
      || !Number.isSafeInteger(delivery.budgets?.completeInstalledWorkBytes)
      || delivery.budgets.shellAndEngineBytes <= 0
      || delivery.budgets.completeInstalledWorkBytes <= delivery.budgets.shellAndEngineBytes) {
    issues.push("the installed-work budget must reserve positive space for the app shell");
  }
  if (issues.length) throw new Error(issues.join("\n"));
}

function renderLaunchSwift(catalog, delivery) {
  const chapters = [...catalog.chapters].sort((left, right) => left.ordinal - right.ordinal);
  const essential = delivery.packages.find((item) => item.isEssentialInstall === true);
  const packageByChapter = new Map(
    delivery.packages.flatMap((item) => item.chapterIDs.map((id) => [id, item.packageID])),
  );
  const chapterOrder = chapters.map((chapter) => `        ${swiftLiteral(chapter.contentID)},`).join("\n");
  const freeIDs = catalog.freeContentIDs.map((id) => `        ${swiftLiteral(id)},`).join("\n");
  const packageOrder = delivery.packages.map((item) => `        ${swiftLiteral(item.packageID)},`).join("\n");
  const packageChapters = delivery.packages.map((item) => {
    const ids = item.chapterIDs.map((id) => `            ${swiftLiteral(id)},`).join("\n");
    return `        ${swiftLiteral(item.packageID)}: [\n${ids}\n        ],`;
  }).join("\n");
  const packageBudgets = delivery.packages.map((item) =>
    `        ${swiftLiteral(item.packageID)}: ${item.maximumInstalledBytes},`).join("\n");
  const launchChapters = chapters.map((chapter) => {
    const access = chapter.freeAtLaunch
      ? ".included"
      : ".entitlement(fullWorkEntitlementID)";
    return `        ChapterIndexEntry(
            id: ${swiftLiteral(chapter.contentID)},
            sequence: ${chapter.ordinal},
            title: LocalizedStringSpec(
                id: ${swiftLiteral(`chapter-${chapter.contentID}-title`)},
                launchEnglish: ${swiftLiteral(chapter.title)}
            ),
            period: LocalizedStringSpec(
                id: ${swiftLiteral(`chapter-${chapter.contentID}-period`)},
                launchEnglish: ${swiftLiteral(chapter.period)}
            ),
            packageID: ${swiftLiteral(packageByChapter.get(chapter.contentID))},
            access: ${access}
        ),`;
  }).join("\n");
  const finalPackageID = delivery.packages.at(-1).packageID;
  const launchPackages = delivery.packages.map((item) => {
    const ids = item.chapterIDs.map((id) => `                ${swiftLiteral(id)},`).join("\n");
    const maximumBytes = item.maximumInstalledBytes
      - (item.packageID === finalPackageID ? delivery.budgets.shellAndEngineBytes : 0);
    return `        ContentPackageSpec(
            id: ${swiftLiteral(item.packageID)},
            version: SchemaVersion(major: 1),
            chapterIDs: [
${ids}
            ],
            maximumInstalledBytes: ${maximumBytes},
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: ${item.isEssentialInstall}
        ),`;
  }).join("\n");

  return `// Generated from the Phase 0 catalog and delivery plan. Do not edit by hand.\n\npublic enum LaunchContent {\n    public static let collectionID: CollectionID = ${swiftLiteral(catalog.collectionID)}\n    public static let essentialPackageID: PackageID = ${swiftLiteral(essential.packageID)}\n    public static let fullWorkEntitlementID: EntitlementID = ${swiftLiteral(delivery.entitlement.entitlementID)}\n    public static let fullWorkStoreProductID = ${swiftLiteral(delivery.entitlement.storeProductID)}\n    public static let completeInstalledWorkBytes: Int64 = ${delivery.budgets.completeInstalledWorkBytes}\n\n    public static let chapterOrder: [ChapterID] = [\n${chapterOrder}\n    ]\n\n    public static let freeChapterIDs: Set<ChapterID> = [\n${freeIDs}\n    ]\n\n    public static let packageIDsInDeliveryOrder: [PackageID] = [\n${packageOrder}\n    ]\n\n    public static let packageChapterIDs: [PackageID: Set<ChapterID>] = [\n${packageChapters}\n    ]\n\n    public static let packageMaximumInstalledBytes: [PackageID: Int64] = [\n${packageBudgets}\n    ]\n\n    public static let launchChapters: [ChapterIndexEntry] = [\n${launchChapters}\n    ]\n\n    public static let launchPackages: [ContentPackageSpec] = [\n${launchPackages}\n    ]\n\n    public static let collectionManifest = CollectionManifest(\n        schemaVersion: SchemaVersion(major: 1),\n        collectionID: collectionID,\n        locale: .launchEnglish,\n        product: .current,\n        chapters: launchChapters,\n        packages: launchPackages,\n        entitlements: [\n            EntitlementSpec(\n                id: fullWorkEntitlementID,\n                storeProductID: fullWorkStoreProductID,\n                kind: .nonConsumable\n            ),\n        ]\n    )\n}\n`;
}

function renderLaunchBudgetsSwift(delivery) {
  return `// Generated from the Phase 0 delivery plan. Do not edit by hand.\n\npublic extension LaunchContent {\n    static let shellAndEngineBytes: Int64 = ${delivery.budgets.shellAndEngineBytes}\n    static let maximumInstalledContentBytes: Int64 = completeInstalledWorkBytes - shellAndEngineBytes\n}\n`;
}

async function main() {
  const [metadata, catalog, delivery] = await Promise.all([
    readFile(metadataPath, "utf8").then(JSON.parse),
    readFile(catalogPath, "utf8").then(JSON.parse),
    readFile(deliveryPath, "utf8").then(JSON.parse),
  ]);
  validate(metadata);
  validateLaunchConfiguration(catalog, delivery);
  const expected = [
    [swiftPath, renderSwift(metadata)],
    [launchSwiftPath, renderLaunchSwift(catalog, delivery)],
    [launchBudgetsSwiftPath, renderLaunchBudgetsSwift(delivery)],
    [xcconfigPath, renderXCConfig(metadata)],
  ];
  if (process.argv.includes("--check")) {
    const drift = [];
    for (const [file, content] of expected) {
      if (await readFile(file, "utf8").catch(() => null) !== content) drift.push(file);
    }
    if (drift.length) throw new Error(`Generated product metadata is stale:\n${drift.join("\n")}`);
    console.log("Validated generated product metadata.");
    return;
  }
  for (const [file, content] of expected) await writeFile(file, content);
  console.log("Synchronized generated product metadata.");
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
