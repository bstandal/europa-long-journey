import { readFile, readdir, stat } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import {
  allowedPublicExtensions,
  allowedPublicTopLevel,
  audioShippingRoles,
  authoritativeWebSourceID,
  editorialLeakagePatterns,
  forbiddenPathSegments,
  interactionGrammars,
  isForbiddenPublicKey,
  nativeAssetLineageTypes,
  normalizePolicyName,
  shippingRoleRules,
  requiredFreeChapterIDs,
  stableIDPattern,
} from "./policy.mjs";
import { validateWorldReplay } from "./world-replay.mjs";

export class ValidationError extends Error {
  constructor(issues) {
    super(issues.join("\n"));
    this.name = "ValidationError";
    this.issues = issues;
  }
}

const checkpointPolicies = new Set(["onEntry", "afterInteraction", "onExit", "continuous"]);
const worldNodeKinds = new Set(["settlement", "city", "frontier", "institution", "landscape", "object"]);
const worldTraceKinds = new Set(["road", "seaRoute", "riverRoute", "frontier", "jurisdiction", "exchange", "transmission"]);
const worldMutations = new Set(["reveal-node", "establish-trace", "transform-node", "set-node-attribute", "supersede-trace"]);
const sceneBlendModes = new Set(["normal", "multiply", "screen", "additive"]);
const atmosphereKinds = new Set(["dust", "embers", "mist", "rain", "snow", "smoke"]);
const audioRoles = new Set(["narration", "score", "soundscape", "spatialDetail", "silence"]);
const responsiveAudioPhases = new Set(["waiting", "engaged", "resistance"]);
const responsiveAudioExitPolicyKinds = new Set(["bounded-fade"]);
const hapticKinds = new Set(["contact", "drag", "resistance", "transfer", "break", "seal"]);
const accessibilityRoles = new Set(["image", "heading", "narration", "mechanism", "action", "adjustable", "status"]);
const accessibilityActionKinds = new Set(["activate", "increment", "decrement"]);
const accessibilityTokenCommands = new Set([
  "trace-next",
  "allocate",
  "commit-allocation",
  "place-component",
  "adjust-pressure",
  "hold-pressure",
  "advance-transform",
]);
const packageIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const canonicalBCP47Pattern = /^(?:[a-z]{2,3}(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*(?:-[0-9a-wy-z](?:-[a-z0-9]{2,8})+)*(?:-x(?:-[a-z0-9]{1,8})+)?|x(?:-[a-z0-9]{1,8})+)$/u;
const sha256Pattern = /^[a-f0-9]{64}$/u;
const maximumDeterministicAudioRampSamples = 4_294_967_295;
const maximumResponsiveAudioLoopSamples = 4_294_967_295;
const msBasicSource = Object.freeze({
  sourceID: "musescore-ms-basic-0-2-0",
  sourceURL: "https://raw.githubusercontent.com/musescore/MuseScore/03c4afd5c9ae72b2698f6716e9e244ce53550495/share/sound/MS%20Basic.sf3",
  title: "MS Basic 0.2.0",
  creator: "MuseScore contributors; FluidR3 and credited sample contributors",
  bytes: 51_278_610,
  sha256: "5ea2375e8bd7d8e71def1036978c1621e85b66934169b6a2744b27b9b3c2d99c",
  licenseSPDX: "MIT",
  licenseURL: "https://raw.githubusercontent.com/musescore/MuseScore/03c4afd5c9ae72b2698f6716e9e244ce53550495/share/sound/MS%20Basic_License.md",
  noticePath: "native/audio/score-soundscape/licenses/MS-Basic-0.2.0-LICENSE.md",
  noticeBytes: 3_320,
  noticeSHA256: "bf7db123b5d6c0beb1a37f6e1b11c6f4dfd8fb6abd5d59ff282ea24a5cd932e5",
});

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function inspectPublicValue(value, location, issues) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => inspectPublicValue(item, `${location}[${index}]`, issues));
    return;
  }
  if (isRecord(value)) {
    for (const [key, child] of Object.entries(value)) {
      // These exact keys use `source` as spatial interaction vocabulary, not
      // research provenance. Keep the firewall intact for every other key.
      if (!["sourceRect", "sourceInteractionTargetID"].includes(key)
          && isForbiddenPublicKey(key)) {
        issues.push(`${location}.${key}: forbidden backstage/research field`);
      }
      inspectPublicValue(child, `${location}.${key}`, issues);
    }
    return;
  }
  if (typeof value !== "string") return;
  for (const pattern of editorialLeakagePatterns) {
    const match = value.match(pattern);
    if (match) issues.push(`${location}: editorial regression '${match[0]}'`);
  }
}

function shape(value, location, required, optional, issues) {
  if (!isRecord(value)) {
    issues.push(`${location}: object required`);
    return null;
  }
  const allowed = new Set([...required, ...optional]);
  for (const key of required) {
    if (!Object.hasOwn(value, key)) issues.push(`${location}.${key}: required`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) issues.push(`${location}.${key}: unknown public field`);
  }
  return value;
}

function authoredString(value, location, issues) {
  if (typeof value !== "string" || !value.trim()) {
    issues.push(`${location}: non-empty string required`);
    return false;
  }
  return true;
}

function validateLocalizedString(value, location, issues) {
  const record = shape(value, location, ["id", "launchEnglish"], [], issues);
  if (!record) return null;
  stableID(record.id, `${location}.id`, issues);
  authoredString(record.launchEnglish, `${location}.launchEnglish`, issues);
  return record;
}

function validateLocaleDescriptor(value, location, issues) {
  const record = shape(value, location, ["identifier"], ["fallbackIdentifier"], issues);
  if (!record) return null;
  if (typeof record.identifier !== "string" || !canonicalBCP47Pattern.test(record.identifier)) {
    issues.push(`${location}.identifier: canonical BCP-47 language tag required`);
  }
  if (Object.hasOwn(record, "fallbackIdentifier")) {
    if (typeof record.fallbackIdentifier !== "string"
        || !canonicalBCP47Pattern.test(record.fallbackIdentifier)
        || record.fallbackIdentifier === record.identifier) {
      issues.push(`${location}.fallbackIdentifier: different canonical BCP-47 language tag required`);
    }
  }
  return record;
}

function requireConsistentLocalizedStrings(value, location, issues) {
  const byID = new Map();
  function visit(current) {
    if (Array.isArray(current)) {
      current.forEach(visit);
      return;
    }
    if (!isRecord(current)) return;
    if (Object.hasOwn(current, "launchEnglish") && Object.hasOwn(current, "id")) {
      const previous = byID.get(current.id);
      if (previous !== undefined && previous !== current.launchEnglish) {
        issues.push(`${location}: localized string ID '${current.id}' has conflicting English launch values`);
      }
      byID.set(current.id, current.launchEnglish);
    }
    Object.values(current).forEach(visit);
  }
  visit(value);
}

function stableID(value, location, issues) {
  if (typeof value !== "string" || !stableIDPattern.test(value)) {
    issues.push(`${location}: stable kebab-case ID required`);
    return false;
  }
  return true;
}

function packageIdentifier(value, location, issues) {
  if (typeof value !== "string" || !packageIDPattern.test(value)) {
    issues.push(`${location}: package ID must start with a lowercase letter and use stable kebab case`);
    return false;
  }
  return true;
}

function finiteNumber(value, location, issues) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    issues.push(`${location}: finite number required`);
    return false;
  }
  return true;
}

function integer(value, location, issues, minimum = Number.MIN_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum) {
    issues.push(`${location}: integer${minimum > Number.MIN_SAFE_INTEGER ? ` >= ${minimum}` : ""} required`);
    return false;
  }
  return true;
}

function boolean(value, location, issues) {
  if (typeof value !== "boolean") {
    issues.push(`${location}: boolean required`);
    return false;
  }
  return true;
}

function enumValue(value, allowed, location, issues) {
  if (typeof value !== "string" || !allowed.has(value)) {
    issues.push(`${location}: expected one of ${[...allowed].join(", ")}`);
    return false;
  }
  return true;
}

function arrayValue(value, location, issues, minimum = 0) {
  if (!Array.isArray(value)) {
    issues.push(`${location}: array required`);
    return [];
  }
  if (value.length < minimum) issues.push(`${location}: at least ${minimum} item${minimum === 1 ? "" : "s"} required`);
  return value;
}

function requireUnique(values, location, issues) {
  const seen = new Set();
  for (const value of values) {
    if (seen.has(value)) issues.push(`${location}: duplicate identifier '${value}'`);
    seen.add(value);
  }
}

function validateSchemaVersion(value, location, issues) {
  const record = shape(value, location, ["major", "minor", "patch"], [], issues);
  if (!record) return;
  integer(record.major, `${location}.major`, issues, 0);
  integer(record.minor, `${location}.minor`, issues, 0);
  integer(record.patch, `${location}.patch`, issues, 0);
}

function validatePoint(value, location, issues, unitSpace = true) {
  const record = shape(value, location, ["x", "y"], [], issues);
  if (!record) return;
  const xValid = finiteNumber(record.x, `${location}.x`, issues);
  const yValid = finiteNumber(record.y, `${location}.y`, issues);
  if (unitSpace && xValid && (record.x < 0 || record.x > 1)) issues.push(`${location}.x: must be in unit space`);
  if (unitSpace && yValid && (record.y < 0 || record.y > 1)) issues.push(`${location}.y: must be in unit space`);
}

function validateNamedValue(value, location, issues) {
  const record = shape(value, location, ["key", "value"], [], issues);
  if (!record) return;
  authoredString(record.key, `${location}.key`, issues);
  if (!["boolean", "number", "string"].includes(typeof record.value) || (typeof record.value === "number" && !Number.isFinite(record.value))) {
    issues.push(`${location}.value: scalar boolean, finite number or string required`);
  }
}

