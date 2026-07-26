# Harvest production-master candidates

Status: `NON_SHIPPING_CANDIDATES`

Nothing in this file approves an image, layer, mask or derivative for shipping.
Each candidate must pass full-resolution visual inspection, historical and
material review, both portrait crops, layer feasibility, provenance and the
editor-in-chief's separate production-asset approval.

## Candidate v1 — Codex built-in image generation

- File: `production-master-candidate-v1.png`
- Dimensions: `941 × 1672 px`
- SHA-256: `18f291dcb3c2842cbd73418b73bbf603713f4676898d9e8582914821fb425ca0`
- Tool: `openai-imagegen-codex`
- Result: `REJECTED_AS_PRODUCTION_MASTER`
- Reason: the reconstruction is coherent and removes all baked interface
  graphics, but it is below the required `1290 × 2796 px` master size. It may
  remain a non-shipping composition reference and cannot be enlarged into a
  production master.

### Prompt

```text
Use case: historical-scene
Asset type: new non-shipping full-resolution portrait reconstruction candidate for a native iPhone 2.5D scene in The Long West: EUROCENTRIC.
Input images: Image 1 is the editor-selected composition reference; Image 2 is the editor-approved composition-and-anatomy target and is the primary authority; Image 3 is a rain-logic reference only, showing the dry sheltered foreground work zone beneath a storm.
Primary request: Reconstruct the complete scene as a genuinely new high-detail master, not an upscale and not a collage. A Neolithic Thessalian farming settlement around 6500–6000 BC under an approaching storm. One finite mound of clean grain on coarse woven cloth dominates the near foreground. Three simultaneous material destinations remain clearly legible in the middle ground: household winter food and hearth activity on the left, a dry protected reserve that can be physically sealed in the centre, and selected spring seed beside prepared ground on the right. The entire settlement is one continuous inhabited place.
Composition/framing: strict vertical 9:16 master intended for 2160 x 3840 delivery, with at least 16 percent fully authored overscan around the useful camera crop. Preserve the depth hierarchy and camera anatomy of Image 2: storm field and distant mountains; inhabited settlement; three destinations; dominant finite grain source; near-black textured closure. Keep the grain source centred around lower-middle and all three destinations visible together. Include clean negative sky for native title text, but bake no text.
Lighting/mood: Darkness frames the evidence. Near-black gives depth, readable midtones reveal hands, grain, woven fibres, mud plaster, timber, baskets, animals and field work; the grain and active storage mechanisms carry the clearest warm light. Rain is visible in the distance and sky, while the near foreground grain-allocation work zone is credibly sheltered and dry. Lighting directions, smoke and weather are coherent.
Historical/material constraints: early Neolithic Thessaly; mudbrick or wattle-and-daub dwellings, timber, reed/thatch, coarse plant-fibre cloth, hand-shaped pottery, woven baskets, stone/wood/bone tools, hand-worked plots, sheep/goats/cattle only where plausible. Natural undyed linen/wool-like garments with simple construction. Rebuild all hands, faces, baskets, roofs, tools and storage structures with correct anatomy, scale, perspective and joins. The centre reserve must read as a plausible dry protected storage practice, not a fantasy raised granary. People are working, not posing.
Production constraints: no typography, numbers, labels, arrows, rings, target markers, glowing route, interface, symbols, watermark or baked UI. No empty triptych, no isolated vignettes, no fantasy lighting, no pristine museum reconstruction. No rain falling on the exposed foreground grain. No modern objects, metal tools, wheels, horses, stone architecture, dramatic heroic poses, decorative gold, or cinematic battle styling. Maintain finished world detail through the overscan; no blurred/generated padding. This is a complete unified composition that can later be separated into registered depth layers and clean plates.
```

## Candidate v2 — local FLUX.2 full-resolution edit

- File: `production-master-candidate-v2.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `23989`
- SHA-256: `3c0754158da7a2e900d629f25afbcb3d98c27a355b8ede62f0897ec8f10ddfe3`
- Tool: `mflux-local` version `0.18.0`
- Model: `flux2-klein-4b`, official snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Transformer blob: `9f29f9edcfdae452a653ffb51a534ca4decd389952c225724ff3b94042612a6e`
- Text-encoder blobs:
  `8c0506e7f4936fa7e26183a4fd8da4e2bdbc5990ba64ae441f965d51228f36ea`,
  `82f2bd839378541b0557bfabaf37c7d3d637071fdcb73302dedd7cf61162ce07`
- VAE blob: `ca70d2202afe6415bdbcb8793ba8cd99fd159cfe6192381504d6c4d3036e0f04`
- Seed: `21076500`
- Quantisation: `8-bit`
- Steps: `4`
- Guidance: `3.5`
- Inputs: `reconstruction-master-draft-v2.png`, `selected-direction.png`,
  `rain-logic-pass-v2.png`
- Prompt: exact bytes in `flux2-production-master-prompt.txt`
- Result: `REJECTED_BLACK_NAN_OUTPUT`
- Reason: the output contains no usable image information. MFLUX emitted
  `RuntimeWarning: invalid value encountered in cast` during image conversion,
  and the exported PNG is uniformly black. The distilled FLUX.2 contract uses
  guidance `1.0`; this run incorrectly supplied `3.5`. Its `--metadata` sidecar
  contains JSON `null`, so the command parameters above are the authoritative
  attempt record.

### Command

```sh
mflux-generate-flux2-edit \
  --model flux2-klein-4b \
  --quantize 8 \
  --image-paths reconstruction-master-draft-v2.png selected-direction.png rain-logic-pass-v2.png \
  --prompt-file flux2-production-master-prompt.txt \
  --width 1296 \
  --height 2800 \
  --steps 4 \
  --guidance 3.5 \
  --seed 21076500 \
  --metadata \
  --output production-master-candidate-v2.png
