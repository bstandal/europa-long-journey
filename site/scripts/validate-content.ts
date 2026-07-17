import { access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { assetRecords, sources } from "../src/data/sources";
import { scenes } from "../src/data/scenes";

const errors: string[] = [];
const sceneIds = new Set<string>();
const hotspotIds = new Set<string>();
const sourceIds = new Set(sources.map((source) => source.id));
const root = fileURLToPath(new URL("../public", import.meta.url));

for (const [index, scene] of scenes.entries()) {
  if (!scene.id || sceneIds.has(scene.id)) errors.push(`Scene ${index + 1} has a missing or duplicate id.`);
  sceneIds.add(scene.id);

  if (scene.order !== index + 1) {
    errors.push(`Scene "${scene.id}" has order ${scene.order}; expected ${index + 1}.`);
  }
  if (scene.period.end !== undefined && scene.period.start > scene.period.end) {
    errors.push(`Scene "${scene.id}" has an invalid period.`);
  }
  if (!scene.title || !scene.thesis || !scene.body || !scene.landmark) {
    errors.push(`Scene "${scene.id}" is missing required public content.`);
  }
  if (!scene.hotspots.length) {
    errors.push(`Scene "${scene.id}" needs at least one interactive map place.`);
  }
  for (const hotspot of scene.hotspots) {
    const qualifiedId = `${scene.id}:${hotspot.id}`;
    if (!hotspot.id || hotspotIds.has(qualifiedId)) {
      errors.push(`Scene "${scene.id}" has a missing or duplicate hotspot id.`);
    }
    hotspotIds.add(qualifiedId);
    if (!hotspot.label || !hotspot.detail) {
      errors.push(`Hotspot "${qualifiedId}" is missing its public label or detail.`);
    }
    if (
      !Number.isFinite(hotspot.latitude) ||
      !Number.isFinite(hotspot.longitude) ||
      hotspot.latitude < -90 ||
      hotspot.latitude > 90 ||
      hotspot.longitude < -180 ||
      hotspot.longitude > 180
    ) {
      errors.push(`Hotspot "${qualifiedId}" has invalid coordinates.`);
    }
  }
  if (scene.body.split(/\s+/).length < 80 || scene.body.split(/\s+/).length > 145) {
    errors.push(`Scene "${scene.id}" body should contain 80–145 words.`);
  }
  for (const sourceId of scene.sourceIds) {
    if (!sourceIds.has(sourceId)) errors.push(`Scene "${scene.id}" references unknown source "${sourceId}".`);
  }
}

for (const source of sources) {
  if (!source.id || !source.author || !source.title || !source.year) {
    errors.push(`Source "${source.id || "unknown"}" has incomplete metadata.`);
  }
}

for (const asset of assetRecords) {
  if (
    !asset.creator ||
    !asset.institution ||
    !asset.sourceUrl ||
    !asset.license ||
    !asset.requiredCredit ||
    !asset.localPath
  ) {
    errors.push(`Asset "${asset.id}" has incomplete license metadata.`);
  }

  try {
    await access(`${root}${asset.localPath}`);
  } catch {
    errors.push(`Asset "${asset.id}" is missing at ${asset.localPath}.`);
  }
}

if (scenes.length !== 14) errors.push(`Expected 14 scenes; found ${scenes.length}.`);

if (errors.length) {
  console.error(`Content validation failed:\n${errors.map((error) => `- ${error}`).join("\n")}`);
  process.exit(1);
}

const totalWords = scenes.reduce(
  (sum, scene) => sum + `${scene.thesis} ${scene.body}`.split(/\s+/).length,
  0,
);

console.log(
  `Validated ${scenes.length} scenes, ${hotspotIds.size} interactive places, ${sources.length} sources and ${assetRecords.length} assets.`,
);
console.log(`Narrative length: ${totalWords} words.`);