function validateWorldNode(value, location, issues) {
  const record = shape(value, location, ["id", "kind", "form", "position", "attributes"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  enumValue(record.kind, worldNodeKinds, `${location}.kind`, issues);
  authoredString(record.form, `${location}.form`, issues);
  validatePoint(record.position, `${location}.position`, issues);
  const attributes = arrayValue(record.attributes, `${location}.attributes`, issues);
  attributes.forEach((item, index) => validateNamedValue(item, `${location}.attributes[${index}]`, issues));
  requireUnique(attributes.filter(isRecord).map((item) => item.key), `${location}.attributes.key`, issues);
}

function validateWorldTrace(value, location, issues) {
  const record = shape(value, location, ["id", "kind", "origin", "destination", "strength"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  enumValue(record.kind, worldTraceKinds, `${location}.kind`, issues);
  stableID(record.origin, `${location}.origin`, issues);
  stableID(record.destination, `${location}.destination`, issues);
  if (finiteNumber(record.strength, `${location}.strength`, issues) && record.strength <= 0) {
    issues.push(`${location}.strength: must be positive`);
  }
}

function validateWorldSeed(value, location, issues) {
  const record = shape(value, location, ["nodes", "traces"], [], issues);
  if (!record) return;
  const nodes = arrayValue(record.nodes, `${location}.nodes`, issues);
  const traces = arrayValue(record.traces, `${location}.traces`, issues);
  nodes.forEach((node, index) => validateWorldNode(node, `${location}.nodes[${index}]`, issues));
  traces.forEach((trace, index) => validateWorldTrace(trace, `${location}.traces[${index}]`, issues));
  const nodeIDs = nodes.filter(isRecord).map((node) => node.id);
  requireUnique(nodeIDs, `${location}.nodes.id`, issues);
  requireUnique(traces.filter(isRecord).map((trace) => trace.id), `${location}.traces.id`, issues);
  const knownNodes = new Set(nodeIDs);
  for (const [index, trace] of traces.entries()) {
    if (!isRecord(trace)) continue;
    if (!knownNodes.has(trace.origin)) {
      issues.push(`${location}.traces[${index}].origin: missing seeded node '${trace.origin}'`);
    }
    if (!knownNodes.has(trace.destination)) {
      issues.push(`${location}.traces[${index}].destination: missing seeded node '${trace.destination}'`);
    }
  }
}

/**
 * Validates a standalone world seed with the exact same wire contract used
 * inside ContentPackagePayload. Backstage authorities call this rather than
 * maintaining a weaker parallel interpretation of canonical world nodes.
 */
export function validateWorldSeedDocument(value, location = "worldSeed") {
  const issues = [];
  validateWorldSeed(value, location, issues);
  if (issues.length) throw new ValidationError(issues);
  return value;
}

function validateWorldEffect(value, location, issues) {
  if (!isRecord(value)) {
    issues.push(`${location}: object required`);
    return;
  }
  const mutation = value.mutation;
  enumValue(mutation, worldMutations, `${location}.mutation`, issues);
  if (mutation === "reveal-node") {
    const record = shape(value, location, ["id", "mutation", "node"], [], issues);
    if (record) validateWorldNode(record.node, `${location}.node`, issues);
  } else if (mutation === "establish-trace") {
    const record = shape(value, location, ["id", "mutation", "trace"], [], issues);
    if (record) validateWorldTrace(record.trace, `${location}.trace`, issues);
  } else if (mutation === "transform-node") {
    const record = shape(value, location, ["id", "mutation", "nodeID", "form", "attributes"], [], issues);
    if (record) {
      stableID(record.nodeID, `${location}.nodeID`, issues);
      authoredString(record.form, `${location}.form`, issues);
      const attributes = arrayValue(record.attributes, `${location}.attributes`, issues);
      attributes.forEach((item, index) => validateNamedValue(item, `${location}.attributes[${index}]`, issues));
      requireUnique(attributes.filter(isRecord).map((item) => item.key), `${location}.attributes.key`, issues);
    }
  } else if (mutation === "set-node-attribute") {
    const record = shape(value, location, ["id", "mutation", "nodeID", "value"], [], issues);
    if (record) {
      stableID(record.nodeID, `${location}.nodeID`, issues);
      validateNamedValue(record.value, `${location}.value`, issues);
    }
  } else if (mutation === "supersede-trace") {
    const record = shape(value, location, ["id", "mutation", "traceID"], [], issues);
    if (record) stableID(record.traceID, `${location}.traceID`, issues);
  } else {
    shape(value, location, ["id", "mutation"], [], issues);
  }
  stableID(value.id, `${location}.id`, issues);
}

function validateNarrative(value, location, issues) {
  const record = shape(value, location, ["heading", "paragraphs"], ["eyebrow", "actionPrompt"], issues);
  if (!record) return;
  if (Object.hasOwn(record, "eyebrow")) validateLocalizedString(record.eyebrow, `${location}.eyebrow`, issues);
  validateLocalizedString(record.heading, `${location}.heading`, issues);
  const paragraphs = arrayValue(record.paragraphs, `${location}.paragraphs`, issues, 1);
  paragraphs.forEach((paragraph, index) => validateLocalizedString(paragraph, `${location}.paragraphs[${index}]`, issues));
  if (Object.hasOwn(record, "actionPrompt")) validateLocalizedString(record.actionPrompt, `${location}.actionPrompt`, issues);
}

function validateTraceConfiguration(value, location, issues) {
  const record = shape(value, location, ["anchors", "tolerance"], ["anchorIDs"], issues);
  if (!record) return;
  const anchors = arrayValue(record.anchors, `${location}.anchors`, issues, 2);
  if (anchors.length > 64) issues.push(`${location}.anchors: at most 64 items allowed`);
  anchors.forEach((point, index) => validatePoint(point, `${location}.anchors[${index}]`, issues));
  if (Object.hasOwn(record, "anchorIDs")) {
    const anchorIDs = arrayValue(record.anchorIDs, `${location}.anchorIDs`, issues, 2);
    if (anchorIDs.length > 64) issues.push(`${location}.anchorIDs: at most 64 items allowed`);
    anchorIDs.forEach((id, index) => stableID(id, `${location}.anchorIDs[${index}]`, issues));
    requireUnique(anchorIDs, `${location}.anchorIDs`, issues);
    if (anchorIDs.length !== anchors.length) {
      issues.push(`${location}.anchorIDs: must identify every Trace anchor in authored order`);
    }
  }
  if (finiteNumber(record.tolerance, `${location}.tolerance`, issues)
      && (record.tolerance <= 0 || record.tolerance > 1)) {
    issues.push(`${location}.tolerance: must be greater than 0 and at most 1`);
  }
}

function validateAllocateConfiguration(value, location, issues) {
  const record = shape(value, location, ["resourceName", "totalUnits", "destinations"], [], issues);
  if (!record) return;
  validateLocalizedString(record.resourceName, `${location}.resourceName`, issues);
  integer(record.totalUnits, `${location}.totalUnits`, issues, 1);
  const destinations = arrayValue(record.destinations, `${location}.destinations`, issues, 2);
  for (const [index, destination] of destinations.entries()) {
    const item = shape(destination, `${location}.destinations[${index}]`, ["id", "minimumUnits"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.destinations[${index}].id`, issues);
    integer(item.minimumUnits, `${location}.destinations[${index}].minimumUnits`, issues, 1);
  }
  requireUnique(destinations.filter(isRecord).map((item) => item.id), `${location}.destinations.id`, issues);
  if (Number.isSafeInteger(record.totalUnits)
      && destinations.every((item) => isRecord(item) && Number.isSafeInteger(item.minimumUnits))
      && destinations.reduce((sum, item) => sum + item.minimumUnits, 0) >= record.totalUnits) {
    issues.push(`${location}.destinations: positive minimums must leave authored surplus for a real allocation choice`);
  }
}

function assemblyContainsCycle(components) {
  const prerequisites = new Map(components.map((component) => [component.id, component.prerequisites]));
  const visiting = new Set();
  const visited = new Set();
  function visit(id) {
    if (visiting.has(id)) return true;
    if (visited.has(id)) return false;
    visiting.add(id);
    for (const prerequisite of prerequisites.get(id) ?? []) {
      if (visit(prerequisite)) return true;
    }
    visiting.delete(id);
    visited.add(id);
    return false;
  }
  return components.some((component) => visit(component.id));
}

function validateAssembleConfiguration(value, location, issues) {
  const record = shape(value, location, ["components"], [], issues);
  if (!record) return;
  const components = arrayValue(record.components, `${location}.components`, issues, 1);
  for (const [index, component] of components.entries()) {
    const item = shape(component, `${location}.components[${index}]`, ["id", "targetSlot", "prerequisites"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.components[${index}].id`, issues);
    stableID(item.targetSlot, `${location}.components[${index}].targetSlot`, issues);
    const prerequisites = arrayValue(item.prerequisites, `${location}.components[${index}].prerequisites`, issues);
    prerequisites.forEach((id, prerequisiteIndex) => stableID(id, `${location}.components[${index}].prerequisites[${prerequisiteIndex}]`, issues));
    requireUnique(prerequisites, `${location}.components[${index}].prerequisites`, issues);
  }
  const validComponents = components.filter((item) => isRecord(item) && typeof item.id === "string" && Array.isArray(item.prerequisites));
  const ids = validComponents.map((item) => item.id);
  const known = new Set(ids);
  requireUnique(ids, `${location}.components.id`, issues);
  for (const component of validComponents) {
    for (const prerequisite of component.prerequisites) {
      if (prerequisite === component.id || !known.has(prerequisite)) {
        issues.push(`${location}.components.${component.id}: unknown or self prerequisite '${prerequisite}'`);
      }
    }
  }
  if (assemblyContainsCycle(validComponents)) issues.push(`${location}.components: prerequisites must be acyclic`);
}

function validatePressureConfiguration(value, location, issues) {
  const record = shape(value, location, ["forces", "stableRange", "requiredHoldMillis"], [], issues);
  if (!record) return;
  const forces = arrayValue(record.forces, `${location}.forces`, issues, 1);
  for (const [index, force] of forces.entries()) {
    const item = shape(force, `${location}.forces[${index}]`, ["id", "direction", "initialMagnitude", "userControllable"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.forces[${index}].id`, issues);
    if (finiteNumber(item.direction, `${location}.forces[${index}].direction`, issues) && item.direction === 0) {
      issues.push(`${location}.forces[${index}].direction: must be non-zero`);
    }
    if (finiteNumber(item.initialMagnitude, `${location}.forces[${index}].initialMagnitude`, issues)
        && (item.initialMagnitude < 0 || item.initialMagnitude > 1)) {
      issues.push(`${location}.forces[${index}].initialMagnitude: must be in unit space`);
    }
    boolean(item.userControllable, `${location}.forces[${index}].userControllable`, issues);
  }
  requireUnique(forces.filter(isRecord).map((item) => item.id), `${location}.forces.id`, issues);
  const range = arrayValue(record.stableRange, `${location}.stableRange`, issues, 2);
  if (range.length !== 2) issues.push(`${location}.stableRange: Swift ClosedRange wire value requires exactly [lowerBound, upperBound]`);
  const lowerValid = finiteNumber(range[0], `${location}.stableRange[0]`, issues);
  const upperValid = finiteNumber(range[1], `${location}.stableRange[1]`, issues);
  if (lowerValid && upperValid && range[0] > range[1]) {
      issues.push(`${location}.stableRange: lowerBound must not exceed upperBound`);
  }
  if (integer(record.requiredHoldMillis, `${location}.requiredHoldMillis`, issues, 100)
      && record.requiredHoldMillis > 15_000) {
    issues.push(`${location}.requiredHoldMillis: must be at most 15000`);
  }
  const typedForces = forces.filter((item) => isRecord(item)
    && Number.isFinite(item.direction) && Number.isFinite(item.initialMagnitude)
    && typeof item.userControllable === "boolean");
  if (!typedForces.some((item) => item.userControllable)) issues.push(`${location}.forces: a user-controllable force is required`);
  if (Number.isFinite(range[0]) && Number.isFinite(range[1])) {
    const reachable = typedForces.reduce((bounds, force) => {
      if (force.userControllable) {
        bounds.minimum += Math.min(0, force.direction);
        bounds.maximum += Math.max(0, force.direction);
      } else {
        const contribution = force.direction * force.initialMagnitude;
        bounds.minimum += contribution;
        bounds.maximum += contribution;
      }
      return bounds;
    }, { minimum: 0, maximum: 0 });
    if (range[1] < reachable.minimum || range[0] > reachable.maximum) {
      issues.push(`${location}.stableRange: authored range is unreachable`);
    }
  }
}

function validateTransformConfiguration(value, location, issues) {
  const record = shape(value, location, ["stages"], [], issues);
  if (!record) return;
  const stages = arrayValue(record.stages, `${location}.stages`, issues, 1);
  for (const [index, stage] of stages.entries()) {
    const item = shape(stage, `${location}.stages[${index}]`, ["id", "controlID", "requiredAmount"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.stages[${index}].id`, issues);
    stableID(item.controlID, `${location}.stages[${index}].controlID`, issues);
    if (finiteNumber(item.requiredAmount, `${location}.stages[${index}].requiredAmount`, issues)
        && (item.requiredAmount <= 0 || item.requiredAmount > 1)) {
      issues.push(`${location}.stages[${index}].requiredAmount: must be greater than 0 and at most 1`);
    }
  }
  requireUnique(stages.filter(isRecord).map((item) => item.id), `${location}.stages.id`, issues);
}

function validateInteraction(value, location, issues) {
  const record = shape(value, location, ["id", "prompt", "grammar", "configuration", "completionEffects", "accessibilityID"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  validateLocalizedString(record.prompt, `${location}.prompt`, issues);
  enumValue(record.grammar, interactionGrammars, `${location}.grammar`, issues);
  if (record.grammar === "trace") validateTraceConfiguration(record.configuration, `${location}.configuration`, issues);
  if (record.grammar === "allocate") validateAllocateConfiguration(record.configuration, `${location}.configuration`, issues);
  if (record.grammar === "assemble") validateAssembleConfiguration(record.configuration, `${location}.configuration`, issues);
  if (record.grammar === "pressure") validatePressureConfiguration(record.configuration, `${location}.configuration`, issues);
  if (record.grammar === "transform") validateTransformConfiguration(record.configuration, `${location}.configuration`, issues);
  const effects = arrayValue(record.completionEffects, `${location}.completionEffects`, issues, 1);
  effects.forEach((effect, index) => validateWorldEffect(effect, `${location}.completionEffects[${index}]`, issues));
  requireUnique(effects.filter(isRecord).map((effect) => effect.id), `${location}.completionEffects.id`, issues);
  stableID(record.accessibilityID, `${location}.accessibilityID`, issues);
}

function validateBeat(value, location, issues) {
  const record = shape(value, location, ["id", "sceneID", "narrative", "narrationCueIDs", "completionEffects", "checkpoint"], ["interaction"], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  stableID(record.sceneID, `${location}.sceneID`, issues);
  validateNarrative(record.narrative, `${location}.narrative`, issues);
  const narrationCueIDs = arrayValue(record.narrationCueIDs, `${location}.narrationCueIDs`, issues);
  narrationCueIDs.forEach((cueID, index) => stableID(cueID, `${location}.narrationCueIDs[${index}]`, issues));
  requireUnique(narrationCueIDs, `${location}.narrationCueIDs`, issues);
  if (Object.hasOwn(record, "interaction")) validateInteraction(record.interaction, `${location}.interaction`, issues);
  const effects = arrayValue(record.completionEffects, `${location}.completionEffects`, issues);
  effects.forEach((effect, index) => validateWorldEffect(effect, `${location}.completionEffects[${index}]`, issues));
  requireUnique(effects.filter(isRecord).map((effect) => effect.id), `${location}.completionEffects.id`, issues);
  if (Object.hasOwn(record, "interaction") && effects.length) {
    issues.push(`${location}.completionEffects: interactive beats keep effects on the interaction`);
  }
  enumValue(record.checkpoint, checkpointPolicies, `${location}.checkpoint`, issues);
}

function validateArc(value, location, issues) {
  const record = shape(value, location,
    ["id", "title", "targetDurationMinutes", "situation", "mechanism", "turn", "consequence", "handoff", "beats"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  for (const key of ["title", "situation", "mechanism", "turn", "consequence", "handoff"]) {
    validateLocalizedString(record[key], `${location}.${key}`, issues);
  }
  if (integer(record.targetDurationMinutes, `${location}.targetDurationMinutes`, issues, 8)
      && record.targetDurationMinutes > 15) {
    issues.push(`${location}.targetDurationMinutes: must be at most 15`);
  }
  const beats = arrayValue(record.beats, `${location}.beats`, issues, 1);
  beats.forEach((beat, index) => validateBeat(beat, `${location}.beats[${index}]`, issues));
  requireUnique(beats.filter(isRecord).map((beat) => beat.id), `${location}.beats.id`, issues);
}

function validateChapter(value, location, issues) {
  const record = shape(value, location, ["schemaVersion", "id", "title", "period", "arcs", "completionEffects"], [], issues);
  if (!record) return;
  validateSchemaVersion(record.schemaVersion, `${location}.schemaVersion`, issues);
  stableID(record.id, `${location}.id`, issues);
  validateLocalizedString(record.title, `${location}.title`, issues);
  validateLocalizedString(record.period, `${location}.period`, issues);
  const arcs = arrayValue(record.arcs, `${location}.arcs`, issues, 1);
  if (arcs.length > 3) issues.push(`${location}.arcs: at most 3 arcs allowed`);
  arcs.forEach((arc, index) => validateArc(arc, `${location}.arcs[${index}]`, issues));
  requireUnique(arcs.filter(isRecord).map((arc) => arc.id), `${location}.arcs.id`, issues);
  const effects = arrayValue(record.completionEffects, `${location}.completionEffects`, issues);
  effects.forEach((effect, index) => validateWorldEffect(effect, `${location}.completionEffects[${index}]`, issues));
  requireUnique(effects.filter(isRecord).map((effect) => effect.id), `${location}.completionEffects.id`, issues);
  const hasPersistentEffect = effects.length > 0 || arcs.some((arc) =>
    Array.isArray(arc?.beats) && arc.beats.some((beat) =>
      (Array.isArray(beat?.completionEffects) && beat.completionEffects.length > 0)
        || (Array.isArray(beat?.interaction?.completionEffects)
          && beat.interaction.completionEffects.length > 0)));
  if (!hasPersistentEffect) {
    issues.push(`${location}: a completed chapter must leave at least one permanent world effect`);
  }
}

function validateSafeAssetPath(value, location, issues) {
  if (!authoredString(value, location, issues)) return false;
  const parts = value.split("/");
  const containsControlCharacter = [...value].some((character) => {
    const codePoint = character.codePointAt(0);
    return codePoint <= 0x1f || codePoint === 0x7f;
  });
  if (value.startsWith("/") || value.includes("://") || value.includes("\\")
      || containsControlCharacter || parts.includes("..") || parts.includes(".")
      || parts.some((part) => !part)) {
    issues.push(`${location}: package-relative asset path required`);
    return false;
  }
  return true;
}

function validateNormalizedRect(value, location, issues) {
  const record = shape(value, location, ["x", "y", "width", "height"], [], issues);
  if (!record) return null;
  const valid = ["x", "y", "width", "height"]
    .every((key) => finiteNumber(record[key], `${location}.${key}`, issues));
  if (!valid) return record;
  if (record.x < 0 || record.y < 0 || record.width <= 0 || record.height <= 0
      || record.x + record.width > 1 || record.y + record.height > 1) {
    issues.push(`${location}: positive normalized rect inside unit space required`);
  }
  return record;
}

function validateScenePixelSize(value, location, issues) {
  const record = shape(value, location, ["width", "height"], [], issues);
  if (!record) return null;
  const widthValid = integer(record.width, `${location}.width`, issues, 1);
  const heightValid = integer(record.height, `${location}.height`, issues, 1);
  if (widthValid && heightValid && record.height <= record.width) {
    issues.push(`${location}: portrait dimensions required`);
  }
  return record;
}

function validateSceneViewportSize(value, location, issues) {
  const record = shape(value, location, ["widthPoints", "heightPoints"], [], issues);
  if (!record) return null;
  const widthValid = integer(record.widthPoints, `${location}.widthPoints`, issues, 1);
  const heightValid = integer(record.heightPoints, `${location}.heightPoints`, issues, 1);
  if (widthValid && heightValid && record.heightPoints <= record.widthPoints) {
    issues.push(`${location}: portrait dimensions required`);
  }
  return record;
}

function validateSceneViewportCrop(value, location, canvas, issues) {
  const record = shape(value, location, ["id", "viewport", "sourceRect", "safeTextRegions"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  const viewport = validateSceneViewportSize(record.viewport, `${location}.viewport`, issues);
  const sourceRect = validateNormalizedRect(record.sourceRect, `${location}.sourceRect`, issues);
  const safeRegions = arrayValue(record.safeTextRegions, `${location}.safeTextRegions`, issues, 1);
  for (const [index, region] of safeRegions.entries()) {
    const item = shape(region, `${location}.safeTextRegions[${index}]`, ["id", "rect"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.safeTextRegions[${index}].id`, issues);
    validateNormalizedRect(item.rect, `${location}.safeTextRegions[${index}].rect`, issues);
  }
  requireUnique(safeRegions.filter(isRecord).map((item) => item.id), `${location}.safeTextRegions.id`, issues);
  if (canvas && viewport && sourceRect
      && [canvas.width, canvas.height, viewport.widthPoints, viewport.heightPoints,
        sourceRect.width, sourceRect.height].every(Number.isFinite)
      && canvas.width > 0 && canvas.height > 0 && viewport.widthPoints > 0
      && viewport.heightPoints > 0 && sourceRect.width > 0 && sourceRect.height > 0) {
    const sourceAspect = canvas.width * sourceRect.width / (canvas.height * sourceRect.height);
    const viewportAspect = viewport.widthPoints / viewport.heightPoints;
    if (Math.abs(sourceAspect / viewportAspect - 1) > 0.01) {
      issues.push(`${location}.sourceRect: must match the authored viewport aspect within one percent`);
    }
  }
}

function validateViewportCropSet(value, location, canvas, issues) {
  const crops = arrayValue(value, location, issues, 1);
  crops.forEach((crop, index) => validateSceneViewportCrop(crop, `${location}[${index}]`, canvas, issues));
  requireUnique(crops.filter(isRecord).map((crop) => crop.id), `${location}.id`, issues);
  const baseline = crops.find((crop) => isRecord(crop) && crop.id === "baseline-393x852");
  if (!baseline || baseline.viewport?.widthPoints !== 393 || baseline.viewport?.heightPoints !== 852) {
    issues.push(`${location}: baseline-393x852 must author the 393 by 852 viewport`);
  }
  return crops;
}

function validateSceneCanvas(value, location, issues) {
  const record = shape(value, location,
    ["canvas", "cameraTravelBounds", "authoredOverscanFraction", "viewportCrops"], [], issues);
  if (!record) return null;
  const canvas = validateScenePixelSize(record.canvas, `${location}.canvas`, issues);
  const travel = validateNormalizedRect(record.cameraTravelBounds, `${location}.cameraTravelBounds`, issues);
  const overscanValid = finiteNumber(record.authoredOverscanFraction, `${location}.authoredOverscanFraction`, issues);
  if (overscanValid && (record.authoredOverscanFraction < 0.15 || record.authoredOverscanFraction > 0.5)) {
    issues.push(`${location}.authoredOverscanFraction: must be between 0.15 and 0.5`);
  }
  if (travel && overscanValid && [travel.x, travel.y, travel.width, travel.height].every(Number.isFinite)) {
    const horizontalMargin = travel.width * record.authoredOverscanFraction;
    const verticalMargin = travel.height * record.authoredOverscanFraction;
    if (travel.x < horizontalMargin || 1 - travel.x - travel.width < horizontalMargin
        || travel.y < verticalMargin || 1 - travel.y - travel.height < verticalMargin) {
      issues.push(`${location}.cameraTravelBounds: master canvas must preserve authored overscan around camera travel`);
    }
  }
  validateViewportCropSet(record.viewportCrops, `${location}.viewportCrops`, canvas, issues);
  return record;
}

const sceneMaskAssetFields = [
  "alphaMaskAssetPath",
  "occlusionMaskAssetPath",
  "depthMaskAssetPath",
  "lightMaskAssetPath",
];

function validateSceneMaskSet(value, location, issues) {
  const record = shape(value, location, [], sceneMaskAssetFields, issues);
  if (!record) return;
  for (const key of sceneMaskAssetFields) {
    if (Object.hasOwn(record, key)) validateSafeAssetPath(record[key], `${location}.${key}`, issues);
  }
}

function validateSceneLayer(value, location, expectedOrder, issues) {
  const record = shape(value, location,
    ["id", "order", "assetPath", "frame", "depth", "opacity", "blendMode", "masks", "motion", "stateVariants"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  if (integer(record.order, `${location}.order`, issues, 0) && record.order !== expectedOrder) {
    issues.push(`${location}.order: must equal authored array order ${expectedOrder}`);
  }
  validateSafeAssetPath(record.assetPath, `${location}.assetPath`, issues);
  validateNormalizedRect(record.frame, `${location}.frame`, issues);
  for (const key of ["depth", "opacity"]) {
    if (finiteNumber(record[key], `${location}.${key}`, issues) && (record[key] < 0 || record[key] > 1)) {
      issues.push(`${location}.${key}: must be in unit space`);
    }
  }
  enumValue(record.blendMode, sceneBlendModes, `${location}.blendMode`, issues);
  validateSceneMaskSet(record.masks, `${location}.masks`, issues);
  const motion = shape(record.motion, `${location}.motion`, ["parallaxFactor", "windResponse", "focusResponse"], [], issues);
  if (motion) {
    for (const key of ["parallaxFactor", "windResponse", "focusResponse"]) {
      if (!finiteNumber(motion[key], `${location}.motion.${key}`, issues)) continue;
      const minimum = key === "parallaxFactor" ? -1 : 0;
      if (motion[key] < minimum || motion[key] > 1) {
        issues.push(`${location}.motion.${key}: must be between ${minimum} and 1`);
      }
    }
  }
  const variants = arrayValue(record.stateVariants, `${location}.stateVariants`, issues);
  for (const [index, variant] of variants.entries()) {
    const item = shape(variant, `${location}.stateVariants[${index}]`, ["id", "assetPath", "masks"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.stateVariants[${index}].id`, issues);
    validateSafeAssetPath(item.assetPath, `${location}.stateVariants[${index}].assetPath`, issues);
    validateSceneMaskSet(item.masks, `${location}.stateVariants[${index}].masks`, issues);
  }
  requireUnique(variants.filter(isRecord).map((variant) => variant.id), `${location}.stateVariants.id`, issues);
}

function validateSignedUnitVector(value, location, issues) {
  const record = shape(value, location, ["dx", "dy"], [], issues);
  if (!record) return;
  const dxValid = finiteNumber(record.dx, `${location}.dx`, issues);
  const dyValid = finiteNumber(record.dy, `${location}.dy`, issues);
  if (!dxValid || !dyValid) return;
  if (record.dx < -1 || record.dx > 1 || record.dy < -1 || record.dy > 1
      || record.dx * record.dx + record.dy * record.dy > 1) {
    issues.push(`${location}: signed unit vector required`);
  }
}

function validateSceneHitRegion(value, location, issues) {
  const record = shape(value, location, ["path"], [], issues);
  if (!record) return;
  const points = arrayValue(record.path, `${location}.path`, issues, 3);
  points.forEach((point, index) => validatePoint(point, `${location}.path[${index}]`, issues));
  const keys = points.filter(isRecord).map((point) => `${point.x},${point.y}`);
  requireUnique(keys, `${location}.path`, issues);
  if (points.length >= 3 && points.every((point) => isRecord(point)
      && Number.isFinite(point.x) && Number.isFinite(point.y))) {
    let doubledArea = 0;
    for (let index = 0; index < points.length; index += 1) {
      const next = points[(index + 1) % points.length];
      doubledArea += points[index].x * next.y - next.x * points[index].y;
    }
    if (!Number.isFinite(doubledArea) || Math.abs(doubledArea) <= 1e-8) {
      issues.push(`${location}.path: non-zero polygon area required`);
    }
  }
}

function sceneHitRegionContains(hitRegion, point) {
  const path = hitRegion?.path;
  if (!Array.isArray(path) || path.length < 3 || !isRecord(point)
      || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return false;
  let inside = false;
  let previous = path[path.length - 1];
  for (const current of path) {
    if (!isRecord(current) || !isRecord(previous)) return false;
    const cross = (point.y - previous.y) * (current.x - previous.x)
      - (point.x - previous.x) * (current.y - previous.y);
    const onSegment = Math.abs(cross) <= 1e-9
      && point.x >= Math.min(previous.x, current.x) - 1e-9
      && point.x <= Math.max(previous.x, current.x) + 1e-9
      && point.y >= Math.min(previous.y, current.y) - 1e-9
      && point.y <= Math.max(previous.y, current.y) + 1e-9;
    if (onSegment) return true;
    const crossesY = (current.y > point.y) !== (previous.y > point.y);
    if (crossesY) {
      const intersectionX = (previous.x - current.x)
        * (point.y - current.y) / (previous.y - current.y) + current.x;
      if (point.x < intersectionX) inside = !inside;
    }
    previous = current;
  }
  return inside;
}

function validateSceneHitRegionInCrop(hitRegion, crop, location, issues) {
  const points = hitRegion?.path;
  const sourceRect = crop?.sourceRect;
  const viewport = crop?.viewport;
  if (!Array.isArray(points) || points.length < 3 || !isRecord(sourceRect) || !isRecord(viewport)
      || ![sourceRect.x, sourceRect.y, sourceRect.width, sourceRect.height,
        viewport.widthPoints, viewport.heightPoints].every(Number.isFinite)
      || sourceRect.width <= 0 || sourceRect.height <= 0
      || !points.every((point) => isRecord(point)
        && Number.isFinite(point.x) && Number.isFinite(point.y))) return;
  const whollyVisible = points.every((point) => {
    const x = (point.x - sourceRect.x) / sourceRect.width;
    const y = (point.y - sourceRect.y) / sourceRect.height;
    return x >= sceneRailGeometryDeadBand && x <= 1 - sceneRailGeometryDeadBand
      && y >= sceneRailGeometryDeadBand && y <= 1 - sceneRailGeometryDeadBand;
  });
  const xs = points.map((point) => point.x);
  const ys = points.map((point) => point.y);
  const widthPoints = (Math.max(...xs) - Math.min(...xs)) / sourceRect.width * viewport.widthPoints;
  const heightPoints = (Math.max(...ys) - Math.min(...ys)) / sourceRect.height * viewport.heightPoints;
  if (!whollyVisible || widthPoints < 44 + sceneRailGeometryDeadBand
      || heightPoints < 44 + sceneRailGeometryDeadBand) {
    issues.push(`${location}: must be wholly visible and at least 44 by 44 points in viewport crop '${crop.id}'`);
  }
}

// Geometry at a camera anchor is insufficient: linear centre and scale interpolation
// produces a quadratic screen-space trajectory between anchors. Keep a normalized
// clearance so boundary contact cannot alternate between accepted and rejected across
// floating-point implementations.
const sceneRailGeometryDeadBand = 1e-10;

function quadraticValue(coefficients, t) {
  return (coefficients.q2 * t + coefficients.q1) * t + coefficients.q0;
}

function quadraticExtrema(coefficients) {
  const values = [quadraticValue(coefficients, 0), quadraticValue(coefficients, 1)];
  if (coefficients.q2 !== 0) {
    const vertex = -coefficients.q1 / (2 * coefficients.q2);
    if (vertex > 0 && vertex < 1) values.push(quadraticValue(coefficients, vertex));
  }
  return values;
}

function projectionPolynomial(pointValue, start, end, railOriginValue, cropExtent, parallaxFactor) {
  const centerStart = start.centerValue;
  const centerDelta = end.centerValue - centerStart;
  const scaleStart = start.scale;
  const scaleDelta = end.scale - scaleStart;
  const offsetStart = pointValue - centerStart
    + parallaxFactor * (centerStart - railOriginValue);
  const offsetDelta = (parallaxFactor - 1) * centerDelta;
  return {
    q0: 0.5 + scaleStart * offsetStart / cropExtent,
    q1: (scaleStart * offsetDelta + scaleDelta * offsetStart) / cropExtent,
    q2: scaleDelta * offsetDelta / cropExtent,
  };
}

function railGeometryInputs(hitRegion, crop, cameraKeyframes, railOrigin, parallaxFactor) {
  const points = hitRegion?.path;
  const sourceRect = crop?.sourceRect;
  const viewport = crop?.viewport;
  if (!Array.isArray(points) || points.length < 1 || !isRecord(sourceRect)
      || !isRecord(viewport) || !Array.isArray(cameraKeyframes)
      || cameraKeyframes.length < 2 || !isRecord(railOrigin)
      || ![sourceRect.width, sourceRect.height, viewport.widthPoints, viewport.heightPoints,
        railOrigin.x, railOrigin.y, parallaxFactor].every(Number.isFinite)
      || sourceRect.width <= 0 || sourceRect.height <= 0
      || viewport.widthPoints <= 0 || viewport.heightPoints <= 0
      || !points.every((point) => isRecord(point)
        && Number.isFinite(point.x) && Number.isFinite(point.y))
      || !cameraKeyframes.every((keyframe) => isRecord(keyframe?.center)
        && [keyframe.center.x, keyframe.center.y, keyframe.scale].every(Number.isFinite)
        && keyframe.scale > 0)) return null;
  return { points, sourceRect, viewport };
}

function projectedPointRangeThroughSegment(
  point,
  axis,
  cropExtent,
  startKeyframe,
  endKeyframe,
  railOrigin,
  parallaxFactor,
) {
  const start = { centerValue: startKeyframe.center[axis], scale: startKeyframe.scale };
  const end = { centerValue: endKeyframe.center[axis], scale: endKeyframe.scale };
  const values = quadraticExtrema(projectionPolynomial(
    point[axis],
    start,
    end,
    railOrigin[axis],
    cropExtent,
    parallaxFactor,
  ));
  return { minimum: Math.min(...values), maximum: Math.max(...values) };
}

function scenePointIsVisibleThroughRail(
  point,
  crop,
  cameraKeyframes,
  railOrigin,
  parallaxFactor,
) {
  const input = railGeometryInputs(
    { path: [point] }, crop, cameraKeyframes, railOrigin, parallaxFactor,
  );
  if (!input) return false;
  for (let index = 0; index < cameraKeyframes.length - 1; index += 1) {
    const start = cameraKeyframes[index];
    const end = cameraKeyframes[index + 1];
    const xRange = projectedPointRangeThroughSegment(
      point, "x", input.sourceRect.width, start, end, railOrigin, parallaxFactor,
    );
    const yRange = projectedPointRangeThroughSegment(
      point, "y", input.sourceRect.height, start, end, railOrigin, parallaxFactor,
    );
    if (xRange.minimum < sceneRailGeometryDeadBand
        || xRange.maximum > 1 - sceneRailGeometryDeadBand
        || yRange.minimum < sceneRailGeometryDeadBand
        || yRange.maximum > 1 - sceneRailGeometryDeadBand) return false;
  }
  return true;
}

function sceneHitRegionIsVisibleThroughRail(
  hitRegion,
  crop,
  cameraKeyframes,
  railOrigin,
  parallaxFactor,
) {
  const input = railGeometryInputs(
    hitRegion, crop, cameraKeyframes, railOrigin, parallaxFactor,
  );
  if (!input || input.points.length < 3) return false;
  const xValues = input.points.map((point) => point.x);
  const yValues = input.points.map((point) => point.y);
  const authoredWidth = Math.max(...xValues) - Math.min(...xValues);
  const authoredHeight = Math.max(...yValues) - Math.min(...yValues);
  for (let index = 0; index < cameraKeyframes.length - 1; index += 1) {
    const start = cameraKeyframes[index];
    const end = cameraKeyframes[index + 1];
    let minimumX = Infinity;
    let maximumX = -Infinity;
    let minimumY = Infinity;
    let maximumY = -Infinity;
    for (const point of input.points) {
      const xRange = projectedPointRangeThroughSegment(
        point, "x", input.sourceRect.width, start, end, railOrigin, parallaxFactor,
      );
      const yRange = projectedPointRangeThroughSegment(
        point, "y", input.sourceRect.height, start, end, railOrigin, parallaxFactor,
      );
      minimumX = Math.min(minimumX, xRange.minimum);
      maximumX = Math.max(maximumX, xRange.maximum);
      minimumY = Math.min(minimumY, yRange.minimum);
      maximumY = Math.max(maximumY, yRange.maximum);
    }
    const minimumScale = Math.min(start.scale, end.scale);
    const minimumWidthPoints = authoredWidth * minimumScale
      / input.sourceRect.width * input.viewport.widthPoints;
    const minimumHeightPoints = authoredHeight * minimumScale
      / input.sourceRect.height * input.viewport.heightPoints;
    if (minimumX < sceneRailGeometryDeadBand
        || maximumX > 1 - sceneRailGeometryDeadBand
        || minimumY < sceneRailGeometryDeadBand
        || maximumY > 1 - sceneRailGeometryDeadBand
        || minimumWidthPoints < 44 + sceneRailGeometryDeadBand
        || minimumHeightPoints < 44 + sceneRailGeometryDeadBand) return false;
  }
  return true;
}

function scenePointIsVisibleInStaticCrop(point, crop) {
  const sourceRect = crop?.sourceRect;
  if (!isRecord(point) || !isRecord(sourceRect)
      || ![point.x, point.y, sourceRect.x, sourceRect.y,
        sourceRect.width, sourceRect.height].every(Number.isFinite)
      || sourceRect.width <= 0 || sourceRect.height <= 0) return false;
  const x = (point.x - sourceRect.x) / sourceRect.width;
  const y = (point.y - sourceRect.y) / sourceRect.height;
  return x >= sceneRailGeometryDeadBand && x <= 1 - sceneRailGeometryDeadBand
    && y >= sceneRailGeometryDeadBand && y <= 1 - sceneRailGeometryDeadBand;
}

function sceneHitRegionBounds(hitRegion) {
  const points = hitRegion?.path;
  if (!Array.isArray(points) || points.length < 3
      || !points.every((point) => isRecord(point)
        && Number.isFinite(point.x) && Number.isFinite(point.y))) return null;
  const xs = points.map((point) => point.x);
  const ys = points.map((point) => point.y);
  return {
    minimumX: Math.min(...xs),
    maximumX: Math.max(...xs),
    minimumY: Math.min(...ys),
    maximumY: Math.max(...ys),
  };
}

function unsafeRegionOverlapThroughRail(
  left,
  right,
  cameraKeyframes,
  railOrigin,
) {
  const leftBounds = sceneHitRegionBounds(left.hitRegion);
  const rightBounds = sceneHitRegionBounds(right.hitRegion);
  if (!leftBounds || !rightBounds || !Array.isArray(cameraKeyframes)
      || cameraKeyframes.length < 2 || !isRecord(railOrigin)
      || ![left.parallaxFactor, right.parallaxFactor,
        railOrigin.x, railOrigin.y].every(Number.isFinite)) return null;

  for (let index = 0; index < cameraKeyframes.length - 1; index += 1) {
    const start = cameraKeyframes[index];
    const end = cameraKeyframes[index + 1];
    if (!isRecord(start?.center) || !isRecord(end?.center)
        || ![start.center.x, start.center.y, end.center.x, end.center.y]
          .every(Number.isFinite)) return null;
    const expressions = [];
    for (const axis of ["X", "Y"]) {
      const coordinate = axis.toLowerCase();
      const centerStart = start.center[coordinate];
      const centerDelta = end.center[coordinate] - centerStart;
      const relativeParallax = left.parallaxFactor - right.parallaxFactor;
      const parallaxIntercept = relativeParallax * (centerStart - railOrigin[coordinate]);
      const parallaxSlope = relativeParallax * centerDelta;
      expressions.push({
        intercept: leftBounds[`maximum${axis}`] - rightBounds[`minimum${axis}`]
          + parallaxIntercept + sceneRailGeometryDeadBand,
        slope: parallaxSlope,
      });
      expressions.push({
        intercept: rightBounds[`maximum${axis}`] - leftBounds[`minimum${axis}`]
          - parallaxIntercept + sceneRailGeometryDeadBand,
        slope: -parallaxSlope,
      });
    }
    if (!expressions.every((expression) => Number.isFinite(expression.intercept)
      && Number.isFinite(expression.slope))) return null;
    const roots = [];
    for (const expression of expressions) {
      if (expression.slope === 0) continue;
      const root = -expression.intercept / expression.slope;
      if (root > 0 && root < 1) roots.push(root);
    }
    roots.sort((leftRoot, rightRoot) => leftRoot - rightRoot);
    const partition = [0];
    for (const root of roots) {
      if (root !== partition[partition.length - 1]) partition.push(root);
    }
    partition.push(1);
    const evaluationPoints = [0, 1];
    for (let partitionIndex = 0; partitionIndex < partition.length - 1; partitionIndex += 1) {
      evaluationPoints.push((partition[partitionIndex] + partition[partitionIndex + 1]) / 2);
    }
    if (evaluationPoints.some((t) => expressions.every(
      (expression) => expression.intercept + expression.slope * t > 0,
    ))) return true;
  }
  return false;
}

function unsafeStaticRegionOverlap(left, right) {
  const leftBounds = sceneHitRegionBounds(left.hitRegion);
  const rightBounds = sceneHitRegionBounds(right.hitRegion);
  if (!leftBounds || !rightBounds) return null;
  const expressions = [
    leftBounds.maximumX - rightBounds.minimumX + sceneRailGeometryDeadBand,
    rightBounds.maximumX - leftBounds.minimumX + sceneRailGeometryDeadBand,
    leftBounds.maximumY - rightBounds.minimumY + sceneRailGeometryDeadBand,
    rightBounds.maximumY - leftBounds.minimumY + sceneRailGeometryDeadBand,
  ];
  if (!expressions.every(Number.isFinite)) return null;
  return expressions.every((expression) => expression > 0);
}

function activeCameraSourceIsInsideMaster(crop, cameraKeyframes) {
  const sourceRect = crop?.sourceRect;
  if (!isRecord(sourceRect) || !Array.isArray(cameraKeyframes)
      || cameraKeyframes.length < 2
      || ![sourceRect.width, sourceRect.height].every(Number.isFinite)
      || sourceRect.width <= 0 || sourceRect.height <= 0
      || !cameraKeyframes.every((keyframe) => isRecord(keyframe?.center)
        && [keyframe.center.x, keyframe.center.y, keyframe.scale].every(Number.isFinite)
        && keyframe.scale > 0)) return false;
  for (let index = 0; index < cameraKeyframes.length - 1; index += 1) {
    const start = cameraKeyframes[index];
    const end = cameraKeyframes[index + 1];
    const scaleDelta = end.scale - start.scale;
    for (const [axis, cropExtent] of [["x", sourceRect.width], ["y", sourceRect.height]]) {
      const centerStart = start.center[axis];
      const centerDelta = end.center[axis] - centerStart;
      const leftClearance = {
        q0: start.scale * (centerStart + sceneRailGeometryDeadBand) - cropExtent / 2,
        q1: start.scale * centerDelta
          + scaleDelta * (centerStart + sceneRailGeometryDeadBand),
        q2: scaleDelta * centerDelta,
      };
      const rightClearance = {
        q0: start.scale * (1 + sceneRailGeometryDeadBand - centerStart) - cropExtent / 2,
        q1: -start.scale * centerDelta
          + scaleDelta * (1 + sceneRailGeometryDeadBand - centerStart),
        q2: -scaleDelta * centerDelta,
      };
      if (Math.min(...quadraticExtrema(leftClearance)) < 0
          || Math.min(...quadraticExtrema(rightClearance)) < 0) return false;
    }
  }
  return true;
}

function validateSceneInteractionVisualBinding(value, location, layers, targets, issues) {
  const record = shape(value, location, ["grammar", "configuration"], [], issues);
  if (!record) return;
  if (!enumValue(record.grammar, interactionGrammars, `${location}.grammar`, issues)) return;
  const layerByID = new Map(layers.filter(isRecord).map((layer) => [layer.id, layer]));
  const targetByID = new Map(targets.filter(isRecord).map((target) => [target.interactionTargetID, target]));
  const variantsExist = (variantIDs, layer) => variantIDs.length === new Set(variantIDs).size
    && variantIDs.every((variantID) => stableIDPattern.test(variantID ?? "")
      && layer?.stateVariants?.some((variant) => variant.id === variantID));

  if (record.grammar === "trace") {
    const configuration = shape(record.configuration, `${location}.configuration`, [
      "interactionID", "interactionTargetID", "layerID", "idleVariantID",
      "tracingVariantID", "completedVariantID",
    ], ["reachedAnchorVariants"], issues);
    if (!configuration) return;
    for (const key of [
      "interactionID", "interactionTargetID", "layerID", "idleVariantID",
      "tracingVariantID", "completedVariantID",
    ]) stableID(configuration[key], `${location}.configuration.${key}`, issues);
    const reachedAnchorVariants = Object.hasOwn(configuration, "reachedAnchorVariants")
      ? arrayValue(
        configuration.reachedAnchorVariants,
        `${location}.configuration.reachedAnchorVariants`,
        issues,
        1,
      )
      : [];
    for (const [index, binding] of reachedAnchorVariants.entries()) {
      const item = shape(binding, `${location}.configuration.reachedAnchorVariants[${index}]`, [
        "anchorID", "variantID",
      ], [], issues);
      if (!item) continue;
      stableID(item.anchorID, `${location}.configuration.reachedAnchorVariants[${index}].anchorID`, issues);
      stableID(item.variantID, `${location}.configuration.reachedAnchorVariants[${index}].variantID`, issues);
    }
    requireUnique(
      reachedAnchorVariants.filter(isRecord).map(({ anchorID }) => anchorID),
      `${location}.configuration.reachedAnchorVariants.anchorID`,
      issues,
    );
    requireUnique(
      reachedAnchorVariants.filter(isRecord).map(({ variantID }) => variantID),
      `${location}.configuration.reachedAnchorVariants.variantID`,
      issues,
    );
    const layer = layerByID.get(configuration.layerID);
    if (!layer || targetByID.get(configuration.interactionTargetID)?.layerID !== configuration.layerID
        || !variantsExist([
          configuration.idleVariantID,
          configuration.tracingVariantID,
          ...reachedAnchorVariants.filter(isRecord).map(({ variantID }) => variantID),
          configuration.completedVariantID,
        ], layer)) {
      issues.push(`${location}.configuration: trace requires a real route target and distinct authored route-state variants`);
    }
    return;
  }

  if (record.grammar === "assemble") {
    const configuration = shape(record.configuration, `${location}.configuration`, ["interactionID", "components"], [], issues);
    if (!configuration) return;
    stableID(configuration.interactionID, `${location}.configuration.interactionID`, issues);
    const components = arrayValue(configuration.components, `${location}.configuration.components`, issues, 1);
    for (const [index, component] of components.entries()) {
      const item = shape(component, `${location}.configuration.components[${index}]`, [
        "componentID", "sourceInteractionTargetID", "slotInteractionTargetID", "layerID",
        "availableVariantID", "resistedVariantID", "placedVariantID",
      ], [], issues);
      if (!item) continue;
      for (const key of Object.keys(item)) stableID(item[key], `${location}.configuration.components[${index}].${key}`, issues);
      const layer = layerByID.get(item.layerID);
      if (item.sourceInteractionTargetID === item.slotInteractionTargetID) {
        issues.push(`${location}.configuration.components[${index}]: source and slot targets must be distinct`);
      }
      if (!layer || targetByID.get(item.sourceInteractionTargetID)?.layerID !== item.layerID
          || targetByID.get(item.slotInteractionTargetID)?.layerID !== item.layerID
          || !variantsExist([item.availableVariantID, item.resistedVariantID, item.placedVariantID], layer)) {
        issues.push(`${location}.configuration.components[${index}]: requires real layer-bound source and slot targets and three component-state variants`);
      }
    }
    const componentRecords = components.filter(isRecord);
    const sourceTargetIDs = componentRecords.map((item) => item.sourceInteractionTargetID);
    const slotTargetIDs = componentRecords.map((item) => item.slotInteractionTargetID);
    requireUnique(componentRecords.map((item) => item.componentID), `${location}.configuration.components.componentID`, issues);
    requireUnique(sourceTargetIDs, `${location}.configuration.components.sourceInteractionTargetID`, issues);
    requireUnique(slotTargetIDs, `${location}.configuration.components.slotInteractionTargetID`, issues);
    requireUnique([...sourceTargetIDs, ...slotTargetIDs], `${location}.configuration.components.sourceAndSlotInteractionTargetID`, issues);
    return;
  }

  if (record.grammar === "pressure") {
    const configuration = shape(record.configuration, `${location}.configuration`, [
      "interactionID", "forces", "systemLayerID", "restingVariantID",
      "resistingVariantID", "stableVariantID", "brokenVariantID",
    ], [], issues);
    if (!configuration) return;
    for (const key of ["interactionID", "systemLayerID", "restingVariantID", "resistingVariantID", "stableVariantID", "brokenVariantID"]) {
      stableID(configuration[key], `${location}.configuration.${key}`, issues);
    }
    const forces = arrayValue(configuration.forces, `${location}.configuration.forces`, issues, 1);
    for (const [index, force] of forces.entries()) {
      const item = shape(force, `${location}.configuration.forces[${index}]`, ["forceID", "layerID"], ["interactionTargetID"], issues);
      if (!item) continue;
      stableID(item.forceID, `${location}.configuration.forces[${index}].forceID`, issues);
      stableID(item.layerID, `${location}.configuration.forces[${index}].layerID`, issues);
      if (!layerByID.has(item.layerID)) issues.push(`${location}.configuration.forces[${index}].layerID: missing scene layer '${item.layerID}'`);
      if (Object.hasOwn(item, "interactionTargetID")) {
        stableID(item.interactionTargetID, `${location}.configuration.forces[${index}].interactionTargetID`, issues);
        if (targetByID.get(item.interactionTargetID)?.layerID !== item.layerID) {
          issues.push(`${location}.configuration.forces[${index}].interactionTargetID: must bind a real target on the force layer`);
        }
      }
    }
    requireUnique(forces.filter(isRecord).map((item) => item.forceID), `${location}.configuration.forces.forceID`, issues);
    const systemLayer = layerByID.get(configuration.systemLayerID);
    if (!systemLayer || !variantsExist([
      configuration.restingVariantID,
      configuration.resistingVariantID,
      configuration.stableVariantID,
      configuration.brokenVariantID,
    ], systemLayer)) {
      issues.push(`${location}.configuration: pressure requires four distinct system-state variants`);
    }
    return;
  }

  if (record.grammar === "transform") {
    const configuration = shape(record.configuration, `${location}.configuration`, ["interactionID", "stages"], [], issues);
    if (!configuration) return;
    stableID(configuration.interactionID, `${location}.configuration.interactionID`, issues);
    const stages = arrayValue(configuration.stages, `${location}.configuration.stages`, issues, 1);
    for (const [index, stage] of stages.entries()) {
      const item = shape(stage, `${location}.configuration.stages[${index}]`, [
        "stageID", "interactionTargetID", "layerID", "beforeVariantID",
        "activeVariantID", "completedVariantID",
      ], [], issues);
      if (!item) continue;
      for (const key of Object.keys(item)) stableID(item[key], `${location}.configuration.stages[${index}].${key}`, issues);
      const layer = layerByID.get(item.layerID);
      if (!layer || targetByID.get(item.interactionTargetID)?.layerID !== item.layerID
          || !variantsExist([item.beforeVariantID, item.activeVariantID, item.completedVariantID], layer)) {
        issues.push(`${location}.configuration.stages[${index}]: requires a real target and three transformation variants`);
      }
    }
    requireUnique(stages.filter(isRecord).map((item) => item.stageID), `${location}.configuration.stages.stageID`, issues);
    requireUnique(stages.filter(isRecord).map((item) => item.interactionTargetID), `${location}.configuration.stages.interactionTargetID`, issues);
    return;
  }

  const configuration = shape(record.configuration, `${location}.configuration`,
    ["interactionID", "resource", "transferLayerID", "destinations"], [], issues);
  if (!configuration) return;
  stableID(configuration.interactionID, `${location}.configuration.interactionID`, issues);
  stableID(configuration.transferLayerID, `${location}.configuration.transferLayerID`, issues);
  const transferLayer = layerByID.get(configuration.transferLayerID);
  if (!transferLayer) {
    issues.push(`${location}.configuration.transferLayerID: missing scene layer '${configuration.transferLayerID}'`);
  } else if (transferLayer.motion?.parallaxFactor !== 0
    || transferLayer.motion?.windResponse !== 0) {
    issues.push(`${location}.configuration.transferLayerID: direct response must control transfer geometry without parallax or wind drift`);
  }
  const resource = shape(configuration.resource, `${location}.configuration.resource`,
    ["layerID", "hitRegion", "hitTest", "variantsByRemainingUnits"], [], issues);
  if (resource) {
    stableID(resource.layerID, `${location}.configuration.resource.layerID`, issues);
    const resourceLayer = layerByID.get(resource.layerID);
    if (!resourceLayer) {
      issues.push(`${location}.configuration.resource.layerID: missing scene layer '${resource.layerID}'`);
    }
    validateSceneHitRegion(resource.hitRegion, `${location}.configuration.resource.hitRegion`, issues);
    if (resource.hitTest !== "selectedVariantAlpha") {
      issues.push(`${location}.configuration.resource.hitTest: expected selectedVariantAlpha`);
    }
    const frame = resourceLayer?.frame;
    if (!isRecord(frame) || !resource.hitRegion?.path?.every((point) => isRecord(point)
      && point.x >= frame.x && point.x <= frame.x + frame.width
      && point.y >= frame.y && point.y <= frame.y + frame.height)
      || resourceLayer?.motion?.windResponse !== 0
      || !resourceLayer?.stateVariants?.every((variant) => typeof variant?.masks?.alphaMaskAssetPath === "string")) {
      issues.push(`${location}.configuration.resource: requires a fixed alpha-bound hit region inside every resource variant`);
    }
    if (resource.layerID === configuration.transferLayerID) {
      issues.push(`${location}.configuration: resource and transfer layers must be distinct`);
    }
    const thresholds = arrayValue(
      resource.variantsByRemainingUnits,
      `${location}.configuration.resource.variantsByRemainingUnits`,
      issues,
      2,
    );
    let previousMaximum = -1;
    const thresholdVariantIDs = [];
    for (const [index, threshold] of thresholds.entries()) {
      const item = shape(threshold,
        `${location}.configuration.resource.variantsByRemainingUnits[${index}]`,
        ["maximumRemainingUnits", "variantID"], [], issues);
      if (!item) continue;
      if (integer(item.maximumRemainingUnits,
        `${location}.configuration.resource.variantsByRemainingUnits[${index}].maximumRemainingUnits`, issues, 0)) {
        if (item.maximumRemainingUnits <= previousMaximum) {
          issues.push(`${location}.configuration.resource.variantsByRemainingUnits: maxima must be strictly increasing from zero`);
        }
        previousMaximum = item.maximumRemainingUnits;
      }
      stableID(item.variantID,
        `${location}.configuration.resource.variantsByRemainingUnits[${index}].variantID`, issues);
      thresholdVariantIDs.push(item.variantID);
    }
    if (thresholds[0]?.maximumRemainingUnits !== 0) {
      issues.push(`${location}.configuration.resource.variantsByRemainingUnits: first maximum must be zero`);
    }
    requireUnique(thresholdVariantIDs, `${location}.configuration.resource.variantsByRemainingUnits.variantID`, issues);
    const resourceVariantIDs = Array.isArray(layerByID.get(resource.layerID)?.stateVariants)
      ? layerByID.get(resource.layerID).stateVariants.map((variant) => variant.id).sort()
      : [];
    if (JSON.stringify([...thresholdVariantIDs].sort()) !== JSON.stringify(resourceVariantIDs)) {
      issues.push(`${location}.configuration.resource.variantsByRemainingUnits: must cover every resource layer variant exactly once`);
    }
  }
  const destinations = arrayValue(
    configuration.destinations,
    `${location}.configuration.destinations`,
    issues,
    1,
  );
  for (const [index, destination] of destinations.entries()) {
    const item = shape(destination, `${location}.configuration.destinations[${index}]`,
      ["destinationID", "interactionTargetID", "layerID", "emptyVariantID",
        "receivingVariantID", "completedVariantID", "transferPath"], [], issues);
    if (!item) continue;
    for (const key of ["destinationID", "interactionTargetID", "layerID", "emptyVariantID",
      "receivingVariantID", "completedVariantID"]) {
      stableID(item[key], `${location}.configuration.destinations[${index}].${key}`, issues);
    }
    const layer = layerByID.get(item.layerID);
    const target = targetByID.get(item.interactionTargetID);
    if (!layer || !target || target.layerID !== item.layerID) {
      issues.push(`${location}.configuration.destinations[${index}]: must bind a real target on the same known layer`);
    }
    const variantIDs = [item.emptyVariantID, item.receivingVariantID, item.completedVariantID];
    requireUnique(variantIDs, `${location}.configuration.destinations[${index}].variants`, issues);
    const knownVariants = new Set(Array.isArray(layer?.stateVariants)
      ? layer.stateVariants.map((variant) => variant.id) : []);
    if (!variantIDs.every((variantID) => knownVariants.has(variantID))) {
      issues.push(`${location}.configuration.destinations[${index}]: visual variants must exist on the destination layer`);
    }
    const transferPath = arrayValue(
      item.transferPath,
      `${location}.configuration.destinations[${index}].transferPath`,
      issues,
      2,
    );
    transferPath.forEach((point, pointIndex) => validatePoint(
      point,
      `${location}.configuration.destinations[${index}].transferPath[${pointIndex}]`,
      issues,
    ));
    if (transferPath.length >= 2
      && (!sceneHitRegionContains(resource?.hitRegion, transferPath[0])
        || !sceneHitRegionContains(target?.hitRegion, transferPath[transferPath.length - 1]))) {
      issues.push(`${location}.configuration.destinations[${index}].transferPath: must begin in the resource hit region and end inside its destination target`);
    }
  }
  for (const key of ["destinationID", "interactionTargetID", "layerID"]) {
    requireUnique(
      destinations.filter(isRecord).map((destination) => destination[key]),
      `${location}.configuration.destinations.${key}`,
      issues,
    );
  }
}

function validateAllocateRailGeometry(
  value,
  location,
  layers,
  targets,
  normalCrops,
  reducedCrops,
  cameraKeyframes,
  railOrigin,
  issues,
) {
  if (value?.grammar !== "allocate" || !isRecord(value.configuration)
      || !isRecord(value.configuration.resource)) return;
  const configuration = value.configuration;
  const resource = configuration.resource;
  const layerByID = new Map(layers.filter(isRecord).map((layer) => [layer.id, layer]));
  const targetByID = new Map(targets.filter(isRecord)
    .map((target) => [target.interactionTargetID, target]));
  const resourceLayer = layerByID.get(resource.layerID);
  const transferLayer = layerByID.get(configuration.transferLayerID);
  if (resourceLayer) {
    for (const crop of normalCrops) {
      if (!sceneHitRegionIsVisibleThroughRail(
        resource.hitRegion,
        crop,
        cameraKeyframes,
        railOrigin,
        resourceLayer.motion?.parallaxFactor,
      )) {
        issues.push(`${location}.configuration.resource.hitRegion.normal: source region must remain visible, follow the rendered resource and stay at least 44 by 44 points through crop '${crop?.id}' and the complete camera rail`);
      }
    }
    for (const crop of reducedCrops) {
      validateSceneHitRegionInCrop(
        resource.hitRegion,
        crop,
        `${location}.configuration.resource.hitRegion.reduced`,
        issues,
      );
    }
  }

  const destinations = Array.isArray(configuration.destinations)
    ? configuration.destinations.filter(isRecord) : [];
  const destinationRegions = [];
  for (const destination of destinations) {
    const target = targetByID.get(destination.interactionTargetID);
    const destinationLayer = layerByID.get(destination.layerID);
    if (target && destinationLayer) {
      destinationRegions.push({
        id: destination.destinationID,
        hitRegion: target.hitRegion,
        parallaxFactor: destinationLayer.motion?.parallaxFactor,
      });
    }
  }
  if (resourceLayer) {
    const resourceRegion = {
      id: "resource",
      hitRegion: resource.hitRegion,
      parallaxFactor: resourceLayer.motion?.parallaxFactor,
    };
    for (const destination of destinationRegions) {
      const unsafeOverlap = unsafeRegionOverlapThroughRail(
        resourceRegion, destination, cameraKeyframes, railOrigin,
      );
      if (unsafeOverlap === null) {
        issues.push(`${location}.configuration: could not prove camera-rail clearance between the source region and destination '${destination.id}'`);
      } else if (unsafeOverlap) {
        issues.push(`${location}.configuration: source region and destination '${destination.id}' overlap or lose the required clearance along the camera rail`);
      }
    }
    const reducedRegions = [resourceRegion, ...destinationRegions];
    for (let leftIndex = 0; leftIndex < reducedRegions.length; leftIndex += 1) {
      for (let rightIndex = leftIndex + 1; rightIndex < reducedRegions.length; rightIndex += 1) {
        const unsafeOverlap = unsafeStaticRegionOverlap(
          reducedRegions[leftIndex], reducedRegions[rightIndex],
        );
        if (unsafeOverlap === null) {
          issues.push(`${location}.configuration: could not prove Reduce Motion clearance between '${reducedRegions[leftIndex].id}' and '${reducedRegions[rightIndex].id}'`);
        } else if (unsafeOverlap) {
          issues.push(`${location}.configuration: regions '${reducedRegions[leftIndex].id}' and '${reducedRegions[rightIndex].id}' overlap or lose the required clearance in Reduce Motion`);
        }
      }
    }
  }

  for (const [destinationIndex, destination] of destinations.entries()) {
    const transferLocation = `${location}.configuration.destinations[${destinationIndex}].transferPath`;
    const transferPath = Array.isArray(destination.transferPath)
      ? destination.transferPath.filter(isRecord) : [];
    const target = targetByID.get(destination.interactionTargetID);
    const destinationLayer = layerByID.get(destination.layerID);
    if (!resourceLayer || !transferLayer || !destinationLayer || !target
        || transferPath.length < 2) continue;
    if (resourceLayer.motion?.windResponse !== 0
        || transferLayer.motion?.windResponse !== 0
        || destinationLayer.motion?.windResponse !== 0) {
      issues.push(`${transferLocation}: source, transfer and destination attachments require fixed wind geometry`);
    }
    for (let pointIndex = 1; pointIndex < transferPath.length; pointIndex += 1) {
      const previous = transferPath[pointIndex - 1];
      const current = transferPath[pointIndex];
      if ([previous.x, previous.y, current.x, current.y].every(Number.isFinite)
          && Math.hypot(current.x - previous.x, current.y - previous.y)
            <= sceneRailGeometryDeadBand) {
        issues.push(`${transferLocation}: adjacent control points must be distinct beyond the normalized clearance`);
        break;
      }
    }
    for (const [pointIndex, point] of transferPath.entries()) {
      const attachmentLayer = pointIndex === 0
        ? resourceLayer
        : pointIndex === transferPath.length - 1 ? destinationLayer : transferLayer;
      for (const crop of normalCrops) {
        if (!scenePointIsVisibleThroughRail(
          point,
          crop,
          cameraKeyframes,
          railOrigin,
          attachmentLayer.motion?.parallaxFactor,
        )) {
          issues.push(`${transferLocation}[${pointIndex}]: control point must remain visible through crop '${crop?.id}' and the complete camera rail using its source, transfer or destination attachment`);
        }
      }
      for (const crop of reducedCrops) {
        if (!scenePointIsVisibleInStaticCrop(point, crop)) {
          issues.push(`${transferLocation}[${pointIndex}]: control point must remain visible in reduced crop '${crop?.id}'`);
        }
      }
    }
  }
}

function validateReduceMotionComposition(value, location, issues) {
  const record = shape(value, location,
    ["canvas", "viewportCrops", "strata"], [], issues);
  if (!record) return null;
  const canvas = validateScenePixelSize(record.canvas, `${location}.canvas`, issues);
  validateViewportCropSet(record.viewportCrops, `${location}.viewportCrops`, canvas, issues);
  const strata = arrayValue(record.strata, `${location}.strata`, issues, 1);
  const stratumIDs = [];
  strata.forEach((value, index) => {
    const stratumLocation = `${location}.strata[${index}]`;
    const stratum = shape(value, stratumLocation, ["id", "kind"], ["assetPath", "layerID"], issues);
    if (!stratum) return;
    stableID(stratum.id, `${stratumLocation}.id`, issues);
    stratumIDs.push(stratum.id);
    if (stratum.kind === "staticPlate") {
      if (!Object.hasOwn(stratum, "assetPath") || Object.hasOwn(stratum, "layerID")) {
        issues.push(`${stratumLocation}: staticPlate requires assetPath and forbids layerID`);
      } else {
        validateSafeAssetPath(stratum.assetPath, `${stratumLocation}.assetPath`, issues);
      }
    } else if (stratum.kind === "stateOverlay") {
      if (!Object.hasOwn(stratum, "layerID") || Object.hasOwn(stratum, "assetPath")) {
        issues.push(`${stratumLocation}: stateOverlay requires layerID and forbids assetPath`);
      } else {
        stableID(stratum.layerID, `${stratumLocation}.layerID`, issues);
      }
    } else {
      issues.push(`${stratumLocation}.kind: expected staticPlate or stateOverlay`);
    }
  });
  requireUnique(stratumIDs, `${location}.strata.id`, issues);
  return record;
}

function validateScene(value, location, issues) {
  const record = shape(value, location,
    ["id", "sceneCanvas", "layers", "cameraRail", "atmosphere", "interactionTargets", "reduceMotionComposition", "mechanismFocus", "accessibilityID"], ["interactionVisualBinding"], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  const sceneCanvas = validateSceneCanvas(record.sceneCanvas, `${location}.sceneCanvas`, issues);
  const reduceMotion = validateReduceMotionComposition(record.reduceMotionComposition, `${location}.reduceMotionComposition`, issues);
  const layers = arrayValue(record.layers, `${location}.layers`, issues, 1);
  layers.forEach((layer, index) => validateSceneLayer(layer, `${location}.layers[${index}]`, index, issues));
  requireUnique(layers.filter(isRecord).map((layer) => layer.id), `${location}.layers.id`, issues);
  const dynamicLayerAssetPaths = new Set(layers.filter(isRecord).flatMap((layer) => [
    layer.assetPath,
    ...(Array.isArray(layer.stateVariants)
      ? layer.stateVariants.filter(isRecord).map((variant) => variant.assetPath)
      : []),
  ]));
  const reducedStrata = Array.isArray(reduceMotion?.strata) ? reduceMotion.strata : [];
  const staticAssetPaths = reducedStrata.filter(isRecord)
    .filter((stratum) => stratum.kind === "staticPlate")
    .map((stratum) => stratum.assetPath);
  if (new Set(staticAssetPaths).size !== staticAssetPaths.length
    || staticAssetPaths.some((assetPath) => dynamicLayerAssetPaths.has(assetPath))) {
    issues.push(`${location}.reduceMotionComposition.strata: static plates require unique assets not reused by dynamic layers`);
  }
  const statefulLayers = layers.filter(isRecord)
    .filter((layer) => Array.isArray(layer.stateVariants) && layer.stateVariants.length > 0)
    .sort((left, right) => left.order - right.order);
  const statefulLayerIDs = statefulLayers.map((layer) => layer.id);
  const reducedOverlayIDs = reducedStrata.filter(isRecord)
    .filter((stratum) => stratum.kind === "stateOverlay")
    .map((stratum) => stratum.layerID);
  if (JSON.stringify(reducedOverlayIDs) !== JSON.stringify(statefulLayerIDs)) {
    issues.push(`${location}.reduceMotionComposition.strata: must place every and only stateful layer once in authored back-to-front order`);
  }
  if (statefulLayerIDs.length > 0
    && (reducedStrata[0]?.kind !== "staticPlate"
      || reducedStrata[reducedStrata.length - 1]?.kind !== "staticPlate")) {
    issues.push(`${location}.reduceMotionComposition.strata: stateful scenes require static underlay and foreground strata`);
  }
  const normalCrops = Array.isArray(sceneCanvas?.viewportCrops) ? sceneCanvas.viewportCrops : [];
  const reducedCrops = Array.isArray(reduceMotion?.viewportCrops) ? reduceMotion.viewportCrops : [];
  const reducedCropByID = new Map(reducedCrops.filter(isRecord).map((crop) => [crop.id, crop]));
  const matchingCropSets = normalCrops.length === reducedCrops.length
    && normalCrops.every((crop) => isRecord(crop) && reducedCropByID.has(crop.id)
      && crop.viewport?.widthPoints === reducedCropByID.get(crop.id)?.viewport?.widthPoints
      && crop.viewport?.heightPoints === reducedCropByID.get(crop.id)?.viewport?.heightPoints);
  if (!matchingCropSets) {
    issues.push(`${location}.reduceMotionComposition.viewportCrops: must match the normal crop IDs and viewport dimensions`);
  }
  const rail = shape(record.cameraRail, `${location}.cameraRail`, ["keyframes"], [], issues);
  let cameraKeyframes = [];
  if (rail) {
    const keyframes = arrayValue(rail.keyframes, `${location}.cameraRail.keyframes`, issues, 2);
    cameraKeyframes = keyframes.filter(isRecord);
    let previous = -Infinity;
    for (const [index, keyframe] of keyframes.entries()) {
      const item = shape(keyframe, `${location}.cameraRail.keyframes[${index}]`, ["progress", "center", "scale"], [], issues);
      if (!item) continue;
      if (finiteNumber(item.progress, `${location}.cameraRail.keyframes[${index}].progress`, issues)
          && (item.progress < 0 || item.progress > 1)) {
        issues.push(`${location}.cameraRail.keyframes[${index}].progress: must be in unit space`);
      }
      if (Number.isFinite(item.progress) && item.progress <= previous) issues.push(`${location}.cameraRail.keyframes: progress must be strictly increasing and unique`);
      if (Number.isFinite(item.progress)) previous = item.progress;
      validatePoint(item.center, `${location}.cameraRail.keyframes[${index}].center`, issues);
      if (sceneCanvas?.cameraTravelBounds && isRecord(item.center)
          && Number.isFinite(item.center.x) && Number.isFinite(item.center.y)) {
        const bounds = sceneCanvas.cameraTravelBounds;
        if (item.center.x < bounds.x || item.center.x > bounds.x + bounds.width
            || item.center.y < bounds.y || item.center.y > bounds.y + bounds.height) {
          issues.push(`${location}.cameraRail.keyframes[${index}].center: must remain inside authored camera travel`);
        }
      }
      if (finiteNumber(item.scale, `${location}.cameraRail.keyframes[${index}].scale`, issues)
          && (item.scale < 0.25 || item.scale > 4)) {
        issues.push(`${location}.cameraRail.keyframes[${index}].scale: must be between 0.25 and 4`);
      }
    }
    if (keyframes[0]?.progress !== 0 || keyframes.at(-1)?.progress !== 1) {
      issues.push(`${location}.cameraRail.keyframes: progress must start at 0 and end at 1`);
    }
    for (const crop of normalCrops) {
      if (!activeCameraSourceIsInsideMaster(crop, cameraKeyframes)) {
        issues.push(`${location}.cameraRail: active camera source must stay inside the authored master through crop '${crop?.id}' and the complete camera rail`);
      }
    }
  }
  const atmosphere = arrayValue(record.atmosphere, `${location}.atmosphere`, issues);
  for (const [index, entry] of atmosphere.entries()) {
    const item = shape(entry, `${location}.atmosphere[${index}]`, ["kind", "density", "velocity", "deterministicSeed"], [], issues);
    if (!item) continue;
    enumValue(item.kind, atmosphereKinds, `${location}.atmosphere[${index}].kind`, issues);
    if (finiteNumber(item.density, `${location}.atmosphere[${index}].density`, issues)
        && (item.density < 0 || item.density > 1)) {
      issues.push(`${location}.atmosphere[${index}].density: must be in unit space`);
    }
    validateSignedUnitVector(item.velocity, `${location}.atmosphere[${index}].velocity`, issues);
    if (integer(item.deterministicSeed, `${location}.atmosphere[${index}].deterministicSeed`, issues, 0)
        && item.deterministicSeed > 4_294_967_295) {
      issues.push(`${location}.atmosphere[${index}].deterministicSeed: 32-bit seed required`);
    }
  }
  const targets = arrayValue(record.interactionTargets, `${location}.interactionTargets`, issues);
  const layerIDs = new Set(layers.filter(isRecord).map((layer) => layer.id));
  const layerByID = new Map(layers.filter(isRecord).map((layer) => [layer.id, layer]));
  const railOrigin = cameraKeyframes[0]?.center;
  for (const [index, target] of targets.entries()) {
    const item = shape(target, `${location}.interactionTargets[${index}]`,
      ["interactionTargetID", "layerID", "hitRegion", "accessibilityElementID"], [], issues);
    if (!item) continue;
    stableID(item.interactionTargetID, `${location}.interactionTargets[${index}].interactionTargetID`, issues);
    if (stableID(item.layerID, `${location}.interactionTargets[${index}].layerID`, issues)
        && !layerIDs.has(item.layerID)) {
      issues.push(`${location}.interactionTargets[${index}].layerID: missing scene layer '${item.layerID}'`);
    }
    stableID(item.accessibilityElementID, `${location}.interactionTargets[${index}].accessibilityElementID`, issues);
    validateSceneHitRegion(item.hitRegion, `${location}.interactionTargets[${index}].hitRegion`, issues);
    const boundLayer = layerByID.get(item.layerID);
    if (boundLayer?.motion?.windResponse !== 0) {
      issues.push(`${location}.interactionTargets[${index}].layerID: interactive target layers must keep fixed hit geometry and cannot use continuous wind displacement`);
    }
    if (boundLayer && !item.hitRegion?.path?.every((point) => isRecord(point)
      && point.x >= boundLayer.frame?.x
      && point.x <= boundLayer.frame?.x + boundLayer.frame?.width
      && point.y >= boundLayer.frame?.y
      && point.y <= boundLayer.frame?.y + boundLayer.frame?.height)) {
      issues.push(`${location}.interactionTargets[${index}].hitRegion: every target point must remain inside its bound layer frame`);
    }
    for (const crop of normalCrops) {
      if (!sceneHitRegionIsVisibleThroughRail(
        item.hitRegion,
        crop,
        cameraKeyframes,
        railOrigin,
        boundLayer?.motion?.parallaxFactor,
      )) {
        issues.push(`${location}.interactionTargets[${index}].hitRegion.normal: target '${item.interactionTargetID}' must be wholly visible, follow its rendered layer and stay at least 44 by 44 points through crop '${crop?.id}' and the complete camera rail`);
      }
    }
    for (const crop of reducedCrops) {
      validateSceneHitRegionInCrop(
        item.hitRegion,
        crop,
        `${location}.interactionTargets[${index}].hitRegion.reduced`,
        issues,
      );
    }
  }
  const targetRegions = targets.filter(isRecord).map((target) => ({
    id: target.interactionTargetID,
    hitRegion: target.hitRegion,
    parallaxFactor: layerByID.get(target.layerID)?.motion?.parallaxFactor,
  }));
  for (let leftIndex = 0; leftIndex < targetRegions.length; leftIndex += 1) {
    for (let rightIndex = leftIndex + 1; rightIndex < targetRegions.length; rightIndex += 1) {
      const unsafeOverlap = unsafeRegionOverlapThroughRail(
        targetRegions[leftIndex],
        targetRegions[rightIndex],
        cameraKeyframes,
        railOrigin,
      );
      if (unsafeOverlap === null) {
        issues.push(`${location}.interactionTargets: could not prove camera-rail clearance between targets '${targetRegions[leftIndex].id}' and '${targetRegions[rightIndex].id}'`);
      } else if (unsafeOverlap) {
        issues.push(`${location}.interactionTargets: targets '${targetRegions[leftIndex].id}' and '${targetRegions[rightIndex].id}' overlap or lose the required clearance in crop '${normalCrops[0]?.id}' along the camera rail`);
      }
    }
  }
  requireUnique(targets.filter(isRecord).map((target) => target.interactionTargetID), `${location}.interactionTargets.interactionTargetID`, issues);
  if (Object.hasOwn(record, "interactionVisualBinding")) {
    validateSceneInteractionVisualBinding(
      record.interactionVisualBinding,
      `${location}.interactionVisualBinding`,
      layers,
      targets,
      issues,
    );
    validateAllocateRailGeometry(
      record.interactionVisualBinding,
      `${location}.interactionVisualBinding`,
      layers,
      targets,
      normalCrops,
      reducedCrops,
      cameraKeyframes,
      railOrigin,
      issues,
    );
  }
  validateLocalizedString(record.mechanismFocus, `${location}.mechanismFocus`, issues);
  stableID(record.accessibilityID, `${location}.accessibilityID`, issues);
}

function validateNarrationCueBinding(value, location, issues) {
  const record = shape(value, location,
    ["manuscriptSegmentID", "manuscriptSegmentSHA256", "scope"], [], issues);
  if (!record) return;
  stableID(record.manuscriptSegmentID, `${location}.manuscriptSegmentID`, issues);
  if (typeof record.manuscriptSegmentSHA256 !== "string"
      || !sha256Pattern.test(record.manuscriptSegmentSHA256)) {
    issues.push(`${location}.manuscriptSegmentSHA256: lowercase SHA-256 required`);
  }
  const scope = shape(record.scope, `${location}.scope`, ["chapterID", "arcID", "beatID"], [], issues);
  if (scope) {
    for (const key of ["chapterID", "arcID", "beatID"]) {
      stableID(scope[key], `${location}.scope.${key}`, issues);
    }
  }
}

function validateAudioTimeline(value, location, issues) {
  const record = shape(value, location, ["id", "sampleRate", "events", "haptics"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  if (integer(record.sampleRate, `${location}.sampleRate`, issues, 1) && record.sampleRate !== 48_000) {
    issues.push(`${location}.sampleRate: authored masters must use 48000 Hz`);
  }
  const events = arrayValue(record.events, `${location}.events`, issues, 1);
  for (const [index, event] of events.entries()) {
    const item = shape(event, `${location}.events[${index}]`, ["cueID", "role", "startSample", "durationSamples", "gain"], ["assetPath", "narrationBinding"], issues);
    if (!item) continue;
    stableID(item.cueID, `${location}.events[${index}].cueID`, issues);
    enumValue(item.role, audioRoles, `${location}.events[${index}].role`, issues);
    integer(item.startSample, `${location}.events[${index}].startSample`, issues, 0);
    integer(item.durationSamples, `${location}.events[${index}].durationSamples`, issues, 0);
    if (finiteNumber(item.gain, `${location}.events[${index}].gain`, issues)
        && (item.gain < 0 || item.gain > 4)) {
      issues.push(`${location}.events[${index}].gain: linear gain must be between zero and four`);
    }
    if (item.role === "silence") {
      if (Object.hasOwn(item, "assetPath")) issues.push(`${location}.events[${index}].assetPath: silence cannot reference an asset`);
    } else if (!Object.hasOwn(item, "assetPath")) {
      issues.push(`${location}.events[${index}].assetPath: audible events require an offline asset`);
    } else {
      validateSafeAssetPath(item.assetPath, `${location}.events[${index}].assetPath`, issues);
    }
    if (item.role === "narration") {
      if (!Object.hasOwn(item, "narrationBinding")) {
        issues.push(`${location}.events[${index}].narrationBinding: narration cues require manuscript digest and scope`);
      } else {
        validateNarrationCueBinding(item.narrationBinding, `${location}.events[${index}].narrationBinding`, issues);
      }
    } else if (Object.hasOwn(item, "narrationBinding")) {
      issues.push(`${location}.events[${index}].narrationBinding: only narration cues can bind manuscript text`);
    }
  }
  requireUnique(events.filter(isRecord).map((event) => event.cueID), `${location}.events.cueID`, issues);
  const haptics = arrayValue(record.haptics, `${location}.haptics`, issues);
  for (const [index, haptic] of haptics.entries()) {
    const item = shape(haptic, `${location}.haptics[${index}]`, ["sample", "kind", "intensity", "sharpness"], [], issues);
    if (!item) continue;
    integer(item.sample, `${location}.haptics[${index}].sample`, issues, 0);
    enumValue(item.kind, hapticKinds, `${location}.haptics[${index}].kind`, issues);
    for (const key of ["intensity", "sharpness"]) {
      if (finiteNumber(item[key], `${location}.haptics[${index}].${key}`, issues) && (item[key] < 0 || item[key] > 1)) {
        issues.push(`${location}.haptics[${index}].${key}: must be in unit space`);
      }
    }
  }
}

function authoredTimelineDuration(timeline) {
  if (!isRecord(timeline)) return 0;
  const eventEnd = (timeline.events ?? []).filter(isRecord).reduce((maximum, event) =>
    Number.isSafeInteger(event.startSample) && Number.isSafeInteger(event.durationSamples)
      ? Math.max(maximum, event.startSample + event.durationSamples)
      : maximum, 0);
  return (timeline.haptics ?? []).filter(isRecord).reduce((maximum, haptic) =>
    Number.isSafeInteger(haptic.sample) ? Math.max(maximum, haptic.sample) : maximum,
  eventEnd);
}

function validateResponsiveAudioCausalMix(
  value,
  location,
  beds,
  timelinesByID,
  loopDuration,
  issues,
) {
  const record = shape(
    value,
    location,
    ["rampDurationSamples", "layers", "states"],
    [],
    issues,
  );
  if (!record) return;

  const rampIsInteger = integer(
    record.rampDurationSamples,
    `${location}.rampDurationSamples`,
    issues,
    1,
  );
  if (rampIsInteger
      && (record.rampDurationSamples > maximumDeterministicAudioRampSamples
        || (Number.isSafeInteger(loopDuration) && record.rampDurationSamples > loopDuration))) {
    issues.push(
      `${location}.rampDurationSamples: must fit one deterministic audio-unit ramp and be no longer than the shared interaction loop`,
    );
  }

  const layers = arrayValue(record.layers, `${location}.layers`, issues, 1);
  const layerOrder = [];
  for (const [index, layer] of layers.entries()) {
    const item = shape(
      layer,
      `${location}.layers[${index}]`,
      ["id", "assetPath", "cueIDs"],
      [],
      issues,
    );
    if (!item) continue;
    stableID(item.id, `${location}.layers[${index}].id`, issues);
    validateSafeAssetPath(item.assetPath, `${location}.layers[${index}].assetPath`, issues);
    const cueIDs = shape(
      item.cueIDs,
      `${location}.layers[${index}].cueIDs`,
      ["waiting", "engaged", "resistance"],
      [],
      issues,
    );
    if (cueIDs) {
      for (const phase of responsiveAudioPhases) {
        stableID(cueIDs[phase], `${location}.layers[${index}].cueIDs.${phase}`, issues);
      }
    }
    layerOrder.push(item.id);
  }
  requireUnique(layerOrder, `${location}.layers.id`, issues);
  for (const phase of responsiveAudioPhases) {
    requireUnique(
      layers.filter(isRecord).map((layer) => layer.cueIDs?.[phase]),
      `${location}.layers.cueIDs.${phase}`,
      issues,
    );
  }

  const states = arrayValue(record.states, `${location}.states`, issues, 1);
  const completedStageCounts = [];
  const parsedLayerGains = [];
  for (const [stateIndex, state] of states.entries()) {
    const item = shape(
      state,
      `${location}.states[${stateIndex}]`,
      ["completedStageCount", "layerGains"],
      [],
      issues,
    );
    if (!item) continue;
    integer(
      item.completedStageCount,
      `${location}.states[${stateIndex}].completedStageCount`,
      issues,
      0,
    );
    completedStageCounts.push(item.completedStageCount);
    const gains = arrayValue(
      item.layerGains,
      `${location}.states[${stateIndex}].layerGains`,
      issues,
      1,
    );
    const stateGains = [];
    for (const [gainIndex, gain] of gains.entries()) {
      const target = shape(
        gain,
        `${location}.states[${stateIndex}].layerGains[${gainIndex}]`,
        ["layerID", "gain"],
        [],
        issues,
      );
      if (!target) continue;
      stableID(
        target.layerID,
        `${location}.states[${stateIndex}].layerGains[${gainIndex}].layerID`,
        issues,
      );
      if (finiteNumber(
        target.gain,
        `${location}.states[${stateIndex}].layerGains[${gainIndex}].gain`,
        issues,
      ) && (target.gain < 0 || target.gain > 4)) {
        issues.push(
          `${location}.states[${stateIndex}].layerGains[${gainIndex}].gain: linear gain must be between zero and four`,
        );
      }
      stateGains.push(target);
    }
    if (JSON.stringify(stateGains.map(({ layerID }) => layerID))
        !== JSON.stringify(layerOrder)) {
      issues.push(
        `${location}.states[${stateIndex}].layerGains: every state must cover every layer exactly once in authored layer order`,
      );
    }
    parsedLayerGains.push(stateGains);
  }
  const expectedStageCounts = Array.from({ length: states.length }, (_, index) => index);
  if (JSON.stringify(completedStageCounts) !== JSON.stringify(expectedStageCounts)) {
    issues.push(`${location}.states.completedStageCount: states must be ordered and contiguous from zero`);
  }

  if (parsedLayerGains.length === 0 || layerOrder.length === 0) return;
  const initialGains = new Map(
    parsedLayerGains[0].map(({ layerID, gain }) => [layerID, gain]),
  );
  for (const [layerIndex, layer] of layers.filter(isRecord).entries()) {
    let sharedSignature;
    for (const phase of responsiveAudioPhases) {
      const bed = beds.find((candidate) => isRecord(candidate) && candidate.phase === phase);
      const timeline = bed ? timelinesByID.get(bed.timelineID) : undefined;
      const cueID = layer.cueIDs?.[phase];
      if (!timeline || typeof cueID !== "string") continue;
      const event = (timeline.events ?? []).find((candidate) => candidate?.cueID === cueID);
      if (!event) {
        issues.push(`${location}.layers[${layerIndex}].cueIDs.${phase}: missing audio cue '${cueID}'`);
        continue;
      }
      if (!["soundscape", "spatialDetail"].includes(event.role)
          || event.assetPath !== layer.assetPath
          || event.gain !== initialGains.get(layer.id)) {
        issues.push(
          `${location}.layers[${layerIndex}]: mapped cues must be material roles using the explicit shared asset path and state-zero gain`,
        );
      }
      const signature = [event.role, event.startSample, event.durationSamples, layer.assetPath];
      if (sharedSignature && JSON.stringify(signature) !== JSON.stringify(sharedSignature)) {
        issues.push(
          `${location}.layers[${layerIndex}]: all phase cues must share role, start, duration and asset path`,
        );
      } else if (!sharedSignature) {
        sharedSignature = signature;
      }
    }
    if (sharedSignature
        && (sharedSignature[1] !== 0 || sharedSignature[2] !== loopDuration)) {
      issues.push(
        `${location}.layers[${layerIndex}]: shared material geometry must span the complete loop from sample zero`,
      );
    }
  }
}

function validateResponsiveAudioProgram(value, location, timelinesByID, issues) {
  const record = shape(value, location,
    ["id", "scope", "approachTimelineID", "interactionBeds", "consequenceTimelineID", "exitPolicy"],
    ["causalMix"], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  const scope = shape(record.scope, `${location}.scope`,
    ["chapterID", "arcID", "beatID", "interactionID"], [], issues);
  if (scope) {
    for (const key of ["chapterID", "arcID", "beatID", "interactionID"]) {
      stableID(scope[key], `${location}.scope.${key}`, issues);
    }
  }
  stableID(record.approachTimelineID, `${location}.approachTimelineID`, issues);
  stableID(record.consequenceTimelineID, `${location}.consequenceTimelineID`, issues);
  const exitPolicy = shape(record.exitPolicy, `${location}.exitPolicy`,
    ["kind", "durationSamples"], [], issues);
  let exitDurationSamples;
  if (exitPolicy) {
    enumValue(
      exitPolicy.kind,
      responsiveAudioExitPolicyKinds,
      `${location}.exitPolicy.kind`,
      issues,
    );
    if (integer(
      exitPolicy.durationSamples,
      `${location}.exitPolicy.durationSamples`,
      issues,
      1,
    )) {
      exitDurationSamples = exitPolicy.durationSamples;
      if (exitDurationSamples > maximumDeterministicAudioRampSamples) {
        issues.push(
          `${location}.exitPolicy.durationSamples: must fit one sample-accurate audio-unit ramp`,
        );
      }
    }
  }
  const beds = arrayValue(record.interactionBeds, `${location}.interactionBeds`, issues, 3);
  for (const [index, bed] of beds.entries()) {
    const item = shape(bed, `${location}.interactionBeds[${index}]`,
      ["phase", "timelineID", "layerStates"], [], issues);
    if (!item) continue;
    enumValue(item.phase, responsiveAudioPhases, `${location}.interactionBeds[${index}].phase`, issues);
    stableID(item.timelineID, `${location}.interactionBeds[${index}].timelineID`, issues);
    const states = shape(item.layerStates, `${location}.interactionBeds[${index}].layerStates`,
      [], ["scoreStateID", "soundscapeStateID"], issues);
    if (states) {
      for (const key of ["scoreStateID", "soundscapeStateID"]) {
        if (Object.hasOwn(states, key)) stableID(states[key], `${location}.interactionBeds[${index}].layerStates.${key}`, issues);
      }
    }
  }
  const phases = beds.filter(isRecord).map((bed) => bed.phase);
  if (beds.length !== 3 || phases.length !== 3
      || phases.some((phase) => !responsiveAudioPhases.has(phase))
      || new Set(phases).size !== 3) {
    issues.push(`${location}.interactionBeds: requires exactly one waiting, engaged and resistance bed`);
  }
  const timelineIDs = [record.approachTimelineID, record.consequenceTimelineID,
    ...beds.filter(isRecord).map((bed) => bed.timelineID)];
  if (new Set(timelineIDs).size !== timelineIDs.length) {
    issues.push(`${location}.timelineIDs: each program region requires its own authored timeline`);
  }
  const timelines = [];
  for (const timelineID of timelineIDs) {
    const timeline = timelinesByID.get(timelineID);
    if (!timeline) {
      issues.push(`${location}.timelineIDs: missing audio timeline '${timelineID}'`);
      continue;
    }
    timelines.push(timeline);
    if (authoredTimelineDuration(timeline) <= 0) {
      issues.push(`${location}.timelineIDs: timeline '${timelineID}' must have a positive authored duration`);
    }
  }
  const consequenceTimeline = timelinesByID.get(record.consequenceTimelineID);
  if (consequenceTimeline && exitDurationSamples !== undefined
      && exitDurationSamples > authoredTimelineDuration(consequenceTimeline)) {
    issues.push(
      `${location}.exitPolicy.durationSamples: must not exceed the full authored consequence timeline`,
    );
  }
  const bedDurations = new Set();
  for (const [index, bed] of beds.filter(isRecord).entries()) {
    const timeline = timelinesByID.get(bed.timelineID);
    if (!timeline) continue;
    const loopDuration = authoredTimelineDuration(timeline);
    if (loopDuration > maximumResponsiveAudioLoopSamples) {
      issues.push(`${location}.interactionBeds[${index}]: loop duration must not exceed UInt32.max samples`);
    }
    for (const event of (timeline.events ?? []).filter(isRecord)) {
      if (event.role !== "silence"
          && Number.isSafeInteger(event.durationSamples)
          && event.durationSamples <= 0) {
        issues.push(
          `${location}.interactionBeds[${index}]: audible event '${event.cueID}' must have positive duration`,
        );
      }
    }
    if ((timeline.events ?? []).some((event) => event?.role === "narration")) {
      issues.push(`${location}.interactionBeds[${index}]: an indefinite interaction bed cannot contain narration`);
    }
    if ((timeline.haptics ?? []).length > 0) {
      issues.push(`${location}.interactionBeds[${index}]: looped beds cannot repeat authored haptics`);
    }
    const hasScore = (timeline.events ?? []).some((event) => event?.role === "score");
    const hasSoundscape = (timeline.events ?? []).some((event) => event?.role === "soundscape");
    const hasScoreState = typeof bed.layerStates?.scoreStateID === "string";
    const hasSoundscapeState = typeof bed.layerStates?.soundscapeStateID === "string";
    if (hasScore !== hasScoreState || hasSoundscape !== hasSoundscapeState) {
      issues.push(`${location}.interactionBeds[${index}].layerStates: named score and soundscape states must exactly match audible timeline roles`);
    }
    bedDurations.add(loopDuration);
  }
  if (bedDurations.size !== 1) {
    issues.push(`${location}.interactionBeds: all phase beds must share one sample-exact loop duration`);
  }
  if (Object.hasOwn(record, "causalMix")) {
    validateResponsiveAudioCausalMix(
      record.causalMix,
      `${location}.causalMix`,
      beds,
      timelinesByID,
      bedDurations.size === 1 ? [...bedDurations][0] : undefined,
      issues,
    );
  }
}

function accessibilityTokenKey(token) {
  if (!isRecord(token)) return "invalid";
  return [token.command, token.targetID ?? "", token.unitsPerStep ?? "", token.step ?? ""].join(":");
}

function validateAccessibilityActionToken(value, location, issues) {
  if (!isRecord(value)) {
    issues.push(`${location}: typed semantic action token object required`);
    return;
  }
  const commandValid = enumValue(value.command, accessibilityTokenCommands, `${location}.command`, issues);
  if (!commandValid) {
    shape(value, location, ["command"], [], issues);
    return;
  }
  if (["trace-next", "commit-allocation", "hold-pressure"].includes(value.command)) {
    shape(value, location, ["command"], [], issues);
    return;
  }
  if (value.command === "allocate") {
    const record = shape(value, location, ["command", "targetID", "unitsPerStep"], [], issues);
    if (!record) return;
    stableID(record.targetID, `${location}.targetID`, issues);
    integer(record.unitsPerStep, `${location}.unitsPerStep`, issues, 1);
    return;
  }
  if (value.command === "place-component") {
    const record = shape(value, location, ["command", "targetID"], [], issues);
    if (record) stableID(record.targetID, `${location}.targetID`, issues);
    return;
  }
  const record = shape(value, location, ["command", "targetID", "step"], [], issues);
  if (!record) return;
  stableID(record.targetID, `${location}.targetID`, issues);
  if (finiteNumber(record.step, `${location}.step`, issues)
      && (record.step <= 0 || record.step > 1)) {
    issues.push(`${location}.step: must be greater than zero and at most one`);
  }
}

function validateAccessibility(value, location, issues) {
  const record = shape(value, location, ["id", "sceneSummary", "elements"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  validateLocalizedString(record.sceneSummary, `${location}.sceneSummary`, issues);
  const elements = arrayValue(record.elements, `${location}.elements`, issues, 1);
  for (const [index, element] of elements.entries()) {
    const item = shape(element, `${location}.elements[${index}]`, ["id", "role", "label", "actions"], ["value", "hint"], issues);
    if (!item) continue;
    stableID(item.id, `${location}.elements[${index}].id`, issues);
    enumValue(item.role, accessibilityRoles, `${location}.elements[${index}].role`, issues);
    validateLocalizedString(item.label, `${location}.elements[${index}].label`, issues);
    if (Object.hasOwn(item, "value")) validateLocalizedString(item.value, `${location}.elements[${index}].value`, issues);
    if (Object.hasOwn(item, "hint")) validateLocalizedString(item.hint, `${location}.elements[${index}].hint`, issues);
    const actions = arrayValue(item.actions, `${location}.elements[${index}].actions`, issues);
    const operable = item.role === "action" || item.role === "adjustable";
    if (operable !== (actions.length > 0)) {
      issues.push(`${location}.elements[${index}].actions: action and adjustable elements must be operable; descriptive elements cannot carry actions`);
    }
    for (const [actionIndex, action] of actions.entries()) {
      const actionRecord = shape(action, `${location}.elements[${index}].actions[${actionIndex}]`, ["kind", "label", "token"], [], issues);
      if (!actionRecord) continue;
      enumValue(actionRecord.kind, accessibilityActionKinds, `${location}.elements[${index}].actions[${actionIndex}].kind`, issues);
      validateLocalizedString(actionRecord.label, `${location}.elements[${index}].actions[${actionIndex}].label`, issues);
      validateAccessibilityActionToken(actionRecord.token, `${location}.elements[${index}].actions[${actionIndex}].token`, issues);
      if (item.role === "action" && actionRecord.kind !== "activate") {
        issues.push(`${location}.elements[${index}].actions[${actionIndex}].kind: action elements activate`);
      }
      if (item.role === "adjustable" && !["increment", "decrement"].includes(actionRecord.kind)) {
        issues.push(`${location}.elements[${index}].actions[${actionIndex}].kind: adjustable elements increment or decrement`);
      }
    }
    requireUnique(
      actions.filter(isRecord).map((action) => `${action.kind}:${accessibilityTokenKey(action.token)}`),
      `${location}.elements[${index}].actions.binding`,
      issues,
    );
  }
  requireUnique(elements.filter(isRecord).map((element) => element.id), `${location}.elements.id`, issues);
}

function accessibilityBindings(specification) {
  if (!isRecord(specification) || !Array.isArray(specification.elements)) return [];
  return specification.elements.filter(isRecord).flatMap((element) =>
    (Array.isArray(element.actions) ? element.actions : []).filter(isRecord).map((action) => ({
      elementID: element.id,
      ...action,
    }))
  );
}

function matchingBindings(bindings, kind, command, targetID) {
  return bindings.filter((binding) => binding.kind === kind
    && binding.token?.command === command
    && (targetID === undefined || binding.token?.targetID === targetID));
}

function requireOneAccessibilityBinding(bindings, kind, command, targetID, location, issues) {
  const matches = matchingBindings(bindings, kind, command, targetID);
  if (matches.length !== 1) {
    const target = targetID === undefined ? "" : ` for '${targetID}'`;
    issues.push(`${location}: requires exactly one ${kind} ${command}${target} binding`);
  }
  return matches[0];
}

function initialParityState(interaction) {
  const state = { phase: "ready", progress: {} };
  const configuration = interaction.configuration;
  if (interaction.grammar === "trace") {
    state.progress = { reachedAnchorCount: 0 };
  } else if (interaction.grammar === "allocate") {
    state.progress = { allocations: Object.fromEntries(configuration.destinations.map((item) => [item.id, 0])) };
  } else if (interaction.grammar === "assemble") {
    state.progress = { placements: new Set() };
  } else if (interaction.grammar === "pressure") {
    state.progress = {
      values: Object.fromEntries(configuration.forces.map((item) => [item.id, item.initialMagnitude])),
      stableMillis: 0,
    };
  } else if (interaction.grammar === "transform") {
    state.progress = { completedStageCount: 0, currentAmount: 0 };
  }
  return state;
}

function reduceParityState(state, interaction, action) {
  if (state.phase === "complete") return [];
  state.phase = "active";
  const configuration = interaction.configuration;
  let completed = false;
  if (interaction.grammar === "trace" && action.type === "trace") {
    const anchor = configuration.anchors[state.progress.reachedAnchorCount];
    const distance = Math.hypot(anchor.x - action.point.x, anchor.y - action.point.y);
    if (distance <= configuration.tolerance) state.progress.reachedAnchorCount += 1;
    completed = state.progress.reachedAnchorCount === configuration.anchors.length;
  } else if (interaction.grammar === "allocate" && action.type === "allocate") {
    const known = configuration.destinations.some((item) => item.id === action.destinationID);
    const otherUnits = Object.entries(state.progress.allocations)
      .filter(([id]) => id !== action.destinationID)
      .reduce((sum, [, units]) => sum + units, 0);
    if (!known || action.units < 0 || otherUnits + action.units > configuration.totalUnits) return [];
    state.progress.allocations[action.destinationID] = action.units;
  } else if (interaction.grammar === "allocate" && action.type === "commit-allocation") {
    const allocatedUnits = Object.values(state.progress.allocations)
      .reduce((sum, units) => sum + units, 0);
    completed = allocatedUnits === configuration.totalUnits
      && configuration.destinations.every((item) =>
        state.progress.allocations[item.id] >= item.minimumUnits);
  } else if (interaction.grammar === "assemble" && action.type === "place") {
    const component = configuration.components.find((item) => item.id === action.componentID);
    if (!component || component.targetSlot !== action.slotID
        || state.progress.placements.has(component.id)
        || !component.prerequisites.every((id) => state.progress.placements.has(id))) return [];
    state.progress.placements.add(component.id);
    completed = state.progress.placements.size === configuration.components.length;
  } else if (interaction.grammar === "pressure" && action.type === "set-pressure") {
    const force = configuration.forces.find((item) => item.id === action.forceID);
    if (!force?.userControllable || action.magnitude < 0 || action.magnitude > 1) return [];
    state.progress.values[action.forceID] = action.magnitude;
  } else if (interaction.grammar === "pressure" && action.type === "advance-pressure") {
    const net = configuration.forces.reduce((sum, force) =>
      sum + force.direction * state.progress.values[force.id], 0);
    if (net >= configuration.stableRange[0] - 1e-9 && net <= configuration.stableRange[1] + 1e-9) {
      state.progress.stableMillis += action.elapsedMillis;
    } else {
      state.progress.stableMillis = 0;
    }
    completed = state.progress.stableMillis >= configuration.requiredHoldMillis;
  } else if (interaction.grammar === "transform" && action.type === "transform") {
    const stage = configuration.stages[state.progress.completedStageCount];
    if (!stage || stage.controlID !== action.controlID || action.amount < 0 || action.amount > 1) return [];
    state.progress.currentAmount = Math.max(state.progress.currentAmount, action.amount);
    if (state.progress.currentAmount >= stage.requiredAmount) {
      state.progress.completedStageCount += 1;
      state.progress.currentAmount = 0;
    }
    completed = state.progress.completedStageCount === configuration.stages.length;
  } else {
    throw new Error("action did not match the authored interaction grammar");
  }
  if (!completed) return [];
  state.phase = "complete";
  return interaction.completionEffects;
}

function semanticReducerAction(binding, interaction, state) {
  const token = binding.token;
  const configuration = interaction.configuration;
  if (interaction.grammar === "trace" && binding.kind === "increment" && token.command === "trace-next") {
    const point = configuration.anchors[state.progress.reachedAnchorCount];
    if (!point) throw new Error("trace-next is unavailable");
    return { type: "trace", point };
  }
  if (interaction.grammar === "allocate" && token.command === "allocate"
      && ["increment", "decrement"].includes(binding.kind)) {
    const current = state.progress.allocations[token.targetID];
    if (!Number.isSafeInteger(current)) throw new Error(`unknown allocation '${token.targetID}'`);
    const delta = binding.kind === "increment" ? token.unitsPerStep : -token.unitsPerStep;
    const units = Math.min(Math.max(current + delta, 0), configuration.totalUnits);
    if (units === current) throw new Error(`allocation '${token.targetID}' cannot move`);
    return { type: "allocate", destinationID: token.targetID, units };
  }
  if (interaction.grammar === "allocate" && binding.kind === "activate"
      && token.command === "commit-allocation") return { type: "commit-allocation" };
  if (interaction.grammar === "assemble" && binding.kind === "activate"
      && token.command === "place-component") {
    const component = configuration.components.find((item) => item.id === token.targetID);
    if (!component || !component.prerequisites.every((id) => state.progress.placements.has(id))) {
      throw new Error(`component '${token.targetID}' is unavailable`);
    }
    return { type: "place", componentID: component.id, slotID: component.targetSlot };
  }
  if (interaction.grammar === "pressure" && token.command === "adjust-pressure"
      && ["increment", "decrement"].includes(binding.kind)) {
    const current = state.progress.values[token.targetID];
    if (!Number.isFinite(current)) throw new Error(`unknown pressure force '${token.targetID}'`);
    const delta = binding.kind === "increment" ? token.step : -token.step;
    const magnitude = Math.min(Math.max(current + delta, 0), 1);
    if (Math.abs(magnitude - current) <= 1e-9) throw new Error(`pressure force '${token.targetID}' cannot move`);
    return { type: "set-pressure", forceID: token.targetID, magnitude };
  }
  if (interaction.grammar === "pressure" && binding.kind === "activate"
      && token.command === "hold-pressure") {
    return {
      type: "advance-pressure",
      elapsedMillis: Math.min(Math.max(configuration.requiredHoldMillis - state.progress.stableMillis, 1), 1000),
    };
  }
  if (interaction.grammar === "transform" && binding.kind === "increment"
      && token.command === "advance-transform") {
    const stage = configuration.stages[state.progress.completedStageCount];
    if (!stage || stage.id !== token.targetID) throw new Error(`transform stage '${token.targetID}' is unavailable`);
    return {
      type: "transform",
      controlID: stage.controlID,
      amount: Math.min(state.progress.currentAmount + token.step, 1),
    };
  }
  throw new Error(`semantic token '${token?.command}' is unbound`);
}

function pressureTarget(interaction, bindings) {
  if (interaction.grammar !== "pressure") return null;
  const configuration = interaction.configuration;
  const fixed = configuration.forces.filter((force) => !force.userControllable)
    .reduce((sum, force) => sum + force.direction * force.initialMagnitude, 0);
  const controls = configuration.forces.filter((force) => force.userControllable).map((force) => {
    const binding = matchingBindings(bindings, "increment", "adjust-pressure", force.id)[0];
    const step = binding.token.step;
    const reachable = new Set([Number(force.initialMagnitude.toFixed(9))]);
    for (let value = force.initialMagnitude; value < 1 - 1e-9;) {
      value = Math.min(value + step, 1);
      reachable.add(Number(value.toFixed(9)));
    }
    for (let value = force.initialMagnitude; value > 1e-9;) {
      value = Math.max(value - step, 0);
      reachable.add(Number(value.toFixed(9)));
    }
    return {
      ...force,
      values: [...reachable].sort((a, b) => Math.abs(a - force.initialMagnitude) - Math.abs(b - force.initialMagnitude)),
    };
  });
  const suffixMin = Array(controls.length + 1).fill(0);
  const suffixMax = Array(controls.length + 1).fill(0);
  for (let index = controls.length - 1; index >= 0; index -= 1) {
    const contributions = controls[index].values.map((value) => controls[index].direction * value);
    suffixMin[index] = suffixMin[index + 1] + Math.min(...contributions);
    suffixMax[index] = suffixMax[index + 1] + Math.max(...contributions);
  }
  const result = {};
  let visited = 0;
  function search(index, net) {
    visited += 1;
    if (visited > 200_000) return false;
    if (net + suffixMax[index] < configuration.stableRange[0] - 1e-9
        || net + suffixMin[index] > configuration.stableRange[1] + 1e-9) return false;
    if (index === controls.length) {
      return net >= configuration.stableRange[0] - 1e-9 && net <= configuration.stableRange[1] + 1e-9;
    }
    const force = controls[index];
    for (const value of force.values) {
      result[force.id] = value;
      if (search(index + 1, net + force.direction * value)) return true;
    }
    delete result[force.id];
    return false;
  }
  if (!search(0, fixed)) throw new Error("discrete VoiceOver pressure path cannot reach the stable range");
  return result;
}

function simulateAccessibilityParity(interaction, accessibility) {
  const bindings = accessibilityBindings(accessibility);
  const target = pressureTarget(interaction, bindings);
  const standard = initialParityState(interaction);
  const voiceOver = initialParityState(interaction);
  let standardEffects = [];
  let voiceOverEffects = [];
  let operations = 0;
  const standardApply = (action) => {
    const effects = reduceParityState(standard, interaction, action);
    if (effects.length) standardEffects = effects;
  };
  const voiceOverApply = (binding) => {
    operations += 1;
    if (operations > 100_000) throw new Error("VoiceOver path exceeded the deterministic operation limit");
    const effects = reduceParityState(voiceOver, interaction, semanticReducerAction(binding, interaction, voiceOver));
    if (effects.length) voiceOverEffects = effects;
  };
  const one = (kind, command, targetID) => matchingBindings(bindings, kind, command, targetID)[0];

  if (interaction.grammar === "trace") {
    for (const anchor of interaction.configuration.anchors) standardApply({ type: "trace", point: anchor });
    for (const _anchor of interaction.configuration.anchors) voiceOverApply(one("increment", "trace-next"));
  } else if (interaction.grammar === "allocate") {
    const minimumTotal = interaction.configuration.destinations
      .reduce((sum, destination) => sum + destination.minimumUnits, 0);
    const surplus = interaction.configuration.totalUnits - minimumTotal;
    for (const [index, destination] of interaction.configuration.destinations.entries()) {
      const targetUnits = destination.minimumUnits + (index === 0 ? surplus : 0);
      standardApply({ type: "allocate", destinationID: destination.id, units: targetUnits });
      while (voiceOver.progress.allocations[destination.id] !== targetUnits) {
        voiceOverApply(one("increment", "allocate", destination.id));
      }
    }
    standardApply({ type: "commit-allocation" });
    voiceOverApply(one("activate", "commit-allocation"));
  } else if (interaction.grammar === "assemble") {
    let remaining = [...interaction.configuration.components];
    while (remaining.length) {
      const component = remaining.find((item) => item.prerequisites.every((id) => standard.progress.placements.has(id)));
      standardApply({ type: "place", componentID: component.id, slotID: component.targetSlot });
      remaining = remaining.filter((item) => item.id !== component.id);
    }
    remaining = [...interaction.configuration.components];
    while (remaining.length) {
      const component = remaining.find((item) => item.prerequisites.every((id) => voiceOver.progress.placements.has(id)));
      voiceOverApply(one("activate", "place-component", component.id));
      remaining = remaining.filter((item) => item.id !== component.id);
    }
  } else if (interaction.grammar === "pressure") {
    for (const force of interaction.configuration.forces.filter((item) => item.userControllable)) {
      standardApply({ type: "set-pressure", forceID: force.id, magnitude: target[force.id] });
      while (Math.abs(voiceOver.progress.values[force.id] - target[force.id]) > 1e-9) {
        const kind = voiceOver.progress.values[force.id] < target[force.id] ? "increment" : "decrement";
        voiceOverApply(one(kind, "adjust-pressure", force.id));
      }
    }
    while (standard.phase !== "complete") {
      standardApply({
        type: "advance-pressure",
        elapsedMillis: Math.min(Math.max(interaction.configuration.requiredHoldMillis - standard.progress.stableMillis, 1), 1000),
      });
    }
    while (voiceOver.phase !== "complete") voiceOverApply(one("activate", "hold-pressure"));
  } else if (interaction.grammar === "transform") {
    for (const stage of interaction.configuration.stages) {
      standardApply({ type: "transform", controlID: stage.controlID, amount: stage.requiredAmount });
      while (voiceOver.progress.completedStageCount < interaction.configuration.stages.length
          && interaction.configuration.stages[voiceOver.progress.completedStageCount].id === stage.id) {
        voiceOverApply(one("increment", "advance-transform", stage.id));
      }
    }
  }
  if (standard.phase !== "complete" || voiceOver.phase !== "complete") {
    throw new Error("standard or VoiceOver interaction path did not complete");
  }
  const expected = JSON.stringify(interaction.completionEffects);
  if (JSON.stringify(standardEffects) !== expected || JSON.stringify(voiceOverEffects) !== expected) {
    throw new Error("VoiceOver path diverged from the standard historical consequence");
  }
}

function validateAccessibilityBinding(interaction, accessibility, location, issues) {
  const startIssueCount = issues.length;
  const bindings = accessibilityBindings(accessibility);
  const configuration = interaction.configuration;
  for (const binding of bindings) {
    const command = binding.token?.command;
    let bound = false;
    if (interaction.grammar === "trace") {
      bound = command === "trace-next" && binding.kind === "increment";
    } else if (interaction.grammar === "allocate") {
      bound = (command === "allocate" && ["increment", "decrement"].includes(binding.kind)
        && configuration.destinations.some((item) => item.id === binding.token.targetID))
        || (command === "commit-allocation" && binding.kind === "activate");
    } else if (interaction.grammar === "assemble") {
      bound = command === "place-component" && binding.kind === "activate"
        && configuration.components.some((item) => item.id === binding.token.targetID);
    } else if (interaction.grammar === "pressure") {
      bound = (command === "adjust-pressure" && ["increment", "decrement"].includes(binding.kind)
        && configuration.forces.some((item) => item.id === binding.token.targetID && item.userControllable))
        || (command === "hold-pressure" && binding.kind === "activate");
    } else if (interaction.grammar === "transform") {
      bound = command === "advance-transform" && binding.kind === "increment"
        && configuration.stages.some((item) => item.id === binding.token.targetID);
    }
    if (!bound) issues.push(`${location}: semantic token '${command}' is unbound to ${interaction.grammar}`);
  }

  if (interaction.grammar === "trace") {
    requireOneAccessibilityBinding(bindings, "increment", "trace-next", undefined, location, issues);
  } else if (interaction.grammar === "allocate") {
    const minimumTotal = configuration.destinations
      .reduce((sum, destination) => sum + destination.minimumUnits, 0);
    const surplus = configuration.totalUnits - minimumTotal;
    for (const [index, destination] of configuration.destinations.entries()) {
      const increment = requireOneAccessibilityBinding(bindings, "increment", "allocate", destination.id, location, issues);
      const decrement = requireOneAccessibilityBinding(bindings, "decrement", "allocate", destination.id, location, issues);
      if (increment && decrement && (increment.token.unitsPerStep !== decrement.token.unitsPerStep
          || (destination.minimumUnits + (index === 0 ? surplus : 0))
            % increment.token.unitsPerStep !== 0)) {
        issues.push(`${location}: allocation steps for '${destination.id}' must match and reach one complete minimum-plus-surplus distribution`);
      }
    }
    requireOneAccessibilityBinding(bindings, "activate", "commit-allocation", undefined, location, issues);
  } else if (interaction.grammar === "assemble") {
    for (const component of configuration.components) {
      requireOneAccessibilityBinding(bindings, "activate", "place-component", component.id, location, issues);
    }
  } else if (interaction.grammar === "pressure") {
    for (const force of configuration.forces.filter((item) => item.userControllable)) {
      const increment = requireOneAccessibilityBinding(bindings, "increment", "adjust-pressure", force.id, location, issues);
      const decrement = requireOneAccessibilityBinding(bindings, "decrement", "adjust-pressure", force.id, location, issues);
      if (increment && decrement && Math.abs(increment.token.step - decrement.token.step) > 1e-9) {
        issues.push(`${location}: pressure steps for '${force.id}' must match`);
      }
    }
    requireOneAccessibilityBinding(bindings, "activate", "hold-pressure", undefined, location, issues);
  } else if (interaction.grammar === "transform") {
    for (const stage of configuration.stages) {
      requireOneAccessibilityBinding(bindings, "increment", "advance-transform", stage.id, location, issues);
    }
  }

  if (issues.length === startIssueCount) {
    try {
      simulateAccessibilityParity(interaction, accessibility);
    } catch (error) {
      issues.push(`${location}: VoiceOver parity failed: ${error.message}`);
    }
  }
}

function validateSceneVisualBindingToInteraction(scene, interaction, location, issues) {
  const binding = scene?.interactionVisualBinding;
  if (!isRecord(binding)) return;
  const configuration = binding.configuration;
  if (binding.grammar !== interaction.grammar || !isRecord(configuration)) {
    issues.push(`${location}: grammar must match the bound interaction`);
    return;
  }
  if (configuration.interactionID !== interaction.id) {
    issues.push(`${location}.configuration.interactionID: must equal '${interaction.id}'`);
  }
  if (interaction.grammar === "trace") {
    const anchorIDs = interaction.configuration?.anchorIDs;
    const reachedAnchorVariants = configuration.reachedAnchorVariants;
    if (Array.isArray(anchorIDs) && Array.isArray(reachedAnchorVariants)) {
      const boundIDs = reachedAnchorVariants.filter(isRecord).map(({ anchorID }) => anchorID);
      if (JSON.stringify(boundIDs) !== JSON.stringify(anchorIDs.slice(0, -1))) {
        issues.push(
          `${location}.configuration.reachedAnchorVariants: must bind every nonterminal Trace anchor in authored order and by exact identity`,
        );
      }
    } else if (anchorIDs !== undefined || reachedAnchorVariants !== undefined) {
      issues.push(
        `${location}.configuration.reachedAnchorVariants: named Trace anchors and reached-anchor visual bindings must be authored together`,
      );
    }
    return;
  }
  if (interaction.grammar === "allocate" && isRecord(interaction.configuration)) {
    const boundDestinationIDs = Array.isArray(configuration.destinations)
      ? configuration.destinations.filter(isRecord).map((destination) => destination.destinationID).sort()
      : [];
    const interactionDestinationIDs = Array.isArray(interaction.configuration.destinations)
      ? interaction.configuration.destinations.filter(isRecord).map((destination) => destination.id).sort()
      : [];
    if (JSON.stringify(boundDestinationIDs) !== JSON.stringify(interactionDestinationIDs)) {
      issues.push(`${location}.configuration.destinations: must bind every and only authored allocation destination`);
    }
    const thresholds = configuration.resource?.variantsByRemainingUnits;
    if (!Array.isArray(thresholds)
        || thresholds.at(-1)?.maximumRemainingUnits !== interaction.configuration.totalUnits
        || thresholds.some((threshold) => threshold.maximumRemainingUnits > interaction.configuration.totalUnits)) {
      issues.push(`${location}.configuration.resource.variantsByRemainingUnits: must end at the interaction's finite resource total`);
    }
  } else if (interaction.grammar === "assemble" && isRecord(interaction.configuration)) {
    const bound = (configuration.components ?? []).filter(isRecord).map((item) => item.componentID).sort();
    const expected = (interaction.configuration.components ?? []).filter(isRecord).map((item) => item.id).sort();
    if (JSON.stringify(bound) !== JSON.stringify(expected)) {
      issues.push(`${location}.configuration.components: must bind every and only authored assembly component`);
    }
  } else if (interaction.grammar === "pressure" && isRecord(interaction.configuration)) {
    const forceByID = new Map((interaction.configuration.forces ?? []).filter(isRecord).map((item) => [item.id, item]));
    const bound = (configuration.forces ?? []).filter(isRecord);
    if (JSON.stringify(bound.map((item) => item.forceID).sort())
        !== JSON.stringify([...forceByID.keys()].sort())
        || bound.some((item) => forceByID.get(item.forceID)?.userControllable
          !== Object.hasOwn(item, "interactionTargetID"))) {
      issues.push(`${location}.configuration.forces: must bind every force and only controllable forces to targets`);
    }
  } else if (interaction.grammar === "transform" && isRecord(interaction.configuration)) {
    const bound = (configuration.stages ?? []).filter(isRecord).map((item) => item.stageID).sort();
    const expected = (interaction.configuration.stages ?? []).filter(isRecord).map((item) => item.id).sort();
    if (JSON.stringify(bound) !== JSON.stringify(expected)) {
      issues.push(`${location}.configuration.stages: must bind every and only authored transformation stage`);
    }
  }
}

function validateShippingRuntimeVisualBinding(scene, interaction, location, issues) {
  if (!isRecord(scene?.interactionVisualBinding)) {
    issues.push(
      `${location}.interactionVisualBinding: an interactive shipping beat requires an authored visual binding supported by the current runtime`,
    );
    return;
  }
  validateSceneVisualBindingToInteraction(
    scene,
    interaction,
    `${location}.interactionVisualBinding`,
    issues,
  );

  const configuration = scene.interactionVisualBinding.configuration;
  if (!isRecord(configuration)) return;
  let runtimeLayerIDs = [];
  if (interaction.grammar === "trace") {
    runtimeLayerIDs = [configuration.layerID];
  } else if (interaction.grammar === "allocate") {
    runtimeLayerIDs = [
      configuration.resource?.layerID,
      ...(configuration.destinations ?? []).filter(isRecord).map((item) => item.layerID),
    ];
  } else if (interaction.grammar === "assemble") {
    runtimeLayerIDs = (configuration.components ?? [])
      .filter(isRecord)
      .map((item) => item.layerID);
    if (new Set(runtimeLayerIDs).size !== runtimeLayerIDs.length) {
      issues.push(
        `${location}.interactionVisualBinding.configuration.components: each assembly component requires its own stateful runtime layer`,
      );
    }
  } else if (interaction.grammar === "pressure") {
    runtimeLayerIDs = [configuration.systemLayerID];
  } else if (interaction.grammar === "transform") {
    runtimeLayerIDs = (configuration.stages ?? [])
      .filter(isRecord)
      .map((item) => item.layerID);
  }
  const statefulLayerIDs = (scene.layers ?? [])
    .filter((layer) => isRecord(layer) && Array.isArray(layer.stateVariants)
      && layer.stateVariants.length > 0)
    .map((layer) => layer.id);
  const uniqueRuntimeLayerIDs = [...new Set(runtimeLayerIDs)].sort();
  if (JSON.stringify(uniqueRuntimeLayerIDs) !== JSON.stringify([...statefulLayerIDs].sort())) {
    issues.push(
      `${location}.interactionVisualBinding: must bind every and only stateful scene layer resolved by its runtime adapter`,
    );
  }
}

export function validateContentPackagePayload(payload, location = "contentPackage", issues = []) {
  const record = shape(payload, location,
    ["schemaVersion", "packageID", "worldSeed", "chapters", "scenes", "audioTimelines", "responsiveAudioPrograms", "accessibility"], [], issues);
  if (!record) return issues;
  validateSchemaVersion(record.schemaVersion, `${location}.schemaVersion`, issues);
  packageIdentifier(record.packageID, `${location}.packageID`, issues);
  validateWorldSeed(record.worldSeed, `${location}.worldSeed`, issues);
  const chapters = arrayValue(record.chapters, `${location}.chapters`, issues, 1);
  const scenes = arrayValue(record.scenes, `${location}.scenes`, issues, 1);
  const audioTimelines = arrayValue(record.audioTimelines, `${location}.audioTimelines`, issues, 1);
  const responsiveAudioPrograms = arrayValue(
    record.responsiveAudioPrograms,
    `${location}.responsiveAudioPrograms`,
    issues,
  );
  const accessibility = arrayValue(record.accessibility, `${location}.accessibility`, issues, 1);
  chapters.forEach((chapter, index) => validateChapter(chapter, `${location}.chapters[${index}]`, issues));
  scenes.forEach((scene, index) => validateScene(scene, `${location}.scenes[${index}]`, issues));
  audioTimelines.forEach((timeline, index) => validateAudioTimeline(timeline, `${location}.audioTimelines[${index}]`, issues));
  const timelinesByID = new Map(audioTimelines.filter(isRecord).map((timeline) => [timeline.id, timeline]));
  responsiveAudioPrograms.forEach((program, index) => validateResponsiveAudioProgram(
    program,
    `${location}.responsiveAudioPrograms[${index}]`,
    timelinesByID,
    issues,
  ));
  accessibility.forEach((spec, index) => validateAccessibility(spec, `${location}.accessibility[${index}]`, issues));
  for (const [index, chapter] of chapters.entries()) {
    if (isRecord(chapter?.schemaVersion) && isRecord(record.schemaVersion)
        && ["major", "minor", "patch"].some((key) => chapter.schemaVersion[key] !== record.schemaVersion[key])) {
      issues.push(`${location}.chapters[${index}].schemaVersion: must match contentPackage.schemaVersion`);
    }
  }

  requireUnique(chapters.filter(isRecord).map((chapter) => chapter.id), `${location}.chapters.id`, issues);
  requireUnique(scenes.filter(isRecord).map((scene) => scene.id), `${location}.scenes.id`, issues);
  requireUnique(audioTimelines.filter(isRecord).map((timeline) => timeline.id), `${location}.audioTimelines.id`, issues);
  requireUnique(responsiveAudioPrograms.filter(isRecord).map((program) => program.id), `${location}.responsiveAudioPrograms.id`, issues);
  requireUnique(accessibility.filter(isRecord).map((spec) => spec.id), `${location}.accessibility.id`, issues);

  const arcs = chapters.filter(isRecord).flatMap((chapter) => Array.isArray(chapter.arcs) ? chapter.arcs : []).filter(isRecord);
  const beats = arcs.flatMap((arc) => Array.isArray(arc.beats) ? arc.beats : []).filter(isRecord);
  const scopedBeats = chapters.filter(isRecord).flatMap((chapter) =>
    (chapter.arcs ?? []).filter(isRecord).flatMap((arc) =>
      (arc.beats ?? []).filter(isRecord).map((beat) => ({ chapter, arc, beat }))));
  const interactions = beats.map((beat) => beat.interaction).filter(isRecord);
  const effects = [
    ...chapters.flatMap((chapter) => Array.isArray(chapter.completionEffects) ? chapter.completionEffects : []),
    ...beats.flatMap((beat) => Array.isArray(beat.completionEffects) ? beat.completionEffects : []),
    ...interactions.flatMap((interaction) => Array.isArray(interaction.completionEffects) ? interaction.completionEffects : []),
  ].filter(isRecord);
  requireUnique(arcs.map((arc) => arc.id), `${location}.arcs.id`, issues);
  requireUnique(beats.map((beat) => beat.id), `${location}.beats.id`, issues);
  requireUnique(interactions.map((interaction) => interaction.id), `${location}.interactions.id`, issues);
  requireUnique(interactions.map((interaction) => interaction.accessibilityID), `${location}.interactions.accessibilityID`, issues);
  requireUnique(effects.map((effect) => effect.id), `${location}.worldEffects.id`, issues);

  const expectedResponsiveScopes = scopedBeats
    .filter(({ beat }) => isRecord(beat.interaction))
    .map(({ chapter, arc, beat }) => `${chapter.id}/${arc.id}/${beat.id}/${beat.interaction.id}`);
  const actualResponsiveScopes = responsiveAudioPrograms.filter(isRecord).map((program) =>
    `${program.scope?.chapterID}/${program.scope?.arcID}/${program.scope?.beatID}/${program.scope?.interactionID}`);
  if (actualResponsiveScopes.length !== expectedResponsiveScopes.length
      || new Set(actualResponsiveScopes).size !== actualResponsiveScopes.length
      || expectedResponsiveScopes.some((scope) => !actualResponsiveScopes.includes(scope))) {
    issues.push(`${location}.responsiveAudioPrograms.scope: every interaction requires exactly one program in its exact chapter/arc/beat scope`);
  }
  const interactionByResponsiveScope = new Map(
    scopedBeats.filter(({ beat }) => isRecord(beat.interaction)).map(({ chapter, arc, beat }) => [
      `${chapter.id}/${arc.id}/${beat.id}/${beat.interaction.id}`,
      beat.interaction,
    ]),
  );
  for (const [index, program] of responsiveAudioPrograms.entries()) {
    if (!isRecord(program) || !Object.hasOwn(program, "causalMix")) continue;
    const programScope = `${program.scope?.chapterID}/${program.scope?.arcID}/${program.scope?.beatID}/${program.scope?.interactionID}`;
    const interaction = interactionByResponsiveScope.get(programScope);
    if (!interaction || interaction.grammar !== "transform") {
      issues.push(
        `${location}.responsiveAudioPrograms[${index}].causalMix: requires the exact scoped Transform interaction`,
      );
      continue;
    }
    const stateCount = Array.isArray(program.causalMix?.states)
      ? program.causalMix.states.length
      : undefined;
    const transformStageCount = Array.isArray(interaction.configuration?.stages)
      ? interaction.configuration.stages.length
      : undefined;
    if (Number.isSafeInteger(stateCount)
        && Number.isSafeInteger(transformStageCount)
        && stateCount !== transformStageCount + 1) {
      issues.push(
        `${location}.responsiveAudioPrograms[${index}].causalMix.states: requires state zero plus exactly one state per Transform stage`,
      );
    }
  }

  const sceneIDs = new Set(scenes.filter(isRecord).map((scene) => scene.id));
  const sceneByID = new Map(scenes.filter(isRecord).map((scene) => [scene.id, scene]));
  const accessibilityIDs = new Set(accessibility.filter(isRecord).map((spec) => spec.id));
  const accessibilityByID = new Map(accessibility.filter(isRecord).map((spec) => [spec.id, spec]));
  const interactionAccessibilityIDs = new Set(interactions.map((interaction) => interaction.accessibilityID));
  const events = audioTimelines.filter(isRecord).flatMap((timeline) => Array.isArray(timeline.events) ? timeline.events : []).filter(isRecord);
  const cueIDs = events.map((event) => event.cueID);
  requireUnique(cueIDs, `${location}.audioTimelines.events.cueID`, issues);
  const narrationEvents = events.filter((event) => event.role === "narration");
  const narrationEventByCueID = new Map(narrationEvents.map((event) => [event.cueID, event]));
  const referencedNarrationCueIDs = [];
  for (const { chapter, arc, beat } of scopedBeats) {
    if (!sceneIDs.has(beat.sceneID)) issues.push(`${location}.beats.${beat.id}.sceneID: missing scene '${beat.sceneID}'`);
    for (const cueID of Array.isArray(beat.narrationCueIDs) ? beat.narrationCueIDs : []) {
      const event = narrationEventByCueID.get(cueID);
      if (!event) {
        issues.push(`${location}.beats.${beat.id}.narrationCueIDs: missing narration cue '${cueID}'`);
        continue;
      }
      referencedNarrationCueIDs.push(cueID);
      const binding = event.narrationBinding;
      const scope = binding?.scope;
      if (scope?.chapterID !== chapter.id || scope?.arcID !== arc.id || scope?.beatID !== beat.id) {
        issues.push(`${location}.audioTimelines.events.${cueID}.narrationBinding.scope: must equal '${chapter.id}/${arc.id}/${beat.id}'`);
        continue;
      }
      const manuscriptSegments = [beat.narrative?.heading, ...(beat.narrative?.paragraphs ?? [])]
        .filter(isRecord);
      const segment = manuscriptSegments.find((item) => item.id === binding?.manuscriptSegmentID);
      if (!segment) {
        issues.push(`${location}.audioTimelines.events.${cueID}.narrationBinding.manuscriptSegmentID: must identify a reading segment inside the scoped beat`);
        continue;
      }
      const digest = createHash("sha256").update(segment.launchEnglish, "utf8").digest("hex");
      if (digest !== binding.manuscriptSegmentSHA256) {
        issues.push(`${location}.audioTimelines.events.${cueID}.narrationBinding.manuscriptSegmentSHA256: does not match editor-approved English manuscript bytes`);
      }
    }
    if (isRecord(beat.interaction)) {
      const scene = sceneByID.get(beat.sceneID);
      if (scene && (!Array.isArray(scene.interactionTargets) || scene.interactionTargets.length === 0)) {
        issues.push(`${location}.scenes.${scene.id}.interactionTargets: interactive scene requires at least one real hit region`);
      }
      if (scene && scene.accessibilityID !== beat.interaction.accessibilityID) {
        issues.push(`${location}.scenes.${scene.id}.accessibilityID: must equal interaction accessibilityID '${beat.interaction.accessibilityID}'`);
      }
      if (scene) {
        validateShippingRuntimeVisualBinding(
          scene,
          beat.interaction,
          `${location}.scenes.${scene.id}`,
          issues,
        );
      }
      const accessibilitySpec = accessibilityByID.get(beat.interaction.accessibilityID);
      if (!accessibilitySpec) {
        issues.push(`${location}.interactions.${beat.interaction.id}.accessibilityID: missing accessibility spec '${beat.interaction.accessibilityID}'`);
      } else {
        const configuration = beat.interaction.configuration;
        const configurationReady = isRecord(configuration)
          && (beat.interaction.grammar === "trace" ? Array.isArray(configuration.anchors)
            : beat.interaction.grammar === "allocate" ? Array.isArray(configuration.destinations)
              : beat.interaction.grammar === "assemble" ? Array.isArray(configuration.components)
                : beat.interaction.grammar === "pressure" ? Array.isArray(configuration.forces) && Array.isArray(configuration.stableRange)
                  : beat.interaction.grammar === "transform" ? Array.isArray(configuration.stages)
                    : false);
        if (configurationReady && Array.isArray(accessibilitySpec.elements)) {
          validateAccessibilityBinding(
            beat.interaction,
            accessibilitySpec,
            `${location}.interactions.${beat.interaction.id}.accessibility`,
            issues,
          );
        }
      }
    }
  }
  requireUnique(referencedNarrationCueIDs, `${location}.beats.narrationCueIDs`, issues);
  const referencedSet = new Set(referencedNarrationCueIDs);
  for (const event of narrationEvents) {
    if (!referencedSet.has(event.cueID)) {
      issues.push(`${location}.audioTimelines.events.${event.cueID}.narrationBinding: narration cue is not referenced by its scoped beat`);
    }
  }
  for (const scene of scenes.filter(isRecord)) {
    if (!accessibilityIDs.has(scene.accessibilityID)) {
      issues.push(`${location}.scenes.${scene.id}.accessibilityID: missing accessibility spec '${scene.accessibilityID}'`);
      continue;
    }
    const elementByID = new Map(
      (accessibilityByID.get(scene.accessibilityID)?.elements ?? [])
        .filter(isRecord)
        .map((element) => [element.id, element]),
    );
    for (const target of (scene.interactionTargets ?? []).filter(isRecord)) {
      const element = elementByID.get(target.accessibilityElementID);
      if (!element) {
        issues.push(`${location}.scenes.${scene.id}.interactionTargets.${target.interactionTargetID}.accessibilityElementID: missing accessibility element '${target.accessibilityElementID}'`);
      } else if (!(["action", "adjustable"].includes(element.role))
          || !Array.isArray(element.actions) || element.actions.length === 0) {
        issues.push(`${location}.scenes.${scene.id}.interactionTargets.${target.interactionTargetID}.accessibilityElementID: must bind to an operable action or adjustable element with authored actions`);
      }
    }
  }
  for (const specification of accessibility.filter(isRecord)) {
    const hasActions = Array.isArray(specification.elements)
      && specification.elements.some((element) => isRecord(element)
        && Array.isArray(element.actions) && element.actions.length > 0);
    if (hasActions && !interactionAccessibilityIDs.has(specification.id)) {
      issues.push(`${location}.accessibility.${specification.id}: operable spec is not bound to an interaction`);
    }
  }
  validateWorldReplay(record, location, issues);
  requireConsistentLocalizedStrings(record, `${location}.localizedStrings`, issues);
  return issues;
}

function validateAccessRule(value, location, issues) {
  if (!isRecord(value)) {
    issues.push(`${location}: object required`);
    return;
  }
  if (value.kind === "included") {
    shape(value, location, ["kind"], [], issues);
  } else if (value.kind === "entitlement") {
    const record = shape(value, location, ["kind", "entitlementID"], [], issues);
    if (record) stableID(record.entitlementID, `${location}.entitlementID`, issues);
  } else {
    shape(value, location, ["kind"], [], issues);
    issues.push(`${location}.kind: expected included or entitlement`);
  }
}

export function validateCollectionManifest(collection, location = "collection", issues = []) {
  const record = shape(collection, location,
    ["schemaVersion", "collectionID", "locale", "product", "chapters", "packages", "entitlements"], [], issues);
  if (!record) return issues;
  validateSchemaVersion(record.schemaVersion, `${location}.schemaVersion`, issues);
  stableID(record.collectionID, `${location}.collectionID`, issues);
  validateLocaleDescriptor(record.locale, `${location}.locale`, issues);
  const product = shape(record.product, `${location}.product`, ["franchiseName", "workTitle"], [], issues);
  if (product) {
    authoredString(product.franchiseName, `${location}.product.franchiseName`, issues);
    authoredString(product.workTitle, `${location}.product.workTitle`, issues);
  }
  const chapters = arrayValue(record.chapters, `${location}.chapters`, issues, 24);
  if (chapters.length !== 24) issues.push(`${location}.chapters: exactly 24 launch chapters required`);
  for (const [index, chapter] of chapters.entries()) {
    const item = shape(chapter, `${location}.chapters[${index}]`, ["id", "sequence", "title", "period", "packageID", "access"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.chapters[${index}].id`, issues);
    integer(item.sequence, `${location}.chapters[${index}].sequence`, issues, 1);
    validateLocalizedString(item.title, `${location}.chapters[${index}].title`, issues);
    validateLocalizedString(item.period, `${location}.chapters[${index}].period`, issues);
    packageIdentifier(item.packageID, `${location}.chapters[${index}].packageID`, issues);
    validateAccessRule(item.access, `${location}.chapters[${index}].access`, issues);
  }
  const packages = arrayValue(record.packages, `${location}.packages`, issues, 8);
  if (packages.length !== 8) issues.push(`${location}.packages: exactly 8 launch packages required`);
  for (const [index, packageSpec] of packages.entries()) {
    const item = shape(packageSpec, `${location}.packages[${index}]`,
      ["id", "version", "chapterIDs", "maximumInstalledBytes", "minimumRuntime", "isEssentialInstall"], [], issues);
    if (!item) continue;
    packageIdentifier(item.id, `${location}.packages[${index}].id`, issues);
    validateSchemaVersion(item.version, `${location}.packages[${index}].version`, issues);
    const chapterIDs = arrayValue(item.chapterIDs, `${location}.packages[${index}].chapterIDs`, issues, 1);
    chapterIDs.forEach((id, chapterIndex) => stableID(id, `${location}.packages[${index}].chapterIDs[${chapterIndex}]`, issues));
    requireUnique(chapterIDs, `${location}.packages[${index}].chapterIDs`, issues);
    integer(item.maximumInstalledBytes, `${location}.packages[${index}].maximumInstalledBytes`, issues, 1);
    validateSchemaVersion(item.minimumRuntime, `${location}.packages[${index}].minimumRuntime`, issues);
    boolean(item.isEssentialInstall, `${location}.packages[${index}].isEssentialInstall`, issues);
  }
  const entitlements = arrayValue(record.entitlements, `${location}.entitlements`, issues, 1);
  for (const [index, entitlement] of entitlements.entries()) {
    const item = shape(entitlement, `${location}.entitlements[${index}]`, ["id", "storeProductID", "kind"], [], issues);
    if (!item) continue;
    stableID(item.id, `${location}.entitlements[${index}].id`, issues);
    authoredString(item.storeProductID, `${location}.entitlements[${index}].storeProductID`, issues);
    if (item.kind !== "nonConsumable") issues.push(`${location}.entitlements[${index}].kind: nonConsumable required`);
  }

  const chapterRecords = chapters.filter(isRecord);
  const packageRecords = packages.filter(isRecord);
  const entitlementRecords = entitlements.filter(isRecord);
  requireUnique(chapterRecords.map((chapter) => chapter.id), `${location}.chapters.id`, issues);
  requireUnique(chapterRecords.map((chapter) => chapter.sequence), `${location}.chapters.sequence`, issues);
  requireUnique(packageRecords.map((packageSpec) => packageSpec.id), `${location}.packages.id`, issues);
  requireUnique(entitlementRecords.map((entitlement) => entitlement.id), `${location}.entitlements.id`, issues);
  const chapterIDs = new Set(chapterRecords.map((chapter) => chapter.id));
  const packageIDs = new Set(packageRecords.map((packageSpec) => packageSpec.id));
  const entitlementIDs = new Set(entitlementRecords.map((entitlement) => entitlement.id));
  const expectedSequences = Array.from({ length: 24 }, (_, index) => index + 1);
  if (JSON.stringify(chapterRecords.map((chapter) => chapter.sequence).sort((a, b) => a - b)) !== JSON.stringify(expectedSequences)) {
    issues.push(`${location}.chapters.sequence: must cover 1 through 24 exactly`);
  }
  for (const chapter of chapterRecords) {
    if (!packageIDs.has(chapter.packageID)) issues.push(`${location}.chapters.${chapter.id}.packageID: missing package '${chapter.packageID}'`);
    if (chapter.access?.kind === "entitlement" && !entitlementIDs.has(chapter.access.entitlementID)) {
      issues.push(`${location}.chapters.${chapter.id}.access: missing entitlement '${chapter.access.entitlementID}'`);
    }
    const owners = packageRecords.filter((packageSpec) => Array.isArray(packageSpec.chapterIDs) && packageSpec.chapterIDs.includes(chapter.id));
    if (owners.length !== 1 || owners[0].id !== chapter.packageID) {
      issues.push(`${location}.chapters.${chapter.id}.packageID: chapter must belong to exactly one matching package`);
    }
  }
  for (const packageSpec of packageRecords) {
    for (const chapterID of packageSpec.chapterIDs ?? []) {
      if (!chapterIDs.has(chapterID)) issues.push(`${location}.packages.${packageSpec.id}.chapterIDs: missing chapter '${chapterID}'`);
    }
  }
  const includedIDs = chapterRecords.filter((chapter) => chapter.access?.kind === "included").map((chapter) => chapter.id).sort();
  const expectedFree = [...requiredFreeChapterIDs].sort();
  if (JSON.stringify(includedIDs) !== JSON.stringify(expectedFree)) {
    issues.push(`${location}.chapters.access: included chapters must equal ${expectedFree.join(", ")}`);
  }
  const essential = packageRecords.filter((packageSpec) => packageSpec.isEssentialInstall === true);
  if (essential.length !== 1 || JSON.stringify([...(essential[0]?.chapterIDs ?? [])].sort()) !== JSON.stringify(expectedFree)) {
    issues.push(`${location}.packages: one essential package must contain exactly the three free chapters`);
  }
  if (entitlementRecords.length !== 1 || entitlementRecords[0]?.kind !== "nonConsumable") {
    issues.push(`${location}.entitlements: exactly one non-consumable launch entitlement required`);
  }
  requireConsistentLocalizedStrings(record, `${location}.localizedStrings`, issues);
  return issues;
}

function validatePrologueSpec(value, location, issues) {
  const record = shape(value, location,
    ["id", "sceneID", "narrative", "interaction", "checkpoint"], [], issues);
  if (!record) return;
  stableID(record.id, `${location}.id`, issues);
  stableID(record.sceneID, `${location}.sceneID`, issues);
  validateNarrative(record.narrative, `${location}.narrative`, issues);
  validateInteraction(record.interaction, `${location}.interaction`, issues);
  if (record.interaction?.grammar !== "trace") {
    issues.push(`${location}.interaction.grammar: prologue must wake the road through trace`);
  }
  if (record.checkpoint !== "afterInteraction") {
    issues.push(`${location}.checkpoint: prologue must checkpoint after its historical action`);
  }
}

function validateLivingWorldPresentationSpec(value, location, issues) {
  const record = shape(value, location, [
    "id", "sceneID", "accessibilityID", "currentPlaceLayerID",
    "nextPressureLayerID", "chapters", "traces",
  ], [], issues);
  if (!record) return;
  for (const key of ["id", "sceneID", "accessibilityID", "currentPlaceLayerID", "nextPressureLayerID"]) {
    stableID(record[key], `${location}.${key}`, issues);
  }
  if (record.currentPlaceLayerID === record.nextPressureLayerID) {
    issues.push(`${location}: current place and next pressure require distinct layers`);
  }
  const chapters = arrayValue(record.chapters, `${location}.chapters`, issues, 1);
  for (const [index, chapter] of chapters.entries()) {
    const item = shape(chapter, `${location}.chapters[${index}]`,
      ["chapterID", "worldNodeID", "position", "historicalInvitation"], [], issues);
    if (!item) continue;
    stableID(item.chapterID, `${location}.chapters[${index}].chapterID`, issues);
    stableID(item.worldNodeID, `${location}.chapters[${index}].worldNodeID`, issues);
    validatePoint(item.position, `${location}.chapters[${index}].position`, issues);
    validateLocalizedString(item.historicalInvitation, `${location}.chapters[${index}].historicalInvitation`, issues);
  }
  requireUnique(chapters.filter(isRecord).map((item) => item.chapterID), `${location}.chapters.chapterID`, issues);
  requireUnique(chapters.filter(isRecord).map((item) => item.worldNodeID), `${location}.chapters.worldNodeID`, issues);
  const traces = arrayValue(record.traces, `${location}.traces`, issues, 1);
  for (const [index, trace] of traces.entries()) {
    const item = shape(trace, `${location}.traces[${index}]`, ["worldTraceID", "layerID"], [], issues);
    if (!item) continue;
    stableID(item.worldTraceID, `${location}.traces[${index}].worldTraceID`, issues);
    stableID(item.layerID, `${location}.traces[${index}].layerID`, issues);
  }
  requireUnique(traces.filter(isRecord).map((item) => item.worldTraceID), `${location}.traces.worldTraceID`, issues);
  requireUnique(traces.filter(isRecord).map((item) => item.layerID), `${location}.traces.layerID`, issues);
}

export function validateAppShellSpec(appShell, location = "appShell", issues = []) {
  const record = shape(appShell, location,
    ["schemaVersion", "id", "locale", "prologue", "livingWorld"], [], issues);
  if (!record) return issues;
  validateSchemaVersion(record.schemaVersion, `${location}.schemaVersion`, issues);
  stableID(record.id, `${location}.id`, issues);
  validateLocaleDescriptor(record.locale, `${location}.locale`, issues);
  validatePrologueSpec(record.prologue, `${location}.prologue`, issues);
  validateLivingWorldPresentationSpec(record.livingWorld, `${location}.livingWorld`, issues);
  requireConsistentLocalizedStrings(record, `${location}.localizedStrings`, issues);
  return issues;
}

function validateAppShellLaunchBinding(
  appShell,
  expectedChapterIDs,
  location,
  issues,
) {
  if (appShell?.locale?.identifier !== "en"
      || Object.hasOwn(appShell?.locale ?? {}, "fallbackIdentifier")) {
    issues.push(`${location}.locale: launch app shell must use the exact English descriptor`);
  }
  const actualChapterIDs = Array.isArray(appShell?.livingWorld?.chapters)
    ? appShell.livingWorld.chapters.filter(isRecord).map((chapter) => chapter.chapterID)
    : [];
  if (!Array.isArray(expectedChapterIDs)
      || expectedChapterIDs.length !== 24
      || JSON.stringify(actualChapterIDs) !== JSON.stringify(expectedChapterIDs)) {
    issues.push(`${location}.livingWorld.chapters: must bind the complete chronological launch road`);
  }
}

export function validateLaunchAppShellSpec(
  appShell,
  expectedChapterIDs,
  location = "appShell",
) {
  const issues = validateAppShellSpec(appShell, location, []);
  validateAppShellLaunchBinding(appShell, expectedChapterIDs, location, issues);
  return issues;
}

function sameStringSet(left, right) {
  return JSON.stringify([...(left ?? [])].sort()) === JSON.stringify([...(right ?? [])].sort());
}

/**
 * Binds a structurally valid shipping collection to the generated Phase 0
 * catalog, central product metadata and locked delivery plan. Generic schema
 * validation deliberately stays reusable; production compilation calls this
 * stricter launch gate before signing.
 */
export function validateCollectionAgainstLaunchConfiguration(
  collection,
  { product, catalog, delivery },
  location = "collection",
) {
  const issues = validateCollectionManifest(collection, location, []);
  if (!isRecord(collection) || !isRecord(product) || !isRecord(catalog) || !isRecord(delivery)) {
    issues.push(`${location}: product, catalog and delivery launch configuration is required`);
    return issues;
  }
  if (collection.collectionID !== catalog.collectionID) {
    issues.push(`${location}.collectionID: must match the Phase 0 catalog`);
  }
  if (collection.locale?.identifier !== "en" || collection.locale?.fallbackIdentifier !== undefined) {
    issues.push(`${location}.locale: launch collection must use the exact English descriptor`);
  }
  if (collection.product?.franchiseName !== product.franchiseName
      || collection.product?.workTitle !== product.workTitle) {
    issues.push(`${location}.product: must match native/product.json`);
  }

  const actualChapters = new Map((collection.chapters ?? []).map((chapter) => [chapter.id, chapter]));
  const expectedChapters = [...(catalog.chapters ?? [])].sort((left, right) => left.ordinal - right.ordinal);
  if (expectedChapters.length !== 24
      || !sameStringSet(actualChapters.keys(), expectedChapters.map((chapter) => chapter.contentID))) {
    issues.push(`${location}.chapters: IDs must match the 24-chapter Phase 0 catalog`);
  }
  for (const expected of expectedChapters) {
    const actual = actualChapters.get(expected.contentID);
    if (!actual) continue;
    if (actual.sequence !== expected.ordinal
        || actual.title?.launchEnglish !== expected.title
        || actual.period?.launchEnglish !== expected.period) {
      issues.push(`${location}.chapters.${expected.contentID}: sequence, title and period must match the catalog`);
    }
    const shouldBeIncluded = (catalog.freeContentIDs ?? []).includes(expected.contentID);
    if (shouldBeIncluded) {
      if (actual.access?.kind !== "included") {
        issues.push(`${location}.chapters.${expected.contentID}.access: free catalog chapter must be included`);
      }
    } else if (actual.access?.kind !== "entitlement"
        || actual.access.entitlementID !== delivery.entitlement?.entitlementID) {
      issues.push(`${location}.chapters.${expected.contentID}.access: paid chapter must use the launch entitlement`);
    }
  }

  const actualPackages = new Map((collection.packages ?? []).map((item) => [item.id, item]));
  const expectedPackages = delivery.packages ?? [];
  if (expectedPackages.length !== 8
      || !sameStringSet(actualPackages.keys(), expectedPackages.map((item) => item.packageID))) {
    issues.push(`${location}.packages: IDs must match the eight-package delivery plan`);
  }
  let aggregateBytes = 0;
  for (const expected of expectedPackages) {
    const actual = actualPackages.get(expected.packageID);
    if (!actual) continue;
    if (!sameStringSet(actual.chapterIDs, expected.chapterIDs)
        || actual.isEssentialInstall !== expected.isEssentialInstall) {
      issues.push(`${location}.packages.${expected.packageID}: ownership and essential state must match the delivery plan`);
    }
    if (actual.maximumInstalledBytes > expected.maximumInstalledBytes) {
      issues.push(`${location}.packages.${expected.packageID}.maximumInstalledBytes: exceeds the package budget`);
    }
    aggregateBytes += actual.maximumInstalledBytes;
  }
  const maximumInstalledContentBytes = delivery.budgets?.completeInstalledWorkBytes
    - delivery.budgets?.shellAndEngineBytes;
  if (!Number.isSafeInteger(aggregateBytes)
      || !Number.isSafeInteger(maximumInstalledContentBytes)
      || maximumInstalledContentBytes <= 0
      || aggregateBytes > maximumInstalledContentBytes) {
    issues.push(`${location}.packages.maximumInstalledBytes: exceeds the complete installed-work budget`);
  }

  const entitlement = (collection.entitlements ?? [])[0];
  if ((collection.entitlements ?? []).length !== 1
      || entitlement?.id !== delivery.entitlement?.entitlementID
      || entitlement?.storeProductID !== delivery.entitlement?.storeProductID
      || entitlement?.kind !== "nonConsumable") {
    issues.push(`${location}.entitlements: must match the locked permanent launch purchase`);
  }
  return issues;
}

export function validateReleaseDocument(release, location = "release", issues = []) {
  const record = shape(release, location, [
    "id", "contentID", "packageID", "version", "chapterIDs", "maximumInstalledBytes",
    "publishedAtUnixMillis", "minimumRuntime",
  ], [], issues);
  if (!record) return issues;
  stableID(record.id, `${location}.id`, issues);
  stableID(record.contentID, `${location}.contentID`, issues);
  packageIdentifier(record.packageID, `${location}.packageID`, issues);
  validateSchemaVersion(record.version, `${location}.version`, issues);
  const chapterIDs = arrayValue(record.chapterIDs, `${location}.chapterIDs`, issues, 1);
  chapterIDs.forEach((chapterID, index) => stableID(chapterID, `${location}.chapterIDs[${index}]`, issues));
  requireUnique(chapterIDs, `${location}.chapterIDs`, issues);
  if (!chapterIDs.includes(record.contentID)) {
    issues.push(`${location}.contentID: must identify a chapter owned by this release`);
  }
  integer(record.maximumInstalledBytes, `${location}.maximumInstalledBytes`, issues, 1);
  integer(record.publishedAtUnixMillis, `${location}.publishedAtUnixMillis`, issues, 0);
  validateSchemaVersion(record.minimumRuntime, `${location}.minimumRuntime`, issues);
  return issues;
}

export function validatePublicDocument(document, location = "document") {
  const issues = [];
  inspectPublicValue(document, location, issues);
  if (!isRecord(document)) {
    issues.push(`${location}: public document must be an object`);
  } else if (Object.hasOwn(document, "collectionID")) {
    validateCollectionManifest(document, location, issues);
  } else if (Object.hasOwn(document, "chapters") || Object.hasOwn(document, "scenes") || Object.hasOwn(document, "audioTimelines")) {
    validateContentPackagePayload(document, location, issues);
  } else if (Object.hasOwn(document, "prologue") || Object.hasOwn(document, "livingWorld")) {
    validateAppShellSpec(document, location, issues);
  } else if (Object.hasOwn(document, "publishedAtUnixMillis")) {
    validateReleaseDocument(document, location, issues);
  } else {
    issues.push(`${location}: expected CollectionManifest, ContentPackagePayload, AppShellSpec or Release`);
  }
  if (issues.length) throw new ValidationError(issues);
  return document;
}

/// Validates one standalone authored scene with the exact same public-field
/// firewall and structural rules used inside a ContentPackagePayload.
export function validateSceneSpec(scene, location = "scene") {
  const issues = [];
  inspectPublicValue(scene, location, issues);
  validateScene(scene, location, issues);
  if (issues.length) throw new ValidationError(issues);
  return scene;
}

export async function listFiles(root) {
  const output = [];
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) await visit(absolute);
      if (entry.isFile()) output.push(absolute);
    }
  }
  await visit(root);
  return output.sort();
}

function documentKind(document) {
  if (isRecord(document) && Object.hasOwn(document, "collectionID")) return "collection";
  if (isRecord(document) && Object.hasOwn(document, "chapters")) return "package";
  if (isRecord(document) && Object.hasOwn(document, "prologue")) return "app-shell";
  if (isRecord(document) && Object.hasOwn(document, "publishedAtUnixMillis")) return "release";
  return "unknown";
}

function addShippingAssetReference(output, assetPath, role) {
  if (typeof assetPath !== "string") return;
  const roles = output.get(assetPath) ?? new Set();
  roles.add(role);
  output.set(assetPath, roles);
}

export function collectShippingAssetReferences(payload) {
  const output = new Map();
  for (const scene of payload?.scenes ?? []) {
    for (const stratum of scene?.reduceMotionComposition?.strata ?? []) {
      addShippingAssetReference(output, stratum?.assetPath, "scene-layer");
    }
    for (const layer of scene?.layers ?? []) {
      addShippingAssetReference(output, layer?.assetPath, "scene-layer");
      for (const field of sceneMaskAssetFields) {
        addShippingAssetReference(output, layer?.masks?.[field], "scene-mask");
      }
      for (const variant of layer?.stateVariants ?? []) {
        addShippingAssetReference(output, variant?.assetPath, "scene-layer");
        for (const field of sceneMaskAssetFields) {
          addShippingAssetReference(output, variant?.masks?.[field], "scene-mask");
        }
      }
    }
  }
  for (const timeline of payload?.audioTimelines ?? []) {
    for (const event of timeline?.events ?? []) {
      if (event?.assetPath === undefined || event?.role === "silence") continue;
      const role = event.role === "spatialDetail" ? "spatial-detail" : event.role;
      addShippingAssetReference(output, event.assetPath, role);
    }
  }
  return output;
}

function validateShippingAssetReference(assetPath, roles, location, issues) {
  const extension = path.extname(assetPath).toLowerCase();
  const [topLevel] = assetPath.split("/");
  for (const role of roles) {
    const rule = shippingRoleRules.get(role);
    if (!rule) {
      issues.push(`${location}: unsupported shipping asset role '${role}'`);
      continue;
    }
    if (topLevel !== rule.topLevel || !rule.extensions.has(extension)) {
      issues.push(`${location}: '${assetPath}' is not a valid ${role} asset`);
    }
  }
}

export async function validatePublicTree(root) {
  const rootStat = await stat(root).catch(() => null);
  if (!rootStat?.isDirectory()) throw new ValidationError([`${root}: public source directory missing`]);
  const files = await listFiles(root);
  if (!files.length) throw new ValidationError([`${root}: public source directory is empty`]);
  const jsonFiles = files.filter((file) => path.extname(file).toLowerCase() === ".json");
  if (!jsonFiles.length) throw new ValidationError([`${root}: no public JSON documents found`]);
  const issues = [];
  const documents = [];
  const relativeFiles = new Set(files.map((file) => path.relative(root, file).split(path.sep).join("/")));
  for (const file of files) {
    const relative = path.relative(root, file);
    const portable = relative.split(path.sep).join("/");
    const [topLevel] = relative.split(path.sep);
    if (!allowedPublicTopLevel.has(topLevel)) issues.push(`${portable}: path is not in the public package allowlist`);
    if (!allowedPublicExtensions.has(path.extname(file).toLowerCase())) issues.push(`${portable}: file type is not in the public package allowlist`);
    for (const segment of relative.split(path.sep)) {
      if (forbiddenPathSegments.has(segment) || ["backstage", "research", "sources", "evidence", "findings", "claims"].includes(normalizePolicyName(segment))) {
        issues.push(`${portable}: forbidden path segment '${segment}'`);
      }
    }
    if (path.extname(file).toLowerCase() !== ".json") continue;
    try {
      const document = JSON.parse(await readFile(file, "utf8"));
      validatePublicDocument(document, portable);
      const kind = documentKind(document);
      documents.push({ kind, document, relative: portable });
      if (portable === "collection.json" && kind !== "collection") issues.push(`${portable}: must contain CollectionManifest`);
      if (portable === "app-shell.json" && kind !== "app-shell") issues.push(`${portable}: must contain AppShellSpec`);
      if (portable.startsWith("chapters/") && kind !== "package") issues.push(`${portable}: must contain ContentPackagePayload`);
      if (portable.startsWith("releases/") && kind !== "release") issues.push(`${portable}: must contain Release`);
      if (!["collection.json", "app-shell.json", "chapters", "releases"].includes(topLevel)) {
        issues.push(`${portable}: authored JSON documents belong in collection.json, app-shell.json, chapters/ or releases/`);
      }
    } catch (error) {
      if (error instanceof ValidationError) issues.push(...error.issues);
      else issues.push(`${portable}: ${error.message}`);
    }
  }
  const packages = documents.filter((entry) => entry.kind === "package");
  if (!packages.length) issues.push(`${root}: at least one ContentPackagePayload is required`);
  requireUnique(packages.map((entry) => entry.document.packageID), "publicTree.packageID", issues);
  const shippingReferences = new Map();
  for (const entry of packages) {
    const packageReferences = collectShippingAssetReferences(entry.document);
    for (const [assetPath, roles] of packageReferences) {
      const combined = shippingReferences.get(assetPath) ?? new Set();
      roles.forEach((role) => combined.add(role));
      shippingReferences.set(assetPath, combined);
      validateShippingAssetReference(assetPath, roles, entry.relative, issues);
      if (!relativeFiles.has(assetPath)) issues.push(`${entry.relative}: missing offline asset '${assetPath}'`);
    }
  }
  for (const relative of relativeFiles) {
    if (path.extname(relative).toLowerCase() === ".json") continue;
    if (!shippingReferences.has(relative)) {
      issues.push(`${relative}: binary file is not referenced by a typed shipping asset field`);
    }
  }
  const collections = documents.filter((entry) => entry.kind === "collection");
  if (collections.length > 1) issues.push("publicTree: at most one CollectionManifest allowed");
  const appShells = documents.filter((entry) => entry.kind === "app-shell");
  if (appShells.length > 1) issues.push("publicTree: at most one AppShellSpec allowed");
  if (appShells.length === 1) {
    if (collections.length !== 1) {
      issues.push("app-shell.json: launch app shell requires exactly one collection.json");
    } else {
      const chronologicalChapterIDs = [...collections[0].document.chapters]
        .sort((left, right) => left.sequence - right.sequence)
        .map((chapter) => chapter.id);
      validateAppShellLaunchBinding(
        appShells[0].document,
        chronologicalChapterIDs,
        appShells[0].relative,
        issues,
      );
    }
  }
  if (collections.length === 1) {
    const packageSpecs = new Map(collections[0].document.packages.map((packageSpec) => [packageSpec.id, packageSpec]));
    const declaredPackages = new Set(packageSpecs.keys());
    for (const entry of packages) {
      if (!declaredPackages.has(entry.document.packageID)) {
        issues.push(`${entry.relative}: packageID '${entry.document.packageID}' is absent from collection.json`);
        continue;
      }
      const expectedChapterIDs = [...packageSpecs.get(entry.document.packageID).chapterIDs].sort();
      const payloadChapterIDs = entry.document.chapters.map((chapter) => chapter.id).sort();
      if (JSON.stringify(payloadChapterIDs) !== JSON.stringify(expectedChapterIDs)) {
        issues.push(`${entry.relative}: payload chapters do not match collection package '${entry.document.packageID}'`);
      }
    }
  }
  const knownPackageIDs = new Set([
    ...packages.map((entry) => entry.document.packageID),
    ...collections.flatMap((entry) => entry.document.packages.map((packageSpec) => packageSpec.id)),
  ]);
  for (const release of documents.filter((entry) => entry.kind === "release")) {
    if (!knownPackageIDs.has(release.document.packageID)) {
      issues.push(`${release.relative}: release references unknown package '${release.document.packageID}'`);
      continue;
    }
    const matchingPayloads = packages.filter(
      (entry) => entry.document.packageID === release.document.packageID,
    );
    if (matchingPayloads.length !== 1) {
      issues.push(`${release.relative}: release requires exactly one matching ContentPackagePayload`);
      continue;
    }
    const payloadChapterIDs = matchingPayloads[0].document.chapters.map((chapter) => chapter.id);
    if (!sameStringSet(release.document.chapterIDs, payloadChapterIDs)) {
      issues.push(`${release.relative}: release chapter ownership does not match its ContentPackagePayload`);
    }
  }
  if (issues.length) throw new ValidationError(issues);
  return files;
}

const authoritativeWebPathPattern = /^\/(?!.*(?:^|\/)\.\.?(?:\/|$))[A-Za-z0-9._/-]+$/u;
const nativeShippingPathPattern = /^(?:assets|audio)\/(?!.*(?:^|\/)\.\.?(?:\/|$))[A-Za-z0-9._/-]+$/u;
const projectAudioSourcePathPattern = /^native\/audio\/(?!.*(?:^|\/)\.\.?(?:\/|$))[A-Za-z0-9._/-]+\.(?:json|mjs|txt)$/u;
const projectAudioNoticePathPattern = /^native\/audio\/(?!.*(?:^|\/)\.\.?(?:\/|$))[A-Za-z0-9._/-]+\.md$/u;
const httpsURLPattern = /^https:\/\/[^\s]+$/u;

function validateAuthoritativeWebSourceInventory(inventory, issues) {
  const location = "webSourceInventory";
  const record = shape(inventory, location,
    ["schemaVersion", "status", "scope", "policy", "generatedFrom", "counts", "declaredButMissing", "assets"],
    [], issues);
  if (!record) return new Map();
  if (record.schemaVersion !== 1) issues.push(`${location}.schemaVersion: expected 1`);
  authoredString(record.scope, `${location}.scope`, issues);
  authoredString(record.policy, `${location}.policy`, issues);
  const generatedFrom = shape(record.generatedFrom, `${location}.generatedFrom`,
    ["assetRegistry", "assetRegistrySHA256", "publicRoot"], [], issues);
  if (generatedFrom) {
    if (generatedFrom.assetRegistry !== "site/src/data/sources.ts#assetRecords"
        || generatedFrom.publicRoot !== "site/public") {
      issues.push(`${location}.generatedFrom: authoritative web registry and public root required`);
    }
    if (!sha256Pattern.test(generatedFrom.assetRegistrySHA256 ?? "")) {
      issues.push(`${location}.generatedFrom.assetRegistrySHA256: lowercase SHA-256 required`);
    }
  }
  const counts = shape(record.counts, `${location}.counts`, [
    "visualFiles", "sourceRecords", "uniqueRecordedPaths", "recordedFiles",
    "blockedFiles", "declaredButMissing",
  ], [], issues);
  if (counts) {
    for (const key of Object.keys(counts)) integer(counts[key], `${location}.counts.${key}`, issues, 0);
  }
  const declaredButMissing = arrayValue(record.declaredButMissing, `${location}.declaredButMissing`, issues);
  declaredButMissing.forEach((sourcePath, index) => {
    if (typeof sourcePath !== "string" || !authoritativeWebPathPattern.test(sourcePath)) {
      issues.push(`${location}.declaredButMissing[${index}]: canonical /site/public path required`);
    }
  });
  requireUnique(declaredButMissing, `${location}.declaredButMissing`, issues);

  const assets = arrayValue(record.assets, `${location}.assets`, issues);
  const assetsByPath = new Map();
  let sourceRecordCount = 0;
  for (const [index, asset] of assets.entries()) {
    const assetLocation = `${location}.assets[${index}]`;
    const item = shape(asset, assetLocation, [
      "localPath", "bytes", "sha256", "mediaType", "provenanceStatus",
      "allowedAsNativeRawMaterial", "obligations", "provenanceRecords",
    ], [], issues);
    if (!item) continue;
    if (!authoritativeWebPathPattern.test(item.localPath ?? "")) {
      issues.push(`${assetLocation}.localPath: canonical /site/public path required`);
    }
    if (assetsByPath.has(item.localPath)) issues.push(`${assetLocation}.localPath: duplicate authoritative path`);
    assetsByPath.set(item.localPath, item);
    integer(item.bytes, `${assetLocation}.bytes`, issues, 1);
    if (!sha256Pattern.test(item.sha256 ?? "")) issues.push(`${assetLocation}.sha256: lowercase SHA-256 required`);
    authoredString(item.mediaType, `${assetLocation}.mediaType`, issues);
    enumValue(item.provenanceStatus,
      new Set(["RECORDED_SOURCE_RIGHTS", "BLOCKED_PROVENANCE_MISSING"]),
      `${assetLocation}.provenanceStatus`, issues);
    boolean(item.allowedAsNativeRawMaterial, `${assetLocation}.allowedAsNativeRawMaterial`, issues);
    const obligations = arrayValue(item.obligations, `${assetLocation}.obligations`, issues);
    obligations.forEach((obligation, obligationIndex) =>
      authoredString(obligation, `${assetLocation}.obligations[${obligationIndex}]`, issues));
    requireUnique(obligations, `${assetLocation}.obligations`, issues);
    const provenanceRecords = arrayValue(item.provenanceRecords, `${assetLocation}.provenanceRecords`, issues);
    sourceRecordCount += provenanceRecords.length;
    for (const [recordIndex, provenance] of provenanceRecords.entries()) {
      const provenanceLocation = `${assetLocation}.provenanceRecords[${recordIndex}]`;
      const source = shape(provenance, provenanceLocation, [
        "id", "title", "creator", "institution", "sourceUrl", "license",
        "requiredCredit", "localPath",
      ], [], issues);
      if (!source) continue;
      stableID(source.id, `${provenanceLocation}.id`, issues);
      for (const key of ["title", "creator", "institution", "sourceUrl", "license", "requiredCredit"]) {
        authoredString(source[key], `${provenanceLocation}.${key}`, issues);
      }
      if (source.localPath !== item.localPath) {
        issues.push(`${provenanceLocation}.localPath: must match its authoritative web asset`);
      }
    }
    requireUnique(
      provenanceRecords.filter(isRecord).map((source) => source.id),
      `${assetLocation}.provenanceRecords.id`, issues,
    );
    const eligible = item.provenanceStatus === "RECORDED_SOURCE_RIGHTS"
      && item.allowedAsNativeRawMaterial === true
      && provenanceRecords.length > 0;
    const blocked = item.provenanceStatus === "BLOCKED_PROVENANCE_MISSING"
      && item.allowedAsNativeRawMaterial === false
      && provenanceRecords.length === 0;
    if (!eligible && !blocked) {
      issues.push(`${assetLocation}: provenance status, eligibility and records are inconsistent`);
    }
  }
  const recordedFiles = assets.filter((asset) => asset?.allowedAsNativeRawMaterial === true).length;
  const blockedFiles = assets.length - recordedFiles;
  if (counts && (counts.visualFiles !== assets.length
      || counts.sourceRecords !== sourceRecordCount
      || counts.uniqueRecordedPaths !== recordedFiles + declaredButMissing.length
      || counts.recordedFiles !== recordedFiles
      || counts.blockedFiles !== blockedFiles
      || counts.declaredButMissing !== declaredButMissing.length)) {
    issues.push(`${location}.counts: inventory totals do not match authoritative records`);
  }
  const expectedStatus = blockedFiles > 0
    ? "RAW_MATERIAL_REQUIRES_PROVENANCE_WORK"
    : "ALL_RAW_MATERIAL_RECORDED";
  if (record.status !== expectedStatus) issues.push(`${location}.status: expected ${expectedStatus}`);
  return assetsByPath;
}

/**
 * Validates the non-shipping source boundary of native asset records. Web
 * derivatives must bind to the frozen web inventory exactly. Generated
 * originals use a separate closed shape and cannot carry a web-source path.
 * Tool IDs are checked here for shape; the compiler's cost registry remains
 * the authority that proves every referenced tool is zero-cost and cleared.
 */
export function validateNativeAssetProvenanceLineage(
  registry,
  authoritativeWebInventory = undefined,
  projectFileInventory = undefined,
) {
  const issues = [];
  const inventoryByPath = authoritativeWebInventory === undefined
    ? undefined
    : validateAuthoritativeWebSourceInventory(authoritativeWebInventory, issues);
  const record = shape(registry, "asset provenance", ["schemaVersion", "status", "assets"], [], issues);
  if (!record) throw new ValidationError(issues);
  if (record.schemaVersion !== 3) issues.push("asset provenance.schemaVersion: expected 3");
  if (!["NO_NATIVE_ASSETS_APPROVED", "ACTIVE"].includes(record.status)) {
    issues.push("asset provenance.status: recognised status required");
  }
  const assets = arrayValue(record.assets, "asset provenance.assets", issues);
  const assetPaths = [];
  const sourceFingerprints = new Map();
  let missingInventoryReported = false;
  let missingProjectFileInventoryReported = false;
  for (const [index, asset] of assets.entries()) {
    const location = `asset provenance.assets[${index}]`;
    const item = shape(asset, location, [
      "assetPath", "bytes", "sha256", "sourceLineage", "toolLineage",
      "shippingRoles", "metadataPolicy", "rightsStatus", "incrementalCostNOK",
      "approvedForShipping",
    ], [], issues);
    if (!item) continue;
    assetPaths.push(item.assetPath);
    if (!nativeShippingPathPattern.test(item.assetPath ?? "")) {
      issues.push(`${location}.assetPath: safe assets/ or audio/ package path required`);
    }
    integer(item.bytes, `${location}.bytes`, issues, 0);
    if (!sha256Pattern.test(item.sha256 ?? "")) issues.push(`${location}.sha256: lowercase SHA-256 required`);
    if (item.rightsStatus !== "COMMERCIAL_USE_CLEARED"
        || item.incrementalCostNOK !== 0 || item.approvedForShipping !== true) {
      issues.push(`${location}: commercial rights, zero cost and shipping approval required`);
    }
    const sourceLineage = arrayValue(item.sourceLineage, `${location}.sourceLineage`, issues, 1);
    const assetRoles = Array.isArray(item.shippingRoles) ? item.shippingRoles : [];
    const audioOnlyAsset = assetRoles.length > 0 && assetRoles.every((role) => audioShippingRoles.has(role));
    const sourceIDs = [];
    for (const [sourceIndex, lineage] of sourceLineage.entries()) {
      const sourceLocation = `${location}.sourceLineage[${sourceIndex}]`;
      if (!isRecord(lineage) || !nativeAssetLineageTypes.has(lineage.lineageType)) {
        issues.push(`${sourceLocation}.lineageType: recognised explicit source lineage required`);
        continue;
      }
      sourceIDs.push(lineage.sourceID);
      stableID(lineage.sourceID, `${sourceLocation}.sourceID`, issues);
      integer(lineage.bytes, `${sourceLocation}.bytes`, issues, 1);
      if (!sha256Pattern.test(lineage.sha256 ?? "")) {
        issues.push(`${sourceLocation}.sha256: lowercase SHA-256 required`);
      }
      let fingerprint;
      if (lineage.lineageType === "WEB_SOURCE_DERIVATIVE") {
        shape(lineage, sourceLocation, [
          "lineageType", "sourceID", "webSourcePath", "bytes", "sha256",
          "acknowledgedObligations",
        ], [], issues);
        if (!authoritativeWebPathPattern.test(lineage.webSourcePath ?? "")) {
          issues.push(`${sourceLocation}.webSourcePath: canonical /site/public path required`);
        }
        const obligations = arrayValue(
          lineage.acknowledgedObligations,
          `${sourceLocation}.acknowledgedObligations`, issues,
        );
        obligations.forEach((obligation, obligationIndex) =>
          authoredString(obligation, `${sourceLocation}.acknowledgedObligations[${obligationIndex}]`, issues));
        requireUnique(obligations, `${sourceLocation}.acknowledgedObligations`, issues);
        if (inventoryByPath === undefined) {
          if (!missingInventoryReported) {
            issues.push("asset provenance: authoritative web source inventory required for WEB_SOURCE_DERIVATIVE lineage");
            missingInventoryReported = true;
          }
        } else {
          const authoritative = inventoryByPath.get(lineage.webSourcePath);
          if (!authoritative) {
            issues.push(`${sourceLocation}: web source is absent from the authoritative inventory`);
          } else if (authoritative.allowedAsNativeRawMaterial !== true
              || authoritative.provenanceStatus !== "RECORDED_SOURCE_RIGHTS") {
            issues.push(`${sourceLocation}: authoritative web source is ineligible for native reuse`);
          } else {
            if (lineage.bytes !== authoritative.bytes || lineage.sha256 !== authoritative.sha256) {
              issues.push(`${sourceLocation}: web source path/hash does not match the authoritative inventory`);
            }
            const expectedSourceID = authoritativeWebSourceID(authoritative.sha256);
            if (lineage.sourceID !== expectedSourceID) {
              issues.push(`${sourceLocation}.sourceID: expected '${expectedSourceID}' for the authoritative web source`);
            }
            if (JSON.stringify(obligations) !== JSON.stringify(authoritative.obligations)) {
              issues.push(`${sourceLocation}.acknowledgedObligations: must exactly preserve authoritative obligations`);
            }
          }
        }
        fingerprint = JSON.stringify([
          lineage.lineageType, lineage.webSourcePath, lineage.bytes, lineage.sha256,
          lineage.acknowledgedObligations,
        ]);
      } else if (lineage.lineageType === "GENERATED_ORIGINAL") {
        shape(lineage, sourceLocation, [
          "lineageType", "sourceID", "bytes", "sha256", "rightsBasis", "license",
        ], [], issues);
        if (lineage.rightsBasis !== "PROJECT_OWNED") {
          issues.push(`${sourceLocation}.rightsBasis: generated originals must be PROJECT_OWNED`);
        }
        if (!authoredString(lineage.license, `${sourceLocation}.license`, issues)
            || !/^Project-owned\b/iu.test(lineage.license ?? "")) {
          issues.push(`${sourceLocation}.license: explicit project-owned generated-original terms required`);
        }
        fingerprint = JSON.stringify([
          lineage.lineageType, lineage.bytes, lineage.sha256,
          lineage.rightsBasis, lineage.license,
        ]);
      } else if (lineage.lineageType === "PROJECT_AUTHORED_AUDIO") {
        shape(lineage, sourceLocation, [
          "lineageType", "sourceID", "sourceKind", "sourcePath", "bytes", "sha256",
          "rightsBasis", "license",
        ], [], issues);
        if (!audioOnlyAsset) {
          issues.push(`${sourceLocation}.lineageType: PROJECT_AUTHORED_AUDIO is restricted to audio shipping roles`);
        }
        if (!["SYMBOLIC_SCORE", "PROCEDURAL_PATCH", "PROJECT_AUDIO_EDIT"].includes(lineage.sourceKind)) {
          issues.push(`${sourceLocation}.sourceKind: recognised authored audio source required`);
        }
        if (!projectAudioSourcePathPattern.test(lineage.sourcePath ?? "")) {
          issues.push(`${sourceLocation}.sourcePath: safe native/audio authoring path required`);
        }
        if (lineage.rightsBasis !== "PROJECT_OWNED") {
          issues.push(`${sourceLocation}.rightsBasis: authored audio must be PROJECT_OWNED`);
        }
        if (!authoredString(lineage.license, `${sourceLocation}.license`, issues)
            || !/^Project-owned\b/iu.test(lineage.license ?? "")) {
          issues.push(`${sourceLocation}.license: explicit project-owned audio terms required`);
        }
        if (projectFileInventory === undefined) {
          if (!missingProjectFileInventoryReported) {
            issues.push("asset provenance: exact project-file inventory required for authored audio lineage");
            missingProjectFileInventoryReported = true;
          }
        } else {
          const sourceFile = projectFileInventory.get(lineage.sourcePath);
          if (!sourceFile
              || sourceFile.bytes !== lineage.bytes
              || sourceFile.sha256 !== lineage.sha256) {
            issues.push(`${sourceLocation}: authored audio source path/hash does not match actual project bytes`);
          }
        }
        fingerprint = JSON.stringify([
          lineage.lineageType, lineage.sourceKind, lineage.sourcePath, lineage.bytes,
          lineage.sha256, lineage.rightsBasis, lineage.license,
        ]);
      } else {
        const openFields = [
          "lineageType", "sourceID", "sourceURL", "title", "creator", "bytes", "sha256",
          "licenseSPDX", "licenseURL", "requiredNotices",
        ];
        const mitFields = ["noticePath", "noticeBytes", "noticeSHA256"];
        shape(lineage, sourceLocation,
          lineage.licenseSPDX === "MIT" ? [...openFields, ...mitFields] : openFields,
          [], issues);
        if (!audioOnlyAsset) {
          issues.push(`${sourceLocation}.lineageType: OPEN_LICENSE_AUDIO_SOURCE is restricted to audio shipping roles`);
        }
        if (!httpsURLPattern.test(lineage.sourceURL ?? "")) {
          issues.push(`${sourceLocation}.sourceURL: immutable HTTPS source required`);
        }
        authoredString(lineage.title, `${sourceLocation}.title`, issues);
        authoredString(lineage.creator, `${sourceLocation}.creator`, issues);
        if (!["CC0-1.0", "MIT"].includes(lineage.licenseSPDX)) {
          issues.push(`${sourceLocation}.licenseSPDX: CC0-1.0 or MIT required`);
        }
        if (!httpsURLPattern.test(lineage.licenseURL ?? "")) {
          issues.push(`${sourceLocation}.licenseURL: immutable HTTPS licence evidence required`);
        }
        const notices = arrayValue(lineage.requiredNotices, `${sourceLocation}.requiredNotices`, issues);
        notices.forEach((notice, noticeIndex) =>
          authoredString(notice, `${sourceLocation}.requiredNotices[${noticeIndex}]`, issues));
        requireUnique(notices, `${sourceLocation}.requiredNotices`, issues);
        if (lineage.licenseSPDX === "MIT" && notices.length === 0) {
          issues.push(`${sourceLocation}.requiredNotices: MIT source notice required`);
        }
        if (lineage.licenseSPDX === "MIT") {
          if (!projectAudioNoticePathPattern.test(lineage.noticePath ?? "")) {
            issues.push(`${sourceLocation}.noticePath: safe native/audio notice path required`);
          }
          integer(lineage.noticeBytes, `${sourceLocation}.noticeBytes`, issues, 1);
          if (!sha256Pattern.test(lineage.noticeSHA256 ?? "")) {
            issues.push(`${sourceLocation}.noticeSHA256: lowercase SHA-256 required`);
          }
          if (projectFileInventory === undefined) {
            if (!missingProjectFileInventoryReported) {
              issues.push("asset provenance: exact project-file inventory required for audio licence notices");
              missingProjectFileInventoryReported = true;
            }
          } else {
            const notice = projectFileInventory.get(lineage.noticePath);
            if (!notice
                || notice.bytes !== lineage.noticeBytes
                || notice.sha256 !== lineage.noticeSHA256) {
              issues.push(`${sourceLocation}: MIT notice path/hash does not match actual project bytes`);
            }
          }
        }
        fingerprint = JSON.stringify([
          lineage.lineageType, lineage.sourceURL, lineage.title, lineage.creator, lineage.bytes,
          lineage.sha256, lineage.licenseSPDX, lineage.licenseURL, notices,
          lineage.noticePath, lineage.noticeBytes, lineage.noticeSHA256,
        ]);
      }
      const previous = sourceFingerprints.get(lineage.sourceID);
      if (previous !== undefined && previous !== fingerprint) {
        issues.push(`${sourceLocation}.sourceID: '${lineage.sourceID}' has conflicting lineage data`);
      } else {
        sourceFingerprints.set(lineage.sourceID, fingerprint);
      }
    }
    requireUnique(sourceIDs, `${location}.sourceLineage.sourceID`, issues);
    const tools = arrayValue(item.toolLineage, `${location}.toolLineage`, issues, 1);
    const toolIDs = [];
    for (const [toolIndex, tool] of tools.entries()) {
      const toolLocation = `${location}.toolLineage[${toolIndex}]`;
      const toolRecord = shape(tool, toolLocation, ["toolID"], [], issues);
      if (!toolRecord) continue;
      toolIDs.push(toolRecord.toolID);
      stableID(toolRecord.toolID, `${toolLocation}.toolID`, issues);
    }
    requireUnique(toolIDs, `${location}.toolLineage.toolID`, issues);
    const usesMSBasic = toolIDs.some((toolID) => [
      "fluid-synth-local",
      "musescore-ms-basic-sf3",
      "authored-score-rendering",
    ].includes(toolID));
    if (usesMSBasic) {
      for (const requiredToolID of [
        "audio-production-local",
        "fluid-synth-local",
        "musescore-ms-basic-sf3",
        "authored-score-rendering",
      ]) {
        if (!toolIDs.includes(requiredToolID)) {
          issues.push(`${location}.toolLineage: MS Basic score requires '${requiredToolID}'`);
        }
      }
      const source = sourceLineage.find((lineage) => lineage.sourceID === msBasicSource.sourceID);
      if (!source || source.lineageType !== "OPEN_LICENSE_AUDIO_SOURCE") {
        issues.push(`${location}.sourceLineage: exact MS Basic MIT source record required`);
      } else {
        for (const [key, expected] of Object.entries(msBasicSource)) {
          if (source[key] !== expected) {
            issues.push(`${location}.sourceLineage: MS Basic ${key} differs from the pinned production source`);
          }
        }
      }
    }
  }
  requireUnique(assetPaths, "asset provenance.assets.assetPath", issues);
  if (record.status === "NO_NATIVE_ASSETS_APPROVED" && assets.length !== 0) {
    issues.push("asset provenance: NO_NATIVE_ASSETS_APPROVED requires an empty asset list");
  }
  if (record.status === "ACTIVE" && assets.length === 0) {
    issues.push("asset provenance: ACTIVE requires at least one approved asset");
  }
  if (issues.length) throw new ValidationError(issues);
  return registry;
}

export function validateCostRegistry(registry) {
  const issues = [];
  const registryRecord = shape(registry, "costRegistry", ["policyVersion", "entries", "unresolvedCapabilities"], [], issues);
  if (!registryRecord) throw new ValidationError(issues);
  if (registry.policyVersion !== 1) issues.push("policyVersion: expected 1");
  const entries = arrayValue(registry.entries, "entries", issues);
  const unresolvedCapabilities = arrayValue(registry.unresolvedCapabilities, "unresolvedCapabilities", issues);
  const categories = new Set(["tool", "model", "font", "image", "audio", "service", "sdk"]);
  const costModels = new Set(["existing", "free-local", "included-membership", "public-domain", "open-license"]);
  const entryIDs = [];
  for (const [index, entry] of entries.entries()) {
    const location = `entries[${index}]`;
    const record = shape(entry, location,
      ["id", "category", "version", "costModel", "incrementalCostNOK", "billingCredentialRequired", "commercialUse", "license", "source"],
      [], issues);
    if (!record) continue;
    entryIDs.push(entry.id);
    stableID(entry.id, `${location}.id`, issues);
    enumValue(entry.category, categories, `${location}.category`, issues);
    authoredString(entry.version, `${location}.version`, issues);
    enumValue(entry.costModel, costModels, `${location}.costModel`, issues);
    if (entry.incrementalCostNOK !== 0) issues.push(`${location}: incremental cost must be 0 NOK`);
    if (entry.billingCredentialRequired !== false) issues.push(`${location}: billing credential is forbidden`);
    if (entry.commercialUse !== "allowed") issues.push(`${location}: commercial use must be explicitly allowed`);
    authoredString(entry.license, `${location}.license`, issues);
    authoredString(entry.source, `${location}.source`, issues);
  }
  requireUnique(entryIDs, "entries.id", issues);
  const gapIDs = [];
  const capabilityCategories = new Set(["image", "audio", "tool", "model", "service"]);
  for (const [index, capability] of unresolvedCapabilities.entries()) {
    const location = `unresolvedCapabilities[${index}]`;
    const record = shape(capability, location,
      ["id", "category", "status", "incrementalCostNOKMaximum", "billingCredentialPermitted", "requiredOutcome", "releaseGate"],
      [], issues);
    if (!record) continue;
    gapIDs.push(capability.id);
    stableID(capability.id, `${location}.id`, issues);
    enumValue(capability.category, capabilityCategories, `${location}.category`, issues);
    if (capability.status !== "BLOCKED_UNTIL_ZERO_COST_COMMERCIAL_TOOL_PASSES") {
      issues.push(`${location}: unresolved capability must remain fail-closed`);
    }
    if (capability.incrementalCostNOKMaximum !== 0 || capability.billingCredentialPermitted !== false) {
      issues.push(`${location}: zero-cost and no-billing limits are mandatory`);
    }
    authoredString(capability.requiredOutcome, `${location}.requiredOutcome`, issues);
    authoredString(capability.releaseGate, `${location}.releaseGate`, issues);
  }
  requireUnique(gapIDs, "unresolvedCapabilities.id", issues);
  for (const id of gapIDs) {
    if (entryIDs.includes(id)) issues.push(`costRegistry: '${id}' cannot be both resolved and unresolved`);
  }
  if (issues.length) throw new ValidationError(issues);
  return registry;
}
