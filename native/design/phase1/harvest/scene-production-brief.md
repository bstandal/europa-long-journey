# The Harvest Had to Last — scene production brief

## Status and authority

| Field | Value |
|---|---|
| Product | `The Long West: EUROCENTRIC` |
| Content | `first-farmers` |
| Arc | `first-farmers-arc-02` |
| Movement | `the-harvest-had-to-last` |
| Native interaction | `interaction-first-farmers-the-harvest-had-to-last` |
| Selected direction | Option 1 |
| Brief status | `NON_SHIPPING_PRODUCTION_BRIEF` |
| Shipping state | `PROHIBITED_UNTIL_REBUILT_AND_APPROVED` |

This brief translates the editor-in-chief's selected visual direction into a
reconstruction target for the Phase 1 laboratory. The byte-identified sources
of truth are [selection.json](./selection.json) and
[selected-direction.png](./selected-direction.png). Where this brief describes
an asset path, it reserves a future package location; it does not claim that
the asset exists or has passed review.

The selected image is a composition reference. It is not a plate to enlarge,
cut apart or ship. Its text, arrows, rings, people, tools, buildings, crops,
grain, weather and material joins all require reconstruction and inspection.
Only the editor-in-chief can approve the rebuilt scene.

[Reconstruction master draft v2](./reconstruction-master-draft-v2.png) is the
editor-approved composition-and-anatomy target. Its exact byte lock and approval
scope are in [reconstruction-approval.json](./reconstruction-approval.json), and
its complete prompt trail is in
[reconstruction-master-drafts.md](./reconstruction-master-drafts.md). It remains
backstage and below production resolution. The approval does not authorize its
pixels, any derivative or any future layer for the native asset registry.

[Rain-logic pass v2](./rain-logic-pass-v2.png) is the current non-shipping
production-source pass. It narrows the visible shelter to the extreme upper
edge, preserves the approved storm field and makes the foreground work zone
read as dry. It remains a generated working image at `862 × 1825 px`, not a
production master, layer source or approved asset. Its rejected predecessor,
hashes and prompts are recorded in
[rain-logic-passes.md](./rain-logic-passes.md).

## Historical action

One finite harvest fills the foreground. It must become winter food, protected
reserve and spring seed. Grain taken for one purpose cannot answer another.
The scene makes deferred use visible: present consumption is bound to scarcity
and to the field that must be sown next year.

The user acts on the grain itself. The result stays in the settlement. This is
an `Allocate` scene, not a resource-management panel and not a question with a
hidden answer. Exact destination requirements belong to the approved
`InteractionSpec`; neither the selected image nor `selection.json` fixes those
values. The established interaction divides the harvest into 12 equal
illustrative runtime shares. They are interaction units, not a historical unit
of weight, volume or household supply. Production must support the final
editor-approved 12-share split, but this brief does not approve the destination
requirements in the final `InteractionSpec`. The selected image's generated
`10 handfuls left` is rejected as text and quantity; it does not override the
existing 12-share contract. Final public counter wording requires separate
editorial approval.

The complete causal contract is:

`move grain -> material answers under the hand -> finite store visibly falls -> destination changes -> divided store persists`

## Locked composition

### Reading order

Coordinates below are normalized to the full portrait master, with `(0, 0)` at
the upper-left.

1. **Weather and time, `y 0.00–0.20`.** A dark storm sky gives the native title
   and short action prompt a quiet field. Rain is clearest against the left
   cloud break. The sky frames the scene; it must not become the brightest
   spectacle.
2. **The inhabited farming world, `y 0.16–0.50`.** Thessalian ground, fields,
   trees, dwellings, smoke, people, animals and work recede through continuous
   depth. This is an operating settlement rather than scenery behind a game.
3. **Three destinations, `y 0.49–0.68`.** Winter food sits left, protected
   reserve at the centre and spring seed right. Each is a physical activity and
   storage condition, not an empty ring. All three remain legible at once.
4. **The finite harvest, `y 0.65–0.96`.** Loose grain on coarse cloth dominates
   the near foreground. Its changing silhouette is the clearest statement of
   scarcity. Hands, baskets and cloth establish bodily scale without enclosing
   the grain in interface chrome.