```

Candidate v2 is retained only as a deterministic failure record. It cannot be
used as a visual source, layer source or shipping asset.

## Candidate v3 — corrected FLUX.2 guidance, quantised edit

- File: `production-master-candidate-v3.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `23989`
- SHA-256: `b4e379100605dd8709479adf071d86b2fbd07a2cbd7bbf2d7ced5991c92ed5d5`
- Tool: `mflux-local` version `0.18.0`
- Model: `flux2-klein-4b`, official snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076500`
- Quantisation: `8-bit`
- Steps: `4`
- Guidance: `1.0`
- Inputs: `reconstruction-master-draft-v2.png`, `selected-direction.png`,
  `rain-logic-pass-v2.png`
- Prompt: exact bytes in `flux2-production-master-prompt.txt`
- Result: `REJECTED_BLACK_NAN_OUTPUT`
- Machine audit: `minimum=0`, `maximum=0`, `mean=0`,
  `standardDeviation=0`, `nearBlackFraction=1`
- Reason: correcting the distilled model's guidance contract did not remove
  the numerical failure. MFLUX again emitted `RuntimeWarning: invalid value
  encountered in cast`; every exported pixel is black, and the metadata sidecar
  is JSON `null`. This isolates the failure to this quantised edit pipeline
  rather than the earlier guidance error.

### Command

```sh
mflux-generate-flux2-edit \
  --model flux2-klein-4b \
  --quantize 8 \
  --image-paths reconstruction-master-draft-v2.png selected-direction.png rain-logic-pass-v2.png \
  --prompt-file flux2-production-master-prompt.txt \
  --width 1296 \
  --height 2800 \
  --steps 4 \
  --guidance 1.0 \
  --seed 21076500 \
  --metadata \
  --output production-master-candidate-v3.png
```

Candidate v3 is retained only as a deterministic failure record. The next
diagnostic removes quantisation at reduced resolution before another
full-resolution attempt is authorised.

## Candidate v4 — unquantised reduced-resolution diagnostic

- File: `production-master-candidate-v4-diagnostic.png`
- Dimensions: `512 × 1024 px`
- Bytes: `1018008`
- SHA-256: `e0fa8d2417f4780cd205fe3a21742e156689baad8e4adaa1f4269ba03b2c582d`
- Tool: `mflux-local` version `0.18.0`
- Model: `flux2-klein-4b`, official snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076500`
- Quantisation: none
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Steps: `4`
- Guidance: `1.0`
- Result: `DIAGNOSTIC_PASS_PIPELINE_ONLY`
- Machine audit: luma range `225`, mean `58.547`, standard deviation
  `29.966`; no NaN warning; peak MLX memory `13.00 GB`
- Visual result: the image contains usable tonal information, proving that
  quantisation caused the black output. It remains categorically non-shipping:
  it is undersized, carries baked white arrows inherited from the UI reference,
  shows only two clear material routes and does not keep the foreground grain
  safely dry.

### Command

```sh
mflux-generate-flux2-edit \
  --model flux2-klein-4b \
  --low-ram \
  --mlx-cache-limit-gb 8 \
  --image-paths reconstruction-master-draft-v2.png selected-direction.png rain-logic-pass-v2.png \
  --prompt-file flux2-production-master-prompt.txt \
  --width 512 \
  --height 1024 \
  --steps 4 \
  --guidance 1.0 \
  --seed 21076500 \
  --metadata \
  --output production-master-candidate-v4-diagnostic.png
```

The full-resolution successor removes the baked-UI source image and conditions
only on the clean reconstruction and rain-logic references.

## Candidate v5 — first unquantised full-resolution reconstruction

- File: `production-master-candidate-v5.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `6051417`
- SHA-256: `5d6aa9050c2c03ea0e697d635185adcb127008f526416473cc473c58274f0551`
- Tool: `mflux-local` version `0.18.0`
- Model: `flux2-klein-4b`, official snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076500`
- Quantisation: none
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Steps: `4`
- Guidance: `1.0`
- Inputs: `reconstruction-master-draft-v2.png`, `rain-logic-pass-v2.png`
- Prompt: exact bytes in `flux2-production-master-prompt.txt`
- Machine result: `SANITY_PASS`; luma range `173`, mean `57.562`, standard
  deviation `23.523`; peak MLX memory `42.78 GB`
- Result: `SUPERSEDED_AS_COMPOSITION_PARENT`
- Reason: the full-resolution local chain works and no baked UI survives, but
  the roof does not visibly shelter the complete grain-allocation zone and the
  large open central pen cannot read as a dry, sealable reserve. The image is
  retained as the exact parent for the two targeted built-in edits below.

## Candidate v6 — targeted shelter edit

- File: `production-master-candidate-v6-shelter-edit.png`
- Dimensions: `853 × 1844 px`
- Bytes: `2691395`
- SHA-256: `57e3a72efe660ab7e4cd317e10ce1ab0cd0bcf479394d3f7fbcae21f3a3a358c`
- Parent: candidate v5,
  `5d6aa9050c2c03ea0e697d635185adcb127008f526416473cc473c58274f0551`
- Tool: `openai-imagegen-codex`, session-provided built-in edit
- Result: `NON_SHIPPING_SHELTER_REFERENCE`
- Reason: the complete foreground now sits beneath a structurally legible
  timber-and-thatch canopy and the storm remains outside it. The output is
  below master resolution and the central open pen remains unresolved.

### Exact edit prompt

