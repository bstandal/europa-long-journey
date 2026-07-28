# Chapter 01 review gate

`CHAPTER_01_REVIEW_READY` is the editor-facing simulator milestone for
`first-farmers`. It does not approve production assets, a production voice, a
launch package or shipping.

Run the source and evidence audit with:

```sh
node native/scripts/validate-chapter-01-review-ready.mjs --json
```

The command succeeds while the gate is `CANDIDATE` when the locked source is
valid and reports every missing deliverable or receipt in `blockers`. The final
promotion command is:

```sh
node native/scripts/validate-chapter-01-review-ready.mjs --require-pass
```

That command fails unless `review-ready-gate.json` says `PASS`, the signed
fixture and all 37 narration files validate, and all eight evidence receipts
below pass. Changing the status before the evidence exists is rejected.

## Common receipt fields

Every receipt is JSON and has exactly these common fields plus the fields for
its type:

```json
{
  "schemaVersion": 1,
  "receiptID": "<evidence-id>-chapter-01-review-v1",
  "type": "<TYPE_FROM_GATE>",
  "milestone": "CHAPTER_01_REVIEW_READY",
  "status": "PASS",
  "chapterID": "first-farmers",
  "shippingState": "PROHIBITED",
  "subjectSHA256": "<current fixture-and-native-subject hash>"
}
```

No receipt may contain a shipping or production-approval field.

Every PASS receipt is tied to the exact signed fixture plus the native source,
test and project inputs used by the run. Dynamic gates also bind their logs or
recordings by path, byte count and SHA-256 under `evidence/artifacts/`. A source,
fixture or artifact change makes the receipt stale and returns the milestone to
`CANDIDATE`.

`templates/receipt-templates.json` contains one machine-readable pending
receipt for every evidence gate. Copy the relevant `receipt` object to its
`destination` only when that run begins. Replace the `null` measurements with
observed values and change `status` to `PASS` only after the referenced command,
simulator run or recording has completed successfully.

## Required evidence

- `AUTOMATED_SUITES` contains `suites` in this exact order:
  `editorial-regression-and-f1-f7`, `tooling`, `swiftpm`, `fixture`, `xcode-ui`,
  `sanitizer`, `release-boundary`. Each item contains `id`, the executed
  `command`, `exitCode: 0` and `errorCount: 0`. Its bound log must contain the
  Release-boundary result and the focused `NON_SHIPPING_LIVE_TEST` 17/6
  traversal marker.
- `FIXTURE_DETERMINISM` contains equal `firstBuildSHA256` and
  `secondBuildSHA256`, with `byteIdentical`, `signatureVerified`,
  `trustBoundaryUnchanged` and `ordinaryReleaseRejectsReviewResources` all
  `true`. Each build hash is the SHA-256 of the sorted fixture-file records
  `relative-path NUL byte-count NUL file-sha256`, joined by line feeds and
  terminated by one line feed. The gate recalculates this digest from the
  current signed fixture tree. `trustReceiptSHA256` separately binds the
  development trust receipt used to admit that tree.
- `SIMULATOR_TRAVERSAL` records a Codex-operated, non-XCTest pass on an iPhone
  17 Pro iOS Simulator at iOS 26.4 or newer, direct entry to the first canonical
  beat, exit from the final beat,
  counts `3/17/6/6/37/47`, a completed traversal, and `false` for account,
  purchase, debug-control and visible-review-mark surfaces. It also records an
  explicit `Begin` entry that starts authored sound after the verified scene is
  ready; the fixed `Turn sound off` / `Turn sound on` control; a completed mute
  and resume; and `Resume sound` without spontaneous playback after both an
  interruption and a cold restore. The run is bound to a traversal log and
  screen recording.
- `INTERACTION_RECORDINGS` binds one completed recording to each canonical
  interaction ID. Every `artifact` has `path`, `bytes` and `sha256`; paths stay
  under `native/quality/chapter-01-review/evidence/recordings/`.
- `RESTORE_MATRIX` records passing entry and exit restores for all 17 beat IDs,
  passing mid-state restores for all six interaction IDs, a preserved loop
  cursor, a paused cold return and the observed final-state SHA-256. The bound
  log carries the structured checkpoint marker that the gate parses.
- `AUDIO_RESTORE` records 48 kHz, zero-sample controlled-pause error, cursor
  writes at or below 250 ms for rapid Trace and hard kill, same-process phase
  preservation, cold `engaged`/`resistance` normalization to `waiting`, paused
  cold return, preserved loop cursor, chapter-local silence persistence and no
  cross-chapter silence leak. The bound log must contain PASS results for the
  concrete cursor, pause, silence, cold-restore and six-program tests.
- `ACCESSIBILITY` records a minimum 44-point target, the same final-state hash
  for touch, VoiceOver and Reduce Motion, all six interaction IDs, and no hidden
  required information or action under Dynamic Type or Increased Contrast,
  with a system-settings log and actual VoiceOver recording.
- `OFFLINE` records denied networking after installation, zero observed network
  requests, a completed traversal and restore, and package-only asset loading,
  with bound network-observation and traversal artifacts. On Simulator, zero
  observed requests is the combined result of 100 percent packet loss,
  continuous external-socket sampling, CFNetwork diagnostics and the compiled
  live-test exclusion of Apple commerce/release/download edges; it is not
  represented as a direct `xctrace Network` count because that instrument does
  not support Simulator.

The later run on the owned physical iPhone remains a separate editorial device
check. It cannot be inferred from this simulator gate and is not a release,
battery, thermal or performance certification.
