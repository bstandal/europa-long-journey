# Local image-model route investigation

Status: `BACKSTAGE_NON_SHIPPING`

This record evaluates zero-incremental-cost local routes for reconstructing the
editor-approved Harvest composition. It does not approve a model, image,
production master, layer, mask or derivative for shipping.

## Fixed evaluation target

- Composition authority:
  `reconstruction-master-draft-v2.png` and the later material corrections
  preserved in candidates v10 and v14.
- Native production floor: at least `1290 × 2796 px`; the tested native
  synthesis size is `1296 × 2800 px`.
- Pass conditions: preserve the one inhabited composition, sheltered dry grain
  floor, finite foreground grain, three simultaneous destinations, every
  person and pose, and the authored light direction; improve period material,
  anatomy and tactile realism; emit no UI or text.
- A low-resolution diagnostic can only reject or advance a route. It cannot
  become a production asset and cannot be enlarged into one.

## Rights and version lock

The source-of-truth revisions below were resolved through the official
Hugging Face model repositories on 24 July 2026. All execution is local after
the weights are downloaded. Hugging Face download and local inference add no
usage fee.

The local cache revision refs match the locked revisions. Sizes were checked
against the official API for all ten consumed Qwen 2509 weight shards, the
five new Qwen 2511 transformer shards and all seven consumed Z-Image weight
shards. Every local blob matches its declared byte count and is stored under
the official LFS SHA-256 identifier. The five Qwen 2511 transformer blobs were
also read back and SHA-256-verified locally after the diagnostic.

| Route | Official repository | Locked revision | Declared licence | Access on this machine |
|---|---|---|---|---|
| Qwen Image Edit 2509 | `Qwen/Qwen-Image-Edit-2509` | `d3968ef930e841f4c73640fb8afa3b306a78167e` | Apache-2.0 | Public, ungated |
| Qwen Image Edit 2511 | `Qwen/Qwen-Image-Edit-2511` | `6f3ccc0b56e431dc6a0c2b2039706d7d26f22cb9` | Apache-2.0 | Public, ungated; requires execution semantics absent from stock MFLUX 0.18.0 |
| Z-Image Turbo | `Tongyi-MAI/Z-Image-Turbo` | `f332072aa78be7aecdf3ee76d5c247082da564a6` | Apache-2.0 | Public, ungated |
| FLUX.1 Schnell | `black-forest-labs/FLUX.1-schnell` | `741f7c3ce8b383c54771c7003378a50191e9efe9` | Apache-2.0; the official card explicitly permits commercial use | Auto-gated; official files return HTTP 401 without a Hugging Face token |
| MFLUX runtime | PyPI `mflux==0.18.0` | wheel SHA-256 `a5357d99cfab0b1856721433dca9fdc38bcd3e7f223266bf414c48e0f7eebee5` | MIT | Installed locally |

Primary records:

- <https://huggingface.co/Qwen/Qwen-Image-Edit-2509/tree/d3968ef930e841f4c73640fb8afa3b306a78167e>
- <https://huggingface.co/Qwen/Qwen-Image-Edit-2511/tree/6f3ccc0b56e431dc6a0c2b2039706d7d26f22cb9>
- <https://huggingface.co/Tongyi-MAI/Z-Image-Turbo/tree/f332072aa78be7aecdf3ee76d5c247082da564a6>
- <https://huggingface.co/black-forest-labs/FLUX.1-schnell/tree/741f7c3ce8b383c54771c7003378a50191e9efe9>
- <https://pypi.org/project/mflux/0.18.0/>
- <https://github.com/huggingface/diffusers/pull/12839>
- <https://github.com/filipstrand/mflux/issues/298>

The model licence clears commercial local use; it does not replace the
project's separate provenance, historical, visual-artifact and editor approval
gates for generated pixels.

## Why each route is being tested

### Qwen Image Edit 2509

The official model is an image-editing checkpoint. Its card reports improved
single-image consistency and preservation of people and product identity. That
capability directly addresses the main Klein failure: a material correction
should not flatten or redesign the approved composition. MFLUX warns that Qwen
outputs are comparatively soft and that six-bit-or-lower quantisation can
degrade them substantially. The diagnostic therefore uses eight-bit
quantisation, a single target and one coupled material edit.

The official `Qwen/Qwen-Image-Edit-2511` checkpoint is not equivalent to 2509.
Its transformer sets `zero_cond_t: true`. The official Diffusers implementation
duplicates each diffusion timestep with a zero timestep, applies the live-time
modulation to generated tokens, applies zero-time modulation to reference-image
tokens, and keeps the live-time embedding for text and final normalisation.
Stock MFLUX 0.18.0 omits that execution path and still has an open upstream
support issue.

