# Native implementation status

Status date: 28 July 2026

## Current UX implementation closure — 28 July 2026

This section supersedes the older current-result claims below. Those entries
remain as dated historical evidence and must not be read as the state of the
present tree.

The First Farmers non-shipping runtime and the shared chapter shell now
implement the agreed chapter journey:

- `Begin`, `Resume` and deliberate review entry can start the verified authored
  sound directly. The former per-scene sound choice is removed. A fixed sound
  control pauses and resumes at the stored sample position, while lifecycle,
  route and VoiceOver transitions remain fail-closed.
- Chapter chrome keeps `Road`, visited-scene navigation and sound available.
  Narrative text scrolls independently of the fixed instruction and action
  footer, including the linear accessibility layout.
- Completed beats are archived as sealed, read-only review records. `Previous`,
  `Next`, `Return to current` and completed-chapter `Done` do not rewind the
  causal route or replay interaction effects.
- Stable paragraph anchors restore the active reading position. Review stores
  its reading position independently.
- Included-chapter map and road entries share one route binding. Completed and
  in-progress chapters open as review and resume respectively. The prologue
  offers a button beside its horizontal gesture, and commerce remains one
  purchase/download sheet.
- Content failures are typed. An unresolved viewport no longer presents a
  missing-package message, while missing, corrupt and incompatible content keep
  their distinct recovery paths.

Current automated verification for this tree is green:

- native script tests: `105/105`;
- Phase 1 tests: `6/6`;
- Phase 2 tests: `27/27`;
- narration and authored-audio tests: `155/155`;
- native tooling tests: `236/236`;
- SwiftPM tests: `872/872`;
- connected Xcode unit and UI tests: `1006/1006` on an iOS Simulator;
- isolated signed live tests: `2/2`, including all 17 First Farmers beats and
  all six principal interactions; and
- ordinary Release app development-resource boundary: `PASS`.

The complete run exposed a timing race between ephemeral responsive-audio
cleanup and the next Transform input. Scene mutation now waits for the cleanup
token to quiesce and then revalidates route authority. The dedicated regression,
the original Continent Remade UI case and the complete Xcode run all pass after
the repair.

The review-readiness validator is still `CANDIDATE`, with eight evidence
blockers: stale automated-suite binding, stale fixture-determinism binding,
pending simulator-traversal evidence, interaction recordings without the
current subject SHA, stale restore-matrix binding, stale audio-restore binding,
no accessibility `PASS` receipt and no offline `PASS` receipt. These receipts
have not been rewritten from simulator results.

The physical-device preflight fails because the registered phone, `Basta 16`,
is unavailable, Developer Mode is disabled and its developer disk image is
unavailable. The required
`quality/physical-device-evidence/first-farmers.receipt.json` does not exist.
The final manual Simulator visual inspection is also pending because the Mac is
locked. Neither condition is reported as a pass.

Production authority remains unchanged:

- `content/public/` contains zero files;
- there is no approved, signed, complete essential launch package or shipping
  trust chain;
- visual, narration, score, soundscape, haptic and complete-package editor
  approvals remain open;
- Chapters 13 and 21 remain development slices, and the other launch packages
  are absent; and
- physical VoiceOver, interruption, Silent Mode, Bluetooth/AirPlay,
  hard-kill, performance, battery, StoreKit, hosted-download and offline gates
  remain unexecuted on a release candidate.

## Gate state

Phase 0 passed on 23 July 2026. All 24 chapter contracts and all 55 arc
records are `APPROVED`; `blueprint/editor-approval.json` binds the approved
contracts, arc matrix and aggregate editorial state by SHA-256.

Phase 1 and Port 1 remain `IN_PRODUCTION`.

- `content/public/` contains zero files.
- No complete production scene exists.
- No complete native chapter exists.
- No native visual or audio asset has shipping approval.
- No shipping content package exists.
- No narration candidate has passed the complete master and artistic gates.

The signed five-grammar package, the Harvest Metal proof, DEBUG product routes,
simulator captures and generated audio are non-shipping production evidence.
None changes this gate state.

## How status claims are separated

### Green now

The last complete `native/scripts/verify-native.sh` sequence passed on 25 July
2026. It is retained as a historical baseline rather than a claim about every
later production edit:

- native script tests: `59/59`;
- Phase 1 tests: `6/6`;
- Phase 2 tests: `12/12`;
- narration tests: `145/145`;
- native tooling tests: `202/202`;
- SwiftPM tests: `605/605`;
- connected Xcode unit and UI tests: `633/633` on the iPhone 17 Pro, iOS 26.5
  simulator;
- focused Thread Sanitizer tests: `134/134`, with zero findings;
- Release `.app` development-resource boundary scan: `PASS`.

The Thread Sanitizer receipt is SHA-256
`999b152a1f157e98fd6ba64ea87b43320c8dd9935fb4ced1b8d7a43ab021a4db`
and binds source digest
`16f6dbbef42dcc74280848ec6ab2d750670e3041368e29733cb3f5a9e217d538`.
The sanitizer and Xcode results are simulator evidence, not physical-device or
shipping approval.

A separate runtime-authority closure on 26 July 2026 passed after the stable
tree above:

- SwiftPM package tests: `758/758`, with the separately blocked
  `ThreeRecordsResponsiveAudioWorkObjectTests` suite explicitly excluded;
- focused runtime, persistence, lifecycle and authority unit tests: `148/148`;
- connected authority, FIFO and ordered-exit UI tests: `18/18` on the iPhone
  17e, iOS 26.5 simulator;
