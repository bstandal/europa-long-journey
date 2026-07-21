import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/empire-takes-cross";

export const empireTakesCross: ChapterDefinition = {
  slug: "empire-takes-cross",
  number: "06",
  title: "The Empire Takes the Cross",
  period: "AD 312–565",
  claim:
    "Christianity entered Roman law, office and imperial ceremony while Constantinople became the centre of a renewed Christian Rome.",
  theme: {
    id: "christian",
    label: "The consecrated city",
  },
  openingAction: "Enter the consecrated city",
  mapLabel: "The victories, councils, walls and sanctuaries of Christian Rome",
  routeImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Laws · creeds · council acts · churches · walls · chronicles · legal codices · imperial histories",
  acts: [
    {
      id: "sign-and-crown",
      number: "I",
      label: "Victory and patronage",
      period: "AD 312–337",
      title: "The Sign and the Crown",
      detail:
        "Constantine wins the western empire, protects Christian worship and gives the faith an imperial architecture before founding a new capital.",
    },
    {
      id: "imperial-faith",
      number: "II",
      label: "Creed and government",
      period: "AD 314–395",
      title: "Faith Becomes Imperial Business",
      detail:
        "Emperors convene councils, bishops argue over doctrine and Nicene Christianity enters the commands and institutions of the Roman state.",
    },
    {
      id: "christian-capital",
      number: "III",
      label: "The city that remains",
      period: "AD 395–518",
      title: "The Christian Capital",
      detail:
        "Walls, churches, hospitals, ceremony and law make Constantinople the secure centre of an empire that remains Roman when western rule fragments.",
    },
    {
      id: "stone-and-law",
      number: "IV",
      label: "Restoration",
      period: "AD 527–565",
      title: "Roman Order in Stone and Law",
      detail:
        "Justinian gathers Roman law, raises Hagia Sophia and recovers lost provinces, binding restoration to extraordinary expense and endurance.",
    },
  ],
  ending: {
    period: "AD 565",
    title: "The Roman centre now faces east",
    detail:
      "Justinian left a Roman Empire whose law, capital and Christian kingship would outlive every western successor state. Its recovered shores were costly to hold, its cities had endured plague and its eastern frontier faced the organised power of Sasanian Persia. The next struggle would decide whether Constantinople could preserve the civilization gathered behind its walls.",
    image: `${imageRoot}/14-restoration-cost.avif`,
    mobileImage: `${imageRoot}/14-restoration-cost-mobile.avif`,
    nextPeriod: "AD 500–1000",
  },
  returnHash: "christian-empire",
  nextHash: "europe-reborn",
  nextTitle: "Europe Reborn",
  movements: [
    {
      id: "a-sign-before-battle",
      actId: "sign-and-crown",
      order: 1,
      period: "28 October AD 312",
      place: "The Milvian Bridge · the northern road to Rome",
      title: "A Sign Before Battle",
      thesis:
        "Constantine’s victory joined the Christian God to Roman imperial success without making the empire Christian in a single day.",
      body: [
        "Two armies meet where the Via Flaminia reaches the Tiber. Maxentius holds Rome and commands the larger political prize; Constantine has marched rapidly from Gaul through northern Italy. The battle ends with Maxentius drowned during the collapse or congestion of his river crossing. Constantine enters the city as sole ruler of the western empire, while the Senate dedicates an arch that attributes his victory to divine inspiration without naming the Christian God.",
        "Christian writers gave the victory a sharper sacred meaning. Lactantius reports that Constantine was instructed in a dream to mark a heavenly sign on his soldiers’ shields. Eusebius later describes a vision of a luminous trophy above the sun and a dream in which Christ explains it. The accounts differ in date, form and literary purpose. They establish that Constantine and his court came to remember the campaign through a Christian sign whose force lay in victory.",
        "The emperor did not abandon Roman government, the army or the ancient capital’s public forms. He added a new divine patron to imperial rule and moved decisively toward the churches that had survived persecution. Money, law, land and access followed. A faith once exposed to magistrates now possessed the favour of the man whose success decided which magistrates would govern.",
      ],
      image: `${imageRoot}/01-sign-before-battle.avif`,
      mobileImage: `${imageRoot}/01-sign-before-battle-mobile.avif`,
      imageAlt:
        "Constantine’s soldiers gather in cold dawn light beside the Tiber before the Battle of the Milvian Bridge, with a Christian military standard rising among Roman spears.",
      imagePosition: "58% center",
      mobileImagePosition: "58% center",
      visualTone: "iron-revelation",
      side: "left",
      sourceIds: ["van-dam-2011", "eusebius-life", "lactantius-persecutors", "holloway-2004"],
      evidence: [
        "The Arch of Constantine, coins, panegyrics and the two Christian narratives preserve distinct public languages for the victory of 312.",
        "Lactantius and Eusebius agree on a Christian sign while differing over the experience and its setting.",
      ],
      map: { x: 48, y: 66 },
    },
    {
      id: "persecution-ends",
      actId: "sign-and-crown",
      order: 2,
      period: "AD 303–313",
      place: "Nicomedia · Rome · Milan",
      title: "The Persecuted Church Enters Imperial Protection",
      thesis:
        "Within a decade, Christian assemblies moved from confiscation to legal restoration and direct imperial favour.",
      body: [
        "The change can be measured against the Great Persecution begun under Diocletian in 303. Imperial orders targeted church buildings, scriptures, officeholders and the legal standing of Christians. Enforcement varied sharply by province and ruler, and resistance produced both martyrdom and disputes over those who surrendered books or cooperated. Galerius ended the policy in 311 with an edict permitting Christians to assemble and asking their prayers for the state.",
        "After Constantine and Licinius met at Milan in 313, letters issued in their names ordered unrestricted worship and the return of confiscated Christian property. No surviving tablet bears the title “Edict of Milan”; Lactantius and Eusebius preserve versions of the policy. Its practical force was unmistakable. Governors had to restore buildings and land even when private buyers had acquired them, and the treasury could compensate those who suffered loss.",
        "Constantine went further in his own territories. Clergy received privileges; episcopal judgments gained recognised force in certain disputes; imperial gifts helped Christian communities build on an unprecedented scale. Policy still moved through existing Roman instruments—rescripts, governors, fiscal exemptions and property law. Christianity did not stand outside the empire and conquer it from a distance. The emperor opened the administrative doors and brought the church through them.",
      ],
      image: `${imageRoot}/02-persecution-ends.avif`,
      imageAlt:
        "Christian clergy receive restored books and keys to a meeting house from a Roman official while a scorched persecution notice hangs nearby.",
      imagePosition: "52% center",
      visualTone: "wax-and-ash",
      side: "right",
      sourceIds: ["lactantius-persecutors", "eusebius-life", "van-dam-2011", "edwards-2015"],
      evidence: [
        "The texts preserved by Lactantius and Eusebius order freedom of worship and restitution of corporate Christian property.",
        "Constantinian laws and letters document exemptions, grants and the new public position of bishops.",
      ],
      map: { x: 58, y: 63 },
      interaction: {
        kind: "christian-policy",
        prompt: "Move the church through four imperial positions",
        accessibleSummary:
          "Four states show Christian communities passing from coercion to toleration, conciliar patronage and an enforced Nicene settlement.",
        states: [
          {
            id: "persecution-303",
            label: "Persecute",
            period: "303",
            detail:
              "Diocletianic orders attack buildings, books, officeholders and legal standing, with enforcement varying across the empire.",
            imperialAction: "Confiscate, exclude and compel sacrifice",
            churchPosition: "A prohibited body exposed to provincial enforcement",
            publicSign: "Demolished meeting places and surrendered scriptures",
          },
          {
            id: "toleration-313",
            label: "Restore",
            period: "313",
            detail:
              "Constantine and Licinius command free worship and the return of confiscated corporate property.",
            imperialAction: "Issue letters through governors and the fiscal administration",
            churchPosition: "A lawful corporation able to hold and recover property",
            publicSign: "Keys, land and buildings returned at public expense",
          },
          {
            id: "council-325",
            label: "Convene",
            period: "325",
            detail:
              "Constantine gathers bishops at Nicaea and supplies an imperial setting for a common doctrinal judgment.",
            imperialAction: "Summon, transport, preside ceremonially and enforce exile",
            churchPosition: "A protected institution asked to speak for the whole empire",
            publicSign: "A creed carried from an imperial council",
          },
          {
            id: "confession-380",
            label: "Confess",
            period: "380–381",
            detail:
              "Theodosius I identifies Nicene Christianity with legitimate imperial religion and supports the council at Constantinople.",
            imperialAction: "Define authorised confession and control public churches",
            churchPosition: "The favoured religious order of the Roman state",
            publicSign: "Nicene bishops occupying the principal urban sees",
          },
        ],
      },
    },
    {
      id: "the-emperor-builds",
      actId: "sign-and-crown",
      order: 3,
      period: "AD 313–337",
      place: "Rome · Jerusalem · imperial estates",
      title: "The Emperor Builds for the Christian God",
      thesis:
        "Imperial patronage gave Christian worship a monumental scale equal to its new public position.",
      body: [
        "Construction made policy visible. On land associated with the Lateran family, a vast basilica rose for the bishop of Rome. Its long nave, columned aisles and apse borrowed the spatial authority of Roman public halls while turning the interior toward Christian assembly, scripture and altar. The emperor’s gifts included precious fittings and landed revenues required to maintain clergy, lamps and ritual.",
        "At the Vatican necropolis, another basilica honoured the burial place Christians associated with Peter. In Jerusalem, Constantine’s patronage cleared the site identified with Christ’s crucifixion and tomb and raised the complex later known as the Holy Sepulchre. These projects bound distant places to one imperial sacred geography: the capital of the old empire, the grave of an apostle and the places of the Gospel.",
        "The buildings did not erase older cults across the empire. Temples, household rites, traditional priesthoods and philosophical schools remained active. The new scale altered the balance of attention and resources. Bishops could gather crowds beneath roofs financed by the ruler; pilgrims could move through monumental sites authenticated by imperial work; Christian memory could inhabit stone intended to last beyond any sermon.",
      ],
      image: `${imageRoot}/03-emperor-builds.avif`,
      imageAlt:
        "Workers and clergy raise the timber roof and colonnades of a Constantinian Christian basilica while imperial officials inspect plans.",
      imagePosition: "61% center",
      visualTone: "basilica-dust",
      side: "left",
      sourceIds: ["holloway-2004", "eusebius-life", "edwards-2015"],
      evidence: [
        "Archaeology, inscriptions and the Liber Pontificalis preserve the exceptional scale and endowment of Constantinian church building.",
        "Eusebius records the emperor’s letters and the Jerusalem building programme from a contemporary Christian perspective.",
      ],
      map: { x: 48, y: 66 },
      interaction: {
        kind: "christian-trace",
        prompt: "Follow imperial patronage into stone",
        accessibleSummary:
          "Three sites show how land, architecture and endowment gave Christian memory a permanent public setting.",
        stops: [
          {
            id: "lateran",
            label: "Assemble",
            period: "c. 313–324",
            detail:
              "The Lateran basilica gives Rome’s bishop a monumental hall for worship and public gathering.",
            instrument: "Imperial land, basilican scale and a funded clerical establishment",
            inheritance: "The cathedral church becomes an institution of the Christian city",
          },
          {
            id: "vatican",
            label: "Remember",
            period: "c. 319–333",
            detail:
              "A great cemetery basilica fixes apostolic memory above the site associated with Peter’s grave.",
            instrument: "A difficult platform built across the Vatican necropolis",
            inheritance: "A local martyr’s shrine becomes an imperial destination",
          },
          {
            id: "jerusalem",
            label: "Pilgrimage",
            period: "c. 325–335",
            detail:
              "The Holy Sepulchre complex monumentalises the places identified with crucifixion and resurrection.",
            instrument: "Excavation, imperial letters, architects and provincial finance",
            inheritance: "Sacred history acquires a connected monumental geography",
          },
        ],
      },
    },
    {
      id: "new-rome-rises",
      actId: "sign-and-crown",
      order: 4,
      period: "AD 324–330",
      place: "Byzantion · the Bosporus",
      title: "A New Rome Rises on the Bosporus",
      thesis:
        "Constantine placed the imperial centre where Europe and Asia, the Black Sea and the Mediterranean could be governed together.",
      body: [
        "After defeating Licinius in 324, Constantine selected ancient Byzantion for an enlarged imperial city. The site occupied a defensible peninsula between the Golden Horn and the Sea of Marmara and watched the narrow Bosporus passage. Roads led west into Thrace; shipping connected the Aegean, Black Sea grain lands and eastern provinces. Geography gave the court an eastern reach without removing it from Europe.",
        "Surveyors extended the walls, engineers supplied water, and builders laid out forums, baths, palaces and a ceremonial avenue. Statues and columns arrived from older cities, carrying the accumulated authority of the Roman world into new settings. The Hippodrome joined palace and people through spectacle. The city was dedicated on 11 May 330 with ceremonies that could be read through both traditional and Christian expectations.",
        "Constantinople was not finished at dedication. Its population, harbours, aqueducts, churches and administrative weight grew across generations. The foundation nevertheless changed the empire’s axis. Rome remained an incomparable symbolic city; Constantinople possessed the living emperor, the senior court and a planned capacity for expansion. The Roman state had created a capital capable of surviving the loss of provinces its founder never expected to lose.",
      ],
      image: `${imageRoot}/04-new-rome-rises.avif`,
      imageAlt:
        "Constantine’s new capital rises above the Bosporus with scaffolded forums, palace roofs, harbour works and the Hippodrome.",
      imagePosition: "57% center",
      visualTone: "porphyry-foundation",
      side: "right",
      sourceIds: ["kaldellis-2023", "grig-kelly-2012", "rutgers-constantinople-2025", "eusebius-life"],
      evidence: [
        "Dedication traditions, monuments, water systems and successive wall lines document a foundation in 324–330 followed by long urban growth.",
        "Administrative evidence and court ceremony show Constantinople’s rising centrality without making Rome immediately irrelevant.",
      ],
      map: { x: 58, y: 64 },
    },
    {
      id: "an-emperor-calls-a-council",
      actId: "imperial-faith",
      order: 5,
      period: "AD 325",
      place: "Nicaea · Bithynia",
      title: "An Emperor Calls the Bishops Together",
      thesis:
        "Nicaea joined episcopal argument to imperial convening power and made a common creed an affair of the Roman world.",
      body: [
        "Dispute over the teaching of Arius, a presbyter of Alexandria, had already spread through letters, synods and rival slogans. At stake was how Christians should speak of the relation between the Father and the Son. Constantine wanted concord in the church whose God he credited with imperial victory. He summoned bishops to Nicaea, provided travel and hospitality, entered ceremonially and urged agreement.",
        "The bishops did the doctrinal work. Their creed declared the Son to be from the substance of the Father and used the contested term *homoousios*, “of one substance.” They also issued canons on discipline and jurisdiction and attempted to coordinate the date of Easter. Constantine supported the settlement with letters and exile. Imperial power could gather the council and enforce its immediate judgment; it could not make every bishop, theologian or successor emperor understand the formula in the same way.",
        "Nicaea became authoritative through a century of conflict, reinterpretation and reception, not because argument stopped in 325. The council established a durable pattern. A Roman emperor could call bishops from many provinces into one hall, while bishops could claim that their common confession bound the Christian people more deeply than a temporary court faction.",
      ],
      image: `${imageRoot}/05-nicaea-council.avif`,
      mobileImage: `${imageRoot}/05-nicaea-council-mobile.avif`,
      imageAlt:
        "Bishops debate across a long council hall at Nicaea while Constantine listens from a low imperial seat beneath smoking lamps.",
      imagePosition: "50% center",
      mobileImagePosition: "47% center",
      visualTone: "council-indigo",
      side: "left",
      sourceIds: ["demacopoulos-2025", "edwards-2015", "eusebius-life", "chadwick-2001"],
      evidence: [
        "The Nicene creed, canons, conciliar letters and Eusebius’s account preserve the council’s decisions and imperial setting.",
        "Subsequent councils and correspondence document prolonged disagreement over Nicene language and authority.",
      ],
      map: { x: 59, y: 64 },
      interaction: {
        kind: "christian-council",
        prompt: "Pass a creed from summons to inheritance",
        accessibleSummary:
          "Four stations separate the emperor’s convening authority, episcopal debate, the conciliar formula and its contested reception.",
        states: [
          {
            id: "summons",
            label: "Summon",
            period: "spring 325",
            detail:
              "Constantine uses the communication and transport of the empire to gather bishops in Bithynia.",
            authority: "The emperor selects the occasion and supplies the meeting",
            act: "Letters, travel orders, lodging and ceremonial presidency",
            consequence: "A local dispute appears before an empire-wide assembly",
          },
          {
            id: "debate",
            label: "Debate",
            period: "June 325",
            detail:
              "Bishops test scriptural and philosophical language for the relation of Father and Son.",
            authority: "Episcopal teaching and collective judgment",
            act: "Argument, drafting, amendment and signatures",
            consequence: "The assembly distinguishes accepted confession from condemned teaching",
          },
          {
            id: "creed",
            label: "Define",
            period: "325",
            detail:
              "The creed calls the Son true God and of one substance with the Father.",
            authority: "A subscribed conciliar text backed by imperial enforcement",
            act: "Creed, anathemas, canons and letters",
            consequence: "Christian unity receives exact public words",
          },
          {
            id: "reception",
            label: "Receive",
            period: "325–381",
            detail:
              "Churches and emperors contest, refine and eventually establish Nicaea as the measure of orthodoxy.",
            authority: "Successive councils, bishops, rulers and local churches",
            act: "Exile, restoration, rival formulas and renewed councils",
            consequence: "Authority grows through reception rather than one day’s decree",
          },
        ],
      },
    },
    {
      id: "the-creed-survives-emperors",
      actId: "imperial-faith",
      order: 6,
      period: "AD 337–381",
      place: "Constantinople · Antioch · Alexandria · the imperial roads",
      title: "The Creed Survives Its Emperors",
      thesis:
        "The fourth-century struggle proved that imperial support could direct church conflict without owning the faith it tried to settle.",
      body: [
        "Constantine’s sons inherited both the empire and its doctrinal dispute. Councils met at Antioch, Sardica, Sirmium, Rimini, Seleucia and Constantinople. Bishops were exiled and recalled as courts changed. Formulas avoided, redefined or rejected Nicene language. The geography of imperial residence mattered: access to a ruler, a chamberlain or a trusted bishop could reshape which confession held the principal churches.",
        "Constantius II promoted settlements hostile to the Nicene formula, while defenders such as Athanasius of Alexandria represented their repeated expulsions as a struggle for apostolic truth against court pressure. Julian’s short reign restored traditional cult and allowed exiled bishops home, partly exposing Christian divisions. Valens supported a non-Nicene hierarchy in the east. No single line from palace to parish controlled this moving argument.",
        "The long contest hardened the church’s own memory, correspondence and standards of legitimate council. Bishops learned to appeal from one imperial hearing to earlier texts, distant colleagues and the faith received at baptism. The empire supplied roads, halls, coercion and the ambition of universality. The creed acquired durability when Christian institutions learned to outlast the preference of a particular emperor.",
      ],
      image: `${imageRoot}/06-creed-survives.avif`,
      imageAlt:
        "Messengers carry rival creeds through a rain-dark Roman way station while an exiled bishop departs under military guard.",
      imagePosition: "60% center",
      visualTone: "rain-and-wax",
      side: "right",
      sourceIds: ["chadwick-2001", "edwards-2015", "smith-nicaea-2018"],
      evidence: [
        "Conciliar creeds, episcopal letters and imperial exile orders reveal rapid changes in official settlement after 325.",
        "The council of Constantinople in 381 and later reception established a Nicene settlement after decades of rivalry.",
      ],
      map: { x: 57, y: 62 },
      interaction: {
        kind: "christian-trace",
        prompt: "Watch authority change hands",
        accessibleSummary:
          "Three moments show court formula, episcopal resistance and conciliar reception turning Nicaea into an inherited standard.",
        stops: [
          {
            id: "court",
            label: "Court",
            period: "337–361",
            detail:
              "Constantius II sponsors councils and formulas intended to produce agreement without Nicene language.",
            instrument: "Imperial summons, preferred bishops, deposition and exile",
            inheritance: "Court power proves able to dominate a season, not the whole memory of the church",
          },
          {
            id: "resistance",
            label: "Resistance",
            period: "340s–370s",
            detail:
              "Exiled bishops build alliances through letters, theology and claims of fidelity to earlier judgment.",
            instrument: "Correspondence, local loyalty and appeal to Nicaea",
            inheritance: "A creed becomes a standard against which rulers can be judged",
          },
          {
            id: "reception-381",
            label: "Reception",
            period: "381",
            detail:
              "The council at Constantinople confirms the Nicene direction within Theodosius’s eastern settlement.",
            instrument: "Council, imperial backing and occupation of principal sees",
            inheritance: "Nicaea becomes the name of an orthodox inheritance",
          },
        ],
      },
    },
    {
      id: "the-state-confesses",
      actId: "imperial-faith",
      order: 7,
      period: "AD 380–395",
      place: "Thessalonica · Constantinople · the Roman provinces",
      title: "The State Confesses",
      thesis:
        "Under Theodosius I, Nicene Christianity became the authorised confession of imperial government.",
      body: [
        "The edict *Cunctos populos*, issued at Thessalonica in 380, instructed the peoples ruled by Theodosius, Gratian and Valentinian II to follow the faith associated with the bishops of Rome and Alexandria. The council at Constantinople in 381 confirmed a Nicene theological settlement in the east and reordered important sees. The emperor placed Nicene bishops in possession of principal churches and treated rival assemblies as unauthorised.",
        "Christianization advanced through officials as well as prohibitions. Magistrates heard episcopal petitions; governors enforced ownership decisions; laws entered the Theodosian Code; court ceremony acquired Christian prayers, processions and sacred language. Traditional sacrifice and temple finance faced mounting restriction, especially in the 390s. Enforcement depended on province, officeholder and local balance, which made the transformation uneven without making it unreal.",
        "The Roman state now confessed a religion whose institutions crossed every provincial boundary. The emperor remained a ruler inside a constitutional and ceremonial inheritance older than Christianity. Bishops gained a language for admonishing him as a Christian sovereign responsible before God. That relationship could produce cooperation, confrontation and public penance. Imperial majesty had taken the cross; the cross also supplied a judgment above the man wearing the diadem.",
      ],
      image: `${imageRoot}/07-state-confesses.avif`,
      imageAlt:
        "Theodosius and Roman officials enter a Constantinopolitan church as a Nicene bishop receives the imperial law beneath lamps and porphyry columns.",
      imagePosition: "54% center",
      visualTone: "law-and-incense",
      side: "left",
      sourceIds: ["codex-theodosianus", "whelan-2026", "chadwick-2001", "kaldellis-2023"],
      evidence: [
        "The Theodosian Code preserves laws defining authorised religion, clerical privilege, heresy and restrictions on sacrifice.",
        "Council records and episcopal correspondence show how imperial decisions were translated into control of churches and sees.",
      ],
      map: { x: 58, y: 64 },
    },
    {
      id: "the-city-grows-behind-walls",
      actId: "christian-capital",
      order: 8,
      period: "AD 395–450",
      place: "Constantinople · the Golden Horn · the Theodosian walls",
      title: "The City Grows Behind New Walls",
      thesis:
        "Constantinople expanded from Constantine’s foundation into a fortified capital large enough to contain the Roman state.",
      body: [
        "The city soon outgrew Constantine’s wall. Under Theodosius II, a new land barrier crossed the peninsula roughly six kilometres west of the old line, conventionally dated to 413 and strengthened after earthquake damage in 447. Its deep ditch, lower outer wall and high inner wall created successive obstacles commanded by towers. Sea walls completed protection around the inhabited peninsula.",
        "Inside stood the court, Senate, law schools, workshops, cisterns, baths, harbours and churches required by an imperial capital. Grain arrived under public supervision. Aqueducts reached across Thrace; covered reservoirs stored water against siege and summer. The Hippodrome gave the people a place to acclaim the ruler, demand the dismissal of officials and identify through racing factions. Ceremony joined palace, cathedral and public street.",
        "The walls did more than defend a population. They enclosed archives, treasury, relics, diplomatic ritual and the men trained to reproduce Roman government. Armies could lose provinces while the administrative centre endured. In the fifth century, as western courts moved and western armies elevated their own masters, Constantinople acquired the physical depth to remain the unquestioned capital of the Roman east.",
      ],
      image: `${imageRoot}/08-city-behind-walls.avif`,
      mobileImage: `${imageRoot}/08-city-behind-walls-mobile.avif`,
      imageAlt:
        "The Theodosian walls rise in layered stone and brick above Constantinople as aqueducts, domes, harbours and crowded streets fill the peninsula.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualTone: "wall-and-indigo",
      side: "right",
      sourceIds: ["rutgers-constantinople-2025", "grig-kelly-2012", "kaldellis-space-2019", "kaldellis-2023"],
      evidence: [
        "Surviving wall fabric, inscriptions, waterworks and urban archaeology document the fifth-century expansion.",
        "Legal and ceremonial sources identify Constantinople’s Senate, grain supply, court offices and Hippodrome politics.",
      ],
      map: { x: 58, y: 64 },
      interaction: {
        kind: "christian-city",
        prompt: "Build the capital that can remain",
        accessibleSummary:
          "Four urban states show the foundation, dedication, Theodosian expansion and mature Christian capital.",
        mapImage: `${imageRoot}/constantinople-plan.avif`,
        states: [
          {
            id: "foundation-324",
            label: "Set the line",
            period: "324",
            detail:
              "Constantine enlarges Byzantion and marks a capital between the Golden Horn and the Sea of Marmara.",
            reach: "A defensible European peninsula commanding the Bosporus",
            institution: "Palace, forum, Hippodrome and the first expanded wall",
            inheritance: "A new residence enters the family of Roman capitals",
          },
          {
            id: "dedication-330",
            label: "Dedicate",
            period: "330",
            detail:
              "Ceremony, monuments and privileges announce Constantinople as Constantine’s imperial city.",
            reach: "Court routes connect the Balkans, Aegean, Black Sea and Anatolia",
            institution: "Senate, public distributions and ceremonial avenue",
            inheritance: "The city carries old Roman forms into an eastern centre",
          },
          {
            id: "wall-413",
            label: "Enclose",
            period: "c. 413–447",
            detail:
              "The Theodosian line multiplies the city’s area and creates the strongest land defence in the Mediterranean world.",
            reach: "A broad inhabited peninsula protected in depth",
            institution: "Ditch, outer wall, inner wall, towers and guarded gates",
            inheritance: "Government gains a fortress able to survive failed frontiers",
          },
          {
            id: "capital-450",
            label: "Govern",
            period: "c. 450",
            detail:
              "Court, cathedral, schools, harbours and administration form a self-reproducing Roman centre.",
            reach: "Orders, bishops, taxes and diplomacy move across the eastern provinces",
            institution: "Archives, treasury, law teaching, cisterns and public grain",
            inheritance: "The Roman state can lose the west without losing its capital",
          },
        ],
      },
    },
    {
      id: "the-bishop-enters-the-city",
      actId: "christian-capital",
      order: 9,
      period: "fourth–fifth centuries",
      place: "The cities of the Roman Empire",
      title: "The Bishop Enters the Life of the City",
      thesis:
        "Christian institutions learned to carry civic memory, organised charity and public authority through an age of political strain.",
      body: [
        "A bishop preached, judged disputes, petitioned governors, managed property and represented his city before powerful outsiders. His authority grew from election or acclamation, ordination, patronage, learning and the ability to mobilise a congregation. Councils linked each see to wider provinces. Cathedral clergy and archives gave the office continuity after an individual bishop died.",
        "Christian giving created durable institutions. Hostels received travellers and pilgrims; hospitals gathered forms of care previously dispersed among households, temples, military facilities and private physicians; distributions fed the poor; monasteries organised disciplined communities of work and prayer. Wealthy patrons converted estates and houses into endowments whose legal protection drew church and state into repeated negotiation.",
        "The bishop did not replace the city council everywhere or at once. He became one of the people through whom a city could act when older municipal office grew harder to finance and imperial demands remained heavy. Processions carried relics through streets, feast days ordered time, and preaching interpreted invasion, earthquake and victory. The Christian city emerged from this union of Roman administration, local loyalty and sacred institution.",
      ],
      image: `${imageRoot}/09-bishop-enters-city.avif`,
      imageAlt:
        "A late Roman bishop crosses a city square between a hospital, a bread distribution and the governor’s portico as citizens bring petitions.",
      imagePosition: "62% center",
      visualTone: "civic-lamplight",
      side: "left",
      sourceIds: ["whelan-2026", "chadwick-2001", "kaldellis-2023"],
      evidence: [
        "Sermons, letters, laws and foundation records document episcopal mediation, charitable property and urban institutions.",
        "The uneven survival of councils and civic offices warns against treating the bishop as a uniform replacement for Roman government.",
      ],
      map: { x: 55, y: 61 },
      interaction: {
        kind: "christian-trace",
        prompt: "See the church acquire civic weight",
        accessibleSummary:
          "Three institutions show how judgment, endowment and public ritual made the church part of urban government.",
        stops: [
          {
            id: "judgment",
            label: "Judge",
            period: "fourth century",
            detail:
              "Litigants seek episcopal arbitration while bishops petition magistrates and governors.",
            instrument: "Recognised hearing, letters, reputation and access to officials",
            inheritance: "Moral office becomes practical civic mediation",
          },
          {
            id: "endowment",
            label: "Endow",
            period: "fourth–fifth centuries",
            detail:
              "Land and gifts support food, lodging, medical care, clergy and monastic communities.",
            instrument: "Protected corporate property and permanent revenues",
            inheritance: "Charity survives the patron who founded it",
          },
          {
            id: "procession",
            label: "Process",
            period: "fifth century",
            detail:
              "Relics, hymns and clergy carry sacred memory through streets shared with court and market.",
            instrument: "Calendar, route, crowd and public prayer",
            inheritance: "The physical city becomes a Christian ceremonial landscape",
          },
        ],
      },
    },
    {
      id: "chalcedon-defines",
      actId: "christian-capital",
      order: 10,
      period: "AD 451",
      place: "Chalcedon · across the Bosporus from Constantinople",
      title: "A Council Defines the Incarnate God",
      thesis:
        "Chalcedon gave imperial Christianity an exact Christological settlement whose authority was purchased with enduring division.",
      body: [
        "More than five hundred bishops and representatives assembled at Chalcedon under close imperial supervision. Officials read documents aloud, controlled procedure and demanded a settlement acceptable to Emperor Marcian and Empress Pulcheria. The council received earlier creeds and letters before defining Christ as one and the same Son acknowledged in two natures, without confusion, change, division or separation.",
        "The definition drew together the language of Rome, Constantinople and influential eastern theologians while condemning rival judgments. Its canons also addressed discipline and ecclesiastical rank. Canon 28 tied Constantinople’s privileges to its status as New Rome, placing the capital immediately after Old Rome in honour. Papal representatives opposed that canon even while Rome received the doctrinal definition.",
        "Reception divided Christian lands. Strong communities in Egypt, Syria and Armenia rejected Chalcedon’s formula or the authority claimed for it, while emperors alternated between enforcement and attempted compromise. The fracture weakened neither side’s conviction. Chalcedon endured as a foundation for the churches of Constantinople and Rome and as a wound inside an empire that understood religious concord as part of public order.",
      ],
      image: `${imageRoot}/10-chalcedon-defines.avif`,
      imageAlt:
        "Roman officials and hundreds of bishops hear the Christological definition read aloud in the church at Chalcedon.",
      imagePosition: "50% center",
      visualTone: "ink-and-purple",
      side: "right",
      sourceIds: ["chalcedon-acts-2022", "smith-nicaea-2018", "kaldellis-2023"],
      evidence: [
        "The surviving Acts preserve sessions, acclamations, documentary readings, the definition and canons in exceptional detail.",
        "Imperial laws and later church histories record both enforcement and sustained anti-Chalcedonian resistance.",
      ],
      map: { x: 58, y: 64 },
    },
    {
      id: "rome-remains-in-east",
      actId: "christian-capital",
      order: 11,
      period: "AD 476",
      place: "Ravenna · Constantinople",
      title: "The Western Throne Empties. Rome Remains.",
      thesis:
        "The removal of the last western emperor ended one imperial office, not the Roman Empire.",
      body: [
        "In 476 the commander Odoacer deposed the young Romulus Augustulus at Ravenna. A delegation sent imperial insignia to Constantinople and argued that one emperor was sufficient. The displaced western court had already lost effective control of Britain, much of Gaul, Spain and North Africa. Military kingdoms governed those lands through mixtures of Roman law, taxation, aristocratic property, Christian office and armed followings.",
        "Emperor Zeno remained the recognised Roman emperor. His government appointed consuls, issued law, negotiated with western rulers and claimed authority over territories it could not directly command. Odoacer and later Theoderic ruled Italy while acknowledging Constantinopolitan legitimacy in carefully managed forms. Coins, offices and legal language show accommodation rather than an announced “fall of Rome” experienced on one date.",
        "The centre of Roman power now stood without a western colleague. Constantinople possessed the court, bureaucracy, army commands, tax system and Christian imperial theology required to act as Rome. Its inhabitants called themselves Romans; their emperors ruled the Roman state. Later historians would need a new label for this long eastern history. The people living it did not believe that Rome had ended.",
      ],
      image: `${imageRoot}/11-rome-remains-east.avif`,
      imageAlt:
        "Western imperial standards are carried into a lamplit hall at Constantinople while the Roman emperor and officials continue their work.",
      imagePosition: "60% center",
      visualTone: "empty-throne",
      side: "left",
      sourceIds: ["kaldellis-2023", "whelan-2026", "grig-kelly-2012"],
      evidence: [
        "Diplomatic accounts, laws, coins and offices show continuing eastern imperial authority after the deposition in Ravenna.",
        "Roman self-identification remained the ordinary political name of the eastern empire through the Middle Ages.",
      ],
      map: { x: 58, y: 64 },
    },
    {
      id: "law-gathered-again",
      actId: "stone-and-law",
      order: 12,
      period: "AD 528–534",
      place: "The imperial palace · Constantinople",
      title: "Roman Law Is Gathered Again",
      thesis:
        "Justinian transformed centuries of imperial decisions and juristic argument into an ordered inheritance for government and study.",
      body: [
        "Roman law had accumulated through statutes, praetorian practice, juristic interpretation and imperial constitutions. Contradictions, obsolete rulings and inaccessible books made that inheritance difficult to command. In 528 Justinian appointed a commission to produce an authoritative code of imperial law. The first Codex appeared in 529; a revised version followed in 534.",
        "The larger project moved faster still. Tribonian and his colleagues extracted and arranged writings of classical jurists into the Digest, issued in 533. The Institutes provided a teaching text with legal force. Later legislation, known as the Novels, continued the work in Latin and increasingly Greek. The compilation did not preserve every Roman argument. Selection, interpolation and imperial decision made a usable order from a vast archive.",
        "These books armed judges and officials in Justinian’s empire. Their longer life was even greater. Medieval scholars in western Europe later recovered the Digest and built disciplined legal teaching around the collection. Civil-law traditions would inherit categories of property, obligation, inheritance and procedure through a sixth-century act of Roman conservation.",
      ],
      image: `${imageRoot}/12-law-gathered.avif`,
      imageAlt:
        "Tribonian’s legal commission works among wax tablets, papyrus rolls and bound codices beneath a porphyry imperial portrait.",
      imagePosition: "53% center",
      visualTone: "codex-gold",
      side: "right",
      sourceIds: ["corpus-iuris", "maas-2005", "kaldellis-2023"],
      evidence: [
        "The Codex, Digest, Institutes and Novels survive as the direct products of Justinian’s commissions.",
        "Constitutions prefacing the works explain their authority, method, teaching purpose and publication dates.",
      ],
      map: { x: 58, y: 64 },
      interaction: {
        kind: "christian-trace",
        prompt: "Assemble the legal inheritance",
        accessibleSummary:
          "Three books show how imperial constitutions, juristic reasoning and legal teaching became one authoritative body.",
        stops: [
          {
            id: "codex",
            label: "Command",
            period: "529 / 534",
            detail:
              "The Codex selects and harmonises imperial constitutions from earlier reigns to Justinian’s own.",
            instrument: "An authorised commission and a single revised collection",
            inheritance: "Judges receive an imperial law book for current government",
          },
          {
            id: "digest",
            label: "Reason",
            period: "533",
            detail:
              "The Digest arranges extracts from generations of Roman jurists by legal subject.",
            instrument: "Fifty books of selected and edited jurisprudence",
            inheritance: "Classical legal reasoning survives the loss of most original works",
          },
          {
            id: "institutes",
            label: "Teach",
            period: "533",
            detail:
              "The Institutes introduces students to persons, things and actions while carrying force of law.",
            instrument: "A concise curriculum tied to the official compilation",
            inheritance: "Roman law becomes a reproducible discipline",
          },
        ],
      },
    },
    {
      id: "wisdom-builds-a-dome",
      actId: "stone-and-law",
      order: 13,
      period: "AD 532–537",
      place: "Hagia Sophia · Constantinople",
      title: "Wisdom Builds a Dome of Light",
      thesis:
        "After revolt burned the capital’s cathedral, Justinian raised a sacred interior that made Christian Roman order visible.",
      body: [
        "In January 532 the Blues and Greens united against the government during the Nika revolt. Crowds burned the centre of Constantinople and acclaimed a rival emperor in the Hippodrome. Justinian’s commanders Belisarius and Mundus crushed the uprising with mass killing inside the arena. The destroyed cathedral gave the emperor a site on which victory, repentance and reconstruction could be joined.",
        "Anthemius of Tralles and Isidore of Miletus designed a church unlike a conventional timber-roofed basilica. Piers, arches, semi-domes and pendentives carried a vast central dome above a flowing interior. Marble revetment mirrored veined stone across walls; columns and coloured pavements gathered material from across the empire. Forty windows at the dome’s base dissolved its edge in changing daylight. Procopius described a canopy suspended from heaven.",
        "Hagia Sophia was dedicated on 27 December 537. Liturgy filled the geometry with chant, incense, procession, silver and flame. The emperor crossed from palace into a church whose scale exceeded any episcopal hall, while patriarch and clergy gave sacred order to imperial presence. Earthquake damage later required Isidore the Younger to rebuild the dome at a steeper profile. The church became the ceremonial heart of Roman Christianity for nine centuries.",
      ],
      image: `${imageRoot}/13-wisdom-builds-dome.avif`,
      mobileImage: `${imageRoot}/13-wisdom-builds-dome-mobile.avif`,
      imageAlt:
        "Hagia Sophia’s sixth-century dome floats above marble, incense and a Christian imperial procession in broken golden light.",
      imagePosition: "50% center",
      mobileImagePosition: "50% center",
      visualTone: "sacred-gold",
      side: "left",
      sourceIds: ["procopius-buildings", "maas-2005", "kaldellis-2023"],
      evidence: [
        "The surviving structure, later repairs, Procopius’s description and liturgical evidence document the building’s engineering and ceremonial use.",
        "Chronicles place the Nika revolt in 532 and the dedication of the rebuilt church in December 537.",
      ],
      map: { x: 58, y: 64 },
      interaction: {
        kind: "sacred-space",
        prompt: "Raise the sacred interior",
        accessibleSummary:
          "Four views explain how structure, material, worship and imperial ceremony made Hagia Sophia the centre of Christian Rome.",
        states: [
          {
            id: "structure",
            label: "Carry",
            period: "532–537",
            detail:
              "A central dome passes its weight through pendentives, great arches and piers into an expanding field of semi-domes.",
            challenge: "Cover a vast square centre without filling it with columns",
            answer: "Pendentives turn a circular dome into loads carried at four corners",
            consequence: "The congregation sees one continuous vertical space",
          },
          {
            id: "material",
            label: "Illuminate",
            period: "537",
            detail:
              "Windows, polished marble, silver and mosaic receive daylight and lamplight as active architectural material.",
            challenge: "Make immense masonry appear weightless",
            answer: "Open the dome’s base to light and reflect it across uneven surfaces",
            consequence: "Stone seems to change with hour, flame and procession",
          },
          {
            id: "liturgy",
            label: "Sound",
            period: "sixth century",
            detail:
              "Clergy, choir and people activate the building through movement, proclamation, chant and incense.",
            challenge: "Give the capital’s Christian people a common sacred action",
            answer: "Order bodies and voices along nave, ambo, sanctuary and galleries",
            consequence: "Doctrine becomes a public experience of space and time",
          },
          {
            id: "emperor",
            label: "Consecrate",
            period: "sixth century",
            detail:
              "The emperor enters by a controlled ceremonial route and stands before a worship greater than his office.",
            challenge: "Join imperial majesty to Christian submission",
            answer: "Place the ruler within a liturgy governed by altar, clergy and creed",
            consequence: "Roman kingship appears as a vocation inside sacred order",
          },
        ],
      },
    },
    {
      id: "restoration-has-a-cost",
      actId: "stone-and-law",
      order: 14,
      period: "AD 533–565",
      place: "North Africa · Italy · the Danube · the eastern frontier",
      title: "Restoration Has a Cost",
      thesis:
        "Justinian recovered Roman provinces and Mediterranean routes while committing the empire to wars and defences that demanded everything its centre could organise.",
      body: [
        "Belisarius crossed to Africa in 533 and destroyed the Vandal kingdom with startling speed. Carthage and the rich African provinces returned to imperial government. The invasion of Italy began in 535 and became a far longer war against the Ostrogoths. Rome changed hands repeatedly; sieges damaged cities and aqueducts; armies lived from contested land. Narses completed organised Gothic resistance in the 550s, and a strip of southern Spain also entered imperial control.",
        "Justinian repaired fortresses from the Balkans to the eastern frontier, reorganised provinces, confronted raids and negotiated costly peace with Sasanian Persia. The first great outbreak of plague reached the empire in 541–542 and returned in later waves. Contemporary descriptions establish mortality and disruption on a terrifying scale without supporting one secure total for the whole Mediterranean.",
        "At Justinian’s death in 565, Roman rule again encircled much of the sea. Law, taxation, fleet, fortified city and Christian kingship held the parts together. The achievement created exposed frontiers and bills that successors inherited. Beyond the eastern forts stood Persia, another ancient imperial civilization with its own armies, court and universal ambition. Their coming struggle would exhaust both powers before a new enemy broke out of Arabia.",
      ],
      image: `${imageRoot}/14-restoration-cost.avif`,
      mobileImage: `${imageRoot}/14-restoration-cost-mobile.avif`,
      imageAlt:
        "A weathered Roman standard overlooks restored Mediterranean harbours, ruined Italian walls and distant eastern fortresses at the end of Justinian’s reign.",
      imagePosition: "58% center",
      mobileImagePosition: "52% center",
      visualTone: "restoration-dusk",
      side: "right",
      sourceIds: ["procopius-wars", "procopius-buildings", "maas-2005", "kaldellis-2023"],
      evidence: [
        "Procopius’s Wars, inscriptions, fortifications, coinage and administrative texts document conquest and reconstruction.",
        "Narrative and scientific evidence establish the arrival of plague in 541–542 while leaving empire-wide mortality totals uncertain.",
      ],
      map: { x: 55, y: 66 },
      interaction: {
        kind: "christian-trace",
        prompt: "Measure the reach and the obligation",
        accessibleSummary:
          "Three theatres show how reconquest, fortified frontiers and plague shaped the empire inherited after 565.",
        stops: [
          {
            id: "africa",
            label: "Recover",
            period: "533–534",
            detail:
              "A concentrated expedition defeats Vandal rule and restores Carthage and Africa to the emperor.",
            instrument: "Fleet, field army, local alliances and surviving Roman administration",
            inheritance: "The empire regains revenue, grain lands and a western naval base",
          },
          {
            id: "italy",
            label: "Endure",
            period: "535–554",
            detail:
              "The Italian war becomes a generation of sieges, reversals, reinforcements and damaged cities.",
            instrument: "Repeated commands, fortified ports and armies supplied across the sea",
            inheritance: "Prestige and territory return with a heavy military burden",
          },
          {
            id: "frontiers",
            label: "Hold",
            period: "541–565",
            detail:
              "Fortifications, diplomacy and taxation defend a wide empire through plague and renewed pressure.",
            instrument: "Walls, subsidies, mobile armies and central administration",
            inheritance: "A formidable Roman centre faces more frontiers than one reign can settle",
          },
        ],
      },
    },
  ],
};
