# EUROPA design QA

## Reference comparison

- Approved visual direction: `/Users/bard/.codex/generated_images/019f6fc6-a777-7ef2-b880-4ee352536fdd/call_pwZvnrfQb2WnxCEHvtj5ZFN8.png`
- Final desktop hero: `/Users/bard/Documents/Eurocentric/site/.audit-current/12-final-desktop.png`
- Final desktop chapter: `/Users/bard/Documents/Eurocentric/site/.audit-current/20-final-icons-desktop.png`
- Final narrow-desktop breakpoint: `/Users/bard/Documents/Eurocentric/site/.audit-current/13-final-breakpoint.png`
- Final mobile explorer: `/Users/bard/Documents/Eurocentric/site/.audit-current/21-final-icons-mobile.png`
- Final global-map chapter: `/Users/bard/Documents/Eurocentric/site/.audit-current/19-final-world-map.png`
- Final sources pages: `/Users/bard/Documents/Eurocentric/site/.audit-current/17-final-sources-mobile.png`
  and `/Users/bard/Documents/Eurocentric/site/.audit-current/18-final-sources-desktop.png`

The 24-chapter implementation preserves the approved visual hierarchy: monumental serif typography,
restrained navigation, the illuminated route, a dark cartographic landscape, bronze accents and one clear
primary action. The extended journey changes the historical scope from 3300 BC to 7000 BC and states the
20-minute commitment without weakening the poster-like opening.

## Functional checks

- A fresh visit presents “Begin the journey”; returning visitors get a chapter-specific resume action and
  can explicitly start again.
- All 24 chapter hashes, the grouped chapter index, the chronology rail, resume links and mobile previous/next
  controls land on the intended active scene.
- The chapter index groups the story into six eras and marks visited chapters without turning the experience
  into a dashboard.
- The four reusable interaction families work in-browser: route, network, boundary and compare.
- Interaction steps update their pressed state, explanatory summary and map drawing. The guided narrative
  remains complete when a visitor ignores the optional controls.
- Chapter 3 presents the Nordic Bronze Age inside the wider European system of copper, tin, amber, shipping,
  rock art and long-distance exchange.
- Chapter 14 lazily loads and crossfades to the Natural Earth world map; later European scenes return to the
  continental map.
- All 63 historical places remain available through map markers and direct mobile place controls.
- Mouse, touch and keyboard interactions expose the same content, with visible focus states and Escape/close
  paths for overlays.
- The mobile Story/Places control follows the tab pattern: one tab in the tab order, Arrow Left/Right and
  Home/End navigation, correctly associated tab panels and deterministic focus on open and close.
- The native chapter dialog moves focus to its close control and returns focus to the opener after close,
  backdrop dismissal or Escape.
- Reduced-motion visitors retain a static, fully informative map rather than losing the visual layer.
- Static HTML contains the complete 24-chapter narrative before PixiJS enhancement.
- Browser console review contains no errors or warnings.

## Responsive checks

- 1440 × 900: full cinematic map, alternating chapter cards, interaction dock and chronology rail.
- 721 × 600: the desktop chronology rail, chapter card and interaction dock remain separate at the exact
  pixel above the mobile breakpoint.
- 390 × 844: compact chapter navigation, collapsible Story/Places explorer, map insight and readable story card.
- 320 × 568: no horizontal overflow; 44px controls, the map explorer and the chapter card remain usable.
- Desktop and mobile source pages have no horizontal overflow and preserve the heading hierarchy.

## Code, security and delivery checks

- `npm run validate:content`: 24 scenes, 63 interactive places, 34 sources and 4 production assets.
- `npm run check`: 0 errors, 0 warnings and 0 hints.
- `npm run build`: two static routes generated successfully with Astro 7.1.1.
- `npm audit --omit=dev`: 0 vulnerabilities.
- `git diff --check`: clean.
- The production artifact is 2.3 MB, reduced from 11 MB by replacing the general-purpose icon font with a
  twelve-symbol local SVG sprite and moving lossless source artwork outside `public/`.
- The global relief remains lazy-loaded; the first journey screen ships the optimized European relief and
  hero assets only.

## Issues resolved

- P1: Twenty-four camera points produced a distracting web of future-route lines. Reduced the inactive route
  to a cartographic trace while keeping the active historical connection legible.
- P1: Native fragment navigation could stop on the preceding chapter. Routed index, chronology, resume and CTA
  links through the scene navigation system and verified the settled active chapter.
- P1: The former mobile experience exposed places but not the new chapter interactions. Added a collapsible,
  tabbed map explorer that offers both interaction steps and direct place access.
- P1: A single European plate could not explain the oceanic and global chapters. Added a lazy world-map scope
  with a restrained crossfade and public-domain Natural Earth relief.
- P1: The Nordic Bronze Age risked appearing as an isolated northern appendix. Built it as a network chapter
  connecting Scandinavian bronze, Baltic amber, Atlantic tin and Mediterranean demand.
- P2: The desktop interaction dock could compete with place detail. It now yields whenever a place insight is
  pinned and returns when the insight closes.
- P2: Returning users previously lacked clear progress continuity. Added local resume state, visited chapters
  and an explicit restart action without blocking first-time visitors.
- P2: Long chapter jumps depended on browser-native fragment positioning. Smooth scene-aware navigation now
  places the selected chapter consistently below the fixed header.
- P1: Opening the mobile explorer or switching tabs could drop focus on the document body. The explorer now
  places focus on its selected tab, implements roving tab focus and restores focus to the visible trigger.
- P1: Closing a mobile place detail discarded keyboard focus. The detail now returns focus to the invoking
  control when visible, or to the map-explorer trigger after the explorer has closed.
- P1: At 721px wide the desktop chronology rail collided with the chapter card. The intermediate breakpoint
  now reserves a dedicated rail gutter and has a verified zero-overlap layout.
- P1: The previous Astro dependency reported one high and one low advisory. Astro 7.1.1 now builds cleanly
  and the production dependency audit reports zero vulnerabilities.
- P2: Progress persistence wrote to local storage on every scroll frame. Writes are now deduplicated by active
  chapter, and “Start again” immediately resets every resume and visited-state affordance.
- P2: Focus treatment varied between native browser outlines and the visual system. Dialog, chapter, mobile
  explorer and place-detail controls now share the same high-contrast bronze focus treatment.
- P2: The icon package and unused PNG copies inflated the production artifact from 2.3 MB to 11 MB. A local SVG
  sprite and non-public source-artwork folder remove that delivery cost.

No unresolved P0, P1 or P2 issues remain.

## Accessibility scope

The audit covered semantic landmarks, heading order, unique IDs, accessible names, dialog focus, tab keyboard
behavior, visible focus, 44px mobile targets and reduced-motion fallbacks. A dedicated screen-reader session
and external contrast instrumentation were not available in this pass; no blocker was found in the semantic
or visual review.

final result: passed