Candidate v20 therefore used an isolated clone of MFLUX source commit
`48e5ae662c003db697af733f677885739483ff28`, not a modified installation. The
minimal MLX patch is preserved byte-for-byte in
`mflux-0.18.0-qwen-edit-2511-zero-cond.patch`, SHA-256
`c4dda7d79aeabe2ec09452b2dc17696ac9daba00f23a591ad48745c525ffe1b7`.
It implements the official token-selective timestep modulation and exposes it
behind `--zero-cond-t`. A deterministic tensor test verified that generated and
reference token positions select their intended shift, scale and gate values.

Only the five changed 2511 transformer shards were downloaded. Its text
encoder weights and VAE are byte-identical to the already verified 2509
components at the locked official revisions, so the diagnostic reused those
local blobs through an isolated symlink assembly. The 2511 configuration,
tokenizer and transformer all came from the locked 2511 snapshot. This avoided
another copy of roughly 20 GB without substituting community weights.

### Z-Image Turbo

The official checkpoint is a six-billion-parameter text-to-image model focused
on photorealism, instruction adherence and eight model evaluations. MFLUX adds
an image-to-image route, but the official Turbo checkpoint is not the unreleased
Z-Image-Edit variant. The diagnostic therefore tests whether its realism gain
survives source conditioning; composition drift is an expected rejection risk.

### FLUX.1 Schnell

The official checkpoint is commercially cleared and MFLUX supports local
image-to-image generation, but it is a legacy text-to-image model rather than a
precise editing checkpoint. The official repository is gated on this machine.
No mirror or repackaged weights are substituted merely to bypass that trust
boundary. The route stays `ACCESS_NOT_PROVEN` until official access exists.

## Native-resolution feasibility

- MFLUX 0.18.0 passes explicit Z-Image width and height through unchanged;
  its latent grid uses each dimension divided by eight. `1296 × 2800` is
  exactly divisible by eight.
- MFLUX Qwen Edit floors explicit output dimensions to a multiple of sixteen.
  `1296 × 2800` is already exactly divisible by sixteen, so it is retained.
- Both routes can therefore synthesize new model pixels at the required size;
  neither requires a raster upscale to meet the dimensional floor.
- This establishes technical feasibility only. A route becomes legitimately
  usable for the production master only after a full-resolution native render
  preserves the composition and passes material, anatomy, crop, overscan,
  provenance and editor gates.

## Diagnostics

The preservation support metric is diagnostic only. It converts the source
and candidate to grayscale, Lanczos-resizes the source to the candidate raster,
and reports Pearson correlation for pixels and centred-difference gradient
magnitudes. Visual identity, anatomy and historical material review remain the
gate.

### Candidate v16 — Z-Image Turbo image-to-image

- Input: `production-master-candidate-v10-grain-edit.png`
- Prompt: exact bytes in `z-image-turbo-diagnostic-prompt.txt`
- Prompt SHA-256:
  `3f7764f76c45b0fe96232580410933c4efa603ee7ba283c86b4fa152613476ad`
- Requested output: `512 × 1024 px`
- Seed: `21076516`
- Quantisation: none
- Steps: `9`
- Image strength: `0.70`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Peak MLX memory: `30.21 GB`
- Generation time after load: `16.75 s`
- SHA-256:
  `4b3285ad09e63dc02dab20754b07b8d15a225ead233b32d5dd0ee9d4b6a24d90`
- Machine result: tonal sanity pass; expected dimensional rejection for a
  reduced diagnostic
- Source-preservation support metric after matching the source to the output
  raster: luma correlation `0.77582`, edge-magnitude correlation `0.39990`
- Status: `REJECTED_COMPOSITION_DRIFT`

The model materially improves grain scale, fired-clay reading and surface
realism. It also replaces people, poses and tools, removes the child, changes
the centre reserve into an oven-like structure, changes distant activity and
weakens the simultaneous three-destination mechanism. The image is a new
interpretation of the scene rather than a faithful reconstruction. It cannot
advance at this strength.

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

### Candidate v18 — Z-Image Turbo preservation diagnostic

Candidate v18 repeats v16 with the same source, prompt, seed, dimensions and
runtime, changing only image strength from `0.70` to `0.875`. It tests whether
the route can retain the approved bodies, objects and allocation mechanism
without losing the material gain.

