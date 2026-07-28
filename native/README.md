# The Long West native production

This directory contains the native iPhone production system for **The Long
West: EUROCENTRIC**. The website remains source material; it is not the native
runtime specification.

[PRODUCTION_PLAN.md](./PRODUCTION_PLAN.md) is the authoritative phase sequence
from the current foundation to App Store release. It defines dependencies,
deliverables and go/no-go gates. [IMPLEMENTATION_STATUS.md](./IMPLEMENTATION_STATUS.md)
records the dated state actually achieved. [WORK_BREAKDOWN.md](./WORK_BREAKDOWN.md)
translates the phase sequence into concrete work packages, dependencies,
completion evidence and editor decision points.

## Directory contract

- `blueprint/` — Phase 0 editorial contracts, arc matrix, interaction mapping
  and cumulative world traces. These are approved backstage authority and
  cannot enter shipping packages.
- `schemas/` — authoritative public-content, package, editorial and cost-policy
  schemas.
- `tooling/` — dependency-free local validation and package compilation.
- `ios/` — Swift 6 application and modular native runtime.
- `phase1/` — the active five-scene experience-laboratory set, its validators
  and non-shipping contract fixtures.
- `design/phase1/` — editor-selected visual targets and production briefs. These
  remain backstage and non-shipping until rebuilt and separately approved.
- `content/public/` — future approved shipping source. Only allowlisted files
  from this tree may enter a package.
- `content/backstage/` — research, claim registers, verifier findings and
  non-shipping approval/provenance controls. Research never enters compilation;
  the compiler may read an explicit control record but never copies backstage
  data into a package.

## Current production gate

Phase 0 was approved by the editor-in-chief on 23 July 2026. All 24 chapter
contracts and 55 native arcs are `APPROVED`; the exact approved files are bound
by SHA-256 in `blueprint/editor-approval.json`. The four resolved contract
decisions are archived in `blueprint/editor-review.md`, and the complete
readable scope is in `blueprint/editor-approval-brief.md`.

Phase 1 and Port 1 are active and have not passed. The five-scene laboratory
set, selected visual direction, strict `SceneSpec` contract, deterministic
frame planner and non-shipping Harvest fixture are present. Harvest state
variants come from reducer state, its direct response is deterministic, Reduce
Motion preserves the consequence and a hard-kill restoration test rebuilds an
identical frame plan. The Harvest manuscript and interaction recommendation is
also stored as a non-shipping editor-review draft. No production layer set,
audio master, complete playable laboratory scene or vertical slice has passed.
Production package compilation remains fail-closed: Phase 0 approval does not
approve later narration, scenes, audio or public payloads.

The Swift and tooling code includes deterministic reducers and a
grammar-neutral driver for all five interactions, durable write-ahead progress,
strict scene validation, deterministic 2.5D frame planning, a bounded Metal
compositor, reducer-derived visual state, versioned restoration, authored
accessibility routing, causal world replay, signed package generation and
installed-file verification. StoreKit entitlement handling, Apple-hosted pack
materialisation and atomic rollback, CloudKit/APNs release discovery and an
AVAudioEngine/Core Haptics transport now have production-shaped native
implementations and local tests. They have not been exercised against the
project's real Apple services or a physical iPhone. This is not a vertical
slice and does not count as completion of Phase 1 or Port 1.

## Execution order

Codex completes local production, offline tests and simulator-verifiable work
before requesting editor decisions, Apple-account actions or the physical test
iPhone. Provisional manuscripts, voices and assets stay non-shipping until the
editor approves them. Physical-device and live Apple-service checks remain
mandatory release gates; they are deferred to the consolidated final
validation round rather than used to interrupt the current local work queue.

## Local gates

```sh
cd native/tooling
npm test
npm run validate:blueprint
npm run validate:costs
npm run validate:ios
```

The complete local gate, including production preflights, Swift Package tests
and a generated iOS simulator build/test, runs with:

```sh
native/scripts/verify-native.sh
```

`IMPLEMENTATION_STATUS.md` records whether that command currently passes. A
passing component suite is not a substitute for the complete command.

## Physical iPhone gate

When the recorded test iPhone and retained run artifacts are available, the
current First Farmers physical performance and restoration receipt contract is
enforced by one Codex-controlled command:

```sh
node native/scripts/validate-physical-device-protocol.mjs --require-pass
```

It requires exactly one connected, developer-ready physical iPhone in the
iPhone 15 Pro performance class or newer, validates the locked protocol and
schemas, and then validates the canonical receipt and every artifact hash under
`native/quality/physical-device-evidence/`. A missing phone, receipt or artifact
fails explicitly. `--preflight-device` and `--require-evidence` may be run
separately for diagnosis. Neither a simulator nor the protocol document itself
can produce a physical pass, and the command never creates evidence or editor
approval.

This receipt contract currently covers the locked performance, power, thermal,
audio and restoration run classes. Live StoreKit, physical accessibility and
airplane-mode editorial gates remain separate release blockers until their own
retained evidence is bound into the same command.

The physical mute-to-silence requirement of at most 100 milliseconds is not
yet claimable by this receipt contract. The raw report has no retained,
hash-bound mute-request and observed-silence timestamps, so this remains an
evidence-contract gap rather than a declared measurement.

The package compiler writes only to a disposable staging directory. It fails
on backstage paths, forbidden research fields, academic leakage, invalid
interaction grammars, impossible world-effect dependencies, unstable IDs or a
non-zero-cost production dependency. Every chapter is replayed from its hidden
world seed before signing; the canonical package replay must produce the same
final digest twice.

Phase 0 approval cannot sign later public copy by itself. Production compilation
also requires a separate backstage approval for the exact launch collection,
the package's exact payload and its complete public file inventory. The compiler
rechecks those bytes after validation and after staging, so an approved source
cannot drift before signing. Approval records never enter shipping packages.

The resource registry distinguishes cleared local tools from unresolved artistic
capabilities. Narration, score, soundscape and native layer production stay
fail-closed until a zero-cost, commercially cleared method passes the vertical
slice. Existing web visuals without recorded provenance are hashed but blocked
from native reuse. A native derivative must bind to the exact eligible web path
and SHA-256 in the frozen source inventory; generated originals use a separate
project-owned lineage type.

No chapter is production-ready merely because it validates. Editor approval,
finished 2.5D direction, final audio, accessibility parity, offline operation,
exact restoration and the physical-device quality gates remain mandatory.