- Release `.app` boundary validator: `PASS`, with zero hits for the new DEBUG
  diagnostics and fault-injection symbols in the app or DramaticAudio binary.

The authoritative result bundles are
`longwest-focused-authority-lifecycle-unit-final-v3.xcresult` and
`longwest-ui-runtime-authority-fifo-ordered-exit-final-v3.xcresult`. The four
ordered-exit UI cases also passed independently before the consolidated run.
Two independent code audits returned `PASS` for the FIFO, transactional audio,
sidecar-retirement and successor-authority failure seams. These remain local
and simulator results; they do not change the physical-device gate.

After the later Harvest, Longhouse and Household Crosses changes, the current
permitted tree has these additional results:

- SwiftPM package tests: `791/791`, with the separately blocked suite excluded;
- Household Crosses named-anchor, reached-state latching, restoration,
  Reduce Motion, reachability and audio-phase coverage: `PASS`;
- Longhouse controller, visual, timeline, grip and accessibility focus:
  `57/57`, followed by an independent `PASS` review;
- generic Debug and Release iOS Simulator app builds: `PASS`;
- rebuilt Release `.app` boundary-only validation: `PASS`;
- receipt and output validation for the five permitted responsive-audio work
  objects: `PASS`; their exact work-object and receipt bindings are recorded
  below.

The connected UI result bundles and sanitizer receipt above predate these
production edits. They remain evidence for their captured commits and will be
rerun at the next complete permitted verification freeze. The generic Release
build and boundary-only scan are current for this permitted tree.

### Chapter 01 technical live-test projection — 26 July 2026

The signed, non-shipping runtime fixture now projects all three First Farmers
arcs, all 17 beats, all six principal interactions, all 17 scene and
accessibility bindings, the six real responsive-audio programs and their 30
timelines. Its manifest binds 231 payload files at `manifestDigest`
`589ea9be981a4bd6b8d8569b0ebd6a98ed1c856d8e54d39dc5281d4e9b513f53`;
the compiled fixture contains 232 physical files including the manifest and
138,253,495 bytes. Narration
remains excluded at the editor decision gate. The fixture is reproducible
byte-for-byte and cannot grant production, asset, narration, editorial or
physical-device approval.

Current local runtime evidence for this tree is:

- SwiftPM: `806/806`, including the focused signed A Continent Remade
  three-stage runtime test;
- signed fixture: `10/10`, including complete 17-beat traversal and real Metal
  preparation of every First Farmers scene;
- Scene Metal compositor: `16/16`;
- native tooling: `235/235`;
- the current Three Records signed-fixture UI preparation test: `1/1`, plus a
  clean manual install and direct live-configuration launch at that beat;
- a prior production-route UI traversal opens all `17/17` First Farmers beats;
  the current fixture integrity and direct Three Records route are retested;
- native script tests: `83/83`;
- focused Thread Sanitizer recapture: `194/194`, with zero findings; receipt
  SHA-256
  `16f54f1347d6a92cb611c21055c5af23443ce272718d90ef3d3a132fc5d9c9e7`
  binds source digest
  `77c98883e64af618205c419c54314d43ff50abfab36e63348c0efed23b46945d`;
- unsigned shipping-equivalent Release build for the ARM64 iPhone target,
  explicitly without coverage instrumentation: `PASS`, 17,383,246 bytes and
  33 files;
- unsigned release-optimized `NON_SHIPPING_LIVE_TEST` ARM64 build: `PASS`,
  155,677,766 bytes, 266 files and 93 M4A assets; and
- Release simulator development-boundary scan: `PASS` for its captured build.

The current integrated Xcode UI gate is `FAIL`, not green: `42/46` tests pass.
The four reproducible failures are
`testResponsiveChapterSoundRequiresChoiceResumeAndColdRestoreConsent`,
`testSignedEuropeanWorldColdRestoresTraceAndExactAudioCursor`,
`testSignedEuropeanWorldPhysicalTraceEngagesResponsiveAudio` and
`testSignedEuropeanWorldSilenceSurvivesLifecycleButNotChapterChange`. The
first and third hit the fail-closed 250 ms cursor-writer watchdog under rapid
Trace input. The other two restore `waiting` rather than the expected
same-process `engaged` phase after lifecycle activation. Focused reruns
reproduce both classes of failure. Passing package, fixture, sanitizer and
single-route tests do not override this red integrated result.

The Metal view is paused outside display requests and short authored response
windows. Texture residency is now pruned to the exact active composition, so
it cannot grow across chapters, scenes or previously visited state variants.
This is a resource-bounded architecture result, not a physical memory,
thermal or battery measurement.

The 91 provisional Chapter 1 PCM work files total 750,820,004 bytes. A pinned
distribution probe now projects them to 90 AAC-LC files and one ALAC seam-safe
fallback at 85,479,069 bytes, an 88.615 percent reduction. The signed live
fixture uses those exact receipt-bound M4A bytes. Both source and encoded
assets remain explicitly non-shipping. The release-candidate boundary hard-caps
the shell at 100,000,000 bytes, essential content at 750,000,000 bytes and the
complete base app at 850,000,000 bytes, independently of mutable delivery-plan
values. It measures the actual app file tree and binds its digest. A shipping
workflow must still validate and publish the same sealed archive; sequential
validation of a writable `.app` is not an atomic publication guarantee.