- Output: `production-master-candidate-v18-z-image-turbo-preservation-diagnostic.png`
- Peak MLX memory: `30.21 GB`
- Generation time after load: `9.27 s`
- SHA-256:
  `c88e6ca979e84ea90049ad77e1e3fe183d6e38ed30f71d647c249d0426f3a857`
- Machine result: tonal sanity pass; expected dimensional rejection for a
  reduced diagnostic
- Source-preservation support metric after matching the source to the output
  raster: luma correlation `0.86071`, edge-magnitude correlation `0.52041`
- Status: `REJECTED_MATERIAL_AND_IDENTITY_DRIFT`

The higher source strength retains the broad camera, roof, finite mound and
three-zone layout substantially better than v16. It still redraws faces,
hands, the central worker's object contact and distant people; the hearth
vessel becomes a bright smooth bowl that remains materially ambiguous and can
still read as metal. The route does not satisfy the rule that a larger render
must be earned by simultaneous composition and material improvement. No
full-resolution Z-Image render is authorised from these diagnostics.

### Candidate v17 — Qwen Image Edit 2509

- Input: `production-master-candidate-v14-hearth-edit.png`
- Prompt: exact bytes in `qwen-edit-2509-diagnostic-prompt.txt`
- Prompt SHA-256:
  `80fca615ae6eced887f1dc832a4ef6596ec52e2a2e3c27c440bdc3a4f290ad66`
- Requested output: `512 × 1024 px`
- Seed: `21076517`
- Quantisation: `8-bit`
- Steps: `20`
- Guidance: `2.5`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Peak MLX memory: `38.36 GB`
- Generation time after load: `185.19 s`
- SHA-256:
  `b7bdfc49117e104b0775e3cc68ca44909834dc4521938ebe9696f6095be954af`
- Machine result: tonal sanity pass; expected dimensional rejection for a
  reduced diagnostic
- Source-preservation support metric after matching the source to the output
  raster: luma correlation `0.31279`, edge-magnitude correlation `0.11810`
- Metadata note: the MFLUX sidecar records guidance as JSON `null`; the exact
  command below is the authoritative requested value
- Status: `REJECTED_GLOBAL_REDRAW`

The output retains the broad roof, foreground mound, reserve and human layout,
and the cereal scale improves. It redraws every person, hand, tool, vessel,
building and field at once, softens material detail, changes the foreground
pottery and does not make the hearth vessel unmistakably hand-built clay. It
does not behave as the requested two-region material correction and cannot
advance to full resolution.

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

### Candidate v19 — Qwen hearth-only preservation diagnostic

The stricter Qwen diagnostic uses candidate v10, where the grain morphology
and composition are already the strongest retained reference, and asks for
only the remaining hearth-vessel correction. `480 × 1024` closely matches the
approved `1296 × 2800` aspect ratio while remaining a reduced diagnostic.

- Input: `production-master-candidate-v10-grain-edit.png`
- Prompt: exact bytes in
  `qwen-edit-2509-hearth-only-diagnostic-prompt.txt`
- Prompt SHA-256:
  `78124436cbcf553c9a748b96ecc4966aa0b3fe55217e4cf20f7025d68e4a1e1b`
- Requested output: `480 × 1024 px`
- Seed: `21076519`
- Quantisation: `8-bit`
- Steps: `30`
- Guidance: `2.5`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Peak MLX memory: `38.34 GB`
- Generation time after load: `287.46 s`
- SHA-256:
  `ab565544258b40dd3c85b9fa327789b9c178d49a16b4983a1366eabf32fed64d`
- Machine result: tonal sanity pass; expected dimensional rejection for a
  reduced diagnostic
- Source-preservation support metric after matching the source to the output
  raster: luma correlation `0.56710`, edge-magnitude correlation `0.25699`
- Metadata note: the MFLUX sidecar records guidance as JSON `null`; the exact
  command below is the authoritative requested value
- Status: `REJECTED_UNREQUESTED_OBJECT_AND_GLOBAL_REDRAW`

Instead of replacing the small hearth vessel in place, the model adds a giant
red clay jar in the left foreground on top of a basket and leaves the hearth
region unresolved. It also redraws the roof, every person, storage, settlement
and field despite the one-region instruction. The route fails precise editing
even under the strictest prompt and production aspect ratio. It cannot advance
to full resolution.

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

### Candidate v20 — Qwen Image Edit 2511 zero-timestep diagnostic

Candidate v20 repeats the one-object hearth test against candidate v10 with
the official 2511 checkpoint and its required reference-image zero-timestep
modulation. The prompt is shorter than v19 and follows the direct editing form
used by the official examples. The model was given forty steps and the
official example's classifier-free guidance scale of `4.0`.

