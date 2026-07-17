import type { StoryScene } from "../types/story";

export const scenes: StoryScene[] = [
  {
    id: "steppe-comes-west",
    order: 1,
    period: { start: -3300, end: -2000, label: "3300–2000 BC" },
    title: "The Steppe Comes West",
    kicker: "Origins",
    thesis: "Europe begins not with purity, but with movement and mixture.",
    body:
      "From the grasslands north of the Black Sea, mobile communities moved west in successive waves. Ancient DNA now reveals the scale: in parts of central Europe, Corded Ware people drew roughly three quarters of their ancestry from steppe-related populations. They met descendants of Europe’s hunter-gatherers and early farmers whose ancestors had come from Anatolia. Out of this encounter came a new human landscape—mixed in ancestry, increasingly linked by Indo-European speech, and organised through far-reaching kinship networks. Horses, wheels and seasonal mobility widened the horizons of the societies they formed. Europe’s first long road was made by people, herds and wagons moving toward the setting sun.",
    focus: { latitude: 47, longitude: 38 },
    camera: { x: 0.682, y: 0.532, scale: 1.28, rotation: -0.018 },
    palette: "steppe",
    layers: ["terrain", "migration", "route", "landmark"],
    sourceIds: ["haak-2015", "lazaridis-2025"],
    landmark: "The Pontic Steppe",
    side: "left",
    hotspots: [
      {
        id: "lower-dnipro",
        label: "Lower Dnipro",
        detail:
          "Steppe, river and forest met here. Communities along this corridor linked mobile pastoral worlds to the farming societies farther west.",
        latitude: 47.5,
        longitude: 34.5,
      },
      {
        id: "corded-ware",
        label: "Corded Ware horizon",
        detail:
          "By the third millennium BC, steppe-related ancestry had reached deep into central Europe alongside new burial practices and far-reaching social networks.",
        latitude: 51,
        longitude: 14,
      },
    ],
  },
  {
    id: "greece-and-the-citizen",
    order: 2,
    period: { start: -800, end: -146, label: "800–146 BC" },
    title: "Greece and the Citizen",
    kicker: "The Polis",
    thesis: "In the Greek city, political life became a conscious human art.",
    body:
      "Across the Aegean, compact city-states made public life visible. Citizens assembled, argued, legislated, judged and fought for their polis. Their freedom was incomplete—women, slaves and foreigners stood outside the citizen body—but the claim was radical: law could be discussed, authority could be justified and a community could govern itself. Athens gave democracy its most famous form; Sparta, Corinth and hundreds of other poleis offered rival answers. Resistance to Persian invasion made political autonomy a civilisational memory. Philosophy, history and tragedy turned political choices into permanent questions. Europe inherited not one Greek constitution, but the restless habit of comparing constitutions.",
    focus: { latitude: 37.98, longitude: 23.72 },
    camera: { x: 0.514, y: 0.724, scale: 1.62, rotation: 0.012 },
    palette: "aegean",
    layers: ["terrain", "coast", "route", "landmark"],
    sourceIds: ["cartledge-2009"],
    landmark: "The Athenian Acropolis",
    side: "right",
    hotspots: [
      {
        id: "athens",
        label: "Athens",
        detail:
          "The assembly, council and popular courts made political argument a public practice on an unprecedented scale.",
        latitude: 37.98,
        longitude: 23.72,
      },
      {
        id: "thermopylae",
        label: "Thermopylae",
        detail:
          "The pass became a lasting memory of resistance during the Persian invasion of 480 BC, even though the decisive struggle continued elsewhere.",
        latitude: 38.8,
        longitude: 22.54,
      },
    ],
  },
  {
    id: "rome-gathers-europe",
    order: 3,
    period: { start: -509, end: 212, label: "509 BC–AD 212" },
    title: "Rome Gathers Europe",
    kicker: "One Political World",
    thesis: "Rome turned conquest into an expanding order of roads, cities, law and citizenship.",
    body:
      "A city beside the Tiber mastered Italy, the Mediterranean and much of Europe. Roman legions opened the way, but endurance came from incorporation. Provinces acquired roads, aqueducts, markets and municipal government; local elites entered imperial service; soldiers and families carried Latin law across frontiers. Rome did not erase every difference. It connected different peoples to a common political centre and gradually widened membership in it. Frontiers separated the imperial peace from worlds beyond, while trade crossed them. In AD 212, Caracalla extended Roman citizenship to nearly all free inhabitants of the empire. Europe’s first continental order was armed, unequal and remarkably absorptive.",
    focus: { latitude: 41.9, longitude: 12.5 },
    camera: { x: 0.382, y: 0.64, scale: 1.48, rotation: -0.006 },
    palette: "roman",
    layers: ["terrain", "roads", "route", "landmark"],
    sourceIds: ["coskun-2021"],
    landmark: "Rome and the Imperial Roads",
    side: "left",
    hotspots: [
      {
        id: "rome",
        label: "Rome",
        detail:
          "The capital connected military command, law, patronage and citizenship to a political world that stretched across three continents.",
        latitude: 41.9,
        longitude: 12.5,
      },
      {
        id: "lugdunum",
        label: "Lugdunum",
        detail:
          "Modern Lyon was a provincial capital, mint and road junction: a clear example of how Roman cities organised distant territories.",
        latitude: 45.76,
        longitude: 4.84,
      },
    ],
  },
  {
    id: "christian-empire",
    order: 4,
    period: { start: 312, end: 1453, label: "312–1453" },
    title: "The Christian Empire",
    kicker: "New Rome",
    thesis: "Christianity transformed Roman power; Constantinople carried the Roman state for another millennium.",
    body:
      "The conversion of Constantine joined the imperial inheritance to a universal Christian faith. Bishops, councils, monasteries and law gave the new religion institutional form while the empire gave it reach. When the western imperial court disappeared, Rome did not end. From Constantinople, emperors who called themselves Romans defended the Balkans and Anatolia, codified Roman law, preserved classical learning and governed a sophisticated Christian state. Greek became its principal language; the Roman name endured. Its survival kept an eastern capital, court and army within Europe’s inheritance. For centuries, the walls of New Rome stood between Europe and successive Persian, Arab and Turkish powers.",
    focus: { latitude: 41.01, longitude: 28.97 },
    camera: { x: 0.576, y: 0.659, scale: 1.58, rotation: 0.01 },
    palette: "byzantine",
    layers: ["terrain", "walls", "route", "landmark"],
    sourceIds: ["millar-2006"],
    landmark: "Constantinople",
    side: "right",
    hotspots: [
      {
        id: "constantinople",
        label: "Constantinople",
        detail:
          "The Theodosian walls, imperial palace and great churches made New Rome the strategic and ceremonial centre of the eastern empire.",
        latitude: 41.01,
        longitude: 28.97,
      },
      {
        id: "ravenna",
        label: "Ravenna",
        detail:
          "From this defensible Adriatic city, late Roman and Ostrogothic rulers governed the western imperial inheritance.",
        latitude: 44.42,
        longitude: 12.2,
      },
    ],
  },
  {
    id: "europe-reborn",
    order: 5,
    period: { start: 500, end: 1000, label: "500–1000" },
    title: "Europe Reborn",
    kicker: "A New Commonwealth",
    thesis: "After western Rome, Europe grew by turning outsiders into members of a shared civilisation.",
    body:
      "The post-Roman centuries were not an empty interlude. Latin churchmen, Germanic kings and surviving Roman institutions built new political worlds from the ruins. The Frankish realm joined conquest to conversion and revived the western imperial title under Charlemagne. Over time, Scandinavians, Slavs, Bohemians, Poles, Croats and Magyars entered the Christian commonwealth. Kyiv and the lands of Rus’ joined its eastern, Byzantine orbit. No single empire contained the whole, yet a recognisable continent took shape. Europe became larger by absorbing peoples once beyond its frontiers. Its unity remained plural: Latin and Greek, kingdoms and cities, royal power and ecclesiastical authority.",
    focus: { latitude: 50.78, longitude: 6.08 },
    camera: { x: 0.307, y: 0.452, scale: 1.38, rotation: -0.01 },
    palette: "carolingian",
    layers: ["terrain", "missions", "route", "landmark"],
    sourceIds: ["berend-2007"],
    landmark: "Aachen",
    side: "left",
    hotspots: [
      {
        id: "aachen",
        label: "Aachen",
        detail:
          "Charlemagne’s palace complex joined royal government, learning and Christian worship around a revived western imperial court.",
        latitude: 50.78,
        longitude: 6.08,
      },
      {
        id: "kyiv",
        label: "Kyiv",
        detail:
          "The conversion of Volodymyr in 988 placed the Rus’ realm within the Byzantine Christian world and Europe’s dynastic system.",
        latitude: 50.45,
        longitude: 30.52,
      },
    ],
  },
  {
    id: "society-beyond-kin",
    order: 6,
    period: { start: 500, end: 1300, label: "500–1300" },
    title: "A Society Beyond Kin",
    kicker: "The Associational West",
    thesis: "Western Europe learned to cooperate through institutions that reached beyond the clan.",
    body:
      "The western Church restricted marriage among close kin, promoted monogamy and weakened the grip of extended lineage. The change unfolded slowly and unevenly, yet its social consequences were profound. Smaller households and greater mobility made room for voluntary associations: monasteries, guilds, communes, cathedral chapters, universities and merchant companies. People increasingly organised around rules, offices and shared purposes rather than blood alone. Corporations could own property, preserve privileges and outlive the people who formed them. These institutions trained Europeans to trust strangers, keep records and submit disputes to impersonal procedures. The medieval city became a workshop for a new kind of social freedom.",
    focus: { latitude: 44.49, longitude: 11.34 },
    camera: { x: 0.369, y: 0.585, scale: 1.58, rotation: 0.008 },
    palette: "monastic",
    layers: ["terrain", "towns", "route", "landmark"],
    sourceIds: ["schulz-2019", "henrich-2020"],
    landmark: "Bologna and the University",
    side: "right",
    hotspots: [
      {
        id: "bologna",
        label: "Bologna",
        detail:
          "Students and masters formed a self-governing legal corporation whose privileges helped define the medieval university.",
        latitude: 44.49,
        longitude: 11.34,
      },
      {
        id: "cluny",
        label: "Cluny",
        detail:
          "The abbey led a network of monasteries that reached beyond local lordship and made institutional discipline continental.",
        latitude: 46.43,
        longitude: 4.66,
      },
    ],
  },
  {
    id: "empire-many-liberties",
    order: 7,
    period: { start: 962, end: 1806, label: "962–1806" },
    title: "The Empire of Many Liberties",
    kicker: "The Holy Roman Empire",
    thesis: "At Europe’s centre, unity survived without uniformity.",
    body:
      "Otto I’s imperial coronation restored the western Roman claim and anchored a political order that endured for more than eight centuries. The Holy Roman Empire was never a centralised state. Emperor, princes, bishops, free cities, knights and rural communities held overlapping rights. Its intricate map recorded freedoms and obligations as much as political fragmentation. What once looked like weakness was also a durable constitution: authority was negotiated, jurisdictions balanced and conflicts channelled into assemblies and courts. The imperial reform of 1495 strengthened public peace and established a supreme chamber court. The empire’s achievement was not command from one capital, but an order spacious enough to contain many liberties.",
    focus: { latitude: 52.13, longitude: 11.63 },
    camera: { x: 0.372, y: 0.423, scale: 1.54, rotation: -0.012 },
    palette: "imperial",
    layers: ["terrain", "circles", "route", "landmark"],
    sourceIds: ["wilson-2016", "westphal-2018"],
    landmark: "Magdeburg and the Imperial Crown",
    side: "left",
    hotspots: [
      {
        id: "magdeburg",
        label: "Magdeburg",
        detail:
          "Otto I made the city an ecclesiastical and imperial centre facing the Slavic frontier; its urban law later travelled widely eastward.",
        latitude: 52.13,
        longitude: 11.63,
      },
      {
        id: "speyer",
        label: "Speyer",
        detail:
          "The Romanesque cathedral became a monumental burial church for Salian emperors and a statement of imperial continuity.",
        latitude: 49.32,
        longitude: 8.43,
      },
    ],
  },
  {
    id: "frontiers-hold",
    order: 8,
    period: { start: 711, end: 1699, label: "711–1699" },
    title: "The Frontiers Hold",
    kicker: "Defence and Recovery",
    thesis: "Europe’s frontiers were made by centuries of resistance, recovery and counter-attack.",
    body:
      "The Christian kingdoms of Iberia advanced south across lands conquered after 711, ending Muslim sovereignty at Granada in 1492. In the east, Byzantium’s appeal for aid helped launch the first crusading movement after Turkish conquest had overrun much of Anatolia. Later, Ottoman armies crossed the Balkans, destroyed the eastern Roman state and pressed into Hungary and toward Vienna. Pressure from North Africa, Anatolia and the steppe made security a continental question. These conflicts were neither continuous nor simple—alliances often crossed religious lines—but their long arc shaped Europe’s boundaries. At Lepanto, Vienna and along the Military Frontier, defence demanded fleets, fortresses, taxes and cooperation.",
    focus: { latitude: 48.21, longitude: 16.37 },
    camera: { x: 0.428, y: 0.506, scale: 1.42, rotation: 0.008 },
    palette: "frontier",
    layers: ["terrain", "frontiers", "route", "landmark"],
    sourceIds: ["reilly-1993", "smith-2024", "agoston-2025"],
    landmark: "Vienna and the Eastern Frontier",
    side: "right",
    hotspots: [
      {
        id: "granada",
        label: "Granada",
        detail:
          "Its surrender in 1492 ended the last Muslim sovereign state in Iberia and completed the territorial arc of the Reconquista.",
        latitude: 37.18,
        longitude: -3.6,
      },
      {
        id: "vienna",
        label: "Vienna",
        detail:
          "The failed Ottoman sieges of 1529 and 1683 made the Habsburg capital a symbol of Europe’s south-eastern defence.",
        latitude: 48.21,
        longitude: 16.37,
      },
    ],
  },
  {
    id: "europe-turns-seaward",
    order: 9,
    period: { start: 1415, end: 1700, label: "1415–1700" },
    title: "Europe Turns Seaward",
    kicker: "The Oceanic Turn",
    thesis: "Navigation, finance and armed shipping moved Europe’s horizon from the Mediterranean to the world.",
    body:
      "Portugal’s capture of Ceuta in 1415 opened a century of deliberate movement down the African coast and into the Atlantic. Iberian mariners combined inherited Mediterranean practice with improved cartography, navigation and ship design. Ocean-going cannon, commercial credit and royal protection made distant routes sustainable. Spain crossed the Atlantic; Portugal reached India; Dutch, English and French rivals followed. The ocean became a political space that ships, ports and contracts could organise. Europe’s expansion depended on conquest, alliance and local knowledge as well as seamanship. Yet the strategic change was unmistakable: European states learned to project organised power across oceans and to connect distant markets through their own fleets.",
    focus: { latitude: 38.72, longitude: -9.14 },
    camera: { x: 0.128, y: 0.708, scale: 1.32, rotation: -0.018 },
    palette: "atlantic",
    layers: ["terrain", "sea-routes", "route", "landmark"],
    sourceIds: ["parker-2012"],
    landmark: "Lisbon and the Atlantic",
    side: "left",
    hotspots: [
      {
        id: "lisbon",
        label: "Lisbon",
        detail:
          "The Tagus became the departure point and commercial clearing house for Portugal’s routes around Africa and into Asia.",
        latitude: 38.72,
        longitude: -9.14,
      },
      {
        id: "seville",
        label: "Seville",
        detail:
          "Spain channelled legal trade with the Americas through the Casa de Contratación, turning a river port into an Atlantic command centre.",
        latitude: 37.39,
        longitude: -5.99,
      },
    ],
  },
  {
    id: "rivalry-science-industry",
    order: 10,
    period: { start: 1450, end: 1850, label: "1450–1850" },
    title: "Rivalry, Science and Industry",
    kicker: "The Great Acceleration",
    thesis: "Europe’s political plurality turned rivalry into a machine for discovery.",
    body:
      "No single ruler could permanently close Europe’s intellectual or commercial life. Printers, scholars, engineers, merchants and religious dissenters could move between competing courts and cities. The press multiplied argument. Scientific societies made experiment public. States sought better guns, ships, taxes and credit; investors sought new machines and markets. Rival states copied success quickly because failure threatened treasure, territory and survival. Competition was often destructive, but it also rewarded useful knowledge. By the eighteenth century, a culture of improvement joined practical craft to formal science. In Britain, abundant coal, skilled labour and finance helped turn that culture into industrial power. Steam compressed distance and remade the scale of production.",
    focus: { latitude: 53.48, longitude: -2.24 },
    camera: { x: 0.209, y: 0.394, scale: 1.34, rotation: 0.012 },
    palette: "industrial",
    layers: ["terrain", "networks", "route", "landmark"],
    sourceIds: ["hoffman-2015", "mokyr-2016"],
    landmark: "Manchester",
    side: "right",
    hotspots: [
      {
        id: "london",
        label: "London",
        detail:
          "Scientific societies, public credit and a dense world of printers and merchants joined knowledge to state and commercial power.",
        latitude: 51.51,
        longitude: -0.13,
      },
      {
        id: "manchester",
        label: "Manchester",
        detail:
          "Cotton mills, steam power and transport networks made the city one of the clearest landscapes of industrial transformation.",
        latitude: 53.48,
        longitude: -2.24,
      },
    ],
  },
  {
    id: "european-world",
    order: 11,
    period: { start: 1815, end: 1914, label: "1815–1914" },
    title: "The European World",
    kicker: "Continental Ascendancy",
    thesis: "Industry gave Europe a global reach without precedent.",
    body:
      "After 1815, the great powers built a continental balance while industry transformed the material basis of power. Railways, steamships, telegraphs and modern finance connected European capitals to an expanding world economy. European law, languages, education and administrative forms travelled with merchants, missionaries, soldiers and officials. Vienna, London and Paris became command points in a system of global exchange. Empires opened routes, imposed hierarchies and organised territory on a vast scale. The benefits and burdens were distributed unequally, but the concentration of capacity was extraordinary. By 1914, a small continent commanded most of the world’s long-distance shipping, capital exports and imperial territory—and believed its predominance might endure.",
    focus: { latitude: 48.86, longitude: 2.35 },
    camera: { x: 0.263, y: 0.492, scale: 1.36, rotation: -0.006 },
    palette: "belle-epoque",
    layers: ["terrain", "telegraph", "route", "landmark"],
    sourceIds: ["orourke-2010", "darwin-2007"],
    landmark: "Paris and the Railway Age",
    side: "left",
    hotspots: [
      {
        id: "paris",
        label: "Paris",
        detail:
          "Railways, boulevards, exhibitions and finance made the city a stage on which industrial Europe displayed its confidence.",
        latitude: 48.86,
        longitude: 2.35,
      },
      {
        id: "vienna-congress",
        label: "Vienna",
        detail:
          "The settlement of 1814–15 restored a balance among the great powers and supplied a diplomatic framework for the century that followed.",
        latitude: 48.21,
        longitude: 16.37,
      },
    ],
  },
  {
    id: "europe-at-war",
    order: 12,
    period: { start: 1914, end: 1945, label: "1914–1945" },
    title: "Europe at War with Itself",
    kicker: "The Catastrophe",
    thesis: "Europe’s mastery of organisation and technology turned inward—and shattered its primacy.",
    body:
      "In 1914, the continental system failed. Mobilisation timetables pulled empires into a war of artillery, trenches and industrial attrition. The peace that followed broke old states without securing a stable order. Fascism, Nazism and Soviet communism harnessed mass politics, bureaucracy and technology to total claims over society. A second war consumed cities, murdered millions and culminated in the Holocaust. Europe’s greatest capacities—science, industry and administration—were enlisted in its self-destruction. The continent emerged divided, exhausted and dependent on powers beyond it. The long route of ascent did not simply slow; it broke. The world Europe had organised survived only in fragments, while leadership passed west to the United States and east to the Soviet Union.",
    focus: { latitude: 49.16, longitude: 5.38 },
    camera: { x: 0.299, y: 0.486, scale: 1.66, rotation: 0.018 },
    palette: "catastrophe",
    layers: ["terrain", "fracture", "route", "landmark"],
    sourceIds: ["mazower-1998"],
    landmark: "Verdun",
    side: "right",
    hotspots: [
      {
        id: "verdun",
        label: "Verdun",
        detail:
          "Ten months of battle in 1916 made the fortified zone a byword for industrial attrition and national endurance.",
        latitude: 49.16,
        longitude: 5.38,
      },
      {
        id: "auschwitz",
        label: "Auschwitz",
        detail:
          "The German camp complex became the largest site of murder in the Holocaust and the most terrible terminus of totalitarian rule.",
        latitude: 50.04,
        longitude: 19.18,
      },
    ],
  },
  {
    id: "continent-rebuilt",
    order: 13,
    period: { start: 1945, end: 1991, label: "1945–1991" },
    title: "The Continent Rebuilt",
    kicker: "Recovery",
    thesis: "Under Atlantic protection, Western Europe rebuilt prosperity and placed law above rivalry.",
    body:
      "Reconstruction began among ruins. American capital and security allowed Western European states to recover while maintaining democratic institutions and social peace. Coal and steel—the foundations of war—were placed under common authority. The European communities expanded from practical cooperation into a shared legal and economic order. Integration advanced through treaties, courts, markets and thousands of uncelebrated administrative decisions. Borders softened in the west even as the Iron Curtain divided the continent. NATO supplied the defence that Europe could not yet provide alone. By the late twentieth century, the western half of Europe had achieved an unusual combination: national freedom, common rules, mass prosperity and peace among former great-power rivals.",
    focus: { latitude: 50.85, longitude: 4.35 },
    camera: { x: 0.286, y: 0.45, scale: 1.52, rotation: -0.008 },
    palette: "reconstruction",
    layers: ["terrain", "rebuilding", "route", "landmark"],
    sourceIds: ["judt-2005"],
    landmark: "Brussels",
    side: "left",
    hotspots: [
      {
        id: "brussels",
        label: "Brussels",
        detail:
          "The institutions gathered here turned treaties into a permanent system of shared administration, negotiation and law.",
        latitude: 50.85,
        longitude: 4.35,
      },
      {
        id: "berlin-wall",
        label: "Berlin",
        detail:
          "From 1961 to 1989, the Wall gave concrete form to Europe’s division between the Atlantic and Soviet systems.",
        latitude: 52.52,
        longitude: 13.41,
      },
    ],
  },
  {
    id: "europe-returns",
    order: 14,
    period: { start: 1991, label: "1991–PRESENT" },
    title: "Europe Returns",
    kicker: "The Unfinished Journey",
    thesis: "Reunification restored Europe’s scale; the eastern frontier asks whether prosperity can become power.",
    body:
      "The collapse of Soviet rule allowed nations from the Baltic to the Balkans to rejoin Europe’s common institutions. The European Union widened; NATO moved east; old cities and routes reconnected across borders once sealed by force. Yet reunion did not end history. Russia’s war against Ukraine returned territorial conquest to the centre of European politics and exposed the distance between economic weight and strategic will. The question is whether a prosperous union can also act as a power. Europe still possesses immense capital, knowledge, institutions and cultural confidence. The completed route now glows across the continent. Its final direction remains open: inheritance becomes destiny only when a civilisation chooses to defend and renew it.",
    focus: { latitude: 50.45, longitude: 30.52 },
    camera: { x: 0.594, y: 0.458, scale: 1.35, rotation: 0.004 },
    palette: "present",
    layers: ["terrain", "union", "route", "landmark"],
    sourceIds: ["eu-history", "nato-enlargement"],
    landmark: "Kyiv and Europe’s Eastern Frontier",
    side: "right",
    hotspots: [
      {
        id: "tallinn",
        label: "Tallinn",
        detail:
          "Estonia’s return to European institutions shows how swiftly a formerly occupied state could rebuild a western legal and digital order.",
        latitude: 59.44,
        longitude: 24.75,
      },
      {
        id: "kyiv-present",
        label: "Kyiv",
        detail:
          "The Ukrainian capital now stands at the meeting point of the Rus’ inheritance, European integration and resistance to Russian conquest.",
        latitude: 50.45,
        longitude: 30.52,
      },
    ],
  },
];

export const sceneById = new Map(scenes.map((scene) => [scene.id, scene]));