The 125 ms crash-cursor store now precreates three slots and performs one file
`fsync` for each changed checkpoint, without per-tick rename or directory
`fsync`. A 30-minute active session can still request 14,400 file `fsync`
calls, so physical energy measurement remains mandatory. The compiler now
caps estimated decoded responsive audio at 100,000,000 steady-state bytes and
200,000,000 transition bytes for launch and future packages. First Farmers
passes at 97,920,000 and 115,200,000 bytes. The distribution encoding reduces
disk use, not this decoded working set. The estimate does not include the rest
of the process footprint and leaves only 2,080,000 bytes of steady audio-budget
headroom.

The physical protocol now includes separate, explicitly paired Harvest and
complete First Farmers battery sets. Each set requires three alternating
30-minute app and static-reference runs. The full-chapter run covers the
28-minute authored traversal. The unchanged release budgets remain 60 fps,
p99 displayed frame time at or below 25 ms, sustained physical footprint below
500 MiB, thermal state no worse than `fair`, absolute battery loss at or below
8 percentage points and no more than 3 percentage points above its paired
static reference. Physical execution remains pending and `not tested` remains
a failure.

### Artistic and editor gates

Visual composition, interaction purpose, narration performance, score,
soundscape, haptics, complete scene direction and complete chapter quality
require their own approvals after production candidates exist. Passing a hash,
schema, deterministic replay or simulator test does not grant artistic,
production-master or shipping authority.

### Physical and live Apple final gate

Real StoreKit, Apple-hosted asset packs, CloudKit, APNs and the recorded test
iPhone remain mandatory. They are deliberately deferred until all safe local,
offline and simulator work has been exhausted. No current result claims a
physical floor-device, thermal, battery, hard-kill, live-purchase, live-push or
live-hosted-download pass.

## Approved product and content authority

- 24 approved editorial contracts, 55 named native arcs, 290 source movements,
  99 principal native interactions, 48 cumulative world traces, 106 authored
  arc effects and 152 later activations.
- Public schemas contain no sources, confidence fields, historiography,
  counterarguments, methodology or verifier output. Research and F1-F7
  findings remain physically backstage.
- Matching Swift and Node contracts cover collection, chapters, arcs, beats,
  scenes, all five interaction grammars, responsive audio, accessibility,
  releases and saved state.
- Blueprint projection rejects drift in approved theses, arcs, interaction
  identities and world effects.
- Development, launch and future-release trust domains are separate. Release
  builds reject the First Farmers development package, its key markers and the
  Harvest proof assets.

## Native runtime foundation

- Portrait-only iOS 26 Swift 6 project with the required performance-gaming
  capability.
- Deterministic journey reducers, per-chapter sessions, cumulative world replay,
  authenticated snapshots and exact scene, camera and audio save fields.
- The progress boundary accepts only an exact conditional transition: prior
  sequence and state, event and candidate state. It reloads the complete
  snapshot and journal authority under a canonical-directory lock, reduces the
  event independently and writes only when every value agrees.
- A grammar-neutral interaction driver and visible-state adapters cover
  `trace`, `allocate`, `assemble`, `pressure` and `transform`. Touch and
  VoiceOver issue the same domain actions and restore the same reducer state.
- New authored `trace` interactions can bind stable, unique anchor IDs in exact
  route order. Their reached-state bindings must cover every nonterminal anchor
  once and in that same order. The durable reached-anchor count selects the
  latched visual state after restoration and under Reduce Motion.
- The content cross-binding gate rejects a named Trace anchor outside its bound
  interaction-target polygon. This makes the authored route's entire causal
  sequence reachable in the same master-space geometry used by touch input.
- `ChapterSceneRuntimeController` serialises preflight, durable append,
  publication, haptics and authored-audio consequence. It cannot publish a
  lasting visible response before the write-ahead commit.
- The Metal runtime has an immutable frame planner, signed texture inventory,
  bounded camera and atmosphere plans, deterministic replay and explicit
  Reduce Motion composition.
- The authored-audio runtime is sample-indexed and uses `AVAudioEngine` and
  Core Haptics. Local restore behaviour is covered; physical interruption and
  hard-kill timing remain in the final device gate.
- A verified retained package generation remains playable offline while an
  update is pending, but only against the exact saved snapshot and active
  generation digest. Paid roads require the package root, verified manifest
  and matching generation authority before opening.
- Restore-internal ownership fallback holds a mutation-barrier token through
  its durable commit and checkpoint. Rollback or deactivation invalidates
  stale launch and future-release refresh flights, publishes the fail-closed
  withdrawal immediately and requires a fresh durable read before authority
  can return.

### Runtime authority, FIFO and ordered exit

The local runtime-authority gate is closed:

- Saturated continuous input keeps one tracked worker through deferred-sample
  promotion. Accepted actions remain FIFO across physical-pause handling and
  route cancellation; coalesced or dropped samples never perform outside that
  worker.
- Responsive-audio quiescence is transactional. If the physical transport
  pauses at a later cursor and then fails, controller state returns to its
  exact entry snapshot, the failed generation loses automatic-boundary
  ownership and any synchronously captured boundary action is discarded.
- Ordered exit stops the cursor pump before physical quiescence. If that
  quiescence fails after exposing a later transport cursor, the stopped-graph
  retry can commit only the exact pre-call snapshot.
- Sidecar retirement revokes future writes and waits for every already
  admitted write owned by the retiring session to complete durable I/O and
  actor verification. Recovery cannot be changed later by a latent writer.
- Every await in ordered-exit preparation is followed by controller-pointer,
  lifecycle-token and current-route validation. Cleanup can discard only the
  captured generation; an installed successor controller or a pre-install
  successor binding remains intact.
