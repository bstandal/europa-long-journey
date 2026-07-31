import { createHash } from "node:crypto";

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function clone(value) {
  return structuredClone(value);
}

function same(left, right) {
  return canonical(left) === canonical(right);
}

function utf8Compare(left, right) {
  return Buffer.compare(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
}

function sortedAttributes(attributes = []) {
  return [...attributes].sort((left, right) => utf8Compare(left.key, right.key));
}

function setAttribute(attributes, value) {
  return sortedAttributes([
    ...attributes.filter((item) => item.key !== value.key),
    clone(value),
  ]);
}

function issue(issues, location, message) {
  issues.push(`${location}: ${message}`);
}

function makeSeedState(seed, location, issues) {
  if (!seed || typeof seed !== "object" || Array.isArray(seed)
      || !Array.isArray(seed.nodes) || !Array.isArray(seed.traces)) {
    issue(issues, `${location}.worldSeed`, "nodes and traces are required for causal replay");
    return undefined;
  }
  const state = { nodes: new Map(), traces: new Map(), effects: new Map() };
  for (const [index, node] of seed.nodes.entries()) {
    if (typeof node?.id !== "string") continue;
    if (state.nodes.has(node.id)) {
      issue(issues, `${location}.worldSeed.nodes[${index}].id`, `duplicate seed node '${node.id}'`);
      continue;
    }
    state.nodes.set(node.id, {
      blueprint: { ...clone(node), attributes: sortedAttributes(node.attributes) },
      visibility: "hidden",
      revision: 0,
    });
  }
  for (const [index, trace] of seed.traces.entries()) {
    if (typeof trace?.id !== "string") continue;
    if (state.traces.has(trace.id)) {
      issue(issues, `${location}.worldSeed.traces[${index}].id`, `duplicate seed trace '${trace.id}'`);
      continue;
    }
    if (!state.nodes.has(trace.origin) || !state.nodes.has(trace.destination)) {
      issue(
        issues,
        `${location}.worldSeed.traces[${index}]`,
        `seed trace '${trace.id}' requires seeded origin and destination nodes`,
      );
      continue;
    }
    state.traces.set(trace.id, { blueprint: clone(trace), state: "dormant" });
  }
  return state;
}

function cloneState(state) {
  return {
    nodes: new Map([...state.nodes].map(([id, value]) => [id, clone(value)])),
    traces: new Map([...state.traces].map(([id, value]) => [id, clone(value)])),
    effects: new Map([...state.effects].map(([id, value]) => [id, clone(value)])),
  };
}

function applyEffect(state, effect, location, issues) {
  if (!effect || typeof effect !== "object" || typeof effect.id !== "string") return;
  const previous = state.effects.get(effect.id);
  if (previous !== undefined) {
    if (!same(previous, effect)) issue(issues, location, `effect '${effect.id}' conflicts with its previous definition`);
    return;
  }

  switch (effect.mutation) {
  case "reveal-node": {
    const node = effect.node;
    if (!node || typeof node.id !== "string") return;
    const existing = state.nodes.get(node.id);
    if (existing === undefined) {
      state.nodes.set(node.id, {
        blueprint: { ...clone(node), attributes: sortedAttributes(node.attributes) },
        visibility: "revealed",
        revision: 0,
      });
    } else if (existing.blueprint.kind !== node.kind || !same(existing.blueprint.position, node.position)) {
      issue(issues, location, `reveal-node conflicts with seeded node '${node.id}'`);
      return;
    } else if (existing.visibility === "hidden") {
      existing.blueprint.form = node.form;
      existing.blueprint.attributes = sortedAttributes(node.attributes);
      existing.visibility = "revealed";
      existing.revision += 1;
    } else if (existing.visibility === "revealed") {
      if (existing.blueprint.form !== node.form
          || !same(existing.blueprint.attributes, sortedAttributes(node.attributes))) {
        issue(issues, location, `reveal-node changes an already revealed node '${node.id}'`);
        return;
      }
    } else {
      issue(issues, location, `reveal-node attempts to rewind transformed node '${node.id}'`);
      return;
    }
    break;
  }
  case "establish-trace": {
    const trace = effect.trace;
    if (!trace || typeof trace.id !== "string") return;
    if (!state.nodes.has(trace.origin)) {
      issue(issues, location, `establish-trace '${trace.id}' is missing origin node '${trace.origin}'`);
      return;
    }
    if (!state.nodes.has(trace.destination)) {
      issue(issues, location, `establish-trace '${trace.id}' is missing destination node '${trace.destination}'`);
      return;
    }
    const existing = state.traces.get(trace.id);
    if (existing === undefined) {
      state.traces.set(trace.id, { blueprint: clone(trace), state: "active" });
    } else if (!same(existing.blueprint, trace)) {
      issue(issues, location, `establish-trace conflicts with seeded trace '${trace.id}'`);
      return;
    } else if (existing.state === "dormant") {
      existing.state = "active";
    } else if (existing.state !== "active") {
      issue(issues, location, `establish-trace attempts to reactivate superseded trace '${trace.id}'`);
      return;
    }
    break;
  }
  case "transform-node": {
    const existing = state.nodes.get(effect.nodeID);
    if (existing === undefined) {
      issue(issues, location, `transform-node is missing node '${effect.nodeID}'`);
      return;
    }
    existing.blueprint.form = effect.form;
    for (const value of effect.attributes ?? []) {
      existing.blueprint.attributes = setAttribute(existing.blueprint.attributes, value);
      existing.revision += 1;
    }
    existing.visibility = "transformed";
    existing.revision += 1;
    break;
  }
  case "set-node-attribute": {
    const existing = state.nodes.get(effect.nodeID);
    if (existing === undefined) {
      issue(issues, location, `set-node-attribute is missing node '${effect.nodeID}'`);
      return;
    }
    existing.blueprint.attributes = setAttribute(existing.blueprint.attributes, effect.value);
    existing.revision += 1;
    break;
  }
  case "supersede-trace": {
    const existing = state.traces.get(effect.traceID);
    if (existing === undefined) {
      issue(issues, location, `supersede-trace is missing trace '${effect.traceID}'`);
      return;
    }
    existing.state = "superseded";
    break;
  }
  default:
    return;
  }
  state.effects.set(effect.id, clone(effect));
}

function chapterEffects(chapter) {
  const effects = [];
  for (const arc of chapter?.arcs ?? []) {
    for (const beat of arc?.beats ?? []) {
      if (beat?.interaction) effects.push(...(beat.interaction.completionEffects ?? []));
      else effects.push(...(beat?.completionEffects ?? []));
    }
  }
  effects.push(...(chapter?.completionEffects ?? []));
  return effects;
}

function applyChapter(state, chapter, location, issues) {
  for (const [index, effect] of chapterEffects(chapter).entries()) {
    applyEffect(state, effect, `${location}.effects[${index}]`, issues);
  }
}

function fingerprint(state) {
  const snapshot = {
    nodes: [...state.nodes.entries()].sort(([left], [right]) => utf8Compare(left, right)).map(([id, value]) => ({
      id,
      kind: value.blueprint.kind,
      form: value.blueprint.form,
      position: value.blueprint.position,
      attributes: sortedAttributes(value.blueprint.attributes),
      visibility: value.visibility,
      revision: value.revision,
    })),
    traces: [...state.traces.entries()].sort(([left], [right]) => utf8Compare(left, right)).map(([id, value]) => ({
      id,
      ...value.blueprint,
      state: value.state,
    })),
    appliedEffectIDs: [...state.effects.keys()].sort(),
  };
  return createHash("sha256").update(canonical(snapshot)).digest("hex");
}

/**
 * Replays every chapter independently from the authored hidden/dormant seed,
 * then replays the package in canonical chapter-array order. The report is
 * deterministic and suitable for a compiler gate; all defects are appended to
 * the caller's issue list so structural validation can report them together.
 */
export function validateWorldReplay(payload, location = "contentPackage", issues = []) {
  const seedState = makeSeedState(payload?.worldSeed, location, issues);
  if (seedState === undefined || !Array.isArray(payload?.chapters)) {
    return { perChapter: [], cumulativeDigest: undefined };
  }

  const perChapter = [];
  for (const [index, chapter] of payload.chapters.entries()) {
    const state = cloneState(seedState);
    applyChapter(state, chapter, `${location}.chapters[${index}]`, issues);
    perChapter.push({ chapterID: chapter?.id, digest: fingerprint(state) });
  }

  const firstCumulative = cloneState(seedState);
  for (const [index, chapter] of payload.chapters.entries()) {
    applyChapter(firstCumulative, chapter, `${location}.canonicalReplay.chapters[${index}]`, issues);
  }
  const secondCumulative = cloneState(seedState);
  for (const [index, chapter] of payload.chapters.entries()) {
    applyChapter(secondCumulative, chapter, `${location}.determinismReplay.chapters[${index}]`, issues);
  }
  const cumulativeDigest = fingerprint(firstCumulative);
  const repeatedDigest = fingerprint(secondCumulative);
  if (cumulativeDigest !== repeatedDigest) {
    issue(issues, `${location}.worldSeed`, "identical canonical replay produced a different final digest");
  }
  return { perChapter, cumulativeDigest };
}
