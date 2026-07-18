import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/bronze-europe";

export const bronzeEurope: ChapterDefinition = {
  slug: "bronze-europe",
  number: "03",
  title: "Bronze Europe",
  period: "2500–500 BC",
  claim:
    "Metal, ships and sacred power joined Europe to the older worlds of Egypt and the East.",
  theme: {
    id: "bronze",
    label: "The bronze current",
  },
  openingAction: "Follow the bronze current",
  mapLabel: "The changing routes of Bronze Age Europe and the Mediterranean",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: `${imageRoot}/mediterranean-route.webp`,
  sourcesEyebrow: "Archaeology · metallurgy · shipwrecks · written archives · oral poetry",
  ending: {
    period: "By 700 BC",
    title: "The palace was gone. The heroic age remained.",
    detail:
      "Greek singers carried bronze names, weapons and memories into the new world of the polis, where public law and citizen armies would give Europe another form.",
    image: `${imageRoot}/10-singer-outlives-scribe.webp`,
    nextPeriod: "800–146 BC",
  },
  returnHash: "bronze-europe",
  nextHash: "greece-and-the-citizen",
  nextTitle: "Greece and the Citizen",
  movements: [
    {
      id: "a-sword-begins-in-an-older-world",
      order: 1,
      period: "c. 2500 BC",
      place: "Europe · Egypt · Mesopotamia",
      title: "A Sword Begins in an Older World",
      thesis: "Europe entered the Bronze Age beside civilizations already ancient.",
      body: [
        "A smith lifts a blade from its mould. The metal shines red-gold before air darkens it. Its edge can be sharpened, damaged and cast again. The sword will belong to a European warrior, yet the knowledge and materials behind it stretch far beyond his settlement. Copper came from a mine. Tin travelled from another geological world. Charcoal, clay, bellows, moulds and trained judgment brought them together. Bronze made distant places present in one object.",
        "Around 2500 BC, Europe held farms, fortified settlements, mining districts, river routes and steppe-descended societies. Across the sea, Egypt had already raised the pyramids of the Old Kingdom. The cities of Mesopotamia had temples, kings, scribes and archives centuries older than the first European palaces. These were neighbouring achievements around a shared zone of water, coast and caravan road, unequal in age and scale but increasingly joined by materials and desire.",
        "Europe’s Bronze Age began through that contact and grew through European command of it. Communities from the Aegean to the Atlantic learned to extract ore, control heat, cast repeatable forms, sail open water and turn rare metal into rank. A sword therefore opens two histories at once: the older urban world around the eastern Mediterranean and the European societies that mastered its most powerful material.",
      ],
      image: `${imageRoot}/the-great-sea.webp`,
      mobileImage: `${imageRoot}/the-great-sea-mobile.webp`,
      imageAlt:
        "A Bronze Age sailing vessel crosses the Mediterranean at dawn beneath a limestone harbour.",
      imagePosition: "54% center",
      mobileImagePosition: "56% center",
      visualTone: "dawn",
      side: "left",
      sourceIds: ["met-first-cities", "met-old-kingdom", "artioli-2024"],
      evidence: [
        "Urban monuments, administrative texts and excavated workshops place Egypt and Mesopotamia within long-lived state traditions before 2500 BC.",
        "Ore chemistry and lead-isotope analysis can connect copper objects to changing mining regions, while remelting and mixed metal complicate any single-object itinerary.",
      ],
      map: { x: 67, y: 70 },
    },
    {
      id: "copper-and-tin-had-to-meet",
      order: 2,
      period: "2500–1600 BC",
      place: "Mines · passes · coasts",
      title: "Copper and Tin Had to Meet",
      thesis: "Bronze was a metal of separated origins and organised skill.",
      body: [
        "Copper could be mined in Cyprus, the Alps, Iberia, the Balkans and other ore zones. Tin was rarer and often farther away. Neither map stayed fixed. Deposits opened and declined; old objects returned to the crucible; merchants changed partners; damaged tools became raw material. Every casting therefore began before the furnace, in the labour that found ore, cut timber, carried loads through passes and moved ingots along rivers and coasts.",
        "The smith controlled the decisive transformation. He judged colour, heat and flow without a thermometer. Too little tin left copper soft. Too much could make the alloy brittle. A useful proportion often lay near one part tin to nine parts copper, adjusted for the object and the available metal. Stone, clay or bronze moulds turned the liquid alloy into axes, sickles, spearheads, ornaments, vessels and swords. Hammering and sharpening finished what casting began.",
        "The process joined specialists who may never have met: miner, charcoal burner, carrier, sailor, broker, patron and smith. No central authority commanded the whole European system. Repeated trust, gift, debt, armed protection and local power kept metal moving. Bronze rewarded communities able to hold several stages together. Its beauty came from heat and form; its political force came from the route behind the finished edge.",
      ],
      image: `${imageRoot}/02-copper-and-tin.webp`,
      imageAlt:
        "Bronze Age smiths pour glowing alloy into a sword mould beside copper and tin stores.",
      imagePosition: "57% center",
      visualTone: "forge",
      side: "right",
      sourceIds: ["artioli-2024", "kristiansen-2015"],
      evidence: [
        "Mines, slag, crucibles, moulds, ingots and metal chemistry preserve different stages of extraction, alloying, casting and recycling.",
        "Provenance methods identify likely ore relationships rather than a complete named chain of owners between a mine and a finished blade.",
      ],
      map: { x: 49, y: 57 },
      interaction: {
        kind: "route",
        prompt: "Assemble the blade",
        accessibleSummary:
          "Four linked points follow copper and tin from separate origins through alloying to a finished bronze sword.",
        points: [
          {
            id: "copper",
            label: "Copper",
            detail:
              "Bulk metal begins in ore districts, where mining, crushing, fuel and smelting turn rock into transportable copper.",
            x: 15,
            y: 66,
          },
          {
            id: "tin",
            label: "Tin",
            detail:
              "Scarcer tin enters through a different chain of deposits, traders and routes; its separation gives the network its reach.",
            x: 37,
            y: 35,
          },
          {
            id: "alloy",
            label: "Alloy",
            detail:
              "The smith controls heat and proportion, making an alloy harder and more castable than unalloyed copper.",
            x: 66,
            y: 53,
          },
          {
            id: "sword",
            label: "Sword",
            detail:
              "Casting, hammering and sharpening concentrate a continent of labour into one weapon and badge of rank.",
            x: 88,
            y: 27,
          },
        ],
      },
    },
    {
      id: "crete-faces-three-continents",
      order: 3,
      period: "1900–1450 BC",
      place: "Crete · the Great Sea",
      title: "Crete Faces Three Continents",
      thesis: "The first European palace civilization grew where three shores met.",
      body: [
        "Crete lies lengthwise across the routes between the Aegean, Egypt and the Levant. Around 1900 BC, great centres rose at Knossos, Phaistos, Malia and Zakros. Paved courts organised movement through multi-storeyed buildings. Storerooms held rows of huge jars. Light wells, drains, painted plaster and finely cut masonry turned administration into architecture. These were workshops, ritual centres, residences and gathering places built to command both harvest and spectacle.",
        "Palace scribes kept accounts in Cretan hieroglyphic and Linear A, a script that remains undeciphered. Craftsmen worked gold, ivory, stone, faience, pottery and bronze with extraordinary control. Frescoes set processions, animals and human bodies in fields of colour. Ships carried timber, cloth, oil, wine and crafted goods outward; tin, copper, gold, silver, ivory and fine stone came back. The island’s art travelled with its containers and its habits of display.",
        "Crete stood inside Europe and looked toward three continents. Its strength came from acting as a hinge between them. Egyptian and Near Eastern forms entered an island society that selected, altered and exported them. Mainland Greeks then learned from Crete’s scripts, images, weights, palatial practices and seafaring. The European palace world was born facing south and east across the sea.",
      ],
      image: `${imageRoot}/03-crete-three-continents.webp`,
      imageAlt:
        "A Minoan harbour below a painted palace, with ships, jars and workshops facing the sea.",
      imagePosition: "52% center",
      visualTone: "harbour",
      side: "left",
      sourceIds: ["hemingway-minoan-2002", "kristiansen-2015"],
      evidence: [
        "Palaces, paved courts, storerooms, workshops, frescoes and administrative tablets establish concentrated economic, ritual and artistic activity on Crete.",
        "Linear A records palace administration but has not been deciphered, so political titles and spoken narratives remain largely unknown.",
      ],
      map: { x: 66, y: 78 },
    },
    {
      id: "the-sea-carries-power",
      order: 4,
      period: "1700–1200 BC",
      place: "Aegean · Mediterranean · Atlantic",
      title: "The Sea Carries Power",
      thesis: "A ship made water into a road, provided men could read it.",
      body: [
        "A Bronze Age hull had no engine, compass or chart. Its crew read wind on the surface, the colour of shoaling water, the flight of birds, the shape of a distant headland and the order of stars. Sail and oar worked together. Stone anchors held the vessel when a cove offered shelter. Timber joined by pegged mortise-and-tenon seams flexed under load. Seamanship turned exposed water from danger into reach.",
        "Most voyages linked familiar coasts, islands and hosts. Cargo could pass through many hands without one merchant travelling from its source to its destination. Ports were social instruments: a captain needed water, repair timber, interpreters, protection and someone willing to receive him. Gifts opened halls. Weights made value comparable. Marriage, guest-friendship and oath carried trust across the gaps between political powers.",
        "Sea power therefore belonged to organised crews and the rulers who could sustain them. In the Aegean, ships bound palaces to islands, Cyprus, Anatolia, Egypt and the Levant. Farther west and north, coastal skill joined Atlantic façades, river mouths and Baltic approaches. Different vessel traditions worked different waters. Together they made Europe a peninsula articulated by seas rather than a landmass divided by them.",
      ],
      image: `${imageRoot}/04-sea-carries-power.webp`,
      imageAlt:
        "A convoy of Bronze Age sailing vessels crosses open blue water between distant headlands.",
      imagePosition: "48% center",
      visualTone: "open-sea",
      side: "right",
      sourceIds: ["ina-uluburun", "kristiansen-2015"],
      evidence: [
        "Shipwreck timbers, anchors, harbour sites, cargo distributions and boat images document construction, navigation and repeated maritime movement.",
        "Cargo provenance reveals connected regions; it seldom proves that one sailor or merchant completed the entire route.",
      ],
      map: { x: 60, y: 73 },
    },
    {
      id: "the-palaces-count-the-world",
      order: 5,
      period: "1600–1200 BC",
      place: "Mycenae · Pylos · Knossos",
      title: "The Palaces Count the World",
      thesis: "The Aegean rulers made writing serve bronze, grain, cloth and the gods.",
      body: [
        "On the Greek mainland, strongholds rose at Mycenae, Tiryns, Thebes and Pylos. Their walls, gateways, bridges, tombs and drainage works demanded organised labour. Within the palace, the ruler’s hall centred on a round hearth. Painted floors and walls staged power in colour. Storerooms and workshops gathered oil, wine, wool, grain, timber and metal. A court could equip chariots, feed retainers, honour gods and send crafted goods toward distant shores.",
        "Scribes pressed a sharpened stylus into damp clay. Linear B adapted an Aegean script to an early form of Greek. The tablets counted land, sheep, women and men, cloth, vessels, rations, offerings and bronze assigned to smiths. They were working records, not literature. Fire preserved many by baking tablets that administrators had expected to recycle. Their narrow purpose now reveals the machinery of a palace in remarkable detail.",
        "The Mycenaean world joined armed kingship to administration. Gold cups, seal stones and inlaid weapons concentrated distant materials in elite graves and halls. Fortifications displayed the capacity to mobilise stone and men. The archive turned obligations into numbers. European power had acquired its own written Greek voice, though that voice spoke in lists long before it sang in hexameter.",
      ],
      image: `${imageRoot}/05-palaces-count-world.webp`,
      imageAlt:
        "Mycenaean scribes record stores on clay tablets beside jars, bronze and woven goods.",
      imagePosition: "60% center",
      visualTone: "archive",
      side: "left",
      sourceIds: ["hemingway-mycenaean-2003", "kirk-1961"],
      evidence: [
        "Fortified centres, storerooms, workshops, monumental tombs and Linear B archives document the material and administrative reach of Mycenaean palaces.",
        "Linear B records an early Greek language and names familiar gods, yet the surviving tablets contain accounts rather than heroic poetry.",
      ],
      map: { x: 64, y: 72 },
    },
    {
      id: "the-north-makes-bronze-its-own",
      order: 6,
      period: "1700–500 BC",
      place: "Jutland · Zealand · Tanum",
      title: "The North Makes Bronze Its Own",
      thesis: "Beyond the metal’s mines, northern Europe created a bronze world of ships and sun.",
      body: [
        "The Nordic Bronze Age rested on farms. Families lived in longhouses shared with stores and livestock, cultivated grain and managed cattle across a worked landscape. Surplus supported voyages, feasts, mound building and skilled craft. The north possessed little copper or tin, so every bronze blade declared the strength of a route. Amber moved outward from Baltic shores. Metal and blue glass came back through linked continental exchanges.",
        "Northern smiths gave imported material a distinct grammar. Swords balanced for the hand; spiral ornaments held light; lurs turned bronze into sound. The Trundholm sun chariot joined a gilded disc to a wheeled horse. Rock carvings at places such as Tanum filled stone with ships, crews, weapons, animals and ritual figures. Barrows raised selected dead above the horizon, while preserved oak coffins held wool clothing, hair, wood and bronze close to the body.",
        "The ship became the north’s commanding sign because the sea was its road. Images of long, crewed vessels appeared on razors, stones and metalwork even when the metal itself had crossed mountains far to the south. This was a confident European transformation: foreign ore, local farms, northern water and a sacred imagination of sun, voyage and return fused into one civilisation.",
      ],
      image: `${imageRoot}/06-north-makes-bronze.webp`,
      imageAlt:
        "A Nordic Bronze Age coast with longhouse, boat, burial mound, amber, sword and carved ship images.",
      imagePosition: "48% center",
      visualTone: "northern-sun",
      side: "right",
      sourceIds: ["horn-2024", "kristiansen-2015"],
      evidence: [
        "Longhouses, agricultural remains, barrows, oak coffins, metalwork, amber, imported glass and rock art preserve the northern economic and sacred landscape.",
        "Ship images are abundant, while surviving hulls are rare; scale and construction must be reconstructed from carvings, associated finds and later boat traditions.",
      ],
      map: { x: 49, y: 28 },
      interaction: {
        kind: "inspect",
        prompt: "Read the northern bronze world",
        accessibleSummary:
          "Four details connect the farm, amber route, ship image and crafted bronze of the Nordic Bronze Age.",
        items: [
          {
            id: "longhouse",
            label: "Longhouse",
            detail:
              "Grain, cattle, stored labour and household continuity supplied the surplus behind voyages, feasts and monuments.",
            x: 26,
            y: 48,
          },
          {
            id: "amber",
            label: "Amber",
            detail:
              "Baltic amber moved south as a desired material and helped draw metal and glass back toward northern shores.",
            x: 43,
            y: 73,
          },
          {
            id: "ship",
            label: "Ship",
            detail:
              "Carved crews and long hulls made seafaring the era’s most repeated northern image of movement and power.",
            x: 70,
            y: 42,
          },
          {
            id: "sword",
            label: "Sword",
            detail:
              "Imported alloy became a locally balanced weapon, inheritance and public sign of a warrior’s rank.",
            x: 82,
            y: 71,
          },
        ],
      },
    },
    {
      id: "the-warrior-carries-his-rank",
      order: 7,
      period: "1600–1100 BC",
      place: "Europe · the Aegean",
      title: "The Warrior Carries His Rank",
      thesis: "Bronze gave courage a visible form and violence a trained edge.",
      body: [
        "The sword was made for combat. An axe could work timber and a spear could hunt; a sword concentrated metal in a weapon whose principal field was another armed body. Its owner trained the hand, shoulder and foot to control distance. A long blade demanded expensive alloy, skilled casting and careful repair. Carried at the hip or placed in a grave, it marked a man whose household could command resources beyond ordinary work.",
        "Warriors rarely stood alone. Retinues formed around leaders who could feed, equip and reward them. Feasting converted cattle, grain, wine and metal vessels into loyalty. Gifts circulated swords, cups, horses, chariot fittings and ornaments through ties between halls. Raiding took animals, metal and captives; defence required walls, watch, weapons and allies. The same routes that carried craftsmen and brides could also carry armed companies.",
        "Across Europe, elite burials and weapons began to resemble one another without dissolving local cultures into a single people. A Mycenaean chariot warrior, a central European swordsman and a Nordic chief lived in different political worlds. Each understood bronze as controlled splendour, inherited rank and the capacity for force. The heroic ideal grew from that union of generosity, courage, reputation and danger.",
      ],
      image: `${imageRoot}/07-warrior-carries-rank.webp`,
      imageAlt:
        "A Bronze Age smith presents a flange-hilt sword to an unarmoured warrior and his retinue.",
      imagePosition: "54% center",
      visualTone: "warrior",
      side: "left",
      sourceIds: ["kristiansen-2015", "horn-2024", "hemingway-mycenaean-2003"],
      evidence: [
        "Swords, spears, shields, armour, trauma, fortifications and martial images preserve the material investment in organised violence.",
        "Grave goods reveal selected public identities; they cannot identify every role a buried person held while alive.",
      ],
      map: { x: 50, y: 53 },
    },
    {
      id: "a-world-in-one-hold",
      order: 8,
      period: "c. 1320 BC",
      place: "Uluburun · southern Anatolia",
      title: "A World in One Hold",
      thesis: "One lost ship carried the materials of an international age.",
      body: [
        "Near Uluburun, off the southern coast of Anatolia, a ship went down around 1320 BC. Its timbers disappeared almost entirely, but the seabed held the load. Hundreds of copper ingots lay with tin in roughly the ratio needed for bronze. Canaanite jars carried food or resin. Blue glass ingots, ivory, ebony, ostrich eggshell, faience, gold, silver, amber, pottery, weapons, tools, weights and personal possessions shared the same wreck.",
        "The cargo had no single cultural label. Copper pointed strongly toward Cyprus; the ship’s cedar construction and pottery belonged to the eastern Mediterranean; objects and passengers linked the voyage to the Aegean, Egypt, the Levant and lands farther away. Baltic amber reached this southern route. A scarab bearing Nefertiti’s name entered the assemblage. Balance weights allowed merchants or officials to compare value across languages and courts.",
        "Uluburun does not reveal one open market governed from a single centre. It reveals something grander and more human: specialised producers, courtly demand, sailors, brokers and trusted measures holding a fragile system together. A storm or navigational error placed an international age on the seabed. The ship’s hold lets us see the density of the Great Sea at its height.",
      ],
      image: `${imageRoot}/08-world-in-one-hold.webp`,
      imageAlt:
        "The Uluburun ship carries copper and tin ingots, jars, glass, ivory, amber and gold across the Mediterranean.",
      imagePosition: "58% center",
      visualTone: "cargo",
      side: "right",
      sourceIds: ["ina-uluburun", "kristiansen-2015"],
      evidence: [
        "The wreck date, hull remains and excavated cargo provide an unusually concentrated record of Late Bronze Age shipbuilding and exchange.",
        "Object origins and cargo composition demonstrate wide connections; the vessel’s exact departure, intended ports and political sponsor remain debated.",
      ],
      map: { x: 75, y: 78 },
      interaction: {
        kind: "inspect",
        prompt: "Open the hold",
        accessibleSummary:
          "Four cargo groups reveal the alloy, provisions, luxury materials and people carried by the Uluburun ship.",
        items: [
          {
            id: "alloy",
            label: "Copper + tin",
            detail:
              "The bulk cargo carried the two separated metals in roughly the proportion needed to make bronze.",
            x: 24,
            y: 66,
          },
          {
            id: "jars",
            label: "Jars + resin",
            detail:
              "Containers held provisions and raw material, tying the voyage to producers and consumers ashore.",
            x: 62,
            y: 45,
          },
          {
            id: "luxuries",
            label: "Glass + ivory",
            detail:
              "Blue glass, tusks, gold, stones and amber served wealthy workshops, courts and gifts.",
            x: 79,
            y: 73,
          },
          {
            id: "people",
            label: "Weights + tools",
            detail:
              "Weights, weapons, galley ware and instruments preserve the working and personal world of crew and passengers.",
            x: 47,
            y: 28,
          },
        ],
      },
    },
    {
      id: "when-the-palaces-burn",
      order: 9,
      period: "c. 1220–1050 BC",
      place: "Eastern Mediterranean",
      title: "When the Palaces Burn",
      thesis: "The connected palace order failed in different places for different reasons.",
      body: [
        "Around 1200 BC, fire reached palaces, cities and ports across parts of the eastern Mediterranean. Mycenaean centres were destroyed or abandoned. The Hittite imperial system ended. Ugarit disappeared. Egypt fought off attacks and retained a state at reduced power. Linear B administration ceased with the Greek palaces. Routes that had supplied courts with copper, tin, glass, ivory, grain and prestige goods lost some of their strongest patrons and protectors.",
        "No single invader or drought explains the full geography. Warfare, migration, internal revolt, political rivalry, food stress, earthquake and the fragility of tightly managed systems acted in different combinations. Destruction layers have different dates and causes. Some places contracted; some moved; some trading communities prospered by working around fallen centres. The failure of a palace did not erase farmers, potters, sailors, smiths or every route they knew.",
        "The crisis was severe and regional, not the end of Bronze Age Europe as one synchronous whole. Nordic and Atlantic societies followed their own chronologies. Cyprus and parts of the Aegean reorganised. Iron gained ground gradually while bronze remained valued. What vanished most decisively in Greece was a form of central rule: the fortified court, its appointed collectors and its clay archive. Political memory now had to travel without palace scribes.",
      ],
      image: `${imageRoot}/09-palaces-burn.webp`,
      imageAlt:
        "A Mycenaean archive burns at night as clay tablets, jars and roof beams fall into ash.",
      imagePosition: "42% center",
      visualTone: "fire",
      side: "left",
      sourceIds: ["middleton-2023", "kotsonas-2025"],
      evidence: [
        "Destruction horizons, abandonment, settlement shifts, changing burials and the end of Linear B administration document a major Aegean political transformation.",
        "Chronology and regional sequences reject a single simultaneous collapse; causes must be argued site by site and system by system.",
      ],
      map: { x: 67, y: 74 },
    },
    {
      id: "the-singer-outlives-the-scribe",
      order: 10,
      period: "1100–700 BC",
      place: "Greece · the Aegean",
      title: "The Singer Outlives the Scribe",
      thesis: "When the archive fell silent, heroic memory passed from voice to voice.",
      body: [
        "A Linear B tablet could tell a palace how much bronze it had assigned to smiths. It could not carry a song after the officials who understood its system disappeared. Greek speech continued without the script. In halls, sanctuaries, feasts and travelling performances, singers worked with metre, formula and remembered names. Repetition made long poems durable while each performance kept them responsive to a new audience.",
        "The Iliad and Odyssey took monumental form centuries after the Mycenaean palaces. Their language preserves old elements beside later ones. Bronze weapons, boar’s-tusk helmets, chariots, great halls and heroic names connect the poems to the lost age, while assemblies, social relations and combat often belong to the world of the singers. Homer is therefore neither an eyewitness nor a free inventor. Oral tradition compressed generations of memory into an intelligible heroic past.",
        "That past became a European inheritance because Greeks carried it into sanctuaries, colonies, schools, theatres, libraries and political argument. Achilles made honour and mortality inseparable; Odysseus made endurance, speech and homecoming instruments of survival. The bronze warrior had entered poetry. The next age would move power beyond the hall, onto the public ground of the citizen.",
      ],
      image: `${imageRoot}/10-singer-outlives-scribe.webp`,
      imageAlt:
        "An early Greek singer performs with a lyre before a household fire beside the Aegean at night.",
      imagePosition: "50% center",
      visualTone: "memory",
      side: "right",
      sourceIds: ["kirk-1961", "kotsonas-2025", "hemingway-mycenaean-2003"],
      evidence: [
        "Linear B preserves early Greek administrative language but no epic poetry; Homeric diction contains forms inherited from older stages of Greek.",
        "The poems combine material and linguistic memories from the Bronze Age with institutions and practices shaped during the centuries of oral transmission.",
      ],
      map: { x: 64, y: 72 },
      interaction: {
        kind: "compare",
        prompt: "Move from account to memory",
        accessibleSummary:
          "A comparison between the palace archive and the singer’s performance follows language, institutions and heroic memory across the break.",
        before: {
          label: "The scribe",
          period: "c. 1200 BC",
          image: `${imageRoot}/05-palaces-count-world.webp`,
        },
        after: {
          label: "The singer",
          period: "c. 750 BC",
          image: `${imageRoot}/10-singer-outlives-scribe.webp`,
        },
        layers: [
          {
            id: "language",
            label: "Language",
            detail:
              "Greek speech survives the loss of Linear B; a new alphabet later gives that language another written form.",
          },
          {
            id: "institutions",
            label: "Institutions",
            detail:
              "Palace collectors and archives disappear while smaller communities, sanctuaries and assemblies organise the social world.",
          },
          {
            id: "memory",
            label: "Memory",
            detail:
              "Formula, metre and performance preserve names and objects while reshaping their meaning for successive audiences.",
          },
        ],
      },
    },
  ],
};
