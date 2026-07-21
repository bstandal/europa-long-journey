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

---

# Chapter 20 design QA

## Current release scope

Chapter 20, “Rivalry and the Industrial Breakthrough.”

Reference and matched implementation:

- `source-assets/chapters/rivalry-industrial-breakthrough/opening-capital-line.png`
- `design/qa/chapter-20-source-vs-desktop-hero.jpg`
- `design/qa/chapter-20-desktop-hero.png`
- `design/qa/chapter-20-mobile-hero.png`
- `design/qa/chapter-20-mobile-ending.png`

Tested at 1536 × 1024 and 390 × 844. The black industrial drawing, copper
capital line, railway prospectus and signal lamps remain legible behind the
opening copy. The portrait composition retains the railway and legal line
without widening the document beyond 390 pixels.

Twelve movements and sixteen dedicated raster scenes load without decode
failure. “Turn the shaft”, “Drive the whole floor”, “Release scheduled train”
and “Close liability boundary” reach their final states. The final interaction
keeps the registered company, transferable share and limited-liability boundary
distinct. The ending resolves to `/chapters/european-world/`.

Local result: passed.

---

# Chapter 21 design QA

## Current release scope

Chapter 21, “The European World.”

Reference and matched implementation:

- `source-assets/chapters/european-world/01-the-sea-acquires-a-law.png`
- `design/qa/chapter-21-source-vs-desktop-hero.jpg`
- `design/qa/chapter-21-desktop-hero.png`
- `design/qa/chapter-21-mobile-hero.png`
- `design/qa/chapter-21-mobile-ending-v3.png`

Tested at 1536 × 1024 and 390 × 844. The opening holds the Atlantic patrol,
Admiralty chart and switchboard in one readable field. Fourteen movements and
the dedicated portrait ending load at their declared dimensions. “Join
timetable”, “Keep protocol”, “Receive inheritance” and “Complete circuit” reach
their final states. The route panel closes with Escape and returns focus to its
toggle. The ending resolves to `/chapters/europe-at-war/`.

Local result: passed.

---

# Chapter 22 design QA

## Current release scope

Chapter 22, “The European Civil War.”

Reference and matched implementation:

- `source-assets/chapters/europe-at-war/01-an-empire-is-proclaimed-in-a-conquered-palace.png`
- `design/qa/chapter-22-source-vs-desktop-hero.jpg`
- `design/qa/chapter-22-desktop-hero.png`
- `design/qa/chapter-22-mobile-hero.png`
- `design/qa/chapter-22-mobile-holocaust-archival-static.png`
- `design/qa/chapter-22-mobile-ending.png`

Tested at 1536 × 1024 and 390 × 844. The opening preserves the split atlas,
Versailles interior and vermilion fracture. Fourteen movements load without
horizontal overflow or failed assets. “France moves east and north”, “People
without a state”, “Citizenship stripped” and “The continent lies open” reach
their final states.

Movements 11–14 use the declared archival treatment. The Holocaust sequence is
a set of separate, still 3:2 plates above the prose on mobile. Its images have
no transform, transition, parallax, button, hover reveal or text overlay. Named
family, deportation record, perpetrator map and survivor record retain their
source captions. Provenance is recorded in
`source-assets/chapters/europe-at-war/PROVENANCE.md`.

The route panel opens, closes with Escape and returns focus to its toggle. The
ending resolves to `/chapters/continent-rebuilt/`. Browser warnings and errors:
none.

Local result: passed.

---

# Chapter 23 design QA

## Current release scope

Chapter 23, “The Continent Rebuilt.”

Reference and matched implementation:

- `source-assets/chapters/continent-rebuilt/opening-two-roads-to-1989.png`
- `design/qa/chapter-23-source-vs-desktop-hero.jpg`
- `design/qa/chapter-23-desktop-hero.png`
- `design/qa/chapter-23-mobile-hero.png`
- `design/qa/chapter-23-mobile-polish-pope.png`
- `design/qa/chapter-23-mobile-ending.png`

Tested at 1536 × 1024 and 390 × 844. The paired postwar roads remain distinct
through twelve movements. The Polish pope movement keeps the public gathering,
pilgrimage route and documentary restraint visible on mobile. “Multiply the
shipment”, “Keep the rule operative”, “Let the nation appear” and “Survive
martial law” reach their final states. The route panel returns focus after
Escape, the console remains clean and the ending resolves to
`/chapters/europe-returns/`.