5. **Near-black closure, `y 0.92–1.00` and both lower corners.** Cloth, baskets,
   forearms and earth close the frame. The darkness must retain weave, skin,
   grain and soil detail instead of crushing them to black.

The principal visual triangle runs from the harvest apex near `(0.50, 0.74)` to
the centres of the three destination areas near `(0.275, 0.585)`,
`(0.500, 0.585)` and `(0.725, 0.585)`. That relation is expressed by worn earth,
carried grain and human attention. No dashed line, arrowhead, target ring,
glowing track or diagrammatic overlay may remain in the rebuilt art.

### Destination anatomy

- **Winter food, left.** A household storage and preparation area connects the
  grain to a dry vessel, hearth and people who will eat through the cold
  season. The final state reads as provisioned through material quantity and
  continued work. It does not become a feast or a reward tableau.
- **Protected reserve, centre.** A dry, defensible store keeps a visibly
  separate share away from damp, pests, animals and immediate consumption. The
  final act is physical closure: lid, seal, lashing or secured opening. The
  current raised circular structure is only a silhouette reference and must be
  rebuilt as a storage practice defensible for the place and date.
- **Spring seed, right.** Selected grain is kept apart at the edge of prepared
  ground. The final state shows sound seed committed to the next sowing. It
  must not jump forward to green shoots or imply that allocation itself makes
  the crop grow.

The settlement is one continuous place behind these destinations. Structures
and people cannot be arranged as three isolated vignettes. Ground routes,
rainfall, smoke direction, perspective, light and activity must connect all
four depths.

## SceneSpec production contract

### Master, overscan and camera bounds

- Rebuild a new portrait master at `1290 × 2796 px`, in a wide-gamut working
  file with a documented final conversion. The `853 × 1844 px` selected image
  cannot be upscaled into the master.
- Author at least `0.16` usable overscan around the camera travel area. Overscan
  must contain finished world and complete objects, not generated padding or
  blurred edge extension.
- Set `cameraTravelBounds` to `{ x: 0.18, y: 0.13, width: 0.64, height: 0.74 }`.
- Keep all scene layers registered to the same master coordinate system. Do not
  compose independently generated layer images after the fact.
- Produce clean plates behind every separated person, hand, basket, building,
  destination and foreground occluder. Camera travel may never reveal a hole,
  clone patch or former subject silhouette.

The authored camera rail is a restrained descent into the mechanism:

| Progress | Centre | Scale | Editorial beat |
|---:|---:|---:|---|
| `0.00` | `(0.49, 0.47)` | `1.000` | Weather, settlement and the finite store are understood together. |
| `0.32` | `(0.50, 0.50)` | `1.025` | Attention settles on the three destinations. |
| `0.68` | `(0.50, 0.54)` | `1.055` | Grain and destination surfaces take priority. |
| `1.00` | `(0.50, 0.58)` | `1.080` | The camera holds for direct allocation. |

The rail never tracks a finger. Once direct manipulation begins, hold the final
camera anchor so that no target moves under the user's hand. Completion changes
the world in the held composition; it does not cut to a result card. Total
centre travel remains below twelve per cent and the largest parallax
displacement remains below 24 points in either authored viewport.

### Portrait crops and native text

`sourceRect` is normalized to the master. `safeTextRegions` is normalized to
the resulting viewport, as required by the SceneSpec API.

| Crop ID | Viewport | Master source rect | Native safe-text regions |
|---|---:|---:|---|
| `baseline-393x852` | `393 × 852 pt` | `{ x: .08, y: .08, width: .84, height: .84 }` | `chapter-heading { .07, .04, .86, .14 }`; `allocation-prompt { .18, .18, .64, .08 }`; `remaining-harvest { .33, .79, .34, .13 }` |
| `largest-430x932` | `430 × 932 pt` | `{ x: .05, y: .05, width: .90, height: .90 }` | the same three viewport-relative regions |

Crop approval requires side-by-side renders of both sizes in normal,
Increased Contrast and Reduce Motion configurations. The three destinations,
the complete harvest source area and each target polygon must remain inside
both crops.