- Direct actor-store recovery, durable journal inspection and a cold launch
  all recover the accepted pre-failure cursor and reject the later cursor
  touched by the failed physical pause.

This closes the simulator failure seam. Sample-exact physical interruption,
hard-kill timing and device lifecycle behaviour remain in the final recorded
iPhone gate.

## Signed five-grammar technical fixture

One atomic, signed development package now exercises the complete technical
path for all five grammars:

- `allocate`, `assemble` and `transform` use First Farmers projections;
- `pressure` uses a Frontiers Hold projection;
- `trace` uses a European World projection;
- signature verification, repository loading, production runtime factories,
  Metal, offline audio, durable progress and accessibility share the same
  package boundary.

The package contains 62 signed inventory files plus its manifest. Its authority
shape is
`SINGLE_ATOMIC_FIVE_GRAMMAR_LAB_PACKAGE_WITH_UNREFERENCED_V26_PARTIAL_PASS_PROOF`.

- payload SHA-256:
  `43466b3c669a2f4d8ace0877faef4589a0d4cc7b6a49de2475c34c55709d0ee4`;
- manifest digest:
  `2635c2f5b98e7bba0dff076f748dca195fa1c5c5fdd700b72903a507b52c4560`;
- package-manifest file SHA-256:
  `c75b49176bfb65c1a763f31a0a3471a01bd51ac9d57f0ca29369f586b1646aaf`;
- fixture-lineage SHA-256:
  `2a6048d9fe4c9f0cf8aa23782dd74d5a6b112ea1cd241f8870b082a6ca247c3d`;
- development-trust receipt SHA-256:
  `70f638ebf28f8d667d09ad5521a263afab4e24721eb38f69a0f053c60784854e`.

The package is `PROHIBITED` for shipping. Four grammar scenes still use
existing web or technical source images, and none is a finished production
scene. The additional Harvest parallax scene is intentionally unreferenced by
any Journey beat.

## Product shell, downloads and future releases

### Launch-package download surface

The Journey shell now connects a visible download sheet to the app-level
`DownloadController` and `DownloadPresentationProjection`. It is no longer only
a UI-neutral controller.

The surface derives the canonical launch packages from the validated manifest
and shows included, installed, pending, queued, transferring, paused, failed
and retryable states without inventing progress. It exposes per-package
requests, `Download all remaining chapters`, `Pause after this package`,
explicit continuation after process restoration, retry and queue removal only
when the controller makes the corresponding command valid. The storage figure
is the conservative sum of remaining `maximumInstalledBytes`.

Network initiation remains fail-closed at `unknown`. Offline paths create no
request. Cellular and Apple-marked expensive paths use the metered-download
gate. Low Data Mode blocks automatic deep-dive requests, while explicit user
requests remain distinct. A schema-versioned two-slot queue journal restores
only a contiguous verified installed prefix.

DEBUG fixtures and simulator UI tests exercise normal download, owned/offline,
metered, bootstrap-failure, interrupted-queue and retry paths. No current
result claims that the real Apple-hosted launch packs exist or have downloaded.

### Future deep dives in the living world

The release-discovery route now carries the complete durable
`ReleaseCatalogEntry` through bootstrap and restoration. A release that is
installed, active, paused or failed remains addressable at its approved world
location after the live catalog and authenticated cache are unavailable. The
route becomes playable only when the verified repository authority exposes the
matching active package generation.

Bootstrap and request failures produce a visible world-node error and retry.
An interrupted retained queue exposes explicit continuation. StoreKit
entitlement updates do not eject the active future route. Stale or quarantined
content cannot republish a prior playable authority.

Focused simulator UI evidence covers:

1. a normal future-release download;
2. bootstrap failure followed by retry;
3. cold restoration of an installed retained entry after catalog withdrawal;
4. an interrupted retained queue followed by explicit continuation.

The publishing compiler now requires four separately bound authorities:

- the `Release` record;
- the public content payload;
- an editor-approved publication record with the exact world placement;
- an editor-approved launch-world authority whose placement IDs are exact
  members of the canonical `worldSeed`.

Approval digest v2 binds all four. Duplicate seed nodes, invented placement
nodes, world-seed drift, post-approval authority drift, launch-package
collisions and backstage-control leakage fail before signing. A new package is
activated only after complete inventory, signature, schema and migration
verification.

This is an implemented offline and publishing boundary, not a published deep
dive. No production future release, CloudKit catalog record or APNs delivery
exists yet.

### Commerce and release boundary

- StoreKit 2 supports the single permanent entitlement, pending and cancelled
  purchases, restore, transaction updates, refund or revocation and an
  authenticated offline ownership cache.
- The real product identifier and live transaction path remain unexercised.
- `validate-release-app-boundary.mjs` scans the actual built Release `.app` for
  development resource names and byte markers. The latest scan is `PASS`.

## Current First Farmers production object

The current source draft and editor object is
`PROVISIONAL_CODEX_COMPLETE_AWAITING_FINAL_EDITOR_GATE`, with SHA-256
`4c3a0a2a4f9a3ec5361d2e34c2f6dd21072f27176e60c881f013c93f76e4a5dd`.
Its non-shipping projection contains:

- 3 arcs, 17 beats and 6 principal interactions;
- 17 scene specifications and accessibility specifications;
- 37 narration cues and 47 audio timelines;
- 6 provisional responsive-audio programs: Harvest, Household Crosses,
  Longhouse, More Mouths, Three Records and A Continent Remade;
