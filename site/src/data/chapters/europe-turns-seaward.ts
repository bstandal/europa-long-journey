import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/europe-turns-seaward";

export const europeTurnsSeaward: ChapterDefinition = {
  slug: "europe-turns-seaward",
  number: "14",
  title: "Europe Turns Seaward",
  openingTitleLines: ["Europe Turns", "Seaward"],
  period: "AD 1415\u20131700",
  claim:
    "Europeans converted the Atlantic from an edge into a road. Repeated voyages, wind knowledge, charts, royal finance and armed ocean-going ships gave small western kingdoms direct strategic access to routes and markets far beyond the reach of any European army on land.",
  openingClaim:
    "Europeans converted the Atlantic from an edge into a road and made the world's oceans an arena of European action.",
  hero: {
    image: `${imageRoot}/01-portugal-takes-african-gate.avif`,
    mobileImage: `${imageRoot}/01-portugal-takes-african-gate-mobile.avif`,
    imageAlt:
      "A salt-stained portolan chart unrolls on a wet table toward Portuguese vessels crossing the Strait of Gibraltar to Ceuta.",
    imagePosition: "center center",
    mobileImagePosition: "64% center",
    visualLabel: "Evidence-led reconstruction \u00b7 the unrolled ocean",
  },
  theme: {
    id: "ocean",
    label: "The unrolled ocean",
  },
  openingAction: "Unroll the ocean",
  mapLabel:
    "The islands, winds, coasts, straits, chart offices and fortified ports through which Europe made the oceans navigable",
  routeImage: "assets/world-relief.jpg",
  sourcesEyebrow:
    "Voyage journals \u00b7 portolan charts \u00b7 crown instructions \u00b7 treaties \u00b7 pilot examinations \u00b7 fort and factory records",
  acts: [
    {
      id: "atlantic-becomes-school",
      number: "I",
      label: "The Atlantic becomes a school",
      period: "AD 1415\u20131460",
      title: "The Atlantic Becomes a School",
      detail:
        "Ceuta, Atlantic islands, fisheries, winds and repeated coastal voyages turn Portugal's western shore into a disciplined base for expansion.",
    },
    {
      id: "coast-opens-ocean",
      number: "II",
      label: "The coast opens into an ocean",
      period: "AD 1453\u20131499",
      title: "The Coast Opens into an Ocean",
      detail:
        "Strategic purpose and accumulated observation carry Portuguese ships beyond the southern end of Africa and directly into the Indian Ocean.",
    },
    {
      id: "routes-enclose-earth",
      number: "III",
      label: "The routes enclose the earth",
      period: "AD 1492\u20131522",
      title: "The Routes Enclose the Earth",
      detail:
        "Westward crossings, treaty claims, new coastlines and the first circumnavigation join Atlantic, Pacific and Indian Ocean geography.",
    },
    {
      id: "voyages-become-systems",
      number: "IV",
      label: "Voyages become systems",
      period: "AD 1500\u20131700",
      title: "Voyages Become Systems",
      detail:
        "Forts, passes, chart offices, companies and rival shipyards convert singular voyages into durable European ocean power.",
    },
  ],
  ending: {
    period: "AD 1700",
    title: "The Coast Has Become a Point of Departure",
    detail:
      "By 1700, charts made in Lisbon, Seville, Amsterdam and London carried routes that no crown could erase. European pilots could cross the Atlantic, round Africa, enter the Indian Ocean and return through a chain of known winds, soundings, ports and archives. Fortified bases and chartered companies projected the power of small states across distances no European field army could traverse. Rivalry kept ships moving after Iberian exclusivity had broken. The same divided Europe that sent fleets around the earth was dividing Latin Christendom at home, where print, territorial government and confessional allegiance would turn theological revolt into a new European contest.",
    image: `${imageRoot}/13-coast-becomes-point-of-departure.avif`,
    nextPeriod: "AD 1517\u20131648",
  },
  returnHash: "europe-turns-seaward",
  nextHash: "reformation",
  nextTitle: "The Reformation",
  movements: [
    {
      id: "portugal-takes-african-gate",
      actId: "atlantic-becomes-school",
      order: 1,
      period: "AD 1415",
      place: "Ceuta",
      title: "Portugal Takes the African Gate",
      thesis:
        "The capture of Ceuta joined crusade, commerce and royal command in Portugal's first permanent foothold beyond Europe.",
      body: [
        "Before dawn on 21 August 1415, Portuguese ships brought King Jo\u00e3o I, his sons and an expeditionary army across the Strait of Gibraltar. Ceuta stood behind walls at the meeting point of the Mediterranean and Atlantic, facing the caravan routes of Morocco and the sea lanes of southern Iberia. The assault took the city in a day. A kingdom with a narrow land frontier had acquired an overseas fortress, and the royal dynasty received a theatre in which crusading honour, noble service and commercial ambition could be directed together.",
        "The customs house revealed the limits of victory. Merchants and caravans could avoid a captured port, while Portugal had to provision and defend Ceuta across the strait. The city offered access to information about Saharan gold and Moroccan politics without delivering command of either. Its exposed garrison turned geography into a continuing expense. Holding the gate therefore sharpened the value of routes that an army could not seize: the Atlantic approaches to West African markets and the long coast that extended beyond familiar sailing.",
        "Portugal answered by making the coast itself an object of sustained royal enterprise. Captains sailed from secure home ports, returned with pilots' reports and prepared the next departure. Prince Henrique became the most durable patron within a larger network of crown officers, merchants, nobles, fishermen and mariners. Their motives included African gold, Christian allies, crusading advantage and profitable trade. European oceanic expansion had begun in 1415, thirty-eight years before Constantinople fell. Ceuta's incomplete success sent Portuguese ambition seaward, where knowledge could advance one voyage at a time.",
      ],
      image: `${imageRoot}/01-portugal-takes-african-gate.avif`,
      mobileImage: `${imageRoot}/01-portugal-takes-african-gate-mobile.avif`,
      imageAlt:
        "A salt-stained portolan chart unrolls toward Portuguese vessels crossing the strait to Ceuta and an occupied customs room beyond.",
      imagePosition: "61% center",
      mobileImagePosition: "67% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "african-gate",
      side: "left",
      sourceIds: ["disney-2009", "newitt-2005"],
      evidence: [
        "Portuguese forces captured Ceuta in August 1415 and retained it as the monarchy's first permanent overseas possession.",
        "The conquest served crusading, dynastic and commercial aims, while diverted caravan traffic prevented the city from yielding the trade its captors expected.",
      ],
      map: { x: 49, y: 30 },
    },
    {
      id: "islands-teach-ocean",
      actId: "atlantic-becomes-school",
      order: 2,
      period: "c. AD 1420\u20131460",
      place: "Madeira, the Azores and Atlantic approaches",
      title: "Islands Teach the Ocean",
      thesis:
        "Settlement made the Atlantic islands into working stations where navigation, provisioning and investment could be repeated.",
      body: [
        "A landing party on Madeira faced steep wooded slopes, fresh water and no ready-made port. Portuguese settlers occupied the island from the early 1420s, cleared ground, cut channels through the hills and built storehouses beside anchorages. Grain, timber and wine supplied early traffic. Sugar then drew mills, irrigation works, merchant capital and coerced labour into a demanding export enterprise. The island required ships to arrive on schedule with tools, people and credit, and to leave with cargo before damp, delay or shortage consumed the season.",
        "Farther west, settlement of the Azores from the 1430s widened the working Atlantic. The islands offered water, livestock, repairs and a position near the broad arc followed by vessels returning from Africa. Every regular passage trained pilots to recognise cloud over land, the colour of shoal water, the set of a current and the sequence of winds across open sea. Crews learned how much food and water a hull could carry, how rig and cargo altered handling, and which failures could be corrected at the next island rather than becoming fatal offshore.",
        "The islands converted exploration into infrastructure. A harbour crew could repair the ship that returned with a damaged yard; a mill and plantation could attract the finance for another hull; a settled community could preserve observations between generations of pilots. Madeira also supplied an early Atlantic pattern in which crown grant, private investment, cultivation and regular shipping reinforced one another. Portugal now possessed a chain of departures and returns west of Europe. That chain taught sailors to leave the coast with confidence and to treat the wind field beyond sight of land as usable geography.",
      ],
      image: `${imageRoot}/02-islands-teach-ocean.avif`,
      imageAlt:
        "Settlers build a harbour, unload barrels and work irrigated terraces on a Portuguese Atlantic island.",
      imagePosition: "64% center",
      mobileImagePosition: "70% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "island-school",
      side: "right",
      sourceIds: ["disney-2009", "newitt-2005", "parker-2012"],
      evidence: [
        "Portuguese settlement of Madeira began in the early 1420s, while sustained settlement in the Azores developed from the 1430s.",
        "Island cultivation, provisioning and regular passages created durable Atlantic stations and accumulated practical knowledge of winds, currents and ship endurance.",
      ],
      map: { x: 45, y: 32 },
    },
    {
      id: "way-home-bends-west",
      actId: "atlantic-becomes-school",
      order: 3,
      period: "AD 1434\u20131460",
      place: "Cape Bojador and the North Atlantic",
      title: "The Way Home Bends West",
      thesis:
        "Portuguese mariners made the open Atlantic a navigational instrument by learning that the surest road home bent away from land.",
      body: [
        "Cape Bojador projected into shoal water beneath haze and a persistent northerly wind. Earlier vessels had turned back before its surf, currents and reputation. In 1434, Gil Eanes passed the cape and returned with evidence that the coast continued beyond it. The achievement removed a practical limit from royal planning. Later captains could receive a destination south of Bojador with the expectation that men, ships and written instructions would come home to report what lay farther on.",
        "Southward sailing revealed the harder problem of return. Near the African coast, winds and currents that assisted a vessel outward could resist its passage north. Portuguese pilots learned to stand west or north-west into the Atlantic, accept days in which home lay apparently farther away, and reach winds that curved the ship toward the Azores and Portugal. This volta do mar joined observation to disciplined trust. The ocean possessed roads, although its roads were moving belts of air and water rather than lines visible from the deck.",
        "No single hull or instrument produced the result. Barcas, caravels and other evolving rigs answered different stages of the work. Compass bearings held a heading; sand glasses and estimated speed supported dead reckoning; the sounding lead tested approaching ground; observation of the sun and stars strengthened latitude practice. Logs and pilots carried the usable pattern ashore. The westward bend turned repeated risk into a route that another captain could follow. Once Portugal could send ships down the African coast and recover them through the open Atlantic, reconnaissance could extend far beyond the range of coastal familiarity.",
      ],
      image: `${imageRoot}/03-way-home-bends-west.avif`,
      imageAlt:
        "Sailors take compass and wind observations as their vessel turns west from the African coast into the North Atlantic.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "atlantic-wind",
      side: "left",
      sourceIds: ["disney-2009", "newitt-2005"],
      evidence: [
        "Gil Eanes passed Cape Bojador in 1434, after which Portuguese voyages extended progressively along the north-west African coast.",
        "The volta do mar used the North Atlantic wind system to make an apparently indirect offshore course the dependable return route to Portugal.",
      ],
      map: { x: 46, y: 36 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "atlantic-wind",
        prompt: "Read the Atlantic wind",
        accessibleSummary:
          "Four route states compare a resisted coast-hugging return with the westward volta do mar that reaches favourable Atlantic winds and carries the vessel home.",
        initialId: "coastal-return",
        records: [
          {
            id: "coastal-return",
            label: "Hold close to Africa",
            period: "Direct course attempted",
            kicker: "The visible road resists",
            detail:
              "The vessel points north along the coast, where opposing wind and current consume water, sailcloth and time.",
            fields: [
              { label: "Heading", value: "Directly toward Portugal" },
              { label: "Wind", value: "Persistent resistance" },
              { label: "Result", value: "Slow, uncertain return" },
            ],
            outcome:
              "The shortest line on the chart proves the weaker road at sea.",
          },
          {
            id: "western-offing",
            label: "Stand west",
            period: "Open Atlantic",
            kicker: "Distance buys a new wind",
            detail:
              "The pilot orders the ship away from land and accepts a longer course toward the north-western Atlantic.",
            fields: [
              { label: "Heading", value: "West and north-west" },
              { label: "Wind", value: "Changing across the ocean field" },
              { label: "Result", value: "Access to the return arc" },
            ],
            outcome:
              "Indirection places the vessel where a favourable wind can act.",
          },
          {
            id: "westerly-belt",
            label: "Take the westerlies",
            period: "Return arc found",
            kicker: "The wind becomes a road",
            detail:
              "Farther north and west, the ship reaches winds that carry it eastward across the ocean toward the Azores and Iberia.",
            fields: [
              { label: "Heading", value: "Curving east" },
              { label: "Wind", value: "Favourable westerly flow" },
              { label: "Result", value: "Reliable homeward progress" },
            ],
            outcome:
              "The moving atmosphere supplies the road that the coastline denied.",
          },
          {
            id: "lisbon-return",
            label: "Enter the Tagus",
            period: "Observation preserved",
            kicker: "One return improves the next",
            detail:
              "The pilot reports bearings, days and weather so that a later vessel can seek the same offshore arc.",
            fields: [
              { label: "Arrives", value: "Ship, log and experienced crew" },
              { label: "Enters the chart", value: "A repeatable wind route" },
              {
                label: "Result",
                value: "Longer reconnaissance becomes viable",
              },
            ],
            outcome:
              "A successful return enlarges the distance the next voyage can attempt.",
          },
        ],
      },
    },
    {
      id: "eastern-trade-western-price",
      actId: "coast-opens-ocean",
      order: 4,
      period: "c. AD 1453\u20131487",
      place: "Constantinople, Alexandria, Venice and Lisbon",
      title: "The Eastern Trade Has a Western Price",
      thesis:
        "Portugal sought a direct Cape route because Europe bought eastern goods through powerful intermediaries it could neither command nor bypass on land.",
      body: [
        "In Alexandria, pepper and other eastern cargoes entered Mediterranean ships after passing through the Red Sea, Egyptian customs and established merchant networks. Venice carried much of that trade onward into European markets. The Ottoman conquest of Constantinople in 1453 changed the strategic balance in the eastern Mediterranean, while spices continued to reach Europe through Alexandria, the Levant and other Muslim-ruled stages. The established commercial system remained active because its Asian, Muslim and Italian participants possessed ships, capital, ports and relationships built over generations.",
        "Portugal entered this contest from the Atlantic. Its expansion had begun at Ceuta in 1415 and had already advanced through islands, Cape Bojador and West African waters before Mehmed II took Constantinople. Portuguese buyers occupied the expensive western end of routes whose decisive stages lay under other powers. Customs, freight, brokerage and political access accumulated in the price. Gold from West Africa, intelligence about Christian kingdoms and a sea passage toward the sources of spices promised a stronger strategic position than purchasing at the final European exchange.",
        "The crown therefore pursued a deliberate bypass. Agents went overland in search of information about India, the Red Sea and the Christian ruler Europeans called Prester John, while ships carried the physical route down Africa. A Cape passage would avoid the chain of Levantine and Egyptian intermediaries and give Portugal direct armed access to Indian Ocean markets. It would enter a flourishing commercial world rather than replace an empty sea. The purpose was command over Portugal's own approach: ships under its crown, cargo loaded closer to its source and strategic reach beyond every land frontier of Europe.",
      ],
      image: `${imageRoot}/04-eastern-trade-western-price.avif`,
      imageAlt:
        "Pepper passes through Red Sea, Cairo, Alexandria and Venetian hands while a Lisbon price book records the accumulated cost.",
      imagePosition: "65% center",
      mobileImagePosition: "72% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "priced-chain",
      side: "right",
      sourceIds: ["newitt-2005", "pearson-1988", "parker-2012"],
      evidence: [
        "Portuguese Atlantic expansion began with Ceuta in 1415 and continued for decades before the Ottoman conquest of Constantinople in 1453.",
        "Spices continued to reach European markets through Alexandria and the Levant after 1453; the Cape project sought direct access that bypassed established intermediaries.",
      ],
      map: { x: 54, y: 32 },
    },
    {
      id: "dias-finds-turn",
      actId: "coast-opens-ocean",
      order: 5,
      period: "AD 1487\u20131488",
      place: "South Atlantic and the Cape of Good Hope",
      title: "Dias Finds the Turn",
      thesis:
        "Bartolomeu Dias used the open South Atlantic to pass Africa's southern end and prove that the coast opened eastward toward another ocean.",
      body: [
        "Bartolomeu Dias left Portugal in 1487 carrying the record of half a century of southward voyages. His small fleet passed the last surveyed points, set markers on the coast and replenished from a storeship before committing itself beyond dependable support. Near the southern end of Africa, hard weather drove the vessels away from land. Dias continued south and then turned east across water where the coast should have appeared. Its absence supplied the first decisive sign that the ships had passed beneath the continent.",
        "The fleet turned north and met land from the south-east near present-day Mossel Bay. The shoreline now ran eastward, and unfamiliar swell entered from the Indian Ocean. Crews pressed farther before fatigue, damaged equipment and the length of the return route forced a council. On the voyage home Dias saw the great headland whose offshore passage he had already achieved. The cape concentrated the dangers of weather and distance, yet it also carried the promise for which King Jo\u00e3o II named it the Cape of Good Hope.",
        "Dias's route joined coastal reconnaissance to deep-ocean sailing. The decisive movement occurred beyond sight of Africa, where a pilot had to preserve an estimated position through storm and empty horizon. His return gave the crown a tested southern turning point, information about currents and anchorages, and proof that the Atlantic connected with eastern water. Generations of recorded capes could now be read as the approach to a through route. The next expedition required ships built for a longer passage, larger stores, diplomacy on the East African coast and knowledge of the monsoon beyond it.",
      ],
      image: `${imageRoot}/05-dias-finds-turn.avif`,
      imageAlt:
        "Dias's storm-dark vessels cross open water south of Africa and meet the coast again from the east.",
      imagePosition: "55% center",
      mobileImagePosition: "61% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "cape-turn",
      side: "left",
      sourceIds: ["disney-2009", "newitt-2005"],
      evidence: [
        "Dias's 1487\u20131488 expedition sailed out of sight of the African coast, turned east and encountered land after passing the continent's southern end.",
        "The expedition proved an Atlantic-to-Indian Ocean passage and returned with route knowledge used in preparing Vasco da Gama's voyage.",
      ],
      map: { x: 55, y: 69 },
    },
    {
      id: "chart-reaches-calicut",
      actId: "coast-opens-ocean",
      order: 6,
      period: "AD 1497\u20131499",
      place: "Lisbon, the Cape, Malindi and Calicut",
      title: "The Chart Reaches Calicut",
      thesis:
        "Vasco da Gama joined Portuguese Atlantic knowledge to Indian Ocean pilotage and completed Europe's direct sea route to India.",
      body: [
        "Four vessels left the Tagus on 8 July 1497 with provisions, trade goods, interpreters and the knowledge purchased by every previous Portuguese return. Vasco da Gama took a broad sweep into the South Atlantic before turning toward the Cape, using the wind system rather than tracing every mile of African shore. Dias's breakthrough had become an instruction. After rounding the cape, the fleet repaired, moved north along the East African coast and entered ports whose rulers and merchants already understood the ocean linking Africa, Arabia and India.",
        "Each harbour demanded political judgment. Portuguese claims and gifts carried little weight in markets served by established Muslim, Gujarati and other merchant communities. At Malindi, the ruler supplied assistance and an experienced Gujarati pilot. His command of the monsoon crossing connected the newest Atlantic route to Indian Ocean knowledge refined through centuries of seasonal sailing. The fleet departed East Africa on the correct wind and reached Calicut in May 1498. There, brokers, officials and the ruler's court received visitors who had reached India with an unimpressive cargo but an unprecedented European sea road behind them.",
        "Negotiation remained difficult and the homeward voyage killed many crewmen, yet the route survived in ships, journals and trained pilots. Portugal could now dispatch a fleet from Europe to the principal markets of the Indian Ocean without carrying its goods through the Levantine chain. Direct access joined information to force: later fleets could bring better cargo, royal letters, cannon and orders shaped by the first encounter. The chart had unrolled from Lisbon around Africa and opened sideways across the monsoon sea. An Atlantic kingdom possessed a repeatable ocean connection to India, and every European rival could understand the strategic magnitude of the achievement.",
      ],
      image: `${imageRoot}/06-chart-reaches-calicut.avif`,
      imageAlt:
        "An African coast chart opens into the Indian Ocean as an East African pilot's monsoon route reaches Calicut.",
      imagePosition: "57% center",
      mobileImagePosition: "64% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "ocean-unrolled",
      side: "right",
      sourceIds: ["disney-2009", "pearson-1988", "vasco-da-gama-journal-1898"],
      evidence: [
        "Da Gama departed Lisbon in July 1497, rounded the Cape, crossed from Malindi with a locally supplied pilot and reached Calicut in May 1498.",
        "The voyage journal records the Indian Ocean expertise available at Malindi, where a locally supplied pilot carried the fleet onto the monsoon road to India.",
      ],
      map: { x: 71, y: 44 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "unroll-ocean",
        prompt: "Unroll the ocean",
        accessibleSummary:
          "Six cumulative chart lengths carry recorded knowledge from Lisbon past Bojador, Guinea and the Cape, then join East African pilotage to the monsoon crossing toward Calicut.",
        initialId: "lisbon-sheet",
        mapImage: `${imageRoot}/06-chart-reaches-calicut.avif`,
        records: [
          {
            id: "lisbon-sheet",
            label: "Open the inherited sheet",
            period: "AD 1415",
            kicker: "The chart begins at home",
            detail:
              "Lisbon, Atlantic islands and the north-west African approaches occupy the known vellum from which sustained royal voyages depart.",
            fields: [
              {
                label: "Recorded",
                value: "Home ports, islands and approaches",
              },
              { label: "Required next", value: "A return from beyond Bojador" },
            ],
            outcome:
              "The crown can order another voyage from a preserved starting field.",
            points: [
              {
                id: "lisbon",
                label: "Lisbon",
                detail: "Departure and archive",
                x: 18,
                y: 16,
              },
            ],
          },
          {
            id: "bojador-entry",
            label: "Enter Bojador",
            period: "AD 1434",
            kicker: "A limit becomes a recorded cape",
            detail:
              "Eanes returns with a passed headland, bearings and a coast that continues south beyond the old turning point.",
            fields: [
              { label: "Recorded", value: "Cape, shoals and return" },
              { label: "Required next", value: "A longer coastal survey" },
            ],
            outcome:
              "A practical boundary becomes the first line on a longer African sheet.",
            points: [
              {
                id: "lisbon",
                label: "Lisbon",
                detail: "Chart office",
                x: 18,
                y: 16,
              },
              {
                id: "bojador",
                label: "Cape Bojador",
                detail: "Cape passed",
                x: 20,
                y: 31,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "guinea-entry",
            label: "Extend through Guinea",
            period: "AD 1440s'1480s",
            kicker: "Returns lengthen the coast",
            detail:
              "Successive pilots add capes, river mouths, anchorages, trade intelligence and the offshore wind road home.",
            fields: [
              { label: "Recorded", value: "Coast, commerce and volta" },
              {
                label: "Required next",
                value: "The continent's southern turn",
              },
            ],
            outcome:
              "Many separate observations become a continuous navigational approach.",
            points: [
              {
                id: "lisbon",
                label: "Lisbon",
                detail: "Chart office",
                x: 18,
                y: 16,
              },
              {
                id: "bojador",
                label: "Cape Bojador",
                detail: "Cape passed",
                x: 20,
                y: 31,
              },
              {
                id: "guinea",
                label: "Guinea coast",
                detail: "Survey and trade",
                x: 24,
                y: 49,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "cape-entry",
            label: "Turn the Cape",
            period: "AD 1488",
            kicker: "The coast opens east",
            detail:
              "Dias's ocean track passes south of Africa and returns with proof that Atlantic water leads into the Indian Ocean.",
            fields: [
              {
                label: "Recorded",
                value: "Southern passage and eastward coast",
              },
              {
                label: "Required next",
                value: "A fleet provisioned for India",
              },
            ],
            outcome:
              "The vertical African roll reaches a hinge and can open into another ocean.",
            points: [
              {
                id: "lisbon",
                label: "Lisbon",
                detail: "Chart office",
                x: 18,
                y: 16,
              },
              {
                id: "bojador",
                label: "Cape Bojador",
                detail: "Cape passed",
                x: 20,
                y: 31,
              },
              {
                id: "guinea",
                label: "Guinea coast",
                detail: "Survey and trade",
                x: 24,
                y: 49,
              },
              {
                id: "cape",
                label: "Cape of Good Hope",
                detail: "Ocean turn",
                x: 35,
                y: 83,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
            ],
          },
          {
            id: "malindi-entry",
            label: "Receive the monsoon line",
            period: "April AD 1498",
            kicker: "Ocean knowledge meets ocean knowledge",
            detail:
              "At Malindi, a Gujarati pilot supplies the seasonal crossing that Atlantic experience alone could not provide.",
            fields: [
              {
                label: "Recorded",
                value: "East African harbour and monsoon departure",
              },
              { label: "Required next", value: "A crossing timed for India" },
            ],
            outcome:
              "The Portuguese route joins the living navigational system of the Indian Ocean.",
            points: [
              {
                id: "lisbon",
                label: "Lisbon",
                detail: "Departure",
                x: 18,
                y: 16,
              },
              {
                id: "guinea",
                label: "Guinea coast",
                detail: "Atlantic approach",
                x: 24,
                y: 49,
              },
              {
                id: "cape",
                label: "Cape of Good Hope",
                detail: "Ocean turn",
                x: 35,
                y: 83,
              },
              {
                id: "malindi",
                label: "Malindi",
                detail: "Pilot and monsoon",
                x: 56,
                y: 61,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
            ],
          },
          {
            id: "calicut-entry",
            label: "Reach Calicut",
            period: "May AD 1498",
            kicker: "The ocean stands connected",
            detail:
              "The fleet arrives in the great Malabar market and gives Europe a direct, repeatable sea route from the Atlantic to India.",
            fields: [
              {
                label: "Recorded",
                value: "Market, court, anchorage and crossing",
              },
              { label: "Returns with", value: "A connected ocean route" },
            ],
            outcome:
              "The unrolled chart now carries one voyage from Lisbon to the Indian spice markets.",
            points: [
              {
                id: "lisbon",
                label: "Lisbon",
                detail: "Departure",
                x: 18,
                y: 16,
              },
              {
                id: "guinea",
                label: "Guinea coast",
                detail: "Atlantic approach",
                x: 24,
                y: 49,
              },
              {
                id: "cape",
                label: "Cape of Good Hope",
                detail: "Ocean turn",
                x: 35,
                y: 83,
              },
              {
                id: "malindi",
                label: "Malindi",
                detail: "Pilot and monsoon",
                x: 56,
                y: 61,
              },
              {
                id: "calicut",
                label: "Calicut",
                detail: "Indian market",
                x: 76,
                y: 56,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
              [3, 4],
            ],
          },
        ],
      },
    },
    {
      id: "columbus-crosses-other-way",
      actId: "routes-enclose-earth",
      order: 7,
      period: "AD 1492\u20131493",
      place: "Palos, the Canary Islands and the Caribbean",
      title: "Columbus Crosses the Other Way",
      thesis:
        "Atlantic wind practice carried a Castilian expedition west into the Caribbean and opened a second ocean road from Iberia.",
      body: [
        "Three vessels left Palos in August 1492 under Christopher Columbus, sailing for Ferdinand and Isabella after the conquest of Granada had released royal attention and patronage. Columbus expected the ocean to place the markets of Asia within a manageable westward crossing. From the Canary Islands, the fleet entered the trade winds and held west for more than a month. Daily estimates, compass headings, changing birds and vegetation in the water sustained judgment where no European chart supplied a destination.",
        "Land appeared on 12 October among the islands of the Caribbean. Columbus interpreted the shore through his Asian expectation and called its inhabitants Indians. Lucayan and other Caribbean communities supplied food, local names, routes and pilots while the Castilian expedition erected crosses, recorded possession and searched for gold. The commander had misidentified the geography, yet his ships had established the practical fact that an Atlantic outward route could reach inhabited western lands and a northern return arc could carry news back to Europe.",
        "Columbus entered Palos again in March 1493 with captives, objects, a journal and claims large enough to command immediate royal action. Letters and printed reports carried the crossing through European courts and ports. The next fleet would be a colonising expedition of seventeen ships, not an isolated reconnaissance. Portugal's route extended south and east around Africa; Castile's now ran west through the Canaries. Iberian mariners had opened the Atlantic in two directions, and their rival crowns required law and geography to decide where one field of expansion ended and the other began.",
      ],
      image: `${imageRoot}/07-columbus-crosses-other-way.avif`,
      imageAlt:
        "Pilots and sailors work a westbound Atlantic passage from the Canaries toward a carefully observed Caribbean shore.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "westward-crossing",
      side: "left",
      sourceIds: ["fernandez-armesto-1991", "brotton-1997", "parker-2012"],
      evidence: [
        "Columbus's 1492 fleet used the Canary route and Atlantic trade winds to reach the Caribbean, then returned through more northerly winds in 1493.",
        "Columbus remained convinced that the lands belonged to the approaches to Asia, while Castilian possession and rapid follow-up voyages gave the crossing immediate political consequence.",
      ],
      map: { x: 29, y: 37 },
    },
    {
      id: "meridian-divides-unknown-world",
      actId: "routes-enclose-earth",
      order: 8,
      period: "AD 1494\u20131500",
      place: "Tordesillas, Cape Verde and the coast of Brazil",
      title: "A Meridian Divides an Unknown World",
      thesis:
        "Tordesillas projected royal law across an ocean whose longitude remained beyond reliable measurement.",
      body: [
        "Diplomats met at Tordesillas in 1494 with a problem created by successful navigation. Portugal defended the Atlantic field built through decades of voyages; Castile defended the western lands reached by Columbus. Their treaty placed a north\u2013south line 370 leagues west of the Cape Verde islands. Lands discovered to the east would fall within the Portuguese sphere and lands to the west within the Castilian sphere. Seals and ratifications divided claims across water wider than either crown could map.",
        "The line possessed legal precision and geographic uncertainty. The treaty did not define one universally accepted length for the league, the position of the Cape Verde baseline invited choices, and mariners lacked a dependable method for determining longitude at sea. Pilots could estimate distance and cartographers could draw meridians, but two experts could place the same words on different parts of a chart. The agreement therefore created a working diplomatic order while surveys, landfalls and rival calculations continued to decide its material reach.",
        "Pedro \u00c1lvares Cabral sailed from Lisbon for India in March 1500, followed the broad South Atlantic route and reached the coast of present-day Brazil in April. A shoreline now stood inside the region Portugal understood as its side of the division. The crown sent reports, claimed the land and ordered further survey. Geography began to give the parchment line ports, resources and consequences. Tordesillas demonstrated a new scale of European statecraft: two monarchies wrote law across the Ocean Sea first, then dispatched pilots and fleets to discover where their legal world met the physical one.",
      ],
      image: `${imageRoot}/08-meridian-divides-unknown-world.avif`,
      imageAlt:
        "The Treaty of Tordesillas lies over an incomplete globe as Cabral's landfall adds the coast of Brazil.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "uncertain-meridian",
      side: "right",
      sourceIds: ["tordesillas-1494", "brotton-1997", "disney-2009"],
      evidence: [
        "The 1494 treaty located its demarcation 370 leagues west of the Cape Verde islands and assigned future claims on either side to Portugal and Castile.",
        "Late fifteenth-century navigators could estimate courses and latitude more effectively than longitude, leaving the treaty meridian open to materially different placements.",
      ],
      map: { x: 39, y: 59 },
      interaction: {
        kind: "chapter-v2",
        family: "record",
        variant: "unmeasured-meridian",
        prompt: "Divide an unmeasured ocean",
        accessibleSummary:
          "Four documentary states move from the treaty's exact words through uncertain longitude to Cabral's Brazilian landfall and the surveys that give a legal claim geographic consequence.",
        initialId: "treaty-line",
        records: [
          {
            id: "treaty-line",
            label: "Write the division",
            period: "7 June AD 1494",
            kicker: "Law crosses the ocean",
            detail:
              "Portuguese and Castilian envoys agree on a pole-to-pole meridian 370 leagues west of the Cape Verde islands.",
            fields: [
              { label: "Legal measure", value: "370 leagues" },
              { label: "Baseline", value: "Cape Verde islands" },
              { label: "Document state", value: "Sealed and ratified" },
            ],
            outcome:
              "The crowns possess a rule for future claims before they possess a complete geography.",
          },
          {
            id: "pilot-estimate",
            label: "Carry it to sea",
            period: "AD 1494\u20131500",
            kicker: "Longitude remains uncertain",
            detail:
              "A pilot can hold a course and estimate distance, but cannot locate the treaty meridian on open water with repeatable precision.",
            fields: [
              {
                label: "Known strongly",
                value: "Heading and approximate latitude",
              },
              { label: "Known weakly", value: "Distance east or west" },
              { label: "Geographic state", value: "A band of possible lines" },
            ],
            outcome:
              "The same treaty can produce different chart positions without losing its diplomatic force.",
          },
          {
            id: "cabral-landfall",
            label: "Meet a coastline",
            period: "22 April AD 1500",
            kicker: "Land tests the paper world",
            detail:
              "Cabral's fleet reaches the Brazilian coast while following the South Atlantic approach toward the Cape.",
            fields: [
              { label: "New fact", value: "A western Atlantic shore" },
              { label: "Portuguese act", value: "Report and possession" },
              { label: "Geographic state", value: "Claim attached to land" },
            ],
            outcome:
              "A physical coast gives the eastern side of the treaty a western Atlantic consequence.",
          },
          {
            id: "surveyed-coast",
            label: "Send the survey",
            period: "after AD 1500",
            kicker: "Observation narrows the claim",
            detail:
              "Later voyages record bays, capes and sailing distances, replacing one landfall with a coast that can be governed and revisited.",
            fields: [
              { label: "Returns", value: "Coast sketches and route estimates" },
              { label: "Crown use", value: "Naming, grants and defence" },
              {
                label: "Geographic state",
                value: "A growing territorial record",
              },
            ],
            outcome:
              "Repeated survey carries the treaty from diplomatic parchment into an administered Atlantic world.",
          },
        ],
      },
    },
    {
      id: "one-ship-closes-circle",
      actId: "routes-enclose-earth",
      order: 9,
      period: "AD 1519\u20131522",
      place:
        "Seville, the Strait of Magellan, the Pacific, the Moluccas and Sanl\u00facar",
      title: "One Ship Closes the Circle",
      thesis:
        "The Magellan\u2013Elcano expedition joined the great oceans in one westward voyage and revealed the immense scale of the Pacific.",
      body: [
        "Five ships sailed from Spain in 1519 under Ferdinand Magellan to reach the spice islands through the Castilian side of the world. The fleet crossed the Atlantic, searched the South American coast and wintered amid cold, hunger and mutiny. In October 1520, it entered the long, difficult channel now bearing Magellan's name. One vessel had already wrecked and another deserted for Spain. The remaining ships emerged into water whose calm first appearance gave the Pacific its European name.",
        "The crossing exposed the ocean's true breadth. Stores ran out during months without a secure port; scurvy and starvation reduced the crews before land and provisions returned. Magellan reached the Philippines and died in battle at Mactan in April 1521 after entering a local conflict. Command passed through surviving officers as the expedition reached the Moluccas and loaded cloves. With too few men for the remaining vessels, the crew burned one hull and prepared two different attempts to return.",
        "Juan Sebasti\u00e1n Elcano took the Victoria west across the Indian Ocean, avoided Portuguese positions and rounded the Cape. On 6 September 1522, the salt-damaged ship reached Sanl\u00facar with eighteen survivors from the expedition's original complement. One hull had completed the first circumnavigation. Its cargo helped justify the immense loss, while its log and track established a connected planetary geography no chart could compress without distortion. Atlantic, Pacific and Indian Ocean routes now enclosed the earth, and competing European crowns possessed direct evidence that command of distance required permanent systems rather than one extraordinary crew.",
      ],
      image: `${imageRoot}/09-one-ship-closes-circle.avif`,
      imageAlt:
        "Five engraved ship marks diminish to the battered Victoria as its route closes around a globe dominated by the Pacific.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "circumnavigation",
      side: "left",
      sourceIds: ["pigafetta-cachey-2007", "brotton-1997", "parker-2012"],
      evidence: [
        "The expedition departed with five ships in 1519; Magellan died in the Philippines, and Elcano returned the Victoria to Sanl\u00facar in September 1522.",
        "Eighteen men completed the full voyage in the Victoria, whose track constituted the first circumnavigation and demonstrated the Pacific's enormous extent.",
      ],
      map: { x: 48, y: 30 },
    },
    {
      id: "cannon-holds-narrow-water",
      actId: "voyages-become-systems",
      order: 10,
      period: "AD 1505\u20131515",
      place: "Goa, Malacca and Hormuz",
      title: "Cannon Holds the Narrow Water",
      thesis:
        "Portugal converted a long route into a maritime system by holding supplied bases and narrow waters with ships, forts, factors and passes.",
      body: [
        "A fleet arriving in the Indian Ocean faced a commercial world larger than Portugal could conquer. Ports along East Africa, Arabia, India and Southeast Asia served rulers, shipowners and merchant communities with their own capital and armed power. The Portuguese crown concentrated its limited men where geography multiplied them. Heavy shipboard cannon could dominate an anchorage or punish a vessel at close range, while a fortified harbour supplied repairs, water, powder, information and a secure office for the factor who bought and stored cargo.",
        "Afonso de Albuquerque made the system territorial at selected hinges. He took Goa in 1510 and made its harbour the principal base on India's western coast. Malacca fell in 1511 beside the strait through which much traffic between the Indian Ocean and the spice-producing islands passed. Albuquerque returned to Hormuz in 1515 and secured the entrance to the Persian Gulf. These positions formed no continuous land empire. They placed Portuguese garrisons and ships beside routes that merchants had made prosperous long before Europeans arrived.",
        "Monsoon timing joined the bases. A fleet required the right seasonal wind, stores within sailing range and intelligence from the next harbour. Convoys protected valuable cargo; factors negotiated supply; the cartaz pass required many regional vessels to purchase Portuguese permission and submit to inspection. Resistance, evasion and rival trade continued across the vast ocean, while control of narrow water allowed a small European kingdom to divert a strategic share. The sea road endured because cannon rested on magazines, magazines on ports, and ports on a scheduled network that could be reinforced from Goa or ultimately from Lisbon.",
      ],
      image: `${imageRoot}/10-cannon-holds-narrow-water.avif`,
      imageAlt:
        "Harbour plans of Goa, Malacca and Hormuz connect forts, factors and armed ships through seasonal monsoon routes.",
      imagePosition: "61% center",
      mobileImagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "armed-sea-road",
      side: "right",
      sourceIds: ["pearson-1988", "subrahmanyam-2012", "parker-2012"],
      evidence: [
        "Albuquerque captured Goa in 1510 and Malacca in 1511, then secured Hormuz in 1515 after an earlier Portuguese intervention there.",
        "Portuguese influence relied on fortified ports, armed shipping, seasonal supply, factors and the cartaz system rather than occupation of the Asian continental interior.",
      ],
      map: { x: 70, y: 42 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "armed-sea-road",
        prompt: "Arm the sea road",
        accessibleSummary:
          "Five cumulative network states connect Goa, Malacca and Hormuz through monsoon timing, supplied forts, factors, armed ships and cartaz inspection.",
        initialId: "monsoon-window",
        mapImage: `${imageRoot}/10-cannon-holds-narrow-water.avif`,
        records: [
          {
            id: "monsoon-window",
            label: "Read the season",
            period: "Monsoon window",
            kicker: "Wind governs reach",
            detail:
              "A fleet departs only when the seasonal wind can carry hulls, stores and orders toward the next base.",
            fields: [
              {
                label: "Instrument",
                value: "Pilot knowledge and sailing calendar",
              },
              {
                label: "System need",
                value: "A supplied destination within range",
              },
            ],
            outcome:
              "Timing turns scattered positions into a route a fleet can sustain.",
            points: [
              { id: "goa", label: "Goa", detail: "Fleet base", x: 43, y: 50 },
            ],
          },
          {
            id: "goa-base",
            label: "Supply Goa",
            period: "AD 1510",
            kicker: "The fleet gains a harbour",
            detail:
              "Dock work, magazines, officials and local commerce give Portuguese ships a durable base on India's western coast.",
            fields: [
              { label: "Holds", value: "Harbour, fort and stores" },
              { label: "Extends", value: "Arabian Sea patrol and repair" },
            ],
            outcome:
              "Ships can remain in Asian waters instead of treating every voyage as a return to Lisbon.",
            points: [
              {
                id: "goa",
                label: "Goa",
                detail: "Fleet base and stores",
                x: 43,
                y: 50,
              },
              {
                id: "calicut",
                label: "Malabar coast",
                detail: "Pepper markets",
                x: 47,
                y: 61,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "malacca-gate",
            label: "Hold Malacca",
            period: "AD 1511",
            kicker: "A strait multiplies force",
            detail:
              "A fort and armed anchorage stand beside the passage joining the Indian Ocean to Southeast Asian and spice-island trade.",
            fields: [
              { label: "Holds", value: "Fortified strait and factor's office" },
              { label: "Extends", value: "Access toward the Moluccas" },
            ],
            outcome:
              "A concentrated position can inspect and influence traffic spread across a much larger sea.",
            points: [
              { id: "goa", label: "Goa", detail: "Western base", x: 43, y: 50 },
              {
                id: "malacca",
                label: "Malacca",
                detail: "Strait and factor",
                x: 76,
                y: 68,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "hormuz-gate",
            label: "Secure Hormuz",
            period: "AD 1515",
            kicker: "The Gulf entrance joins the system",
            detail:
              "Portuguese force returns to Hormuz and establishes a position beside the maritime entrance to the Persian Gulf.",
            fields: [
              {
                label: "Holds",
                value: "Anchorage, fort and negotiated authority",
              },
              { label: "Extends", value: "Persian Gulf approach" },
            ],
            outcome:
              "Goa now stands between fortified approaches to western and eastern trade.",
            points: [
              {
                id: "hormuz",
                label: "Hormuz",
                detail: "Gulf entrance",
                x: 22,
                y: 31,
              },
              { id: "goa", label: "Goa", detail: "Fleet base", x: 43, y: 50 },
              {
                id: "malacca",
                label: "Malacca",
                detail: "Eastern strait",
                x: 76,
                y: 68,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "cartaz-circuit",
            label: "Inspect the circuit",
            period: "Sixteenth century",
            kicker: "Paper carries the cannon's claim",
            detail:
              "The cartaz names vessel, cargo and permitted route; patrols and forts give the pass consequence at sea and in port.",
            fields: [
              { label: "Document", value: "Purchased maritime pass" },
              { label: "Enforcement", value: "Inspection, seizure and convoy" },
              {
                label: "System reach",
                value: "Selected routes between fortified bases",
              },
            ],
            outcome:
              "A small crown imposes a documented claim across narrow waters while the greater ocean trade continues around it.",
            points: [
              {
                id: "hormuz",
                label: "Hormuz",
                detail: "Pass inspection",
                x: 22,
                y: 31,
              },
              {
                id: "goa",
                label: "Goa",
                detail: "Fleet and archive",
                x: 43,
                y: 50,
              },
              {
                id: "malacca",
                label: "Malacca",
                detail: "Pass inspection",
                x: 76,
                y: 68,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
        ],
      },
    },
    {
      id: "voyage-enters-archive",
      actId: "voyages-become-systems",
      order: 11,
      period: "c. AD 1500\u20131600",
      place: "Lisbon and the Casa de la Contrataci\u00f3n, Seville",
      title: "The Voyage Enters the Archive",
      thesis:
        "Crown chart offices made experience cumulative by turning the pilot's return into corrected instruments, examinations and instructions for the next fleet.",
      body: [
        "A pilot came ashore carrying a salt-stiff log, damaged chart and numerical observations taken under difficult conditions. Crown officers wanted the harbour depths, latitudes, reefs, currents, sailing days and political intelligence that could make a later fleet safer and stronger. In Lisbon, Portuguese storehouses and cartographic services assembled route knowledge around a controlled master chart. In Seville, the Casa de la Contrataci\u00f3n, founded in 1503, gathered commercial administration, navigation and cosmography for Spain's Atlantic enterprise.",
        "The offices joined men to documents. Spain appointed a pilot major in 1508 to examine pilots, supervise instruments and maintain the padr\u00f3n real. Portuguese practice centred its own guarded padr\u00e3o real and the charts, rutters and astronomical tables issued for crown service. A returning pilot's coast sketch could be compared with earlier testimony; disagreement called for another observation; a corrected cape or shoal entered the working copy for a later departure. Knowledge remained strategic, and crowns controlled circulation because a route could be as valuable as artillery.",
        "The archive gave ocean power a memory beyond any captain. Men died, ships foundered and individual charts wore out, while an office could preserve a sequence of returns, train replacements and impose common reference points across a fleet. Latitude became increasingly serviceable through instruments and tables; longitude continued to resist exact determination, so dead reckoning, repeated landfall and accumulated local knowledge retained their importance. European expansion became cumulative because the deck and the desk formed one institution. Observation entered the master record, and the amended record returned to sea in the hands of another pilot.",
      ],
      image: `${imageRoot}/11-voyage-enters-archive.avif`,
      imageAlt:
        "A wet ship log and damaged instrument arrive as cosmographers amend a guarded master chart in a crown office.",
      imagePosition: "64% center",
      mobileImagePosition: "71% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "chart-office",
      side: "left",
      sourceIds: ["portuondo-2009", "brotton-1997", "disney-2009"],
      evidence: [
        "The Casa de la Contrataci\u00f3n was founded in Seville in 1503, and the office of pilot major supervised examinations and the Spanish master chart from 1508.",
        "Portuguese and Spanish crown services treated charts, rutters, pilot knowledge and cosmographic work as controlled strategic resources updated through returning voyages.",
      ],
      map: { x: 48, y: 29 },
    },
    {
      id: "rival-europe-takes-sea",
      actId: "voyages-become-systems",
      order: 12,
      period: "c. AD 1580\u20131700",
      place: "Amsterdam, London, the Atlantic and Indian Ocean routes",
      title: "Rival Europe Takes to Sea",
      thesis:
        "European political rivalry multiplied ocean power by joining inherited routes to chartered companies, deeper capital markets and competing shipyards.",
      body: [
        "Northern pilots entered the routes Iberian crowns had spent generations opening. Printed sailing directions, captured charts, returning mariners and direct reconnaissance carried working knowledge into Amsterdam and London. Dutch and English shipyards produced fleets suited to long cargo voyages and armed convoy. Their merchants could draw capital from several investors, spread danger across multiple sailings and place resident agents in distant ports. Iberian secrecy slowed imitation without preserving an exclusive ocean.",
        "The English East India Company received its charter in 1600 and the Dutch East India Company in 1602. Each joined private capital to public authority for trade, fortification, treaty and war. The Dutch company concentrated resources across chambers and fleets on a scale able to challenge Portuguese positions in Asian waters; English merchants built their own chain of factories and naval protection. France entered with crown-backed companies and fleets. Rival Europeans brought different legal and financial forms onto the same winds, capes and monsoon passages.",
        "Competition made the ocean system denser. Amsterdam became a clearing house for information, cargo, insurance and finance; London expanded its docks, customs and overseas institutions. Wars in Europe reached colonies and sea lanes, while gains overseas strengthened navies and treasuries at home. By 1700, no single crown could close the ocean roads that Portuguese pilots had begun to unroll. Europe's divided states had made maritime reach a permanent field of power. Their confessional divisions, carried through print and territorial government, now open the next chapter inside Europe itself.",
      ],
      image: `${imageRoot}/12-rival-europe-takes-sea.avif`,
      imageAlt:
        "Portuguese routes remain on a working chart as Dutch, English and French lines join from rival ports and shipyards.",
      imagePosition: "60% center",
      mobileImagePosition: "67% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "rival-oceans",
      side: "right",
      sourceIds: ["israel-1989", "harris-2020", "parker-2012"],
      evidence: [
        "The English East India Company was chartered in 1600 and the Dutch East India Company in 1602, joining pooled capital to delegated public powers overseas.",
        "Dutch, English and French competition expanded European shipping and commercial institutions across routes first systematised by the Iberian crowns.",
      ],
      map: { x: 51, y: 21 },
    },
  ],
};
