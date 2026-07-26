import { validateWorldReplay } from "./world-replay.mjs";

const launchPackageCount = 8;
const launchChapterCount = 24;
const sha256Pattern = /^[a-f0-9]{64}$/;

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function sameArray(left, right) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => value === right[index]);
}

function effectEntries(chapter, chapterLocation) {
  const entries = [];
  for (const [arcIndex, arc] of (chapter?.arcs ?? []).entries()) {
    for (const [beatIndex, beat] of (arc?.beats ?? []).entries()) {
      const beatLocation = `${chapterLocation}.arcs[${arcIndex}].beats[${beatIndex}]`;
      for (const [effectIndex, effect] of (beat?.completionEffects ?? []).entries()) {
        entries.push({ effect, location: `${beatLocation}.completionEffects[${effectIndex}]` });
      }
      for (const [effectIndex, effect] of (beat?.interaction?.completionEffects ?? []).entries()) {
        entries.push({
          effect,
          location: `${beatLocation}.interaction.completionEffects[${effectIndex}]`,
        });
      }
    }
  }
  for (const [effectIndex, effect] of (chapter?.completionEffects ?? []).entries()) {
    entries.push({ effect, location: `${chapterLocation}.completionEffects[${effectIndex}]` });
  }
  return entries;
}

export class LaunchAssemblyError extends Error {
  constructor(issues) {
    super(issues.join("\n"));
    this.name = "LaunchAssemblyError";
    this.issues = [...issues];
  }
}

/**
 * Verifies the complete launch as one causal work after the collection and
 * each payload have passed their document-level validators. Package array
 * order is immaterial; package chapter order and collection sequence are not.
 */
