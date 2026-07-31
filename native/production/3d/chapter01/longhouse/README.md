# Chapter 01 · Danube loess longhouse cell

Status: `CONTINUITY_PROOF`. This package proves the persistent frame, action
components, postholes, damage/repair states, succession state, authored cameras,
collisions, LOD and deterministic RealityKit export. It is blocked from
final-art approval until hero workers, timber, rope, thatch, weather and repair
animation meet the locked art-direction target.

The source of authority is the reviewable Python recipe plus
[`scene-spec.json`](./scene-spec.json). Generated `.blend`, USD, USDC and USDZ
files are build artefacts. No downloaded asset is used.

Two clean builds produce byte-identical USDA, USD/USDC, USDZ and portrait
preview files. The `.blend` file is retained as generated authoring evidence;
Blender embeds process-local data in that container, so it is verified against
the selected manifest but is outside the byte-reproducibility claim.

```sh
blender --background --factory-startup --python native/production/3d/chapter01/longhouse/scripts/generate.py
blender --background --factory-startup --python native/production/3d/chapter01/longhouse/scripts/validate.py
```

USD prim paths use underscores because USD identifiers cannot contain the
locked hyphenated runtime names. `userProperties:runtime_name`, USD
`displayName` and `entity-bindings.json` preserve the exact contract.
