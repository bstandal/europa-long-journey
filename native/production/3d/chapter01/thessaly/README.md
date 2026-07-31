# Thessaly household-store continuity proof

This directory is the text-authored source of the Chapter 01 Thessaly 3D cell.
It contains no downloaded geometry, textures, scans, fonts, or third-party
assets. Blender creates every mesh and material from deterministic Python.

Status: `CONTINUITY_PROOF`. The runtime structure, transitions, material-state
continuity, interaction bindings, cameras, LODs, and packaging are usable for
integration. This cell is not approved for shipping or representative of final
visual quality. In particular, the two procedural human figures are blocking
stand-ins that must be replaced by the shared production human base. Character
anatomy, facial quality, grounded contact, winter precipitation, background
atmosphere, and final lighting remain outside this proof's acceptance claim.

## Build

The proof toolchain is pinned to Blender 5.2.0 LTS. From this directory:

```sh
./build.sh
```

The command rebuilds the USD family in `outputs/`, renders three non-canonical
review images, and runs structural and RealityKit-oriented USD validation. The
canonical runtime build deliberately contains no generation timestamp.
Rebuilding on the pinned Blender build reproduces the runtime hashes in
`build-manifest.json`. Review PNGs are excluded from this byte-identity claim.

## Runtime contract

The USD root has the logical name `thessalian-household-store`. Hyphens are not
legal in USD prim identifiers, so the exporter uses safe prim identifiers and
stores each exact logical name as both USD `displayName` and
`userProperties:runtimeName`. `entity-bindings.json` records the logical-name to
prim-path mapping used by the runtime.

The default visible state is harvest. `state-winter` and `state-spring` remain
authored in the same scene and are initially invisible. State roots, action
volumes, camera anchors, transition anchors, and material-response objects are
separate entities so the deterministic domain model can project consequences
without asking rendering or physics to decide them.

Action volumes are real meshes with zero-opacity materials and explicit
collision metadata. The export does not depend on Blender-only empties for
interaction hit areas.

## Outputs

- `thessaly-household-store.usd`: inspectable ASCII USD source.
- `thessaly-household-store.usdc`: full-detail binary runtime asset.
- `thessaly-household-store.usdz`: RealityKit package.
- `thessaly-household-store-lod1.usdc`: reduced secondary-residency asset.
- `thessaly-household-store-lod2.usdc`: low-detail transition silhouette.
- `preview-*.png`: review-only renders for the three material states; they are
  not canonical runtime inputs and their PNG bytes are not reproducibility
  evidence.

`provenance.json` is the rights and source-lineage record.
`build-manifest.json` locks tool, source, output, topology, and binding hashes.
