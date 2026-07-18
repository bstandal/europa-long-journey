# Design QA — EUROPA deep chapters

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

## Steppe extension — visual comparison

- Farmers reference/current regression:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/20-farmers-reference-current-comparison.jpg`
- Matched 1280 × 720 Farmers/Steppe comparison:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/21-farmers-steppe-matched-comparison.jpg`
- Eight-image Steppe contact sheet:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/15-steppe-scene-contact-sheet.jpg`
- Final desktop opening:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/18-steppe-opening-1280x720.jpg`
- Final desktop interaction states:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/02-desktop-mobility-herd-1440.png`,
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/03-desktop-turnover-central-1440.png` and
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/09-desktop-inheritance-gods-1440.png`
- Final mobile opening:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/13-mobile-opening-390-final.png`
- Final compact opening:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/12-mobile-opening-320-final.png`
- Final mobile interaction states:
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/07-mobile-mobility-interaction-390.png` and
  `/Users/bard/Documents/Eurocentric/site/.audit-steppe/14-mobile-inheritance-gods-390.png`

The matched comparison confirms that Farmers is visually unchanged while Steppe retains the shared
EUROPA frame, typography, route plate and editorial hierarchy. Steppe introduces a distinct cold-to-warm
daylight progression, lower horizons, mobile households, kurgan shadows, fire and a repeated circle that
develops from camp to solid wheel, mound and solar/religious inheritance. Scene scale alternates between
landscape, close material detail, overhead monument, direct confrontation and firelit gathering. The
confrontation is legible without gore, mounted invasion imagery or fantasy equipment.

### Visual iterations resolved

- P1: The initial inheritance map was too pale and its branches did not communicate the three layers.
  Increased relief contrast, strengthened routes, added origin/destination labels and differentiated
  people, language and religion with solid, dashed and dotted treatments.
- P2: The first desktop mobility control read as a semicircle. Closed it into a complete wheel while
  retaining the linear mobile control.
- P1: At 320 × 568 the opening title started beneath the fixed route plate. Added a compact-height layout
  that keeps the full title, thesis and opening action visible without horizontal overflow.
- P1: Mobile route links inherited 38 px targets. Scoped Steppe’s route plate to 44 px links and adjusted
  the sticky image and compact opening offsets without changing Farmers.

No unresolved P0, P1 or P2 visual differences remain.

## Steppe extension — content and interaction

- The chapter contains exactly seven movements and three principal interactions: mobility, regional
  paternal-line turnover and Eurasian inheritance.
- Every movement includes two developed paragraphs, a “What survived” record and scene-level sources.
- The mobility scene uses people on foot, herds and ox-drawn solid-wheel wagons. The public evidence note
  dates widespread horse-based mobility to about 2200 BC and the early imagery contains no saddles,
  stirrups, armour, swords or chariots.
- Turnover separates Central Europe, Bohemia and Iberia instead of inventing a continental replacement
  percentage. Each view identifies aggregate ancestry, local paternal lines and incoming paternal lines.
- The inheritance map separates population movement, language transmission and selected religious
  correspondences. It explicitly distinguishes linguistic inheritance from the strong functional and
  poetic parallel of the divine twins.
- Direct violence is represented once in a plausible settlement takeover; long-duration violence is
  carried by burials, authority markers and sampled paternal-line turnover.
- Main-road entry lands on `/chapters/steppe-comes-west/`; both header and footer return to
  `/#steppe-comes-west`; the ending continues to `/#bronze-europe`.
- Direct fragment loads restore the correct movement. All three interactions update pressed state,
  explanatory detail and their visual record in the browser.

## Steppe extension — accessibility and verification

- At 390 × 844 and 320 × 568 there is no horizontal overflow. Header, route, opening and interaction
  controls meet the 44 px touch-target requirement.
- Interaction choices are native buttons with visible `:focus-visible` treatment, grouped accessible
  names, `aria-pressed` state and polite live regions. Evidence is native disclosure content.
- Static production HTML contains all seven movements, all evidence text and the initial content for all
  three interactions before JavaScript enhancement.
- Shared and Steppe-specific reduced-motion rules remove parallax transforms and collapse nonessential
  transition durations while retaining every informative state.
- The browser console was checked on the chapter opening, inheritance state, 320 px layout and main-road
  navigation with no warnings or errors.
- `npm run check`: 0 errors, warnings or hints.
- `npm run validate:content`: 24 scenes, 2 deep chapters, 63 places, 50 sources and 4 registered shared
  assets.
- `npm run test:chapter`: Farmers regression and Steppe chapter checks passed.
- `npm run build`: passed; Farmers and Steppe routes were generated in a four-page static build.

final result: passed
