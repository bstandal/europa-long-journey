# Native Phase 0 blueprint

These files define the editorial and structural baseline for the native Journey. They are backstage production data, not shipping content packages.

## Files

- `chapter-catalog.json`: the canonical launch order, stable content IDs, titles, periods, access state and current locked thesis for all 24 chapters.
- `chapter-contracts.json`: 24 approved editorial contracts covering thesis, Europe-centred causal spine, required emphases, governing judgement, ending and handoff.
- `arc-matrix.json`: 55 approved native arcs of 8–15 minutes. Every one of the current 290 movements appears exactly once, with direct references to its principal native interactions and world effects.
- `world-traces.json`: 48 persistent roads, borders, cities, institutions, networks, inheritances and ruptures forming the cumulative world. It contains 106 authored arc effects—99 caused by principal interactions and seven by named non-interactive beats—plus 152 curated later activation transitions.
- `interaction-mapping.json`: all 122 current web interactions mapped to an arc, stable native ID, role, grammar, disposition, world trace and world effect.
- `authored-interaction-effects-01-12.json` and `authored-interaction-effects-13-24.json`: the explicit action-to-consequence chains for every principal interaction. These ledgers are the authority used to regenerate mapping and world effects; no token match or hash fallback may assign historical meaning.
- `editor-review.md`: the four contract decisions resolved by the editor-in-chief before approval.
- `editor-approval-brief.md`: generated, readable review of all 24 contracts and 55 arcs, with exact source fields rather than paraphrases.
- `editor-approval.json`: approved authority record. Production requires matching SHA-256 digests of the contracts and arcs plus one aggregate digest over the catalog, both authored-effect ledgers, interaction mapping and cumulative world.
- `source-inventory.json`: an exact SHA-256 freeze of the 24 web chapter sources,
  their 290 movements, 122 interaction-bearing movements and the web runtime
  files needed to interpret them.
- `source-asset-provenance.json`: SHA-256 inventory of every existing web visual,
  its recorded source rights and a fail-closed eligibility flag. Missing provenance
  blocks reuse; a web plate is never a finished native asset. Native derivative
  lineage must repeat the inventory's exact path, bytes, hash and obligations.
  Generated-original lineage uses a separate schema branch and cannot claim a web
  path.
- `delivery-plan.json`: the locked base install, seven paid package groups,
  entitlement, byte ceilings and signed atomic activation contract.
- `enrich.mjs`: deterministic normalisation that rebuilds the implementable references without touching contracts.
- `validate.mjs`: dependency-free structural gate for the complete Phase 0 blueprint.
- `generate-editor-approval-brief.mjs`: deterministic generator and stale-file check for the editor review artifact.

## Authority and status

- Every chapter contract and arc chapter is `APPROVED`. Only the editor-in-chief may reopen an approved contract.
- Research and verification may identify a concrete F1–F7 defect. They may not rebalance, decentre, moralise or revise a contract.
- `KEEP` preserves an interaction's historical mechanism, not its TypeScript component or web gesture. Every item is rebuilt for the native runtime.
- No interaction is currently marked `REMOVE`: every source item contains a causal contribution. Twenty-three lighter items are merged into larger native beats, and twenty-six require a behavioural rewrite.
- The mapping resolves to 99 principal native interactions and 23 supporting source interactions. Every arc carries one to three principal interactions.
- Every `MERGE` item has a stable merge group and points to a principal native interaction in the same arc. The supporting item inherits that interaction's world trace and effect.
- `beatID: "UNASSIGNED"` is deliberate. Arc placement is fixed before scene writing; a beat ID cannot be invented before the beat exists.
- Arc durations are production targets and never appear as public interface copy.
- World traces are persistent historical state. They are not collectibles, scores or rewards.
- Every later activation fixes its target chapter, target arc, operation, before-state, after-state and stable effect ID. Allowed operations are `reactivate`, `transform`, `contest` and `supersede`.
- `trace-continent-split-open` originates in `europe-at-war-arc-01`, where the 1918 imperial rupture occurs. Later destruction and division transform that existing trace.

## Locked launch access

The free chapters are keyed only by stable content ID:

- `first-farmers`
- `europe-holds-the-line`
- `european-world`

## Validation

From the repository root:

```sh
node native/blueprint/enrich.mjs --check
node native/blueprint/generate-editor-approval-brief.mjs --check
node native/blueprint/validate.mjs
node native/scripts/verify-web-source-inventory.mjs
node native/scripts/build-source-asset-provenance.mjs --check
```

The first command proves that the generated mapping and world model are current; run it without `--check` only after an authored ledger changes. The approval brief check prevents a readable
review from drifting behind the JSON. The final command rejects missing IDs, invalid merge
targets, effects attached to the wrong trace, state-chain gaps, bad movement or
arc placement, fewer than one or more than three principal interactions in an
arc, altered approval status and the known 1918 origin error.

## Approved editor decisions

The editor-in-chief approved the complete Phase 0 set on 23 July 2026 and chose
all four resolutions recorded in `editor-review.md`. Chapter 06 hands directly
to Chapter 07; its eastern Roman continuation remains a later world activation.
Chapter 24 retains a fact lock of 20 July 2026 and must pass a fresh
primary-source verification before its native package is accepted.