Local result: passed.

---

# Chapter 17 design QA

## Current release scope

Chapter 17, “The Scientific Revolution.”

Reference:

- `source-assets/chapters/scientific-revolution/opening-measured-page.png`
- `source-assets/chapters/scientific-revolution/opening-measured-page-mobile.png`
- `source-assets/chapters/scientific-revolution/ending-europe-makes-knowledge-cumulative.png`

Matched implementation:

- `design/qa/chapter-17-desktop-hero-v2.png`
- `design/qa/chapter-17-source-vs-desktop-hero.jpg`
- `design/qa/chapter-17-mobile-hero.png`
- `design/qa/chapter-17-mobile-public-circuit.png`
- `design/qa/chapter-17-mobile-ending-with-art-v2.png`
- `design/qa/chapter-17-mobile-ending-top.png`
- `design/qa/chapter-17-desktop-ending-v2.png`

Tested viewports:

- Desktop: 1440 × 900
- Mobile: 390 × 844

## Visible comparison

The rendered opening preserves the measured-page source: ruled folios, brass
dividers, anatomical plate, astronomical tables and the red line joining
observation to proof. The desktop source and implementation were compared at
the same crop. The dedicated portrait source keeps the instruments, page edge
and title field inside the mobile frame.

The closing scene places ledgers, instruments, correspondence and Amsterdam's
harbour behind the conclusion. The desktop gradient leaves the working table
legible while holding a quiet field for the title and paragraph. The mobile
crop follows the table's centre and darkens toward the chapter handoff.

## Findings and resolutions

- P1 — Chapter-v2 endings declared a closing image in chapter data but the
  shared footer style never rendered it. The footer now composes the declared
  desktop and mobile image variables beneath responsive reading gradients.
- Regression checks on chapters 10 and 11 confirm their existing closing
  images, titles, prose and chapter handoffs remain legible at desktop and
  mobile widths.
- All twelve movement images, the two opening sources and the ending complete
  with non-zero intrinsic dimensions. The corrected Hooke scene uses an adult
  flea, and the Newton–Halley scene addresses Newton at Trinity College.
- The ending hands directly to `/chapters/dutch-republic/`.

## Interaction and navigation checks

- “Open the two books of 1543” reaches “Rule the gutter” and makes the ruled
  line the chapter's measuring spine.
- “Carry the measure into law” reaches the common operation of measurement,
  comparison and mathematical form.
- “Make the invisible visible” reaches the focused microscope and expands the
  scale of observable fact.
- “Send a result into public” completes the answerable circuit through a
  received reply.
- The interactions expose 4, 4, 3 and 5 distinct button states.
- The route panel opens within 390 pixels, closes with Escape and restores
  focus to its toggle.
- Document and viewport widths both measure 390 pixels on mobile. No requested
  chapter image fails to load.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed

---

# Chapter 12 design QA

## Current release scope

Chapter 12, “The Empire of Many Liberties.”

Reference:

- `source-assets/chapters/empire-many-liberties/08-diet-in-session.png`
- `source-assets/chapters/empire-many-liberties/08-diet-in-session-mobile.png`

Matched implementation:

