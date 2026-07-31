# Chapter 01 signed immersive review package

This directory builds the non-shipping signed `ContentPackagePayloadV2` fixture
for `first-farmers-3d-review-v1`. It is a continuity and integrity proof, not a
final-art or final-audio approval.

The public package contains exactly one canonical V2 payload and the 34 assets
that payload names: five scene containers, one shared mobile PBR material
carrier, one shared directed-animation library, five environments, six
mechanism programs, six transitions and ten word-exact provisional narration
files.
Every inner asset size and SHA-256 must equal the signed outer manifest record.
No backstage status, provenance or quality-gate field is admitted to the
public package.

The five scene USDZ sources are the current generated continuity-proof cells.
The shared material and animation files are rights-cleared deterministic
candidates with their final art/contact gates still open. Final production
remains blocked on accepted world art, character integration, contact/IK and
LOD outputs.

The environment, mechanism and transition files are earlier Chapter 01 review
audio. The ten narration files use the exact V2 transcript with a macOS system
voice solely to prove offline binding, timing and restoration. They cannot be
promoted to final audio. Their frozen bytes and open narration gate live under
`backstage/`; the generator is a reproducible production recipe, not a claim
that system speech synthesis produces identical bytes each time.

Build and verify:

```sh
node build-review-package.mjs
node --test build-review-package.test.mjs
```

The compiler invokes the Swift V2 factory, signs the canonical package with a
deterministic non-secret review key, verifies every byte, and atomically
publishes `compiled/first-farmers-3d-review-v1.runtimefixture`. The release
compiler rejects this key family. iOS verification tests cover complete offline
load, cold-start admission, decode-edge asset checks and activation through the
existing immutable-generation and rollback authority.
