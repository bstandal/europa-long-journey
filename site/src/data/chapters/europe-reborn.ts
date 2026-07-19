import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/europe-reborn";

export const europeReborn: ChapterDefinition = {
  slug: "europe-reborn",
  number: "07",
  title: "Europe Reborn",
  period: "AD 500–1000",
  claim:
    "Western Rome fell, but its Christian inheritance did not. Bishops, monasteries and kings rebuilt it as a commonwealth that could survive without one empire—and grow beyond Rome’s old frontiers.",
  theme: {
    id: "carolingian",
    label: "The written commonwealth",
  },
  openingAction: "Follow the rebuilt road",
  mapLabel:
    "The cities, courts, monasteries and missions that connected post-Roman Europe",
  routeImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Chronicles · rules · capitularies · charters · letters · manuscripts · churches · graves · hoards · settlements",
  acts: [
    {
      id: "survival",
      number: "I",
      label: "Institutions after empire",
      period: "AD 476–590",
      title: "The City Outlives the Crown",
      detail:
        "Royal government fragments in the western provinces while bishops, households and monasteries adapt Roman offices, property and writing to smaller political worlds.",
    },
    {
      id: "frankish-order",
      number: "II",
      label: "Kingship and discipline",
      period: "AD 496–804",
      title: "Crown, Font and Written Command",
      detail:
        "Frankish rulers bind conquest to Catholic patronage, sacred kingship and written government, creating a realm whose unity depends on repeated local work.",
    },
    {
      id: "imperial-inheritance",
      number: "III",
      label: "Empire divided and renewed",
      period: "AD 800–973",
      title: "One Crown Becomes Several Claims",
      detail:
        "A western imperial coronation revives Roman language, dynastic division breaks Carolingian unity, and rulers from Saxony to the North Sea adapt its inheritance.",
    },
    {
      id: "widening-commonwealth",
      number: "IV",
      label: "New Christian polities",
      period: "AD 845–1000",
      title: "The Commonwealth Crosses the Frontier",
      detail:
        "Rulers and communities in central, northern and eastern Europe receive Christianity through Latin and Byzantine networks and turn conversion into durable institutions.",
    },
  ],
  ending: {
    period: "AD 1000",
    title: "Europe can meet without one ruler",
    detail:
      "At Gniezno, an emperor, a Polish ruler and the clergy around a missionary’s shrine recognised one another through gifts, ritual and a new archbishopric. Their agreement depended on a common Christian language and left each political centre intact. That plurality would soon produce a harder question: who could appoint the bishops and command the institutions that held this commonwealth together?",
    image: `${imageRoot}/14-europe-meets-gniezno.avif`,
    mobileImage: `${imageRoot}/14-europe-meets-gniezno-mobile.avif`,
    nextPeriod: "AD 1049–1122",
  },
  returnHash: "europe-reborn",
  nextHash: "papal-revolution",
  nextTitle: "The Papal Revolution",
  movements: [
    {
      id: "crown-leaves-the-west",
      actId: "survival",
      order: 1,
      period: "c. AD 500",
      place: "Tours · the former Roman province of Gaul",
      title: "The Crown Leaves the West",
      thesis:
        "The disappearance of a western emperor narrowed government without erasing the property, offices and habits that Roman rule had left behind.",
      body: [
        "A generation after the last western emperor was deposed, Tours remained a city of walls, churches, workshops, estates and written claims. The imperial tax system had lost the scale and regularity it once possessed. Long-distance state supply contracted; local magnates controlled more land and armed followings; kings moved with courts whose reach depended on loyalty and presence. The Roman city had become a smaller political arena, governed through bargains among rulers, landholders, clergy and communities.",
        "Continuity lay in practices rather than an intact state. Latin remained the language of law and worship. Titles, fiscal privileges, land registers and the prestige of Roman office entered the service of successor kings. Roads, bridges and stone buildings survived unevenly because people repaired what their reduced resources allowed. Western Rome ceased to command its former provinces, while Roman property, Christian institutions and written memory supplied the materials from which new governments could be assembled.",
        "The scale of change differed across the old empire. Parts of Italy, Gaul and Iberia retained cities, coinage and Mediterranean exchange; Britain lost most Roman urban and fiscal structures; rural communities everywhere carried a larger share of subsistence and defence. “Post-Roman” names a common political rupture whose material consequences remained regional.",
      ],
      image: `${imageRoot}/01-crown-leaves-west.avif`,
      mobileImage: `${imageRoot}/01-crown-leaves-west-mobile.avif`,
      imageAlt:
        "A cleric writes beside wax tablets and bound books in a reused Roman hall while a mounted messenger enters a muddy post-imperial town through a round arch.",
      imagePosition: "62% center",
      mobileImagePosition: "64% center",
      visualTone: "charcoal-vellum",
      side: "left",
      sourceIds: ["wickham-2005", "gregory-tours-franks"],
      evidence: [
        "Archaeology records sharply different regional contractions in settlement, exchange and public construction after Roman rule.",
        "Law codes, charters and episcopal histories preserve Roman titles and property forms inside successor kingdoms.",
      ],
      map: { x: 42, y: 56 },
    },
    {
      id: "bishop-keeps-the-city",
      actId: "survival",
      order: 2,
      period: "AD 573–594",
      place: "Tours · a bishop’s household and basilica",
      title: "The Bishop Keeps the City",
      thesis:
        "A bishop could turn property, literacy and sacred authority into practical urban government when royal power arrived only at intervals.",
      body: [
        "Gregory of Tours wrote as bishop, landholder, judge, patron and political intermediary. Petitioners came to churches because bishops controlled stores, clerks, sanctuary and access to rulers. Clergy ransomed captives, distributed food, supervised buildings and negotiated with counts. These activities grew from the church’s landed wealth and corporate continuity. They also depended on servants, tenants and donors whose labour made charity and ceremony possible.",
        "Episcopal government never replaced every civic institution. Counts commanded royal justice and armed force; aristocratic families defended their own claims; monasteries and basilicas competed for property. A bishop’s influence varied with reputation, kinship and relations at court. His office carried one exceptional advantage: succession could preserve archives, estates and obligations beyond a king’s visit or a family’s death. The city acquired an institution able to remember what previous holders had promised.",
        "That archive also shaped what can now be known. Clerics recorded violations of church property, miracles at saints’ shrines and negotiations involving bishops more readily than the routines of farmers or craftspeople. Their prominence in surviving texts reflects real institutional power and the unequal survival of voices. Civic continuity must be read through both facts.",
      ],
      image: `${imageRoot}/02-bishop-keeps-city.avif`,
      imageAlt:
        "A sixth-century bishop and deacon distribute grain and hear petitioners inside a reused late-Roman civic hall with round arches.",
      imagePosition: "40% center",
      visualTone: "grain-and-wax",
      side: "right",
      sourceIds: ["gregory-tours-franks", "wickham-2005"],
      evidence: [
        "Gregory’s Histories and hagiographic works place bishops inside disputes over sanctuary, taxation, famine, property and royal violence.",
        "Church councils, wills and charters document the estates and clerical personnel that sustained episcopal action.",
      ],
      map: { x: 42, y: 56 },
      interaction: {
        kind: "commonwealth-city",
        prompt: "Place four civic burdens in the bishop’s household",
        accessibleSummary:
          "Four states show how stores, clerks, sanctuary and royal access gave a bishop practical authority with clear limits.",
        states: [
          {
            id: "relief",
            label: "Feed",
            period: "scarcity",
            detail:
              "Church estates and gifts could supply grain for organised relief when local harvests or markets failed.",
            office: "Steward of ecclesiastical stores",
            instrument: "Estate rents, alms, granaries and clerical distribution",
            limit: "Supply depended on land, transport and the bishop’s household",
          },
          {
            id: "judgment",
            label: "Hear",
            period: "dispute",
            detail:
              "Petitioners used a bishop’s hall to seek arbitration, sanctuary or a letter to a royal official.",
            office: "Mediator rather than sole magistrate",
            instrument: "Oaths, witnesses, letters and negotiated settlement",
            limit: "Counts, kings and magnates retained coercive power",
          },
          {
            id: "memory",
            label: "Record",
            period: "succession",
            detail:
              "Clerks preserved gifts, rents and obligations across the death of an individual officeholder.",
            office: "Guardian of an institutional archive",
            instrument: "Charters, estate lists, books and trained scribes",
            limit: "Documents mattered when a community could defend their claims",
          },
          {
            id: "access",
            label: "Intercede",
            period: "royal visit",
            detail:
              "Sacred status and elite connections allowed a bishop to petition rulers for captives, cities and church property.",
            office: "Broker between local society and itinerant court",
            instrument: "Personal audience, relics, letters and public ritual",
            limit: "Intercession relied on royal consent and political trust",
          },
        ],
      },
    },
    {
      id: "frank-enters-the-font",
      actId: "frankish-order",
      order: 3,
      period: "c. AD 496–508",
      place: "Reims · the baptism remembered by Gregory of Tours",
      title: "A Frank Enters the Font",
      thesis:
        "Clovis’s Catholic baptism aligned a conquering dynasty with the bishops and Roman population of Gaul.",
      body: [
        "Gregory of Tours presents Clovis turning to the Christian God during war, receiving instruction from Queen Clotild and entering the font at Reims with Bishop Remigius. The narrative was written decades after the event and shaped as sacred history. The exact year remains disputed. Coins, letters and the political sequence confirm that Clovis emerged as a Catholic king while rival Visigothic and Burgundian rulers were associated with non-Nicene Christianity.",
        "The baptism created an alliance, not an instant conversion of every Frank. Royal patronage protected churches and councils; bishops could interpret conquest through a Catholic language shared with the old Roman population. Frankish warriors retained their own loyalties, and violence continued within the dynasty. The durable change lay in the crown’s chosen partners. A Germanic-speaking military elite and a Latin Christian episcopate could represent one kingdom through a single rite.",
        "At the Council of Orléans in 511, bishops met with royal approval and legislated on sanctuary, clerical discipline and church property. The council shows the alliance becoming procedure. The king could gather a provincial episcopate; bishops could state common rules; both could extend decisions through local churches whose authority did not depend on a permanent capital.",
      ],
      image: `${imageRoot}/03-frank-enters-font.avif`,
      imageAlt:
        "Clovis stands in a late-antique baptismal pool while Bishop Remigius performs the rite before a restrained Frankish retinue.",
      imagePosition: "62% center",
      visualTone: "font-and-oath",
      side: "left",
      sourceIds: ["gregory-tours-franks", "wickham-2005"],
      evidence: [
        "Gregory of Tours supplies the fullest narrative of the baptism and writes from a later sixth-century episcopal perspective.",
        "The date, sequence and scale of the conversion require reconstruction from later narrative, contemporary letters and royal policy.",
      ],
      map: { x: 45, y: 53 },
      interaction: {
        kind: "commonwealth-trace",
        prompt: "Separate one baptism from a kingdom’s conversion",
        accessibleSummary:
          "Three stops distinguish royal rite, episcopal alliance and the slower work of Christianisation.",
        stops: [
          {
            id: "font",
            label: "Rite",
            period: "c. 496–508",
            detail:
              "A ruler receives Catholic baptism in the narrative preserved by Gregory of Tours.",
            instrument: "Baptism, anointing, creed and episcopal sponsorship",
            reach: "The king, household and assembled followers",
            inheritance: "A public religious identity for the dynasty",
          },
          {
            id: "alliance",
            label: "Alliance",
            period: "early sixth century",
            detail:
              "Royal protection and episcopal cooperation connect Frankish conquest to Gallo-Roman institutions.",
            instrument: "Councils, patronage, immunity and personal intercession",
            reach: "Cities and church estates across conquered Gaul",
            inheritance: "A Catholic language of legitimate kingship",
          },
          {
            id: "parish",
            label: "Practice",
            period: "generations",
            detail:
              "Clergy, households and local cults carry Christian practice far beyond the royal ceremony.",
            instrument: "Baptismal churches, saints’ shrines, preaching and burial",
            reach: "Communities unevenly connected to church institutions",
            inheritance: "Gradual Christianisation rather than a single conversion day",
          },
        ],
      },
    },
    {
      id: "rule-orders-the-day",
      actId: "frankish-order",
      order: 4,
      period: "c. AD 530–547",
      place: "Monte Cassino · central Italy",
      title: "The Rule Orders the Day",
      thesis:
        "A monastic rule converted time, obedience and material work into an institution that could be copied across political borders.",
      body: [
        "The Rule associated with Benedict of Nursia organises a community around an abbot, common property, prayer, reading, hospitality and manual labour. It assumes storerooms, tools, clothing, kitchens and fields as carefully as it regulates psalms. Authority is intimate and demanding: the abbot knows individuals, assigns work and answers for judgment. Monastic order begins in repeated acts performed by a particular household.",
        "Benedict’s text became widely dominant only through later copying and Carolingian promotion. Early medieval monasteries followed several customs, served aristocratic families and relied on extensive estates worked by dependants. Their contribution to continuity came from durable routines: training readers, preserving records, receiving travellers and managing property across generations. A monastery could carry the same rule into a new kingdom while adapting its economy to local land and patrons.",
        "Preservation was selective. Scribes copied texts needed for worship, grammar, law and elite memory, while countless works disappeared. Libraries could burn, disperse or scrape old parchment for reuse. Monasteries mattered because they renewed a limited body of writing through repeated labour. Their achievement was institutional reproduction under conditions of scarcity, choice and dependence.",
      ],
      image: `${imageRoot}/04-rule-orders-day.avif`,
      imageAlt:
        "Monks read, copy a book, repair a tool and prepare bread in a modest sixth-century workshop at Monte Cassino.",
      imagePosition: "56% center",
      visualTone: "rule-and-labour",
      side: "right",
      sourceIds: ["rule-benedict", "wickham-2005", "costambeys-2011"],
      evidence: [
        "The Rule describes prayer, reading, food, clothing, tools, hospitality and authority inside a working monastic household.",
        "Manuscript transmission and Carolingian legislation show its gradual promotion among several early monastic traditions.",
      ],
      map: { x: 50, y: 69 },
      interaction: {
        kind: "commonwealth-trace",
        prompt: "Order one day into a durable institution",
        accessibleSummary:
          "Three stops connect common prayer, trained reading and managed property.",
        stops: [
          {
            id: "hours",
            label: "Keep hours",
            period: "each day",
            detail:
              "A shared timetable makes communal obligation visible and repeatable.",
            instrument: "Bell, psalm cycle, night office and assigned duties",
            reach: "Every member of the household",
            inheritance: "Institutional time that survives individual lives",
          },
          {
            id: "reading",
            label: "Train readers",
            period: "each season",
            detail:
              "Reading aloud and private study require books, instruction and disciplined attention.",
            instrument: "Codices, copying, correction and memorisation",
            reach: "Monks, pupils, clergy and patrons",
            inheritance: "A reproducible culture of Latin learning",
          },
          {
            id: "estate",
            label: "Manage land",
            period: "across generations",
            detail:
              "Common property supports worship and hospitality through organised labour and rents.",
            instrument: "Stewards, estate records, tenants, workshops and stores",
            reach: "A wider dependent population around the monastery",
            inheritance: "Corporate property held beyond one abbot’s tenure",
          },
        ],
      },
    },
    {
      id: "king-receives-the-oil",
      actId: "frankish-order",
      order: 5,
      period: "AD 751–754",
      place: "The Frankish kingdom · Saint-Denis",
      title: "The King Receives the Oil",
      thesis:
        "Pippin’s elevation joined aristocratic choice, papal alliance and sacred rite to give a new dynasty an accepted title.",
      body: [
        "Pippin already commanded the Frankish realm as mayor of the palace when the last Merovingian king was removed. A royal title had to be made credible among magnates accustomed to another dynasty. Sources written under Carolingian rule describe papal approval and an anointing, though the evidence for a first rite in 751 is uncertain. In 754 Pope Stephen II crossed the Alps and anointed Pippin and his sons at Saint-Denis.",
        "The ceremony gave each party something practical. The Carolingians received sacred confirmation and dynastic succession. The pope gained an armed protector against Lombard pressure in Italy. Frankish campaigns then transferred conquered territories to papal government. Kingship rested on warriors, land and aristocratic consent; oil added a Christian vocabulary of office and obligation. A ruler could be judged by the mission conferred at the altar as well as by descent.",
        "Anointing also changed succession politics. Stephen extended the rite to Pippin’s sons and warned the Franks against choosing a king from another line. Sacred language fortified a dynastic programme created through deposition. The new dynasty would answer papal requests in Italy, while popes learned that a ruler beyond the Alps could remake political order around Rome.",
      ],
      image: `${imageRoot}/05-king-receives-oil.avif`,
      mobileImage: `${imageRoot}/05-king-receives-oil-mobile.avif`,
      imageAlt:
        "A Frankish king kneels for papal anointing in a modest eighth-century basilica while clerics and magnates witness.",
      imagePosition: "52% center",
      mobileImagePosition: "51% center",
      visualTone: "oil-and-compact",
      side: "left",
      sourceIds: ["costambeys-2011", "royal-frankish-annals"],
      evidence: [
        "Papal biographies and Carolingian narratives preserve the alliance and the well-attested anointing at Saint-Denis in 754.",
        "The evidence for an anointing in 751 is late and contested; the political elevation and the later papal rite must be distinguished.",
      ],
      map: { x: 43, y: 55 },
    },
    {
      id: "frontier-enters-by-sword-and-font",
      actId: "frankish-order",
      order: 6,
      period: "AD 772–804",
      place: "Saxony · between Rhine and Elbe",
      title: "The Frontier Enters by Sword and Font",
      thesis:
        "Frankish conquest forced Saxon submission and baptism, while lasting Christian institutions grew through slower local settlement.",
      body: [
        "Charlemagne’s armies campaigned repeatedly in Saxony, destroyed the Irminsul sanctuary, took hostages, deported communities and demanded oaths. The Capitulatio de partibus Saxoniae attached severe penalties to resistance and certain non-Christian practices. The execution reported at Verden in 782 belongs to this coercive landscape, although its precise circumstances and scale remain debated. Baptism could mark political defeat under armed supervision.",
        "Conquest did not produce uniform belief. Frankish rulers founded bishoprics and monasteries, redistributed land and worked through Saxon elites. Clergy translated teaching into local settings; families combined older customs with new rites; resistance and accommodation changed across regions. By the tenth century a Saxon dynasty would claim the western imperial title. That reversal grew from institutions established after violence and reshaped by the descendants of the conquered.",
        "The frontier therefore exposes two timescales. Annals compress a campaign, submission and baptism into one royal year. Churches, cemeteries and local patronage reveal Christianisation continuing after the army moved on. Force altered the field of choice; generations of Saxons then decided how the imported offices, stories and rituals would operate inside their own communities.",
      ],
      image: `${imageRoot}/06-saxon-frontier.avif`,
      imageAlt:
        "A guarded baptism and oath take place beside a timber church and a felled sacred grove on the Carolingian Saxon frontier.",
      imagePosition: "46% center",
      visualTone: "iron-and-water",
      side: "right",
      sourceIds: ["rembold-2017", "royal-frankish-annals", "carolingian-capitularies"],
      evidence: [
        "Royal annals and capitularies document repeated campaigns, hostages, deportations, compulsory baptism and severe legal penalties.",
        "Church foundations and later Saxon evidence reveal regional adaptation beyond the court’s language of immediate submission.",
      ],
      map: { x: 49, y: 47 },
      interaction: {
        kind: "commonwealth-trace",
        prompt: "Track conquest into uneven Christianisation",
        accessibleSummary:
          "Three stops expose coercive oath, planted institution and local appropriation.",
        stops: [
          {
            id: "submission",
            label: "Submit",
            period: "772–804",
            detail:
              "Campaign, hostage-taking and oath bind military defeat to compulsory baptism.",
            instrument: "Army, capitulary, assembly and imposed rite",
            reach: "Leaders and communities under Frankish pressure",
            inheritance: "A Christian settlement carrying the memory of force",
          },
          {
            id: "foundation",
            label: "Plant",
            period: "late eighth century",
            detail:
              "Bishoprics, monasteries and estates give the new order permanent local personnel.",
            instrument: "Land grants, churches, schools and clerical appointments",
            reach: "Strategic centres and their dependent districts",
            inheritance: "Institutions that remain after an army withdraws",
          },
          {
            id: "appropriation",
            label: "Adapt",
            period: "ninth–tenth centuries",
            detail:
              "Saxon elites and communities make Christian offices part of their own political society.",
            instrument: "Local patronage, marriage, burial and vernacular teaching",
            reach: "Households and regional aristocracies",
            inheritance: "A former frontier becomes an imperial centre",
          },
        ],
      },
    },
    {
      id: "word-travels-further-than-king",
      actId: "frankish-order",
      order: 7,
      period: "AD 779–813",
      place: "Aachen · Frankfurt · monasteries and county courts",
      title: "The Word Travels Further Than the King",
      thesis:
        "Capitularies, letters and corrected books let an itinerant court project expectations farther than the ruler could travel.",
      body: [
        "Charlemagne governed by movement, assembly and delegation. Counts, bishops, abbots and royal envoys gathered at court, carried decisions outward and returned with disputes. Capitularies organised subjects ranging from military service and justice to schools, preaching and estate management. Their surviving manuscripts often differ, because texts were selected, copied and combined for particular users rather than issued as one uniform code.",
        "Writing strengthened government through people who interpreted it. A command drafted near the king had to be copied by a competent scribe, carried along roads, read at a local assembly and converted into judgment or routine. Royal envoys investigated officials; oaths made obligations public; corrected liturgical books aligned worship. Compliance varied widely. The achievement was a shared field of reference in which a local decision could answer to words attributed to a distant ruler.",
        "The Admonitio generalis of 789 illustrates the range of this ambition. It addressed clerical education, preaching, schools, measures and conduct as parts of one Christian order. No chancery could inspect every parish. The programme recruited bishops, abbots and counts as responsible interpreters, joining moral correction to administrative delegation and making reform a recurring duty.",
      ],
      image: `${imageRoot}/07-word-travels.avif`,
      imageAlt:
        "A mounted Carolingian messenger exchanges a sealed capitulary with a monastery scribe beside wax tablets and folded vellum.",
      imagePosition: "62% center",
      visualTone: "ink-and-road",
      side: "left",
      sourceIds: ["mckitterick-1989", "davis-2015", "carolingian-capitularies"],
      evidence: [
        "Capitulary manuscripts, formulae, letters and estate records show extensive uses of writing in law, government and lay society.",
        "Variant collections and uneven survival reveal local selection and copying rather than mechanical transmission from one centre.",
      ],
      map: { x: 47, y: 52 },
      interaction: {
        kind: "written-network",
        prompt: "Carry one command from court to local judgment",
        accessibleSummary:
          "Four states follow a capitulary through drafting, copying, travel and local interpretation.",
        states: [
          {
            id: "deliberate",
            label: "Deliberate",
            period: "assembly",
            detail:
              "King, magnates and clergy turn petitions, disputes and reform into agreed headings.",
            author: "Court working through counsel and precedent",
            carrier: "Memory, notes and draft clauses",
            localAct: "A decision gains an attributed royal voice",
          },
          {
            id: "copy",
            label: "Copy",
            period: "scriptorium",
            detail:
              "A scribe selects and copies provisions for a recipient or regional collection.",
            author: "Trained cleric using an exemplar",
            carrier: "Ruled vellum, ink, headings and correction",
            localAct: "The command becomes portable and reproducible",
          },
          {
            id: "carry",
            label: "Carry",
            period: "royal road",
            detail:
              "Envoys, bishops and counts move texts with oral instruction and authority.",
            author: "Named bearer able to answer questions",
            carrier: "Horse, riverboat, sealed packet and hospitality",
            localAct: "Distant court enters a face-to-face assembly",
          },
          {
            id: "adapt",
            label: "Apply",
            period: "county court",
            detail:
              "Officials read, paraphrase and fit a general order to local rights and evidence.",
            author: "Count, bishop, witnesses and local notables",
            carrier: "Public reading, oath and written record",
            localAct: "Royal expectation becomes a negotiated judgment",
          },
        ],
      },
    },
    {
      id: "rome-crowns-western-emperor",
      actId: "imperial-inheritance",
      order: 8,
      period: "25 December AD 800",
      place: "Old St Peter’s · Rome",
      title: "Rome Crowns a Western Emperor",
      thesis:
        "Leo III’s coronation of Charlemagne joined Frankish force, papal ritual and Roman title in a new western imperial claim.",
      body: [
        "Charlemagne came to Rome after Pope Leo III had fled opponents and sought Frankish protection. A synod addressed the accusations against the pope; Leo swore an oath of purgation. On Christmas Day, during Mass at St Peter’s, Leo placed a crown on the Frankish king and the Roman congregation acclaimed him emperor. Papal and Frankish accounts agree on the act while presenting agency and expectation differently.",
        "The title did not resurrect the western empire of the fifth century. Charlemagne’s power rested on Frankish conquest, aristocratic networks, churches and an itinerant court north of the Alps. Coronation placed that power inside a Roman Christian vocabulary and complicated relations with Constantinople, whose rulers remained Roman emperors. Europe now contained two imperial centres able to claim Roman and Christian universality through different political worlds.",
        "Einhard later claimed that Charlemagne would have avoided the basilica had he known Leo’s plan. Frankish annals present the acclamation more positively. Both accounts were written within political relationships shaped by the result. Diplomatic recognition came in 812, when Emperor Michael I’s envoys addressed Charlemagne as emperor while each court guarded its own Roman claim.",
      ],
      image: `${imageRoot}/08-western-emperor.avif`,
      mobileImage: `${imageRoot}/08-western-emperor-mobile.avif`,
      imageAlt:
        "Pope Leo III crowns Charlemagne in candlelit Old St Peter’s before clergy and a Roman assembly on Christmas Day 800.",
      imagePosition: "46% center",
      mobileImagePosition: "49% center",
      visualTone: "crown-and-confessio",
      side: "right",
      sourceIds: ["einhard-life", "royal-frankish-annals", "costambeys-2011"],
      evidence: [
        "The Royal Frankish Annals, Einhard and the Liber Pontificalis preserve differing accounts of the coronation and its meaning.",
        "Diplomatic negotiation with Constantinople and Charlemagne’s later titulature show that recognition remained politically contested.",
      ],
      map: { x: 50, y: 69 },
    },
    {
      id: "heirs-divide-the-realm",
      actId: "imperial-inheritance",
      order: 9,
      period: "AD 843",
      place: "Verdun · the Carolingian realms",
      title: "The Heirs Divide the Realm",
      thesis:
        "The Treaty of Verdun distributed dynastic resources among three brothers without drawing the nations of modern Europe.",
      body: [
        "After Louis the Pious died, his sons fought over rank, inheritance and the resources required to reward followers. At Verdun, Lothar retained the imperial title and a long middle realm from the North Sea through Italy. Louis received lands east of the Rhine and north of the Alps; Charles received a western kingdom. Negotiators worked with counties, estates, roads, rivers and established loyalties rather than a clean map of peoples.",
        "The settlement ended one phase of civil war and opened further partitions. Each king needed bishops, counts, abbeys and royal lands capable of sustaining court and army. Boundaries remained permeable, and aristocratic families held interests across them. Modern France and Germany would develop through later centuries. Verdun’s immediate result was plural kingship inside a shared Carolingian Christian culture whose texts, monasteries and elite kinship crossed every share.",
        "The Strasbourg Oaths of 842 reveal how rulers made that plural politics audible. Louis and Charles swore before each other’s armies in Romance and Germanic vernaculars, while Nithard recorded the texts in Latin history. The languages helped soldiers understand a present alliance. They did not announce two timeless national communities or predetermine Verdun’s eventual borders.",
      ],
      image: `${imageRoot}/09-heirs-divide-realm.avif`,
      imageAlt:
        "Three Carolingian delegations negotiate around a waxed board, parchment itinerary and estate counters at Verdun in 843.",
      imagePosition: "60% center",
      visualTone: "wax-and-partition",
      side: "left",
      sourceIds: ["nithard-histories", "costambeys-2011", "mckitterick-1989"],
      evidence: [
        "Nithard writes as participant and cousin to the rulers, preserving the civil war, oaths and dynastic calculations around partition.",
        "Charters and later divisions show that rulers allocated fiscal resources and aristocratic relationships rather than modern national territory.",
      ],
      map: { x: 46, y: 54 },
      interaction: {
        kind: "realm-partition",
        prompt: "Divide a dynasty without inventing three nations",
        accessibleSummary:
          "Four states separate imperial rank, western and eastern shares, and the connected institutions left across them.",
        states: [
          {
            id: "lothar",
            label: "Middle realm",
            period: "Lothar I",
            detail:
              "Lothar keeps the imperial title and a discontinuous corridor linking northern lands, Burgundy and Italy.",
            share: "Imperial centres, Italy and territories between his brothers",
            basis: "Rank, royal estates, routes and negotiated counties",
            consequence: "A prestigious realm difficult to transmit as one durable unit",
          },
          {
            id: "louis",
            label: "Eastern realm",
            period: "Louis the German",
            detail:
              "Louis receives kingdoms and duchies east of the Rhine with their own aristocratic centres.",
            share: "Bavaria, Saxony, Alemannia, Thuringia and related lands",
            basis: "Existing rule, supporters and a viable fiscal core",
            consequence: "An eastern Frankish kingship with several regional peoples",
          },
          {
            id: "charles",
            label: "Western realm",
            period: "Charles the Bald",
            detail:
              "Charles receives western counties where magnates and bishops must accept a young king’s settlement.",
            share: "Western Frankish territories from Aquitaine toward the North Sea",
            basis: "Dynastic claim, negotiated allegiance and local resources",
            consequence: "A western kingship repeatedly tested by family and aristocracy",
          },
          {
            id: "shared",
            label: "Common field",
            period: "after 843",
            detail:
              "Latin worship, monastic networks and elite kinship continue to cross the dynastic shares.",
            share: "No single ruler controls the whole Carolingian inheritance",
            basis: "Books, offices, saints, marriages and remembered law",
            consequence: "Political division survives inside a connected commonwealth",
          },
        ],
      },
    },
    {
      id: "shores-burn-and-connect",
      actId: "imperial-inheritance",
      order: 10,
      period: "AD 793–900",
      place: "North Sea and Baltic shores",
      title: "The Shores Burn—and Connect",
      thesis:
        "Scandinavian raiding destroyed communities while the same ships carried trade, settlement and new political connections.",
      body: [
        "The attack on Lindisfarne in 793 became a Christian emblem of northern violence. Raids then reached monasteries, towns and river valleys from Ireland to Francia. Captives, silver and movable wealth rewarded crews; rulers exacted tribute or built defences; some fleets became armies seeking land. The human cost appears in burned sites, slave routes, hoards and chronicles written by those under attack.",
        "Ships also connected emerging towns such as Hedeby, Birka, York and Dublin. Merchants weighed silver, exchanged fur, cloth, metalwork and enslaved people, and linked the Baltic to Islamic and Byzantine markets through river routes. Settlement created mixed communities and new rulers. Scandinavian expansion belongs to Europe’s reconstruction because violence and exchange widened the field in which kingship, towns and Christianity would operate.",
        "The captive trade joins the two histories directly. People seized in raids could be sold through northern towns and eastern rivers, converted into household labour or ransomed by churches and families. Silver arriving from the Abbasid world records commercial reach, while shackles, burials and scattered testimony reveal whose bodies carried its cost. Connection offered unequal forms of mobility.",
      ],
      image: `${imageRoot}/10-shores-burn-connect.avif`,
      imageAlt:
        "Scandinavian merchants unload scales, silver and fur at a river quay watched by guards beside a repaired palisade.",
      imagePosition: "42% center",
      visualTone: "river-silver",
      side: "right",
      sourceIds: ["kalmring-2024", "berend-2007"],
      evidence: [
        "Archaeology of emporia, ship burials, weights, silver hoards and imported goods documents dense northern exchange networks.",
        "Annals and destruction layers record raiding and warfare; settlement evidence shows longer processes than episodic attack narratives.",
      ],
      map: { x: 51, y: 38 },
      interaction: {
        kind: "commonwealth-trace",
        prompt: "Follow one ship through three northern economies",
        accessibleSummary:
          "Three stops connect raid, market and settlement without collapsing their different human consequences.",
        stops: [
          {
            id: "raid",
            label: "Take",
            period: "seasonal raid",
            detail:
              "A mobile crew targets concentrated wealth, captives and prestige.",
            instrument: "Shallow-draft ship, intelligence, weapons and surprise",
            reach: "Coasts and navigable rivers",
            inheritance: "Fear, tribute, fortification and displaced people",
          },
          {
            id: "market",
            label: "Exchange",
            period: "trading season",
            detail:
              "Merchants turn silver by weight into goods gathered from distant regions.",
            instrument: "Scale, weights, hacksilver, craft production and credit",
            reach: "North Sea, Baltic and eastern river routes",
            inheritance: "Towns that concentrate skill, information and patronage",
          },
          {
            id: "settlement",
            label: "Remain",
            period: "generation",
            detail:
              "Families settle, farm, intermarry and negotiate with existing communities.",
            instrument: "Landholding, assembly, local alliance and baptism",
            reach: "Danelaw, Atlantic towns and frontier districts",
            inheritance: "New polities formed from migration and local adaptation",
          },
        ],
      },
    },
    {
      id: "imperial-claim-moves-east",
      actId: "imperial-inheritance",
      order: 11,
      period: "AD 936–973",
      place: "Saxony · Aachen · Rome · Magdeburg",
      title: "The Imperial Claim Moves East",
      thesis:
        "Otto I built a western empire from Saxon power, episcopal partnership and victory on a frontier once conquered by the Franks.",
      body: [
        "Otto was crowned king at Aachen in 936, using Charlemagne’s palace to claim succession while drawing strength from Saxony. Rebellions within the royal family and pressure from Magyar armies tested his rule. Victory at the Lechfeld in 955 elevated his authority. In 962 Pope John XII crowned him emperor in Rome, giving a Saxon dynasty the title created for a Frankish ruler.",
        "Ottonian government relied on travel, assemblies, royal lands and bishops who served as hosts, advisers and regional officeholders. Otto founded Magdeburg as an archbishopric for missions and rule toward Slavic lands. Marriage between his son and the Byzantine princess Theophanu brought objects, people and ceremonial knowledge from Constantinople. Competing imperial claims became a channel of diplomacy and imitation across Christian Europe.",
        "Bishops were useful because their churches possessed estates, clerks and durable office. Royal influence over appointments could place trusted men in strategic sees, although cathedral communities and aristocratic interests constrained every choice. The arrangement supplied government without a salaried bureaucracy. It also planted the conflict over investiture that the next chapter will bring into the open.",
      ],
      image: `${imageRoot}/11-imperial-claim-east.avif`,
      imageAlt:
        "Otto I receives envoys in a tenth-century Saxon palace church complex where a sealed document and Byzantine silk mark diplomatic connection.",
      imagePosition: "61% center",
      visualTone: "saxon-porphyry",
      side: "left",
      sourceIds: ["reuter-1991", "widukind-saxon-deeds"],
      evidence: [
        "Widukind of Corvey, charters and royal itineraries show Ottonian kingship operating through Saxon resources, assemblies and bishops.",
        "The imperial coronation, Magdeburg’s foundation and the Byzantine marriage connect frontier expansion to Roman Christian claims.",
      ],
      map: { x: 50, y: 48 },
    },
    {
      id: "rulers-choose-christian-future",
      actId: "widening-commonwealth",
      order: 12,
      period: "AD 845–1000",
      place: "Bohemia · Poland · Hungary",
      title: "Rulers Choose a Christian Future",
      thesis:
        "Baptism gave new dynasties access to priests, marriages and recognised institutions while conversion remained a contested social process.",
      body: [
        "Bohemian, Polish and Hungarian rulers entered Latin Christian networks through different sequences. Bořivoj’s baptism connected the Přemyslid court to Moravia; Mieszko’s baptism in 966 strengthened relations with Christian neighbours and supported a bishopric; Stephen’s kingship around 1000 joined baptism, royal organisation and Latin ecclesiastical structures in Hungary. Each decision emerged from local rivalry and external diplomacy.",
        "A ruler’s choice could redirect burial, marriage, tribute and the training of clerks. It could also provoke resistance, because temples, ritual specialists and customary authority were embedded in communities. Churches required land, personnel and successors before they could reach beyond court. Christian monarchy formed through repeated patronage and negotiation. Conversion placed a polity inside a wider language of legitimate rule while leaving its people, law and political centre distinct.",
        "Foreign missionaries never worked on empty ground. They entered societies with assemblies, sacred places, exchange routes and ranked households. A successful dynasty used Christian resources to reorganise those relationships and depended on local elites to make the changes credible. The resulting monarchies resembled their neighbours through church office and differed through inherited political practice.",
      ],
      image: `${imageRoot}/12-rulers-choose-future.avif`,
      imageAlt:
        "A central European ruler, spouse, cleric and local elites gather beside a timber church foundation, baptismal basin and building plan.",
      imagePosition: "43% center",
      visualTone: "timber-and-font",
      side: "right",
      sourceIds: ["berend-2007", "reuter-1991"],
      evidence: [
        "Narrative sources, burials, church foundations and diplomatic evidence place ruler-sponsored baptism within competitive polity formation.",
        "Regional variation in parish growth and recurring resistance show that court conversion preceded wider Christian practice.",
      ],
      map: { x: 57, y: 53 },
    },
    {
      id: "two-christian-roads-reach-north",
      actId: "widening-commonwealth",
      order: 13,
      period: "AD 863–988",
      place: "Moravia · Bulgaria · Preslav · Kyiv",
      title: "Two Christian Roads Reach North",
      thesis:
        "Latin and Byzantine missions carried related faiths through different languages, alphabets and political alliances before a formal schism divided their churches.",
      body: [
        "Cyril and Methodius came from Constantinople to Moravia in 863, translating worship and scripture into Slavonic and training disciples. Conflict over jurisdiction and liturgical language drew Rome, Frankish clergy and Byzantine tradition into the mission. After Methodius’s death, expelled disciples found patronage in Bulgaria. Literary centres associated with Preslav and Ohrid developed a Slavic Christian culture using Glagolitic and, soon, Cyrillic writing.",
        "In 988 Volodymyr of Kyiv accepted baptism and Byzantine Christianity within a political relationship with Emperor Basil II. The Primary Chronicle’s later account gives the event a dramatic theological choice; contemporary diplomacy and archaeology reveal a longer Christian presence and gradual institutional growth. Latin and Byzantine roads belonged to one connected Christian field. Their differences in authority, language and rite created durable orientations without making the separation of 1054 an accomplished fact in the tenth century.",
        "These routes also crossed. Methodius appealed to Rome; Latin missionaries worked among Slavic speakers; dynastic marriages connected Kyiv, Poland, Scandinavia and western courts. Greek texts entered Slavonic translation, and western clergy encountered Byzantine practice. The two-road model clarifies institutional orientation only when the many bridges between them remain visible.",
      ],
      image: `${imageRoot}/13-two-christian-roads.avif`,
      imageAlt:
        "Byzantine-trained clergy and Slavic scribes prepare liturgical books as river travellers arrive at a tenth-century eastern European court.",
      imagePosition: "60% center",
      visualTone: "slavonic-ink",
      side: "left",
      sourceIds: ["berend-2007", "franklin-shepard-1996", "primary-chronicle"],
      evidence: [
        "Papal letters, saints’ lives and manuscript traditions document the Moravian mission and the movement of disciples into Bulgaria.",
        "The Primary Chronicle is a later narrative source; treaties, coins, burials and church archaeology extend the evidence for Rus’ conversion.",
      ],
      map: { x: 66, y: 51 },
      interaction: {
        kind: "conversion-roads",
        prompt: "Compare two roads into Christian Europe",
        accessibleSummary:
          "Four paths compare Latin, Moravian-Bulgarian, Kyivan and shared Christian institutions before the eleventh-century schism.",
        paths: [
          {
            id: "latin",
            label: "Latin courts",
            period: "ninth–tenth centuries",
            detail:
              "Roman liturgy and Latin writing travel through bishops tied to western rulers and the papacy.",
            patron: "Kings, dukes, bishops and monasteries",
            language: "Latin in liturgy, law and learned correspondence",
            institution: "Diocese linked through metropolitan and papal relations",
            limit: "Local practice and political control vary sharply",
          },
          {
            id: "slavonic",
            label: "Slavonic books",
            period: "from 863",
            detail:
              "Translation gives Slavic-speaking communities a literary Christian language with Byzantine roots.",
            patron: "Moravian invitation, then Bulgarian royal protection",
            language: "Old Church Slavonic in Glagolitic and Cyrillic traditions",
            institution: "Schools, monasteries and episcopal missions",
            limit: "Jurisdiction and acceptable liturgical language remain contested",
          },
          {
            id: "kyiv",
            label: "Kyivan alliance",
            period: "988",
            detail:
              "Baptism binds Volodymyr’s dynasty to Constantinople and supports a metropolitan church.",
            patron: "Prince, imperial alliance and Byzantine clergy",
            language: "Slavonic worship with Greek models and personnel",
            institution: "Court churches, metropolitan authority and new foundations",
            limit: "Christian practice spreads through a diverse and extensive polity",
          },
          {
            id: "shared",
            label: "Connected faith",
            period: "before 1054",
            detail:
              "Both roads transmit baptism, creed, scripture, episcopal succession and monastic life.",
            patron: "Intermarried dynasties and communicating churches",
            language: "Latin, Greek and Slavonic Christian literatures",
            institution: "Related rites and rival jurisdictions within one Christian world",
            limit: "Difference has not yet hardened into a complete civilisational border",
          },
        ],
      },
    },
    {
      id: "europe-meets-at-gniezno",
      actId: "widening-commonwealth",
      order: 14,
      period: "AD 1000",
      place: "Gniezno · the shrine of Adalbert",
      title: "Europe Meets at Gniezno",
      thesis:
        "Otto III and Bolesław Chrobry used pilgrimage, gifts and church organisation to recognise a Polish Christian centre without absorbing it.",
      body: [
        "Otto III travelled to the shrine of Adalbert, the missionary bishop killed in Prussia in 997. Bolesław received him at Gniezno with calculated splendour. Thietmar, writing from the Saxon frontier, describes the meeting with suspicion toward Polish power; other traditions emphasise honour and friendship. Gifts included a copy of the Holy Lance and, according to later accounts, an imperial diadem or symbolic elevation.",
        "The most durable act was institutional. Gniezno became an archbishopric with suffragan sees, reducing dependence on German ecclesiastical centres and recognising a Polish church within Latin Christendom. Otto departed without annexing Bolesław’s realm. A saint’s body, papal consent, episcopal organisation and imperial presence had made a frontier court legible to the wider commonwealth. Europe could hold a formal meeting across political borders because its institutions now reached beyond Rome’s former frontier.",
        "The meeting did not settle rank forever. Bolesław became king only in 1025, Otto died in 1002, and political relations changed under their successors. Gniezno endured as evidence that recognition could be organised through offices larger than a personal alliance. The commonwealth had acquired another centre capable of disputing the meaning of its shared forms.",
      ],
      image: `${imageRoot}/14-europe-meets-gniezno.avif`,
      mobileImage: `${imageRoot}/14-europe-meets-gniezno-mobile.avif`,
      imageAlt:
        "Otto III and Bolesław Chrobry exchange gifts beside Adalbert’s shrine as clergy and envoys witness the Gniezno meeting of 1000.",
      imagePosition: "45% center",
      mobileImagePosition: "49% center",
      visualTone: "relic-and-recognition",
      side: "right",
      sourceIds: ["thietmar-2001", "berend-2007", "reuter-1991"],
      evidence: [
        "Thietmar is a near-contemporary witness with a distinct Saxon and episcopal perspective on Bolesław and the meeting.",
        "The creation of the Gniezno archbishopric and its suffragan sees provides institutional evidence beyond ceremonial interpretation.",
      ],
      map: { x: 58, y: 47 },
      interaction: {
        kind: "commonwealth-trace",
        prompt: "Build recognition from body, gift and office",
        accessibleSummary:
          "Three stops show how a missionary shrine, reciprocal gifts and an archbishopric made a new political centre durable.",
        stops: [
          {
            id: "shrine",
            label: "Pilgrimage",
            period: "997–1000",
            detail:
              "Adalbert’s relics give Gniezno a sacred claim that draws an emperor across a frontier.",
            instrument: "Martyr’s body, shrine, liturgy and remembered mission",
            reach: "Pilgrims, clergy and rulers beyond one dynasty",
            inheritance: "A local centre with transregional sacred authority",
          },
          {
            id: "gifts",
            label: "Recognition",
            period: "March 1000",
            detail:
              "Public hospitality and exchanged objects express alliance without political merger.",
            instrument: "Procession, feast, relic, lance and ceremonial honour",
            reach: "Imperial, Polish and papal audiences",
            inheritance: "A relationship later writers could interpret and contest",
          },
          {
            id: "archbishopric",
            label: "Institution",
            period: "from 1000",
            detail:
              "A metropolitan see gives the Polish church an internal hierarchy recognised in Latin Christendom.",
            instrument: "Archbishop, suffragan bishops, papal consent and royal patronage",
            reach: "Gniezno, Kraków, Wrocław and Kołobrzeg",
            inheritance: "A church organisation able to outlive the meeting",
          },
        ],
      },
    },
  ],
};
