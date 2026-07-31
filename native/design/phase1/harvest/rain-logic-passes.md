# Harvest rain-logic production passes

Status: backstage image-production record. Both images were created with the
built-in Image Generation tool on 23 July 2026. Neither is a production master,
layer source, provenance-approved asset or shipping content.

The edit target for both passes was the byte-locked
`reconstruction-master-draft-v2.png`. The editor's approval of that target fixes
composition and anatomy. It does not transfer to either derivative.

| Pass | Pixels | SHA-256 | Decision |
|---|---:|---|---|
| `rain-logic-pass-v1-rejected.png` | `862 × 1825` | `ce2e6c005a651b8e95c00f94a62965cd546a63d427fee0e400ec49f4713b286c` | Rejected: the overhead roof displaced too much of the approved storm field and changed the reading order. |
| `rain-logic-pass-v2.png` | `862 × 1825` | `8d547126cf3601d3bfa1a9a9d7b5becbb90ac067099c2ce76f4aec8a40d0ffbb` | Current non-shipping production-source pass: narrow roof edge, retained storm field and dry foreground reading. |

Pass v2 is still below the required `1290 × 2796 px` master, has no finished
overscan, plates, layers, masks or state variants and remains outside the native
asset provenance registry.

## Pass v1 prompt

```text
Use case: precise-object-edit
Asset type: non-shipping production-source pass for a portrait native iPhone 2.5D historical scene.
Input image: Image 1 is the editor-approved composition and anatomy target and the edit target.
Primary request: change only the physical rain protection around the foreground harvest. Extend the existing large thatched roof/eave from the upper-left foreground far enough across the work area that the central foreground grain mound, its coarse woven cloth, the empty receiving baskets, and the working hands are clearly under a dry shelter. Remove rain streaks, wet sheen, puddling, and runoff only from the sheltered foreground work area. Rain remains active and visible in the open settlement, sky, fields, distant roofs, and exposed middle ground.
Invariants: preserve the exact tall portrait framing, camera viewpoint, full composition, depth hierarchy, settlement plan, mountains, storm sky, every person and animal, all architecture outside the eave extension, the left hearth activity, the open empty mud-plastered reserve bin, every empty basket and vessel, and the one large central foreground grain mound as the sole visible grain source. Preserve positions, scale, posture, object silhouettes, sightlines, lighting direction, and restrained dark documentary palette. The shelter must feel structurally connected to the existing Early Neolithic mud-and-timber dwelling, with plausible timber support and reed/thatch construction, not a new building or isolated canopy. Keep the visual path between the grain and all three material destinations unobstructed.
Historical constraints: Early Neolithic Thessaly, 6500–6000 BC. Rectangular mudbrick or wattle-and-daub dwellings, reed/thatch roofs, hand-shaped pottery, woven baskets, stone/bone tools, simple woven garments, cattle, sheep and goats. No horses, carts, wheels, metal, writing, masonry, later Greek dress, fantasy forms, or modern objects.
Rendering: exceptionally realistic cinematic historical reconstruction, tactile documentary naturalism, physically coherent perspective and motivated light. Correct anatomy, hands, joinery, basket weave, grain, cloth and roof construction. Preserve clear object separation for later layer extraction.
Text: none.
Avoid: any baked title, label, numeral, arrow, path, circle, target ring, icon, panel, UI chrome, border, watermark, signature, magical glow, duplicated figure, malformed hand, fused object, new grain outside the central mound, filled destination container, green shoots, or enlarged/cropped framing.
```

## Pass v2 prompt

```text
Use case: precise-object-edit
Asset type: non-shipping production-source pass for a portrait native iPhone 2.5D historical scene.
Input image: Image 1 is the editor-approved composition and anatomy target and the edit target.
Primary request: change only the foreground rain logic. Preserve the existing left dwelling and its roof. Extend its eave subtly toward the camera as an off-frame shelter so that only a narrow, believable dark edge/underside of reed thatch is visible along the extreme upper-left and upper edge, occupying no more than the top 12 percent of the full frame and never crossing the central storm opening. Add at most two slim, period-plausible timber supports at the far side edges if structurally needed. The large central foreground grain mound, woven cloth, empty baskets, and working hands are visibly dry beneath this overhead shelter: remove rain streaks, wet sheen, runoff, and puddling only from that foreground work zone. Rain remains active in the open settlement, sky, fields, distant roofs, exposed people, and middle ground.
Critical framing invariants: retain at least the original top 20 percent as a broad readable storm-sky field; preserve the exact tall portrait crop, camera viewpoint, horizon height, mountains, settlement scale and placement, all people and animals, the three destination areas, the open empty reserve bin, the one central grain source, every empty receiving container, and the complete foreground mound. Do not create a new canopy, roof mass, building, wall, crossbeam, or enclosure over the middle of the image. Do not obscure the storm, settlement, destination triangle, central sightline, or any figure. Keep the roof change subordinate to the existing composition.
Other invariants: preserve positions, scale, posture, silhouettes, lighting direction, restrained dark documentary palette, left hearth activity, continuous ground routes, and one and only one visible grain source. No grain in any other basket, bowl, pot, hand, or bin.
Historical constraints: Early Neolithic Thessaly, 6500–6000 BC; mudbrick or wattle-and-daub dwellings; reed/thatch roofing; hand-shaped pottery; woven baskets; stone and bone tools; simple woven garments; cattle, sheep and goats. No horses, carts, wheels, metal, writing, masonry, later Greek dress, fantasy forms, or modern objects.
Rendering: exceptionally realistic cinematic historical reconstruction, tactile documentary naturalism, physically coherent perspective and motivated light. Correct anatomy, hands, joinery, basket weave, grain, cloth and roof construction. Preserve clean object separation for later layer extraction.
Text: none.
Avoid: baked title, label, numeral, arrow, path, circle, target ring, icon, panel, interface chrome, border, watermark, signature, magical glow, duplicated figure, malformed hand, fused object, green shoots, additional grain, filled destination container, enlarged roof, reduced sky, changed horizon, changed crop, or shifted composition.
```
