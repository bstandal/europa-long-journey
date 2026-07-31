# Chapter 01 mobile PBR material candidates

Status: `MATERIAL_CANDIDATE`  
Shipping: `BLOCKED`  
Final art gate: `OPEN`

This library supplies pinned 1K surface maps for the Chapter 01 3D production
pipeline. It is not a final-art approval and it does not establish historical
form by itself. Geometry, scale, construction, wear, wetness, seasonal state
and material variation remain authored in the cell generators.

## Rights and source boundary

Every downloaded byte comes from an exact `https://dl.polyhaven.org` URL in
[`material-library-manifest.json`](./material-library-manifest.json). Poly Haven
states that all of its asset files are CC0 and allows commercial use and
redistribution without required attribution:

- License evidence: <https://polyhaven.com/license>
- Provider: <https://polyhaven.com/>

The manifest records each asset page, metadata endpoint, file-index endpoint,
author and author role, source MD5, project SHA-256, byte count, dimensions,
colour space and normal-map convention. Any mismatch stops the build.

## Selected candidates

| Material ID | Poly Haven source | Author | Intended Chapter 01 use |
|---|---|---|---|
| `soil-dirt-v1` | [Dirt](https://polyhaven.com/a/dirt) | Charlotte Baglioni | Worked soil and field microdetail |
| `gorge-dark-rock-v1` | [Dark Rock 02](https://polyhaven.com/a/dark_rock_02) | Amal Kumar | Iron Gates cliff and river-edge microdetail |
| `timber-fine-grain-v1` | [Fine Grained Wood](https://polyhaven.com/a/fine_grained_wood) | Rob Tuytel | Posts, braces, threshold and worked timber |
| `cloth-rough-weave-v1` | [Rough Linen](https://polyhaven.com/a/rough_linen) | colormass; Rico Cilliers | Woven-cloth normal and roughness microdetail |
| `reed-thatch-v1` | [Thatch Roof Angled](https://polyhaven.com/a/thatch_roof_angled) | Dimitrios Savva; Rob Tuytel | Reed/thatch roof microdetail |

The cloth source has a blue diffuse map and Poly Haven also categorises it
under cotton and hessian. Its base colour is therefore `REFERENCE_ONLY`.
Chapter 01 may use its normal and roughness maps with an authored neutral
flax/wool colour; it may not present the scan as proof of fibre identity.

Each material contains:

- `baseColor.jpg` in sRGB;
- `normal.jpg` in linear data space using OpenGL `+Y` orientation;
- `roughness.jpg` in linear data space.

All five candidates are dielectric and use the manifest's constant metallic
value of `0.0`; a redundant metallic texture is not packaged.

Four sets are exactly 1024 × 1024. Poly Haven's pinned Rough Linen 1K files
are 1024 × 1026; those exact source dimensions are recorded and verified.
Ambient occlusion and displacement are deliberately omitted from this mobile
candidate. Authored geometry carries silhouette and contact depth.

## Deterministic build

Run from the repository root:

```sh
python3 native/production/3d/chapter01/material-library/build_material_library.py
python3 native/production/3d/chapter01/material-library/build_material_library.py --verify-generated
```

The first command downloads and verifies all 15 maps. It independently builds
the package twice and stops unless the archives are byte-identical. ZIP entries
use fixed timestamps, permissions, ordering and `ZIP_STORED`; JPEG maps are
already compressed. No timestamp, host path or other volatile field enters the
package.

Generated outputs:

- `generated/unpacked/materials/<material-id>/<channel>.jpg`
- `generated/unpacked/manifest.json`
- `generated/unpacked/SHA256SUMS`
- `generated/chapter01-mobile-pbr-materials-v1.zip`
- `generated/build-receipt.json`

Current verified archive:

- bytes: `10,638,864`
- SHA-256: `85dc87db0742e00e0b74ead817c22ba94709a1fccde321e92d2a2012195ef5bf`
- two complete builds: byte-identical

`--manifest-only` validates the checked-in rights, channel and path gates
without making a network request. `--verify-generated` validates the existing
archive and unpacked files without a network request.

## Integration limits

- Use these maps as microdetail, not as geometry or historical evidence.
- Keep base colour readable in the project's midtone range; darkness frames
  the acted material rather than hiding it.
- Do not use the cloth blue diffuse map in Chapter 01.
- Do not infer tree species, geology, roof construction or field state from a
  scan. Those decisions belong in the authored scene and its provenance.
- Cell-level visual approval and the physical iPhone performance gate remain
  open after a material is integrated.

## RealityKit material carrier

[`chapter01-material-carrier.usda`](./chapter01-material-carrier.usda) binds
the approved candidate channels to five stable `UsdPreviewSurface` material
prims. The generated carrier is self-contained: every texture reference is
package-relative, every member is stored without compression on a 64-byte
boundary, and the root USDC is the first package member.

| Role | Stable material prim | RealityKit extraction swatch |
|---|---|---|
| Soil | `/Chapter01MaterialCarrier/Materials/M_CH01_Soil` | `Swatch_Soil` |
| Dark rock | `/Chapter01MaterialCarrier/Materials/M_CH01_DarkRock` | `Swatch_DarkRock` |
| Timber | `/Chapter01MaterialCarrier/Materials/M_CH01_Timber` | `Swatch_Timber` |
| Neutral cloth | `/Chapter01MaterialCarrier/Materials/M_CH01_ClothNeutral` | `Swatch_ClothNeutral` |
| Thatch | `/Chapter01MaterialCarrier/Materials/M_CH01_Thatch` | `Swatch_Thatch` |

The cloth material uses the authored linear RGB value `(0.42, 0.31, 0.20)`
with the pinned weave normal and roughness. The blue source diffuse map is not
present in the USDZ.

Build and verify:

```sh
python3 native/production/3d/chapter01/material-library/build_material_carrier.py
python3 native/production/3d/chapter01/material-library/build_material_carrier.py --verify-generated
```

The build performs two independent USDC builds and two independent USDZ
builds, then compares bytes. It runs strict `usdchecker --arkit` and loads all
five swatches through RealityKit from the local USDZ. Current artifact:

- path: `generated/carrier/chapter01-material-carrier-v1.usdz`
- bytes: `9,792,365`
- SHA-256: `bb79b8b83ea92e7baca4d437602693649d6111b0e79804e4633a7731e817a045`
- classification: `MATERIAL_CANDIDATE`
- final art gate: `OPEN`

The swatches make the materials addressable after RealityKit import. They are
carrier geometry and must never be mounted in a chapter cell. Load the USDZ,
find the named swatch, copy its single `PhysicallyBasedMaterial`, then release
the carrier entity.

### Signed V2 review-package path

[`material-carrier-contract.json`](./material-carrier-contract.json) fixes the
review-package asset ID and destination path. Integration can remove the five
current `materials/material-0N.usdz` files, which are byte copies of scene
USDZs, and include the carrier once at:

`immersive/first-farmers/materials/chapter01-material-carrier-v1.usdz`

Use asset ID `asset-first-farmers-material-carrier-v1`, kind `material`, and
point the provisional material states at that one asset. Runtime material
selection uses the stable role-to-prim table above; it must not treat cell
number as a material family. This packaging repair changes no interaction,
`WorldEffect`, reducer state, public text or editorial contract.