- `design/qa/chapter-12-desktop-hero-v2.png`
- `design/qa/chapter-12-source-vs-desktop-hero-v2.jpg`
- `design/qa/chapter-12-mobile-hero-v3.png`
- `design/qa/chapter-12-desktop-crown-final-v3.png`
- `design/qa/chapter-12-mobile-crown-interaction-v2.png`
- `design/qa/chapter-12-mobile-ending.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The opening uses the selected Diet chamber on desktop and its dedicated portrait
source on mobile. The final side-by-side comparison confirms the same assembly,
central document, chamber depth and subdued brown-black palette in the source
and implementation. The reading gradient preserves the officials and table
while giving the title a stable dark field.

Typography, rules, spacing and active states use the chapter system’s ivory,
aged gold, display serif and compact sans-serif metadata. The opening title,
claim and entry action fit inside both tested viewports. The mobile page reports
390 pixels for both document width and viewport width.

## Findings and resolutions

- P1 — The desktop opening initially inherited movement 01 and showed Otto’s
  coronation instead of the selected Diet source. The chapter-v2 opening now
  uses its declared desktop and mobile opening images at the specified crop.
- P1 — The mobile title’s final line was clipped at 390 pixels. A bounded
  chapter-specific title size keeps all three lines within the viewport without
  changing the desktop hierarchy.
- P2 — The four place labels in “Carry the crown” were distorted by the
  non-proportional SVG map and collided around the Rhine–Danube corridor.
  Responsive HTML markers now retain the route coordinates while setting the
  labels on four clear sides of the cluster. The final desktop and mobile
  screenshots show Aachen, Goslar, Regensburg and Frankfurt without overlap.
- All twelve movement scenes load their intended 1536-pixel landscape source or
  1024-pixel portrait source. No requested movement image fails to decode.
- The ending and next-chapter handoff remain inside the mobile viewport.

## Interaction and navigation checks

- “Carry the crown” reaches “Frankfurt · Realm assembly” and changes the record
  to “The circuit closes in law.”
- “Elect without a dynasty” reaches “Proclaim King of the Romans” and returns
  the chosen office.
- “Pass an imperial decision” reaches “Confirm Imperial recess” and returns
  consent to the crown.
- “Keep the peace in many laws” reaches “Remain · Regensburg · 1663” and makes
  the continuous assembly visible.
- Each interaction exposes four or more distinct states through semantic
  buttons and `aria-pressed`.
- The chapter route opens, closes with Escape and restores focus to its toggle.
- The in-app browser log contains no warnings or errors after the interaction
  pass.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed

---

# Chapter 14 design QA

## Current release scope

Chapter 14, “Europe Turns Seaward.”

Reference:

- `source-assets/chapters/europe-turns-seaward/01-portugal-takes-african-gate.png`
- `source-assets/chapters/europe-turns-seaward/01-portugal-takes-african-gate-mobile.png`

Matched implementation:

- `design/qa/chapter-14-desktop-hero.png`
- `design/qa/chapter-14-source-vs-desktop-hero.jpg`
- `design/qa/chapter-14-mobile-hero.png`
- `design/qa/chapter-14-mobile-unrolled-ocean.png`
- `design/qa/chapter-14-mobile-ending.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The source and implementation retain the same open portolan, compass, Ceuta
harbour, Portuguese shipping and dark western field. The title sits in the
source’s negative space while the ship, city and chart remain visible. The
mobile opening uses its portrait source and keeps the ship, fortress and chart
inside the first screen.

The two-line title, claim and action fit at both viewports. At 390 pixels the
document has no horizontal overflow. The slate-blue ocean, parchment, iron and
brass palette is carried through existing chapter tokens and state borders.

## Findings and resolutions

No actionable P0, P1 or P2 findings remain.

- The desktop and mobile openings use their declared source assets and crops.
- The final “Unroll the ocean” state keeps Lisbon, the Guinea coast, the Cape of
  Good Hope, Malindi and Calicut legible over the chart. The responsive marker
  treatment removes the distortion present in the earlier SVG labels.
- All twelve movement scenes load with non-zero intrinsic width. The ending
  hands directly to `/chapters/reformation/`.
- The account places Ceuta in 1415 and describes the eastern trade problem as
  strategic cost and intermediary dependence rather than claiming that one
  event simply closed the land route.

## Interaction and navigation checks

- “Read the Atlantic wind” reaches “Enter the Tagus” and preserves the return
  observation.
- “Unroll the ocean” reaches Calicut through six cumulative states.
- “Divide an unmeasured ocean” reaches the post-1500 survey state.
- “Arm the sea road” reaches the inspected Hormuz–Goa–Malacca circuit.
- The interactions expose 4, 6, 4 and 5 distinct button states.
- The route panel opens within 390 pixels, closes with Escape and restores focus
  to its toggle.
- No failed chapter image or horizontal overflow was measured during the full
  mobile pass.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed

---

# Chapter 24 design QA

## Current release scope

Chapter 24, “Europe Returns.”

Reference and matched implementation:

- `source-assets/chapters/europe-returns/opening-the-eastern-line.png`
- `design/qa/chapter-24-source-vs-desktop-hero.jpg`
- `design/qa/chapter-24-desktop-hero.png`
- `design/qa/chapter-24-mobile-hero.png`
- `design/qa/chapter-24-mobile-ending.png`

