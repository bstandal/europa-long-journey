# Chapter 07 production control

## Selected direction

**The Written Commonwealth** is the binding visual source for Chapter 07, *Europe Reborn*. The chapter treats writing, travel, reused Roman material, Christian institutions and negotiated kingship as the connective tissue of a Europe without one western empire.

Reference:

- `../../chapter-07-visual-prototype/design/reference-option-2.png`
- `../../chapter-07-visual-prototype/public/assets/chapter-07-written-commonwealth.png`

## Visual thesis

A ruled manuscript line becomes a route, a border, a dynastic division and a line of transmission. The chapter moves from the emptied apparatus of western empire toward a network of courts, bishoprics and monasteries that can copy, carry and adapt shared forms across political frontiers.

## Locked material language

- Matte charcoal and soot-black framing
- Vellum, stitched codices, wax tablets and iron styli
- Rough limewashed masonry and reused Roman stone
- Dark oak, iron fittings and modest candlelight
- Muted monastic green, oxidised bronze, dusty madder and restrained Carolingian gold
- Round Roman and pre-Romanesque arches only
- Early medieval dress, hair, armour, buildings and objects appropriate to each named place and date

## Exclusions

- No Gothic or pointed arches
- No high-medieval castles, plate armour, heraldic surcoats or fantasy crowns
- No generic “Dark Ages” ruin porn
- No clean modern paper, quill clichés in every frame or floating decorative maps
- No invented text, pseudo-Latin lettering, captions, borders or watermarks inside images
- No monumental spectacle unless the movement concerns an actual court, church or assembly

## Image grammar

- Cinematic historical reconstruction with documentary restraint
- Natural human scale; work, negotiation, travel and ritual over heroic posing
- Camera near table, threshold, road or assembly edge
- Strong foreground evidence object; middle-ground human action; deep background place
- Low winter daylight, hearth or candlelight; no theatrical orange-and-teal grade
- Leave the darker third of alternating frames available for chapter copy on desktop
- Every scene must remain legible when centre-cropped on a narrow screen

## Scene asset schedule

All desktop scenes target 1536×1024 landscape. Files are stored in `public/assets/chapters/europe-reborn/`.

1. `01-crown-leaves-west.png` — Tours, c. 500. A Gallo-Roman cleric records rents and petitions at a reused civic basilica while a messenger rides into a muddy post-imperial street. Copy space left. The corrected prototype image is the source asset.
2. `02-bishop-keeps-city.png` — Tours, c. 573. Bishop, deacon, widows and local petitioners divide grain and hear a dispute in a former Roman reception hall. Copy space right.
3. `03-frank-enters-font.png` — Reims, traditional date c. 496. Clovis stands waist-deep in a large late-antique baptismal pool with Bishop Remigius and a restrained Frankish retinue; ritual, not triumph. Copy space left.
4. `04-rule-orders-day.png` — Monte Cassino, c. 540. Dawn monastic workshop: one monk reads a rule, others copy a codex, repair tools and prepare bread; ordered labour. Copy space right.
5. `05-king-receives-oil.png` — Pippin’s anointing, 754. A Frankish king kneels in a modest basilica while a bishop applies oil; magnates and clerics witness the compact. Copy space left.
6. `06-saxon-frontier.png` — Saxony, 772–804. A guarded baptism and oath beside a timber church and felled sacred grove; Frankish soldiers visible enough to show coercion without melodrama. Copy space right.
7. `07-word-travels.png` — Carolingian road, c. 790. A mounted messenger exchanges a sealed capitulary with a monastery scribe at a roadside gate; wax tablets and folded vellum in foreground. Copy space left.
8. `08-western-emperor.png` — Old St Peter’s, 25 December 800. Leo III places a simple crown on Charlemagne before the confessio; crowded, candlelit, seen from within the assembly, no Gothic architecture. Copy space right.
9. `09-heirs-divide-realm.png` — Verdun, 843. Three royal delegations negotiate around a waxed board and a parchment itinerary; rivers and estates are marked by counters, not a modern national map. Copy space left.
10. `10-shores-burn-connect.png` — Dorestad or York, c. 870. Scandinavian merchants unload scales, silver and fur at a river quay while a repaired palisade and armed watch recall violence. Copy space right.
11. `11-imperial-claim-east.png` — Quedlinburg, 973. Otto I receives envoys in a timber-and-stone palace church complex; Byzantine silk and a sealed document signal diplomatic connection. Copy space left.
12. `12-rulers-choose-future.png` — Mieszko’s realm, 966. A ruler, spouse, cleric and local elites stand at a timber church foundation where oath, baptismal basin and building plan meet. Copy space right.
13. `13-two-christian-roads.png` — Preslav and Kyiv, 988 as connected worlds. Byzantine-trained clergy and Slavic scribes prepare liturgical books while river travellers arrive; Cyrillic/Glagolitic manuscript culture implied through real writing surfaces without legible invented text. Copy space left.
14. `14-europe-meets-gniezno.png` — Gniezno, 1000. Otto III and Bolesław Chrobry meet beside the shrine of Adalbert with clergy, envoys, gift exchange and a newly organised church; political assembly, not coronation. Copy space right.

## Mobile crops

Dedicated portrait treatments are required for movements 1, 5, 8 and 14 because their ritual focal points cannot survive an arbitrary landscape crop. Other movement images must be tested with `object-position` and receive a dedicated mobile asset only if the historical action is obscured.

## Interaction rhythm

- Movement 2: **Who keeps the city?** — compare the bishop’s inherited civic functions.
- Movement 7: **How does a written command travel?** — follow drafting, copying, carrying and local adaptation.
- Movement 9: **What did Verdun divide?** — expose dynastic shares without projecting modern nations backward.
- Movement 13: **Two roads into Christian Europe** — compare Latin and Byzantine routes without treating 1054 as an accomplished schism.
- Movements 3, 4, 6, 10 and 14 carry lighter three-stop evidence traces.

## QA gate

- The corrected prototype and production opening must be compared at the same desktop viewport.
- Each generated scene must be inspected for date-specific architecture, dress, objects and avoid-list violations.
- Desktop, tablet and mobile screenshots must show complete claim, action and evidence without clipped text.
- Keyboard, focus, reduced-motion and interaction state changes must be checked before the main-journey link is enabled.
