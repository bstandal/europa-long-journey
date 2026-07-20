# Chapter 07 visual prototype design QA

## Comparison target

- Source visual truth:
  `design/reference-option-2.png`
- Implementation:
  `http://localhost:4173/`
- Primary implementation screenshot:
  `design/qa/desktop-1440x1024-final.png`
- Primary viewport:
  1440 × 1024 CSS pixels
- Primary state:
  chapter opening at scroll position 0
- Full-view comparison evidence:
  `design/qa/desktop-comparison-final.png`
- Focused typography and copy comparison:
  `design/qa/desktop-focus-copy-final.png`
- Responsive evidence:
  `design/qa/mobile-390x844.png` and `design/qa/tablet-834x1194.png`

The generated source image was 1487 × 1058 and was normalized to the primary
1440 × 1024 viewport for comparison.

## Findings

No actionable P0, P1 or P2 findings remain.

- **Fonts and typography:** The implementation uses the project’s Bodoni Moda
  display face and Manrope interface face from local font packages. The title,
  metadata, claim and action match the selected reference’s hierarchy, optical
  width, line wrapping and tracked uppercase treatment. The final claim occupies
  four lines on desktop, matching the source.
- **Spacing and layout rhythm:** The 84-pixel header, asymmetric approximately
  37.5/62.5 split, copy baseline, title-to-claim gap and action placement follow
  the selected reference. The divider begins at the metadata and continues
  through the image without introducing a card or overlay panel.
- **Colors and tokens:** Ink black, vellum ivory and restrained aged gold map to
  the existing EUROPA palette. Warm light remains inside the historical scene;
  the interface itself stays near-black and low-gloss.
- **Image quality and asset fidelity:** The prototype uses a dedicated 1536 ×
  1024 raster reconstruction with the selected scriptorium, writing hand,
  codices, wax tablet, messenger and reused Roman column. The selected mock’s
  pointed arches were intentionally corrected to round late-Roman arches
  appropriate to AD 750–820. The desktop crop preserves the mock’s column, hand,
  messenger and foreground desk hierarchy; mobile recomposes the same asset
  without stretching.
- **Copy and content:** All visible public copy from the selected mock is present
  verbatim. The off-screen preview continues the same editorial claim without
  exposing prototype or design-process language.
- **Icons:** Navigation and movement arrows use one consistent Phosphor icon
  family at restrained sizes. No handcrafted SVG, CSS illustration or text-glyph
  icon substitutes are present.
- **States and interactions:** “Follow the rebuilt road” scrolls to the chapter
  preview, and “Return to the opening” returns to the hero. Both actions were
  exercised in the browser on desktop, and the entry action was exercised on
  mobile.
- **Responsiveness:** At 390 × 844 the image, title, complete claim and entry
  action all fit inside the opening viewport. At 834 × 1194 the split composition
  remains intact. Measured document width equals viewport width at both tested
  sizes, with no horizontal overflow.
- **Accessibility and resilience:** The page uses semantic navigation, labelled
  regions, real buttons, descriptive image alt text, visible keyboard focus,
  reduced-motion handling and a 46-pixel mobile entry target. Browser logs showed
  no warnings or errors.

## Focused comparison

The focused copy comparison was required because the selected direction depends
on exact display-face width, claim wrapping and action alignment. The final
comparison confirms the title occupies the same two-line block, the claim uses
the same four-line measure and the action rule terminates at the same visual
width. A separate focused image crop was unnecessary because the full-view
comparison clearly shows the hero asset’s principal column, arch, messenger,
hand and desk objects at readable scale.

## Comparison history

### Pass 1 — blocked

- **[P2] Editorial block sat too high.** Metadata, title and claim entered the
  frame roughly 40–50 pixels above the selected source.
- **[P2] Hero crop placed the reused column and writing hand too far right.**
  The crop weakened the source’s intended image hierarchy.
- Evidence: `design/qa/desktop-1440x1024-pass1.png` and
  `design/qa/desktop-comparison-pass1.png`.

### Fixes

- Anchored the desktop copy from the top with a measured 258-pixel inset.
- Rebalanced the claim and action gaps so the action retained its source
  baseline.
- Shifted the historical asset crop left to align the arch, reused column,
  messenger and writing hand with the selected composition.

### Pass 2 — blocked

- **[P2] Display width and body measure drifted from the source.** The title was
  optically too wide, while the narrower claim wrapped to five lines rather than
  four. The action rule was also shorter than the source.
- Evidence: `design/qa/desktop-comparison-pass2.png`.

### Final fixes

- Applied a restrained horizontal optical correction to the desktop title
  without changing its vertical scale.
- Widened the desktop copy measure to 452 pixels and restored the source’s
  four-line claim.
- Matched the action rule and continuity-rule start to the selected reference.

### Final pass — passed

- Desktop full-view and focused comparisons contain no actionable P0, P1 or P2
  differences.
- Mobile and tablet layouts remain inside their viewports.
- Entry and return actions work, fonts and the hero image load, and the browser
  console contains no warnings or errors.

final result: passed