Tested at 1536 × 1024 and 390 × 844. The opening keeps European Union law in
cobalt, NATO collective defence in ice blue and Russian aggression in iron red.
The desktop composition preserves the source atlas at the same viewport. The
portrait source retains separate legal and defensive lines behind the title,
claim and first action without horizontal overflow.

Twelve movements and twenty-four raster variants load at their declared
dimensions. “Ratify accession”, “Full-scale invasion”, “Connect lawful support”
and “Record the receipt” reach their final states. EU candidacy and NATO Article
5 status remain separate in the interaction copy. The route panel opens,
closes with Escape and restores focus to its toggle. Browser warnings and
errors: none.

The ending uses its dedicated portrait asset and states the status date as 20
July 2026. Cluster 1 and Cluster 6, total EU support, the nine eastern-flank
battlegroups and the Ankara support pledge were checked against current Council,
Commission and NATO records on 21 July 2026.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints. Content
validation covers 24 scenes, 24 deep chapters, 63 interactive places, 412
sources and 17 asset records. All twenty-four chapter checks pass and the static
build emits all 29 routes.

Local result: passed.

---

# Chapter 18 design QA

## Current release scope

Chapter 18, “The Dutch Republic.”

Reference:

- `source-assets/chapters/dutch-republic/opening-exchange-hall.png`
- `source-assets/chapters/dutch-republic/opening-exchange-hall-mobile.png`
- `source-assets/chapters/dutch-republic/ending-exchange-keeps-speaking-mobile.png`

Matched implementation:

- `design/qa/chapter-18-desktop-hero.png`
- `design/qa/chapter-18-source-vs-desktop-hero.jpg`
- `design/qa/chapter-18-mobile-hero.png`
- `design/qa/chapter-18-mobile-exchange-news.png`
- `design/qa/chapter-18-mobile-ending-v2.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The opening preserves the exchange-hall source: rain-dark brick arcades,
public notices, ledgers, coin packets and the harbour map entering the table.
The desktop title uses the source's empty western field while clerks, traders
and the active courtyard remain visible. The portrait source keeps the arcade,
central gate and working desk behind the mobile title.

The chapter carries the same slate, brick, black wool and restrained brass
palette through assembly rooms, shipyards, polders, the bank and the bourse.
The closing image joins the exchange bell, newspapers and the road to London
without breaking the established documentary realism.

## Findings and resolutions

No actionable P0, P1 or P2 findings remain.

- The desktop source and implementation were compared at the same
  1536 × 1024 crop; the reading gradient preserves the source composition.
- All twelve movement images, both opening sources and both ending sources
  decode at their intended dimensions. The two lazy-loaded scenes omitted by
  the first scroll pass were opened through the chapter route and completed at
  1536 × 1024.
- The mobile document width and viewport width both measure 390 pixels.
- The ending hands directly to `/chapters/enlightenment-public-opinion/`.

## Interaction and navigation checks

- “Assemble the provinces” reaches unanimous provincial consent.
- “Make capital permanent” transfers an investor's claim while the common
  enterprise continues.
- “Clear the exchange” turns delayed shipping news into a contested price.
- “Command the common water” joins the Water Line to the sea perimeter.
- The interactions expose 4, 4, 4 and 4 distinct button states.
- The route panel fills the 390-pixel viewport, closes with Escape and restores
  focus to its toggle.
- The browser console reports no warnings or errors.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed

---

# Chapter 19 design QA

## Current release scope

Chapter 19, “The Enlightenment.”

Reference:

- `source-assets/chapters/enlightenment-public-opinion/opening-continent-in-conversation.png`
- `source-assets/chapters/enlightenment-public-opinion/opening-continent-in-conversation-mobile.png`
- `source-assets/chapters/enlightenment-public-opinion/ending-europe-learns-to-judge-aloud-mobile.png`

Matched implementation:

- `design/qa/chapter-19-desktop-hero.png`
- `design/qa/chapter-19-source-vs-desktop-hero.jpg`
- `design/qa/chapter-19-mobile-hero-v2.png`
- `design/qa/chapter-19-mobile-cross-reference.png`
- `design/qa/chapter-19-mobile-ending-v2.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The opening preserves the source's London coffeehouse table, marked papers,
bundled correspondence and open street. The desktop gradient follows the dark
wall at left while the carrier, readers and active table remain legible. The
portrait source keeps the paper circuit behind the title and places the action
above the first fold.

