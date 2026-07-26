export const stableIDPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export const interactionGrammars = new Set([
  "trace",
  "allocate",
  "assemble",
  "pressure",
  "transform",
]);

export const requiredFreeChapterIDs = [
  "first-farmers",
  "europe-holds-the-line",
  "european-world",
];

export const forbiddenPublicKeys = new Set([
  "backstage",
  "bibliography",
  "balance",
  "claimRegister",
  "citations",
  "confidence",
  "confidenceScore",
  "counterarguments",
  "evidence",
  "evidenceIds",
  "findings",
  "historiography",
  "methodology",
  "scholarNotes",
  "sourceIds",
  "sources",
  "verifierFindings",
  "whatSurvived",
]);

// Key spelling is not a firewall. Normalise snake_case, kebab-case and singular
// aliases before checking so `source_ids` cannot bypass a `sourceIds` rule.
export const forbiddenPublicKeyAliases = new Set([
  "backstage",
  "balance",
  "bibliography",
  "claimregister",
  "claimregisters",
  "citation",
  "citations",
  "confidence",
  "confidencescore",
  "counterargument",
  "counterarguments",
  "evidence",
  "evidenceid",
  "evidenceids",
  "finding",
  "findings",
  "historiography",
  "methodology",
  "research",
  "researchdata",
  "researchnote",
  "researchnotes",
  "scholarnote",
  "scholarnotes",
  "source",
  "sourceid",
  "sourceids",
  "sourcelist",
  "sourceregister",
  "sources",
  "verifierfinding",
  "verifierfindings",
  "whatsurvived",
]);

export function normalizePolicyName(value) {
  return String(value).normalize("NFKC").toLowerCase().replace(/[^a-z0-9]/g, "");
}

export function isForbiddenPublicKey(key) {
  const normalized = normalizePolicyName(key);
  return forbiddenPublicKeys.has(key)
    || forbiddenPublicKeyAliases.has(normalized)
    || [
      "bibliograph",
      "citation",
      "claimregister",
      "confidence",
      "counterargument",
      "evidence",
      "historiograph",
      "methodolog",
      "research",
      "scholarnote",
      "source",
      "verifierfinding",
    ].some((prefix) => normalized.startsWith(prefix));
}

export const forbiddenPathSegments = new Set([
  "backstage",
  "claims",
  "evidence",
  "findings",
  "research",
  "sources",
]);

export const allowedPublicTopLevel = new Set([
  "collection.json",
  "app-shell.json",
  "accessibility",
  "assets",
  "audio",
  "chapters",
  "releases",
  "world",
]);

export const allowedPublicExtensions = new Set([
  ".aac",
  ".ahap",
  ".caf",
  ".heic",
  ".heif",
  ".json",
  ".m4a",
  ".metallib",
  ".png",
]);

export const shippingAssetRoles = new Set([
  "scene-layer",
  "scene-mask",
  "narration",
  "score",
  "soundscape",
  "spatial-detail",
]);

export const shippingMetadataPolicies = new Set([
  "STRIPPED_AND_INSPECTED",
]);

// Shipping lineage is deliberately a closed union. A web derivative is bound
// to the frozen web-source inventory; a generated original cannot masquerade
// as one by supplying an arbitrary path or hash.
export const nativeAssetLineageTypes = new Set([
  "WEB_SOURCE_DERIVATIVE",
  "GENERATED_ORIGINAL",
  "PROJECT_AUTHORED_AUDIO",
  "OPEN_LICENSE_AUDIO_SOURCE",
]);

export const audioShippingRoles = new Set([
  "narration",
  "score",
  "soundscape",
  "spatial-detail",
]);

export function authoritativeWebSourceID(sha256) {
  return typeof sha256 === "string" && /^[a-f0-9]{64}$/u.test(sha256)
    ? `web-${sha256.slice(0, 16)}`
    : undefined;
}

export const shippingRoleRules = new Map([
  ["scene-layer", { topLevel: "assets", extensions: new Set([".heic", ".heif", ".png"]) }],
  ["scene-mask", { topLevel: "assets", extensions: new Set([".heic", ".heif", ".png"]) }],
  ["narration", { topLevel: "audio", extensions: new Set([".aac", ".caf", ".m4a"]) }],
  ["score", { topLevel: "audio", extensions: new Set([".aac", ".caf", ".m4a"]) }],
  ["soundscape", { topLevel: "audio", extensions: new Set([".aac", ".caf", ".m4a"]) }],
  ["spatial-detail", { topLevel: "audio", extensions: new Set([".aac", ".caf", ".m4a"]) }],
]);

export const requiredCapabilityByShippingRole = new Map([
  ["scene-layer", "native-image-layer-production"],
  ["scene-mask", "native-image-layer-production"],
  ["narration", "final-narration-synthesis"],
  ["score", "authored-score-rendering"],
  ["soundscape", "soundscape-generation"],
  ["spatial-detail", "soundscape-generation"],
]);

export const editorialLeakagePatterns = [
  /\bscholars debate\b/i,
  /\bhistorians disagree\b/i,
  /\bthe picture is complex\b/i,
  /\bthis account is contested\b/i,
  /\bfrom another perspective\b/i,
  /\bit is important to note\b/i,
  /\bthere are competing interpretations\b/i,
  /\bthe historiography\b/i,
  /\bmethodological(?:ly)?\b/i,
];