All title, period, place, prompt, destination name, allocation status and
remaining-share text is native SwiftUI text. The master and every state asset
must be clean underneath it.

- `chapter-heading` holds the period/place line and movement title during
  orientation. It may recede when manipulation begins.
- `allocation-prompt` holds one short historical action. When a destination is
  focused, this region may carry its name and current consequence instead.
- `remaining-harvest` reports the finite source state and, once the full store
  has been placed, the historically named commit action. It must not cover the
  grain mound or become a floating glass panel.
- At standard sizes, concise destination names may be anchored above their
  physical objects. At accessibility text sizes, show the focused destination
  in `allocation-prompt` rather than squeezing three enlarged labels across the
  world. Never truncate the movement title or prompt.
- The objects must remain distinguishable without labels. Typography clarifies
  the action; it cannot rescue ambiguous production art.

### Ordered layer and mask inventory

The deterministic backstage production and provenance contract for this
inventory is defined in
[`layer-production-contract.json`](./layer-production-contract.json) and
[`layer-production-workflow.md`](./layer-production-workflow.md). It remains
blocked on an editor-approved P1.04 master and cannot grant shipping approval.

Future package root: `assets/phase1/harvest-option-1/`. Every path below is
reserved and non-shipping. Mask abbreviations are `A` alpha, `O` occlusion, `D`
depth and `L` light.

| Order | Layer ID | Normalized frame | Depth | Blend / opacity | Masks | Motion `(parallax, wind, focus)` | Production content |
|---:|---|---|---:|---|---|---|---|
| 0 | `storm-sky` | `{ 0, 0, 1, 1 }` | `.05` | normal / `1` | `D L` | `(.01, .18, 0)` | Storm body, cloud break and clean title field. No baked rain. |
| 1 | `farming-landscape` | `{ 0, 0, 1, 1 }` | `.14` | normal / `1` | `D` | `(.025, .08, 0)` | Hills, trees, hand-worked plots and continuous ground. |
| 2 | `settlement` | `{ .05, .17, .90, .45 }` | `.24` | normal / `1` | `A O D L` | `(.05, .10, .04)` | Dwellings, roofs, fences, hearth sources and defensible storage structures. |
| 3 | `people-and-work` | `{ .08, .27, .84, .38 }` | `.34` | normal / `1` | `A D` | `(.08, .05, .08)` | Distant people, animals and historically verified work. |
| 4 | `allocation-ground` | `{ .12, .46, .76, .27 }` | `.45` | normal / `1` | `A D` | `(.10, .04, .12)` | Worn earth connecting harvest and destinations; never an arrow graphic. |
| 5 | `winter-store` | `{ .17, .49, .24, .19 }` | `.60` | normal / `1` | `A D` | `(.12, 0, .50)` | Left destination and its three persistent states. Its hit geometry remains fixed. |
| 6 | `protected-reserve` | `{ .38, .49, .24, .19 }` | `.61` | normal / `1` | `A D` | `(.125, 0, .55)` | Centre destination and its three persistent states. Its hit geometry remains fixed. |
| 7 | `spring-seed` | `{ .59, .49, .24, .19 }` | `.62` | normal / `1` | `A D` | `(.13, 0, .60)` | Right destination and its three persistent states. Its hit geometry remains fixed. |
| 8 | `central-harvest` | `{ .19, .65, .62, .31 }` | `.78` | normal / `1` | `A D L` | `(.16, 0, .85)` | Finite grain mound, clean cloth and depletion states. Its alpha hit geometry remains fixed. |
| 9 | `hands-and-grain` | `{ 0, .68, 1, .32 }` | `.86` | normal / `1` | `A O D` | `(0, 0, .72)` | Correct hands, baskets, lifted grain and transfer occlusion. Direct response geometry controls its position. |
| 10 | `foreground-occluders` | `{ 0, 0, 1, 1 }` | `.94` | normal / `1` | `A O` | `(.20, .09, .18)` | Cloth edges, forearms, basket rims and near-ground closure. |
| 11 | `mechanism-light` | `{ 0, 0, 1, 1 }` | `.98` | screen / `.82` | `A L` | `(0, 0, 1)` | Materially bounded focus light on grain and the active destination. It may not draw a route, ring or halo. |