```text
Use case: precise-object-edit
Asset type: non-shipping production-master candidate for a native iPhone 2.5D historical scene in The Long West: EUROCENTRIC.
Input image: Image 1 is the edit target. Preserve its portrait composition, camera position, people, settlement, grain mound, baskets, hearth, fields, livestock, mountains, restrained dark palette, and every historically useful material detail.
Primary request: correct only the physical shelter logic. Extend and complete the existing timber-and-thatch canopy at the upper and left edge so the entire foreground grain-allocation work zone—including the full cloth, grain mound, nearest baskets, and working hands—is visibly beneath a credible roof. The canopy must have coherent early-Neolithic timber supports, beam joins, perspective, drainage, and depth. Keep the storm and rain clearly visible across the open middle and far distance, but show no rain streaks, wet sheen, splashes, runoff, or exposed storm light on the sheltered grain and cloth.
Composition/framing invariants: keep the exact vertical framing and depth hierarchy; retain clean negative storm sky; retain all three material destinations; do not crop or enlarge the grain; do not move or redesign any person, animal, building, vessel, field, mountain, or destination.
Historical/material constraints: early Neolithic Thessaly, 6500–6000 BC; rough timber, reed and thatch construction; plausible load-bearing posts and lashings; no metal fasteners or later architecture.
Avoid: typography, numbers, labels, arrows, rings, route marks, interface, signs, symbols, watermark, modern objects, fantasy lighting, new people, duplicated limbs, anatomy changes, blur padding, rain on the grain, or any change outside the shelter and local rain interaction. This is a targeted structural correction, not a restyle.
```

## Candidate v7 — targeted storage edit

- File: `production-master-candidate-v7-storage-edit.png`
- Dimensions: `853 × 1844 px`
- Bytes: `2673572`
- SHA-256: `f3076add8bb811918319ce32e8385e1c3214eddcb0f3d1917546cbcec7b6aa87`
- Parent: candidate v6,
  `57e3a72efe660ab7e4cd317e10ce1ab0cd0bcf479394d3f7fbcae21f3a3a358c`
- Tool: `openai-imagegen-codex`, session-provided built-in edit
- Result: `NON_SHIPPING_COMPOSITION_REFERENCE`
- Reason: the centre is now a compact, materially legible reserve with one
  receiving bin and covered bins ready for sealing. The winter-food hearth,
  reserve and spring-seed work remain distinct. The output is below production
  resolution and therefore becomes only the composition parent for a new local
  full-resolution reconstruction.

### Exact edit prompt

```text
Use case: precise-object-edit
Asset type: non-shipping production-master candidate for a native iPhone 2.5D historical scene in The Long West: EUROCENTRIC.
Input image: Image 1 is the edit target. Preserve the exact portrait framing, complete timber-and-thatch canopy, storm, people, bodies and hands, grain mound, cloth, baskets, hearth, settlement, fields, livestock, mountains, lighting, palette, and every element outside the central storage installation.
Primary request: replace only the large open rectangular mud-walled pen in the centre-right middle ground. Make this destination read immediately as dry household grain reserve: a compact group of low plastered clay storage bins and large raw-clay vessels beneath the canopy, with fitted woven-reed or light timber lids ready to be sealed around their rims with clay. Show one bin open to receive grain and two already closed; keep their scale practical for household storage. Preserve clear floor access from the foreground grain mound. The installation must be visually distinct from the winter-food hearth at left and the selected spring-seed work at right.
Historical/material constraints: a materially plausible early-Neolithic northern Greek solution using clay/plaster, straw temper, reed, woven fibre and timber; no raised fantasy granary, no masonry, no metal fittings, no wheel-made vessels, no monumental communal store.
Invariants: change only the central storage object and the immediately occluded ground behind it. Keep every person and all anatomy pixel-stable in appearance and position. Keep the canopy and dry foreground unchanged.
Avoid: typography, numbers, labels, arrows, circles, target marks, interface, signs, symbols, watermark, modern objects, new people, duplicated vessels, impossible lids, fantasy architecture, restyling, reframing, or changes elsewhere.
```

## Candidate v8 — full-resolution reconstruction of v7

- File: `production-master-candidate-v8.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `5965054`
- SHA-256: `3819f496bc1b62d0746812c1fefdd83c6055507fc7ae8e569ef2788cd5096e4c`
- Parent: candidate v7,
  `f3076add8bb811918319ce32e8385e1c3214eddcb0f3d1917546cbcec7b6aa87`
- Tool/model: unquantised `mflux-local` `0.18.0` /
  `flux2-klein-4b` snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076501`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Steps/guidance: `4` / `1.0`
- Prompt: exact bytes in `flux2-production-master-reconstruction-prompt.txt`
- Machine result: `SANITY_PASS`; luma range `198`, mean `47.076`, standard
  deviation `21.445`
- Result: `SUPERSEDED_BY_TARGETED_CORRECTIONS`
- Reason: the full-size canopy and reserve logic survive, but a bright wrist
  band can read as forbidden metal and the oversized, repeated grain shapes do
  not survive material review.

## Candidate v9 — targeted wrist correction

- File: `production-master-candidate-v9-wrist-edit.png`
- Dimensions: `853 × 1844 px`
- Bytes: `2489549`
- SHA-256: `13d80b8b7c10045c8fc3b8331c07e98def97e35129ced9db96b5621ea92fd806`
- Parent: candidate v8,
  `3819f496bc1b62d0746812c1fefdd83c6055507fc7ae8e569ef2788cd5096e4c`
- Tool: `openai-imagegen-codex`, session-provided built-in edit
- Result: `NON_SHIPPING_CORRECTION_REFERENCE`
- Reason: the seated worker now has bare wrists. The output is below master
  resolution and the grain morphology remains rejected.

### Exact edit prompt

```text
Use case: precise-object-edit
Asset type: non-shipping correction pass for a native iPhone 2.5D historical production master.
Input image: Image 1 is the edit target and must remain compositionally unchanged.
Primary request: remove only the bright bracelet or wrist band from the seated woman's near wrist at centre-right, where her hands work over the woven basket. Replace it with continuous bare skin; no jewellery, ornament, cord or object around either wrist.
Invariants: preserve every pixel-level visual choice outside that tiny wrist region: exact framing, canopy, rain, people, faces, poses, fingers, clothing, grain mound, baskets, storage bins and lids, hearth, animals, settlement, lighting, palette and texture. Do not alter the hand anatomy or move the wrist.
Avoid: any metal, jewellery, new object, anatomy change, restyling, reframing, typography, symbols, watermark or edits elsewhere.
```

## Candidate v10 — targeted grain correction

