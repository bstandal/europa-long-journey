# Native iPhone foundation

This directory contains the first executable foundation for **The Long West: EUROCENTRIC**. It is an
engine and product-shell milestone, not a finished chapter or a substitute for the native bible.

The editor-in-chief locked authored real-time 3D on 30 July 2026. No real-time 3D renderer or world
cell is implemented here yet. The existing frame planner and Metal compositor are legacy non-shipping
2.5D evidence unless a later 3D proof reuses a bounded subsystem explicitly.

## What is authoritative here

- `Sources/ContentKit`: shipping content contracts. The schema intentionally has no research,
  historiography, confidence, counterargument or evidence-panel fields.
- `Sources/JourneyDomain`: deterministic journey, interaction and cumulative-world state.
- `Sources/ProgressStore`: an offline append journal with checksummed replay and atomic snapshots.
- `Sources/SceneRuntime`: deterministic scene interaction plus the legacy frame planner and narrow
  Metal compositor used by the former 2.5D prototype.
- `Sources/JourneyAccessibility`: semantic equivalents for the five interaction grammars.
- `Sources/DramaticAudio`: sample-indexed authored timelines and the iOS
  `AVAudioEngine`/Core Haptics transport.
- `Sources/CommerceKit`: StoreKit 2 purchase, restore, transaction-listener and authenticated offline
  entitlement state for the single launch purchase.
- `Sources/ContentDelivery`: Apple-hosted pack materialisation, signed-package validation, atomic
  activation and rollback.
- `Sources/ReleaseDiscovery`: CloudKit release discovery, authenticated offline catalog cache, durable
  notification deduplication and world deep links.
- `Sources/ExperiencePreferences`: schema-versioned offline choices for narration, authored audio,
  haptics and downloads, with atomic writes and preservation of unreadable or newer documents.
- `Sources/JourneyApp`: a portrait-only SwiftUI shell with a playable prologue foundation and the
  three stable free chapter entries. No chapter is represented as finished.

The franchise and work names live in `ProductMetadata`; content IDs and persistence keys do not
contain either title.

### Experience-preference integration boundary

`ContentDelivery.DownloadInitiationPolicy` derives a new-request decision from the cellular and
automatic deep-dive choices. `NWPathDownloadNetworkBasisProvider` supplies the latest fail-closed
network basis, and `DownloadRequestInitiator` checks both immediately before it invokes an injected
new-request operation. Expensive paths, including Personal Hotspot, use the cellular-download gate.
Low Data Mode blocks automatic deep-dive requests while leaving explicit requests under the normal
network gate. None of these types controls an existing Apple-managed transfer.

`DownloadController` owns the local launch-delivery composition. Concurrent bootstrap callers share one
restore flight. The restored journal is reconciled against today's canonical paid-package order: a safe
package-ID subsequence keeps the user's intent but receives today's complete specs and requires an
explicit resume; unknown, removed or reordered IDs produce a machine-readable stale-journal state and
never start. The queue journal remains the only durable queue authority.

A single-package request and `Download all` accept two consecutive matching reads of the active index
and current preferences before the latest network context is read and the installer is invoked. These
separate stores do not provide a cross-store transaction; the repeated reads close mutations observed
during an await without claiming impossible atomicity beyond the final installer hop. Refresh generations
prevent an older result from replacing a newer snapshot, and a failed terminal refresh remains visible
as `refreshFailure` while the last verified index stays active. Terminal, cancelled and package-boundary
transfer observations normalize to idle, so old Apple progress is never paired with a completed, failed
or later-package installation state. Pause-after-current, resume, retry and remove continue to operate
on the journaled queue without consulting new-request network policy.

The remaining delivery integration gap is:

- app composition-root ownership of the network monitor, saved-preference provider, package activator,
  queue journal and `DownloadController` lifecycle;
- real-account validation of the Apple-hosted provider and its status stream;
- product-shell presentation of controller results, storage ceilings and queue state;
- settings exposure for cellular and automatic deep-dive choices after that path is connected.

An offline or unknown decision prevents a new request only. Transfers already accepted by Apple keep
their system-owned lifecycle; this initiation policy exposes no cancellation or suspension command.

`ContentKit.Release` is the post-launch discovery contract. A trusted Release declares exact chapter
ownership, package version, minimum runtime and installed-byte ceiling, then derives the
`ContentPackageSpec` passed to `ContentPackageVerifier`. The app must obtain that Release through its
trusted release catalog; it must never derive trust from a Release found only inside an unverified
download.

Before a future package request can begin, `ReleaseDiscoveryController` seals the complete
authenticated `ReleaseCatalogEntry` into `ReleaseInstallationContractStore`. This separate HMAC-
authenticated two-slot ledger survives process death, newest-slot corruption and later removal from
the live discovery query. Cold-launch verification therefore retains the exact chapter ownership,
version, runtime and byte ceiling that authorised the installed bytes. Retirement is also sealed into
both slots so a corrupt fallback cannot resurrect stale package authority.
`FutureReleaseDownloadController` then derives the verifier package spec from
that retained entry, reapplies explicit/automatic network policy, restores an
interrupted queue without the live catalog and rejects any installed generation
whose exact release contract is absent.

## Build and test

The core modules and their tests have no runtime dependencies:

```sh
swift test --package-path native/ios
```

The iPhone project is declared in `project.yml`. Generate it with a locally available XcodeGen binary,
then build with Xcode's command-line tools:

```sh
cd native/ios
xcodegen generate
xcodebuild -project LongWestJourney.xcodeproj \
  -scheme LongWestJourney \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build test
```

For an optimized Chapter 1 run on a physical iPhone, select the
`LongWestJourneyLiveTest` scheme. Its Run and Profile actions use the
release-type `NON_SHIPPING_LIVE_TEST` configuration, pass the signed fixture
arguments for `first-farmers`, and install as
`com.thelongwest.journey.nonshippinglivetest` with the display name
`EUROCENTRIC LIVE TEST`. The Run action does not attach LLDB. The configuration
includes only the exact signed runtime fixture and its development trust
receipt; the unsigned generated payload remains excluded. It has no Push or
CloudKit entitlement and uses an unavailable local ReleaseDiscovery model, so
the physical run cannot enter the production discovery edge.

The app and embedded downloader extension share the dedicated development app
group `group.com.thelongwest.journey.nonshippinglivetest.assets`. Register that
group and assign it to both live-test App IDs before asking Xcode to create the
two physical-device development profiles. The production app group and iCloud
container are not part of either live-test profile.

The live-test scheme's Archive action is pinned to ordinary `Release`.
Ordinary `Release` does not compile the fixture seam, excludes the fixture and
receipt, and remains subject to `validate-release-app-boundary.mjs`. A
`NON_SHIPPING_LIVE_TEST` product is physical-test input, never a release
candidate.

XcodeGen is a development-time project generator only. It is not linked into the app. The generated
`.xcodeproj` is disposable; source, configuration and authored data remain inspectable text files.

The current Metal prologue is a deterministic procedural foundation used to verify the render path.
It is not launch art. The Apple-facing adapters are locally testable through narrow protocols, but no
test double or simulator result is evidence that the real StoreKit product, hosted asset packs,
CloudKit container, APNs environment or physical-device path works. Those service and device checks
remain deferred release gates.
