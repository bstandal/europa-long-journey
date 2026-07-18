import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/steppe-comes-west";

export const steppeComesWest: ChapterDefinition = {
  slug: "steppe-comes-west",
  number: "02",
  title: "The Steppe Comes West",
  period: "3300–2000 BC",
  claim:
    "From the grasslands north of the Black Sea came a mobile order of armed, patrilineal peoples. It displaced old male lines and carried new populations, languages and gods across Europe.",
  theme: {
    id: "steppe",
    label: "The sacred circle",
  },
  openingAction: "Beyond the last fields.",
  mapLabel: "The movement from the Pontic-Caspian steppe into Europe",
  sourcesEyebrow: "Archaeology · ancient DNA · historical linguistics",
  ending: {
    period: "By 2000 BC",
    title: "The steppe was no longer east of Europe.",
    detail: "It lived in Europe’s lineages, languages and gods.",
    image: `${imageRoot}/bronze-handoff.webp`,
    nextPeriod: "2500–500 BC",
  },
  returnHash: "steppe-comes-west",
  nextHash: "bronze-europe",
  nextTitle: "Bronze Europe",
  movements: [
    {
      id: "where-the-fields-end",
      order: 1,
      period: "c. 3300 BC",
      place: "Lower Dnipro",
      title: "Where the Fields End",
      thesis: "Beyond the last fields, wealth could walk away.",
      body: [
        "East of the farming plains, the woodland thinned and the sky widened. The lower Dnipro joined river valleys, grazing land and the open grasslands north of the Black Sea. Farmers lived along this frontier. So did communities whose cattle and sheep turned grass into food, hides and portable wealth. Exchange carried copper, pottery and animals across the boundary. Raiding and feuding could travel along the same routes.",
        "This was the edge of Europe’s settled world, not the edge of human society. Steppe households knew wells, river crossings and seasonal pasture. Their dead occupied marked places. Their living could assemble, divide and move without abandoning the animals that sustained them. That difference in movement would become a difference in reach, then in power.",
      ],
      image: `${imageRoot}/01-where-fields-end.webp`,
      mobileImage: `${imageRoot}/01-where-fields-end-mobile.webp`,
      imageAlt:
        "Cultivated fields and woodland open onto a broad blue-green steppe beside the lower Dnipro.",
      imagePosition: "58% center",
      mobileImagePosition: "62% center",
      visualTone: "dawn",
      side: "left",
      sourceIds: ["anthony-2007", "lazaridis-2025"],
      evidence: [
        "Settlement remains, animal bones and exchanged objects place farming and pastoral communities in sustained contact around the lower Dnipro.",
        "Ancient genomes reconstruct related steppe populations from sampled burials; they do not turn every frontier encounter into a single migration event.",
      ],
      map: { x: 70, y: 62 },
    },
    {
      id: "a-world-that-could-move",
      order: 2,
      period: "3300–3000 BC",
      place: "Pontic-Caspian Steppe",
      title: "A World That Could Move",
      thesis: "The herd made distance part of the household economy.",
      body: [
        "Cattle and sheep made the open grasslands productive, but grazing was never fixed in one place. Households moved between known water, shelter and pasture. Animals carried much of their own food on the hoof. People carried milk, meat, hides, tools and the knowledge of routes. A camp could gather around work, animals and fire, then loosen when the grass demanded movement.",
        "Mobility did not mean endless wandering. It was an ordered circuit through remembered land. Families returned to rivers and winter ground, met allies, exchanged partners and renewed claims. Herds enlarged the territory a household could use. Networks of kin turned separate journeys into a social world extending far beyond one village.",
      ],
      image: `${imageRoot}/02-world-could-move.webp`,
      imageAlt:
        "A mobile pastoral camp, cattle, sheep and people arranged in a loose circle on the pale morning steppe.",
      imagePosition: "54% center",
      visualTone: "morning",
      side: "right",
      sourceIds: ["anthony-2007", "lazaridis-2025"],
      evidence: [
        "Animal remains and settlement patterns show economies centred on cattle and sheep across steppe and river environments.",
        "Seasonal movement is reconstructed from landscape, subsistence and settlement evidence; the exact circuits of individual households are lost.",
      ],
      map: { x: 76, y: 58 },
    },
    {
      id: "the-wheel-carries-the-house",
      order: 3,
      period: "3300–2800 BC",
      place: "Dnipro · Lower Danube",
      title: "The Wheel Carries the House",
      thesis: "The wagon made the household itself mobile.",
      body: [
        "The earliest heavy wagons had solid wooden wheels and moved behind oxen. They were slow, rough and transformative. A household could carry shelter, vessels, food, tools and young children while accompanying its herds. The wagon did not create steppe pastoralism, but it widened the practical circuit of people who already lived through animals and seasonal movement.",
        "This expansion was not a cavalry charge. Horses were known, valued and sometimes managed, yet genomic evidence places widespread horse-based mobility around 2200 BC, centuries after the main Yamnaya movement into Europe. The earlier westward reach rested on feet, hooves, cattle and solid wheels. Its power came from carrying a whole social unit across distance.",
      ],
      image: `${imageRoot}/03-wheel-carries-house.webp`,
      imageAlt:
        "A low view beside the solid wooden wheel of an ox-drawn wagon moving across the steppe.",
      imagePosition: "59% center",
      visualTone: "wheel",
      side: "left",
      sourceIds: ["anthony-2007", "librado-2024"],
      evidence: [
        "Wheel tracks, vehicle models and wagon burials establish solid-wheeled transport in the fourth and early third millennia BC.",
        "Ancient horse genomes place the rapid expansion of the modern domestic lineage and widespread horse-based mobility around 2200 BC.",
      ],
      map: { x: 65, y: 67 },
      interaction: {
        kind: "mobility",
        prompt: "Set the household in motion",
        accessibleSummary:
          "Three states show how herds, an ox wagon and a westward household successively widened practical reach.",
        states: [
          {
            id: "herd",
            label: "Herd",
            detail:
              "Cattle and sheep turn distant pasture into portable food and wealth along a seasonal circuit.",
            reach: "Pasture to pasture",
            load: "Animals carry themselves",
          },
          {
            id: "wagon",
            label: "Wagon",
            detail:
              "Oxen pull shelter, stores, tools and children beyond the range of a village-bound household.",
            reach: "A wider circuit",
            load: "The house can travel",
          },
          {
            id: "westward-household",
            label: "Westward",
            detail:
              "Related households can cross the lower Danube with herds, possessions and a living social order.",
            reach: "Into new country",
            load: "Kin, herd and stores",
          },
        ],
      },
    },
    {
      id: "the-mound-holds-the-fathers",
      order: 4,
      period: "3200–2600 BC",
      place: "Steppe · Carpathian Basin",
      title: "The Mound Holds the Fathers",
      thesis: "The dead fixed a moving people to land.",
      body: [
        "A low mound broke the horizon. Beneath it, selected dead lay in graves marked by ochre, timber, stone or sacrificed animals. Later burials could enter the same mound, binding descendants to a remembered ancestor. The kurgan made a claim that could be seen from far away: this route, pasture and assembly ground belonged to a lineage with a past.",
        "Weapons and male burials reveal an armed order, while ancient DNA exposes concentrated paternal lines and women drawn from wider backgrounds. These patterns were neither identical in every cemetery nor gentle in their effects. They point to households in which senior men, sons and allied fighters could control animals, movement, marriage and the ancestry attached to territory.",
      ],
      image: `${imageRoot}/04-mound-holds-fathers.webp`,
      imageAlt:
        "A burial mound seen from above with long shadows and armed men standing on foot around its circular edge.",
      imagePosition: "52% center",
      visualTone: "mound",
      side: "right",
      sourceIds: ["anthony-2007", "papac-2021", "goldberg-2017"],
      evidence: [
        "Kurgans, repeated graves, ochre, stone settings and animal offerings preserve acts that joined ancestry to visible ground.",
        "Y-chromosome concentration and sex-biased ancestry support strong paternal organization; genetic estimates describe sampled populations, not a single rule for every steppe household.",
      ],
      map: { x: 58, y: 63 },
    },
    {
      id: "the-fathers-disappear",
      order: 5,
      period: "2900–2000 BC",
      place: "Central Europe · Iberia",
      title: "The Fathers Disappear",
      thesis: "The westward movement reordered who fathered the future.",
      body: [
        "Across central Europe, incoming groups entered landscapes already divided by fields, paths and old graves. Some encounters ended in exchange or marriage. Others placed armed newcomers against local men defending land and household. The long result appears with exceptional clarity in ancient DNA: steppe-related ancestry rose rapidly, and established paternal lines contracted or vanished from sampled communities.",
        "The pattern was regional, not a single European percentage. German Corded Ware individuals carried about three quarters Yamnaya-related ancestry. In Bohemia, successive social changes produced sharp reductions and complete replacements of Y-chromosome diversity. By about 2000 BC, Iberia had received roughly 40 percent new ancestry while nearly all sampled Y chromosomes had been replaced by lineages associated with steppe ancestry. Women and local ancestry remained part of the new populations; local male continuity often did not.",
      ],
      image: `${imageRoot}/05-fathers-disappear.webp`,
      mobileImage: `${imageRoot}/05-fathers-disappear-mobile.webp`,
      imageAlt:
        "Armed newcomers on foot confront local men at the edge of a farmed landscape in a restrained dusk scene.",
      imagePosition: "52% center",
      mobileImagePosition: "55% center",
      visualTone: "dusk",
      side: "left",
      sourceIds: ["haak-2015", "papac-2021", "goldberg-2017", "olalde-2019"],
      evidence: [
        "Ancient genomes measure ancestry and paternal descent in sampled burials; they reveal demographic outcomes but rarely identify the cause of an individual death.",
        "One influential X-chromosome model estimated five to fourteen migrating steppe men per woman; a published reanalysis disputed the precision of that ratio. The broader male bias is supported by regional Y-chromosome turnover.",
      ],
      map: { x: 43, y: 65 },
      interaction: {
        kind: "turnover",
        prompt: "Read three regional records",
        accessibleSummary:
          "Central Europe, Bohemia and Iberia separate overall ancestry from the survival or replacement of paternal lines.",
        regions: [
          {
            id: "central-europe",
            label: "Central Europe",
            period: "c. 2750 BC",
            detail:
              "The German Corded Ware sample documents a massive migration into central Europe, with a small male sample already carrying incoming paternal lines.",
            measures: [
              {
                id: "ancestry",
                label: "Overall ancestry",
                value: "≈75%",
                note: "Yamnaya-related ancestry in sampled German Corded Ware individuals.",
              },
              {
                id: "local-paternal",
                label: "Earlier local male lines",
                value: "0 of 3",
                note: "None of the three typed Corded Ware males carried the earlier farmer-associated Y lineage G2a.",
              },
              {
                id: "incoming-paternal",
                label: "Incoming male lines",
                value: "3 of 3",
                note: "All three typed Corded Ware males carried R1a, a lineage associated with the incoming horizon in this sample.",
              },
            ],
            sourceId: "haak-2015",
          },
          {
            id: "bohemia",
            label: "Bohemia",
            period: "c. 2900–2400 BC",
            detail:
              "Dense regional sampling reveals repeated social reorganizations inside Corded Ware and Bell Beaker communities rather than one stable migrant population.",
            measures: [
              {
                id: "ancestry",
                label: "Overall ancestry",
                value: "Mixed",
                note: "Early Corded Ware people carried diverse ancestry and assimilated women from different backgrounds.",
              },
              {
                id: "local-paternal",
                label: "Earlier local male lines",
                value: "Collapsed",
                note: "Y-chromosome diversity fell sharply around 2600 BC and again around 2400 BC.",
              },
              {
                id: "incoming-paternal",
                label: "Incoming male lines",
                value: "Complete turnover",
                note: "The study reports complete replacement of Y-chromosome diversity at both transitions.",
              },
            ],
            sourceId: "papac-2021",
          },
          {
            id: "iberia",
            label: "Iberia",
            period: "c. 2500–2000 BC",
            detail:
              "Steppe-related ancestry arrived through populations already transformed farther east, then spread through Iberia over several centuries.",
            measures: [
              {
                id: "ancestry",
                label: "Overall ancestry",
                value: "≈40%",
                note: "Share of Iberia’s genome-wide ancestry replaced by about 2000 BC.",
              },
              {
                id: "local-paternal",
                label: "Earlier local male lines",
                value: "Nearly 0%",
                note: "Copper Age Y-chromosome lineages became almost absent in the Bronze Age sample.",
              },
              {
                id: "incoming-paternal",
                label: "Incoming male lines",
                value: "Nearly 100%",
                note: "Almost all sampled Y chromosomes were replaced by lineages associated with steppe ancestry.",
              },
            ],
            sourceId: "olalde-2019",
          },
        ],
      },
    },
    {
      id: "speech-follows-power",
      order: 6,
      period: "2900–2000 BC",
      place: "Corded Ware Europe",
      title: "Speech Follows Power",
      thesis: "Children learned the language of the household that controlled their future.",
      body: [
        "No sentence spoken by these communities survives. The evidence lies in later languages whose shared grammar and vocabulary point back to common ancestors. Indo-European speech had words for kin, livestock, wheels, exchange, sky and ritual. Its European branches spread across populations carrying substantial steppe ancestry, making migration a powerful vehicle for language change.",
        "Language travelled through daily dependence rather than written decree. A child learned from parents and kin around the fire. A spouse entered another household’s obligations. Allies, clients and captives needed the speech of those who controlled herds, land and marriage. Population movement opened the path; unequal social reproduction carried the language across generations.",
      ],
      image: `${imageRoot}/06-speech-follows-power.webp`,
      imageAlt:
        "Families and armed men gather in a circle around a night fire as an elder speaks to children.",
      imagePosition: "54% center",
      visualTone: "fire",
      side: "right",
      sourceIds: ["haak-2015", "heggarty-2023", "mallory-adams-2006"],
      evidence: [
        "Historical linguistics reconstructs inherited words and relationships between later languages; it cannot recover a recording of Yamnaya or Corded Ware speech.",
        "The strong geographic overlap between steppe-related migration and later Indo-European branches supports transmission through people and power, while language and genes never move in a fixed one-to-one ratio.",
      ],
      map: { x: 39, y: 55 },
    },
    {
      id: "the-gods-take-two-roads",
      order: 7,
      period: "after c. 2500 BC",
      place: "Europe · Central Asia · India",
      title: "The Gods Take Two Roads",
      thesis: "The same inherited sky opened above Europe and India.",
      body: [
        "Indo-European speech carried a ritual vocabulary and patterns of sacred story. Later traditions preserved related names for the daylight sky and dawn: Vedic Dyáuṣ beside Greek Zeus and Roman Jupiter; Vedic Uṣás beside Greek Eos and Roman Aurora. Divine horse twins appear in India’s Aśvins and in the Greek Dioscuri through a shared poetic pattern, though their names are not direct linguistic cognates.",
        "These traditions did not travel as a sealed religion. Communities inherited, altered and combined stories with older local cults. One branch moved west into Europe. Another crossed Central Asia and entered South Asia in the second millennium BC, carrying steppe-related ancestry and Indo-Iranian speech. The comparison with India exposes deep inheritance; the European Bronze Age will give that inheritance metal, ships, monuments and new local gods.",
      ],
      image: `${imageRoot}/07-gods-take-two-roads.webp`,
      mobileImage: `${imageRoot}/07-gods-take-two-roads-mobile.webp`,
      imageAlt:
        "A ritual fire circle transforms into a bronze solar disc above routes stretching from Europe to India.",
      imagePosition: "52% center",
      mobileImagePosition: "50% center",
      visualTone: "solar",
      side: "left",
      sourceIds: [
        "narasimhan-2019",
        "west-2007",
        "indo-european-interfaces-2024",
        "mallory-adams-2006",
      ],
      evidence: [
        "Cognate divine names are reconstructed through regular sound correspondences; similar roles alone do not prove common inheritance.",
        "Ancient DNA places Steppe Middle-to-Late Bronze Age ancestry in South Asia after the Indus urban period and finds a male-biased contribution in present-day South Asian populations.",
      ],
      map: { x: 48, y: 53 },
      interaction: {
        kind: "inheritance",
        prompt: "Follow what travelled",
        accessibleSummary:
          "Three map layers trace related population movements, language branches and selected inherited religious correspondences from the steppe into Europe and South Asia.",
        mapImage: "assets/world-relief.jpg",
        layers: [
          {
            id: "people",
            label: "People",
            detail:
              "Steppe-related populations moved west into Europe before related Bronze Age groups moved through Central Asia towards South Asia.",
            routes: [
              {
                id: "people-west",
                label: "West into Europe",
                points: [
                  { x: 53, y: 35 },
                  { x: 43, y: 37 },
                  { x: 34, y: 36 },
                ],
              },
              {
                id: "people-east",
                label: "Through Central Asia",
                points: [
                  { x: 55, y: 35 },
                  { x: 68, y: 39 },
                  { x: 76, y: 55 },
                ],
              },
            ],
          },
          {
            id: "language",
            label: "Language",
            detail:
              "Indo-European branches spread through different populations and periods; the map shows descent and transmission, not one simultaneous migration.",
            routes: [
              {
                id: "language-west",
                label: "European branches",
                points: [
                  { x: 53, y: 35 },
                  { x: 44, y: 36 },
                  { x: 34, y: 35 },
                ],
              },
              {
                id: "language-east",
                label: "Indo-Iranian",
                points: [
                  { x: 55, y: 35 },
                  { x: 67, y: 40 },
                  { x: 76, y: 55 },
                ],
              },
            ],
          },
          {
            id: "religion",
            label: "Gods",
            detail:
              "Names of the sky father and dawn are linguistic inheritances. The divine twins preserve a close poetic and ritual parallel.",
            routes: [
              {
                id: "religion-west",
                label: "Europe",
                points: [
                  { x: 53, y: 35 },
                  { x: 42, y: 39 },
                  { x: 34, y: 44 },
                ],
              },
              {
                id: "religion-east",
                label: "India",
                points: [
                  { x: 55, y: 35 },
                  { x: 68, y: 42 },
                  { x: 76, y: 56 },
                ],
              },
            ],
            correspondences: [
              {
                reconstructed: "*Dyēus ph₂tḗr",
                west: "Zeus · Jupiter",
                east: "Dyáuṣ Pitṛ́",
                note: "Inherited name of the daylight sky father.",
              },
              {
                reconstructed: "*H₂éwsōs",
                west: "Eos · Aurora",
                east: "Uṣás",
                note: "Inherited name and imagery of dawn.",
              },
              {
                reconstructed: "Divine horse twins",
                west: "Dioscuri",
                east: "Aśvins",
                note: "A strong functional and poetic parallel, not a shared inherited name.",
              },
            ],
          },
        ],
      },
    },
  ],
};