- File: `production-master-candidate-v10-grain-edit.png`
- Dimensions: `853 × 1844 px`
- Bytes: `2427879`
- SHA-256: `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Parent: candidate v9,
  `13d80b8b7c10045c8fc3b8331c07e98def97e35129ced9db96b5621ea92fd806`
- Tool: `openai-imagegen-codex`, session-provided built-in edit
- Result: `NON_SHIPPING_COMPOSITION_REFERENCE`
- Reason: the exact mound now reads as thousands of naturally small dry cereal
  kernels rather than repeated pasta-like pieces. Its undersized bytes remain
  prohibited as a production master.

### Exact edit prompt

```text
Use case: precise-object-edit
Asset type: non-shipping correction pass for a native iPhone 2.5D historical production master.
Input image: Image 1 is the edit target and must remain compositionally unchanged.
Primary request: replace only the morphology and surface texture of the pale grain mound on the foreground cloth. Keep the mound's exact silhouette, height, footprint, volume, shadows and lighting, but make it consist of thousands of naturally small early cereal kernels at correct scale relative to the nearby hands and basket weave. Use short, plump, slightly tapered hulled einkorn/emmer-wheat and barley-like kernels, each matte and irregular with subtle longitudinal creases, varied warm straw-to-tan colour, occasional tiny husk fragments and natural packing. The mound must read instantly as real dry grain, not enlarged objects.
Invariants: preserve the cloth and every pixel-level visual choice outside the grain kernels: exact framing, canopy, rain, people, hands, bare wrists, clothing, baskets, storage bins, lids, hearth, animals, settlement, lighting and palette.
Avoid: pasta, larvae, worms, rice, maize, almonds, beans, polished pellets, identical repeated kernels, wet sheen, anatomy changes, restyling, reframing, typography, symbols, watermark or edits outside the mound.
```

## Candidate v11 — full-resolution reconstruction of v10

- File: `production-master-candidate-v11.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `5790574`
- SHA-256: `3d133537912cea7a08d03a8dd4875e145e05df4d765c4c1dcd4701c949dec278`
- Parent: candidate v10,
  `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Tool/model: unquantised `mflux-local` `0.18.0` /
  `flux2-klein-4b` snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076502`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Steps/guidance: `4` / `1.0`
- Prompt: exact bytes in `flux2-production-master-reconstruction-prompt.txt`
- Machine result: `SANITY_PASS`; luma range `226`, mean `48.078`, standard
  deviation `20.705`
- Result: `FULL_RESOLUTION_CANDIDATE_UNDER_REVIEW`
- Open review: canopy, dry foreground, reserve and kernel scale now pass the
  targeted logic checks. Full-resolution anatomy, the hearth group, all
  objects, both camera crops and overall artistic force still require a final
  side-by-side decision; these bytes are not approved for shipping.

## Candidate v12 — image-to-image reconstruction diagnostic

- File: `production-master-candidate-v12-img2img-diagnostic.png`
- Dimensions: `512 × 1024 px`
- Bytes: `895212`
- SHA-256: `dc9e1f7e98344215d3fc9fbd9de99336fc32b09e129d5e377e60011e80efb975`
- Parent: candidate v10,
  `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Tool/model: unquantised `mflux-local` `0.18.0` /
  `flux2-klein-4b` snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076503`
- Image strength: `0.75`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Requested steps/guidance: `4` / `1.0`; image-to-image strength reduced the
  executed denoising schedule to one step
- Prompt: exact bytes in `flux2-production-master-reconstruction-prompt.txt`
- Machine result: `REJECT`; luma range `197`, mean `49.427`, standard
  deviation `22.657`; peak MLX memory `14.78 GB`
- Result: `NON_SHIPPING_PIPELINE_DIAGNOSTIC`
- Reason: the image-to-image route preserves the selected composition more
  closely than the edit reconstruction, but this diagnostic is far below the
  production-master dimensions.

### Exact local command

```sh
mflux-generate-flux2 \
  --model flux2-klein-4b \
  --low-ram --mlx-cache-limit-gb 8 \
  --image-path production-master-candidate-v10-grain-edit.png \
  --image-strength 0.75 \
  --prompt-file flux2-production-master-reconstruction-prompt.txt \
  --width 512 --height 1024 --steps 4 --guidance 1.0 \
  --seed 21076503 --metadata \
  --output production-master-candidate-v12-img2img-diagnostic.png
```

## Candidate v13 — full-resolution image-to-image reconstruction

- File: `production-master-candidate-v13.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `5487485`
- SHA-256: `fd1d91518730a539c9c2d9572ab53655753caab12b9b512ec46d93173e80ff55`
- Parent: candidate v10,
  `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Tool/model: unquantised `mflux-local` `0.18.0` /
  `flux2-klein-4b` snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076503`
- Image strength: `0.75`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Requested steps/guidance: `4` / `1.0`; image-to-image strength reduced the
  executed denoising schedule to one step
- Prompt: exact bytes in `flux2-production-master-reconstruction-prompt.txt`
- Machine result: `SANITY_PASS`; luma range `162`, mean `50.556`, standard
  deviation `19.904`; peak MLX memory `54.96 GB`
- Result: `REJECTED_MATERIAL_REVIEW`
- Reason: the full-resolution route retains the useful canopy, three material
  destinations and dry work zone, but the hearth vessel reads as a suspended
  metal cauldron. The grain reads closer to pulses than hulled cereal, and the
  reconstruction smooths several people and buildings into a generic digital
  illustration. It cannot become a layer master without a new material pass.

### Exact local command

```sh
mflux-generate-flux2 \
  --model flux2-klein-4b \
  --low-ram --mlx-cache-limit-gb 8 \
  --image-path production-master-candidate-v10-grain-edit.png \
  --image-strength 0.75 \
  --prompt-file flux2-production-master-reconstruction-prompt.txt \
  --width 1296 --height 2800 --steps 4 --guidance 1.0 \
  --seed 21076503 --metadata \
  --output production-master-candidate-v13.png
