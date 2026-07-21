import type { StoryScene } from "../types/story";

export const scenes: StoryScene[] = [
  {
    id: "first-farmers",
    order: 1,
    era: "origins",
    period: { start: -7000, end: -3300, label: "7000–3300 BC" },
    title: "The First Farmers",
    kicker: "A Settled Continent",
    thesis:
      "Farming reached Europe chiefly with people whose ancestry traced to Anatolian farming populations, changing land and population together.",
    body: "The first European fields were sown by farming communities moving from western Anatolia. They crossed the Aegean, established villages in the Balkans and followed the Danube towards central Europe. Others moved west along Mediterranean coasts. Wheat, barley, sheep and cattle travelled with them, together with the knowledge needed to store a harvest, fire a pot and cultivate the same ground again. Clearings opened within woodland for fields and pasture; grain stores supported denser settlements. Established river and forest communities traded with the villages, joined households and adopted selected practices. By the time riders appeared on the eastern plains, farming had already remade Europe’s landscape, diet and population.",
    focus: { latitude: 40.2, longitude: 25.2 },
    camera: { x: 0.525, y: 0.69, scale: 1.38, rotation: -0.01 },
    palette: "aegean",
    layers: ["terrain", "migration", "settlements", "route"],
    sourceIds: ["shennan-2018"],
    landmark: "The Aegean and the Danube",
    side: "left",
    interaction: {
      family: "route",
      prompt: "Follow the farming frontier",
      accessibleSummary:
        "Three stages trace farming communities from Anatolia through the Aegean and Danube corridor into central Europe.",
      mapScope: "europe",
      steps: [
        {
          id: "aegean-crossing",
          label: "The Aegean",
          summary:
            "Farming communities crossed from western Anatolia into the Aegean and established some of Europe’s earliest farming villages.",
          points: [
            { latitude: 38.5, longitude: 30.5, label: "Western Anatolia" },
            { latitude: 39.5, longitude: 22.5, label: "Thessaly" },
          ],
        },
        {
          id: "danube-corridor",
          label: "The Danube",
          summary:
            "Rivers became corridors for people, livestock, seed and knowledge.",
          points: [
            { latitude: 39.5, longitude: 22.5, label: "Thessaly" },
            { latitude: 44.7, longitude: 22.4, label: "Iron Gates" },
            { latitude: 47.5, longitude: 19, label: "Middle Danube" },
          ],
        },
        {
          id: "central-villages",
          label: "New villages",
          summary:
            "Permanent settlements spread across the loess plains of central Europe.",
          points: [
            { latitude: 44.7, longitude: 22.4, label: "Iron Gates" },
            { latitude: 47.5, longitude: 19, label: "Middle Danube" },
            { latitude: 50.1, longitude: 14.4, label: "Central Europe" },
            { latitude: 50.8, longitude: 6.1, label: "Rhine frontier" },
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "thessaly",
        label: "Thessaly",
        detail:
          "Some of Europe’s earliest farming villages appeared on this fertile plain, joining Anatolian practices to local landscapes.",
        latitude: 39.5,
        longitude: 22.5,
      },
      {
        id: "iron-gates",
        label: "The Iron Gates",
        detail:
          "At this Danube gorge, incoming farmers and established river communities met, exchanged practices and formed new populations.",
        latitude: 44.7,
        longitude: 22.4,
      },
      {
        id: "central-europe",
        label: "Central European villages",
        detail:
          "Longhouses and fields spread rapidly along the fertile loess belt, creating a connected farming landscape.",
        latitude: 50.1,
        longitude: 14.4,
      },
    ],
    chronicle: {
      href: "chapters/first-farmers/",
      label: "Enter the first fields",
    },
  },
  {
    id: "steppe-comes-west",
    order: 2,
    era: "origins",
    period: { start: -3300, end: -2000, label: "3300–2000 BC" },
    title: "The Steppe Comes West",
    kicker: "Origins",
    thesis:
      "Mobile, armed and patrilineal communities from the Pontic steppe transformed Europe’s population and inheritance.",
    body: "Around 3000 BC, people from the grasslands north of the Black Sea moved west in large numbers. Herds and ox-drawn wagons carried households across the lower Danube; widespread horse-based mobility came centuries later. Ancient DNA reveals the scale: sampled Corded Ware communities in Germany derived about three quarters of their ancestry from Yamnaya-related populations. Burial mounds fixed paternal lines to the landscape, while weapons and male-biased migration reordered power and descent. Speech travelled with kinship, marriage and command. From the lower Dnipro to central Europe and Iberia, steppe migration created new populations and helped Indo-European languages and inherited religious traditions spread.",
    focus: { latitude: 47, longitude: 38 },
    camera: { x: 0.682, y: 0.532, scale: 1.28, rotation: -0.018 },
    palette: "steppe",
    layers: ["terrain", "migration", "route", "landmark"],
    sourceIds: ["haak-2015", "lazaridis-2025"],
    landmark: "The Pontic Steppe",
    side: "right",
    interaction: {
      family: "route",
      prompt: "Trace the steppe movement",
      accessibleSummary:
        "The route moves from the lower Dnipro through the Danube plains and into the Corded Ware horizon of central Europe.",
      mapScope: "europe",
      steps: [
        {
          id: "steppe-homeland",
          label: "The steppe",
          summary:
            "River, grassland and forest formed a mobile frontier north of the Black Sea.",
          points: [
            { latitude: 47.5, longitude: 34.5, label: "Lower Dnipro" },
            { latitude: 47, longitude: 38, label: "Pontic Steppe" },
          ],
        },
        {
          id: "westward",
          label: "Westward",
          summary:
            "People, herds and wagons moved through the plains north of the lower Danube.",
          points: [
            { latitude: 47.5, longitude: 34.5, label: "Lower Dnipro" },
            { latitude: 46.2, longitude: 28, label: "Lower Danube" },
            { latitude: 47.5, longitude: 19, label: "Carpathian Basin" },
          ],
        },
        {
          id: "corded-ware-spread",
          label: "Corded Ware",
          summary:
            "Steppe-related ancestry and new social networks spread deep into central and northern Europe.",
          points: [
            { latitude: 47.5, longitude: 19, label: "Carpathian Basin" },
            { latitude: 51, longitude: 14, label: "Central Europe" },
            { latitude: 55.7, longitude: 12.6, label: "Southern Scandinavia" },
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "lower-dnipro",
        label: "Lower Dnipro",
        detail:
          "Steppe, river and forest met here, linking mobile pastoral worlds to farming societies farther west.",
        latitude: 47.5,
        longitude: 34.5,
      },
      {
        id: "corded-ware",
        label: "Corded Ware horizon",
        detail:
          "By the third millennium BC, steppe-related ancestry had reached central Europe alongside new burials and social networks.",
        latitude: 51,
        longitude: 14,
      },
    ],
    chronicle: {
      href: "chapters/steppe-comes-west/",
      label: "Enter the eastern grasslands",
    },
  },
  {
    id: "bronze-europe",
    order: 3,
    era: "origins",
    period: { start: -2500, end: -500, label: "2500–500 BC" },
    title: "Bronze Europe",
    kicker: "Ships, Amber and the Northern Sun",
    thesis:
      "Bronze tied the Nordic world to mines, ports and trading communities far beyond the Baltic.",
    body: "A bronze sword buried in Scandinavia began as ore somewhere else. Copper and tin rarely lay near one another, so every axe, razor and ornament depended on miners, sailors, traders and metalworkers spread across great distances. Copper moved north from the Alps, Wales and more distant sources; Baltic amber travelled south towards the Aegean. The Nordic Bronze Age grew inside this traffic. Longhouses and burial mounds overlooked busy waterways, while rock carvings filled Scandinavian stone with ships, crews and warriors. Chiefs turned imported metal into gifts, weapons and ceremony. Command of the sea routes became a source of authority at home.",
    focus: { latitude: 55.8, longitude: 10.2 },
    camera: { x: 0.34, y: 0.34, scale: 1.16, rotation: -0.006 },
    palette: "steppe",
    layers: ["terrain", "metals", "amber", "sea-routes"],
    sourceIds: ["horn-2024", "kristiansen-2015"],
    landmark: "The Nordic Seas",
    side: "left",
    interaction: {
      family: "network",
      prompt: "Reveal the Bronze Age networks",
      accessibleSummary:
        "Three views show imported metals moving north, amber moving south and maritime links connecting Nordic, Atlantic and Mediterranean regions.",
      mapScope: "europe",
      steps: [
        {
          id: "metals-north",
          label: "Metals north",
          summary:
            "Every piece of Nordic bronze depended on copper and tin arriving from beyond Scandinavia.",
          points: [
            { latitude: 53.3, longitude: -3.8, label: "Great Orme" },
            { latitude: 50.3, longitude: -5.1, label: "Cornwall" },
            { latitude: 47.4, longitude: 13, label: "Mitterberg" },
            { latitude: 57, longitude: 9.2, label: "Limfjord" },
            { latitude: 58.7, longitude: 11.3, label: "Tanum" },
          ],
          links: [
            [0, 3],
            [1, 3],
            [2, 3],
            [2, 4],
          ],
        },
        {
          id: "amber-south",
          label: "Amber south",
          summary:
            "Northern amber became a precious material far beyond the Baltic and North Sea.",
          points: [
            { latitude: 57, longitude: 9.2, label: "Limfjord" },
            { latitude: 54.5, longitude: 10.2, label: "Western Baltic" },
            { latitude: 50.1, longitude: 14.4, label: "Central Europe" },
            { latitude: 37.7, longitude: 22.8, label: "Mycenae" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
          ],
        },
        {
          id: "northern-seaways",
          label: "Ships and rock art",
          summary:
            "Maritime skill tied coastal communities together and gave Nordic elites access to distant worlds.",
          points: [
            { latitude: 57, longitude: 9.2, label: "Limfjord" },
            { latitude: 58.7, longitude: 11.3, label: "Tanum" },
            { latitude: 58.8, longitude: 5.7, label: "Jæren" },
            { latitude: 50.3, longitude: -5.1, label: "Cornwall" },
            { latitude: 35.2, longitude: 25.1, label: "Crete" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
            [3, 4],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "limfjord",
        label: "Limfjord",
        detail:
          "Amber, flint, productive farmland and sheltered water made this region a northern centre of exchange and maritime power.",
        latitude: 57,
        longitude: 9.2,
      },
      {
        id: "tanum",
        label: "Tanum",
        detail:
          "Thousands of rock carvings preserve ships, warriors, animals and rituals from a society oriented toward the sea.",
        latitude: 58.7,
        longitude: 11.3,
      },
      {
        id: "mycenae",
        label: "Mycenae",
        detail:
          "The palace worlds of the Aegean stood at the southern end of networks carrying metal, amber, weapons and prestige.",
        latitude: 37.73,
        longitude: 22.75,
      },
    ],
    chronicle: {
      href: "chapters/bronze-europe/",
      label: "Enter the great sea",
    },
  },
  {
    id: "greece-and-the-citizen",
    order: 4,
    era: "classical",
    period: { start: -800, end: -146, label: "800–146 BC" },
    title: "Greece and the Citizen",
    kicker: "The Polis",
    thesis:
      "The Greek polis made government something citizens could argue about in public.",
    body: "Politics in a Greek polis happened at shouting distance. Citizens met in assemblies, sat on juries and fought beside men whose proposals they had just opposed. In Athens, speakers persuaded the assembly, magistrates faced scrutiny and large citizen juries decided public cases. Sparta, Corinth and hundreds of smaller cities organised power in their own ways, turning the Greek world into a field of political experiments. Resistance to Persia joined civic freedom to military survival. Historians recorded the choices of statesmen; philosophers asked which constitution formed the best citizens. Europe inherited from the polis a durable question: who should rule, and by what right?",
    focus: { latitude: 37.98, longitude: 23.72 },
    camera: { x: 0.514, y: 0.724, scale: 1.62, rotation: 0.012 },
    palette: "aegean",
    layers: ["terrain", "coast", "poleis", "route"],
    sourceIds: ["cartledge-2009"],
    landmark: "The Athenian Acropolis",
    side: "right",
    interaction: {
      family: "compare",
      prompt: "Compare city and empire",
      accessibleSummary:
        "The comparison contrasts the network of autonomous Greek poleis with the much larger Persian imperial world they resisted.",
      mapScope: "europe",
      steps: [
        {
          id: "poleis",
          label: "The poleis",
          summary:
            "Hundreds of small political communities offered rival forms of citizenship and rule.",
          points: [
            { latitude: 37.98, longitude: 23.72, label: "Athens" },
            { latitude: 37.08, longitude: 22.43, label: "Sparta" },
            { latitude: 37.94, longitude: 22.93, label: "Corinth" },
            { latitude: 38.48, longitude: 22.5, label: "Delphi" },
          ],
          links: [
            [0, 2],
            [1, 2],
            [2, 3],
          ],
        },
        {
          id: "persian-pressure",
          label: "The imperial challenge",
          summary:
            "Persian expansion made the political autonomy of the city-states a question of survival.",
          points: [
            { latitude: 38.8, longitude: 22.54, label: "Thermopylae" },
            { latitude: 38, longitude: 23.5, label: "Attica" },
            { latitude: 39, longitude: 26, label: "Aegean frontier" },
            { latitude: 38, longitude: 29, label: "Anatolian satrapies" },
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "athens",
        label: "Athens",
        detail:
          "The assembly, council and popular courts made political argument part of the city’s ordinary business.",
        latitude: 37.98,
        longitude: 23.72,
      },
      {
        id: "thermopylae",
        label: "Thermopylae",
        detail:
          "The pass became a lasting memory of resistance during the Persian invasion of 480 BC.",
        latitude: 38.8,
        longitude: 22.54,
      },
    ],
    chronicle: {
      href: "chapters/greece-and-the-citizen/",
      label: "Enter the public ground",
    },
  },
  {
    id: "rome-gathers-europe",
    order: 5,
    era: "classical",
    period: { start: -509, end: 212, label: "509 BC–AD 212" },
    title: "Rome Gathers Europe",
    kicker: "One Political World",
    thesis:
      "Rome made conquest durable by giving provincial communities a place within the empire.",
    body: "Roman legions conquered the Mediterranean; roads, cities and citizenship made the conquests hold. Rome recruited provincial elites, preserved useful local customs and gave municipal councils responsibility for taxes and order. A notable in Gaul or Spain could govern his city, enter imperial service and make Rome his political world. Soldiers, merchants and families carried Latin and Roman law far beyond Italy. Each extension of citizenship turned former subjects into participants in the imperial system. In AD 212, Caracalla granted the Roman name to almost every free inhabitant of the empire. A city on the Tiber had gathered much of Europe into one legal order.",
    focus: { latitude: 41.9, longitude: 12.5 },
    camera: { x: 0.382, y: 0.64, scale: 1.48, rotation: -0.006 },
    palette: "roman",
    layers: ["terrain", "roads", "cities", "route"],
    sourceIds: ["coskun-2021"],
    landmark: "Rome and the Imperial Roads",
    side: "left",
    interaction: {
      family: "compare",
      prompt: "Watch Rome gather a continent",
      accessibleSummary:
        "Three snapshots move from an Italian republic to a Mediterranean empire and finally to the citizenship settlement of AD 212.",
      mapScope: "europe",
      steps: [
        {
          id: "italy",
          label: "An Italian republic",
          summary:
            "Rome first built a system of alliances, colonies and roads across Italy.",
          points: [
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
            { latitude: 40.85, longitude: 14.27, label: "Capua" },
            { latitude: 41.1, longitude: 16.87, label: "Southern Italy" },
          ],
        },
        {
          id: "mediterranean",
          label: "A Mediterranean empire",
          summary:
            "Conquest joined distant provinces to one military, fiscal and urban system.",
          points: [
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
            { latitude: 37.98, longitude: 23.72, label: "Athens" },
            { latitude: 43.3, longitude: 5.37, label: "Massilia" },
            { latitude: 41.38, longitude: 2.17, label: "Barcino" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
          ],
        },
        {
          id: "citizenship",
          label: "Citizenship, AD 212",
          summary:
            "The Roman name became a legal identity shared across nearly the entire free population.",
          points: [
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
            { latitude: 45.76, longitude: 4.84, label: "Lugdunum" },
            { latitude: 51.75, longitude: -1.25, label: "Britannia" },
            { latitude: 41.01, longitude: 28.97, label: "Byzantium" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [0, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "rome",
        label: "Rome",
        detail:
          "The capital connected command, law, patronage and citizenship to a political world spanning three continents.",
        latitude: 41.9,
        longitude: 12.5,
      },
      {
        id: "lugdunum",
        label: "Lugdunum",
        detail:
          "Modern Lyon was a provincial capital, mint and road junction organising distant territories.",
        latitude: 45.76,
        longitude: 4.84,
      },
    ],
    chronicle: {
      href: "chapters/rome-gathers-europe/",
      label: "Enter the forged road",
    },
  },
  {
    id: "christian-empire",
    order: 6,
    era: "classical",
    period: { start: 312, end: 565, label: "312–565" },
    title: "The Empire Takes the Cross",
    kicker: "The Consecrated City",
    thesis:
      "Christian faith entered Roman government while Constantinople became the centre of a renewed Christian Rome.",
    body: "Constantine’s victory opened Roman law, money and monumental space to the Christian church. Emperors summoned councils; bishops defined a creed able to judge the ruler who enforced it. On the Bosporus, Constantinople grew from a new residence into a fortified capital containing court, Senate, cathedral, harbours and archives. When the western imperial office disappeared, the Roman state remained here. Justinian gathered Roman law, raised Hagia Sophia and recovered Mediterranean provinces. By 565, Christian kingship, a defensible European capital and the institutions of Rome had been bound into an imperial order built to endure.",
    focus: { latitude: 41.01, longitude: 28.97 },
    camera: { x: 0.576, y: 0.659, scale: 1.58, rotation: 0.01 },
    palette: "byzantine",
    layers: ["terrain", "walls", "capitals", "route"],
    sourceIds: [
      "kaldellis-2023",
      "van-dam-2011",
      "rutgers-constantinople-2025",
    ],
    landmark: "Constantinople",
    side: "right",
    interaction: {
      family: "boundary",
      prompt: "Consecrate the imperial centre",
      accessibleSummary:
        "Snapshots for 312, 330, 451 and 565 show Christian faith, Constantinople and Roman government becoming one imperial order.",
      mapScope: "europe",
      steps: [
        {
          id: "constantine",
          label: "AD 312",
          summary:
            "Victory brings Christianity into sustained imperial protection and patronage.",
          points: [
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
            { latitude: 41.94, longitude: 12.47, label: "Milvian Bridge" },
          ],
        },
        {
          id: "new-rome",
          label: "AD 330",
          summary:
            "Constantinople is dedicated as an imperial city commanding the Bosporus.",
          points: [
            { latitude: 41.9, longitude: 12.5, label: "Old Rome" },
            { latitude: 41.01, longitude: 28.97, label: "Constantinople" },
          ],
        },
        {
          id: "chalcedon",
          label: "AD 451",
          summary:
            "A council beside New Rome defines doctrine for the Christian imperial church.",
          points: [
            { latitude: 41.01, longitude: 28.97, label: "Constantinople" },
            { latitude: 40.99, longitude: 29.03, label: "Chalcedon" },
          ],
        },
        {
          id: "justinian",
          label: "AD 565",
          summary:
            "Law, cathedral, capital and recovered provinces define Justinian’s Roman restoration.",
          points: [
            { latitude: 41.01, longitude: 28.97, label: "Constantinople" },
            { latitude: 36.81, longitude: 10.18, label: "Carthage" },
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "constantinople",
        label: "Constantinople",
        detail:
          "The walls, palace and great churches made New Rome the strategic centre of the eastern empire.",
        latitude: 41.01,
        longitude: 28.97,
      },
      {
        id: "nicaea",
        label: "Nicaea",
        detail:
          "Constantine summoned bishops here in 325, giving an empire-wide council the setting for a common creed.",
        latitude: 40.43,
        longitude: 29.72,
      },
    ],
    chronicle: {
      href: "chapters/empire-takes-cross/",
      label: "Enter the consecrated city",
    },
  },
  {
    id: "europe-reborn",
    order: 7,
    era: "medieval",
    period: { start: 500, end: 1000, label: "500–1000" },
    title: "Europe Reborn",
    kicker: "A New Commonwealth",
    thesis:
      "After Rome’s western collapse, kingdoms and churches slowly assembled a new Christian Europe.",
    body: "New kingdoms rose among the remains of western Rome. Their rulers borrowed Roman titles, employed Latin churchmen and founded monasteries that preserved books, trained officials and cleared land. The Franks joined conquest, conversion and government; on Christmas Day 800, Charlemagne received an imperial crown in Rome. Missionaries and royal marriages then carried Christianity beyond the old frontier. Scandinavians, Bohemians, Poles, Croats and Magyars entered the Latin Church, while Kyiv received its Christianity from Constantinople. Courts, bishoprics and monasteries connected rulers across long distances. By the year 1000, Latin west and Greek east formed two related worlds with a shared Christian inheritance.",
    focus: { latitude: 50.78, longitude: 6.08 },
    camera: { x: 0.307, y: 0.452, scale: 1.38, rotation: -0.01 },
    palette: "carolingian",
    layers: ["terrain", "missions", "kingdoms", "route"],
    sourceIds: ["berend-2007"],
    landmark: "Aachen",
    side: "left",
    interaction: {
      family: "network",
      prompt: "See the commonwealth expand",
      accessibleSummary:
        "The map links Aachen, Prague, Gniezno, Esztergom and Kyiv as rulers and communities joined the Latin and Byzantine Christian worlds.",
      mapScope: "europe",
      steps: [
        {
          id: "frankish-core",
          label: "The Frankish core",
          summary:
            "Aachen joined royal power, Christian worship and a revived western imperial claim.",
          points: [
            { latitude: 50.78, longitude: 6.08, label: "Aachen" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
          ],
          links: [
            [0, 1],
            [0, 2],
          ],
        },
        {
          id: "central-europe",
          label: "Central Europe",
          summary:
            "New Christian monarchies carried the continental system eastward.",
          points: [
            { latitude: 50.78, longitude: 6.08, label: "Aachen" },
            { latitude: 50.08, longitude: 14.44, label: "Prague" },
            { latitude: 52.53, longitude: 17.6, label: "Gniezno" },
            { latitude: 47.79, longitude: 18.74, label: "Esztergom" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [1, 3],
          ],
        },
        {
          id: "two-christianities",
          label: "Latin and Byzantine",
          summary:
            "Kyiv entered the Byzantine orbit while remaining part of Europe’s dynastic world.",
          points: [
            { latitude: 41.01, longitude: 28.97, label: "Constantinople" },
            { latitude: 42.7, longitude: 23.32, label: "Sofia" },
            { latitude: 50.45, longitude: 30.52, label: "Kyiv" },
            { latitude: 50.08, longitude: 14.44, label: "Prague" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [2, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "aachen",
        label: "Aachen",
        detail:
          "Charlemagne’s palace joined government, learning and worship around a revived western imperial court.",
        latitude: 50.78,
        longitude: 6.08,
      },
      {
        id: "kyiv",
        label: "Kyiv",
        detail:
          "The conversion of Volodymyr in 988 placed the Rus’ realm within the Byzantine Christian world.",
        latitude: 50.45,
        longitude: 30.52,
      },
    ],
    chronicle: {
      href: "chapters/europe-reborn/",
      label: "Follow the rebuilt road",
    },
  },
  {
    id: "papal-revolution",
    order: 8,
    era: "medieval",
    period: { start: 1049, end: 1122, label: "1049–1122" },
    title: "The Papal Revolution",
    kicker: "Power Divides",
    thesis:
      "The quarrel over bishops divided spiritual investiture from temporal government without removing either power from the Christian order.",
    body: "In the winter of 1077, Henry IV reached Canossa before German princes could assemble under papal judgment. Gregory VII absolved a penitent king without deciding the kingship, and civil war continued. Their quarrel concerned bishops who carried sacramental office, landed regalia, justice and royal service in one person. Reformers claimed canonical election and spiritual investiture for the Church; rulers defended the government attached to episcopal lands. At Worms in 1122, reciprocal promises separated ring and staff from the sceptre while preserving royal presence and influence. Papal and imperial courts remained inside one Christian world as organised jurisdictions that neither side could absorb.",
    focus: { latitude: 44.58, longitude: 10.45 },
    camera: { x: 0.372, y: 0.566, scale: 1.62, rotation: 0.008 },
    palette: "imperial",
    layers: ["terrain", "papacy", "empire", "route"],
    sourceIds: ["cushing-2005", "blumenthal-1991", "investiture-documents"],
    landmark: "Canossa and Worms",
    side: "right",
    interaction: {
      family: "compare",
      prompt: "Separate the two powers",
      accessibleSummary:
        "The comparison moves from royal control of church office to the conflict at Canossa and the negotiated division at Worms.",
      mapScope: "europe",
      steps: [
        {
          id: "one-order",
          label: "One sacred order",
          summary:
            "Kings treated bishops as pillars of royal government and invested them with office.",
          points: [
            { latitude: 49.32, longitude: 8.43, label: "Imperial church" },
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
          ],
          links: [[0, 1]],
        },
        {
          id: "canossa",
          label: "Canossa, 1077",
          summary:
            "The emperor’s penance dramatised the pope’s claim to judge a Christian ruler.",
          points: [
            { latitude: 50.11, longitude: 8.68, label: "Imperial Germany" },
            { latitude: 44.58, longitude: 10.45, label: "Canossa" },
            { latitude: 41.9, longitude: 12.5, label: "Rome" },
          ],
          links: [
            [0, 1],
            [1, 2],
          ],
        },
        {
          id: "worms",
          label: "Worms, 1122",
          summary:
            "The compromise distinguished spiritual office from temporal authority while leaving both institutions intact.",
          points: [
            { latitude: 49.63, longitude: 8.36, label: "Worms" },
            { latitude: 41.9, longitude: 12.5, label: "Papacy" },
            { latitude: 50.11, longitude: 8.68, label: "Empire" },
          ],
          links: [
            [0, 1],
            [0, 2],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "canossa",
        label: "Canossa",
        detail:
          "Henry IV’s penance in 1077 made this castle a symbol of the papacy’s new claim over Christian rulers.",
        latitude: 44.58,
        longitude: 10.45,
      },
      {
        id: "worms",
        label: "Worms",
        detail:
          "The 1122 concordat divided the spiritual and temporal elements of episcopal appointment.",
        latitude: 49.63,
        longitude: 8.36,
      },
    ],
    chronicle: {
      href: "chapters/papal-revolution/",
      label: "Enter the contested order",
    },
  },
  {
    id: "society-beyond-kin",
    order: 9,
    era: "medieval",
    period: { start: 1000, end: 1300, label: "1000–1300" },
    title: "A Society Beyond Kin",
    kicker: "The Associational West",
    thesis:
      "Medieval Europeans gave monasteries, guilds, communes and universities legal lives that outlasted their founders.",
    body: "A monastery could hold land centuries after its founders were dead. A guild could elect officers, fine a member and support the household of a deceased craftsman. Communes, cathedral chapters and universities acquired the same durable character. Members swore oaths, kept records, held common property and settled disputes under written rules. Canon lawyers gave these bodies a legal personality distinct from any one member. The idea travelled easily because it solved practical problems: property survived succession, obligations became enforceable and collective decisions bound future officeholders. Medieval Europe filled with self-governing institutions whose lives exceeded those of the people who created them.",
    focus: { latitude: 44.49, longitude: 11.34 },
    camera: { x: 0.369, y: 0.585, scale: 1.58, rotation: 0.008 },
    palette: "monastic",
    layers: ["terrain", "towns", "institutions", "route"],
    sourceIds: ["schulz-2019", "henrich-2020"],
    landmark: "Bologna and the University",
    side: "left",
    interaction: {
      family: "network",
      prompt: "Build a society of associations",
      accessibleSummary:
        "The map connects monasteries, communes, guild cities and universities as institutions organised beyond extended kinship.",
      mapScope: "europe",
      steps: [
        {
          id: "monastic-networks",
          label: "Monasteries",
          summary:
            "Religious houses connected disciplined communities across local lordships.",
          points: [
            { latitude: 46.43, longitude: 4.66, label: "Cluny" },
            { latitude: 48.5, longitude: 8, label: "Rhine houses" },
            { latitude: 44.49, longitude: 11.34, label: "Bologna" },
          ],
          links: [
            [0, 1],
            [0, 2],
          ],
        },
        {
          id: "urban-corporations",
          label: "Guilds and communes",
          summary:
            "Urban communities created offices, privileges and rules that survived their members.",
          points: [
            { latitude: 45.46, longitude: 9.19, label: "Milan" },
            { latitude: 50.85, longitude: 4.35, label: "Brussels" },
            { latitude: 51.05, longitude: 3.73, label: "Ghent" },
            { latitude: 53.87, longitude: 10.69, label: "Lübeck" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
          ],
        },
        {
          id: "universities",
          label: "Universities",
          summary:
            "Students and masters formed self-governing corporations dedicated to learning.",
          points: [
            { latitude: 44.49, longitude: 11.34, label: "Bologna" },
            { latitude: 51.75, longitude: -1.25, label: "Oxford" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
          ],
          links: [
            [0, 2],
            [1, 2],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "bologna",
        label: "Bologna",
        detail:
          "Students and masters formed a self-governing legal corporation whose privileges helped define the university.",
        latitude: 44.49,
        longitude: 11.34,
      },
      {
        id: "cluny",
        label: "Cluny",
        detail:
          "The abbey led a monastic network reaching beyond local lordship and making discipline continental.",
        latitude: 46.43,
        longitude: 4.66,
      },
    ],
    chronicle: {
      href: "chapters/society-beyond-kin/",
      label: "Cross the forbidden line",
    },
  },
  {
    id: "commercial-revolution",
    order: 10,
    era: "medieval",
    period: { start: 950, end: 1350, label: "950–1350" },
    title: "The Medieval Commercial Revolution",
    kicker: "Trust at a Distance",
    thesis:
      "Medieval merchants developed ways to make promises credible far from home.",
    body: "At the fairs of Champagne, an Italian merchant could buy Flemish cloth with money that existed only as an entry in a ledger. Trade on this scale required promises that survived distance. Notaries recorded partnerships, merchant courts delivered quick judgments and bills of exchange moved credit without moving heavy coin. Ports and rulers granted foreign merchants privileges because traffic produced customs revenue. Regular fairs gave strangers known dates and places to settle accounts. From Genoa to Bruges, documents joined markets governed by different laws and currencies. The oceanic ventures of later centuries would rely on commercial habits first tested in these fairs, ports and counting houses.",
    focus: { latitude: 48.3, longitude: 4.1 },
    camera: { x: 0.315, y: 0.49, scale: 1.34, rotation: -0.008 },
    palette: "monastic",
    layers: ["terrain", "fairs", "ports", "credit"],
    sourceIds: ["lopez-1976"],
    landmark: "The Fairs of Champagne",
    side: "right",
    interaction: {
      family: "network",
      prompt: "Open the medieval markets",
      accessibleSummary:
        "Three networks connect Champagne fairs, Mediterranean ports and northern cloth towns through goods, contracts and credit.",
      mapScope: "europe",
      steps: [
        {
          id: "champagne-fairs",
          label: "The fairs",
          summary:
            "Seasonal fairs made Champagne a meeting place between northern producers and Italian merchants.",
          points: [
            { latitude: 48.3, longitude: 4.1, label: "Champagne" },
            { latitude: 50.85, longitude: 4.35, label: "Brabant" },
            { latitude: 45.46, longitude: 9.19, label: "Milan" },
            { latitude: 44.41, longitude: 8.93, label: "Genoa" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
          ],
        },
        {
          id: "maritime-ports",
          label: "The ports",
          summary:
            "Competing maritime cities organised shipping, law and armed protection.",
          points: [
            { latitude: 45.44, longitude: 12.33, label: "Venice" },
            { latitude: 44.41, longitude: 8.93, label: "Genoa" },
            { latitude: 43.72, longitude: 10.4, label: "Pisa" },
            { latitude: 41.01, longitude: 28.97, label: "Constantinople" },
          ],
          links: [
            [0, 3],
            [1, 3],
            [2, 3],
          ],
        },
        {
          id: "credit-network",
          label: "Credit",
          summary:
            "Documents allowed value and obligation to travel more safely than coin.",
          points: [
            { latitude: 44.41, longitude: 8.93, label: "Genoa" },
            { latitude: 48.3, longitude: 4.1, label: "Champagne" },
            { latitude: 51.21, longitude: 3.22, label: "Bruges" },
            { latitude: 51.51, longitude: -0.13, label: "London" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "champagne",
        label: "Champagne",
        detail:
          "A cycle of protected fairs brought merchants, currencies and commercial jurisdictions into regular contact.",
        latitude: 48.3,
        longitude: 4.1,
      },
      {
        id: "genoa",
        label: "Genoa",
        detail:
          "Notarial contracts and maritime partnerships made the port a laboratory of long-distance commercial organisation.",
        latitude: 44.41,
        longitude: 8.93,
      },
      {
        id: "bruges",
        label: "Bruges",
        detail:
          "Northern cloth production met Italian credit and international shipping in this densely connected city.",
        latitude: 51.21,
        longitude: 3.22,
      },
    ],
    chronicle: {
      href: "chapters/medieval-commercial-revolution/",
      label: "Follow the written road",
    },
  },
  {
    id: "hanseatic-north",
    order: 11,
    era: "medieval",
    period: { start: 1150, end: 1500, label: "1150–1500" },
    title: "The Hanseatic North",
    kicker: "Cities Without a State",
    thesis:
      "Baltic and North Sea towns protected their trade by acting together while guarding their independence.",
    body: "Merchants from Lübeck, Hamburg and other northern towns built the Hanseatic League from privileges, warehouses and repeated meetings. Fish from Norway, grain from Prussia, Russian wax and Flemish cloth passed through their hands. Four great foreign enclaves secured places for Hanseatic merchants in London, Bruges, Bergen and Novgorod. The league had no king, treasury or permanent capital. Its strength came from coordinated action: towns closed markets, imposed boycotts and armed fleets when trade was threatened. Each city decided when to take part, preserving the independence that made cooperation valuable. For centuries, northern rulers had to negotiate with cities acting as a collective power.",
    focus: { latitude: 53.87, longitude: 10.69 },
    camera: { x: 0.36, y: 0.31, scale: 1.28, rotation: -0.012 },
    palette: "carolingian",
    layers: ["terrain", "ports", "goods", "sea-routes"],
    sourceIds: ["dollinger-1970"],
    landmark: "Lübeck and the Baltic",
    side: "left",
    interaction: {
      family: "network",
      prompt: "Light the Hanseatic routes",
      accessibleSummary:
        "The map links western markets, Baltic ports and the league’s four great foreign trading enclaves.",
      mapScope: "europe",
      steps: [
        {
          id: "western-route",
          label: "West",
          summary:
            "Cloth, salt and credit connected London and Bruges to the Baltic ports.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 51.21, longitude: 3.22, label: "Bruges" },
            { latitude: 53.55, longitude: 9.99, label: "Hamburg" },
            { latitude: 53.87, longitude: 10.69, label: "Lübeck" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
          ],
        },
        {
          id: "northern-route",
          label: "North",
          summary:
            "Stockfish from Bergen entered an international urban trading system.",
          points: [
            { latitude: 60.39, longitude: 5.32, label: "Bergen" },
            { latitude: 53.87, longitude: 10.69, label: "Lübeck" },
            { latitude: 51.51, longitude: -0.13, label: "London" },
          ],
          links: [
            [0, 1],
            [0, 2],
          ],
        },
        {
          id: "eastern-route",
          label: "East",
          summary:
            "Grain, timber, wax and furs moved through Baltic and Rus’ trading cities.",
          points: [
            { latitude: 53.87, longitude: 10.69, label: "Lübeck" },
            { latitude: 54.35, longitude: 18.65, label: "Gdańsk" },
            { latitude: 59.44, longitude: 24.75, label: "Tallinn" },
            { latitude: 58.52, longitude: 31.28, label: "Novgorod" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "lubeck",
        label: "Lübeck",
        detail:
          "Its position between North Sea and Baltic made Lübeck the leading meeting place of the Hanseatic towns.",
        latitude: 53.87,
        longitude: 10.69,
      },
      {
        id: "bergen",
        label: "Bergen",
        detail:
          "The Bryggen trading enclave channelled northern stockfish into the league’s commercial system.",
        latitude: 60.39,
        longitude: 5.32,
      },
      {
        id: "novgorod",
        label: "Novgorod",
        detail:
          "At the eastern end of the network, merchants exchanged western goods for wax, furs and forest products.",
        latitude: 58.52,
        longitude: 31.28,
      },
    ],
    chronicle: {
      href: "chapters/hanseatic-north/",
      label: "Enter the northern harbour",
    },
  },
  {
    id: "empire-many-liberties",
    order: 12,
    era: "medieval",
    period: { start: 962, end: 1806, label: "962–1806" },
    title: "The Empire of Many Liberties",
    kicker: "The Holy Roman Empire",
    thesis:
      "Negotiated rights held the many jurisdictions of central Europe inside one imperial order.",
    body: "Central Europe lived for more than eight centuries inside the Holy Roman Empire. An elected emperor governed alongside princes, bishops, free cities, knights and village communities, each holding rights acquired at different moments. The map became a mosaic because jurisdiction followed inheritance, privilege and custom. Imperial diets gathered the estates to approve taxes and settle common business. After 1495, the Imperial Chamber Court offered a standing forum for disputes that once invited private war. A city could defend its charter and a prince his territory without leaving the realm. Negotiated rights gave the empire its durability and made legal pluralism a central European political tradition.",
    focus: { latitude: 50.1, longitude: 9.4 },
    camera: { x: 0.365, y: 0.45, scale: 1.46, rotation: -0.01 },
    palette: "imperial",
    layers: ["terrain", "jurisdictions", "courts", "route"],
    sourceIds: ["wilson-2016", "westphal-2018"],
    landmark: "The Imperial Constitution",
    side: "right",
    interaction: {
      family: "boundary",
      prompt: "Enter the imperial mosaic",
      accessibleSummary:
        "Three views show the imperial core, the variety of self-governing jurisdictions and the legal institutions that held them together.",
      mapScope: "europe",
      steps: [
        {
          id: "imperial-core",
          label: "The realm",
          summary:
            "The imperial claim joined German, Italian, Burgundian and Bohemian lands without making them uniform.",
          points: [
            { latitude: 53, longitude: 8, label: "North" },
            { latitude: 51, longitude: 16, label: "East" },
            { latitude: 46, longitude: 13, label: "South" },
            { latitude: 46, longitude: 6, label: "South-west" },
            { latitude: 50, longitude: 4, label: "West" },
          ],
          closed: true,
        },
        {
          id: "many-estates",
          label: "Many estates",
          summary:
            "Princes, bishops, cities and knights governed through different kinds of right.",
          points: [
            { latitude: 52.13, longitude: 11.63, label: "Magdeburg" },
            { latitude: 50.11, longitude: 8.68, label: "Frankfurt" },
            { latitude: 49.45, longitude: 11.08, label: "Nuremberg" },
            { latitude: 50.08, longitude: 14.44, label: "Prague" },
            { latitude: 48.14, longitude: 11.58, label: "Munich" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
            [2, 4],
          ],
        },
        {
          id: "law-and-peace",
          label: "Law and peace",
          summary:
            "Assemblies and courts gave rivals procedures short of private war.",
          points: [
            { latitude: 50.11, longitude: 8.68, label: "Imperial election" },
            { latitude: 49.63, longitude: 8.36, label: "Imperial diets" },
            { latitude: 50.56, longitude: 8.5, label: "Chamber court" },
          ],
          links: [
            [0, 1],
            [1, 2],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "magdeburg",
        label: "Magdeburg",
        detail:
          "Its urban law travelled widely eastward, carrying a portable model of civic rights and jurisdiction.",
        latitude: 52.13,
        longitude: 11.63,
      },
      {
        id: "worms-imperial",
        label: "Worms",
        detail:
          "Imperial diets made the city one of many temporary stages on which the realm negotiated its affairs.",
        latitude: 49.63,
        longitude: 8.36,
      },
    ],
    chronicle: {
      href: "chapters/empire-many-liberties/",
      label: "Enter the imperial assembly",
    },
  },
  {
    id: "frontiers-hold",
    order: 13,
    era: "medieval",
    period: { start: 711, end: 1699, label: "711–1699" },
    title: "The Frontiers Hold",
    kicker: "Defence and Recovery",
    thesis:
      "Centuries of war around Iberia, the Balkans and the Mediterranean shaped Europe’s southern and eastern edges.",
    body: "For centuries, Europe’s southern and eastern frontiers were made by siege, settlement and counterattack. Christian kingdoms advanced through Iberia until Granada surrendered in 1492. Turkish conquest in Anatolia helped provoke the crusades; Ottoman armies then took Constantinople, crossed the Balkans and twice reached Vienna. Mediterranean powers built galley fleets, island bases and chains of coastal forts. The Habsburgs organised a permanent military frontier through Hungary and Croatia, supporting garrisons with taxes raised far inland. Karlowitz shifted the frontier south-east in 1699. These long wars turned border defence into a European enterprise and forced states to command men, money and supplies on a new scale.",
    focus: { latitude: 48.21, longitude: 16.37 },
    camera: { x: 0.428, y: 0.506, scale: 1.42, rotation: 0.008 },
    palette: "frontier",
    layers: ["terrain", "frontiers", "fortresses", "route"],
    sourceIds: ["reilly-1993", "smith-2024", "agoston-2025"],
    landmark: "Vienna and the Eastern Frontier",
    side: "left",
    interaction: {
      family: "boundary",
      prompt: "Move across the contested frontiers",
      accessibleSummary:
        "Four moments locate the long Iberian frontier, the fall of Constantinople, the siege of Vienna and the settlement of 1699.",
      mapScope: "europe",
      steps: [
        {
          id: "iberia",
          label: "Granada, 1492",
          summary:
            "The capture of Granada ended the last Muslim sovereign state in Iberia.",
          points: [
            { latitude: 43, longitude: -9, label: "North-west" },
            { latitude: 43, longitude: 3, label: "North-east" },
            { latitude: 37.18, longitude: -3.6, label: "Granada" },
            { latitude: 36, longitude: -7, label: "South-west" },
          ],
          closed: true,
        },
        {
          id: "constantinople-falls",
          label: "1453",
          summary:
            "Ottoman conquest replaced the eastern Roman state and opened a new Balkan frontier.",
          points: [
            { latitude: 41.01, longitude: 28.97, label: "Constantinople" },
            { latitude: 42.7, longitude: 23.32, label: "Sofia" },
            { latitude: 44.8, longitude: 20.46, label: "Belgrade" },
          ],
        },
        {
          id: "vienna-siege",
          label: "Vienna, 1683",
          summary:
            "The failed siege marked the limit of Ottoman expansion into central Europe.",
          points: [
            { latitude: 41.01, longitude: 28.97, label: "Istanbul" },
            { latitude: 44.8, longitude: 20.46, label: "Belgrade" },
            { latitude: 47.5, longitude: 19.04, label: "Buda" },
            { latitude: 48.21, longitude: 16.37, label: "Vienna" },
          ],
        },
        {
          id: "karlowitz",
          label: "Karlowitz, 1699",
          summary:
            "A diplomatic settlement moved the frontier south-east and confirmed a new balance.",
          points: [
            { latitude: 45.2, longitude: 19.93, label: "Karlowitz" },
            { latitude: 47.5, longitude: 19.04, label: "Hungary" },
            { latitude: 44.8, longitude: 20.46, label: "Balkan frontier" },
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "granada",
        label: "Granada",
        detail:
          "Its surrender in 1492 ended the last Muslim sovereign state in Iberia.",
        latitude: 37.18,
        longitude: -3.6,
      },
      {
        id: "vienna",
        label: "Vienna",
        detail:
          "The failed Ottoman sieges of 1529 and 1683 made the Habsburg capital a symbol of south-eastern defence.",
        latitude: 48.21,
        longitude: 16.37,
      },
      {
        id: "karlowitz",
        label: "Karlowitz",
        detail:
          "The 1699 treaty confirmed major Ottoman territorial losses and a transformed central European frontier.",
        latitude: 45.2,
        longitude: 19.93,
      },
    ],
    chronicle: {
      href: "chapters/europe-holds-the-line/",
      label: "Hold the line",
    },
  },
  {
    id: "europe-turns-seaward",
    order: 14,
    era: "early-modern",
    period: { start: 1415, end: 1700, label: "1415–1700" },
    title: "Europe Turns Seaward",
    kicker: "The Oceanic Turn",
    thesis:
      "Armed ocean-going ships allowed European states to operate far beyond their own coasts.",
    body: "Portugal captured Ceuta in 1415 and spent the next decades extending its voyages down the African coast. Each expedition added winds, currents and harbours to the charts carried home. Mariners adapted Mediterranean navigation and shipbuilding to Atlantic conditions; cannon and royal finance kept vessels at sea and protected fortified ports. Portuguese ships rounded Africa and reached India. Spanish expeditions crossed the Atlantic, followed by Dutch, English and French rivals. Pilots and brokers turned landfalls into working routes; forts and contracts made the routes durable. Ocean-going ships had enlarged the reach of the European state to thousands of miles beyond its own shores.",
    focus: { latitude: 38.72, longitude: -9.14 },
    camera: { x: 0.128, y: 0.708, scale: 1.32, rotation: -0.018 },
    palette: "atlantic",
    layers: ["terrain", "sea-routes", "ports", "route"],
    sourceIds: ["parker-2012"],
    landmark: "Lisbon and the Atlantic",
    side: "right",
    interaction: {
      family: "route",
      prompt: "Follow the oceanic turn",
      accessibleSummary:
        "A world map traces Portuguese routes around Africa to India and Spanish routes across the Atlantic.",
      mapScope: "world",
      steps: [
        {
          id: "african-coast",
          label: "Down the coast",
          summary:
            "Portuguese voyages turned Atlantic islands and the African coast into a connected route.",
          points: [
            { latitude: 38.72, longitude: -9.14, label: "Lisbon" },
            { latitude: 32.65, longitude: -16.9, label: "Madeira" },
            { latitude: 14.72, longitude: -17.47, label: "Senegambia" },
            { latitude: 5.55, longitude: -0.2, label: "Gold Coast" },
          ],
        },
        {
          id: "india-route",
          label: "Around Africa",
          summary:
            "The Cape route gave Portugal direct armed access to the Indian Ocean.",
          points: [
            { latitude: 38.72, longitude: -9.14, label: "Lisbon" },
            { latitude: -33.92, longitude: 18.42, label: "Cape of Good Hope" },
            { latitude: -4.05, longitude: 39.67, label: "Mombasa" },
            { latitude: 15.5, longitude: 73.83, label: "Goa" },
          ],
        },
        {
          id: "atlantic-crossing",
          label: "Across the Atlantic",
          summary:
            "Spain channelled American conquest and exchange through Seville.",
          points: [
            { latitude: 37.39, longitude: -5.99, label: "Seville" },
            { latitude: 28.1, longitude: -15.4, label: "Canaries" },
            { latitude: 18.48, longitude: -69.9, label: "Caribbean" },
            { latitude: 19.43, longitude: -99.13, label: "Mexico" },
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "lisbon",
        label: "Lisbon",
        detail:
          "The Tagus became the departure point and clearing house for Portugal’s routes around Africa and into Asia.",
        latitude: 38.72,
        longitude: -9.14,
      },
      {
        id: "seville",
        label: "Seville",
        detail:
          "Spain channelled legal trade with the Americas through the Casa de Contratación.",
        latitude: 37.39,
        longitude: -5.99,
      },
    ],
    chronicle: {
      href: "chapters/europe-turns-seaward/",
      label: "Unroll the ocean",
    },
  },
  {
    id: "reformation",
    order: 15,
    era: "early-modern",
    period: { start: 1517, end: 1648, label: "1517–1648" },
    title: "The Reformation",
    kicker: "Christendom Fractures",
    thesis:
      "The Reformation divided western Christendom and made confessional allegiance a permanent concern of government.",
    body: "Luther began with an argument about indulgences and church authority. Print turned it into a European crisis. Pamphlets crossed borders, vernacular Bibles entered homes and rulers discovered that reform could place churches and property under territorial control. Catholic renewal answered with seminaries, schools, new religious orders and missions. Confessional loyalty reached into worship, marriage and education; rulers expected subjects to share the faith of the state. Revolts and wars followed as rival churches hardened their institutions. Augsburg and Westphalia ended the project of restoring a single western Christendom. European governments learned to conduct politics across permanent religious division.",
    focus: { latitude: 51.87, longitude: 12.65 },
    camera: { x: 0.375, y: 0.414, scale: 1.5, rotation: -0.012 },
    palette: "imperial",
    layers: ["terrain", "confessions", "print", "route"],
    sourceIds: ["rublack-2017"],
    landmark: "Wittenberg",
    side: "left",
    interaction: {
      family: "boundary",
      prompt: "Watch Christendom divide",
      accessibleSummary:
        "Snapshots show the initial Lutheran challenge, the spread of competing confessions and the political settlement of 1648.",
      mapScope: "europe",
      steps: [
        {
          id: "wittenberg-1517",
          label: "1517",
          summary:
            "A university dispute in Wittenberg entered the European print system.",
          points: [
            { latitude: 51.87, longitude: 12.65, label: "Wittenberg" },
            { latitude: 50.11, longitude: 8.68, label: "Frankfurt printers" },
            { latitude: 48.37, longitude: 10.9, label: "Augsburg" },
          ],
          links: [
            [0, 1],
            [0, 2],
          ],
        },
        {
          id: "confessions-1555",
          label: "1555",
          summary:
            "Lutheran, Reformed and Catholic territories formed a confessional patchwork.",
          points: [
            { latitude: 55.7, longitude: 12.6, label: "Lutheran north" },
            { latitude: 51, longitude: 11, label: "Lutheran centre" },
            { latitude: 46.2, longitude: 6.15, label: "Reformed Geneva" },
            {
              latitude: 48.2,
              longitude: 16.37,
              label: "Catholic Habsburg lands",
            },
          ],
        },
        {
          id: "westphalia-1648",
          label: "1648",
          summary:
            "Peace accepted that Europe’s political order would persist without restored religious unity.",
          points: [
            { latitude: 51.96, longitude: 7.63, label: "Münster" },
            { latitude: 52.28, longitude: 8.05, label: "Osnabrück" },
            { latitude: 50.11, longitude: 8.68, label: "Imperial estates" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [1, 2],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "wittenberg",
        label: "Wittenberg",
        detail:
          "Luther’s university town became the first centre of a reform movement amplified by print.",
        latitude: 51.87,
        longitude: 12.65,
      },
      {
        id: "geneva",
        label: "Geneva",
        detail:
          "Calvin’s city trained ministers and supplied books to Reformed communities across Europe.",
        latitude: 46.2,
        longitude: 6.15,
      },
      {
        id: "munster",
        label: "Münster",
        detail:
          "Negotiations here helped end the Thirty Years’ War and stabilise a religiously divided imperial order.",
        latitude: 51.96,
        longitude: 7.63,
      },
    ],
    chronicle: {
      href: "chapters/reformation/",
      label: "Read the burned Empire",
    },
  },
  {
    id: "habsburg-europe",
    order: 16,
    era: "early-modern",
    period: { start: 1526, end: 1918, label: "1526–1918" },
    title: "Habsburg Europe",
    kicker: "Many Peoples, One Crown",
    thesis:
      "The Habsburgs bound historic kingdoms and their different peoples to a common dynasty.",
    body: "The Habsburg monarchy was assembled one inheritance and marriage at a time. After 1526, the Austrian lands, Bohemia and Hungary shared a dynasty and an Ottoman frontier. Each crownland kept its laws, diet and privileges. Vienna supplied the court, diplomatic centre and much of the army; provincial elites supplied taxes, recruits and local government through recurring bargains. The Compromise of 1867 created separate Austrian and Hungarian governments under one ruler. Czechs, Croats, Poles, Romanians and Ukrainians organised national movements inside the dynastic framework. Millions carried local, national, dynastic and imperial loyalties together until war destroyed the monarchy in 1918.",
    focus: { latitude: 48.21, longitude: 16.37 },
    camera: { x: 0.43, y: 0.5, scale: 1.42, rotation: 0.008 },
    palette: "imperial",
    layers: ["terrain", "crownlands", "peoples", "route"],
    sourceIds: ["judson-2016"],
    landmark: "Vienna and the Crownlands",
    side: "right",
    interaction: {
      family: "boundary",
      prompt: "Assemble the crownlands",
      accessibleSummary:
        "Four snapshots show the Habsburg monarchy’s expansion, eighteenth-century consolidation, dual structure and dissolution.",
      mapScope: "europe",
      steps: [
        {
          id: "crowns-1526",
          label: "1526",
          summary:
            "Austria, Bohemia and Hungary came under one dynasty after Mohács.",
          points: [
            { latitude: 49.2, longitude: 12, label: "Bohemian lands" },
            { latitude: 51, longitude: 18.5, label: "North-east" },
            { latitude: 46, longitude: 23, label: "Hungarian frontier" },
            { latitude: 45, longitude: 14, label: "South-west" },
            { latitude: 47, longitude: 9, label: "Austrian west" },
          ],
          closed: true,
        },
        {
          id: "monarchy-1713",
          label: "1713",
          summary:
            "War and inheritance created a composite central European great power.",
          points: [
            { latitude: 51, longitude: 18.5, label: "Silesia" },
            { latitude: 49, longitude: 24, label: "Galicia frontier" },
            { latitude: 44, longitude: 23, label: "South-east" },
            { latitude: 45, longitude: 13, label: "Adriatic" },
            { latitude: 50, longitude: 8.5, label: "Western lands" },
          ],
          closed: true,
        },
        {
          id: "dual-monarchy",
          label: "1867",
          summary:
            "Austria-Hungary divided central institutions while preserving one dynasty and common foreign policy.",
          points: [
            { latitude: 48.21, longitude: 16.37, label: "Vienna" },
            { latitude: 47.5, longitude: 19.04, label: "Budapest" },
            { latitude: 50.08, longitude: 14.44, label: "Prague" },
            { latitude: 49.84, longitude: 24.03, label: "Lviv" },
            { latitude: 45.81, longitude: 15.98, label: "Zagreb" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
            [1, 4],
          ],
        },
        {
          id: "dissolution-1918",
          label: "1918",
          summary:
            "War destroyed the dynastic framework and released rival national projects.",
          points: [
            { latitude: 48.21, longitude: 16.37, label: "Austria" },
            { latitude: 47.5, longitude: 19.04, label: "Hungary" },
            { latitude: 50.08, longitude: 14.44, label: "Czechoslovakia" },
            { latitude: 45.81, longitude: 15.98, label: "South Slav state" },
            { latitude: 52.23, longitude: 21.01, label: "Poland" },
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "vienna-habsburg",
        label: "Vienna",
        detail:
          "The court coordinated diplomacy, military power and dynastic ceremony across lands that retained separate identities.",
        latitude: 48.21,
        longitude: 16.37,
      },
      {
        id: "prague-habsburg",
        label: "Prague",
        detail:
          "The Bohemian capital embodied both participation in the monarchy and resistance to centralising rule.",
        latitude: 50.08,
        longitude: 14.44,
      },
      {
        id: "lviv-habsburg",
        label: "Lviv",
        detail:
          "Polish, Ukrainian, Jewish, Armenian and German lives overlapped in this eastern crownland capital.",
        latitude: 49.84,
        longitude: 24.03,
      },
    ],
    chronicle: {
      href: "chapters/habsburg-europe/",
      label: "Enter the braided current",
    },
  },
  {
    id: "scientific-revolution",
    order: 17,
    era: "early-modern",
    period: { start: 1543, end: 1700, label: "1543–1700" },
    title: "The Scientific Revolution",
    kicker: "Knowledge Under Inspection",
    thesis:
      "European scholars built institutions that exposed claims about nature to observation, test and criticism.",
    body: "Copernicus rearranged the heavens, Vesalius opened bodies, Galileo pointed new instruments at the sky and Newton gave motion a mathematical language. Their work travelled through printers, universities, workshops, observatories and courts competing for useful knowledge. Scientific societies in London, Paris and elsewhere asked members to describe methods closely enough for another observer to repeat them. Journals fixed claims in print and correspondence carried criticism across borders. A scholar blocked in one city could find a publisher in another. Evidence acquired a public career: results travelled, drew attack, survived replication or yielded to correction. Knowledge became a cumulative European enterprise.",
    focus: { latitude: 51.51, longitude: -0.13 },
    camera: { x: 0.28, y: 0.43, scale: 1.32, rotation: -0.006 },
    palette: "industrial",
    layers: ["terrain", "observatories", "letters", "societies"],
    sourceIds: ["shapin-1996", "mokyr-2016"],
    landmark: "The Republic of Letters",
    side: "left",
    interaction: {
      family: "network",
      prompt: "Open the scientific network",
      accessibleSummary:
        "The map connects astronomy, anatomy, experiment and scientific societies through European centres of inquiry.",
      mapScope: "europe",
      steps: [
        {
          id: "new-cosmos",
          label: "The cosmos",
          summary:
            "Astronomers joined inherited observations to new mathematics and instruments.",
          points: [
            { latitude: 54.36, longitude: 19.68, label: "Frombork" },
            { latitude: 50.06, longitude: 19.94, label: "Kraków" },
            { latitude: 50.08, longitude: 14.44, label: "Prague" },
            { latitude: 43.77, longitude: 11.25, label: "Florence" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
          ],
        },
        {
          id: "observation",
          label: "Observation",
          summary:
            "Universities, workshops and courts gave instruments and direct observation new authority.",
          points: [
            { latitude: 45.41, longitude: 11.88, label: "Padua" },
            { latitude: 43.77, longitude: 11.25, label: "Florence" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
          ],
          links: [
            [0, 1],
            [1, 2],
          ],
        },
        {
          id: "societies",
          label: "Public science",
          summary:
            "Societies, journals and letters made criticism part of organised knowledge.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
            { latitude: 52.37, longitude: 4.9, label: "Amsterdam" },
          ],
          links: [
            [0, 1],
            [0, 3],
            [1, 2],
            [1, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "frombork",
        label: "Frombork",
        detail:
          "Copernicus developed the heliocentric model while serving as a cathedral canon on the Baltic frontier.",
        latitude: 54.36,
        longitude: 19.68,
      },
      {
        id: "padua",
        label: "Padua",
        detail:
          "A major university and medical centre joined anatomy, mathematics and instrument-based observation.",
        latitude: 45.41,
        longitude: 11.88,
      },
      {
        id: "london-science",
        label: "London",
        detail:
          "The Royal Society made experiment, correspondence and published scrutiny part of a durable institution.",
        latitude: 51.51,
        longitude: -0.13,
      },
    ],
    chronicle: {
      href: "chapters/scientific-revolution/",
      label: "Set the measuring line",
    },
  },
  {
    id: "dutch-republic",
    order: 18,
    era: "early-modern",
    period: { start: 1572, end: 1713, label: "1572–1713" },
    title: "The Dutch Republic",
    kicker: "Commerce, Credit and Toleration",
    thesis:
      "The Dutch Republic turned the independence of its cities into an unlikely source of global power.",
    body: "The Dutch Republic rose as a loose federation of provinces crowded with self-governing towns. Amsterdam’s merchants built shipping networks from the Baltic to Asia. The state borrowed at low rates, investors traded shares and marine risk, and the exchange concentrated news from every market. Printers sold maps, books and arguments across Europe. Leiden’s university drew scholars, while refugees brought capital, skills and commercial contacts into Dutch cities. Provincial rivalry kept power dispersed; common danger made the towns cooperate through the States General. Foreign visitors found a country where civic independence, religious latitude and relentless commerce reinforced one another—and made a small republic a global power.",
    focus: { latitude: 52.37, longitude: 4.9 },
    camera: { x: 0.292, y: 0.38, scale: 1.58, rotation: -0.008 },
    palette: "atlantic",
    layers: ["terrain", "ports", "credit", "print"],
    sourceIds: ["israel-1995"],
    landmark: "Amsterdam",
    side: "right",
    interaction: {
      family: "network",
      prompt: "Enter the Dutch system",
      accessibleSummary:
        "Three networks show the republic’s urban federation, commercial finance and circulation of books and scholars.",
      mapScope: "europe",
      steps: [
        {
          id: "urban-republic",
          label: "The provinces",
          summary:
            "Power was distributed among provinces, cities and representative institutions.",
          points: [
            { latitude: 52.37, longitude: 4.9, label: "Amsterdam" },
            { latitude: 52.08, longitude: 4.31, label: "The Hague" },
            { latitude: 52.16, longitude: 4.49, label: "Leiden" },
            { latitude: 51.92, longitude: 4.48, label: "Rotterdam" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
          ],
        },
        {
          id: "credit-and-shipping",
          label: "Credit and ships",
          summary:
            "Markets for shares, debt and marine risk helped organise more voyages than any merchant house could finance alone.",
          points: [
            { latitude: 52.37, longitude: 4.9, label: "Amsterdam" },
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 53.55, longitude: 9.99, label: "Hamburg" },
            { latitude: 38.72, longitude: -9.14, label: "Lisbon" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
          ],
        },
        {
          id: "books-and-refugees",
          label: "Books and refuge",
          summary:
            "Printers, universities and migrant communities made the republic a European information centre.",
          points: [
            { latitude: 52.16, longitude: 4.49, label: "Leiden" },
            { latitude: 52.37, longitude: 4.9, label: "Amsterdam" },
            { latitude: 51.05, longitude: 3.73, label: "Southern Netherlands" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [1, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "amsterdam",
        label: "Amsterdam",
        detail:
          "Exchange, bank, docks and merchant houses made the city a command point for European and global commerce.",
        latitude: 52.37,
        longitude: 4.9,
      },
      {
        id: "leiden",
        label: "Leiden",
        detail:
          "Its university and printers drew scholarship into the republic’s unusually open intellectual market.",
        latitude: 52.16,
        longitude: 4.49,
      },
      {
        id: "the-hague",
        label: "The Hague",
        detail:
          "The States General coordinated a republic whose power remained distributed among provinces and cities.",
        latitude: 52.08,
        longitude: 4.31,
      },
    ],
    chronicle: {
      href: "chapters/dutch-republic/",
      label: "Ring the exchange bell",
    },
  },
  {
    id: "enlightenment-public-opinion",
    order: 19,
    era: "early-modern",
    period: { start: 1680, end: 1789, label: "1680–1789" },
    title: "The Enlightenment",
    kicker: "Public Opinion",
    thesis:
      "A growing reading public began to judge laws, rulers and customs as matters open to argument.",
    body: "The Enlightenment gathered in London coffeehouses, Parisian salons, Masonic lodges, theatres and provincial reading societies. Newspapers and journals carried arguments from one room to another. Readers compared English liberties, Dutch commerce, French manners and the reforms of central European rulers. Edinburgh philosophers examined sympathy, history and markets; Parisian writers built reputations large enough to trouble ministers. Publishers learned that controversy sold. Reviews made books answerable to strangers, and public opinion became a force courts tried to measure and manage. A law or custom once defended by age and authority now faced a new test: could it survive criticism in print?",
    focus: { latitude: 48.86, longitude: 2.35 },
    camera: { x: 0.33, y: 0.47, scale: 1.28, rotation: -0.004 },
    palette: "belle-epoque",
    layers: ["terrain", "print", "salons", "letters"],
    sourceIds: ["melton-2001"],
    landmark: "The European Public",
    side: "left",
    interaction: {
      family: "network",
      prompt: "Enter the public sphere",
      accessibleSummary:
        "The map shows newspapers and coffeehouses, salons and academies, and a wider network of readers across Europe.",
      mapScope: "europe",
      steps: [
        {
          id: "coffee-and-news",
          label: "Coffee and news",
          summary:
            "Commercial cities supplied regular places and publications for political discussion.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 52.37, longitude: 4.9, label: "Amsterdam" },
            { latitude: 55.95, longitude: -3.19, label: "Edinburgh" },
          ],
          links: [
            [0, 1],
            [0, 2],
          ],
        },
        {
          id: "salons-academies",
          label: "Salons and academies",
          summary:
            "Conversation, reputation and learned institutions carried criticism into elite society.",
          points: [
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
            { latitude: 48.21, longitude: 16.37, label: "Vienna" },
            { latitude: 59.33, longitude: 18.07, label: "Stockholm" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [1, 3],
          ],
        },
        {
          id: "reading-public",
          label: "A reading public",
          summary:
            "Books and periodicals let arguments cross political and confessional borders.",
          points: [
            { latitude: 55.95, longitude: -3.19, label: "Edinburgh" },
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
            { latitude: 48.21, longitude: 16.37, label: "Vienna" },
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
    hotspots: [
      {
        id: "london-public",
        label: "London",
        detail:
          "Coffeehouses and a competitive press joined commerce, news and political argument.",
        latitude: 51.51,
        longitude: -0.13,
      },
      {
        id: "paris-public",
        label: "Paris",
        detail:
          "Salons, theatres and print made literary reputation an influence that even the monarchy had to consider.",
        latitude: 48.86,
        longitude: 2.35,
      },
      {
        id: "edinburgh",
        label: "Edinburgh",
        detail:
          "A compact intellectual world connected philosophy, history, economics and the study of commercial society.",
        latitude: 55.95,
        longitude: -3.19,
      },
    ],
    chronicle: {
      href: "chapters/enlightenment-public-opinion/",
      label: "Send the marked sentence",
    },
  },
  {
    id: "rivalry-industrial-breakthrough",
    order: 20,
    era: "industrial",
    period: { start: 1700, end: 1850, label: "1700–1850" },
    title: "Rivalry and the Industrial Breakthrough",
    kicker: "The Great Acceleration",
    thesis:
      "In Britain, coal, machinery and commercial skill pushed production beyond the limits of muscle and water.",
    body: "Britain’s industrial breakthrough joined expensive labour, accessible coal, skilled mechanics, credit and large markets. Mine owners bought engines to pump water from deep shafts. Textile manufacturers adapted machinery to spin and weave at speeds no workshop could match. Steam power escaped the mine and entered factories, ships and railways; each application created demand for stronger iron, better tools and more coal. Manchester drew raw cotton through Liverpool and sent finished cloth into world markets. By 1850, factory bells and railway timetables governed the working day in growing towns. Industrial production had given European states a new kind of economic and military power.",
    focus: { latitude: 53.48, longitude: -2.24 },
    camera: { x: 0.209, y: 0.394, scale: 1.34, rotation: 0.012 },
    palette: "industrial",
    layers: ["terrain", "coal", "factories", "railways"],
    sourceIds: ["hoffman-2015", "mokyr-2016", "orourke-2010"],
    landmark: "Manchester",
    side: "right",
    interaction: {
      family: "compare",
      prompt: "Compare Europe before and after steam",
      accessibleSummary:
        "Three views contrast an eighteenth-century craft economy with coal-powered factories and the first railway network.",
      mapScope: "europe",
      steps: [
        {
          id: "craft-economy",
          label: "1700",
          summary:
            "Production remained distributed among farms, workshops, water power and urban crafts.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 52.49, longitude: -1.9, label: "Birmingham" },
            { latitude: 53.48, longitude: -2.24, label: "Manchester" },
          ],
        },
        {
          id: "coal-and-factories",
          label: "1800",
          summary:
            "Coal and steam concentrated power in mines, mills and industrial towns.",
          points: [
            { latitude: 54.98, longitude: -1.62, label: "Newcastle coalfield" },
            { latitude: 53.48, longitude: -2.24, label: "Manchester" },
            { latitude: 52.49, longitude: -1.9, label: "Birmingham" },
            { latitude: 51.51, longitude: -0.13, label: "London" },
          ],
          links: [
            [0, 3],
            [1, 3],
            [2, 3],
          ],
        },
        {
          id: "railway-age",
          label: "1850",
          summary:
            "Railways cut journey and freight times, turning industrial growth into a continental race.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 53.48, longitude: -2.24, label: "Manchester" },
            { latitude: 50.85, longitude: 4.35, label: "Brussels" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [2, 3],
            [3, 4],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "manchester",
        label: "Manchester",
        detail:
          "Cotton mills, steam power and transport networks made the city a defining industrial landscape.",
        latitude: 53.48,
        longitude: -2.24,
      },
      {
        id: "newcastle",
        label: "Newcastle",
        detail:
          "Accessible coal and coastal shipping connected the north-eastern coalfield to national and European markets.",
        latitude: 54.98,
        longitude: -1.62,
      },
      {
        id: "brussels-industrial",
        label: "Belgium",
        detail:
          "Coal, iron and dense transport links made Belgium the first major industrial economy on the continent.",
        latitude: 50.85,
        longitude: 4.35,
      },
    ],
  },
  {
    id: "european-world",
    order: 21,
    era: "industrial",
    period: { start: 1815, end: 1914, label: "1815–1914" },
    title: "The European World",
    kicker: "Continental Ascendancy",
    thesis:
      "Industrial power allowed European states to command trade routes, territory and capital on a global scale.",
    body: "A traveller leaving Europe in 1900 encountered European power in shipping schedules, banks, colonial offices, railway stations and telegraph cables. Steam compressed ocean journeys; railways carried troops and goods inland; industrial supply chains kept imperial armies equipped far from home. London and Paris directed capital towards mines, ports and plantations on other continents. Shipping companies and submarine cables bound those investments to European markets and ministries. By 1914, European states controlled most imperial territory, the leading sea routes and a commanding share of overseas finance. Industrial capacity had become geopolitical command, placing Europe at the centre of a world system.",
    focus: { latitude: 48.86, longitude: 2.35 },
    camera: { x: 0.263, y: 0.492, scale: 1.36, rotation: -0.006 },
    palette: "belle-epoque",
    layers: ["terrain", "telegraph", "steam", "empire"],
    sourceIds: ["orourke-2010", "darwin-2007"],
    landmark: "Paris and the Railway Age",
    side: "left",
    interaction: {
      family: "network",
      prompt: "Reveal the European world system",
      accessibleSummary:
        "A world map shows steam routes, telegraph cables and financial command lines radiating from European capitals.",
      mapScope: "world",
      steps: [
        {
          id: "steam-routes",
          label: "Steam",
          summary:
            "Regular steam routes compressed oceanic time and linked ports to imperial systems.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 31.2, longitude: 29.92, label: "Alexandria" },
            { latitude: 19.08, longitude: 72.88, label: "Bombay" },
            { latitude: 1.29, longitude: 103.85, label: "Singapore" },
            { latitude: -33.87, longitude: 151.21, label: "Sydney" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
            [3, 4],
          ],
        },
        {
          id: "telegraph-cables",
          label: "Cables",
          summary:
            "Submarine cables brought distant command and information into near-real time.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 40.71, longitude: -74.01, label: "New York" },
            { latitude: 18.94, longitude: 72.84, label: "Bombay" },
            { latitude: 22.32, longitude: 114.17, label: "Hong Kong" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [2, 3],
          ],
        },
        {
          id: "capital-and-empire",
          label: "Capital and empire",
          summary:
            "European finance and military administration concentrated decisions far from their consequences.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "London" },
            { latitude: 48.86, longitude: 2.35, label: "Paris" },
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
            { latitude: 28.61, longitude: 77.21, label: "Delhi" },
            { latitude: 14.72, longitude: -17.47, label: "Dakar" },
          ],
          links: [
            [0, 3],
            [1, 4],
            [2, 4],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "paris",
        label: "Paris",
        detail:
          "Railways, boulevards, exhibitions and finance made the city a stage for industrial Europe’s confidence.",
        latitude: 48.86,
        longitude: 2.35,
      },
      {
        id: "vienna-congress",
        label: "Vienna",
        detail:
          "The settlement of 1814–15 supplied a diplomatic framework for a century of managed great-power rivalry.",
        latitude: 48.21,
        longitude: 16.37,
      },
      {
        id: "london-global",
        label: "London",
        detail:
          "Finance, shipping, cables and imperial administration made London a central switchboard of the world economy.",
        latitude: 51.51,
        longitude: -0.13,
      },
    ],
  },
  {
    id: "europe-at-war",
    order: 22,
    era: "catastrophe",
    period: { start: 1914, end: 1945, label: "1914–1945" },
    title: "Europe at War with Itself",
    kicker: "The Catastrophe",
    thesis:
      "Two world wars turned Europe’s industrial and administrative strength against its own societies.",
    body: "Europe went to war in 1914 with railway schedules, mass armies and confident promises of victory. Four years of artillery, trenches and blockade killed millions and broke the German, Habsburg, Russian and Ottoman empires. The peace drew new borders without creating a stable order. Fascists, Nazis and Soviet communists then joined radio, bureaucracy and mass politics to systems of control beyond the reach of older tyrannies. The next war consumed cities and culminated in Germany’s systematic murder of Europe’s Jews. In 1945, the continent that had commanded the world lay ruined and divided between American and Soviet power.",
    focus: { latitude: 49.16, longitude: 5.38 },
    camera: { x: 0.299, y: 0.486, scale: 1.66, rotation: 0.018 },
    palette: "catastrophe",
    layers: ["terrain", "fracture", "fronts", "route"],
    sourceIds: ["mazower-1998"],
    landmark: "Verdun",
    side: "right",
    transitionEffect: "fracture",
    interaction: {
      family: "compare",
      prompt: "See the European order break",
      accessibleSummary:
        "Three snapshots show the imperial order of 1914, the unstable settlement after 1919 and the ruined, divided continent of 1945.",
      mapScope: "europe",
      steps: [
        {
          id: "empires-1914",
          label: "1914",
          summary:
            "A small number of multinational empires organised most of central and eastern Europe.",
          points: [
            { latitude: 52.52, longitude: 13.41, label: "German Empire" },
            { latitude: 48.21, longitude: 16.37, label: "Habsburg Empire" },
            { latitude: 41.01, longitude: 28.97, label: "Ottoman Empire" },
            { latitude: 59.93, longitude: 30.34, label: "Russian Empire" },
          ],
        },
        {
          id: "new-states-1919",
          label: "1919",
          summary:
            "New and enlarged nation-states inherited disputed borders, minorities and unresolved grievances.",
          points: [
            { latitude: 52.23, longitude: 21.01, label: "Poland" },
            { latitude: 50.08, longitude: 14.44, label: "Czechoslovakia" },
            { latitude: 44.81, longitude: 20.46, label: "Yugoslavia" },
            { latitude: 47.5, longitude: 19.04, label: "Hungary" },
          ],
        },
        {
          id: "ruin-1945",
          label: "1945",
          summary:
            "War, genocide and occupation left Europe ruined and divided between external superpowers.",
          points: [
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
            { latitude: 50.04, longitude: 19.18, label: "Auschwitz" },
            { latitude: 52.23, longitude: 21.01, label: "Warsaw" },
            { latitude: 49.16, longitude: 5.38, label: "Western front" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "verdun",
        label: "Verdun",
        detail:
          "Ten months of battle in 1916 made this fortified zone a byword for industrial attrition.",
        latitude: 49.16,
        longitude: 5.38,
      },
      {
        id: "auschwitz",
        label: "Auschwitz",
        detail:
          "The German camp complex became the largest site of murder in the Holocaust.",
        latitude: 50.04,
        longitude: 19.18,
      },
      {
        id: "berlin-1945",
        label: "Berlin",
        detail:
          "The destroyed capital became the meeting point of military defeat, occupation and Europe’s coming division.",
        latitude: 52.52,
        longitude: 13.41,
      },
    ],
  },
  {
    id: "continent-rebuilt",
    order: 23,
    era: "catastrophe",
    period: { start: 1945, end: 1991, label: "1945–1991" },
    title: "The Continent Rebuilt",
    kicker: "Recovery",
    thesis:
      "Western Europe recovered by tying national economies and old rivals into a shared legal order.",
    body: "Western Europe rebuilt through factories, trade and security guaranteed by the United States. France and West Germany placed coal and steel under a common authority, turning the raw materials of war into subjects of routine administration. Treaties widened the arrangement into a common market; courts and regulations made each bargain part of a permanent legal order. Growth financed welfare states and gave democratic politics a material foundation. Across the Iron Curtain, Soviet power held a different European system in place. In 1989, strikes, demonstrations and political courage from Gdańsk to Prague broke that division and opened the road to continental reunification.",
    focus: { latitude: 50.85, longitude: 4.35 },
    camera: { x: 0.286, y: 0.45, scale: 1.52, rotation: -0.008 },
    palette: "reconstruction",
    layers: ["terrain", "division", "integration", "route"],
    sourceIds: ["judt-2005"],
    landmark: "Brussels and Berlin",
    side: "left",
    transitionEffect: "rebuild",
    interaction: {
      family: "boundary",
      prompt: "Rebuild the continent",
      accessibleSummary:
        "Four snapshots show the division of 1945, the first European communities, western enlargement and the breach of 1989.",
      mapScope: "europe",
      steps: [
        {
          id: "division-1945",
          label: "1945",
          summary:
            "Occupation and superpower rivalry divided Europe before reconstruction had begun.",
          points: [
            { latitude: 69, longitude: 25, label: "Northern division" },
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
            { latitude: 48, longitude: 17, label: "Central division" },
            { latitude: 41, longitude: 21, label: "Southern division" },
          ],
        },
        {
          id: "community-1957",
          label: "1957",
          summary:
            "Six states placed strategic industries and markets inside common institutions.",
          points: [
            { latitude: 48.86, longitude: 2.35, label: "France" },
            { latitude: 50.85, longitude: 4.35, label: "Belgium" },
            { latitude: 52.37, longitude: 4.9, label: "Netherlands" },
            { latitude: 50.11, longitude: 8.68, label: "West Germany" },
            { latitude: 41.9, longitude: 12.5, label: "Italy" },
          ],
          links: [
            [1, 0],
            [1, 2],
            [1, 3],
            [1, 4],
          ],
        },
        {
          id: "western-order",
          label: "1973–86",
          summary:
            "Democratic enlargement extended the common legal and economic order.",
          points: [
            { latitude: 51.51, longitude: -0.13, label: "United Kingdom" },
            { latitude: 55.68, longitude: 12.57, label: "Denmark" },
            { latitude: 37.98, longitude: 23.72, label: "Greece" },
            { latitude: 38.72, longitude: -9.14, label: "Portugal" },
            { latitude: 40.42, longitude: -3.7, label: "Spain" },
          ],
        },
        {
          id: "berlin-1989",
          label: "1989",
          summary:
            "The opening of the Berlin Wall turned eastern dissent into continental transformation.",
          points: [
            { latitude: 52.52, longitude: 13.41, label: "Berlin" },
            { latitude: 52.23, longitude: 21.01, label: "Warsaw" },
            { latitude: 50.08, longitude: 14.44, label: "Prague" },
            { latitude: 47.5, longitude: 19.04, label: "Budapest" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "brussels",
        label: "Brussels",
        detail:
          "Institutions gathered here turned treaties into a permanent system of negotiation, administration and law.",
        latitude: 50.85,
        longitude: 4.35,
      },
      {
        id: "berlin-wall",
        label: "Berlin",
        detail:
          "From 1961 to 1989, the Wall gave concrete form to Europe’s division between Atlantic and Soviet systems.",
        latitude: 52.52,
        longitude: 13.41,
      },
      {
        id: "rome-treaties",
        label: "Rome",
        detail:
          "The 1957 treaties established a common market and institutions intended to make integration durable.",
        latitude: 41.9,
        longitude: 12.5,
      },
    ],
  },
  {
    id: "europe-returns",
    order: 24,
    era: "catastrophe",
    period: { start: 1991, label: "1991–PRESENT" },
    title: "Europe Returns",
    kicker: "The Unfinished Journey",
    thesis:
      "Reunification enlarged Europe’s institutions; the war in Ukraine now tests their capacity for common action.",
    body: "After 1989, countries from the Baltic to the Balkans entered institutions once confined to Western Europe. Roads and railways crossed borders sealed within living memory; students, workers and capital followed. European Union membership carried law and markets eastward. NATO extended an American-backed defence guarantee across the same region. Ukraine held neither membership when Russia launched its full-scale invasion in 2022. European governments answered with sanctions, weapons and new defence budgets, while the United States remained central to the military effort. The unfinished journey now turns on Europe’s ability to convert common interests into decisions, resources and sustained power.",
    focus: { latitude: 50.45, longitude: 30.52 },
    camera: { x: 0.594, y: 0.458, scale: 1.35, rotation: 0.004 },
    palette: "present",
    layers: ["terrain", "union", "alliance", "route"],
    sourceIds: ["eu-history", "nato-enlargement"],
    landmark: "Kyiv and Europe’s Eastern Frontier",
    side: "right",
    transitionEffect: "return",
    interaction: {
      family: "boundary",
      prompt: "Reunite the map",
      accessibleSummary:
        "Separate views show European Union enlargement, NATO enlargement and the eastern frontier without treating the institutions as identical.",
      mapScope: "europe",
      steps: [
        {
          id: "opening-1991",
          label: "1991",
          summary:
            "Soviet rule ended and the continent’s sealed routes reopened.",
          points: [
            { latitude: 59.44, longitude: 24.75, label: "Tallinn" },
            { latitude: 52.23, longitude: 21.01, label: "Warsaw" },
            { latitude: 50.08, longitude: 14.44, label: "Prague" },
            { latitude: 42.7, longitude: 23.32, label: "Sofia" },
          ],
        },
        {
          id: "eu-enlargement",
          label: "European Union",
          summary:
            "Membership extended a common legal and economic order eastward in successive waves.",
          points: [
            { latitude: 50.85, longitude: 4.35, label: "Brussels" },
            { latitude: 52.23, longitude: 21.01, label: "Poland" },
            { latitude: 59.44, longitude: 24.75, label: "Estonia" },
            { latitude: 42.7, longitude: 23.32, label: "Bulgaria" },
            { latitude: 45.81, longitude: 15.98, label: "Croatia" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
            [0, 4],
          ],
        },
        {
          id: "nato-enlargement",
          label: "NATO",
          summary:
            "A separate security alliance extended collective defence into central and eastern Europe.",
          points: [
            { latitude: 50.88, longitude: 4.43, label: "NATO headquarters" },
            { latitude: 52.23, longitude: 21.01, label: "Poland" },
            { latitude: 59.44, longitude: 24.75, label: "Estonia" },
            { latitude: 60.17, longitude: 24.94, label: "Finland" },
            { latitude: 59.33, longitude: 18.07, label: "Sweden" },
          ],
          links: [
            [0, 1],
            [0, 2],
            [0, 3],
            [0, 4],
          ],
        },
        {
          id: "ukraine-frontier",
          label: "The eastern frontier",
          summary:
            "Ukraine’s defence tests whether Europe’s institutions can also sustain strategic power.",
          points: [
            { latitude: 50.45, longitude: 30.52, label: "Kyiv" },
            { latitude: 49.84, longitude: 24.03, label: "Lviv" },
            { latitude: 52.23, longitude: 21.01, label: "Warsaw" },
            { latitude: 50.85, longitude: 4.35, label: "Brussels" },
          ],
          links: [
            [0, 1],
            [1, 2],
            [2, 3],
          ],
        },
      ],
    },
    hotspots: [
      {
        id: "tallinn",
        label: "Tallinn",
        detail:
          "Estonia rebuilt its democratic state and rejoined European legal and political institutions after Soviet occupation.",
        latitude: 59.44,
        longitude: 24.75,
      },
      {
        id: "warsaw-return",
        label: "Warsaw",
        detail:
          "Poland’s accession to NATO and the EU became a central event in the continent’s post-Cold War reunion.",
        latitude: 52.23,
        longitude: 21.01,
      },
      {
        id: "kyiv-present",
        label: "Kyiv",
        detail:
          "The Ukrainian capital stands at the meeting point of the Rus’ inheritance, European integration and resistance to conquest.",
        latitude: 50.45,
        longitude: 30.52,
      },
    ],
  },
];

export const sceneById = new Map(scenes.map((scene) => [scene.id, scene]));

export const storyEras = [
  { id: "origins", label: "Origins", range: "7000–500 BC" },
  { id: "classical", label: "Classical inheritance", range: "800 BC–1453" },
  { id: "medieval", label: "Europe remade", range: "500–1699" },
  {
    id: "early-modern",
    label: "Ocean, faith and knowledge",
    range: "1415–1789",
  },
  { id: "industrial", label: "Industry and world power", range: "1700–1914" },
  { id: "catastrophe", label: "Catastrophe and return", range: "1914–present" },
] as const;