- Input: `production-master-candidate-v10-grain-edit.png`
- Prompt: exact bytes in
  `qwen-edit-2511-hearth-only-diagnostic-prompt.txt`
- Prompt SHA-256:
  `56b8d5161de705e0887afe55ef6f718f5ad8a13d409ba9f09cdfde7f24f91d04`
- Requested output: `480 × 1024 px`
- Seed: `21076520`
- Quantisation: `8-bit`
- Steps: `40`
- Requested guidance: `4.0`; negative prompt: one space
- Runtime: isolated MFLUX source commit
  `48e5ae662c003db697af733f677885739483ff28` plus the recorded
  `zero_cond_t` patch
- Model: `Qwen/Qwen-Image-Edit-2511` at
  `6f3ccc0b56e431dc6a0c2b2039706d7d26f22cb9`
- Memory mode: `--low-ram --mlx-cache-limit-gb 8`
- Peak MLX memory: `38.49 GB`
- Recorded generation-loop time: `7527.88 s`; this run overlapped severe
  unified-memory contention, so it is not a model-speed benchmark
- SHA-256:
  `3786ca77ddaad47dd3cc820ce2677b966acc4a62bd6d12f2c00964231326aea6`
- Bytes: `703116`
- Machine result: tonal sanity pass; expected dimensional rejection for a
  reduced diagnostic
- Source-preservation support metric after matching v10 to the output raster:
  luma correlation `0.65158`, edge-magnitude correlation `0.27973`
- ORB support metric against v10: `481` ratio-test matches and `429`
  homography inliers; v19 produced `336` and `262` under the same analysis
- Status: `REJECTED_UNREQUESTED_OBJECT_AND_GLOBAL_REDRAW`

The 2511 execution path retains the source geometry more closely than v19:
v19's corresponding luma and edge correlations are `0.56710` and `0.25699`.
That improvement is insufficient. Candidate v20 again turns the requested
small replacement into a dominant new foreground clay jar, leaves the actual
hearth-vessel region unresolved, and redraws the canopy, every person, tools,
storage, buildings, field and distant activity. It is still a complete scene
reconstruction rather than a local material correction and cannot advance to
full resolution.

The generated MFLUX sidecar labels the model as
`Qwen/Qwen-Image-Edit-2509` and guidance as JSON `null` because those metadata
fields remain hard-coded in stock 0.18.0. The locked revision, model assembly,
patch and exact command below are authoritative; the unedited sidecar is kept
as evidence of the runtime limitation.

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

## Advancement rule

A route advances to a native `1296 × 2800` diagnostic only if the reduced
render retains the roof, rain boundary, finite source, three destinations,
people and camera while materially improving the clay hearth vessel, cereal
grain and human/animal anatomy. A route that produces generic illustration,
wet grain, metal, pulses, UI, duplicated anatomy or a rearranged settlement is
rejected without a larger render.

## Route decision

No tested local route proves a better Harvest reconstruction master than the
current Klein/built-in edit chain:

- Z-Image Turbo supplies stronger photoreal material but is a text-to-image
  checkpoint; its MFLUX image conditioning cannot retain the approved people,
  objects and mechanism.
- Qwen Image Edit 2509 is the correct model class but MFLUX 0.18.0 at eight-bit
  precision performs a global redraw for both the coupled and surgical edits.
  The single-region test introduces a dominant unrequested vessel.
- Qwen Image Edit 2511 with the official `zero_cond_t` semantics improves
  measurable structural retention over 2509, but the improvement is not close
  to local-edit fidelity. It repeats the dominant foreground-vessel failure
  and reconstructs every protected scene element.
- FLUX.1 Schnell is an older text-to-image route, and its official files are
  unavailable without the repository's access gate. There is no factual basis
  for expecting it to beat either failed precision test, and bypassing the
  official repository through a mirror would weaken provenance.

No full-resolution diagnostic is produced from these routes. The dimensional
feasibility remains proven, but the artistic and preservation prerequisite is
not. This is a production finding, not an editor approval request.

## Remaining zero-cost local routes

No further heavy render is justified from the tested checkpoints. The local
paths that remain technically credible are narrower:

- A commercially cleared edit or inpaint checkpoint with an explicit spatial
  mask and a Mac-native runtime. Mask enforcement would prevent protected
  scene regions from being resynthesised; stock MFLUX Qwen Edit exposes no
  such path.
