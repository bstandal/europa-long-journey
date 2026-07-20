# Chapter 08 design QA

## Scope

- Chapter: `The Papal Revolution`
- Route: `http://127.0.0.1:4326/chapters/papal-revolution/`
- Reference direction: `Two Courts, One Christendom`
- Reference image: `/Users/bard/.codex/generated_images/019f7b67-8579-73e1-a093-abfce1ef2978/call_rR5CqTLycBDwtkMbF0Oa91mr.png`
- Browser: Codex in-app browser
- States reviewed: opening, route drawer, reform-papacy interaction, Worms settlement interaction
- Viewports reviewed: 1487 × 1058, 900 × 1024, 390 × 844

## Comparison evidence

### Full opening

- Production capture: `design/chapter-08-qa/opening-desktop-1487x1058-final.png`
- Side-by-side reference and production: `design/chapter-08-qa/comparison-desktop-final.png`
- Mobile production capture: `design/chapter-08-qa/opening-mobile-390x844.png`

The final desktop opening preserves the reference triptych, central title field, aged-gold procedural route, restrained serif hierarchy and low-key Romanesque palette. The compact public opening claim restores the reference's line length and vertical rhythm while the fuller historical thesis remains the chapter's canonical claim.

### Focused chapter regions

- Final Worms movement, desktop: `design/chapter-08-qa/movement-worms-desktop.png`
- Final Worms interaction, mobile: `design/chapter-08-qa/movement-worms-mobile-390x844.png`

The focused comparison confirms that the opening grammar carries into the long-form chapter: dark archival surfaces, parchment typography, fine gold rules, documentary imagery and legible state changes remain coherent in the final movement.

## Comparison history

1. Pass 1 found a P2 visual mismatch: the full editorial thesis occupied about twice the reference's vertical space and displaced the opening action.
2. The opening now uses a concise public claim matching the approved reference density. The canonical chapter claim retains the historically precise account of spiritual investiture, temporal regalia and two organised jurisdictions.
3. The final side-by-side comparison shows no remaining P1 or P2 visual mismatch.

## Visual findings

- Typography: display scale, line breaks, tracking and serif/sans contrast match the approved direction.
- Spacing: title, claim and action retain the reference's central rhythm; all three remain visible in the first mobile viewport.
- Colour: charcoal, parchment, aged gold and muted madder remain consistent through opening, movements and interactions.
- Images: thirteen production AVIF assets have period-specific subjects, coherent crops and a shared early-Romanesque visual language.
- Copy: the full chapter contains four acts and twelve movements, with the concise opening claim used only where visual density requires it.
- Icons and controls: controls use the project's existing marks and interaction grammar; no placeholder, emoji or improvised vector art is present.

## Responsive and accessibility findings

- No horizontal overflow at 1487 px, 900 px or 390 px.
- At 390 × 844, the opening title, claim and primary action end above the first viewport fold.
- The final four Worms choice controls measure 155 × 50 px on mobile.
- Active interaction choices update `aria-pressed`, reveal the matching record and preserve an `aria-live` detail region.
- The route toggle updates `aria-expanded` from `false` to `true` and back.
- Headings, landmarks, skip link and native buttons/links remain present in the accessibility snapshot.

## Functional findings

- Reform-papacy state tested: `synod` → `legate`.
- Worms settlement state tested: `elect` → `enfeoff`.
- Route drawer open and close tested.
- Browser console checked after desktop, mobile and tablet navigation: no warnings or errors.
- `npm run check`: 0 errors, 0 warnings, 0 hints.
- `npm run build`: passed content validation, chapter tests and static production build.
- Validated corpus: 24 scenes, 8 deep chapters, 63 interactive places, 146 sources.
- Chapter narrative reported by the validator: 2,781 words.

## Final assessment

No P1 or P2 issues remain. The implementation is visually faithful to the approved prototype, responsive, interactive and production-build clean.

final result: passed

# Chapter 09 design QA

## Scope

- Chapter: `A Society Beyond Kin`
- Route: `http://127.0.0.1:4326/chapters/society-beyond-kin/`
- Reference direction: `The Forbidden Threshold`
- Reference image: `/Users/bard/.codex/generated_images/019f7b67-8579-73e1-a093-abfce1ef2978/call_sQ9Q46Orp91spIg9RWafNtQM.png`
- Browser: Codex in-app browser
- States reviewed: opening, marriage interaction, commune interaction, final corporate-body interaction and ending
- Viewports reviewed: 1487 × 1058 and 390 × 844

## Comparison evidence

- Final desktop opening: `design/chapter-09-qa/opening-desktop-final.png`
- Side-by-side reference and production: `design/chapter-09-qa/opening-comparison.png`
- Mobile opening: `design/chapter-09-qa/opening-mobile-390x844.png`
- Mobile marriage interaction: `design/chapter-09-qa/interaction-mobile-390x844.png`
- Desktop commune movement: `design/chapter-09-qa/movement-08-desktop-final.png`
- Desktop ending: `design/chapter-09-qa/ending-desktop-final.png`
- Mobile ending: `design/chapter-09-qa/ending-mobile-390x844-final.png`

The desktop opening preserves the approved deep-charcoal editorial field, monumental ivory title,
Romanesque threshold, inspected kinship parchment, separated family groups and open road. The mobile
opening retains the same causal image while fitting period, full title, claim and primary action
inside the first viewport.

## Visual findings

- Typography: the two-line Bodoni title, compact period line and restrained small-cap action match
  the selected direction’s hierarchy.
- Composition: the opening keeps copy in the dark left field while the priest, couple, parchment and
  road carry the visual argument on the right.
- Colour: near-black, smoky parchment, aged gold, oxblood, limestone and dark oak remain consistent
  through all thirteen generated scenes and the interaction surfaces.
- Long-form continuity: each movement depicts a concrete institutional act—prohibition, consent,
  donation, vow, oath, election, divided custody, legal recognition or succession.
- No placeholder imagery, improvised vector art, modern wedding conventions, Gothic spectacle or
  later medieval armour appears.

## Responsive and accessibility findings

- No horizontal overflow at 1487 px or 390 px.
- The 390 × 844 opening contains the title, claim and primary action in the first viewport.
- Mobile interaction choices remain at least 50 px high and use a two-column layout.
- Every interaction keeps exactly one `aria-pressed` choice and one visible matching record.
- All twelve movement images have descriptive alt text and load at their intended 1536 px source
  width.
- The chapter retains headings, regions, skip navigation, native links and native buttons in the
  accessibility tree.

## Functional findings

- Marriage interaction tested from `Blood kin` to `Consent`; record and `aria-live` detail update.
- Eight chapter interactions render with the expected four or three choices and one visible record.
- The chapter ending links to the existing `The Medieval Commercial Revolution` scene.
- Browser console: no warnings or errors.
- `npm run check`: 0 errors, 0 warnings, 0 hints.
- `npm run validate:content`: passed with 24 scenes, 9 deep chapters, 63 interactive places and 155
  sources.
- `npm run test:chapter`: passed all chapter assertions.
- `npm run build`: passed and generated `/chapters/society-beyond-kin/`.

## Final assessment

No P1 or P2 issues remain. Chapter 09 is a complete, responsive and production-build-clean
historical essay whose visual system remains faithful to the approved prototype across the full
chapter.

final result: passed