```

## Candidate v14 — targeted hearth-vessel correction

- File: `production-master-candidate-v14-hearth-edit.png`
- Dimensions: `853 × 1843 px`
- Bytes: `2342147`
- SHA-256: `ec6ade20ff8343051521c4c9f40c4dd9ef5900ec12c81e90ea925619ebdb1fc0`
- Parent: candidate v13,
  `fd1d91518730a539c9c2d9572ab53655753caab12b9b512ec46d93173e80ff55`
- Tool: `openai-imagegen-codex`, session-provided built-in edit
- Machine result: `REJECT`; luma range `134`, mean `48.539`, standard
  deviation `19.720`; dimensions below the production-master floor
- Result: `NON_SHIPPING_MATERIAL_REFERENCE`
- Reason: the suspended handled cauldron is now a low, handleless vessel seated
  in the hearth stones. Its soot-darkened surface still requires a production
  reconstruction that resolves fired-clay material unmistakably, and the
  inherited grain and generic-illustration defects remain open.

### Exact edit prompt

```text
Use case: precise-object-edit.
Asset type: non-shipping correction pass for a portrait native iPhone 2.5D historical scene master for The Long West: EUROCENTRIC.
Input image: Image 1 is the sole edit target. Preserve its exact portrait composition, camera, roof, rain, every person, body, hand, face, garment, grain, basket, storage bin, vessel, animal, building, field, mountain, lighting, palette, depth and texture outside the tiny hearth-vessel region at lower-left middle ground.
Primary request: replace only the black suspended cooking cauldron above the left hearth. It is an anachronistic metal object. Replace it with one plausible early-Neolithic hand-built fired-clay cooking vessel: thick-walled, low rounded body, matte warm brown/charcoal clay, subtly irregular hand-shaped rim, no glaze, no metallic surface, no handle, no bail, no chain and no suspension. Seat the clay vessel securely among the existing hearth stones at the edge of the existing embers, with physically coherent contact shadow, soot darkening and firelight. Keep the fire, smoke, seated woman, child, tools and all surrounding stones in exactly the same positions except for the minimum local occlusion needed by the new vessel.
Historical constraints: Thessaly, 6500–6000 BC; no metal, wheel-thrown precision, later tripod, modern cookware or fantasy design.
Invariants: no reframing, restyling, relighting, new objects, anatomy changes or edits elsewhere.
Avoid: text, numbers, labels, arrows, circles, interface, symbols, watermark, metal, jewellery, duplicate vessel, altered people, altered grain, altered architecture, blur padding or crop changes. This is a surgical material correction, not a new scene.
```

## Candidate v15 — material-directed full-resolution reconstruction

- File: `production-master-candidate-v15.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `4923340`
- SHA-256: `86c84c2aa1353b1ed6a60ff12b53c16131383ee34791b6c1068d2d0a9dba9277`
- Parent: candidate v14,
  `ec6ade20ff8343051521c4c9f40c4dd9ef5900ec12c81e90ea925619ebdb1fc0`
- Tool/model: unquantised `mflux-local` `0.18.0` /
  `flux2-klein-4b` snapshot
  `e7b7dc27f91deacad38e78976d1f2b499d76a294`
- Seed: `21076504`
- Image strength: `0.875`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Requested steps/guidance: `8` / `1.0`; the strength schedule executed one
  denoising step
- Prompt: exact bytes in `flux2-v15-material-reconstruction-prompt.txt`
- Machine result: `SANITY_PASS`; luma range `139`, mean `54.147`, standard
  deviation `20.242`; peak MLX memory `54.96 GB`
- Result: `REJECTED_MATERIAL_AND_PERIOD_REVIEW`
- Reason: higher source influence preserves geometry but does not resolve the
  material defects. The hearth vessel again reads as metal, the mound reads as
  pulses, and smoothed houses and people remain generic and later-looking.
  This establishes that another pass through the same Klein image-to-image
  route is not a justified next step.

### Exact local command

```sh
mflux-generate-flux2 \
  --model flux2-klein-4b \
  --low-ram --mlx-cache-limit-gb 8 \
  --image-path production-master-candidate-v14-hearth-edit.png \
  --image-strength 0.875 \
  --prompt-file flux2-v15-material-reconstruction-prompt.txt \
  --width 1296 --height 2800 --steps 8 --guidance 1.0 \
  --seed 21076504 --metadata \
  --output production-master-candidate-v15.png
```

## Candidate v16 — Z-Image Turbo reconstruction diagnostic

- File: `production-master-candidate-v16-z-image-turbo-diagnostic.png`
- Dimensions: `512 × 1024 px`
- Bytes: `892799`
- SHA-256: `4b3285ad09e63dc02dab20754b07b8d15a225ead233b32d5dd0ee9d4b6a24d90`
- Parent: candidate v10,
  `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Tool/model: unquantised `mflux-local` `0.18.0` /
  `Tongyi-MAI/Z-Image-Turbo` revision
  `f332072aa78be7aecdf3ee76d5c247082da564a6`
- Seed: `21076516`
- Image strength: `0.70`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Steps: `9`; model guidance: none
- Prompt: exact bytes in `z-image-turbo-diagnostic-prompt.txt`
- Machine result: tonal sanity pass; peak MLX memory `30.21 GB`;
  generation time after load `16.75 s`; dimensions intentionally below the
  production floor
- Result: `REJECTED_COMPOSITION_DRIFT`
- Reason: the route improves grain scale, fired-clay reading and surface
  realism but replaces people, poses and tools, removes the child, changes the
  centre reserve and weakens the three simultaneous destinations. It is a new
  interpretation rather than a faithful reconstruction.

```sh
mflux-generate-z-image-turbo \
  --model z-image-turbo \
  --low-ram --mlx-cache-limit-gb 8 \
  --image-path production-master-candidate-v10-grain-edit.png \
  --image-strength 0.70 \
  --prompt-file z-image-turbo-diagnostic-prompt.txt \
  --width 512 --height 1024 --steps 9 \
  --seed 21076516 --metadata \
  --output production-master-candidate-v16-z-image-turbo-diagnostic.png
