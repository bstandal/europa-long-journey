# Chapter 01 · Iron Gates cell

Status: `CONTINUITY_PROOF`. This is the deterministic RealityKit scenegraph,
state, camera, collision, LOD and export contract. It is deliberately blocked
from final-art approval until hero people, terrain, architecture, materials,
weather and contact animation meet the locked art-direction target.

The source of authority is the reviewable Python recipe plus
[`scene-spec.json`](./scene-spec.json). The generated `.blend`, USD, USDC and
USDZ files are build artefacts. No image is embedded as a background and no
downloaded geometry or texture enters the cell.

Two clean builds produce byte-identical USDA, USD/USDC, USDZ and portrait
preview files. The `.blend` file is retained as generated authoring evidence;
Blender embeds process-local data in that container, so it is verified against
the selected manifest but is outside the byte-reproducibility claim.

Build with the locked toolchain:

```sh
blender --background --factory-startup --python native/production/3d/chapter01/iron-gates/scripts/generate.py
```

Validate hashes, USD metadata, exact runtime bindings, state containers,
collision metadata, LOD declarations and USDZ integrity:

```sh
blender --background --factory-startup --python native/production/3d/chapter01/iron-gates/scripts/validate.py
```

Hyphens are illegal inside USD prim identifiers. The exporter therefore stores
the locked name in `userProperties:runtime_name`, mirrors it in
`userProperties:runtimeName`, writes it as USD `displayName`, and records the
sanitised prim path in `entity-bindings.json`. Runtime lookup must use that
binding contract rather than assume a prim-path spelling.
