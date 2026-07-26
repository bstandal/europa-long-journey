# Native visual bible

Status: locked production rule; Phase 1 is active. The user approves
chapter-specific directions through each editorial contract; this file controls
the shared visual floor.

## Governing composition

The selected world direction is **The Cartographic Procession**. Europe is one
continuous material world whose roads, borders, cities, institutions and
objects accumulate through time. A chapter does not open as a card or leave
the user in a library grid. The world moves to the next historical pressure.

The display is iPhone portrait only. The baseline canvas is 393 × 852 points.
Every master includes at least 15 per cent overscan around the approved camera
path and a separately approved crop for the largest supported portrait canvas.

`Darkness frames the evidence` is literal art direction:

- near-black creates the frame, depth and separation;
- readable midtones show faces, hands, tools, fabric, stone and action;
- the mechanism that changes history carries the clearest light;
- darkness may never conceal a detail the scene asks the user to understand;
- gold and brightness belong to named material or light, never generic prestige.

## Scene construction

Existing web plates are composition references. A native scene requires:

1. one approved high-resolution portrait master;
2. clean deep background after subject removal;
3. background, middle, subject/object and foreground depth layers;
4. separate interactive objects and state variants;
5. occlusion, depth, light and atmosphere masks;
6. authored camera anchors and safe text regions;
7. an ordered Reduce Motion composition with a static world underlay, causal
   state overlays in authored depth order and static foreground occlusion;
8. a typed binding from reducer state to every visual state variant;
9. provenance, prompt/model where relevant, edit history and hashes;
10. package-relative assets bound to the signed manifest before decode.

Generate the complete composition before extracting layers. Independently
generated layers are prohibited by default because identity, perspective and
light drift. A scene with halos, missing disocclusion areas, broken anatomy,
invented inscriptions, period errors or inconsistent material light is remade.

## First Phase 1 visual lock

The editor-in-chief selected option 1 for `The Harvest Had to Last` on
23 July 2026. [selected-direction.png](../design/phase1/harvest/selected-direction.png)
is the composition target, and
[selection.json](../design/phase1/harvest/selection.json) records its exact bytes
and selected direction. The later
[reconstruction-approval.json](../design/phase1/harvest/reconstruction-approval.json)
byte-locks the editor-approved reconstruction composition and anatomy. Neither
record approves shipping pixels or production layers.

The [non-shipping SceneSpec fixture](../phase1/fixtures/harvest-option-1.scene.json)
translates that anatomy into crops, layers, masks, state variants, camera and
hit regions. Its [production brief](../design/phase1/harvest/scene-production-brief.md)
defines the required reconstruction. Both reserve future asset paths; neither
contains an approved production layer or authorises a shipping scene.

The remaining harvest dominates the near foreground. Winter food, protected
reserve and spring seed remain visible together as material destinations in one
inhabited settlement. The user moves grain out of the finite central store; the
household hearth, dry protected reserve and prepared ground answer in the same
scene. This depth hierarchy and causal legibility are fixed for the laboratory
scene.

The selected image is not a shipping plate. Its baked text becomes native text,
its generated dashed arrows become worn routes and responsive material, and its
final master must add overscan, clean layers, state variants, masks and corrected
historical anatomy. Those production corrections cannot turn the scene back into
a card, three sliders or an abstract allocation diagram.

## Motion

Motion has one of three jobs: establish human presence, respond to action or
make consequence visible. Decorative idle motion cannot carry a scene.

- Camera movement follows authored rails and cannot become free navigation.
- Parallax remains subordinate to the active object and never distorts text.
- Atmosphere is spatially coherent and tied to a source: wind, smoke, dust,
  water, flame, textile, work or crowds.
- A completed consequence remains in the scene or living world; it does not
  reset when explanatory copy has finished.
- Reduce Motion replaces travel with fixed anchors and restrained state
  transitions. Static foreground strata remain in front of the state overlays;
  it never removes or falsely unoccludes the causal result.
- Stable visual variants come only from accepted reducer state. Gesture contact,
  carried material and resistance are transient responses and cannot forge a
  completed historical state.
- Direct material remains attached to the same transforms as its source,
  transfer layer and destination. A camera rail cannot make a path drift away
  from the physical object it joins.

Initial laboratory limit: no more than 24 points of foreground displacement or
12 per cent camera travel without a scene-specific justification. These are
comfort constraints to test, not a target to fill.

## Typography and interface

- Bodoni Moda is the display face for franchise and chapter scale.
- Manrope is the working face for body, controls, captions and metadata.
- Historical labels name the action: `Carry the household`, `Raise the road`,
  `Hold the frontier`. Avoid `Continue`, `Explore interaction` and tutorial
  language when the historical action can carry the control.
- Text remains native SwiftUI text. Do not bake narrative or labels into art.
- All body text scales through accessibility sizes without truncation.
- Touch targets are at least 44 × 44 points and remain reachable with one hand.
- Cards, glass panels and floating controls are exceptional. Copy should sit in
  the world or in an intentional dark editorial field, never in generic UI chrome.

## Rejection tests

A scene fails when any answer is yes:

- Would it still be the same article after removing parallax?
- Could its art, motion and controls be moved to three unrelated chapters?
- Is the clearest light ornamental rather than historical?
- Does the user manipulate a slider, button row or hotspot instead of the
  represented route, resource, institution, pressure or transformation?
- Does reduced motion, high contrast or large text hide the consequence?
- Does the image contain an unresolved material, anatomical or chronological error?