- 778 future asset requirements.

The generated content payload is SHA-256
`f3a459d72799bb2ee34a24e98fd164ea42c79186a13e60a67d75eaf58d89999d`.
The generated chapter file is SHA-256
`32fbcf8824852a8e0e77ae1e8e8ef4d1ff8a85f1869187f080408085f2629e6f`.
The current payload-receipt file is SHA-256
`d0b0843524d38268383721ca58b1fe420e374f2d13ee496097684e56f83a1f97`.

The backstage claim register has 15 findings: 9 `PASS`, 1 `NARROW`, 1
`REMOVE` and 4 `EDITOR_DECISION`. The two non-editorial repairs are closed.
The four changes that could alter the selected interaction or ending remain
unapplied in the private editor queue.

The DEBUG repository can load and restore the generated payload. The signed
five-grammar fixture proves each runtime adapter. Missing production visual and
audio assets still fail openly. First Farmers is not yet a playable chapter.

### Household Crosses Trace closure

The Household Crosses source and generated chapter now carry four stable
route-anchor IDs. Three exact, ordered nonterminal bindings select the visible
state reached at each crossing; no later state can appear before its durable
anchor contact. Restoration and Reduce Motion recover the same latched state.

The bound interaction target is a visible corridor containing all four route
anchors in master space. The cross-binding validator rejects a future edit
that moves an anchor outside that target. Touch and VoiceOver continue through
the same reducer actions and durable progress.

The corridor layers and three reached-state variants are declared only as
asset requirements with status `FUTURE_PRODUCTION_ASSET_NOT_PRESENT`. This
closes the content geometry, ordered visual-state contract and local runtime
seam. It does not create a production plate, a completed 2.5D scene, an
artistic approval or shipping authority.

## Harvest visual production

### Flat candidate

The strongest flat candidate remains
`design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png`:

- `1290 x 2796` portrait pixels;
- SHA-256
  `e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca`;
- pixels outside the authorised garment mask are identical to the v25 parent.

It remains `NON_SHIPPING`. It has no production-master, asset-DAG or shipping
approval.

### Rejected geometric 86-asset DAG

An 86-asset geometric clean-plate, mask, layer and state attempt was produced
with 47 additional diagnostic outputs. It is retained only as a negative
fixture. Its masks were geometric approximations, its clean plates contained
smears and duplicated geometry, and its parallax and state transitions did not
pass the combined visual gates.

- status: `REJECTED_GEOMETRIC_MASK_NEGATIVE_FIXTURE`;
- shipping state: `PROHIBITED`;
- rejection receipt SHA-256:
  `8214fa9c2b2b2610cef3a7769693b9f0727dc40fd531f34e717aaffd99e662b5`;
- rejected DAG file SHA-256:
  `5f64b46095b03a5846f4fca1d022c537265ff3862ac453eedd090a918228cff9`;
- rejected output-receipt SHA-256:
  `eb543367c1d8333dcf4a0f8a33d8e9b534cb16301f7829bcd2f24a81bad5a878`.

These files cannot establish progress toward a production asset count.

### Source-aligned segmentation and partial parallax pass

Twenty-two SAM2 masks are bound to the exact v26 canvas. The deterministic MPS
segmentation receipt has SHA-256
`4c378ffe243bdafd85b9c0476147d14b023389e9ea88d5f9884fcba3f3d75191`.

Two broad parallax attempts were rejected for roof, pillar, storage and seam
residues. The frozen narrow pass covers only people, central grain and
foreground occluders:

- parallax proof receipt SHA-256:
  `dbc54f8afef3dceb6a49bd6e21ce9efe0fcd5f039f80d925465d4838a2851277`;
- review authority SHA-256:
  `416848fed0d504fcdc2e2b823725e1f6f8190e3899e7f101a68481cab4c4f8e9`.

The built-in image editor was tried twice for a full clean plate. Both outputs
regenerated protected roofs, beams, posts, walls, cattle, hearth, field and
ground, and both were lower than the source resolution. Both are rejected.
The rejection receipt SHA-256 is
`262999acb54f569020a42d149a457f6b63fd6cf7ab5edc63c08dde86547c1f55`.
Further retries through that built-in global edit route are not authorised by
the receipt.

### Central-grain source authority

One source-aligned central-grain disocclusion underlay is byte-bound as
`CODEX_VISUAL_REVIEWED_NON_SHIPPING_SOURCE_INPUT`. It covers only the central
Harvest crop. Initial-state recomposition restores every authorised pixel
exactly; the scene-scale and objective technical checks found no failed gate.
It grants no editor, production-master, package or shipping authority.

- underlay SHA-256:
  `de1b460d983c49cd337247cdd3ab58d56bde3cf28bd5eff633143ab17468114e`;
- authorisation-mask SHA-256:
  `11f7d1016bdc6a1ddd897f7283c35ffcacaf4510b4899c20bedf33b19b1500f9`;
- source-authority SHA-256:
  `c2915382f8d52162540487d51e70ccafa6fd459969cf6c70c3da2cd1aae23eca`;
- R5c scene-QA receipt SHA-256:
  `4ada27254650aae2ea7b139aff9ca87708928f7f42d7c159bbe275196c567be9`.

The authority validator, its `5/5` regression tests, the existing `6/6`
underlay-author tests and `15/15` visual-tooling tests pass. This closes one
disocclusion input, not the remaining Harvest plate set.

### Restricted Metal proof