```

## Candidate v18 — Z-Image Turbo preservation diagnostic

- File: `production-master-candidate-v18-z-image-turbo-preservation-diagnostic.png`
- Dimensions: `512 × 1024 px`
- Bytes: `889460`
- SHA-256: `c88e6ca979e84ea90049ad77e1e3fe183d6e38ed30f71d647c249d0426f3a857`
- Parent, model, prompt, seed, steps and memory mode: identical to v16
- Image strength: `0.875`
- Machine result: tonal sanity pass; peak MLX memory `30.21 GB`;
  generation time after load `9.27 s`; dimensions intentionally below the
  production floor
- Result: `REJECTED_MATERIAL_AND_IDENTITY_DRIFT`
- Reason: stronger conditioning keeps the broad camera, roof, finite mound and
  three-zone layout, but still redraws faces, hands, object contact and distant
  people. The bright smooth hearth bowl remains materially ambiguous and can
  still read as metal. The route did not earn a full-resolution render.

The model rights, locked revisions, local feasibility and weight hashes for
these diagnostics are recorded in
`local-model-route-investigation.md`. Neither image is a production master,
source layer or approved reconstruction.

## Candidate v17 — Qwen coupled-material edit diagnostic

- File: `production-master-candidate-v17-qwen-edit-2509-diagnostic.png`
- Dimensions: `512 × 1024 px`
- Bytes: `768043`
- SHA-256: `b7bdfc49117e104b0775e3cc68ca44909834dc4521938ebe9696f6095be954af`
- Parent: candidate v14,
  `ec6ade20ff8343051521c4c9f40c4dd9ef5900ec12c81e90ea925619ebdb1fc0`
- Tool/model: eight-bit `mflux-local` `0.18.0` /
  `Qwen/Qwen-Image-Edit-2509` revision
  `d3968ef930e841f4c73640fb8afa3b306a78167e`
- Seed: `21076517`
- Steps/requested guidance: `20` / `2.5`; the MFLUX metadata sidecar records
  guidance as JSON `null`, so the exact command below is authoritative
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Prompt: exact bytes in `qwen-edit-2509-diagnostic-prompt.txt`
- Machine result: tonal sanity pass; peak MLX memory `38.36 GB`;
  generation time after load `185.19 s`; dimensions intentionally below the
  production floor
- Result: `REJECTED_GLOBAL_REDRAW`
- Reason: cereal scale improves and the broad arrangement survives, but the
  model redraws every person, hand, tool, vessel, building and field, softens
  material detail and leaves the hearth vessel materially unresolved. It does
  not perform the requested two-region correction.

```sh
mflux-generate-qwen-edit \
  --quantize 8 \
  --low-ram --mlx-cache-limit-gb 8 \
  --image-paths production-master-candidate-v14-hearth-edit.png \
  --prompt-file qwen-edit-2509-diagnostic-prompt.txt \
  --width 512 --height 1024 --steps 20 --guidance 2.5 \
  --seed 21076517 --metadata \
  --output production-master-candidate-v17-qwen-edit-2509-diagnostic.png
```

## Candidate v19 — Qwen hearth-only preservation diagnostic

- File: `production-master-candidate-v19-qwen-edit-2509-hearth-only-diagnostic.png`
- Dimensions: `480 × 1024 px`
- Bytes: `742444`
- SHA-256: `ab565544258b40dd3c85b9fa327789b9c178d49a16b4983a1366eabf32fed64d`
- Parent: candidate v10,
  `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Tool/model and revision: identical to v17
- Seed: `21076519`
- Steps/requested guidance: `30` / `2.5`; the MFLUX metadata sidecar again
  records guidance as JSON `null`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Prompt: exact bytes in
  `qwen-edit-2509-hearth-only-diagnostic-prompt.txt`
- Machine result: tonal sanity pass; peak MLX memory `38.34 GB`;
  generation time after load `287.46 s`; dimensions intentionally below the
  production floor
- Result: `REJECTED_UNREQUESTED_OBJECT_AND_GLOBAL_REDRAW`
- Reason: instead of replacing the small hearth vessel in place, Qwen adds a
  dominant red clay jar in the left foreground on top of a basket and redraws
  the complete scene. It violates the single-region instruction and does not
  earn a full-resolution render.

```sh
mflux-generate-qwen-edit \
  --quantize 8 \
  --low-ram --mlx-cache-limit-gb 8 \
  --image-paths production-master-candidate-v10-grain-edit.png \
  --prompt-file qwen-edit-2509-hearth-only-diagnostic-prompt.txt \
  --width 480 --height 1024 --steps 30 --guidance 2.5 \
  --seed 21076519 --metadata \
  --output production-master-candidate-v19-qwen-edit-2509-hearth-only-diagnostic.png
```

Candidates v17 and v19 remain diagnostic failure records. They cannot be used
as production masters, visual parents, source layers or correction references.

## Candidate v20 — Qwen 2511 zero-timestep preservation diagnostic

- File:
  `production-master-candidate-v20-qwen-edit-2511-hearth-only-diagnostic.png`
