# Harvest reconstruction master drafts

Status: backstage design material. Neither image is an approved native asset.
The editor-in-chief approved draft v2 as the composition-and-anatomy target on
23 July 2026. That decision is byte-locked in
[reconstruction-approval.json](./reconstruction-approval.json). It does not
approve the draft's pixels for layer extraction, a public package or the native
asset provenance registry.

| Draft | Role | Pixels | SHA-256 | Decision |
|---|---|---:|---|---|
| `reconstruction-master-draft-v1.png` | First corrected reconstruction | `863 × 1823` | `2e39b4be5351eb875a40300f540c4e3fc44f432a144bbda9a0a4a3ffd69a52d2` | Rejected for showing grain already distributed into destination containers. |
| `reconstruction-master-draft-v2.png` | Locked composition-and-anatomy target | `862 × 1824` | `602c730450d7abd99fa88e877c6b74e2e0e2ad8bfd79bc57b6c7a50fcdc059be` | `APPROVED_BY_EDITOR_IN_CHIEF`; shipping pixels remain prohibited. |

Both drafts were made with the built-in Image Generation tool on 23 July
2026. The selected option-1 image was used only as a composition reference.
The candidate is a new generated raster, not an enlargement or layer extraction
of that reference.

## Candidate anatomy

- One continuous Early Neolithic Thessalian settlement, with rectangular
  mud-and-timber dwellings and thatch.
- Winter preparation remains beside the household hearth on the left.
- A dry, open mud-plastered reserve bin occupies the centre-right.
- Empty receiving baskets and prepared ground establish spring seed on the
  right.
- The foreground mound is the only visible grain source before allocation.
- Cattle, sheep and goats replace the equids that appeared in the first raw
  generation.
- No title, label, numeral, path, ring or other interface mark is baked in.

The approved target remains below the `1290 × 2796 px` production-master requirement.
It has no clean plates, separated layers, disocclusion reconstruction, state
variants or masks. Foreground shelter, rain logic, every hand, vessel, animal,
material join and historical object still require full-resolution production
inspection. The approval locks its composition and anatomy; it does not make
its pixels shippable. Subsequent rain-logic work is recorded in
[rain-logic-passes.md](./rain-logic-passes.md).

## Prompt set

### New reconstruction

```text
Use case: historical-scene
Asset type: new portrait reconstruction master draft for a native iPhone 2.5D scene; Image 1 is a composition reference only, not an edit target and no pixels, text, symbols, or generated anatomy should be preserved.
Primary request: create a completely new, historically grounded scene of an Early Neolithic farming settlement in Thessaly, 6500–6000 BC, showing one finite cereal harvest that must serve winter food, protected reserve, and spring seed.
Composition/framing: very tall iPhone portrait, roughly 9:19.5. A restrained, slightly elevated human viewpoint looks down through one continuous inhabited settlement. Dark storm sky and clean atmospheric negative space in the top 20 percent; rectangular mudbrick and timber houses, thatch, fields, smoke, people at work and domesticated sheep/goats/cattle in the middle distance; three materially distinct but naturally connected uses of grain across the middle-lower scene; a large tactile mound of harvested emmer/einkorn grain on coarse woven cloth dominates the near foreground. Keep generous finished world at every edge for later camera movement. The visual triangle and depth hierarchy may echo Image 1, but rebuild every object and person from scratch.
Historical anatomy: Early Neolithic Thessaly only. Rectangular mudbrick or wattle-and-daub dwellings with reed/thatch roofs; hand-shaped pottery, woven baskets, stone and bone tools, simple woven garments, cereal processing by hand. No raised circular fantasy granary: protected reserve is a plausible dry, roofed, mud-plastered storage bin or sealed vessel arrangement. Winter food is shown through household storage and preparation near a restrained hearth. Spring seed is visibly separated in sound baskets or vessels beside prepared earth, without green shoots. No horses, carts, wheels, metal, writing, masonry, later Greek dress, medieval forms, or modern objects.
Human action: people work naturally throughout the settlement; hands and baskets in the foreground establish bodily scale. Correct hands, faces, posture, tool use and grain handling. No isolated game stations; the three destinations belong to one working place connected by worn earth, sightlines and human movement.
Lighting/mood: `Darkness frames the evidence`. Near-black cloud, earth, cloth and foreground objects frame readable midtones. People, timber, mud, fiber and grain retain detail. A narrow storm break and warm hearth give motivated light; the finite grain and the active storage mechanism are clearest, without magical glow. Fine rain remains legible against sky and roofs, but the stored grain is under bodily/cloth protection and does not appear soaked.
Style/medium: exceptionally realistic cinematic historical reconstruction, tactile documentary naturalism, restrained color, physically coherent perspective and light, no glossy fantasy concept-art finish.
Text: none.
Constraints: no baked title, labels, numerals, arrows, dotted paths, circles, target rings, icons, panels, interface chrome, borders, watermark, or signature. No duplicated people, malformed hands, fused baskets, impossible architecture, halos, cutout edges, or blurred padding. Preserve clear object separation and clean background areas suitable for later layer extraction, masks and foreground occlusion.
```

### Animal correction

```text
Change only the two equid-looking animals in the middle-distance settlement. Replace them with a small, anatomically correct Early Neolithic cattle pair that fits the same space and scale, while retaining the nearby sheep/goats and people. Preserve the exact composition and every element outside the animal edit. No horses, donkeys, carts, wheels, harnesses, metal, text, symbols, interface, watermark or new objects.
```

### Single finite source

```text
Establish one and only one visible finite grain source. Keep the large central foreground mound exactly as it is. Remove grain from every other basket, bowl, pot, hand and storage bin. Keep those containers physically present, empty, dry and ready to receive allocation. The mud-plastered reserve bin must have a visibly empty dry interior. Preserve the exact composition and all unrelated scene elements. No new grain outside the central mound; no text, symbols, paths, interface or new objects.
```
