# Codex-only production bible

## Authority

The user is editor-in-chief. Every chapter begins with an approved contract
fixing thesis, Europe-centred causal spine, required emphases, governing
judgement and ending. Only the user can reopen those decisions.

Research and verification are backstage controls. A verifier returns only
`PASS`, `NARROW`, `REPLACE`, `REMOVE` or `EDITOR_DECISION` with F1–F7. It never
writes public prose. A narrative writer applies the smallest factual repair in
the approved voice. Anything that may change thesis, weight, allegiance or
ending stops for the user.

## Production separation

- `blueprint/` contains Phase 0 contracts and planning data.
- `content/backstage/` contains research, claims, sources and findings.
- `content/public/` contains only material allowed to ship.
- The compiler starts with an allowlisted public path. It never copies a mixed
  tree and removes private data afterward.
- Editorial leakage and backstage fields are release-blocking failures.

## Asset line

For every visible or audible asset, store source, creator or model, version,
licence, commercial rights, transformation history, prompts when applicable,
selected master and final hashes. Non-commercial, no-derivatives, editorial-use
only or unclear rights are prohibited.

Codex produces and reviews assets through separate passes:

1. historical/material brief;
2. complete composition or sound concept;
3. layer/stem production;
4. visual or acoustic defect inspection;
5. anachronism and continuity inspection;
6. integration in the actual scene;
7. physical iPhone review by the user.

No raw generated output earns approval by existing. Every correction is made
to a preserved master; regeneration is not assumed to remain reproducible.

## Zero-cost gate

The cost and licence registry is authoritative. A production dependency fails
when incremental cost is non-zero, a billing credential is required, a trial
can roll into payment, commercial rights are unclear or the licence is
non-commercial. Existing Apple membership and existing Codex access are treated
as already covered.

No external narrator, composer, artist, tester, historian, consultant or other
human contributor may enter the pipeline. If local or included tools cannot
meet the fixed artistic bar, production stops for an editor decision; quality
is not lowered and spending is not silently introduced.

## Quality ratchet

A later improvement to shared typography, rendering, interaction, audio,
haptics, accessibility, persistence or packaging triggers an audit of every
earlier chapter. The weakest required chapter determines release readiness.
Nothing is frozen merely because it was produced earlier.

## Causal world compilation

Every shipping package declares the hidden nodes and dormant traces needed by
its independently selectable chapters. The compiler replays each chapter from
that seed, then replays the package twice in collection chronology. A missing
node, missing trace, conflicting transformation or different final digest stops
the build.

An individually signed package is a build artefact, not release authority. All
eight launch payloads must also pass `validate:launch-assembly` together. That
gate requires identical world seeds, exact package ownership and chapter order,
globally unique effect IDs and one deterministic 24-chapter final world hash.
No launch package may be submitted to App Review until the combined gate has
passed against the exact payload bytes selected for submission.

The runtime uses the same seed semantics. The set of completed chapters is
reconstructed in collection order when the cumulative world is rebuilt, so the
same completed history has one state even when the user entered its chapters in
a different order. Seed objects are public experience data. They cannot carry
sources, confidence, historiography or verifier findings.

## Download queue semantics

`Download all` derives its queue from the validated launch manifest and active
installed-package index. It excludes the essential pack and current installed
generations, then retains the delivery-plan order of `paid-pack-01` through
`paid-pack-07`. The displayed storage figure is the sum of the remaining
packages' `maximumInstalledBytes` values and is labelled as an `up to` storage
budget. It is not presented as an observed download size or exact transfer-byte
count.

One explicit package request is downloaded, verified and activated at a time.
A queue-pause request is accepted only while that work is active. It finishes
the current atomic package, then holds before the next package. The interface
names this action `Pause after this package`; it never claims that the app can
freeze an Apple-managed transfer at an exact byte position.

Apple's system-transfer states remain separate from the queue state. The app
reflects `began`, `paused`, `downloading`, `finished` and `failed` as received.
`began` can mean a first start or a return from a system pause; a return is
derived only when the preceding observed state for that package was `paused`.
System pause never appears as a user-requested queue hold, and `finished` does
not mean that package verification and activation have finished.

Already installed packages remain playable offline. A failed, corrupt,
incomplete or out-of-space package never replaces the active verified
generation. The failed head and remaining queue stay blocked until the user
explicitly retries or removes that head. Queue intent is stored in a
schema-versioned, digest-checked atomic journal. Cold start reconciles only the
contiguous current package prefix against the installed index. A journaled
running queue waits for an explicit restoration policy before it can restart;
a journaled user pause remains paused under every automatic restoration policy.