The base asset stems are
`layers/00-storm-sky.heif` through `layers/11-mechanism-light.heif` with
matching, uniquely named files under `masks/`. A layer receives only the masks
listed above. State variants carry their own alpha, depth and, where noted,
light masks; they must not reuse a base mask whose silhouette has changed.

### State-variant inventory

| Layer | Variant ID | Required image state | Variant masks |
|---|---|---|---|
| `winter-store` | `empty` | Dry destination is visibly available, with no allocated grain. | `A D` |
|  | `receiving` | Grain has arrived; vessel, hands or preparation surface physically answers in place. The image asserts arrival, not an exact historical volume. | `A D` |
|  | `provisioned` | Winter food is stored and active household work continues under restrained hearth light. | `A D L` |
| `protected-reserve` | `empty` | Separate, defensible storage is open and ready. | `A D` |
|  | `receiving` | Grain passes into the protected store; lid, basket or opening is still in use. | `A D` |
|  | `sealed` | The reserve is visibly closed, lashed or secured against use and damage. | `A D L` |
| `spring-seed` | `empty` | A distinct seed vessel or clean receiving surface is ready beside prepared ground. | `A D` |
|  | `receiving` | Selected grain is separated into that vessel; no future crop appears. | `A D` |
|  | `committed` | Seed is kept apart for sowing and remains materially distinct from food. | `A D L` |
| `central-harvest` | `full` | Full initial silhouette. | `A D L` |
|  | `reduced` | First unmistakable reduction in height and spread. | `A D L` |
|  | `scarce` | Cloth dominates; a small final quantity remains. | `A D L` |
|  | `exhausted` | Empty cloth, loose chaff and a few kernels only. | `A D` |

Initial variants are `full`, `empty`, `empty`, `empty`. Completion
variants are `exhausted`, `provisioned`, `sealed`, `committed`. These four final
changes occur together after the approved allocation is committed, and persist
in the resumed beat and in the resulting world effect.

The four harvest silhouettes mark global depletion thresholds rather than
pretending that a painted pile can show twelve exact quantities. Exact allocation
counts remain deterministic runtime state and accessible native text. Each
accepted unit still receives an immediate event-driven transfer response before
the next stable variant is selected.

### Runtime visual binding

The fixture's `interactionVisualBinding` binds this scene to
`interaction-first-farmers-the-harvest-had-to-last`. Runtime code derives the
four stateful layer variants from the matching `Allocate` reducer state; a view
or gesture handler cannot submit its own variant dictionary.

| Remaining shares | Central harvest variant |
|---:|---|
| `0` | `exhausted` |
| `1–4` | `scarce` |
| `5–8` | `reduced` |
| `9–12` | `full` |

Each destination remains `empty` at zero accepted shares, changes to
`receiving` after the first accepted share and reaches its named final variant
only when the reducer has accepted the complete allocation. A forged complete
state or total above twelve fails closed.

The Reduce Motion composition keeps an authored back-to-front order: a static
world underlay, the four selected causal state overlays in their normal layer
order, then a static foreground-occlusion plate. The foreground plate restores
cloth, forearms and basket rims above the changing grain and destinations. The
same depletion and destination consequence therefore remains visible without
camera, parallax or material travel, without flattening the causal objects over
their intended occluders.

## Direct Allocate interaction

### Stable target bindings

Hit polygons use master-normalized coordinates and bind to the physical object,
not to the generated rings in the reference.

| Interaction target | Layer | Polygon, clockwise | Accessibility element | Approximate target size in both crops |
|---|---|---|---|---:|
| `winter-food-target` | `winter-store` | `(.18,.50) (.37,.50) (.37,.67) (.18,.67)` | `allocate-winter-food` | `89 × 172 pt` |
| `protected-reserve-target` | `protected-reserve` | `(.405,.50) (.595,.50) (.595,.67) (.405,.67)` | `allocate-protected-reserve` | `89 × 172 pt` |
| `spring-seed-target` | `spring-seed` | `(.63,.50) (.82,.50) (.82,.67) (.63,.67)` | `allocate-spring-seed` | `89 × 172 pt` |