- A crop-local edit diagnostic followed by deterministic masked compositing
  into candidate v10. This could isolate the hearth material problem, but it
  would test a compositing production method rather than prove that Qwen
  preserves the full composition. It should begin with a tiny diagnostic and
  only after its crop, feather and geometry contract is recorded.
- A future public Z-Image editing checkpoint or upstream MFLUX 2511 support,
  provided its official licence, revision and preservation behaviour pass the
  same reduced gate. The unsupported name alone is not a reason to download
  or render.
- Deterministic local reconstruction from retained pixels and generated
  material references. This avoids another global diffusion pass and is the
  strongest current no-cost production direction, but it is a separate visual
  assembly workflow and still requires artifact, anatomy and editor gates.

FLUX.1 Schnell remains gated and is a text-to-image checkpoint. Another
unmasked Z-Image Turbo, Qwen 2509 or Qwen 2511 scene-wide pass has no unresolved
question worth the memory and time cost.

## Cost-register additions required

Do not change `native/tooling/registries/cost-license.json` from this
investigation. A later register update must add the exact model repository,
revision, Apache-2.0 declaration, zero usage price, local-only execution,
download date and SHA-256 values for every consumed weight shard. It must also
retain the installed MFLUX 0.18.0 wheel hash, MIT licence, source commit,
isolated 2511 patch hash and the fact that stock 0.18.0 does not support 2511.

### Weight SHA-256 values for the register

`Tongyi-MAI/Z-Image-Turbo` at
`f332072aa78be7aecdf3ee76d5c247082da564a6`:

- text encoder:
  `328a91d3122359d5547f9d79521205bc0a46e1f79a792dfe650e99fc2d651223`,
  `6cd087b316306a68c562436b5492edbcf6e16c6dba3a1308279caa5a58e21ca5`,
  `7ca841ee75b9c61267c0c6148fd8d096d3d21b6d3e161256a9b878154f91fc52`
- transformer:
  `95facd593e2549e8252acb571c653d57f7ddb7f1060d4e81712f152555a88804`,
  `a4bbe43ee184a1fb5af4b412d27555f532893bdc3165b1149e304ed82b5d7015`,
  `aba4e37a590e63210878160a718d916d80398f4e1f78ab6c9b2b2a00d92769fa`
- VAE:
  `f5b59a26851551b67ae1fe58d32e76486e1e812def4696a4bea97f16604d40a3`

`Qwen/Qwen-Image-Edit-2509` at
`d3968ef930e841f4c73640fb8afa3b306a78167e`:

- text encoder:
  `d725335e4ea2399be706469e4b8807716a8fa64bd03468252e9f7acf2415fee4`,
  `b1830db6908dcc76df3a71492acbcf2b8cac130114cf1f3c2d9edae8de8c6de3`,
  `09c1807c6d00d7cab94f7db39d4c02ebb8537225ccde383861ac48db97945aa6`,
  `5dd068336d14d45ffb43cef374d286cc6ba9d8741b028f90a7d040d847961f4a`
- transformer:
  `784a8efc4dcea09ba20b534bbe9e5fae3367d929525031a4bd26c5ddb7eb18e5`,
  `86ce21e5e3bdecfbeaa31aa587c03d0d1af6ab05d79c127149e8217f81e0247f`,
  `c6a046daa991f3b32c3ae39ff95e6e7220455265fcbbb643e9f556bea8641d02`,
  `c28bf871d5db0a6397843eca3987e58ba2c3013d287d5d4a1271d68e158ce7e8`,
  `dd2844e5cafb03b16bed9556aa29c15396a787e17c38a0eda7f5a1281497c76a`
- VAE:
  `0c8bc8b758c649abef9ea407b95408389a3b2f610d0d10fcb054fe171d0a8344`

`Qwen/Qwen-Image-Edit-2511` at
`6f3ccc0b56e431dc6a0c2b2039706d7d26f22cb9`:

- transformer:
  `2a0c30c9ba44a5f11c21ca139e37951430bbde814ff4e0b5b1a68b80530e7a1a`,
  `54ec249b07b4376e19cf16b764054f03ca03ae2cfbd9939453e2085f4e9bd259`,
  `c55157843525653161e8f6af5acc670ba3aceff04284f7cf657199d24d065e16`,
  `ffcfb5a4895702635890a67bad183591e0ae515d794bdcb26e217b27a7f6d12d`,
  `2b2556b736629e10a5a0dfa14606f2057f4f81c2ba53f94103682c7ac42d4940`
- text encoder and VAE: byte-identical to the Qwen 2509 hashes listed above;
  the diagnostic reused those verified blobs rather than duplicating them
