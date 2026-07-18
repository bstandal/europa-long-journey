# Bronze Europe — final design QA

- Source visual truth:
  `/Users/bard/.codex/generated_images/019f7563-067e-77a0-8425-d9a7318ca24f/call_gA2vA7KC3UyuNU4uama8bxWb.png`
- Browser-rendered implementation:
  `/Users/bard/Documents/Eurocentric/site/audit/bronze-scroll-qa-2026/01-opening-mobile-390x844.png`
- Full-view comparison:
  `/Users/bard/Documents/Eurocentric/site/audit/bronze-scroll-qa-2026/comparison-opening-source-left-implementation-right.png`
- Flow evidence:
  `/Users/bard/Documents/Eurocentric/site/audit/bronze-scroll-qa-2026/flow-contact-sheet.png`
- Viewport: `390 × 844`
- State: opening and representative movement, interaction and ending states

## Findings

No actionable P0, P1 or P2 issues remain at the target mobile viewport.

- Fonts and typography: Bodoni Moda and Manrope retain the selected display/editorial hierarchy.
  Every movement title is readable at 390 px, the longest titles wrap deliberately, and prose keeps a
  comfortable line length and line height.
- Spacing and layout rhythm: the 62 px header and 198 px opening atlas plate match the selected
  map-to-sea sequence. During the narrative, the route contracts to 150 px and the document becomes a
  continuous vertical flow. There is no horizontal overflow.
- Colors and visual tokens: green-black water, limestone ivory, graphite relief and restrained
  polished bronze remain consistent from opening through sources. Bronze is used for route, date,
  focus and evidence accents rather than as a general wash.
- Image quality and asset fidelity: the opening map, sea scene and nine movement reconstructions are
  production raster assets with complete natural dimensions. No image failed to load. Crops preserve
  the principal action on mobile and stay within the selected museum-editorial art direction.
- Copy and content: the opening claim remains unchanged. The page now contains 2,750 visible words,
  ten narrative movements, ten evidence disclosures, four optional interactions and a concrete
  handoff to Greece. No reading-time or application-state copy appears in the public experience.
- Navigation and interaction: all ten route states update from scrolling alone. The alloy route,
  Nordic inspection, Uluburun inspection and archive-to-memory comparison work as optional pauses.
  Opening and ending route states no longer leak into one another.
- Accessibility: semantic headings, labelled map region, alt text, focus styles, reduced-motion
  handling and 44 px primary touch targets are present. Inline citation links use the WCAG inline-text
  target exception. The page has no horizontal overflow at 390 px.

## Full-view comparison evidence

The combined source-left/implementation-right image compares the same opening and target mobile
viewport. The implementation preserves the source’s header, bronze route plate, low ship-level
horizon, two-line title, thesis and final historical invitation. The live route adds a current place
line beneath the map so the same component can guide all ten movements.

## Focused-region evidence

The seven-state contact sheet keeps route labels, scene titles, prose measure, act transitions,
interaction controls and ending copy large enough to judge. A separate pixel crop was unnecessary
because those surfaces remain legible at half scale in the sheet and were inspected individually in
the browser at 1:1.

## Primary interactions tested

- Ordinary scrolling activates every movement and updates date, place, route marker and URL hash.
- `Sword` in the alloy sequence changes the selected point and explanatory consequence.
- The archive-to-memory slider updates the visual split from 50 to 82 percent.
- `Memory` changes the selected comparison layer and detail.
- Returning to scroll position zero restores `c. 2500 BC · Europe · Egypt · Mesopotamia`.
- Entering the ending preserves the European route map instead of restoring the opening atlas.
- All movement images load; no horizontal overflow appears; build and content validation pass.

## Comparison history

### Iteration 1 — structural correction

- P1: the previous act tabs hid two-thirds of the experience and made clicking the primary navigation.
- P1: 249 visible words and three mobile screens could not sustain the requested chapter depth.

Fixes:

- Replaced the standalone tab page with the existing deep-chapter engine.
- Added ten continuous movements, automatic route progress, ten evidence layers and four optional
  interactions.
- Expanded the visible narrative to 2,750 words and the mobile document to 22,091 px.

### Iteration 2 — route and fidelity correction

- P2: returning to the opening after Homer kept the final Greek place label.
- P2: the first rebuilt opening compressed the selected 198 px atlas region to 150 px.
- P2: the comparison slider exposed only a 30 px-high touch target.

Fixes:

- Added explicit opening, movement and ending route regions and reset the opening location.
- Restored the 198 px mobile opening atlas while keeping the compact movement route.
- Raised range-input hit areas to 44 px.

Post-fix evidence:

- `/Users/bard/Documents/Eurocentric/site/audit/bronze-scroll-qa-2026/comparison-opening-source-left-implementation-right.png`
- `/Users/bard/Documents/Eurocentric/site/audit/bronze-scroll-qa-2026/flow-contact-sheet.png`

## Residual test limits

- The target visual is mobile, so the current browser-rendered comparison is limited to `390 × 844`.
  Desktop uses the already established deep-chapter layout and passed static build validation, but it
  is not part of this final pixel comparison.

final result: passed
