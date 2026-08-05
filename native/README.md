# The Long West native production

> **Frozen 5 August 2026.** This iPhone project is inactive and preserved for possible future return.
> Do not delete or continue it without an explicit user decision. Its product, design, architecture and
> production choices do not govern the new Mac exploration; the website is that work's sole starting
> point.

This directory contains the native iPhone production system for **The Long
West: EUROCENTRIC**. The website remains source material; it is not the native
runtime specification.

[PRODUCTION_PLAN.md](./PRODUCTION_PLAN.md) was the authoritative phase sequence
for the attempted path to App Store release. It records dependencies,
deliverables and go/no-go gates as they stood at freezing. [IMPLEMENTATION_STATUS.md](./IMPLEMENTATION_STATUS.md)
records the dated state actually achieved. [WORK_BREAKDOWN.md](./WORK_BREAKDOWN.md)
records the former work packages, dependencies, completion evidence and editor decision points.

The editor-in-chief had locked authored real-time 3D as the global iPhone Journey medium
on 30 July 2026. The durable decision is
[`blueprint/real-time-3d-medium-lock-2026-07-30.md`](./blueprint/real-time-3d-medium-lock-2026-07-30.md).
That decision remains part of the frozen iPhone record and does not govern Mac work.

## Directory contract

- `bibles/` — shared production standards. `experience-bible.md` controls the
  complete felt chapter flow; the interaction, visual, audio and production
  bibles control their disciplines inside that standard.
- `blueprint/` — Phase 0 editorial contracts, arc matrix, interaction mapping
  and cumulative world traces. These are approved backstage authority and
  cannot enter shipping packages.
- `schemas/` — authoritative public-content, package, editorial and cost-policy
  schemas.
- `tooling/` — dependency-free local validation and package compilation.
- `ios/` — Swift 6 application and modular native runtime.
- `phase1/` — the legacy five-scene 2.5D experience-laboratory set, its
  validators and non-shipping contract fixtures.
- `design/phase1/` — editor-selected visual targets and production briefs. These
  remain backstage and non-shipping until rebuilt and separately approved.
- `content/public/` — future approved shipping source. Only allowlisted files
  from this tree may enter a package.
- `content/backstage/` — research, claim registers, verifier findings and
  non-shipping approval/provenance controls. Research never enters compilation;
  the compiler may read an explicit control record but never copies backstage
  data into a package.

## Production gate at freezing

Phase 0 was approved by the editor-in-chief on 23 July 2026. All 24 chapter
contracts and 55 native arcs are `APPROVED`; the exact approved files are bound
by SHA-256 in `blueprint/editor-approval.json`. The four resolved contract
decisions are archived in `blueprint/editor-review.md`, and the complete
readable scope is in `blueprint/editor-approval-brief.md`.

The former 2.5D Phase 1 visual route is suspended. The approved Chapter 01
real-time 3D projection has five cells, six sequences and six unchanged causal
interactions. A signed RealityKit substrate and five continuity cells exist,
but every visible cell is classified `TECHNICAL_GREYBOX_CONTINUITY_PROOF` and
is blocked from Release. It proves selected runtime contracts only; it is not
visual evidence.

The editor-approved requirements reset of 4 August 2026 is recorded in
[`production/3d/chapter01/REQUIREMENTS_RESET_2026-08-04.md`](./production/3d/chapter01/REQUIREMENTS_RESET_2026-08-04.md).
The active sequence at freezing was method proof, complete Chapter 01 greybox, complete
`0:00–2:30` production slice, remaining Chapter 01 blocks and complete chapter.
Both `CHAPTER_01_3D_SLICE_READY` and `CHAPTER_01_3D_CHAPTER_READY` remain
`CANDIDATE`. Production package compilation remains fail-closed: neither Phase
0 approval nor the requirements reset approves narration, scenes, audio or a
public payload.

The Swift and tooling code includes deterministic reducers and a
grammar-neutral driver for all five interactions, durable write-ahead progress,
strict scene validation, legacy deterministic 2.5D frame planning, a bounded
Metal compositor, reducer-derived visual state, versioned restoration, authored
accessibility routing, causal world replay, signed package generation and
installed-file verification. StoreKit entitlement handling, Apple-hosted pack
materialisation and atomic rollback, CloudKit/APNs release discovery and an
AVAudioEngine/Core Haptics transport now have production-shaped native
implementations and local tests. They have not been exercised against the
project's real Apple services or a physical iPhone. This is not a vertical
slice and does not count as completion of Phase 1 or Port 1.

## Former execution order

Chapter 01's experience projection, premium sculptural direction and revised
proof model had been approved. The planned next work was the method proof and
full greybox before the complete 2:30 slice. That sequence is preserved as
history and must not be executed while the project is frozen.

## Historical local gates

```sh
cd native/tooling
npm test
npm run validate:blueprint
npm run validate:costs
npm run validate:ios
```

The complete local gate, including production preflights, Swift Package tests
and a generated iOS simulator build/test, was run with:

```sh
native/scripts/verify-native.sh
```

`IMPLEMENTATION_STATUS.md` records whether that command currently passes. A
passing component suite is not a substitute for the complete command.

## Physical iPhone gates

The older general physical protocol remains useful infrastructure and legacy
2.5D evidence:

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

That command cannot qualify the new Chapter 01 3D slice or chapter. Their
active fail-closed gates are evaluated with:

```sh
node native/scripts/validate-chapter-01-3d-gates.mjs --json
node native/scripts/validate-chapter-01-3d-gates.mjs --require-slice-pass
node native/scripts/validate-chapter-01-3d-gates.mjs --require-chapter-pass
```

The 3D physical receipt binds the exact app record, signed package, device and
OS; retains raw trace roles; requires three warmed runs; derives dropped-frame
rate from retained counts; and records the worst result. Manual visual and
editor evidence binds an uncut capture and explicit decision. Until these
artifacts exist, both 3D gates remain `CANDIDATE`.

Live StoreKit, physical accessibility and airplane-mode editorial gates remain
separate release blockers until their retained evidence is bound to the
corresponding complete candidate.

The legacy physical mute-to-silence requirement of at most 100 milliseconds is
not yet claimable. Its raw report has no retained, hash-bound mute-request and
observed-silence timestamps, so it remains historical evidence-contract debt,
not a measurement for the new 3D gate.

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
capabilities. Narration, score, soundscape and native 3D production stay
fail-closed until a zero-cost, commercially cleared method passes the vertical
slice. Existing web visuals without recorded provenance are hashed but blocked
from native reuse. A native derivative must bind to the exact eligible web path
and SHA-256 in the frozen source inventory; generated originals use a separate
project-owned lineage type.

No chapter is production-ready merely because it validates. Editor approval,
finished authored real-time 3D direction, final audio, accessible equivalence,
offline operation, durable checkpoint restoration and the physical-device
quality gates remain mandatory.
