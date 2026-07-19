# Chapter 07 production QA

**Chapter:** Europe Reborn
**Review date:** 19 July 2026
**Status:** Production ready

## Production scope

- Four acts and fourteen movements covering AD 476–1000.
- 2,778 narrative words in the rendered chapter.
- Four principal interactions in movements 2, 7, 9 and 13.
- Five compact evidence traces in movements 3, 4, 6, 10 and 14.
- Fourteen landscape historical reconstructions and four dedicated portrait mobile compositions.
- A source-backed handoff from the western imperial collapse to the Papal Revolution.

## Automated checks

| Check | Result |
| --- | --- |
| `npm run check` | Pass: 53 files, no errors, warnings or hints |
| `npm run validate:content` | Pass: 24 scenes, 7 deep chapters, 63 interactive places, 138 sources |
| `npm run test:chapter` | Pass: all seven deep-chapter suites |
| `npm run build` | Pass: 9 static routes generated |
| Browser console | Pass: no error-level messages |

## Visual QA

| Surface | Result | Notes |
| --- | --- | --- |
| Desktop, 1440 × 1024 | Pass | Opening compared side by side with the selected Written Commonwealth reference; split, scale, ruled line, typography and image balance align with the source direction. |
| Tablet, 768 × 1024 | Pass after fix | Interaction grid now uses flexible columns and remains inside the viewport. |
| Mobile, 390 × 844 | Pass after fix | Story width and movement padding reset correctly below 720 px; title, body, evidence and controls no longer clip. |
| Mobile scene assets | Pass | Movements 1, 5, 8 and 14 load their dedicated 1024 × 1536 AVIF sources. |
| Ending and handoff | Pass | Gniezno conclusion, next chapter and return path remain readable and reachable on mobile. |

## Interaction QA

- Every principal interaction exposes a native button group with an active `aria-pressed` state.
- Switching a state updates the detail sentence and displays the matching record.
- The route explorer opens and closes through its button and updates `aria-expanded`.
- The homepage “Follow the rebuilt road” entry opens `/chapters/europe-reborn/`.
- The ending points to `/#papal-revolution`.

## Editorial and image review

- Clovis’s baptism date and Pippin’s first anointing remain explicitly uncertain.
- Saxon conversion is described as forced within conquest.
- The coronation accounts of AD 800 are not collapsed into a single uncontested reading.
- Verdun is not treated as the birth of modern France and Germany.
- Viking violence, trade and slavery remain visible together.
- Latin and Byzantine Christian roads are related without projecting the formal schism of 1054 backwards.
- Gniezno is presented as pilgrimage, gift exchange and political recognition, not a coronation.
- Image review found no pointed Gothic arches, plate armour, papal tiaras, heraldic fantasy or modern objects in the production set.

## Review artifacts

- `opening-reference-vs-production-final.png`
- `opening-desktop-1440x1024-final.png`
- `movement-02-desktop-1440x1024-final.png`
- `movement-02-tablet-768x1024-fixed.png`
- `opening-mobile-390x844-candidate.png`
- `movement-02-mobile-390x844-fixed.png`
- `movement-14-mobile-390x844-final.png`
- `ending-mobile-390x844-final.png`
- `scenes-01-14-contact-final.png`
- `mobile-assets-contact-final.png`

All review artifacts and lossless source PNGs are retained in `site/design/chapter-07-generated/`. The public production directory contains only the AVIF delivery assets.