The horizontal gap between adjacent target bounds is approximately 16 points
in both crops. Production silhouettes must preserve that gap and may not put a
foreground person, label or particle emitter across it. Each polygon remains
wholly visible and exceeds `44 × 44 pt` in normal and Reduce Motion crops.

The `central-harvest` alpha silhouette is the direct source region. It is not a
fourth destination. Dragging begins on visible grain, not anywhere inside its
rectangular layer frame. Every selected harvest variant supplies its own alpha
mask; contact must pass the authored source polygon and that currently selected
alpha mask before direct manipulation begins.

The source polygon is
`(.27,.69) (.73,.69) (.79,.84) (.69,.875) (.31,.875) (.21,.84)`.
It deliberately covers the continuously visible upper grain rather than the
lowest cloth edge, which leaves the first camera anchor and the baseline crop.
The alpha mask narrows this geometric gate again for each depletion state.

Each transfer path is attached to rendered material rather than to a free
viewport overlay. Its first control point uses the `central-harvest` transform,
its interior control points use `hands-and-grain`, and its last point uses the
destination layer transform. All three attachment layers have zero wind
response. The complete path remains inside both crops throughout every camera
rail segment, and adjacent control points may not coincide.

### Gesture and response sequence

1. **Contact.** A touch on grain compresses the top surface locally, changes a
   few kernels and raises dry grain detail in the near sound field. The response
   occurs under the finger within one rendered frame.
2. **Lift.** One coherent share separates from the pile. Grain remains partly
   occluded by the authored hand and basket masks. The stable pile silhouette
   changes only after a transfer commits.
3. **Carry.** The lifted grain follows the finger over the existing worn ground.
   Loose chaff and a few kernels show direction. No line is drawn. Camera and
   target geometry remain fixed.
4. **Contact with a destination.** The object answers before release: a basket
   flexes, a cloth edge moves, an opening or lid responds, or a waiting hand
   shifts. `mechanism-light` raises only the touched material by a small amount.
5. **Accepted drop.** Grain lands with a destination-specific material sound,
   brief chaff and a restrained transfer haptic. Runtime records one whole unit,
   the destination enters `receiving`, and the central store advances to the
   correct depletion threshold.
6. **Revision.** Before final commit, a placed share can be carried back to the
   central cloth or to another destination. State, sound and pile silhouette
   reverse deterministically; there is no red error state.
7. **Commit.** When all twelve shares have left the central harvest, a native,
   historically named commit action replaces the remaining-share status. The
   exact wording and required split depend on the approved `InteractionSpec`.
   A failed commit gives material resistance at the relevant destination; it
   does not explain a hidden solution in a modal.
8. **Consequence.** The three final variants settle in place, the empty cloth
   remains foregrounded and the world effect establishes the divided seasonal
   store. There is no score burst, badge, confetti, victory text or reset.

A direct tap on one destination transfers one share from the central harvest
for users who do not drag. VoiceOver increment and decrement actions dispatch
the same allocation reducer, and its commit action reaches the same consequence.
No slider, card, allocation table or detached inventory appears in any input
mode.

Stable integer allocations are checkpointed after every accepted or reversed
share. Transient hand, chaff and contact-light animation is reconstructed from
that state after interruption and is never treated as historical state. A cold
resume must show the same pile threshold, destination variants, target counts,
camera anchor and paused audio position.

The versioned visual snapshot stores the scene identity and deterministic
atmosphere tick beside the existing chapter state. The frame-request factory
combines it with the persisted allocation, camera anchor and audio position; an
identical restored input must produce an identical frame plan. Every production
asset is resolved from an activated, signed package manifest and its size and
SHA-256 are rechecked immediately before decode.

## Atmosphere and light

### Deterministic atmosphere