export function validateLaunchAssembly(collection, payloads) {
  const issues = [];
  const packageSpecs = Array.isArray(collection?.packages) ? collection.packages : [];
  const chapterEntries = Array.isArray(collection?.chapters) ? collection.chapters : [];
  const authoredPayloads = Array.isArray(payloads) ? payloads : [];

  if (packageSpecs.length !== launchPackageCount) {
    issues.push(`launchAssembly.collection.packages: exactly ${launchPackageCount} declared packages required`);
  }
  if (chapterEntries.length !== launchChapterCount) {
    issues.push(`launchAssembly.collection.chapters: exactly ${launchChapterCount} declared chapters required`);
  }
  if (!Array.isArray(payloads)) {
    issues.push("launchAssembly.payloads: array required");
  } else if (payloads.length !== packageSpecs.length) {
    issues.push("launchAssembly.payloads: exactly one payload per declared package required");
  }

  const packageSpecByID = new Map();
  for (const [index, packageSpec] of packageSpecs.entries()) {
    if (!isRecord(packageSpec) || typeof packageSpec.id !== "string") {
      issues.push(`launchAssembly.collection.packages[${index}].id: package ID required`);
      continue;
    }
    if (packageSpecByID.has(packageSpec.id)) {
      issues.push(`launchAssembly.collection.packages[${index}].id: duplicate declared package '${packageSpec.id}'`);
      continue;
    }
    packageSpecByID.set(packageSpec.id, packageSpec);
  }

  const payloadByPackageID = new Map();
  for (const [index, payload] of authoredPayloads.entries()) {
    if (!isRecord(payload) || typeof payload.packageID !== "string") {
      issues.push(`launchAssembly.payloads[${index}].packageID: package ID required`);
      continue;
    }
    if (!packageSpecByID.has(payload.packageID)) {
      issues.push(`launchAssembly.payloads[${index}].packageID: undeclared package '${payload.packageID}'`);
      continue;
    }
    if (payloadByPackageID.has(payload.packageID)) {
      issues.push(`launchAssembly.payloads[${index}].packageID: duplicate payload for '${payload.packageID}'`);
      continue;
    }
    payloadByPackageID.set(payload.packageID, payload);
  }

  for (const packageID of packageSpecByID.keys()) {
    if (!payloadByPackageID.has(packageID)) {
      issues.push(`launchAssembly.payloads: missing payload for '${packageID}'`);
    }
  }

  const firstPayload = authoredPayloads.find((payload) => isRecord(payload) && isRecord(payload.worldSeed));
  const canonicalSeed = firstPayload === undefined ? undefined : canonical(firstPayload.worldSeed);
  if (canonicalSeed === undefined) {
    issues.push("launchAssembly.worldSeed: every payload requires the shared launch seed");
  }

  const chapterByID = new Map();
  const effectLocationByID = new Map();
  for (const [packageID, packageSpec] of packageSpecByID) {
    const payload = payloadByPackageID.get(packageID);
    if (payload === undefined) continue;
    if (!isRecord(payload.worldSeed) || canonical(payload.worldSeed) !== canonicalSeed) {
      issues.push(`launchAssembly.payloads.${packageID}.worldSeed: must be identical across all launch packages`);
    }

    const expectedChapterIDs = packageSpec.chapterIDs;
    const actualChapters = Array.isArray(payload.chapters) ? payload.chapters : [];
    const actualChapterIDs = actualChapters.map((chapter) => chapter?.id);
    if (!sameArray(actualChapterIDs, expectedChapterIDs)) {
      issues.push(`launchAssembly.payloads.${packageID}.chapters: ownership and order must exactly match collection package`);
    }

    for (const [chapterIndex, chapter] of actualChapters.entries()) {
      const chapterLocation = `launchAssembly.payloads.${packageID}.chapters[${chapterIndex}]`;
      if (!isRecord(chapter) || typeof chapter.id !== "string") continue;
      if (chapterByID.has(chapter.id)) {
        issues.push(`${chapterLocation}.id: duplicate launch chapter '${chapter.id}'`);
      } else {
        chapterByID.set(chapter.id, chapter);
      }
      for (const { effect, location } of effectEntries(chapter, chapterLocation)) {
        if (!isRecord(effect) || typeof effect.id !== "string") continue;
        const previousLocation = effectLocationByID.get(effect.id);
        if (previousLocation !== undefined) {
          issues.push(`${location}.id: duplicate world-effect '${effect.id}' first declared at ${previousLocation}`);
        } else {
          effectLocationByID.set(effect.id, location);
        }
      }
    }
  }

  const orderedEntries = [...chapterEntries].sort((left, right) => left.sequence - right.sequence);
  const orderedChapterIDs = orderedEntries.map((entry) => entry?.id);
  const expectedSequence = Array.from({ length: launchChapterCount }, (_, index) => index + 1);
  if (!sameArray(orderedEntries.map((entry) => entry?.sequence), expectedSequence)) {
    issues.push("launchAssembly.collection.chapters.sequence: must cover 1 through 24 exactly");
  }

  for (const [index, entry] of orderedEntries.entries()) {
    if (!isRecord(entry) || typeof entry.id !== "string") continue;
    const owner = packageSpecByID.get(entry.packageID);
    if (!owner || !Array.isArray(owner.chapterIDs) || !owner.chapterIDs.includes(entry.id)) {
      issues.push(`launchAssembly.collection.chapters[${index}]: '${entry.id}' is not owned by package '${entry.packageID}'`);
    }
    if (!chapterByID.has(entry.id)) {
      issues.push(`launchAssembly.collection.chapters[${index}]: payload chapter '${entry.id}' is missing`);
    }
  }
  for (const chapterID of chapterByID.keys()) {
    if (!orderedChapterIDs.includes(chapterID)) {
      issues.push(`launchAssembly.payloads: undeclared launch chapter '${chapterID}'`);
    }
  }

  if (issues.length > 0) throw new LaunchAssemblyError(issues);

  const orderedChapters = orderedEntries.map((entry) => chapterByID.get(entry.id));
  const replayIssues = [];
  const replay = validateWorldReplay(
    { worldSeed: firstPayload.worldSeed, chapters: orderedChapters },
    "launchAssembly.replay",
    replayIssues,
  );
  if (replayIssues.length > 0) throw new LaunchAssemblyError(replayIssues);
  if (typeof replay.cumulativeDigest !== "string" || !sha256Pattern.test(replay.cumulativeDigest)) {
    throw new LaunchAssemblyError(["launchAssembly.replay: deterministic final SHA-256 was not produced"]);
  }

  return {
    packageCount: packageSpecs.length,
    chapterCount: orderedChapters.length,
    finalWorldSHA256: replay.cumulativeDigest,
  };
}