- Dimensions: `480 × 1024 px`
- Bytes: `703116`
- SHA-256: `3786ca77ddaad47dd3cc820ce2677b966acc4a62bd6d12f2c00964231326aea6`
- Parent: candidate v10,
  `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Tool/model: eight-bit isolated MFLUX source commit
  `48e5ae662c003db697af733f677885739483ff28` /
  `Qwen/Qwen-Image-Edit-2511` revision
  `6f3ccc0b56e431dc6a0c2b2039706d7d26f22cb9`
- Runtime correction: official-reference `zero_cond_t` semantics implemented
  by `mflux-0.18.0-qwen-edit-2511-zero-cond.patch`, SHA-256
  `c4dda7d79aeabe2ec09452b2dc17696ac9daba00f23a591ad48745c525ffe1b7`
- Seed: `21076520`
- Steps/requested guidance: `40` / `4.0`; negative prompt is one space
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Prompt: exact bytes in
  `qwen-edit-2511-hearth-only-diagnostic-prompt.txt`, SHA-256
  `56b8d5161de705e0887afe55ef6f718f5ad8a13d409ba9f09cdfde7f24f91d04`
- Machine result: tonal sanity pass; peak MLX memory `38.49 GB`;
  dimensions intentionally below the production floor
- Preservation support against v10: luma correlation `0.65158`,
  edge-magnitude correlation `0.27973`, `481` ORB ratio-test matches and
  `429` homography inliers
- Comparison with v19: luma `0.56710`, edge `0.25699`, `336` ORB matches and
  `262` homography inliers; 2511 is structurally closer but remains far below
  local-edit fidelity
- Sidecar limitation: stock metadata labels the model as
  `Qwen/Qwen-Image-Edit-2509` and guidance as JSON `null`; the locked model
  assembly, patch and command below are authoritative
- Result: `REJECTED_UNREQUESTED_OBJECT_AND_GLOBAL_REDRAW`
- Reason: the model again creates a dominant foreground clay jar instead of
  replacing the small hearth vessel in place. It leaves the hearth unresolved
  and redraws the canopy, every person, tools, storage, buildings, field and
  distant activity. Better structural correlation does not make it a precise
  edit, and no full-resolution render is justified.

```sh
PYTHONPATH=/tmp/eurocentric-mflux-2511.yZTLiz/mflux/src \
  /Users/bard/.local/share/uv/tools/mflux/bin/python \
  -m mflux.models.qwen.cli.qwen_image_edit_generate \
  --model /tmp/eurocentric-mflux-2511.yZTLiz/qwen2511-model \
  --zero-cond-t \
  --quantize 8 \
  --low-ram --mlx-cache-limit-gb 8 \
  --image-paths native/design/phase1/harvest/production-master-candidate-v10-grain-edit.png \
  --prompt-file native/design/phase1/harvest/qwen-edit-2511-hearth-only-diagnostic-prompt.txt \
  --negative-prompt ' ' \
  --width 480 --height 1024 --steps 40 --guidance 4.0 \
  --seed 21076520 --metadata \
  --output native/design/phase1/harvest/production-master-candidate-v20-qwen-edit-2511-hearth-only-diagnostic.png