| Kind | Scene source | SceneSpec values | Behaviour |
|---|---|---|---|
| `rain` | Storm front and cloud break above the settlement | density `.48`; velocity `(-.08, .72)`; seed `18423001` | Rain is most readable against sky, roofs and dark earth. It obeys roofs and occluders; it cannot fall inside storage or dwellings. Wetness accumulates through material response, not a full-frame filter. |
| `smoke` | Visible hearths and dwelling openings | density `.22`; velocity `(.06, -.12)`; seed `18423002` | Every plume begins at a visible source, drifts with the same wind and passes behind the correct roofs, people and trees. |

Wind is shown through thatch edges, trees, smoke, rain, clothing and loose chaff.
Those responses share one direction and intensity envelope. Transfer chaff is
an event bound to moved grain, not a permanently running global dust effect.
Settlement work is sparse, source-bound and asynchronous. No idle loop may draw
more attention than the finite store.

### Light hierarchy

1. A cool, broad cloud break from upper-left/back reveals rain, the settlement
   plane and wet earth without bleaching the sky.
2. Small warm hearth sources reveal hands, ceramic, basket weave, timber and
   doorway activity. Warm light remains local and physically occluded.
3. Plausible skylight and cloth bounce make the foreground grain the clearest
   material in the frame. It must look like grain, not a self-luminous gold
   prize.
4. The active destination receives a restrained, mask-bounded lift in exposure
   and local contrast. Inactive destinations remain readable together.
5. Completion redistributes emphasis across the three material consequences
   while the exhausted cloth stays visible. The sky never celebrates the
   allocation.

Near-black values frame the evidence. Readable midtones must retain hands,
faces, grain morphology, basket weave, timber joints, thatch, pottery, soil,
rain and smoke on the target iPhone display. Uniform underexposure, crushed
faces or a bright ornamental horizon fails the composition.

## Reduce Motion composition

Produce a separate full portrait plate at
`reduce-motion/harvest-allocation-static.heif`, registered to the same
`1290 × 2796` canvas and carrying the two normal crop definitions unchanged.
It is not a flattened export of one dynamic layer and may not share an asset
path with any normal layer or variant.

- Hold one fixed composition at the interaction camera anchor. Remove camera
  travel, parallax, continuous rain travel, smoke drift, hand-follow motion and
  streaming grain.
- Keep storm, smoke, rain marks and work poses in coherent static positions so
  the same weather and inhabited settlement remain legible.
- Preserve the three target polygons and the central source silhouette exactly.
- Transfer by direct tap or semantic action. Use a restrained cross-dissolve or
  discrete replacement between stable states, with no zoom, sweep or spatial
  displacement. Local material contrast may change briefly at the touched
  object.
- Show the same `empty -> receiving -> final` destination states and
  `full -> reduced -> scarce -> exhausted` source thresholds. Do not remove a causal
  change merely because its normal form used motion.
- Keep the same native text, Dynamic Type behaviour, Increased Contrast
  treatment, audio semantics, haptic meaning, save points and final world
  effect.
- Stop continuous decorative haptics. Retain one contact cue and one accepted
  transfer cue because they communicate action rather than movement.

## Sound and haptic source map

This is a source and dramatic-function map, not an approved `AudioTimeline`.
Every eventual cue needs an authored asset, sample position, gain, offline
package path, licence/provenance record and pronunciation review.

| Source / event | Spatial placement and role | Sound material | Haptic meaning |
|---|---|---|---|
| Storm front | Broad rear/upper field; continuous soundscape | Soft rain on earth and thatch, distant low thunder used sparingly, wind shaped by buildings | None |
| Hearth and winter area | Left-middle, tied to visible flame and vessels | Small fire, ceramic contact, low household work; no generic tavern bed | None |
| Protected store | Centre-middle | Wicker/fibre strain, dry grain against storage surface, lid or lashing movement | Slightly firmer threshold when the store closes |
| Spring-seed area | Right-middle | Grain selected into ceramic, wood or fibre vessel; cloth and hand detail | Light accepted-transfer impact |
| Settlement work | Distant, source-bound spatial detail | Footsteps in wet soil, wood, animals and restrained human activity only where visible | None |
| Touch grain | Near-centre foreground | Dry kernel movement and cloth rasp, very close and short | Fine, low-intensity contact texture |
| Lift one share | Follows the direct source only | Small grain separation, hand and basket friction | One soft lift impulse; no continuous buzz |
| Carry | Near field, moving only with actual grain | Sparse kernel/chaff movement; silence is allowed between source and destination | At most sparse texture tied to real contact |
| Destination contact | At the physical destination | Basket flex, vessel touch, cloth or lid response unique to the destination | Subtle threshold cue |
| Accepted drop | At the physical destination | Grain impact scaled to a single share, then immediate decay into the scene | Restrained material impact |
| Revision / return | Reverse path | Grain removed and returned without warning sound | Soft inverse cue, never an error buzz |
| Final divided store | Three destinations remain audible in the same world | Store closure, household continuity and a deliberate breath of quiet | One restrained causal seal, not a reward fanfare |

