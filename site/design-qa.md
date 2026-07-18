# Design QA — The First Farmers

## Visual comparison

- Selected source:
  `/Users/bard/.codex/generated_images/019f70e6-72f7-7271-b3a9-f2c0d7433470/call_p0aJgn4PD9ITemcQwtC7csP2.png`
- Final implementation:
  `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/first-farmers-fix-qa/harvest-mobile-final-390.png`
- Combined source/current comparison:
  `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/first-farmers-fix-qa/reference-current-mobile-comparison-final.png`
- Representative control state:
  `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/first-farmers-fix-qa/harvest-mobile-control-390.png`
- Viewports checked: 390 × 844 and 320 × 568. Desktop structure was checked at a
  normal viewport; the in-app capture backend returned a device-pixel-ratio crop at desktop size, so
  the final side-by-side uses the fully verified 390 × 844 state.

The selected source and the implementation preserve the same visual language: forest-black ground,
ivory Bodoni display type, restrained bronze detail, smoky landscape photography and a fixed EUROPA
wordmark. The implementation adapts the reference to a narrow viewport instead of clipping the title
and thesis. It also adds the geographic route and readable narrative space needed by the chapter.

No actionable P0, P1 or P2 visual differences remain.

## Content and evidence

- Migration is described as movement by farming communities chiefly related to western Anatolian
  farmers, not as an empty-land replacement story.
- Iron Gates exchange and ancestry are represented as dated archaeological contexts, not a fictional
  three-generation pedigree.
- Harvest, population and clearance states use illustrative choices or qualitative reconstructions;
  unsupported ancestry percentages, household counts and woodland percentages were removed.
- Kinship language distinguishes local patrilocal patterns from universal inheritance rules.
- Disease copy follows the ancient-pathogen chronology and separates the first zoonotic detections
  from later pastoralist expansion.
- Selection copy states what the 2026 ancient-DNA study measured and explicitly rejects the inference
  that farming raised human intelligence.
- Language copy separates the south-Caucasus language-tree model from the later steppe-associated
  spread of many Indo-European branches in Europe.
- Every movement exposes scene-level evidence and linked sources under “What survived”.

## Interaction and accessibility

The final production build was tested in the in-app browser:

- Seasons: selecting Summer changes the landscape description and resources.
- Route: selecting the Danube advances the visible route and historical detail.
- Harvest: reducing spring seed changes the store allocation and consequence.
- Lineage: selecting contact-period burials reveals the dated ancestry evidence.
- Longhouse: selecting the older house reveals the posthole evidence.
- Growth: moving to the contraction state changes image, settlement and landscape text.
- Comparison: moving the reveal and selecting Languages changes both the split and interpretation.

Standard buttons and range inputs retain native keyboard semantics. Visible focus styles, 44 px touch
targets, descriptive `aria-valuetext`, live regions, an accessible mobile return link and inert
off-screen desktop controls are present. The chapter remains readable without JavaScript, and its
reduced-motion rules remove nonessential transitions.

The browser console was checked during interaction QA with no runtime warnings or errors.

## Verification

- `npm run check`: 0 errors, warnings or hints.
- `npm run validate:content`: 24 scenes, 1 deep chapter, 63 places, 41 sources and 4 licensed assets.
- `npm run test:chapter`: passed.
- `npm run build`: passed; 3 static routes generated.
- Forbidden duration, progress, tutorial and chapter-count phrases are absent from public chapter copy.

final result: passed