The chapter maintains one document-led visual language through presses,
libraries, workshops, ministries and assemblies. The closing image gathers
marked pages around a working table while the Paris street and early iron
structure remain visible beyond it.

## Findings and resolutions

- P1 — The initial mobile title used the shared 56.16-pixel size; the word
  “Enlightenment” widened the document to 396 pixels and clipped its final
  letters. A chapter-specific responsive size now fits the 346-pixel reading
  field and restores the 390-pixel document width.
- Interaction copy no longer speaks about “the reader” as an interface actor.
  Subjects, objects and cross-references now carry each result directly.
- All twelve movement images, both opening sources and both ending sources
  decode at their intended dimensions. Lazy-loaded movement images 03 and 04
  were brought into view and completed at 1536 × 1024.
- The ending hands directly to
  `/chapters/rivalry-industrial-breakthrough/`.

## Interaction and navigation checks

- “Make the coffeehouse paper” reaches the evening essay and its recurring
  examination of public manners.
- “Compare the laws” reaches the Habsburg administrative route.
- “Cross-reference the world” reaches the redrawn tree of knowledge.
- “Follow one argument” reaches proportionate punishment and Tuscan reform.
- The interactions expose 4, 4, 4 and 3 distinct button states.
- The route panel fills the 390-pixel viewport, closes with Escape and restores
  focus to its toggle.
- Document and viewport widths both measure 390 pixels after the title fix.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed

---

# Chapter 11 design QA

## Current release scope

Chapter 11, “The Hanseatic North.”

Reference:

- `source-assets/chapters/hanseatic-north/01-bryggen-before-sunrise.png`
- `source-assets/chapters/hanseatic-north/01-bryggen-before-sunrise-mobile.png`

Matched implementation:

- `design/qa/chapter-11-desktop-1536x1024.png`
- `design/qa/chapter-11-desktop-comparison-final.png`
- `design/qa/chapter-11-mobile-390x844.png`
- `design/qa/chapter-11-mobile-comparison-final.png`
- `design/qa/chapter-11-mobile-signature-state.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The production opening preserves the generated Bryggen composition, including
the receding timber fronts, wet quay, working boat, stockfish cargo and the
human group around the scales. The desktop treatment retains the image’s
harbour depth beneath a restrained reading gradient. The dedicated mobile
source keeps both the Bryggen roofline and the weighing scene legible instead of
forcing the landscape source into a destructive crop. The title, claim and
entry action remain fully inside the first 844 mobile pixels.

## Findings and resolutions

- The chapter title and opening claim fit without clipping at both tested
  viewports, with zero document-level horizontal overflow at 390 pixels.
- The fourth movement’s architectural interaction remains readable as a
  two-column mobile control and exposes the communal hall without displacing
  its explanation.
- The covenant map uses its dedicated portrait source on mobile. The full
  four-town field remains visible above the selected council state rather than
  being cropped into an illegible fragment.
- All twelve movement images use dedicated raster assets and descriptive alt
  text. Loaded desktop and mobile sources report their expected intrinsic
  dimensions; no requested asset returns a failed image.

## Interaction and navigation checks

- “Carry the northern year” changes to “Return cargo,” updates
  `aria-pressed`, and replaces the cargo, season and outcome record.
- “Open a Bryggen yard” changes to “Schøtstue” and exposes its communal task,
  rule and explanatory record.
- “Raise the covenant” changes to “Consenting action” and reveals the final
  locally authorized coalition state.
- “Hold the four Kontore” changes to “Novgorod” and replaces the goods, office,
  dependency and intelligence record.
- The mobile route panel opens, closes with Escape and restores focus to its
  toggle.
- Chapter 10 hands off to `/chapters/hanseatic-north/`; Chapter 11 hands off to
  `/#empire-many-liberties`.
- The in-app browser log contains no warnings or errors after the complete
  interaction and navigation pass.

## Build verification

Astro diagnostics, content validation, chapter structure tests and the
production build complete without errors.

final result: passed

---

# Chapter 10 design QA

## Current release scope

Chapter 10, “The Medieval Commercial Revolution.”

Reference:

- `source-assets/chapters/medieval-commercial-revolution/01-ledger-road.png`

Matched implementation:

- `design/qa/chapter-10-desktop-1536x1024.png`
- `design/qa/chapter-10-desktop-comparison-final.png`
- `design/qa/chapter-10-mobile-390x844.png`
- `design/qa/chapter-10-voyage-interaction-1536x1024.png`
- `design/qa/chapter-10-mobile-route-panel-390x844.png`

Tested viewports:

- Desktop: 1536 × 1024 and 1440 × 1024
- Mobile: 390 × 844

## Visible comparison

The production hero preserves the generated source composition, tonal range, harbour architecture, ledger table and human focal group. The page uses the source’s dark negative space for the title and keeps the working merchants visible on both desktop and mobile. The dedicated mobile source maintains the subject rather than relying on a destructive desktop crop.

## Findings and resolutions

- P1 — The first title treatment concatenated title lines and overflowed the right edge. Resolved by restoring semantic spaces, block-level title lines and a bounded responsive type scale.
- P1 — The voyage allocation grid reserved a third empty column and repeated the active outcome description. Resolved with a two-party grid and one live outcome description.
- P2 — The sixth Champagne fair wrapped onto an isolated row. Resolved by fitting all six dated stops on one desktop rail while retaining the two-column mobile rail.
- P2 — The chapter’s limited-liability passage read as a modern legal disclaimer. Resolved as affirmative narrative: Europe discovers the commercial power of a voyage-bound form, then enlarges the principle in later corporate law.

## Interaction and responsive checks

- “Finance the voyage” updates from safe return to total loss, including loss, household exposure and accessible value text.
- “Keep the fair cycle” changes pressed state, visible record, outcome and chapter state.
- The mobile route panel opens, closes with Escape and returns focus to its toggle.
- Main-journey entry and chapter-ending handoff navigate to the intended destinations.
- No horizontal overflow at 390 px.
- No browser console warnings or errors.

final result: passed

---

# Chapter 13 design QA

## Current release scope

Chapter 13, “The Frontiers Hold.”

Reference:

- `source-assets/chapters/europe-holds-the-line/01-kingdom-falls-one-campaign.png`
- `source-assets/chapters/europe-holds-the-line/01-kingdom-falls-one-campaign-mobile.png`

Matched implementation:

- `design/qa/chapter-13-desktop-hero.png`
- `design/qa/chapter-13-source-vs-desktop-hero.jpg`
- `design/qa/chapter-13-mobile-hero.png`
- `design/qa/chapter-13-mobile-frontier-turn.png`
- `design/qa/chapter-13-mobile-ending.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The opening preserves the source’s long column, exposed coastal road, distant
city and discarded royal seal. Its reading gradient follows the empty western
field and leaves the advancing force legible. The desktop source and rendered
opening match at the same 1536 × 1024 viewport. The portrait source keeps the
road, city and forward standard inside the mobile frame.

The title, claim and action fit without clipping. At 390 pixels the title forms
three deliberate lines, the action remains above the fold and document width
equals viewport width. The frontier palette uses iron black, ash, old bronze
and restrained alarm red through existing chapter tokens.

## Findings and resolutions

No actionable P0, P1 or P2 findings remain.

- The shared chapter-v2 opening correction selects the declared frontier hero
  rather than movement-stage state.
- The responsive map-marker correction keeps the final Vienna–Karlowitz hinge
  legible on desktop and mobile. The four final labels do not collide.
- All fourteen movement sections and the ending use dedicated raster scenes.
  Every requested frontier image completes with a non-zero intrinsic width.
- The final link resolves to `/chapters/europe-turns-seaward/`.

## Interaction and navigation checks

- “Hold the northern valleys” reaches “Move the line” and turns refuge into a
  kingdom capable of recovery.
- “Answer the eastern call” reaches Jerusalem and updates the expedition’s
  final record.
- “Feed the military frontier” reaches “Extend the watch” and joins village,
  beacon and fortress.
- “Turn the frontier” reaches Karlowitz and moves the recognised frontier
  beyond most of Hungary.
- The four interactions expose 4, 5, 5 and 5 distinct button states.
- The route panel opens to the full 390-pixel width, closes with Escape and
  restores focus to the route toggle.
- No horizontal overflow or failed chapter image was measured after the full
  mobile pass.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed

---

# Chapter 15 design QA

## Current release scope

Chapter 15, “The Reformation.”

Reference:

- `source-assets/chapters/reformation/opening-burned-empire.png`
- `source-assets/chapters/reformation/opening-burned-empire-mobile.png`

Matched implementation:

- `design/qa/chapter-15-desktop-hero.png`
- `design/qa/chapter-15-source-vs-desktop-hero.jpg`
- `design/qa/chapter-15-mobile-hero-v2.png`
- `design/qa/chapter-15-mobile-war-table.png`
- `design/qa/chapter-15-mobile-ending.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The rendered opening preserves the source’s burned imperial map, abandoned
counters, congress papers, dividers and waiting diplomats. The title occupies
the dark left field while the map’s burned edge remains the visual hinge. The
portrait source retains the full table depth and scorched centre on mobile.