Narration states the situation and then yields to the user's allocation. Score
must leave room for grain, work, weather and silence. It may carry seasonal
tension and deferred obligation, but it cannot tell the user that a destination
is correct before the world does. Narration, score and soundscape resume from
their authored paused position after interruption; they never autoplay after a
cold launch.

## Reconstruction and defect gate

Every item below is release-blocking for this scene. A checked box records a
verified repair; it does not grant production approval.

### Master and composition

- [ ] Rebuild a new `1290 × 2796` master; do not upscale or paint directly over
      the selected `853 × 1844` image.
- [ ] Supply at least 16 per cent finished camera overscan and verify both crop
      rectangles with no edge extension, clone repetition or empty plate.
- [ ] Remove all baked title, period, place, prompt, destination labels, counter,
      dashed arrows, arrowheads and target rings.
- [ ] Preserve the locked hierarchy: finite grain first, three destinations
      together, inhabited settlement behind, darkness as frame.
- [ ] Keep all three destinations legible without interface marks or labels.
- [ ] Replace the generated ground diagram with plausible wear, footprints,
      carried material and human attention.
- [ ] Reconstruct complete hidden bodies, baskets, cloth, roofs and ground
      behind every extracted layer.
- [ ] Verify perspective and horizon across settlement, destination objects,
      field rows, baskets, cloth and foreground hands.

### Historical and material reconstruction

- [ ] Verify the entire visible material culture against the approved backstage
      source set for Thessaly, `6500–6000 BC`; keep that work out of the public
      package.
- [ ] Replace the current polished, uniform kernel mass with grain morphology
      appropriate to the approved crop portrayal, including credible variation,
      chaff and processing state. It must not read as modern polished rice.
- [ ] Rebuild the raised central storage structure if its circular form,
      elevation, ladder, joinery, roof or use cannot be defended for this place
      and date. Preserve the centre destination's causal role, not an unsupported
      generated object.
- [ ] Replace any metal- or glass-looking suspended lamp, cauldron, fastener,
      blade or fitting with a verified period material and construction.
- [ ] Verify storage pits, baskets, bins, sacks, ceramic vessels, hearths and
      food preparation as distinct technologies rather than interchangeable
      rustic props.
- [ ] Verify mud, timber, wattle, roof and threshold construction; remove
      medieval or picturesque architectural cues.
- [ ] Verify crops, plot scale and ground preparation. Replace machine-regular
      furrows or modern field geometry with the approved hand-worked landscape.
- [ ] Remove the visible cattle traction or plough team unless that exact use is
      supported for the approved time and place. Animals may remain only with
      correct species, scale, equipment and work.
- [ ] Verify clothing fibres, weave, drape, seams, footwear and head coverings;
      remove modern tailoring and generic fantasy costume.
- [ ] Verify every tool material and working edge; no metal agriculture enters
      the scene by visual habit.
- [ ] Keep spring seed visibly separate and sound. Do not show germination,
      flowering or future yield as an immediate consequence.
- [ ] Keep winter food as provision and work, not ceremonial abundance.
- [ ] Keep the protected reserve dry, separate and closed without inventing a
      bureaucratic seal, inscription or lock.

### Anatomy, generated artefacts and layer extraction

- [ ] Correct finger count, joints, grip, wrist rotation, forearm attachment and
      scale for every foreground and midground hand.