The narrow people, grain and foreground pass now traverses the signed package,
production frame planner and real Metal shader path. At both bounded camera
extrema, repeat renders are byte-identical. Save and restore reproduce the same
frame plan. Reduce Motion produces zero changed pixels against the frozen
static crop. Normal scenes cannot use the diagnostic exact-copy path; opacity,
blend, mask, viewport and dimension deviations remain on the shader path.

- runtime-proof receipt SHA-256:
  `16c3416ecd7a3495b2f657d88cffe97da85ff47d43d86677bd78c7936f04eab6`;
- normal extrema BGRA hashes:
  `dd83b40d4d9de0f3859a228fe6934ee0a28cf7532a68ffabb6c609990cdd4dac`
  and
  `d5d59cb4e3bf3c469c5e581a55f5e02cc2bf93954cd99a2ff0dc4a5437f9e01f`;
- Reduce Motion BGRA hash:
  `fab1954e917b0b7f48353332dcda85f8e21574d8e29fa314d8b0f9cfd455fef2`;
- four-panel simulator comparison SHA-256:
  `3178d181276f61613487f87a0e8bd755338911c2dc226344d274e728b2127125`.

This pass excludes the winter vessel, protected reserve, spring seed store,
settlement shelter, allocation cloth, the remaining disocclusion underlays,
complete state plates, the complete layer DAG and the complete scene. It grants
no production-master, artistic, editor or shipping authority.

The Harvest interaction manuscript remains `DRAFT_AWAITING_EDITOR_APPROVAL`
and `PROHIBITED` for shipping.

## Harvest responsive score and soundscape

Harvest has five authored responsive regions and 75 deterministic 48 kHz,
24-bit outputs. The complete set was rendered twice offline with identical
bytes.

- work-object SHA-256:
  `0580c37949a3dc735148cd166c2cde8ae819ceda3406be2292152859c2b348a6`;
- render-receipt SHA-256:
  `85f5b802716e804ab26b4435964af52ac89ee20f9ae7561c6ff18c8383d6e38c`;
- aggregate output size: `535685606` bytes;
- reproducibility: `PASS_SECOND_COMPLETE_OFFLINE_RENDER`.

The current work object binds the score and soundscape sources, renderer,
program runtime, controller, timeline planner, resolver, native transport,
preferences, durable completion and semantic haptics. The audio remains
`PROVISIONAL_NON_SHIPPING`. It has not passed the integrated Harvest artistic
gate.

## Longhouse visual direction and direct manipulation

Option A4, `The Inherited Ground`, is the selected provisional composition
direction. It remains composition-only and requires another comparison before
asset production.

- concept image SHA-256:
  `1f166356445255c302f795623af2e56259f0924d153c41cf5c2a4d683d2b8ae7`;
- selection SHA-256:
  `2e7019abd837297d5eb42aa27b53095f841401ed2864728a183fe3c39e7cb7cd`;
- A5/A6 390-point refinement review SHA-256:
  `3a50b45899af9c80a577e8b87af269d5650a293f4982727a3d6ca0a0dcdbc250`;
- interaction-production contract SHA-256:
  `f0cbd691ab5d321cc03d992e174a4244edb35a7c8d262af615589896e43d575f`.

The First Farmers payload and signed technical fixture now carry distinct
source and bearing-slot targets for posts, hearth, storage and roof. All eight
targets preserve the 44-point minimum in the baseline portrait crop. A legacy
single-target binding decodes only for compatibility and cannot be encoded or
used for physical placement.

Physical manipulation preserves the acquired point inside irregular source
geometry. Contact, lift, carry and slot approach are presentation-only. A
cancelled or rejected drop follows a bounded 220 ms spatial return; Reduce
Motion retains static contact and resistance without displacement. Only a
reducer-accepted drop appends `place`. VoiceOver submits the same action, and
old cleanup work cannot clear a newer response.

The Longhouse focus passes `57/57` tests and an independent code review. The
source-slot contract passes `4/4`. This closes the local controller and content
binding seam, not the production-scene gate: the signed fixture still uses
technical geometry and non-production imagery. A4 still needs one complete,
readable offset former footprint and reworn threshold at phone scale. A5 made
the footprint visible through pit-like marks; A6 removed that confusion but
also removed phone-scale legibility and introduced broader rendering drift.
Both remain rejected non-shipping evidence studies.

## Longhouse responsive score and soundscape

`Raise the House` now has a second provisional authored responsive program
with 75 deterministic outputs. It was rendered twice offline with identical
bytes.

- work-object SHA-256:
  `3988bd147135469fd851cf37d3e0d28b50d0bf70e469c6e0067a5591a78f871b`;
- render-receipt SHA-256:
  `3749f218603431c9d1fbd706d7e4816dc00b85c56056e4eb38dd2fbc99ca1993`;
- reproducibility: `PASS_SECOND_COMPLETE_OFFLINE_RENDER`.

The program follows the same receipt-bound responsive runtime and remains
`PROVISIONAL_NON_SHIPPING`. It is present in a signed technical fixture but has
no integrated production scene or artistic approval.

## A Continent Remade responsive score and soundscape

`A Continent Remade` now has a third provisional authored responsive program.
Its Harvest and Longhouse material is recomposed across three independent
stems while worked ground, settlement hearths, stored grain, household fibre
and visible field work remain separate source-bound layers. No water, animal
or voice material is fabricated from the existing DSP vocabulary.

- work-object SHA-256:
  `2b3a850e8e398faa720cdf4b574dc209763b538fad3aa477e3f9801d90d43f89`;
