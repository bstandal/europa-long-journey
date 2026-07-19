import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/rome-gathers-europe";

export const romeGathersEurope: ChapterDefinition = {
  slug: "rome-gathers-europe",
  number: "05",
  title: "Rome Gathers Europe",
  period: "509 BC–AD 212",
  claim:
    "Rome made conquest durable by extending citizenship, local office and military service outwards from one city until much of Europe lived inside a common political order.",
  theme: {
    id: "rome",
    label: "The forged road",
  },
  openingAction: "Enter the forged road",
  mapLabel: "The roads, cities and commands of the Roman political world",
  routeImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Laws · roads · military diplomas · census records · municipal charters · histories · papyri",
  acts: [
    {
      id: "power-without-king",
      number: "I",
      label: "The city under law",
      period: "509–338 BC",
      title: "Power Without a King",
      detail:
        "Rome divides command among magistrates, Senate and assemblies, then makes conflict inside the citizen body part of the constitution.",
    },
    {
      id: "italian-engine",
      number: "II",
      label: "Roads and allies",
      period: "338–146 BC",
      title: "The Road Makes an Army",
      detail:
        "Different settlements, colonies and military obligations turn defeated Italian communities into the manpower system of Mediterranean conquest.",
    },
    {
      id: "commands-break-republic",
      number: "III",
      label: "The returning command",
      period: "146–27 BC",
      title: "The Conquered World Returns Home",
      detail:
        "Land, enslaved labour and overseas armies enlarge the prize of office until public commands become weapons in Roman civil war.",
    },
    {
      id: "provinces-enter-name",
      number: "IV",
      label: "One Roman name",
      period: "27 BC–AD 212",
      title: "The Provinces Enter the Name",
      detail:
        "Emperors govern through armies, censuses and self-governing cities while service and grants carry citizenship across the provinces.",
    },
  ],
  ending: {
    period: "AD 212",
    title: "The name now spans the empire",
    detail:
      "Caracalla’s grant made almost every free inhabitant a Roman citizen. It left slavery, wealth and legal privilege intact, but gave the empire a shared civic status through which later emperors, bishops and jurists could address people from Britain to Syria as members of one Roman commonwealth.",
    image: `${imageRoot}/ending-faith-enters-empire.avif`,
    mobileImage: `${imageRoot}/ending-faith-enters-empire-mobile.avif`,
    nextPeriod: "AD 312–1453",
  },
  returnHash: "rome-gathers-europe",
  nextHash: "christian-empire",
  nextTitle: "The Christian Empire",
  movements: [
    {
      id: "power-after-the-king",
      actId: "power-without-king",
      order: 1,
      period: "traditionally 509–c. 450 BC",
      place: "The Forum · the Capitoline · the Tiber crossing",
      title: "The King Leaves. Command Remains.",
      thesis:
        "Rome answered the fear of kingship by dividing public power without making that power weak.",
      body: [
        "At dawn, attendants cross the Forum carrying bundles of rods before an elected magistrate. The rods announce coercive authority; outside the sacred boundary of the city, an axe can be added to them. Roman memory placed the expulsion of the last king in 509 BC and made hatred of kingship the Republic’s first principle. The exact transition is hidden by centuries of later storytelling, but the political order that emerged treated command as necessary, dangerous and temporary.",
        "Two consuls eventually stood at the summit of the annual magistracies. Each possessed imperium, the authority to summon troops, lead armies and execute public decisions, and each had a colleague capable of obstruction. Praetors developed judicial and military functions. Censors registered citizens and property, revised the Senate and let contracts for public work. The offices accumulated over time; the familiar constitution of the middle Republic cannot be placed fully formed in its first year.",
        "The Senate supplied memory across those short terms. Its members were current and former magistrates drawn from the leading families. Formally it advised. In practice its control of finance, foreign relations, religious consultation and the allocation of commands gave its decisions enormous weight. Popular assemblies elected magistrates, enacted laws and judged some capital cases, although citizens voted in groups whose order and composition favoured wealth, age and established organisation.",
        "Roman liberty therefore meant that no citizen should obey a king, not that each citizen held equal power. Elite households competed for office and military honour before a voting people. Magistrates needed authorisation, auspices, colleagues and money; senators needed men willing to vote and serve; assemblies needed an officeholder to summon them and place a proposal before them. The Republic created action from this managed dependence, then carried the same magistrates from civic space into war.",
      ],
      image: `${imageRoot}/01-power-after-king.avif`,
      mobileImage: `${imageRoot}/01-power-after-king-mobile.avif`,
      imageAlt:
        "A worn early Roman Forum at dawn as lictors carry rods before an elected magistrate and citizens gather around timber and stone public buildings.",
      imagePosition: "57% center",
      mobileImagePosition: "52% center",
      visualTone: "iron-dawn",
      side: "left",
      sourceIds: ["drogula-2026", "lintott-1999", "livy-history", "polybius-histories"],
      evidence: [
        "The conventional date of 509 BC belongs to Roman historical memory; archaeology and later literary reconstruction show a longer transformation from monarchy to republican government.",
        "Magistracies, assemblies, senatorial procedure, religious rules and symbols such as the fasces document a constitution built from divided but effective authority.",
      ],
      map: { x: 48, y: 67 },
    },
    {
      id: "the-people-make-power-answer",
      actId: "power-without-king",
      order: 2,
      period: "fifth–fourth centuries BC",
      place: "The Forum · the Aventine · the assembly grounds",
      title: "The People Make Power Answer",
      thesis:
        "Conflict between citizens forced command to acquire written limits, elected opponents and public procedures.",
      body: [
        "A debtor is seized by a creditor and led through the same public ground where magistrates promise to defend the community. Rome’s citizen body contained sharp divisions of wealth, lineage and legal capacity. The later narrative called the struggle between patricians and plebeians a conflict of the orders. Its episodes were polished by family memory, but the institutions it produced are unmistakable: tribunes of the plebs, a plebeian council, access to magistracies and a body of public law claimed by the whole citizen community.",
        "The tribunes carried personal inviolability and the power to intervene on behalf of a citizen. They could stop official action, summon the plebeian council and bring elite conduct before a public audience. Their office did not abolish hierarchy. It created an authorised point from which hierarchy could be challenged inside the state. Plebeian families then entered the highest magistracies and joined patricians in a new office-holding nobility.",
        "Roman tradition dated the Twelve Tables to 451 and 450 BC after a special commission displayed rules in the Forum. The tablets themselves are lost; later authors quote and paraphrase fragments concerning debt, inheritance, family authority, injury and procedure. The surviving language is neither a modern code nor proof of equal justice. Its political force lay in the claim that legal words could stand outside the private knowledge of magistrates and priests.",
        "The resulting constitution rested on several kinds of public action at once. Citizens elected and legislated; magistrates proposed and executed; the Senate coordinated money, diplomacy and long policy. Religious specialists judged signs and lawful timing. Tribunes could interrupt. Each element acquired leverage by preventing another from acting alone. This was a competitive order built for a face-to-face city, and its capacity to turn civic rank into military obligation would soon make the city much larger than its institutions expected.",
      ],
      image: `${imageRoot}/02-people-make-power-answer.avif`,
      imageAlt:
        "Citizens crowd around a public display of early Roman law while a tribune intervenes between a magistrate and a seized debtor.",
      imagePosition: "62% center",
      visualTone: "public-iron",
      side: "right",
      sourceIds: ["drogula-2026", "lintott-1999", "twelve-tables", "livy-history"],
      evidence: [
        "Later quotations preserve fragments attributed to the Twelve Tables, while the political narrative of their publication comes through authors writing centuries afterward.",
        "Tribunician powers, plebeian legislation and the eventual opening of senior offices document durable institutional results of conflict within the citizen body.",
      ],
      map: { x: 48, y: 67 },
      interaction: {
        kind: "roman-constitution",
        prompt: "Hold the Republic in balance",
        accessibleSummary:
          "Three views explain what the people, magistrates and Senate could do, what restrained each institution and what their dependence produced.",
        institutions: [
          {
            id: "people",
            label: "The people",
            detail:
              "Assemblies elected magistrates, enacted laws and decided some trials, but citizens voted through unequal groups and only on business placed before them.",
            authority: "Election · legislation · public judgment",
            limit: "Unequal voting units; a magistrate convenes and proposes",
            consequence: "Elite competition must pass through a citizen vote",
          },
          {
            id: "magistrates",
            label: "The magistrates",
            detail:
              "Consuls, praetors, censors and tribunes converted public decisions into command, justice, registration and obstruction.",
            authority: "Agenda · imperium · courts · intervention",
            limit: "Short terms, colleagues, vetoes, law and later accountability",
            consequence: "Rome can act quickly without making ordinary command permanent",
          },
          {
            id: "senate",
            label: "The Senate",
            detail:
              "Former magistrates gave the Republic continuity through finance, diplomacy, religion and the allocation of military responsibilities.",
            authority: "Money · advice · foreign affairs · continuity",
            limit: "No independent legislative sovereignty; prestige depends on office and obedience",
            consequence: "Annual commands become part of a longer aristocratic strategy",
          },
        ],
      },
    },
    {
      id: "defeat-teaches-rome-to-return",
      actId: "power-without-king",
      order: 3,
      period: "c. 390–338 BC",
      place: "Rome · Latium · the central Apennines",
      title: "Defeat Teaches Rome to Return",
      thesis:
        "Rome’s strength lay in restoring armies and political relationships after reverses that would end another city’s war.",
      body: [
        "A household returns to blackened ground after a Gallic force has occupied and ransomed Rome. The date and details of the sack, conventionally placed in 390 BC, are entangled with later moral stories. The defeat itself remained central to Roman memory because the city survived it. Walls were strengthened, armies went out again and neighbouring communities discovered that one successful invasion had not removed Rome from Latium.",
        "Republican warfare drew on citizens registered by household and property. The census connected a man’s civic position to military liability and voting rank. Service demanded harvest time, equipment, bodily risk and years away from land. Success rewarded commanders and could distribute booty, but repeated campaigning also pressed smallholders and debtors. The system joined political standing to an expectation that citizens would fight under elected magistrates.",
        "Rome also learned through settlements rather than battlefield annihilation. Some defeated communities lost land. Some received forms of citizenship. Some remained allies bound by treaty and military obligation. Colonies placed organised groups at strategic sites without creating a continuous Roman territory. These arrangements were neither uniform nor designed in one moment; they accumulated through negotiation, coercion, local circumstance and renewed revolt.",
        "The settlement after the Latin War in 338 BC became a decisive enlargement. Rome dissolved the old Latin League and dealt with communities separately. Direct collective action against Rome became harder, while each community acquired its own bundle of rights and duties. The city had begun to solve a problem that Greek hegemonies repeatedly faced: how to preserve local civic structures while preventing allied autonomy from becoming a rival coalition.",
      ],
      image: `${imageRoot}/03-defeat-teaches-return.avif`,
      imageAlt:
        "Roman families and soldiers rebuild beside a scorched city wall after the Gallic sack while new levies assemble beyond the gate.",
      imagePosition: "54% center",
      visualTone: "ash-return",
      side: "left",
      sourceIds: ["livy-history", "drogula-2026", "helm-2017", "lintott-1999"],
      evidence: [
        "Archaeology does not confirm the full destruction described by later literary narratives, but the Gallic sack became an organising memory of Roman vulnerability and recovery.",
        "Colonies, treaty communities and differentiated citizenship are visible in settlement histories, legal categories and military obligations after Rome’s fourth-century wars.",
      ],
      map: { x: 47, y: 65 },
      interaction: {
        kind: "roman-trace",
        prompt: "Rebuild the power to return",
        accessibleSummary:
          "Three stops show how registration, negotiated obligation and separate settlements let Rome raise forces again and prevent a rival Latin coalition.",
        stops: [
          {
            id: "register",
            label: "Register",
            period: "fourth century BC",
            detail:
              "The census connected household, property, civic rank and military liability, making renewed recruitment a public procedure rather than a commander’s private following.",
            mechanism: "Households and property are assigned to civic and military classes",
            consequence: "A defeated city can summon another citizen levy",
          },
          {
            id: "bind",
            label: "Bind",
            period: "fourth century BC",
            detail:
              "Treaties, colonies and differentiated grants preserved local communities while attaching land, routes and soldiers to Roman war-making.",
            mechanism: "Each community receives its own obligations and recognised position",
            consequence: "Recovery draws on relationships beyond Rome’s walls",
          },
          {
            id: "separate",
            label: "Separate",
            period: "338 BC",
            detail:
              "After the Latin War, Rome dissolved the league and settled with its former members community by community.",
            mechanism: "Collective Latin action is replaced by bilateral settlements",
            consequence: "Local cities survive without rebuilding one rival coalition",
          },
        ],
      },
    },
    {
      id: "many-terms-of-defeat",
      actId: "italian-engine",
      order: 4,
      period: "338–c. 275 BC",
      place: "Latium · Campania · Samnium · southern Italy",
      title: "Defeat Has Many Terms",
      thesis:
        "Rome enlarged its power by imposing different relationships on different communities instead of erasing every conquered city.",
      body: [
        "Envoys arrive in Rome carrying separate requests from cities that had fought on the same side. One community keeps its magistrates and territory as an allied state. Another receives citizenship without a practical vote at Rome. A Latin colony gains rights of commerce and movement defined by its status. A third loses land on which Roman or Latin settlers will stand guard. The variety prevents a single defeated bloc from re-forming.",
        "Roman citizenship itself contained political, civil and military dimensions. Voting and eligibility for office mattered at the centre. Marriage recognised by Roman law, property transactions, inheritance and access to courts shaped family and economic life. Partial grants could separate these benefits. Latin status provided another adaptable legal relationship. Treaties with allied communities preserved formal local independence while requiring troops and accepting Roman leadership in war.",
        "The system imposed heavy burdens. Allied contingents often matched or exceeded Roman troops in republican armies, while decisions about war remained at Rome. Colonies occupied confiscated land and controlled routes. Communities that resisted could face renewed campaigns, hostage-taking, property loss and enslavement. Incorporation worked because it created usable positions below full equality, not because conquered peoples had freely chosen Roman command.",
        "It also left room for ambition. Local elites kept councils, cults and property, dealt with Roman commanders and could seek better status for themselves or their communities. Individuals moved for trade, marriage and service across legal boundaries that required new courts and instruments. By the early third century BC, Rome commanded a peninsula filled with cities that remained locally recognisable while supplying a common war effort.",
      ],
      image: `${imageRoot}/04-many-terms-of-defeat.avif`,
      imageAlt:
        "Italian envoys place separate treaty tablets before Roman magistrates while colonists, allied soldiers and local councillors wait under a smoky portico.",
      imagePosition: "66% center",
      visualTone: "treaty-red",
      side: "right",
      sourceIds: ["helm-2017", "roselaar-2016", "lintott-1999", "livy-history"],
      evidence: [
        "Community histories and later legal discussions preserve a dense landscape of citizens, citizens without voting power, Latins and treaty allies rather than one standard settlement.",
        "Republican levy figures and campaign narratives repeatedly distinguish Roman and allied contingents serving under Roman strategic leadership.",
      ],
      map: { x: 48, y: 67 },
    },
    {
      id: "the-road-makes-an-army",
      actId: "italian-engine",
      order: 5,
      period: "312–264 BC",
      place: "The Via Appia · Campania · the Adriatic approaches",
      title: "The Road Makes an Army",
      thesis:
        "Roads and colonies turned separate obligations into forces that Rome could assemble, supply and replace.",
      body: [
        "A surveyor sights along a taut line while labourers set large basalt blocks into prepared layers. The Via Appia began in 312 BC under the censor Appius Claudius Caecus, running from Rome toward Capua before later extensions reached southern Italy. It did not appear as a finished imperial highway. Drainage, bridges, cuttings, paving and milestones accumulated as Roman movement required a durable route through contested land.",
        "The road served armies before it became a familiar symbol of travel. Messengers carried orders; recruits reached mustering points; pack animals and carts moved equipment; officials could return to Rome. Sea and river transport remained essential for bulk goods, and many local roads were older than Roman rule. Roman power came from joining those routes to colonies, treaty obligations and a calendar of repeated levies.",
        "Colonies held crossings, coasts and corridors. Their settlers received land and a corporate civic life while anchoring Roman or Latin power among neighbouring communities. Roads made those positions mutually supporting. A hostile army could win a field and find another fortified community ahead, another allied contingent behind and another Roman levy forming along the route to the capital.",
        "The network was political before it was geometric. Each line led to communities with distinct rights, resentments and reasons to comply. Rome demanded manpower and interfered with land; it also offered allies a share in campaigns whose victories could bring booty and regional advantage. By the First Punic War, this Italian engine allowed a city with limited naval experience to lose fleets, build replacements and continue fighting across the sea.",
      ],
      image: `${imageRoot}/05-road-makes-army.avif`,
      imageAlt:
        "Roman surveyors, road builders and allied recruits occupy a long basalt road under construction between a colony gate and the hills of Campania.",
      imagePosition: "61% center",
      visualTone: "basalt-line",
      side: "left",
      sourceIds: ["laurence-1999", "helm-2017", "bradley-warfare-2020", "livy-history"],
      evidence: [
        "Milestones, road surfaces, bridges and settlement patterns document routes built and extended in stages rather than a single centrally planned network.",
        "Colonial locations and literary campaign accounts show how roads linked strategic settlements, levies and military supply across Italy.",
      ],
      map: { x: 49, y: 68 },
      interaction: {
        kind: "roman-network",
        prompt: "Build the Italian engine",
        accessibleSummary:
          "Four map states show separate settlements, the Via Appia, a peninsula of colonies and allies, and the mobilisation system tested by Hannibal.",
        mapImage: "assets/europe-relief.webp",
        states: [
          {
            id: "settlements-338",
            label: "Separate settlements",
            period: "338 BC",
            detail:
              "Rome broke the defeated Latin coalition into distinct settlements whose rights and military duties were negotiated community by community.",
            measure: "One war ends in several legal relationships",
            points: [
              { id: "rome", label: "Rome", detail: "The Senate and people direct war and settlement.", x: 48, y: 66 },
              { id: "capua", label: "Capua", detail: "A powerful Campanian city receives a form of Roman citizenship without an effective vote at Rome.", x: 49, y: 69 },
              { id: "antium", label: "Antium", detail: "Land and ships pass under Roman control after Latin resistance.", x: 46, y: 68 },
              { id: "tibur", label: "Tibur", detail: "A treaty preserves a distinct allied community under Roman leadership.", x: 49, y: 64 },
            ],
            links: [[0, 1], [0, 2], [0, 3]],
          },
          {
            id: "via-appia-312",
            label: "The road south",
            period: "312 BC",
            detail:
              "The first Via Appia bound Rome to Campania through a reliable military corridor that could be repaired and extended.",
            measure: "A measured road joins command to a strategic region",
            points: [
              { id: "rome-road", label: "Rome", detail: "Orders and levies leave the capital.", x: 48, y: 66 },
              { id: "aricia", label: "Aricia", detail: "The road crosses the Alban landscape southeast of Rome.", x: 48.5, y: 67 },
              { id: "terracina", label: "Tarracina", detail: "A coastal choke point requires engineering and protection.", x: 48, y: 68.5 },
              { id: "capua-road", label: "Capua", detail: "The original road reaches the Campanian centre.", x: 49, y: 69 },
            ],
            links: [[0, 1], [1, 2], [2, 3]],
          },
          {
            id: "peninsula-275",
            label: "A peninsula under obligation",
            period: "c. 275 BC",
            detail:
              "Colonies and allied cities kept local institutions while supplying troops across a widening Italian theatre.",
            measure: "Local cities remain; Roman military leadership connects them",
            points: [
              { id: "rome-peninsula", label: "Rome", detail: "The common strategic centre.", x: 48, y: 66 },
              { id: "ariminum", label: "Ariminum", detail: "A Latin colony guards the Adriatic route.", x: 51, y: 61 },
              { id: "venusia", label: "Venusia", detail: "A large Latin colony secures inland southern routes.", x: 51, y: 70 },
              { id: "tarentum", label: "Tarentum", detail: "A defeated Greek city enters Roman command after the Pyrrhic War.", x: 54, y: 72 },
              { id: "cosa", label: "Cosa", detail: "A Latin colony anchors the Tyrrhenian coast.", x: 44, y: 64 },
            ],
            links: [[0, 1], [0, 2], [2, 3], [0, 4]],
          },
          {
            id: "mobilisation-218",
            label: "The levy survives disaster",
            period: "218–216 BC",
            detail:
              "After catastrophic defeats, Rome drew on citizens, allies, colonies, maritime movement and repeated recruitment rather than one standing national army.",
            measure: "Lost armies can be replaced while the alliance system holds",
            points: [
              { id: "rome-levy", label: "Rome", detail: "New magistrates and levies keep the war public.", x: 48, y: 66 },
              { id: "placentia", label: "Placentia", detail: "A new colony contests the northern approach.", x: 46, y: 56 },
              { id: "ariminum-levy", label: "Ariminum", detail: "The Adriatic corridor remains connected to Rome.", x: 51, y: 61 },
              { id: "beneventum", label: "Beneventum", detail: "A colony controls inland movement in Samnium.", x: 50, y: 68 },
              { id: "canusium", label: "Canusium", detail: "Survivors of Cannae find refuge in an allied city.", x: 53, y: 69 },
            ],
            links: [[0, 1], [0, 2], [0, 3], [3, 4]],
          },
        ],
      },
    },
    {
      id: "hannibal-wins-battles",
      actId: "italian-engine",
      order: 6,
      period: "218–201 BC",
      place: "The Alps · Cannae · Capua · North Africa",
      title: "Hannibal Wins the Battles. Rome Keeps the War.",
      thesis:
        "The Second Punic War revealed that Rome’s decisive weapon was the political capacity to replace armies and retain enough Italian partners.",
      body: [
        "Hannibal crosses the Alps with a Carthaginian army drawn from several regions, wins at the Trebia and Lake Trasimene, then destroys a much larger Roman force at Cannae in 216 BC. Tens of thousands are killed or captured. Consuls, former consuls, senators, allied officers and ordinary soldiers disappear in a day. Several southern Italian communities defect; Capua, one of the peninsula’s greatest cities, opens its gates to Hannibal.",
        "Rome refuses a negotiated settlement. The Senate fills offices, ransoms no prisoners under the traditional account and orders new recruitment that reaches younger men, older men, the poor and enslaved volunteers promised freedom. Armies avoid another Cannae while attacking Hannibal’s allies, protecting loyal communities and contesting supply. The strategy is costly and inconsistent, but it keeps several theatres active at once.",
        "Italian loyalty is not automatic. Communities calculate danger, grievance and opportunity. Some Samnite, Lucanian, Bruttian and Greek cities join Carthage; Latin colonies resist demands for further troops; other allies hold to Rome under severe pressure. Hannibal can punish resistance and reward defection, yet he cannot dissolve the entire network or receive enough sustained reinforcement to turn battlefield mastery into a new Italian settlement.",
        "Roman forces then carry the war outward. Campaigns in Spain cut Carthaginian resources. Syracuse falls. Capua is recovered and punished. Publius Cornelius Scipio invades North Africa, compelling Hannibal to leave Italy, and wins at Zama in 202 BC with crucial Numidian support. Rome’s victory belongs to no timeless superiority of legion over phalanx or genius over commerce. A coercive alliance system survived its hardest test and gave the Republic the manpower to learn across defeat.",
      ],
      image: `${imageRoot}/06-hannibal-wins-battles.avif`,
      mobileImage: `${imageRoot}/06-hannibal-wins-battles-mobile.avif`,
      imageAlt:
        "Exhausted Roman and allied survivors reach the gates of Canusium after Cannae while officials organise another levy without heroic battle poses.",
      imagePosition: "59% center",
      mobileImagePosition: "48% center",
      visualTone: "cannae-dust",
      side: "right",
      sourceIds: ["polybius-histories", "livy-history", "bradley-warfare-2020", "helm-2017"],
      evidence: [
        "Polybius provides the closest extended narrative and an analysis of Roman institutions; Livy preserves additional Roman traditions from a later Augustan setting.",
        "Defections, loyal communities, repeated levies, colony protests and simultaneous campaigns show an alliance system under negotiation and coercion rather than automatic Italian unity.",
      ],
      map: { x: 50, y: 69 },
      interaction: {
        kind: "roman-trace",
        prompt: "See why Cannae did not end the war",
        accessibleSummary:
          "Three stops move from the destroyed army at Cannae through the contested Italian alliance network to Rome’s outward counterwar.",
        stops: [
          {
            id: "field",
            label: "The field",
            period: "216 BC",
            detail:
              "Cannae destroyed a Roman army and killed much of its command class, but the Senate, magistracies and recruitment procedures remained in operation.",
            mechanism: "Vacant offices are filled and recruitment opens again",
            consequence: "The loss of an army does not dissolve the state directing the war",
          },
          {
            id: "network",
            label: "The network",
            period: "216–212 BC",
            detail:
              "Capua and several southern communities defected, while Latin colonies and many central Italian allies remained connected to Rome under extreme pressure.",
            mechanism: "Communities choose between rival armies under unequal risks",
            consequence: "Hannibal gains allies without breaking the whole Italian system",
          },
          {
            id: "counterwar",
            label: "The counterwar",
            period: "211–202 BC",
            detail:
              "Roman armies recovered Capua, attacked Carthaginian resources in Spain and carried the war to North Africa with Numidian support.",
            mechanism: "Several theatres consume the enemy’s allies, supplies and freedom of movement",
            consequence: "Battlefield survival becomes a negotiated Roman victory",
          },
        ],
      },
    },
    {
      id: "victory-enters-the-city",
      actId: "commands-break-republic",
      order: 7,
      period: "200–133 BC",
      place: "Rome · Carthage · Corinth · the new provinces",
      title: "Victory Enters the City",
      thesis:
        "Mediterranean conquest brought wealth, captives and long commands into institutions designed for annual competition in one city.",
      body: [
        "A triumph winds through Rome behind paintings of captured cities. Silver, weapons, statues and chained prisoners display a magistrate’s victory before citizens who will vote in future elections. Between the defeat of Hannibal and 146 BC, Roman armies broke Macedonian power, imposed settlements across the Greek east, destroyed Carthage and crushed the Achaean League at Corinth. Provinces placed overseas communities under recurring Roman command and taxation.",
        "Conquest redistributed people as brutally as land and money. Captives entered slave markets and households, mines, workshops and large estates. Enslaved labour had long existed in Italy; expanding wars increased its scale and visibility. Roman and Italian traders, tax contractors, creditors and governors pursued opportunity in the provinces. Provincial communities faced levies, requisitions, judicial dependence and the possibility that a Roman official’s one-year ambition would become their emergency.",
        "The profits were unequal. Aristocrats converted command into glory, clients and wealth. Some Italian landholders assembled larger properties while military service, debt and market pressures strained other households. The scale and regional pattern of dispossession remain debated, and the simple picture of slave plantations replacing every citizen farm cannot carry the evidence. The political fact is clearer: access to public land, booty and overseas command became explosive questions inside Rome.",
        "The Republic had developed ways to share office among a narrow competitive class and to mobilise communities across Italy. It had no permanent civil service proportionate to its conquests and no neutral machinery for assigning the rewards. The Senate governed through magistrates, commissioners, contractors, local elites and precedent. Each new province enlarged the value of command and the number of people who could suffer when Roman competition escaped its old limits.",
      ],
      image: `${imageRoot}/07-victory-enters-city.avif`,
      imageAlt:
        "A Roman triumph brings captured objects and prisoners into a crowded, smoky city as auctioneers and senators turn conquest into property and political credit.",
      imagePosition: "64% center",
      visualTone: "triumph-shadow",
      side: "left",
      sourceIds: ["steel-2013", "flower-2010", "bryen-2026", "polybius-histories"],
      evidence: [
        "Triumphal records, booty, imported monuments, slave-sale evidence and provincial settlements document the material transfer produced by conquest.",
        "The distribution of Italian landholding is contested, while political conflicts over public land, recruitment and overseas exploitation are directly visible in law and narrative.",
      ],
      map: { x: 52, y: 68 },
    },
    {
      id: "the-allies-demand-the-name",
      actId: "commands-break-republic",
      order: 8,
      period: "133–70 BC",
      place: "Rome · Asculum · Corfinium · the Italian peninsula",
      title: "The Allies Demand the Name",
      thesis:
        "The communities that had helped conquer the Mediterranean forced Rome to admit that military partnership without equal civic standing could not endure.",
      body: [
        "A survey line reaches land occupied by an Italian ally whose family has fought under Roman commanders for generations. The land commission associated with Tiberius Gracchus after 133 BC seeks to recover public land and settle citizens, but boundary decisions expose the insecure position of allies who possess or use land claimed by Rome. Reform at the centre reaches people who cannot vote on the law that alters their holdings.",
        "Italian elites and communities had reasons to value Roman citizenship beyond the ballot. Recognised marriage, inheritance, contracts, appeal, protection against arbitrary treatment and access to Roman political careers shaped family strategy and economic security. Many Italians had adopted Latin and cultivated Roman patrons while retaining local identities. Their troops had borne a large share of republican warfare without equal authority over the state that sent them.",
        "After the murder of the tribune Marcus Livius Drusus in 91 BC, rebellion spread among several allied peoples. They created a rival federal centre at Corfinium, issued coinage and appointed magistrates whose titles answered Rome with an Italy capable of governing itself. Other communities remained loyal. The Social War became a contest over membership in the Roman state, conducted through sieges, devastation and armies trained in the same military world.",
        "Rome conceded while fighting. The Lex Iulia of 90 BC offered citizenship to loyal or disarming communities; further laws in 89 widened access under stated conditions. Enrolment, voting tribes and practical integration took years, with a major census in 70 BC marking a later stage. The settlement did not erase local towns or regional identities. It made Roman citizenship the common status of Italy and converted the old allied manpower system into an army of Roman citizens.",
      ],
      image: `${imageRoot}/08-allies-demand-name.avif`,
      imageAlt:
        "Italian allied veterans and municipal envoys confront Roman land surveyors as the Social War standard of Italia rises in a fortified town.",
      imagePosition: "58% center",
      visualTone: "italian-red",
      side: "right",
      sourceIds: ["roselaar-2016", "mouritsen-1998", "appian-civil-wars", "steel-2013"],
      evidence: [
        "Italian coinage, community histories and Appian’s later narrative document a rival wartime organisation with magistrates, armies and a federal centre.",
        "The citizenship laws of 90–89 BC and later census evidence show concession during war followed by a longer process of registration and political integration.",
      ],
      map: { x: 49, y: 66 },
      interaction: {
        kind: "roman-trace",
        prompt: "Watch citizenship become the war aim",
        accessibleSummary:
          "Three stops show Italian exclusion, the rival institutions created during revolt and the laws that made Roman citizenship the common status of Italy.",
        stops: [
          {
            id: "exclusion",
            label: "Exclusion",
            period: "133–91 BC",
            detail:
              "Italian allies supplied soldiers and lived under Roman strategic decisions without equal votes, appeals or access to Roman careers.",
            mechanism: "Military partnership operates below equal civic standing",
            consequence: "Land reform and command expose burdens that allies cannot vote to change",
          },
          {
            id: "italia",
            label: "Italia",
            period: "91–90 BC",
            detail:
              "Rebel communities created a federal centre, magistrates, coinage and armies that claimed Italy could govern the war in its own name.",
            mechanism: "Roman military experience is turned into a rival Italian state",
            consequence: "Membership becomes the object of war rather than a future reward",
          },
          {
            id: "enrolment",
            label: "Enrolment",
            period: "90–70 BC",
            detail:
              "Citizenship laws conceded status during the fighting; registration, voting assignments and a later census made the grant effective over time.",
            mechanism: "Law opens the status and civic administration records its new holders",
            consequence: "The old allied army becomes an Italian army of Roman citizens",
          },
        ],
      },
    },
    {
      id: "armies-follow-generals-home",
      actId: "commands-break-republic",
      order: 9,
      period: "88–27 BC",
      place: "Rome · the eastern provinces · Gaul · Actium",
      title: "Armies Follow Their Generals Home",
      thesis:
        "When long wars tied soldiers’ futures to individual commanders, Rome’s public power became capable of conquering Rome itself.",
      body: [
        "In 88 BC, the consul Lucius Cornelius Sulla turns troops assigned to an eastern war toward Rome after a political rival transfers his command. A Roman army crosses the city’s sacred boundary under its own magistrate. Sulla later returns from the east, wins a civil war, publishes lists of enemies who may be killed and has himself appointed dictator to rewrite the state. The Republic’s emergency power now follows victory rather than containing it.",
        "The underlying commands keep growing. Pompey receives exceptional authority across the Mediterranean and eastern provinces, then seeks land and ratification for his veterans and settlements. Julius Caesar’s years in Gaul produce conquest, plunder, patronage and an army accustomed to his leadership. When the Senate’s political coalition demands that he surrender command, Caesar crosses the Rubicon in 49 BC and presents civil war as the defence of his dignitas and tribunician rights.",
        "Caesar wins and accumulates offices, honours and a dictatorship without normal end. His assassins kill him in 44 BC while claiming to restore liberty. The murder removes the ruler, not the armies, colonies, debts and rival claims created by civil war. Octavian, Mark Antony and Lepidus obtain a legally constituted triumvirate, proscribe enemies and defeat the assassins. Another war then divides the Roman world between Antony in the east and Octavian in the west.",
        "Octavian’s victory at Actium in 31 BC leaves one commander in possession of the decisive armies and provinces. In 27 BC he stages a transfer of powers and receives the name Augustus; later settlements give his position a durable combination of proconsular command and tribunician authority. Magistrates, Senate and assemblies continue. Their competition now takes place under a ruler who controls the largest military resources and can transmit a political household to successors.",
      ],
      image: `${imageRoot}/09-armies-follow-generals.avif`,
      mobileImage: `${imageRoot}/09-armies-follow-generals-mobile.avif`,
      imageAlt:
        "A Roman legion marches across the sacred boundary toward its own city while civil standards and anxious civilians replace any scene of foreign conquest.",
      imagePosition: "55% center",
      mobileImagePosition: "52% center",
      visualTone: "civil-iron",
      side: "left",
      sourceIds: ["steel-2013", "flower-2010", "appian-civil-wars", "caesar-civil-war", "res-gestae"],
      evidence: [
        "Appian, Caesar, Cicero’s correspondence, inscriptions and coinage preserve partisan accounts and public acts across the civil wars.",
        "The legal grants to Sulla, the triumvirs and Augustus show extraordinary command being authorised through Roman institutions as those institutions lost independent control of force.",
      ],
      map: { x: 48, y: 66 },
      interaction: {
        kind: "roman-command",
        prompt: "Follow the command back to Rome",
        accessibleSummary:
          "Four states trace how an assigned war became a personal army, how repeated civil war normalised exceptional power and where command settled under Augustus.",
        states: [
          {
            id: "sulla-88",
            label: "The first march",
            period: "88 BC",
            detail:
              "Sulla persuades legions assigned to him to reverse direction and seize the city that had issued their command.",
            commander: "Sulla, serving consul",
            command: "The war against Mithridates is transferred by political action at Rome",
            institutionalChange: "An army decides which Roman decision it will obey",
          },
          {
            id: "caesar-49",
            label: "The provincial army",
            period: "49 BC",
            detail:
              "Caesar’s long Gallic command supplies money, prestige and veteran loyalty strong enough to contest the Senate’s coalition.",
            commander: "Julius Caesar, proconsul",
            command: "Years of conquest in Gaul under repeated extensions",
            institutionalChange: "A provincial command becomes an independent political base",
          },
          {
            id: "triumvirs-43",
            label: "Exception becomes law",
            period: "43 BC",
            detail:
              "Octavian, Antony and Lepidus receive statutory power to remake the state, then use proscription and armies against Roman rivals.",
            commander: "Three legally appointed triumvirs",
            command: "Extraordinary authority over offices, enemies and provinces",
            institutionalChange: "Civil-war supremacy acquires a constitutional form",
          },
          {
            id: "augustus-27",
            label: "Command settles",
            period: "27–23 BC",
            detail:
              "Augustus returns selected powers while retaining the provinces and authorities that make rival military command impossible.",
            commander: "Augustus, princeps",
            command: "Superior provincial imperium joined to tribunician power",
            institutionalChange: "Republican offices continue beneath permanent one-man military pre-eminence",
          },
        ],
      },
    },
    {
      id: "the-emperor-governs-through-cities",
      actId: "provinces-enter-name",
      order: 10,
      period: "27 BC–second century AD",
      place: "Tarraco · Lugdunum · Corinth · Ephesus",
      title: "The Emperor Governs Through Cities",
      thesis:
        "The Principate held distant provinces through a small imperial superstructure resting on armies, censuses and local civic government.",
      body: [
        "A provincial household declares people, land and property before officials preparing a census. Augustus divides provincial commands between areas formally assigned to the Senate and those where he appoints legates, retaining control of the principal military zones. A permanent army receives regular terms of service and discharge. Taxes, customs dues, estates, mines and requisitions support soldiers, administration, the court and the immense food needs of Rome.",
        "The imperial state remains thin by modern standards. A governor travels with staff, hears cases, supervises finance and answers disorder, but cannot administer every street from the provincial capital. Cities perform much of the daily work. Councils of local property holders manage funds, buildings, cults, markets and honours; magistrates regulate civic business; communities send embassies and petitions upward when local solutions fail.",
        "Roman rule therefore preserves and reshapes existing civic landscapes. Greek poleis continue assemblies, councils and laws under imperial sovereignty. Western communities receive colonial or municipal forms adapted to local histories. The Lex Irnitana from Flavian Spain records procedures for magistrates, councils, elections, finances and jurisdiction in a Latin-status municipality. Such charters reveal neither identical cities nor unrestricted autonomy, but a repeatable grammar connecting local office to Roman authority.",
        "Governors, soldiers, tax collectors and local magnates could abuse that structure. Provincial people paid for conquest, endured requisitions and faced unequal access to Roman patrons and courts. Emperors advertised hearings and punishment of bad officials because exploitation was a recurring danger. The empire became durable through this tension: Rome required local notables to govern, while those notables used Roman office, law and imperial favour to strengthen their position at home.",
      ],
      image: `${imageRoot}/10-emperor-governs-through-cities.avif`,
      imageAlt:
        "A multilingual provincial city gate opens onto a census table, local council chamber, market and distant Roman military road under worn painted masonry.",
      imagePosition: "63% center",
      visualTone: "provincial-brick",
      side: "right",
      sourceIds: ["res-gestae", "ando-2000", "campbell-provinces-2025", "bryen-2026", "lex-irnitana"],
      evidence: [
        "Census records, municipal laws, council decrees, petitions and governors’ correspondence reveal provincial administration working through local civic institutions.",
        "Legal complaints and imperial responses document both administrative ideals and recurrent extraction, military interference and difficulty obtaining redress.",
      ],
      map: { x: 43, y: 58 },
      interaction: {
        kind: "roman-trace",
        prompt: "Send an order through a province",
        accessibleSummary:
          "Three stops show how imperial command passed through a governor and a local council before it reached ordinary provincial households.",
        stops: [
          {
            id: "emperor",
            label: "Emperor",
            period: "the Principate",
            detail:
              "The emperor controlled the principal military provinces, appointed legates and answered selected petitions from communities and officials.",
            mechanism: "Commands, appointments and judgments leave the imperial centre",
            consequence: "One ruler coordinates distant armies without administering every town",
          },
          {
            id: "governor",
            label: "Governor",
            period: "provincial circuit",
            detail:
              "A governor and a small staff travelled, heard cases, supervised finance and intervened when local order or imperial revenue was threatened.",
            mechanism: "A mobile provincial office interprets imperial authority",
            consequence: "Cases and demands are concentrated without creating a modern bureaucracy",
          },
          {
            id: "city",
            label: "City council",
            period: "local government",
            detail:
              "Municipal magistrates and councils managed funds, markets, buildings, honours and local collection, then petitioned upward when their powers failed.",
            mechanism: "Local property holders perform the daily work of government",
            consequence: "Roman durability rests on cities that retain recognisable civic institutions",
          },
        ],
      },
    },
    {
      id: "service-opens-the-gate",
      actId: "provinces-enter-name",
      order: 11,
      period: "first century BC–second century AD",
      place: "The Rhine · Hispania · Gaul · cities across the empire",
      title: "Service Opens the Gate",
      thesis:
        "Citizenship spread through military service, manumission, local office and imperial grants long before it became nearly universal.",
      body: [
        "A bronze diploma is folded, sealed and handed to an auxiliary veteran after twenty-five years of service. He entered the army as a free provincial without Roman citizenship. The document records an imperial grant that can alter marriage, inheritance and the legal position of his household, although the treatment of children and unions changed over time. Thousands of such diplomas make citizenship visible as a reward administered across distant frontiers.",
        "The army was one route among several. Enslaved people freed by Roman citizens could acquire forms of Roman citizenship, subject to legal restrictions, patronal obligations and the permanent mark of former enslavement. Their freeborn children entered a different standing. In towns with Latin rights, holding a municipal magistracy could bring Roman citizenship to an officeholder and family under the applicable grant. Emperors could reward individuals, units, communities or provincial elites.",
        "Citizenship did not require a person to abandon every other belonging. A citizen of a Gallic or Spanish city could maintain local cult, kinship, language and office while acting in Roman law. Claudius argued in AD 48 for admitting leading men from Gallia Comata to the Senate, presenting Rome’s history as repeated incorporation. Tacitus preserves a literary version of the speech; the bronze Lyon Tablet preserves substantial wording from the imperial address itself.",
        "The opening remained unequal. Senatorial office demanded immense wealth and imperial approval. Municipal government concentrated burdens and honours among property holders. Citizen women possessed important rights in property, inheritance and family status but did not vote or hold ordinary political magistracies. Enslaved people remained property. Citizenship expanded the number of people who could claim recognised standing from Roman institutions; it did not dissolve the hierarchies those institutions enforced.",
      ],
      image: `${imageRoot}/11-service-opens-gate.avif`,
      imageAlt:
        "A provincial auxiliary veteran receives a bronze citizenship diploma beside his family while a freedperson and municipal magistrate wait at the same civic gate.",
      imagePosition: "60% center",
      visualTone: "diploma-light",
      side: "left",
      sourceIds: ["british-museum-legion-2024", "campbell-status-2025", "eck-2021", "tacitus-annals", "coskun-2021"],
      evidence: [
        "Thousands of military diplomas record dated grants of citizenship and marriage rights to auxiliary veterans, with changes in formula across the imperial period.",
        "Municipal laws, manumission rules, honorific inscriptions and the Lyon Tablet document several distinct routes into Roman civic standing.",
      ],
      map: { x: 42, y: 50 },
      interaction: {
        kind: "roman-citizenship",
        prompt: "Trace a path into the Roman name",
        accessibleSummary:
          "Four paths show how an auxiliary veteran, a freedperson, a municipal officeholder and a provincial notable could acquire citizenship, together with the limits that remained.",
        paths: [
          {
            id: "auxiliary",
            label: "Auxiliary service",
            detail:
              "A free non-citizen could serve for roughly twenty-five years and receive an individually recorded imperial grant at honourable discharge.",
            startingStatus: "A peregrine recruited into an auxiliary unit",
            route: "Long military service · honourable discharge · bronze diploma",
            rights: "Roman citizenship and stated family or marriage provisions",
            limit: "Service was dangerous, discipline severe and diploma formulas changed over time",
          },
          {
            id: "manumission",
            label: "Manumission",
            detail:
              "Formal release by a Roman owner could make a formerly enslaved person a citizen while preserving obligations and social stigma.",
            startingStatus: "A person legally owned by a Roman citizen",
            route: "Recognised manumission under rules governing age and form",
            rights: "A freed citizen able to contract, own and transmit within Roman law",
            limit: "Patronal duties, legal restrictions and the history of enslavement remained",
          },
          {
            id: "municipal-office",
            label: "Municipal office",
            detail:
              "In communities holding the relevant Latin right, local magistracy could convert civic service and wealth into Roman status.",
            startingStatus: "A local notable in a Latin-status municipality",
            route: "Election and completion of a qualifying municipal magistracy",
            rights: "Roman citizenship for the officeholder under the community’s grant",
            limit: "The path privileged property holders able to bear costly local office",
          },
          {
            id: "imperial-grant",
            label: "Imperial grant",
            detail:
              "An emperor could grant citizenship to an individual, family, military unit or whole community for service and political advantage.",
            startingStatus: "A provincial individual or community with local standing",
            route: "Petition, patronage, service or collective imperial decision",
            rights: "Recognised Roman status alongside continuing local citizenship",
            limit: "Access depended on power, patrons and imperial judgment until AD 212",
          },
        ],
      },
    },
    {
      id: "the-name-crosses-the-empire",
      actId: "provinces-enter-name",
      order: 12,
      period: "AD 117–212",
      place: "Britannia · the Danube · North Africa · Egypt · Syria",
      title: "The Roman Name Crosses the Empire",
      thesis:
        "By the third century, provincial citizens, cities and armies had carried Rome far beyond Italy before one decree made citizenship the normal status of the free population.",
      body: [
        "A traveller can move from a British fort through Gallic towns, Alpine roads, Danubian camps, Greek cities and Syrian markets without entering a culturally uniform world. Latin dominates official life across much of the west; Greek carries administration and education across much of the east. Local languages, names, cults, food and law continue. What connects the route is a hierarchy of recognised cities, governors, military commands, taxes and appeals under the emperor.",
        "The ruling class itself changes origin. Men from Spain, Gaul, North Africa and the eastern provinces enter the Senate; Trajan and Hadrian come from a senatorial family established in Italica, while later dynasties draw power from African and Syrian networks. Provincial birth does not make an emperor representative of ordinary provincial people. It shows that access to the centre no longer requires ancestral roots in the old Roman nobility.",
        "In AD 212, Caracalla issues the measure known as the Constitutio Antoniniana. A damaged Greek papyrus from Egypt preserves part of its wording. The decree granted Roman citizenship to almost all free inhabitants of the empire. The exact treatment of dediticii in the fragment remains disputed. Ancient testimony associates the measure with taxes; scholars also examine military, legal, religious and political purposes. No single motive is securely proved by the surviving text.",
        "The grant transforms citizenship by making it common. It expands the reach of Roman private law and brings new citizens within taxes attached to citizen transactions, while local law and identity continue in practice. The line between citizen and non-citizen loses much of its old organising force; divisions between free and enslaved, wealthy and poor, officeholder and subject remain severe. Rome has scaled the civic name of one city across an empire, creating the legal population that the Christian emperors will inherit.",
      ],
      image: `${imageRoot}/12-name-crosses-empire.avif`,
      mobileImage: `${imageRoot}/12-name-crosses-empire-mobile.avif`,
      imageAlt:
        "A courier carries Caracalla’s citizenship decree through a crowded multilingual provincial city where soldiers, merchants, families and officials gather under a worn arch.",
      imagePosition: "62% center",
      mobileImagePosition: "55% center",
      visualTone: "common-name",
      side: "right",
      sourceIds: ["giss-40", "campbell-status-2025", "coskun-2021", "eck-2021", "british-museum-legion-2024"],
      evidence: [
        "P.Giss. 40 preserves a fragmentary Greek version of Caracalla’s edict; restoration of its exception clause and the emperor’s motives remain disputed.",
        "Names, military diplomas, municipal careers, senatorial origins and legal documents show citizenship spreading widely before AD 212 and local identities continuing afterward.",
      ],
      map: { x: 55, y: 57 },
      interaction: {
        kind: "roman-trace",
        prompt: "Read the reach of AD 212",
        accessibleSummary:
          "Three stops distinguish the many provincial citizens already inside Roman law, the free inhabitants admitted by Caracalla and the hierarchies the grant did not remove.",
        stops: [
          {
            id: "already-inside",
            label: "Already inside",
            period: "before AD 212",
            detail:
              "Military service, manumission, municipal office and imperial grants had already created large provincial populations of Roman citizens.",
            mechanism: "Individual and collective routes extend status over generations",
            consequence: "The decree enters an empire where citizenship is widespread but incomplete",
          },
          {
            id: "common-grant",
            label: "Common grant",
            period: "AD 212",
            detail:
              "Caracalla’s edict granted Roman citizenship to almost all free inhabitants of the empire; the fragmentary exception concerning dediticii remains disputed.",
            mechanism: "One imperial decision changes the normal legal status of free subjects",
            consequence: "Citizen law becomes a common floor across culturally different provinces",
          },
          {
            id: "limits-remain",
            label: "Limits remain",
            period: "after AD 212",
            detail:
              "The decree did not free enslaved people, equalise wealth, open office to everyone or erase local laws and identities.",
            mechanism: "A shared civic status sits inside older social and economic hierarchies",
            consequence: "Roman citizenship expands without producing social equality",
          },
        ],
      },
    },
  ],
};
