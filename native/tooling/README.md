# Native content tooling

`npm test` exercises the canonical Swift wire model, the public/backstage
firewall, package cross-references, signed manifests and installed-file
verification.

## Backstage audio production

`npm run validate:audio` validates the P1.09 symbolic score, its independently
renderable stems, the five source-bound soundscape materials, authored silence
and the pinned zero-cost toolchain. `npm run render:audio-probe` creates local
48 kHz / 24-bit technical outputs and refreshes the non-approval receipt. The
authoritative method and open artistic gates are recorded in
`../audio/score-soundscape/README.md`.

Native asset provenance schema v3 adds two audio-only branches. A project-owned
symbolic score, procedural patch or edit uses `PROJECT_AUTHORED_AUDIO`. An
imported CC0 or MIT source uses `OPEN_LICENSE_AUDIO_SOURCE` with immutable URL,
exact bytes, SHA-256, licence evidence and required notices. Other open
licences and undocumented Apple audio fail closed.

## Diagnostic launch causal assembly

After extracting the canonical payload JSON from each of the eight launch
packages, validate them together against the shipping `collection.json`:

```sh
npm run validate:launch-assembly -- \
  /absolute/path/to/collection.json \
  /absolute/path/to/essential-payload.json \
  /absolute/path/to/paid-payload-1.json \
  /absolute/path/to/paid-payload-2.json \
  /absolute/path/to/paid-payload-3.json \
  /absolute/path/to/paid-payload-4.json \
  /absolute/path/to/paid-payload-5.json \
  /absolute/path/to/paid-payload-6.json \
  /absolute/path/to/paid-payload-7.json
```

The command performs document validation first. It then requires one payload
per declared package, identical world seeds, exact chapter ownership and
ordering, and globally unique world-effect IDs. All 24 chapters are replayed
in collection sequence. Success prints the deterministic final world SHA-256.
The command does not alter input files and cannot sign or publish a launch set.
The production compiler repeats this validation before and after signing.

## Atomic production launch compilation

The production command accepts one descriptor containing exactly the eight
package inputs in the locked delivery plan. Each record names a public source
tree, its package-specific editor approval and its asset-provenance registry:

```json
{
  "schemaVersion": 1,
  "packages": [
    {
      "packageID": "essential-free-v1",
      "sourceRoot": "/absolute/path/to/public/essential-free-v1",
      "approvalPath": "/absolute/path/to/backstage/essential-free-v1/launch-package-approval.json",
      "assetProvenancePath": "/absolute/path/to/backstage/essential-free-v1/native-asset-provenance.json"
    }
  ]
}
```

The real descriptor has one record for every locked package ID. Paths must be
absolute and unique. Public source trees and backstage controls must be
disjoint. Every source contains one package payload and the same exact
`collection.json` bytes.

Launch compilation refuses a blueprint while any chapter contract or arc
matrix entry remains `DRAFT_PENDING`. It requires a P-256 signing key outside
this repository, readable only by its owner.

Phase 0 approval does not approve later shipping prose or scenes. Each of the
eight launch packages therefore requires its own editor-in-chief approval in a
separate `backstage/` tree. That record binds the exact `collection.json`, exact
`ContentPackagePayload` bytes and every path, byte count and SHA-256 in the
public source tree. Any public edit after approval stops compilation. The
approval record is read as a control input and is never copied into the package.
No command creates or infers an approval.

```sh
LONG_WEST_PACKAGE_SIGNING_KEY_FILE=/absolute/path/outside/repository/package-key.pem \
LONG_WEST_PACKAGE_SIGNING_KEY_ID=production-key-01 \
npm run compile:launch-set -- \
  /absolute/path/to/backstage/launch-set-input.json \
  /absolute/path/to/submission/launch-set
```

`LONG_WEST_BLUEPRINT_ROOT` may override the default `native/blueprint` path.
The CLI reads key bytes from the permission-checked file; it accepts neither key
bytes nor a key path as a command-line argument and never prints either.

The command completes these gates in order:

1. Validate all eight public trees, Phase 0 approval, package approvals,
   provenance records, zero-cost registry entries and the byte-identical
   collection before signing anything.
2. Replay the exact 24 approved payloads in collection order.
3. Compile and sign all eight packages into one disposable set staging tree.
4. Verify every signed manifest and file, compare each staged payload with its
   approved preflight bytes, and replay the staged payloads again.
5. Write the set receipt beside `packages/` and atomically rename the complete
   staging tree into the submission path.

A failure leaves the prior submission set unchanged. The official CLI has no
standalone launch-package signing command; `compile` fails with an instruction
to use `compile-launch-set`. The internal `compilePublicPackage` function
remains available to the set compiler and isolated cryptographic tests. The set
compiler rejects the test-only approval bypass.