- render-receipt SHA-256:
  `2eb9647c48e9a46b47fc070eabd9dd3afd3567e02860642f87084da09c2165b8`;
- aggregate output size: `476933935` bytes across 75 outputs;
- reproducibility: `PASS_SECOND_COMPLETE_OFFLINE_RENDER`.

The five-region program replaces the prior payload placeholder, preserves the
same sample cursor across waiting, engaged and resistance beds, and keeps
narration and timed haptics out of its loops. `drag`, `break` and durable
`seal` remain semantic runtime actions. The program is
`PROVISIONAL_NON_SHIPPING`; narration calibration, scene integration,
artistic approval and physical-device review remain open.

## Permitted responsive-audio validator set

The five permitted responsive-audio validators pass with these exact
work-object and receipt bindings:

- Harvest:
  `0580c37949a3dc735148cd166c2cde8ae819ceda3406be2292152859c2b348a6` /
  `85f5b802716e804ab26b4435964af52ac89ee20f9ae7561c6ff18c8383d6e38c`;
- Longhouse:
  `3988bd147135469fd851cf37d3e0d28b50d0bf70e469c6e0067a5591a78f871b` /
  `3749f218603431c9d1fbd706d7e4816dc00b85c56056e4eb38dd2fbc99ca1993`;
- A Continent Remade:
  `2b3a850e8e398faa720cdf4b574dc209763b538fad3aa477e3f9801d90d43f89` /
  `2eb9647c48e9a46b47fc070eabd9dd3afd3567e02860642f87084da09c2165b8`;
- More Mouths:
  `c8eb8c6cb395f6cb3b5bd791321c7355aceef034eb46f8d9281f5902d2105362` /
  `3a313680830634629cd385da262ceee872813a31fba070ab8b95fb90ad133ec7`;
- Household Crosses:
  `95d73e6b63407da48fe0d83ff914247ad1fef44c0e153d0e30dbbc44cda1cb7b` /
  `ca9318db16481a213b62bea26dd4eda80be32e4fcbc7e2546c5ec7a9511c3914`.

These receipts prove permitted local validator and output integrity only. All
five programmes remain provisional and non-shipping until their complete
scenes pass the integrated artistic gates.

## Narration programme: V5 through V12

All results below are backstage, anonymous and non-shipping. No version has
produced a narrator choice or an approved production master.

### V5

V5 produced deterministic cue assemblies for candidates 05 and 06 from the
exact 3,400-word stress text. The complete machine audit rejected both for
severe repetition and content collapse. It is negative evidence only.

- V5 audit receipt SHA-256:
  `55aaa8764651fb83d53b3deb9b1e2e82140bea55b4bac5eacbe69af39fbdcb79`.

### V6 and V7

V6 R4 produced two complete masters inside the 18-22-minute duration window
using 123 short audited utterances per voice and deterministic authored-boundary
assembly. V7 then applied independent windowed decoding:

- candidate 05 passed words and repetition but retained `15.43965%` silence,
  above the `12%` ceiling;
- candidate 06 also exposed a long-window decoder-collapse problem;
- the 30-second diagnostic showed that the source utterances themselves were
  not repeating, so the decoder method had to change rather than treating the
  failure as a passing master.

The V6 R4 stress receipt is SHA-256
`703ebc41cb8b2eca73038ae3f53c7356ea9713e8a461e06811d7dc58f8250784`.
The complete V7 audit receipt is SHA-256
`80f07b8e7f33d6d91c8d133893055476fa58cfcaec81ed9deb9722d5f949856e`.
Both masters are rejected.

### V8

V8 repartitioned the exact approved text into 203 semantic utterances per
voice. The frozen pause-density lab found no factor that passed the unchanged
silence ceiling for both voices, despite passing identity, word, utterance and
duration checks. No full 406-utterance Qwen set was generated.

- pause-density receipt SHA-256:
  `e105fdf35e3c48fa2759bebb224471223de3adcc8f472530c9ec11344f1fd9af`.

The retained decoder method is a `30/15/15`-second window, overlap and hop
grid. Its candidate-06 proof passed all 87 windows and 86 overlap gates, with
WER `1.16891%` and zero excess repetition, but missed one exact cue-coverage
threshold. The receipt SHA-256 is
`50abe90764b04e8f391dc36da707589e3652eb8c107ec6c23e02f349583fec2c`.
The `25/15/10` alternative is closed negative evidence because one seam needed
three timestamp adjustments and `1011.905 ms`, beyond the frozen limits of two
words and `750 ms`.

A pinned Chatterbox-Turbo comparison generated the same 14 representative
utterances for both voices. All utterance, identity, aggregate-word and named-
pronunciation checks passed, but both voices retained `15.49%` silence and
projected beyond the maximum full duration. The comparison receipt SHA-256 is
`fc0dc51cae7763b2635b5ce4ec561730b2597060f3c39b372ab72e0a32553f98`.
Chatterbox audio cannot parent a master.

### V9

The local-only inventory found no third eligible cached method. Apple's
installed System Voices cannot be recorded and redistributed under the bound
macOS licence and cannot condition on the two frozen references. Other local
source trees lack the complete cached weights, licence bindings or control
bindings required for a zero-cost offline run. No V9 comparison audio was
generated.

- V9 inventory receipt SHA-256:
  `e767a33f2df97e62a6892f5abb2cc03b451856dda981b77fa464bb6e54a7d288`.

### V10

