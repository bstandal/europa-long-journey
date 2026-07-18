# Navigation QA — Front to The First Farmers

## Scope

The tested task is to move from the EUROPA front page, through the first point on the long road, and
into the interactive `The First Farmers` chapter.

## Before

1. **Front page — healthy.** The central down-arrow action reached the first point on the road.
2. **The First Farmers overview — unclear.** The deep-chapter link appeared only after the full body
   copy and resembled low-priority footer information.
3. **Interactive chapter — healthy.** The destination preserved the same title, period, palette and
   return route.

Evidence:

- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/01-front-current.png`
- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/02-first-farmers-current.png`
- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/03-chapter-current.png`

## Implemented path

1. **Front page — healthy.** The first action now names its destination:
   `The First Farmers · 7000 BC`.
2. **The First Farmers overview — healthy.** A full-width bordered threshold now appears directly
   after the thesis and before the long body copy. Its public text remains historical:
   `7000–3300 BC` and `Enter the first fields`.
3. **Interactive chapter — healthy.** The link reaches the chapter opening, and `The long road`
   remains available as the return path.

Desktop evidence:

- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/10-front-desktop-final.png`
- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/11-first-farmers-desktop-final.png`
- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/12-chapter-desktop-final.png`

Mobile evidence:

- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/07-front-mobile-fixed.png`
- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/08-first-farmers-mobile-fixed.png`
- `/Users/bard/.codex/visualizations/2026/07/17/019f70e6-72f7-7271-b3a9-f2c0d7433470/front-to-chapter-audit/09-chapter-mobile-fixed.png`

## Accessibility checks

- The threshold is a semantic link with a descriptive accessible name.
- Its 72 px minimum height exceeds the existing touch-target baseline.
- Keyboard focus remains visibly outlined.
- The whole story card was deliberately not made clickable, preserving its internal reading and map
  controls.
- Screenshots confirm hierarchy and reflow; they do not establish full WCAG conformance.

final result: passed
