#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const inventoryPath = path.join(repositoryRoot, "native/blueprint/source-inventory.json");
const chapterRoot = path.join(repositoryRoot, "site/src/data/chapters");

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}

function relative(absolute) {
  return path.relative(repositoryRoot, absolute).split(path.sep).join("/");
}

function matchingClose(source, openIndex, openCharacter, closeCharacter) {
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = openIndex; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (character === "\n") lineComment = false;
      continue;
    }
    if (blockComment) {
      if (character === "*" && next === "/") {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }
    if (character === "/" && next === "*") {
      blockComment = true;
      index += 1;
      continue;
    }
    if (character === "\"" || character === "'" || character === "`") {
      quote = character;
      continue;
    }
    if (character === openCharacter) depth += 1;
    if (character === closeCharacter) {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  throw new Error(`Unclosed ${openCharacter} at byte ${openIndex}`);
}

function movementObjects(source, sourcePath) {
  const match = /^[\t ]*movements:[\t ]*\[/mu.exec(source);
  if (!match) throw new Error(`${sourcePath}: movements array not found`);
  const arrayStart = match.index + match[0].lastIndexOf("[");
  const arrayEnd = matchingClose(source, arrayStart, "[", "]");
  const objects = [];
  let index = arrayStart + 1;
  while (index < arrayEnd) {
    const character = source[index];
    if (character === "\"" || character === "'" || character === "`") {
      const end = matchingStringEnd(source, index, character);
      index = end + 1;
      continue;
    }
    if (character === "/" && source[index + 1] === "/") {
      index = source.indexOf("\n", index + 2);
      if (index < 0) break;
      continue;
    }
    if (character === "/" && source[index + 1] === "*") {
      const end = source.indexOf("*/", index + 2);
      if (end < 0) throw new Error(`${sourcePath}: unclosed block comment`);
      index = end + 2;
      continue;
    }
    if (character === "{") {
      const end = matchingClose(source, index, "{", "}");
      objects.push(source.slice(index, end + 1));
      index = end + 1;
      continue;
    }
    index += 1;
  }
  return objects;
}

function matchingStringEnd(source, start, quote) {
  let escaped = false;
  for (let index = start + 1; index < source.length; index += 1) {
    if (escaped) {
      escaped = false;
    } else if (source[index] === "\\") {
      escaped = true;
    } else if (source[index] === quote) {
      return index;
    }
  }
  throw new Error(`Unclosed string at byte ${start}`);
}

function topLevelMovement(object, sourcePath) {
  let depth = 0;
  let movementID = null;
  let hasInteraction = false;
  let index = 0;
  while (index < object.length) {
    const character = object[index];
    if (character === "\"" || character === "'" || character === "`") {
      index = matchingStringEnd(object, index, character) + 1;
      continue;
    }
    if (character === "/" && object[index + 1] === "/") {
      const end = object.indexOf("\n", index + 2);
      index = end < 0 ? object.length : end + 1;
      continue;
    }
    if (character === "/" && object[index + 1] === "*") {
      const end = object.indexOf("*/", index + 2);
      if (end < 0) throw new Error(`${sourcePath}: unclosed block comment`);
      index = end + 2;
      continue;
    }
    if (character === "{") {
      depth += 1;
      index += 1;
      continue;
    }
    if (character === "}") {
      depth -= 1;
      index += 1;
      continue;
    }
    if (depth === 1 && /[A-Za-z_$]/u.test(character)) {
      const start = index;
      index += 1;
      while (index < object.length && /[A-Za-z0-9_$]/u.test(object[index])) index += 1;
      const key = object.slice(start, index);
      while (/\s/u.test(object[index] ?? "")) index += 1;
      if (object[index] !== ":") continue;
      index += 1;
      if (key === "interaction") hasInteraction = true;
      if (key === "id") {
        while (/\s/u.test(object[index] ?? "")) index += 1;
        const quote = object[index];
        if (quote !== "\"" && quote !== "'") {
          throw new Error(`${sourcePath}: movement id must be a static string`);
        }
        const end = matchingStringEnd(object, index, quote);
        movementID = object.slice(index + 1, end);
        index = end + 1;
      }
      continue;
    }
    index += 1;
  }
  if (!movementID) throw new Error(`${sourcePath}: movement without a static top-level id`);
  return { movementID, hasInteraction };
}

async function sourceRecord(absolute) {
  const data = await readFile(absolute);
  return { path: relative(absolute), sha256: sha256(data) };
}

async function supportFiles() {
  const interactionRoot = path.join(repositoryRoot, "site/src/components/chapters/interactions");
  const interactionFiles = (await readdir(interactionRoot, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith(".astro"))
    .map((entry) => path.join(interactionRoot, entry.name));
  const fixed = [
    "site/src/data/chapters/index.ts",
    "site/src/types/chapter.ts",
    "site/src/components/chapters/ChapterInteraction.astro",
    "site/src/components/chapters/ChapterMovement.astro",
    "site/src/components/chapters/ChapterStage.astro",
    "site/src/scripts/chapter-runtime.ts",
  ].map((item) => path.join(repositoryRoot, item));
  return Promise.all([...fixed, ...interactionFiles].sort().map(sourceRecord));
}

async function buildInventory() {
  const chapterFiles = (await readdir(chapterRoot, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith(".ts") && entry.name !== "index.ts")
    .map((entry) => path.join(chapterRoot, entry.name))
    .sort();
  const chapters = [];
  for (const absolute of chapterFiles) {
    const data = await readFile(absolute);
    const source = data.toString("utf8");
    const slug = /^[\t ]*slug:[\t ]*["']([^"']+)["']/mu.exec(source)?.[1];
    if (!slug) throw new Error(`${relative(absolute)}: static chapter slug not found`);
    const movements = movementObjects(source, relative(absolute)).map((object) =>
      topLevelMovement(object, relative(absolute)));
    const movementIDs = movements.map((movement) => movement.movementID);
    if (new Set(movementIDs).size !== movementIDs.length) {
      throw new Error(`${relative(absolute)}: duplicate movement ID`);
    }
    chapters.push({
      contentID: slug,
      path: relative(absolute),
      sha256: sha256(data),
      movementCount: movements.length,
      interactionCount: movements.filter((movement) => movement.hasInteraction).length,
      movementIDs,
      interactionMovementIDs: movements
        .filter((movement) => movement.hasInteraction)
        .map((movement) => movement.movementID),
    });
  }
  chapters.sort((left, right) => left.contentID.localeCompare(right.contentID, "en"));
  return {
    schemaVersion: 1,
    sourceRoot: "site/src/data/chapters",
    chapterCount: chapters.length,
    movementCount: chapters.reduce((sum, chapter) => sum + chapter.movementCount, 0),
    interactionCount: chapters.reduce((sum, chapter) => sum + chapter.interactionCount, 0),
    chapters,
    supportFiles: await supportFiles(),
  };
}

function equalJSON(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function equalSets(left, right) {
  return equalJSON([...left].sort(), [...right].sort());
}

async function verifyCrossReferences(inventory) {
  const [catalog, arcs, interactions] = await Promise.all([
    readFile(path.join(repositoryRoot, "native/blueprint/chapter-catalog.json"), "utf8").then(JSON.parse),
    readFile(path.join(repositoryRoot, "native/blueprint/arc-matrix.json"), "utf8").then(JSON.parse),
    readFile(path.join(repositoryRoot, "native/blueprint/interaction-mapping.json"), "utf8").then(JSON.parse),
  ]);
  const issues = [];
  const inventoryIDs = new Set(inventory.chapters.map((chapter) => chapter.contentID));
  const catalogIDs = new Set(catalog.chapters.map((chapter) => chapter.contentID));
  if (!equalSets(inventoryIDs, catalogIDs)) issues.push("chapter IDs differ between web source and native catalog");

  const sourceMovements = new Set();
  const sourceInteractions = new Set();
  for (const chapter of inventory.chapters) {
    chapter.movementIDs.forEach((movementID) => sourceMovements.add(`${chapter.contentID}/${movementID}`));
    chapter.interactionMovementIDs.forEach((movementID) => sourceInteractions.add(`${chapter.contentID}/${movementID}`));
  }
  const mappedMovements = new Set(arcs.chapters.flatMap((chapter) =>
    chapter.arcs.flatMap((arc) => arc.movementIDs.map((movementID) => `${chapter.contentID}/${movementID}`))));
  const mappedInteractions = new Set(interactions.items.map((item) => item.sourceInteractionID));
  if (!equalSets(sourceMovements, mappedMovements)) issues.push("290-movement coverage differs from the frozen web source");
  if (!equalSets(sourceInteractions, mappedInteractions)) issues.push("122 interaction IDs differ from the frozen web source");
  if (issues.length) throw new Error(issues.join("\n"));
}

async function main() {
  const current = await buildInventory();
  if (process.argv.includes("--print")) {
    process.stdout.write(`${JSON.stringify(current, null, 2)}\n`);
    return;
  }
  const frozen = JSON.parse(await readFile(inventoryPath, "utf8"));
  if (!equalJSON(current, frozen)) {
    throw new Error("Web Journey source drifted from native/blueprint/source-inventory.json");
  }
  if (current.chapterCount !== 24 || current.movementCount !== 290 || current.interactionCount !== 122) {
    throw new Error(
      `Expected 24 chapters / 290 movements / 122 interactions; found ${current.chapterCount} / ${current.movementCount} / ${current.interactionCount}`,
    );
  }
  await verifyCrossReferences(current);
  process.stdout.write(
    `Web source frozen: ${current.chapterCount} chapters, ${current.movementCount} movements, ${current.interactionCount} interactions.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error.message}\n`);
  process.exitCode = 1;
});
