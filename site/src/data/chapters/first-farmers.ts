import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/first-farmers";

export const firstFarmers: ChapterDefinition = {
  slug: "first-farmers",
  number: "01",
  title: "The First Farmers",
  period: "7000–3300 BC",
  claim:
    "Farming came to Europe with people who carried seed, animals and knowledge. It bound growing populations to land, season and stores made to outlast a single generation.",
  theme: {
    id: "farmers",
    label: "Field, river and settled ground",
  },
  openingAction: "The river before the fields",
  mapLabel: "The route from the Iron Gates to the first farming landscapes",
  sourcesEyebrow: "Archaeology · ancient DNA · palaeopathology",
  ending: {
    period: "By 3300 BC",
    title: "Europe had become a continent of fields, herds and long-lived settlements.",
    detail: "No text preserves the languages of the people who made it so.",
    nextPeriod: "3300 BC",
  },
  returnHash: "first-farmers",
  nextHash: "steppe-comes-west",
  nextTitle: "The Steppe Comes West",
  movements: [
    {
      id: "before-the-fields",
      order: 1,
      period: "c. 7000 BC",
      place: "The Iron Gates",
      title: "Before the Fields",
      thesis: "The river already held a world.",
      body: [
        "Long before crops reached the Danube, people lived from the gorge’s river and forest. Fishing mattered enormously; hunting, gathered plants and exchange widened the food supply. At Lepenski Vir and nearby sites, substantial buildings, cemeteries and repeated occupation anchored communities to particular stretches of river. People moved to exploit changing resources, then returned to places already dense with memory. Boats connected banks, islands and distant exchange partners more easily than forest paths did.",
        "The first farmers therefore entered an inhabited continent. At the Iron Gates, established river communities had houses, cemeteries, exchange routes and memories attached to place. Farming would not replace an empty wilderness. It would meet societies whose lives were already fitted closely to river, forest and season.",
      ],
      image: `${imageRoot}/before-the-fields.webp`,
      imageAlt:
        "A misty Danube gorge with fishing weirs and seasonal shelters along the wooded shore.",
      side: "left",
      sourceIds: ["shennan-2018", "mathieson-2018"],
      evidence: [
        "Fish bones, mammal remains and stable isotopes record diets drawn heavily from the Danube and its wooded banks.",
        "Buildings, burials and sculpted stones at Lepenski Vir show repeated occupation of a place already dense with memory.",
      ],
      map: { x: 61, y: 66 },
      interaction: {
        kind: "seasons",
        prompt: "Turn the river year",
        accessibleSummary:
          "Four seasons show how fish, forest foods and movement supported life before local farming.",
        stages: [
          {
            id: "spring",
            label: "Spring",
            detail: "Fish runs drew people to narrow channels and repaired weirs.",
            landscape: "High water opened channels through the gorge.",
            resources: ["Migrating fish", "Fresh greens", "Waterfowl"],
            tone: "spring",
          },
          {
            id: "summer",
            label: "Summer",
            detail: "River, grassland and forest offered many smaller sources of food.",
            landscape: "Low banks widened the meeting place between water and forest.",
            resources: ["Fish", "River plants", "Small game"],
            tone: "summer",
          },
          {
            id: "autumn",
            label: "Autumn",
            detail: "Nuts, fruit and game could be gathered before cold tightened the gorge.",
            landscape: "The forest edge became a store of nuts, fruit and hunted meat.",
            resources: ["Hazelnuts", "Wild fruit", "Deer"],
            tone: "autumn",
          },
          {
            id: "winter",
            label: "Winter",
            detail: "Households returned to dependable water and food kept from earlier seasons.",
            landscape: "Cold narrowed the range of foods and drew life back to dependable water.",
            resources: ["Stored fish", "Dried meat", "River access"],
            tone: "winter",
          },
        ],
      },
    },
    {
      id: "a-household-crosses",
      order: 2,
      period: "7000–6500 BC",
      place: "Anatolia · The Aegean · Thessaly",
      title: "A Household Crosses the Sea",
      thesis: "The field travelled as a living system.",
      body: [
        "Communities from western Anatolia carried more than seed. Emmer and einkorn wheat needed knowledge of soil and timing. Sheep and goats needed breeding, fodder and protection. Pottery, grinding stones and storage joined the same system. Children learned its routines by working beside adults, making knowledge portable without writing. Remove one part and the others became harder to sustain.",
        "Ancient DNA shows that farming reached southeastern Europe chiefly through the movement of people whose ancestry traced largely to Anatolian farming populations. Repeated crossings through the Aegean brought people, animals and seed to new shores and into Thessaly. From the Balkans, farming later followed the Danube towards central Europe. Other communities moved west along Mediterranean coasts. The routes differed, but people, plants, animals and learned routines moved together.",
      ],
      image: `${imageRoot}/crossing-the-sea.webp`,
      imageAlt:
        "A household loads grain, animals and tools into a small boat on an Aegean shore.",
      imagePosition: "62% center",
      side: "left",
      sourceIds: ["mathieson-2018", "shennan-2018"],
      evidence: [
        "Ancient genomes connect southeastern Europe’s first farming populations chiefly to earlier farmers in Anatolia.",
        "Domestic wheat, sheep and goats appear with pottery, grinding stones and storage practices along Aegean and Balkan routes.",
      ],
      map: { x: 69, y: 78 },
      interaction: {
        kind: "route",
        prompt: "Carry the household",
        accessibleSummary:
          "Four connected places trace a farming household from western Anatolia through the Aegean to Thessaly and the Danube.",
        points: [
          {
            id: "anatolia",
            label: "Western Anatolia",
            detail: "Seed, livestock and practiced routines began the crossing together.",
            x: 72,
            y: 66,
          },
          {
            id: "aegean",
            label: "The Aegean",
            detail: "Short sea passages linked familiar coasts and islands.",
            x: 61,
            y: 50,
          },
          {
            id: "thessaly",
            label: "Thessaly",
            detail: "New villages made the farming system durable on European ground.",
            x: 49,
            y: 41,
          },
          {
            id: "danube",
            label: "The Danube",
            detail: "River corridors carried households deeper into the continent.",
            x: 38,
            y: 27,
          },
        ],
      },
    },
    {
      id: "the-harvest-had-to-last",
      order: 3,
      period: "6500–6000 BC",
      place: "Thessaly",
      title: "The Harvest Had to Last",
      titleLines: ["The Harvest", "Had to Last"],
      thesis: "Seed kept for spring could not be eaten in winter.",
      body: [
        "A field changed the shape of the year. Ground had to be cleared and worked before seed went into it. Young plants needed protection. Grain ripened within a narrow window, then had to be cut, dried, threshed and kept away from damp, fire, insects and hungry animals. Livestock spread risk, but they added daily demands for pasture, water, birth and winter fodder. A missed season could not be repaired by working harder the next week.",
        "Storage made the system powerful. Grain moved food through time, but the store contained competing futures. Some fed the household now. Some guarded against a poor winter. Some had to survive untouched until sowing. Farming could support more people in one place because households disciplined present hunger for a harvest that did not yet exist.",
      ],
      image: `${imageRoot}/harvest-had-to-last-v2.webp`,
      imageAlt:
        "An early Thessalian settlement beside harvested grain plots, baskets, sheaves and protected stores.",
      side: "left",
      sourceIds: ["shennan-2018"],
      evidence: [
        "Charred emmer and einkorn grains preserve the crops that entered stores, ovens and spring sowing.",
        "Grinding stones, sickle traces, storage pits and burnt house deposits preserve the work between harvest and meal.",
      ],
      map: { x: 59, y: 78 },
      interaction: {
        kind: "harvest",
        prompt: "Divide the store",
        accessibleSummary:
          "Move shares of one illustrative store between food, reserve and seed; every choice changes what the household can face next.",
        total: 12,
        allocations: [
          {
            id: "food",
            label: "Food now",
            detail: "Grain eaten through winter cannot answer spoilage or return to the soil.",
            initial: 5,
            minimum: 4,
          },
          {
            id: "reserve",
            label: "Held back",
            detail: "A reserve absorbs damp, pests and a winter that lasts longer than expected.",
            initial: 4,
            minimum: 2,
          },
          {
            id: "seed",
            label: "Spring seed",
            detail: "The next field exists only if sound grain remains untouched until sowing.",
            initial: 3,
            minimum: 3,
          },
        ],
      },
    },
    {
      id: "at-the-iron-gates",
      order: 4,
      period: "6200–5800 BC",
      place: "The Iron Gates",
      title: "At the Iron Gates",
      thesis: "Two ways of living entered the same households.",
      body: [
        "At the Danube gorge, incoming farmers met communities built around river and forest. Fish and hides crossed one way; pottery, grain and domestic animals crossed another. Stone from distant sources already travelled through older river networks, giving newcomers routes they had not created. Some people adopted selected practices without abandoning older ones. Some moved into farming settlements. Some farming households included partners whose ancestry and childhood lay along the river.",
        "The result varied from place to place and generation to generation. Ancient DNA records migration and mixture, while tools and food remains record exchanges that genes alone cannot show. The frontier was neither a clean replacement nor a single peaceful merger. It was a long sequence of encounters in which people, goods and skills travelled at different speeds.",
      ],
      image: `${imageRoot}/at-the-iron-gates.webp`,
      imageAlt:
        "River and farming communities exchange food and objects beside the Danube.",
      imagePosition: "60% center",
      side: "left",
      sourceIds: ["mathieson-2018"],
      evidence: [
        "Ancient DNA distinguishes hunter-gatherer-related and Aegean farmer-related ancestry without turning a cemetery into a universal family sequence.",
        "Fish bones, domestic animals, cereal remains and pottery show practices crossing the frontier at different speeds.",
      ],
      map: { x: 61, y: 66 },
      interaction: {
        kind: "lineage",
        prompt: "Set three records beside one another",
        accessibleSummary:
          "Dated archaeological contexts show changing ancestry and subsistence at different Iron Gates places, not a single three-generation pedigree.",
        snapshots: [
          {
            id: "river-communities",
            label: "River communities",
            period: "Before c. 6200 BC",
            detail: "Fishing, hunting and exchange organised life in long-used settlements along the gorge.",
            evidence: "Predominantly Iron Gates hunter-gatherer-related ancestry in sampled individuals.",
          },
          {
            id: "contact-burials",
            label: "Contact-period burials",
            period: "c. 6200–6000 BC",
            detail: "Some cemeteries contain people with different childhood diets and ancestry histories.",
            evidence: "Both local hunter-gatherer-related and Aegean farmer-related ancestry are present.",
          },
          {
            id: "later-settlements",
            label: "Later settlements",
            period: "After c. 6000 BC",
            detail: "Farming became more widespread while local ancestry and river foods persisted unevenly.",
            evidence: "Mixture and subsistence vary by site and individual; no single sequence fits the gorge.",
          },
        ],
      },
    },
    {
      id: "the-house-outlives",
      order: 5,
      period: "5600–4900 BC",
      place: "The Loess Plains",
      title: "The House Outlives Its Builders",
      thesis: "Timber failed. The place endured.",
      body: [
        "Across the fertile soils of central Europe, longhouses gathered people, tools and stores beneath one roof, with livestock held close around the settlement. Posts rotted and walls were repaired. New buildings rose beside the marks of older ones. Wells, paths and worked ground tied neighbouring houses into a shared place. Cleared soil, stored grain and livestock made one generation’s labour part of the life awaiting the next.",
        "Burials and ancient pedigrees reveal that some communities organised this continuity through strong paternal lines. Women often arrived from other communities, creating connections between settlements. These patterns differed between places, but they show how fixed houses and repeatedly worked fields anchored kinship and obligation to a durable place.",
      ],
      image: `${imageRoot}/house-outlives-builders.webp`,
      imageAlt:
        "A partially cut-away Neolithic longhouse with older postholes visible in the soil.",
      imagePosition: "62% center",
      side: "left",
      sourceIds: ["rivollat-2023", "gelabert-2025"],
      evidence: [
        "Postholes, wall trenches, wells and repaired floors reveal houses rebuilt beside the footprints of earlier structures.",
        "Burials, strontium isotopes and ancient pedigrees reveal kinship, mobility and different local rules of residence.",
      ],
      map: { x: 49, y: 50 },
      interaction: {
        kind: "inspect",
        prompt: "Read the longhouse",
        accessibleSummary:
          "Four places in the longhouse connect storage, daily work, repair and earlier buildings.",
        items: [
          {
            id: "store",
            label: "The store",
            detail: "Stored grain carried one harvest into another season and another round of sowing.",
            x: 76,
            y: 38,
          },
          {
            id: "hearth",
            label: "The hearth",
            detail: "Work, food and memory returned to the same interior place.",
            x: 67,
            y: 62,
          },
          {
            id: "posts",
            label: "The posts",
            detail: "Repairs kept a structure alive beyond the strength of its first timbers.",
            x: 84,
            y: 68,
          },
          {
            id: "footprint",
            label: "The older house",
            detail: "Postholes fixed earlier households beneath the feet of later ones.",
            x: 45,
            y: 76,
          },
        ],
      },
    },
    {
      id: "more-mouths-more-land",
      order: 6,
      period: "5500–4000 BC",
      place: "The Danube and the Loess Belt",
      title: "More Mouths, More Land",
      thesis: "A household became a demographic force.",
      body: [
        "Across many regions, archaeological dates trace a rapid rise in population after farming arrived. Stored harvests, settled childcare and repeated cultivation were likely contributors, while permanent houses concentrated care and work in one place. One longhouse became several. Paths joined neighbouring clearings. Across the Danube corridor and the loess plains, village networks expanded within a few centuries. Along Mediterranean coasts, farming moved through a different chain of shores and islands.",
        "Growth demanded ground. Trees fell for fields, pasture and timber. Radiocarbon dates reveal regional population booms followed by contraction rather than a smooth advance. No single mechanism ended them: harvest failure, disease, conflict and local environmental strain acted in different combinations. Some houses emptied while people, seed and animals established settlements elsewhere. Farming spread through repeated growth, disruption and movement.",
      ],
      image: `${imageRoot}/more-mouths-more-land-v2.webp`,
      imageAlt:
        "Widely spaced Neolithic longhouses and irregular clearings within a still heavily wooded river plain.",
      imagePosition: "60% center",
      side: "left",
      sourceIds: ["shennan-2013", "shennan-2018"],
      evidence: [
        "Radiocarbon dates rise and fall in regional clusters, tracing population expansion and contraction rather than a smooth advance.",
        "Settlement plans, charcoal and pollen record new houses, clearance and later regrowth without yielding exact continent-wide household totals.",
      ],
      map: { x: 53, y: 57 },
      interaction: {
        kind: "growth",
        prompt: "Open the ground",
        accessibleSummary:
          "Three reconstructed landscape states move from one clearing to an expanding settlement zone and later local contraction.",
        stages: [
          {
            id: "one-house",
            label: "One clearing",
            detail: "A clearing held one household, its animals and a guarded store.",
            settlement: "A single longhouse",
            landscape: "Continuous woodland around a small worked opening",
            image: `${imageRoot}/one-house-one-clearing.webp`,
          },
          {
            id: "settlement-zone",
            label: "New clearings",
            detail: "Longhouses and fields spread through the loess belt while large tracts of woodland remained.",
            settlement: "Separated houses and linked clearings",
            landscape: "Fields, paths, regrowth and standing forest",
            image: `${imageRoot}/more-mouths-more-land-v2.webp`,
          },
          {
            id: "contraction",
            label: "Empty houses",
            detail: "Some local expansions ended; surviving households began elsewhere.",
            settlement: "Weathering structures without smoke",
            landscape: "Grass, scrub and young trees returning to worked ground",
            image: `${imageRoot}/empty-houses-regrowth.webp`,
          },
        ],
      },
    },
    {
      id: "a-continent-remade",
      order: 7,
      period: "4500–3300 BC",
      place: "Europe",
      title: "A Continent Remade",
      thesis: "Fields changed the land. Herds changed the traffic of disease.",
      body: [
        "By 3300 BC, fields, herds and permanent houses extended across much of Europe. Farming ancestry had mixed with local populations in different proportions. Pathogens had accompanied humans long before farming, but ancient DNA begins to reveal zoonotic pathogens from about 4500 BC. Their prevalence rose towards 3000 BC alongside widespread livestock keeping, then increased further during later pastoralist migrations. Grain-heavy diets and repeated labour also left marks on teeth and bone.",
        "Across the ten millennia that include this transformation, ancient genomes record strong directional selection at hundreds of variants. The first farmers did not possess one fixed European appearance: pigmentation-related variants changed in frequency across later millennia, just as ancestry continued to change. Some combinations of variants that now correlate with measures of cognitive performance also changed in frequency. Their effects in prehistoric lives are unknown, and they do not show that farming raised human intelligence.",
        "The languages of these farming communities are lost. Names they gave rivers, seasons and crops disappeared or survive beyond recognition. One recent language-tree model places an earlier Indo-European expansion among farming populations south of the Caucasus; ancient DNA associates many branches later spoken in Europe with populations moving west from the steppe after 3300 BC. Those steppe migrants entered a continent already organised around fields, herds and long-lived settlements.",
      ],
      image: "assets/europe-relief.webp",
      imageAlt:
        "A relief map of Europe, used to compare the spread of fields, herds and settled populations.",
      side: "right",
      sourceIds: [
        "mathieson-2018",
        "sikora-2025",
        "akbari-2026",
        "heggarty-2023",
        "lazaridis-2025",
      ],
      evidence: [
        "Human, animal and pathogen genomes preserve ancestry change, selection and the later rise of several zoonotic infections.",
        "Teeth and bone preserve diet, labour and disease; pollen, charcoal and settlement remains preserve altered land.",
        "No inscription records the languages of Europe’s first farmers.",
      ],
      map: { x: 50, y: 47 },
      interaction: {
        kind: "compare",
        prompt: "Set the two landscapes against each other",
        accessibleSummary:
          "A split view compares a river world around 7000 BC with a farming landscape around 4500 BC; four themes identify what changed and what the evidence cannot recover.",
        before: {
          label: "Iron Gates",
          period: "c. 7000 BC",
          image: `${imageRoot}/before-the-fields.webp`,
        },
        after: {
          label: "Loess belt",
          period: "c. 4500 BC",
          image: `${imageRoot}/more-mouths-more-land-v2.webp`,
        },
        layers: [
          {
            id: "land",
            label: "Land",
            detail: "Seasonal ranges became mosaics of field, pasture and managed woodland.",
          },
          {
            id: "people",
            label: "People",
            detail: "Migration, mixture and regional population growth changed who lived together.",
          },
          {
            id: "bodies",
            label: "Bodies",
            detail: "Diet, livestock and denser settlement changed exposure to disease and selection.",
          },
          {
            id: "languages",
            label: "Languages",
            detail: "The farmers’ languages are lost; later Indo-European branches entered an already farmed continent.",
          },
        ],
      },
    },
  ],
};
