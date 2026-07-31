# Chapter 01 cattle rig candidate

Status: `ANIMAL_RIG_CANDIDATE`. Final-art gate: `OPEN`.

This library provides the two cattle forms already required by the authored 3D
cells: a close/middle-distance adult for the herd and final barrier, and a
younger animal for the Aegean boat. It deliberately does not add sheep, goats
or another species to the current scene contracts.

The source of authority is `generate_chapter01_cattle.py`. It generates all
geometry, UVs, textures, materials, skeletons and directed keyframes without an
external animal asset. `build-cattle-library.sh` pins Blender, builds two mobile
LODs twice, compares the canonical USDC and USDZ bytes, runs ARKit validation,
and writes `build-manifest.json`.

## Runtime contract

- Cloneable local-origin roots: `cattle_adult`, `cattle_young`.
- LOD0: close interaction and boat use, nominally 0–9 metres.
- LOD1: herd and middle distance, nominally 9–30 metres.
- Adult clips: `herd-walk`, `barrier-weight-shift`, `rest`.
- Young clips: `boat-brace`, `boat-weight-shift`, `rest`.
- Clip ranges are in root custom metadata and `build-manifest.json` at 24 fps.
- Preview camera, lights, ground and boat planks are excluded from runtime USD.

World-cell placement, contact timing and historical completion remain outside
the asset. The deterministic domain reducer is still the authority.

## Build

```sh
native/production/3d/chapter01/animals/build-cattle-library.sh
```

The build produces `outputs/chapter01-cattle-library-lod{0,1}.usdc`, matching
USDZ packages, three project-authored hide maps, an inspectable Blender file,
and a 9:16 review render.

## Open gates

- Close-camera anatomy and deformation review in the Aegean composition.
- Hoof-ground, body-barrier and boat-bracing contact polish in the cells.
- Final hair/fur treatment if the authored camera proves the current normal map
  insufficient.
- Final material, lighting, herd-variation and physical-iPhone performance
  approval.