- [ ] Correct faces, eyes, ears, feet, knees, seated poses and tool contact for
      every visible person, especially the left household, central store worker
      and right seed worker.
- [ ] Correct animal legs, hooves, heads, harness/contact and occlusion.
- [ ] Remove duplicated people, baskets, kernels, roof marks, trees, smoke
      plumes and repeated texture patches.
- [ ] Remove haloing, matte fringe, colour spill and hard cut edges around hair,
      hands, grain, wicker, thatch, rain and smoke.
- [ ] Match rain direction, wetness, shadow softness, colour temperature and
      reflected light across all separated layers and variants.
- [ ] Verify that smoke begins at a visible source and passes through the right
      depth order. Verify that rain stops at roofs and covered spaces.
- [ ] Verify clean disocclusion at every camera keyframe and at the maximum
      parallax offset for both crops.
- [ ] Verify depth and occlusion masks at basket openings, hands in grain,
      ladder/structure joins, roof lines and the three destination surfaces.
- [ ] Verify that every state variant registers at subpixel alignment and does
      not change identity, camera, weather, body pose or unrelated scenery.
- [ ] Verify that `mechanism-light` contains no ring, path, label, arbitrary
      bloom or light without a physical source.

### Interaction, state and restoration

- [ ] Bind direct touch to the visible central-harvest alpha silhouette and the
      three exact destination polygons.
- [ ] Confirm every target remains at least `44 × 44 pt`, wholly visible and at
      least 12 points from its neighbour in both normal and Reduce Motion crops.
- [ ] Deliver contact response in the first rendered frame and accepted
      transfer response without a detached UI confirmation.
- [ ] Verify that every accepted or reversed share updates deterministic state,
      source depletion, destination state, sound and haptic meaning together.
- [ ] Approve destination `minimumUnits` and the resulting free surplus in the separate `InteractionSpec`
      before authoring final commit copy. Their sum must match the 12-share
      runtime contract unless the interaction runtime is deliberately revised.
- [ ] Verify that the final three consequences coexist and that the exhausted
      foreground remains visible after commit.
- [ ] Force-quit after every stable allocation and reversal; restore identical
      counts, variants, camera, world state and paused audio position.
- [ ] Verify deterministic replay to the same final world-effect hash.
- [ ] Confirm that no path permits a slider, panel, card, quiz answer, victory
      state, alternative history or decorative target overlay to re-enter.

### Text, accessibility, sound and runtime

- [ ] Rebuild every visible word as SwiftUI text using the franchise type
      system and editorially approved English copy.
- [ ] Test all Dynamic Type sizes without truncation, covered evidence or
      unreachable action. Use the focused-destination strategy at large sizes.
- [ ] Verify Increased Contrast without turning destinations into bright UI
      outlines or flattening the light hierarchy.
- [ ] Verify VoiceOver increment, decrement and commit actions against the same
      reducer and the same persistent consequences as touch.
- [ ] Verify Switch Control and direct-tap transfer without requiring a drag.
- [ ] Produce the separate static Reduce Motion master and every required
      stable state; do not merely disable normal animations over a dynamic
      composition.
- [ ] Trace every sound to the visible material or authored dramatic function;
      remove generic settlement beds, modern tools and reward cues.
- [ ] Verify all haptics on the physical target iPhone and remove continuous
      vibration, duplicate feedback and ornamental pulses.
- [ ] Meet the Phase 1 60 fps, frame-time, memory, thermal, cold-resume and
      offline gates with the final layer and mask set.
- [ ] Record creator/tool, model and version where relevant, prompt, source
      inputs, edit history, licence basis and cryptographic hash for every
      master, layer, mask, variant and audio asset.
- [ ] Confirm the public package contains no source notes, claim register,
      confidence score, verifier output, counter-narrative or evidence field.
- [ ] Run final image, chronology, pronunciation, seam and editorial regression
      gates. Escalate any thesis-changing repair privately to the editor-in-chief.

Completion of this checklist makes the scene eligible for editorial review. It
does not change the brief, reference image or future fixture to
`PRODUCTION_APPROVED`, and it does not authorize any asset for a shipping
package.