The launch approval's public inventory digest is SHA-256 of these UTF-8 lines,
including the final newline and one canonically path-sorted `file=` line for
every public source file:

```text
long-west-launch-public-inventory-v1
file=<POSIX path>\t<decimal byte count>\t<lowercase SHA-256>
```

Every approved save-migration plan has two independent authority digests. The
graph digest binds the package target, the complete explicit source-version
set, every unique route to the target and each edge's signed world-ownership
delta. The descriptor-inventory digest binds one implementation descriptor to
each edge. Compilation with a migration plan also requires the absolute
`saveMigrationDescriptorRoot` option. This root is backstage and must be
disjoint from the public package source. Every inventory path is opened below
that root as a real regular file; path escapes and symbolic links are rejected,
and the SHA-256 of the exact bytes must equal the inventory and graph
implementation digest. A package with no migration plan still uses the
canonical empty digests for its package version.

`launchPackageApprovalSHA256` is SHA-256 of these UTF-8 lines, again including
the final newline:

```text
long-west-launch-package-approval-v2
collectionSHA256=<SHA-256 of exact public CollectionManifest bytes>
payloadSHA256=<SHA-256 of exact public ContentPackagePayload bytes>
publicSourceInventorySHA256=<digest described above>
saveMigrationGraphSHA256=<canonical migration-graph digest for this package version>
saveMigrationDescriptorInventorySHA256=<canonical descriptor-inventory digest>
```

The submission receipt is `launch-set-receipt.json` at the launch-set root. It
never enters an individual package or its signed manifest. The receipt records
the collection digest, final replayed world digest, signing-key ID and, in
locked delivery order, each package's chapter IDs, payload path, payload digest
and signed manifest digest. It has no timestamp, so unchanged inputs produce
the same receipt digest even though ECDSA signature bytes may differ.

`receiptSHA256` is SHA-256 of these UTF-8 lines, including the final newline and
one `package=` line for each of the eight packages:

```text
long-west-launch-set-receipt-v1
collectionID=<stable collection ID>
collectionSHA256=<SHA-256 of the byte-identical CollectionManifest>
finalWorldSHA256=<SHA-256 returned by the 24-chapter replay>
keyID=<stable signing-key ID>
package=<package ID>\tchapters=<comma-separated chapter IDs>\tpayloadPath=<POSIX package-relative path>\tpayloadSHA256=<payload SHA-256>\tmanifestDigest=<signed manifest digest>
```

## Apple-hosted launch asset-pack archives

After the approved eight-package launch set has been compiled, the seven paid
packages can be turned into Apple asset-pack archives entirely locally:

```sh
npm run package:background-assets -- \
  --launch-set /absolute/path/to/submission/launch-set \
  --output /absolute/path/to/submission/background-assets \
  --trust /absolute/path/to/launch-package-trust.json \
  --approved-trust-receipt /absolute/path/to/approved-trust-receipt.json
```

The bridge invokes the installed `xcrun ba-package` tool and does not contact a
network service. Before creating anything, it revalidates the exact locked
eight-package set, the approved production trust root, every signed manifest
and file, the current collection/package specifications, ordered chapter
ownership and the complete 24-chapter world replay. `essential-free-v1` is
verified as part of the set but is never archived.

Each Apple manifest uses the on-demand asset-pack ID `paid-pack-0N` and the
single directory selector `packages/paid-pack-0N`. The signed semantic package
version is carried by `package-manifest.json`, the `.aar` filename and the
archive-set receipt; Apple's asset-pack manifest has no independent version
field. Output is published as one atomic directory containing:

```text
archives/paid-pack-01-1.0.0.aar
manifests/paid-pack-01-1.0.0.ba-manifest.json
background-assets-receipt.json
```

The receipt binds the raw signed-manifest SHA-256, signed `manifestDigest`,
archive SHA-256 and bytes, explicit archive ceiling, trust approval and launch
set. An unchanged rerun verifies and reuses the existing output. A failed or
changed run leaves the previous complete directory in place. Symbolic links,
special files, foreign paths, backstage paths, an unapproved key, an altered
input tree and an archive above its package ceiling all fail closed.

Tests can request the internal `NON_SHIPPING_TEST_FIXTURE` receipt status only
under `node --test`. The production CLI has no fixture switch and cannot label
provisional inputs as production archives.

## Post-launch deep-dive compilation

Future deep dives use the separate `validate-release` and `compile-release`
commands. This route never consumes the aggregate Phase 0 approval. It rejects
`collection.json`, every one of the 24 locked launch content IDs and all eight
launch package IDs.