The single-line desktop title, claim and action fit inside the first viewport.
On mobile the final title is scaled to the available 346-pixel reading width.
The page now reports 390 pixels for both viewport and document width.

## Findings and resolutions

- P1 — The first mobile pass rendered “The Reformation” at 56.16 pixels inside
  a no-wrap title line, widening the document to 455 pixels and clipping the
  word. A bounded 44.07-pixel chapter title restores the full word and removes
  horizontal overflow.
- P2 — Münster and Osnabrück collided in the final war-table map. The two
  congress cities now take opposite label positions, while “Imperial estates”
  sits below the connecting line. All three labels remain clear at 390 pixels.
- Fourteen movement scenes, the dedicated opening sources and the ending use
  raster assets matched to the Burned Empire direction. No requested chapter
  image fails to decode.
- The ending hands directly to `/chapters/habsburg-europe/`.

## Interaction and navigation checks

- “Pull the print run” reaches “Fold and carry” and leaves copies beyond any
  single seizure.
- “Build a confessional territory” reaches the standing court.
- “Read the war table” exposes seven dated states and ends with law remaining
  after the counters withdraw.
- “Make the peace” binds the three settlements into one guaranteed peace.
- The interactions expose 4, 4, 7 and 4 distinct button states.
- The route panel opens within 390 pixels, closes with Escape and restores focus
  to its toggle.
- No failed chapter image or horizontal overflow remains after the full mobile
  pass.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed

---

# Chapter 16 design QA

## Current release scope

Chapter 16, “Habsburg Europe.”

Reference:

- `source-assets/chapters/habsburg-europe/opening-braided-danube.png`
- `source-assets/chapters/habsburg-europe/opening-braided-danube-mobile.png`

Matched implementation:

- `design/qa/chapter-16-desktop-hero.png`
- `design/qa/chapter-16-source-vs-desktop-hero.jpg`
- `design/qa/chapter-16-mobile-hero.png`
- `design/qa/chapter-16-mobile-imperial-journey.png`
- `design/qa/chapter-16-mobile-ending.png`

Tested viewports:

- Desktop: 1536 × 1024
- Mobile: 390 × 844

## Visible comparison

The opening preserves the source’s Danube, Vienna skyline, bridge, railway and
four braided documentary colours. The seals, telegraph register and common map
remain visible beneath the reading gradient. The portrait source keeps the
bridge and braid aligned behind the mobile title.

The two-line title, claim and action fit at both viewports. The mobile document
width equals the 390-pixel viewport. Gold is limited to fine rules and active
states while burgundy, blue, green and black-gold carry the composite monarchy
through the existing theme tokens.

## Findings and resolutions

No actionable P0, P1 or P2 findings remain.

- The desktop source and rendered opening match at the same 1536 × 1024
  viewport.
- The final imperial-journey map keeps Zagreb/Agram, Lake Balaton and Budapest
  readable over the timetable and route board.
- All fourteen movement scenes complete with non-zero intrinsic width. The
  dedicated portrait source appears for the railway movement on mobile.
- The ending hands directly to `/chapters/scientific-revolution/`.

## Interaction and navigation checks

- “Assemble the three crowns” reaches “Join without merging.”
- “Put the realm into service” reaches the school that reproduces its skills.
- “Balance the Dual Monarchy” adds the Croatian constitutional layer.
- “Follow one imperial journey” reaches Zagreb–Budapest and preserves the
  documented constitutional difference along the shared route.
- The interactions expose 4, 4, 5 and 4 distinct button states.
- The route panel opens within 390 pixels, closes with Escape and restores focus
  to its toggle.
- No failed chapter image or horizontal overflow was measured during the full
  mobile pass.

## Build verification

Astro diagnostics complete with zero errors, warnings or hints.

final result: passed
