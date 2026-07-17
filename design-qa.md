# EUROPA design QA

## Reference comparison

- Reference: `/Users/bard/.codex/generated_images/019f6fc6-a777-7ef2-b880-4ee352536fdd/call_pwZvnrfQb2WnxCEHvtj5ZFN8.png`
- Final desktop capture: `/Users/bard/Documents/Eurocentric/site/.qa-hero-final.png`
- Same-canvas comparison: `/Users/bard/Documents/Eurocentric/site/.qa-comparison.png`
- Comparison viewport: 1440 × 900

The implementation preserves the reference hierarchy and tone: monumental serif wordmark, restrained
navigation, illuminated route, dark cartographic landscape, bronze accents and a single primary action.
The hero is intentionally quieter than the concept image: the sound control is absent because the MVP
has no sound, and the persistent chronology enters with the journey rather than competing with the poster.

## Functional checks

- Initial poster renders before PixiJS enhancement.
- “Begin the journey” moves to the first stable scene hash.
- Chapter dialog opens, closes and links to all fourteen chapters.
- Persistent chronology updates chapter, start year and route progress.
- Every chapter exposes historically specific map places; hover/focus previews and click/tap pins the
  detail panel.
- Place controls work with mouse, touch, Enter and Escape, and update with the active chapter.
- Public navigation and story cards contain no source links. The owner reference page remains directly
  accessible at `/sources/` and is marked `noindex, nofollow`.
- The MVP ends with chapter fourteen; there is no separate completed-route or continuation panel.
- Browser console contains no current errors.
- Static HTML contains the complete story before client enhancement.

## Responsive checks

- 1440 × 900: full cinematic map, alternating story cards and chronology rail.
- 1024 × 768: compact card typography keeps a complete chapter in view.
- 390 × 844: fitted hero wordmark, static map plate, tappable place markers and a contained detail panel.
- Reduced-motion CSS removes the animated canvas and exposes a static map plate.

## Issues resolved

- P1: Mobile hero wordmark exceeded the viewport. Reduced the mobile scale and letter spacing.
- P1: Compact-desktop cards could begin above the viewport. Added height-aware typography and spacing.
- P1: Mobile static plate initially showed the map’s north-west corner. Added scene-specific static framing.
- P2: Future route markers competed with the active chapter. Dimmed unreached markers.
- P2: The 1914 transition lacked a visible rupture. Added a restrained fracture marker and catastrophe palette.
- P1: The map was cinematic but passive. Added 28 chapter-specific places with contextual details and
  accessible pointer, touch and keyboard interaction.
- P1: Interactive controls initially inherited `aria-hidden` from the map stage. Restored the stage as a
  labelled interactive region and hid only decorative layers.
- P2: The map instruction collided with coordinates. Moved the instruction to the upper free edge.
- P2: Source links and the continuation panel competed with the narrative. Removed both from the public MVP.

No unresolved P0, P1 or P2 issues remain.

final result: passed