```

Candidate v20 remains a diagnostic failure record. It cannot be used as a
production master, visual parent, source layer or correction reference.

## Candidate v21 — built-in hearth-only edit

- File: `production-master-candidate-v21-hearth-edit.png`
- Dimensions: `853 × 1844 px`
- Bytes: `2431086`
- SHA-256: `7976863cd01f61badb287d5af985961987b1acdf2365de5faefb4983f9cc87f6`
- Parent: candidate v10,
  `01b60b1627fa125a0b37c606eb8a3113820d9494b539b4f5a7c2d655b0f62080`
- Tool: Codex built-in image edit; the interface exposes neither model
  version nor seed, so the exact output bytes and prompt are the reproducible
  authority.
- Prompt: `openai-v21-hearth-only-edit-prompt.txt`, SHA-256
  `1e6878429578f9295e0bdb1e6cc9694e73078527c3fb1107db28a826a5103e71`
- Requested-region result: the black cauldron becomes a low, handleless,
  soot-darkened fired-clay pot seated at the existing hearth.
- Direct-edit result: `REJECTED_GLOBAL_PIXEL_DRIFT`. Against v10 the complete
  image measures PSNR `30.333025 dB` and SSIM `0.852345`; the tool redrew
  pixels well outside the authorised object despite preserving the apparent
  composition. The full output cannot become a parent or master.

Candidate v21 is retained only as a byte-bound local material source for the
masked composite below.

## Candidate v22 — deterministic hearth-local composite

- File: `production-master-candidate-v22-hearth-local-composite.png`
- Dimensions: `853 × 1844 px`
- Bytes: `2432058`
- SHA-256: `11dc4dd55d7fe25341de1962af625834ffd5b153090c0f6fe9ce1a3227918d66`
- Parent: candidate v10; local source: candidate v21.
- Authorised mask:
  `production-master-candidate-v22-hearth-local-mask.png`, SHA-256
  `113dd952717af5384ba7387bed06e228dfe6bf3927a40826a10ef728139ad574`.
- Compositor: planar-RGB FFmpeg `maskedmerge`, with a feathered ellipse around
  the hearth vessel only.
- Isolation proof: raw-frame SHA-256 values match the parent above, below,
  left and right of the authorised `136 × 100 px` bounding rectangle. The
  complete composite measures PSNR `39.417161 dB` and SSIM `0.998102` against
  v10 because all effective change is confined to the pot.
- Result: `NON_SHIPPING_LOCAL_CORRECTION_REFERENCE`. The vessel and existing
  grain morphology now pass the two material corrections simultaneously,
  without changing the selected composition or people.
- Production-master result: `REJECT_BELOW_DIMENSION_FLOOR`. These bytes remain
  `853 × 1844`, below the required `1290 × 2796`; they cannot be enlarged or
  treated as final pixels.

Candidate v22 proves the crop-local imagegen plus deterministic-compositing
route. The next legitimate master must reproduce this exact pot, grain,
shelter and three-destination logic natively at production resolution.

## Candidate v23 — full-resolution hearth-local composite

- File: `production-master-candidate-v23-hearth-local-composite.png`
- Dimensions: `1296 × 2800 px`
- Bytes: `5835222`
- SHA-256: `c2f71d113775dce78b2bfcae8486a84e5872e829a8d346b891c6b918ac0d4596`
- Parent: full-resolution candidate v11,
  `3d133537912cea7a08d03a8dd4875e145e05df4d765c4c1dcd4701c949dec278`
- Input: a byte-bound `440 × 440` crop at `(0,1390)`, enlarged to
  `880 × 880` only for the local edit.
- Tool: Codex built-in image edit. The interface exposes no model version or
  seed, so the exact prompt, input and output bytes are the authority.
- Prompt: `openai-v23-hearth-crop-edit-prompt.txt`, SHA-256
  `5b63dca75ab288e6bc6c8cba0844b9a56305532b620c77f99917746bf8ead625`.
- Local source: `production-master-candidate-v23-hearth-crop-edit-source.png`,
  SHA-256
  `001378dba16f4d9a1dff994e6b82aeed7fb9894e92c7ab0d98b11a47e54b20ec`.
  The complete generated crop is rejected as a redraw and retained only for
  the clay-vessel pixels.
- Authorised mask:
  `production-master-candidate-v23-hearth-local-mask.png`, with the exact
  non-zero rectangle `(30,1651,161,125)` in the full-resolution parent.
- Isolation proof: raw-frame SHA-256 values match the parent above, below,
  left and right of that rectangle. The complete composite measures PSNR
  `43.335140 dB` and SSIM `0.998535` against v11.
- Material result: `PASS_PROVISIONAL_LOCAL_CORRECTION`. The unsupported metal
  cauldron is now a handleless, soot-darkened, hand-built fired-clay vessel.
- Result: `NON_SHIPPING_FULL_RESOLUTION_LOCAL_CORRECTION_CANDIDATE`. The image
  clears the `1290 × 2796` dimension floor. It does not become a production
  master until the complete layered asset DAG, runtime variants, final
  artefact inspection and artistic gate exist.

## Candidate v24 — exact SceneSpec canvas

- File: `production-master-candidate-v24-canvas-normalized.png`
- Dimensions: `1290 × 2796 px`
- Bytes: `5805477`
- SHA-256: `bfc3ea276fa2d63857381e31845d25716dc7c71b82cf38afd734a021dff8b7c1`
- Parent: candidate v23.
- Transform: crop three pixels from each horizontal edge and two pixels from
  each vertical edge. There is no resampling or upscaling.
- Pixel proof: the parent crop and v24 decode to the same raw-frame SHA-256,
  `03dd3a1f45e20ad09b5d19cb8b421c39a35c25df2e74a0b4bb7aa5978061ab5f`.
- Result: `NON_SHIPPING_CANVAS_NORMALIZED_PRODUCTION_CANDIDATE`. The candidate
  now matches the Harvest SceneSpec canvas exactly. It still grants no
  production-master or 86-file layer-DAG authority before the artistic gate.

## Candidate v25 — exact-canvas cereal correction

- File: `production-master-candidate-v25-grain-local-composite.png`
- Dimensions: `1290 × 2796 px`
- Bytes: `5879816`
- SHA-256: `5ddcef3511e0b29dd0ace635a26135290bcf50402531b7d55b60e30422873762`
- Parent: exact-canvas candidate v24.
- Input: exact `900 × 900` parent crop at `(190,1750)`.
- Tool: Codex built-in image edit; exact prompt, input and generated bytes are
  retained because the interface exposes no model version or seed.
- Prompt: `openai-v25-grain-crop-edit-prompt.txt`, SHA-256
  `bdb7061563456c14ca5dc31034f3a43e61439c32e1d8459b020f0f95b062dcc3`.
- Local source: `production-master-candidate-v25-grain-crop-edit-source.png`,
  SHA-256
  `4ee2f086008b03526f4afe38717ca1cb1cd97f4e78fa71727968ea89b310cd23`.
  The complete generated crop is rejected as a redraw and retained only for
  the finite grain-mound pixels.
- Authorised mask: `production-master-candidate-v25-grain-local-mask.png`,
  with exact non-zero rectangle `(260,2120,791,551)`.
- Isolation proof: raw-frame SHA-256 values match v24 above, below, left and
  right of the authorised rectangle. Complete-image PSNR is `33.083717 dB`;
  SSIM is `0.959403` because the intentionally corrected mound is large.
- Material result: `PASS_PROVISIONAL_CEREAL_SCALE_AND_MORPHOLOGY`. The mound
  reads as thousands of small hulled cereal kernels with chaff instead of
  oversized bean-like pieces.
- Result: `NON_SHIPPING_EXACT_CANVAS_MATERIAL_CORRECTION_CANDIDATE`. It grants
  no production-master or 86-file layer-DAG authority before the artistic
  gate.

## Candidate v26 — exact-canvas garment correction

- File: `production-master-candidate-v26-garments-local-composite.png`
- Dimensions: `1290 × 2796 px`
- Bytes: `5860864`
- SHA-256: `e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca`
- Parent: exact-canvas candidate v25.
- Input: exact `1290 × 1290` parent crop at `(0,1000)`.
- Tool: Codex built-in image edit; exact prompt, input and generated bytes are
  retained because the interface exposes no model version or seed.
- Prompt: `openai-v26-garments-crop-edit-prompt.txt`, SHA-256
  `93f4c66932215391e2cc13976710ed095d7b6c7910589c0d1bf9c77f500896cf`.
- Local source:
  `production-master-candidate-v26-garments-crop-edit-source.png`, SHA-256
  `1269d182ef1c60da5051167f4b43a13110864913f6fcefa22877b5e4bc01754a`.
  The complete generated crop is rejected as a redraw and retained only for
  clothing pixels inside five authored masks.
- Authorised mask:
  `production-master-candidate-v26-garments-local-mask.png`, derived from the
  retained SVG mask and feathered at sigma `4`.
- Isolation proof: complete decoded raw-frame hashes match v25 above the edited
  people region, below it and along the untouched left edge. Complete-image
  PSNR is `35.609663 dB`; SSIM is `0.978717`.
- Material result: `PASS_PROVISIONAL_F5_MODERN_GARMENT_CUE_REMOVAL`. The modern
  button placket, knitted-shirt surfaces and factory-cut neck/sleeve cues have
  been replaced with irregular undyed woven wraps and tunics.
- Result: `NON_SHIPPING_LOCAL_HISTORICAL_GARMENT_CORRECTION_CANDIDATE`. It
  grants no production-master or 86-file layer-DAG authority before the
  artistic gate.
