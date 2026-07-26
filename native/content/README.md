# Native content source boundary

`public/` will contain only approved text, scenes, interactions, audio cues,
accessible alternatives and world effects that may ship to an iPhone.

`backstage/` will contain editorial contracts, research, claim registers,
sources and F1–F7 verifier findings. Nothing below `backstage/` may be copied,
referenced or encoded into a public package.

The package compiler starts from an explicit `public/` path and rejects known
research fields and academic-regression phrases recursively. It never copies a
parent content directory and then tries to remove private files afterward.

`backstage/native-asset-provenance.json` is also a compiler control input, but is never
copied into a package. Every shipping image and audio file must match an approved
path, byte count and SHA-256 record with source lineage, tool lineage, commercial
rights and zero incremental cost. The empty Phase 0 registry intentionally makes
all future binary assets fail closed until they are authored and approved.

Source lineage is a closed union. `WEB_SOURCE_DERIVATIVE` records carry the exact
leading-slash path below `site/public`, byte count and SHA-256 from
`native/blueprint/source-asset-provenance.json`; the source must be marked eligible
there, and every recorded reuse obligation must be copied exactly. A path absent
from that inventory, a blocked web plate or a changed hash fails compilation.
`GENERATED_ORIGINAL` records have no web path. They require an explicit stable
source ID, exact master hash, `PROJECT_OWNED` rights and project-owned generation
terms. In either branch the shipping output still requires a cleared zero-cost
tool chain, commercial-use clearance and its own output hash.

Every launch package also requires a package-specific editor approval outside
`public/`. It binds the exact collection bytes, exact payload bytes and a
canonical digest of the complete public source inventory, including every
binary asset path, byte count and SHA-256. A Codex provisional visual-master
authority can build local development assets, but cannot satisfy this gate or
set `approvedForShipping`. Phase 0 approval alone
cannot authorise shipping wording or scenes, and a changed file must receive a
new explicit launch-package approval before compilation. The schema is
`schemas/launch-package-approval.schema.json`; no approval record exists until
the editor-in-chief makes that decision.

A post-launch deep dive is compiled from its own bounded `public/` root. It must
contain one payload under `chapters/` and one Release under `releases/`; it must
not contain the launch `collection.json`. Its separate backstage tree contains
the release-specific asset provenance and the editor-in-chief approval that
binds the exact Release and payload bytes. Those controls may be read by the
compiler but can never enter the signed file inventory.
