# Chapter 06 design QA

## Comparison target

- Source visual truth:
  `design/references/chapter-06-consecrated-city.png`
- Local implementation:
  `http://127.0.0.1:4323/chapters/empire-takes-cross/`
- Primary viewport:
  1440 × 1024 CSS pixels, device scale factor 1
- Primary state:
  chapter opening at scroll position 0
- Final implementation screenshot:
  `design/qa/chapter-06-desktop-1440x1024.png`
- Final side-by-side comparison:
  `design/qa/chapter-06-desktop-comparison-final.png`
- Mobile responsive evidence:
  `design/qa/chapter-06-mobile-390x844.png`
- Focused interaction evidence:
  `design/qa/chapter-06-policy-interaction-1440x1024.png`

## Findings

No actionable P0, P1 or P2 findings remain.

- **Fonts and typography:** The implementation retains the project’s existing
  high-contrast display serif, restrained sans-serif metadata and wide-tracked
  EUROPA wordmark. Title scale, two-line desktop wrap, line-height and optical
  weight match the selected direction. At 390 pixels the title becomes a
  controlled three-line composition without clipping.
- **Spacing and layout rhythm:** Header height, left alignment, opening number,
  title, claim and action follow the reference hierarchy. The desktop action is
  fully visible inside the 1024-pixel viewport. The mobile opening preserves
  readable space between title, claim and action. No document-level horizontal
  overflow was measured at either viewport.
- **Colors and tokens:** Iron black, smoky ivory, porphyry shadow, indigo and
  sparse aged gold map to the selected direction. Gold is restricted to
  reflected light, rules, metadata and active states rather than used as a
  generic luxury surface.
- **Image quality and asset fidelity:** The opening uses a purpose-built,
  evidence-led Milvian Bridge reconstruction rather than the option mock’s
  generic construction procession. This is an intentional content correction:
  the subject now matches movement 01 while preserving the reference’s road,
  dark field, processional depth and sacred break of light. All fourteen
  movement scenes and the Constantinople plan are dedicated raster assets; no
  historical scene is replaced by placeholder or code-drawn art.
- **Copy and content:** Public copy is coherent as a standalone chapter opening
  and uses the locked 312–565 claim. The final claim is slightly more exact than
  the concept mock by naming a “renewed Christian Rome.”
- **States and interactions:** Policy, council, city and sacred-space controls
  update their selected button, live detail and corresponding record. Five
  three-stop trace interactions use the same touch-friendly state system. The
  mobile route panel opens and closes, stays within 390 pixels and returns focus
  to normal reading order.
- **Accessibility and resilience:** Controls are semantic buttons, selected
  state is exposed through `aria-pressed`, details update in live regions, the
  map panel has an expanded state, movement images have narrative alt text, and
  reduced-motion rules remove decorative transition duration. Mobile principal
  buttons measure 118 × 72 pixels.

## Focused comparison

The opening required a full-view side-by-side comparison because hierarchy,
crop and the title-to-image relationship are the fidelity-critical surfaces.
The focused interaction screenshot was reviewed separately because the concept
mock did not define an interaction state. It confirms that the 44-pixel
navigation rail occupies the opposite side from the active story and that the
fixed interaction occupies the lower viewport without horizontal clipping.

## Comparison history

### Pass 1 — blocked

- **[P2] Opening action fell below the desktop fold.**
  The first screenshot placed the action at 1000–1044 pixels in a 1024-pixel
  viewport, making the invitation partly inaccessible above the fold.
- **[P2] Chapter route added visual competition to the opening.**
  The route rail appeared over the upper-right image field although the selected
  source kept the opening free of chapter navigation.
- Evidence:
  `design/qa/chapter-06-desktop-1440x1024-pass1.png` and
  `design/qa/chapter-06-desktop-comparison-pass1.png`.

### Fixes

- Raised the desktop opening block by changing its top/bottom vertical padding
  from 39/14 svh to 32/25 svh.
- Hid the chapter route only while `data-chapter-region="opening"`; it returns as
  a compact 44-pixel rail after entry and remains hidden at the ending.

### Pass 2 — passed

- The action now occupies 888–932 pixels and is fully visible.
- The route opacity is zero in the opening and returns after the entrance link.
- Title, claim and action remain within the selected source hierarchy.
- The desktop and mobile pages measure zero document-level horizontal overflow.
- Post-fix evidence:
  `design/qa/chapter-06-desktop-comparison-final.png` and
  `design/qa/chapter-06-mobile-390x844.png`.

## Browser verification

- Entered the chapter through “Enter the consecrated city.”
- Opened and closed the mobile route panel.
- Changed policy to `confession-380`.
- Changed the council to `reception`.
- Changed the city to `capital-450`.
- Changed Hagia Sophia to `emperor`.
- Checked the in-app browser log after the interactions: no warnings or errors.
- Ran Astro type diagnostics, content validation, chapter tests and production
  build with zero errors.

final result: passed