One future-release source tree contains exactly one `ContentPackagePayload` and
one public `Release`. The Release owns the payload's exact ordered chapter-ID
sequence and declares the package version, minimum runtime and positive
installed-byte ceiling. Every world-effect ID is namespaced
`effect-<owning-chapter-id>-…`; the globally cumulative Journey can therefore
never confuse a later consequence with one from the 24 launch chapters or a
different deep dive. These values become the signed manifest metadata and the
`ContentPackageSpec` used by the Swift verifier.

The editor-in-chief approval, publication placement, canonical world authority
and asset-provenance registry remain in a separate `backstage/` tree. The world
authority contains the exact launch world seed accepted by runtime and the
subset of its node IDs to which later releases may attach. A placement on any
other node fails before signing. The future payload must carry the identical
world seed, so a later package cannot silently fork continuity.

The release approval hashes the exact bytes of the public Release, payload,
publication placement and world authority. Any edit after approval invalidates
compilation. None of these backstage controls enters the signed content
package, and no command creates or infers an approval.

```sh
LONG_WEST_RELEASE_APPROVAL_FILE=/absolute/path/to/backstage/release-approval.json \
LONG_WEST_RELEASE_PUBLICATION_FILE=/absolute/path/to/backstage/release-publication.json \
LONG_WEST_RELEASE_WORLD_AUTHORITY_FILE=/absolute/path/to/backstage/launch-world-authority.json \
LONG_WEST_RELEASE_ASSET_PROVENANCE_FILE=/absolute/path/to/backstage/asset-provenance.json \
npm run validate:release -- /absolute/path/to/release/public

LONG_WEST_PACKAGE_SIGNING_KEY_FILE=/absolute/path/outside/repository/package-key.pem \
LONG_WEST_PACKAGE_SIGNING_KEY_ID=production-key-01 \
LONG_WEST_RELEASE_APPROVAL_FILE=/absolute/path/to/backstage/release-approval.json \
LONG_WEST_RELEASE_PUBLICATION_FILE=/absolute/path/to/backstage/release-publication.json \
LONG_WEST_RELEASE_WORLD_AUTHORITY_FILE=/absolute/path/to/backstage/launch-world-authority.json \
LONG_WEST_RELEASE_ASSET_PROVENANCE_FILE=/absolute/path/to/backstage/asset-provenance.json \
npm run compile:release -- /absolute/path/to/release/public /absolute/path/to/staging/package
```

Both commands also require the shared zero-cost registry to have no unresolved
capability needed by a shipping asset. Every image and audio file must match the
release-specific provenance registry by path, byte count, SHA-256, rights,
tool lineage and shipping role.

The combined approval digest is SHA-256 of these UTF-8 lines, including the
final newline:

```text
long-west-future-release-approval-v3
releaseSHA256=<SHA-256 of exact public Release bytes>
payloadSHA256=<SHA-256 of exact public ContentPackagePayload bytes>
publicationSHA256=<SHA-256 of exact backstage publication-placement bytes>
worldAuthoritySHA256=<SHA-256 of exact canonical world-authority bytes>
saveMigrationGraphSHA256=<canonical migration-graph digest for this package version>
saveMigrationDescriptorInventorySHA256=<canonical descriptor-inventory digest>
```

## Signed manifest wire contract

`manifest.files` is ordered by raw UTF-8 path bytes. Paths cannot contain
control characters, backslashes, absolute prefixes or traversal segments. The
digest material is exactly these UTF-8 lines, including the final newline:

```text
long-west-package-v1
packageID=<stable ID>
packageVersion=<major>.<minor>.<patch>
schemaVersion=<major>.<minor>.<patch>
minimumRuntime=<major>.<minor>.<patch>
[saveMigrationSupportedSources=<comma-separated explicit source versions>]
[saveMigrationDescriptorInventory=<canonical descriptor-inventory SHA-256>]
[saveMigration=<ID>\t<from>\t<to>\tsave=<positive integer>\tstate=<positive integer>\tfields=<canonical field IDs>\toldEffectIDs=<canonical IDs>\tnewEffectIDs=<canonical IDs>\toldNodeIDs=<canonical IDs>\tnewNodeIDs=<canonical IDs>\toldTraceIDs=<canonical IDs>\tnewTraceIDs=<canonical IDs>\timplementation=<lowercase SHA-256>]
file=<POSIX path>\t<decimal byte count>\t<lowercase SHA-256>
```

The bracketed save-migration lines are omitted together when no migration plan
exists. Otherwise one `saveMigration=` line appears for every graph edge and
the verifier requires exactly one complete route from every declared source to
the package version. One `file=` line appears for every file record.
`manifestDigest` is the lowercase
SHA-256 of those bytes. `signature.value` is a base64 DER ECDSA P-256/SHA-256
signature over the UTF-8 64-character `manifestDigest`. `signature.keyID`
selects a trusted key pinned outside the package. Runtime public keys use
uncompressed ANSI X9.63 bytes (`04 || X || Y`), base64 encoded.
