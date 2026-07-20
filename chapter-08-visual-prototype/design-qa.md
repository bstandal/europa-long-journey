# Chapter 08 visual prototype — design QA

## Comparison target

- Source visual truth:
  `/Users/bard/.codex/generated_images/019f7b67-8579-73e1-a093-abfce1ef2978/call_rR5CqTLycBDwtkMbF0Oa91mr.png`
- Final desktop implementation:
  `/Users/bard/Documents/Eurocentric/chapter-08-visual-prototype/design/qa/opening-desktop-1487x1058-final.png`
- Final mobile implementation:
  `/Users/bard/Documents/Eurocentric/chapter-08-visual-prototype/design/qa/opening-mobile-390x844.png`
- Full-view comparison evidence:
  `/Users/bard/Documents/Eurocentric/chapter-08-visual-prototype/design/qa/comparison-desktop-final.png`
- Focused central-copy comparison evidence:
  `/Users/bard/Documents/Eurocentric/chapter-08-visual-prototype/design/qa/comparison-central-copy-final.png`
- Desktop viewport: 1487 × 1058
- Mobile viewport: 390 × 844
- State: chapter opening before interaction

## Findings

No actionable P0, P1 or P2 fidelity issues remain.

- Fonts and typography: Bodoni Moda and Manrope reproduce the target's high-contrast display face,
  restrained metadata and small tracked actions. The final focused comparison confirms the same
  three-line hierarchy, similar optical width, readable claim and uncut action. The generated source
  does not identify an exact display font; the remaining difference in letterform detail is P3.
- Spacing and layout rhythm: the 84px desktop header, central title pier, flanking courts, copy stack,
  action rule and messenger opening preserve the source hierarchy. The 390 × 844 layout stacks the
  messenger-centred scene above all opening copy and keeps the primary action inside the first
  viewport.
- Colors and tokens: near-black, parchment bone and restrained aged gold match the source balance.
  Gold remains limited to metadata, route, navigation and action states.
- Image quality and asset fidelity: the dedicated 1536 × 1024 raster plate preserves both assemblies,
  the central passage, messenger, paired seals and non-glowing procedural route. It uses no CSS,
  div-art or SVG substitute for the historical image.
- Copy and content: the title, date, claim and primary action match the selected direction. The
  supporting preview uses the planned opening movement at Sutri and stays inside the chapter's
  editorial mechanism.
- Icons: the two navigation arrows use Phosphor's regular icon family at the target's restrained
  weight and scale.
- Responsiveness and accessibility: mobile document width equals the 390px viewport; no horizontal
  overflow is present. The primary action is 44px high, all image content has useful alternative
  text, the icon-only mobile return link has an accessible name, and keyboard focus styles are
  defined.

## Interaction and runtime evidence

- “Enter the contested order” moved the document to `#chapter-preview`; the preview aligned to the
  viewport top and its heading remained visible.
- “Return to the two courts” restored the opening to scroll position 0.
- The mobile return control resolves to the accessible name “Return to the long road”.
- Browser console warnings and errors after loading and testing: none.
- Production build: passed.

## Comparison history

1. Pass 1 found a P2 vertical-rhythm issue: the claim/action stack sat roughly 30px below the source,
   placing the action directly over the bright doorway. The opening top padding, claim scale and
   spacing, and action margin were tightened.
2. Pass 2 found a P2 typography issue: the title's optical width was broader than the source. The
   display scale was reduced and line height increased to retain the source's vertical measure.
3. The final full-view and focused comparisons show the corrected hierarchy with no actionable
   P0/P1/P2 mismatch.

## Follow-up polish

- P3: the target's synthetic display face has slightly narrower capitals than Bodoni Moda. This does
  not change wrapping, hierarchy or readability and should only be revisited if EUROPA later adopts a
  different licensed serif across all chapters.

## Implementation checklist

- [x] Dedicated historical raster asset placed
- [x] Desktop source composition recreated
- [x] 390 × 844 mobile opening verified
- [x] Primary and return actions tested
- [x] Accessible navigation names verified
- [x] Console checked
- [x] Production build passed

final result: passed