OpenVoice V2 completed its exact snapshot, offline runtime and fixed `14 x 2`
representative comparison. Both frozen references failed the unchanged gate,
so neither could parent a complete master. The durable negative-evidence
SHA-256 is
`5b65d6ef9d6fa5f09e0d9423c20e07a8e1794b236c7f4283cf83aaba011e872b`.
V10 is closed and rejected.

### V11

The remaining-candidate gate selected VoxCPM2. Its exact
`4960731703`-byte model loaded offline on MPS in float32. The first
representative attempt produced one raw WAV and one audit WAV, then stopped
before any job receipt when the process created 46 undeclared Numba cache
files inside the protected runtime tree.

Completed jobs remain zero. Retry, resume, the full representative comparison
and complete-work generation are prohibited under V11. The failure receipt is
SHA-256
`c9c85595279132a495edaa4b94f65d5b14cae1f69459a1b026ce0ce30db89b24`;
the incomplete-evidence record is SHA-256
`0e947daaad78491da59f4bc6ec1d6f7a59c872c3675fc5736fcbbe4f123b577a`.
V11 is terminal.

### V12

V12 rebuilt the method from 59 locked local wheels with the Numba cache held
outside the protected runtime. Two fresh processes loaded the model and
replayed the frozen reference and prompt encodings identically. The synthesis
call remained blocked: there was no network request, no call to generation and
no PCM or WAV output.

The pre-synthesis receipt is SHA-256
`f88851125d3e50da50d36d44e11c38c36e2873740a8d7305a63254c9e0a036c3`.
Its authority is `synthesisPermitted=false`, `v11IsTerminal=true` and
`requiresEditorDecision=true`. There is still no passing narration master,
candidate promotion, voice choice, artistic approval or shipping authority.

## What remains before Port 1 can pass

### Production and artistic work

- A production-approved Harvest master with source-aligned clean plates,
  complete layers and masks, material state variants and full Reduce Motion
  composition. The narrow people/grain/foreground Metal proof does not satisfy
  this gate.
- A passing two-voice narration stress set, provisional voice identity,
  pronunciation lexicon, editor voice choice and complete artistic approval.
- Finished Harvest narration and integrated artistic approval of score,
  soundscape, silence and haptic direction.
- One integrated Harvest scene from a signed package with production imagery,
  causal allocation, audio, accessibility, offline operation and exact
  restoration.
- Four equivalent finished production scenes for the other interaction
  grammars. Their technical adapters and signed fixtures already exist; their
  production assets and complete scene direction do not.
- The complete playable prologue, all 17 First Farmers beats and six
  interactions, the two other free chapters and the cumulative living world.
- All 21 paid chapters, production launch packages and full 24-chapter quality
  parity.

### Completed local verification

The 25 July complete-script receipt and the later runtime-authority receipt
remain valid for the workspace states they captured. The latter passed
`758/758` package tests, `148/148` focused units, `18/18` connected UI tests
and a rebuilt Release boundary scan. That Release `.app` contained no DEBUG
fixture, Harvest proof, narration work tree, source, verifier or backstage
control byte.

The current permitted tree passes `806/806` SwiftPM tests, the named Household
Crosses Trace closure, the `57/57` Longhouse focus, the Harvest source-input
authority checks and all six provisional responsive-audio validators. Generic
Debug and Release iOS Simulator app builds succeed, the ARM64 Release iPhone
build succeeds, and the rebuilt Release `.app` boundary-only scan passes for
its captured build. A current production-route UI test opens all 17 First
Farmers beats, and the focused Thread Sanitizer recapture passes `194/194`
with zero findings. The current integrated Xcode UI gate remains red at
`42/46`; therefore the tree does not yet have a complete local app-level pass.
All of these remain local and simulator evidence, not a physical iPhone
result.

### Final physical and service verification

- Live StoreKit purchase, pending, restore, refund and revocation.
- Live Apple-hosted package transfer, interruption, storage failure, update and
  rollback.
- Live CloudKit release discovery and one APNs notification for an actually
  available deep dive.
- Recorded physical-iPhone frame pacing, memory, thermal, battery, cold start,
  hard kill, exact restoration, VoiceOver, Dynamic Type, Increased Contrast,
  Reduce Motion and complete fly-mode use.
- The editor-in-chief's final manuscript, interaction, visual, voice, scene,
  chapter and release decisions after the corresponding complete candidates
  exist.

## Immediate autonomous work order

1. Keep narration closed at the V12 editor-decision gate. Do not retry V11 or
   weaken the unchanged voice and artistic requirements.
2. Hold Household Crosses visual implementation at the three displayed,
   source-grounded 390 x 844 interaction-focus directions until the editor
   selects one. Keep every corridor and reached-state image at
   `FUTURE_PRODUCTION_ASSET_NOT_PRESENT` until a complete source plate, layer
   set, state set and visual authority exist.
3. Refine Longhouse A4 until the complete inherited footprint and reworn
   threshold read at 390-point width, then register production source and slot
   geometry against the approved layer DAG.
4. Produce the remaining source-aligned Harvest disocclusion underlays and
   material state plates; keep the rejected geometric DAG and both global
   image-editor attempts quarantined.
5. Build the complete Harvest and Longhouse scenes through the signed package,
   including both motion modes, responsive audio, accessibility, offline use
   and exact restoration.
6. Recapture connected simulator and sanitizer evidence, then continue the next
   safe scene machine before involving the editor-in-chief or the physical
   iPhone. The current generic Release build and boundary-only scan already
   pass.
