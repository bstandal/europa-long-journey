import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/papal-revolution";

export const papalRevolution: ChapterDefinition = {
  slug: "papal-revolution",
  number: "08",
  title: "The Papal Revolution",
  openingTitleLines: ["The", "Papal", "Revolution"],
  period: "AD 1046–1123",
  claim:
    "The struggle to free ecclesiastical office from lay possession turned pope, emperor, bishops and princes into rival claimants under law. Worms divided spiritual investiture from temporal regalia, leaving Latin Europe with two organised jurisdictions that neither side could fully absorb.",
  openingClaim:
    "Pope, emperor, bishops and princes learned to rule through rival courts that neither side could absorb.",
  theme: {
    id: "papal",
    label: "Two courts, one Christendom",
  },
  openingAction: "Enter the contested order",
  mapLabel:
    "The synods, courts, bishoprics and negotiated settlements that divided one Christian order",
  routeImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Registers · letters · synodal decrees · election rules · polemics · privileges · chronicles · concordats",
  acts: [
    {
      id: "reform-rome",
      number: "I",
      label: "Reform moves to Rome",
      period: "AD 1046–1059",
      title: "A Restored Papacy Learns to Govern",
      detail:
        "An emperor clears a Roman succession crisis, then reforming popes build synods, legations, privileges and a new election procedure that can act beyond Rome.",
    },
    {
      id: "two-burdens",
      number: "II",
      label: "One bishop, two burdens",
      period: "AD 1057–1075",
      title: "Sacred Office Carries Public Power",
      detail:
        "Urban reform and the material duties of bishops make appointment the point where pastoral authority, landed government and royal service meet.",
    },
    {
      id: "broken-communion",
      number: "III",
      label: "King and pope break communion",
      period: "AD 1076–1085",
      title: "Judgment Becomes a Contest for Obedience",
      detail:
        "Pope, king, bishops and princes turn censures into rival claims, while penance, rebellion and war expose how much enforcement depends on political allies.",
    },
    {
      id: "divided-ceremony",
      number: "IV",
      label: "The ceremony is divided",
      period: "AD 1090s–1123",
      title: "Compromise Separates the Instruments",
      detail:
        "Settlements in France and England prepare a distinction that imprisonment cannot force: canonical election and spiritual investiture remain ecclesiastical, while rulers confer temporal regalia.",
    },
  ],
  ending: {
    period: "AD 1123",
    title: "One order now contains rival jurisdictions",
    detail:
      "The First Lateran Council received the settlement made at Worms. Cathedral chapters could claim canonical election, rulers could demand the services attached to regalia, and papal and royal courts each kept records with which to defend their competence. Neither institution withdrew from public government. Their coexistence made jurisdiction something that monasteries, communes, guilds and universities could also seek, define and preserve.",
    image: `${imageRoot}/13-two-jurisdictions-endure.avif`,
    nextPeriod: "AD 1000–1300",
  },
  returnHash: "papal-revolution",
  nextHash: "society-beyond-kin",
  nextTitle: "A Society Beyond Kin",
  movements: [
    {
      id: "emperor-judges-three-popes",
      actId: "reform-rome",
      order: 1,
      period: "AD 1046",
      place: "Sutri and Rome · central Italy",
      title: "The Emperor Judges Three Popes",
      thesis:
        "Henry III ended a Roman succession crisis as protector of the Church, giving reformers a papacy whose dependence on royal intervention was plain.",
      body: [
        "Henry III crossed the Alps to receive the imperial crown and found three men associated with the papal office. Benedict IX, Sylvester III and Gregory VI rested on different elections, factions and transactions. The synod held at Sutri judged Sylvester and Gregory; Gregory’s acquisition of the office from Benedict made his position indefensible to reformers who treated the purchase of sacred office as simony. Benedict was removed when the proceedings continued at Rome.",
        "The king did not arrive as an enemy of ecclesiastical reform. He convened bishops, supplied coercive authority and helped raise Suidger of Bamberg as Clement II. The new pope crowned Henry emperor on Christmas Day. German and Lotharingian churchmen then entered Roman government with programmes of clerical discipline and opposition to simony. Imperial protection gave reform a centre from which it could act.",
        "The sequence survives through accounts written from different interests, and the exact juridical form of every removal remains contested. Its political meaning is clearer. A sacred emperor had restored order in the Roman Church by judging its claimants. The institutions rebuilt after 1046 would soon argue that no lay protector could possess the offices he had rescued.",
      ],
      image: `${imageRoot}/01-emperor-judges-three-popes.avif`,
      imageAlt:
        "A papal reform synod and a royal-princely court work in separate Romanesque chambers while a messenger carries a sealed document between them.",
      imagePosition: "center center",
      mobileImagePosition: "50% 78%",
      visualTone: "two-courts",
      side: "left",
      sourceIds: ["cushing-2005", "blumenthal-1991"],
      evidence: [
        "Narratives of Sutri agree on a papal succession crisis and decisive royal intervention, while differing over the legal form and sequence of the judgments.",
        "Clement II’s coronation of Henry III in Rome joined reforming papal government to imperial protection at the chapter’s starting point.",
      ],
      map: { x: 50, y: 68 },
    },
    {
      id: "reformers-build-government",
      actId: "reform-rome",
      order: 2,
      period: "AD 1049–1054",
      place: "Rome, Reims and Mainz · a travelling papal court",
      title: "Reformers Build a Government in Rome",
      thesis:
        "Leo IX made reform portable through personnel, synods, legates and written privileges, turning Roman primacy into repeated administrative action.",
      body: [
        "Bruno of Toul entered Rome as Leo IX in 1049 with reformers drawn from Lotharingia and Burgundy. He did not govern from one chair. At councils in Rome, Pavia, Reims and Mainz, clerics faced accusations of simony and breaches of clerical discipline. The pope’s journeys made local bishops answer inside assemblies that claimed authority from the apostolic see.",
        "Travel alone could not sustain that reach. Leo and his successors used legates who carried mandates, heard disputes and convened councils; privileges that recorded papal protection and exemptions; and a curial household able to preserve decisions. Cardinal clergy acquired larger roles around the Roman church. Reform became a chain of authorised acts: a petition arrived, a case was heard, a document was sealed and a messenger returned with terms that a local institution had reason to keep.",
        "The system remained small, personal and vulnerable. Legates negotiated with rulers and bishops whose cooperation they needed, while Roman nobles and the city’s clergy still shaped papal elections. Its consequence was institutional. The papacy could now intervene far from Rome through recognisable offices and documents rather than waiting for a ruler to bring the Church together.",
      ],
      image: `${imageRoot}/02-reformers-build-government.avif`,
      imageAlt:
        "Clerics, cardinal clergy and a papal legate organise registers and sealed instructions in a rough Romanesque hall.",
      imagePosition: "38% center",
      visualTone: "register-and-seal",
      side: "right",
      sourceIds: ["cushing-2005", "howe-2025"],
      evidence: [
        "Papal itineraries, council records and privileges reveal a government operating through travel, delegated authority and authenticated writing.",
        "The reform circle included figures and institutions formed before Gregory VII; the later movement cannot be reduced to one pope’s programme.",
      ],
      map: { x: 50, y: 68 },
      interaction: {
        kind: "papal-court",
        prompt: "Build a reform papacy from four working instruments",
        accessibleSummary:
          "Four states show how synods, legates, cardinal clergy and written privileges let Roman reform act across distance.",
        states: [
          {
            id: "synod",
            label: "Synod",
            period: "assembly",
            detail:
              "A pope gathers bishops, states accusations and turns reform into a public judgment that local churches must answer.",
            office: "Pope among assembled bishops",
            instrument: "Citation, testimony, canon and sentence",
            consequence: "Simony and clerical discipline become matters for a wider forum",
          },
          {
            id: "legate",
            label: "Legate",
            period: "delegation",
            detail:
              "A named representative carries papal authority into a region where the pope cannot remain.",
            office: "Legate acting by a defined commission",
            instrument: "Mandate, council, negotiation and report",
            consequence: "Roman decisions acquire agents beyond the city",
          },
          {
            id: "cardinalate",
            label: "Cardinalate",
            period: "household",
            detail:
              "Cardinal bishops and clergy form a more durable circle around papal worship, counsel and succession.",
            office: "Cardinal clergy of the Roman church",
            instrument: "Liturgy, counsel, subscription and election",
            consequence: "The papal court gains institutional memory between pontificates",
          },
          {
            id: "privilege",
            label: "Privilege",
            period: "record",
            detail:
              "A sealed privilege gives a monastery or church a portable statement of protection, exemption or right.",
            office: "Papal notaries and petitioning institutions",
            instrument: "Vellum, formula, subscription and seal",
            consequence: "Authority can be preserved, copied and produced in a later dispute",
          },
        ],
      },
    },
    {
      id: "cardinals-claim-election",
      actId: "reform-rome",
      order: 3,
      period: "AD 1059",
      place: "The Lateran · Rome",
      title: "Cardinals Claim the Election",
      thesis:
        "Nicholas II’s election decree gave cardinal bishops the initiating role in choosing a pope and reduced the succession’s exposure to Roman faction and royal possession.",
      body: [
        "Papal reform required a succession that could reproduce it. The decree issued under Nicholas II in 1059 directed cardinal bishops to consider a candidate first, then bring in other cardinal clergy and seek the assent of the remaining clergy and people. It preferred a member of the Roman church but allowed another suitable candidate when necessity required.",
        "The text did not create the later conclave, and its clauses concerning royal honour have an uncertain textual and political history. Roman acclamation, aristocratic force and imperial influence did not disappear. The decree instead placed a procedural claim inside the election: the Roman church possessed an order of action that no family or ruler could simply replace with nomination.",
        "Nicholas also secured Norman support in southern Italy. The papacy was learning to combine electoral rule with new political protection. A reform court once restored by a German emperor could now survive by defining who acted first, recording that order and bargaining with powers outside the old imperial relationship.",
      ],
      image: `${imageRoot}/03-cardinals-claim-election.avif`,
      imageAlt:
        "Cardinal bishops and Roman clergy inspect and seal an election decree while nobles and citizens wait beyond a round-arched portico.",
      imagePosition: "66% center",
      visualTone: "election-order",
      side: "left",
      sourceIds: ["cushing-2005", "howe-2025"],
      evidence: [
        "The 1059 decree survives in differing recensions; its basic ordering of cardinal bishops, other cardinal clergy, and wider assent is secure.",
        "Later conclave procedure must not be projected backwards onto an eleventh-century election still shaped by Roman and external powers.",
      ],
      map: { x: 50, y: 69 },
      interaction: {
        kind: "papal-trace",
        prompt: "Trace how an election acquires an order",
        accessibleSummary:
          "Three stops distinguish the initiating role of cardinal bishops, wider clerical participation and public assent.",
        stops: [
          {
            id: "discern",
            label: "Discern",
            period: "first",
            detail:
              "Cardinal bishops consider the candidate before the choice enters the wider Roman arena.",
            instrument: "Prior deliberation among a defined group",
            consequence: "The succession gains a procedural beginning",
            inheritance: "Election becomes an institutional act rather than an empty acclamation",
          },
          {
            id: "join",
            label: "Join",
            period: "then",
            detail:
              "Other cardinal clergy join the choice and connect it to the worship and offices of the Roman church.",
            instrument: "Clerical counsel and subscription",
            consequence: "A broader ecclesiastical body owns the decision",
            inheritance: "The papal household can reproduce its leadership",
          },
          {
            id: "assent",
            label: "Assent",
            period: "after",
            detail:
              "Clergy and people retain a public place without receiving an unrestricted power to impose a candidate.",
            instrument: "Acclamation and reception",
            consequence: "Procedure acknowledges Rome without surrendering to one faction",
            inheritance: "Consent is ordered rather than erased",
          },
        ],
      },
    },
    {
      id: "milan-streets-judge-clergy",
      actId: "two-burdens",
      order: 4,
      period: "AD 1057–1075",
      place: "Milan · streets, churches and the archiepiscopal court",
      title: "Milan’s Streets Judge the Clergy",
      thesis:
        "The Pataria made clerical office a public urban question and pulled Roman reform into a contest over who could judge Milan’s church.",
      body: [
        "Milan’s reform did not descend from Rome into a passive city. Ariald, Landulf Cotta and later the lay captain Erlembald mobilised clergy and townspeople against simony and clerical marriage. Supporters refused ministries they considered polluted, gathered in streets and churches, and challenged an archiepiscopal establishment embedded in noble families and the city’s own liturgical tradition.",
        "Violence, excommunication and rival claims followed. Pope Alexander II supported the Pataria and supplied Erlembald with a banner; opponents defended local custom and the authority of Archbishop Guido. Artisans, lesser clergy, magnates and neighbourhoods acted for their own reasons. Reform gave urban groups a language with which to judge officeholders, while papal backing gave one party an appeal beyond Milan.",
        "The dispute over Guido’s succession sharpened the institutional issue. Henry IV invested Godfrey as archbishop; reformers supported Atto, elected by their party and recognised by Rome. Control of a metropolitan see now linked a city’s internal struggle to the king’s government and the pope’s claim. Milan helped turn reform into an open conflict over appointment.",
      ],
      image: `${imageRoot}/04-milan-streets-judge-clergy.avif`,
      imageAlt:
        "Artisans, townspeople and clergy gather around a Pataria preacher before a rough eleventh-century Milanese basilica.",
      imagePosition: "40% center",
      visualTone: "street-and-cross",
      side: "right",
      sourceIds: ["cushing-2005", "cowdrey-1998"],
      evidence: [
        "Accounts of the Pataria were written by participants and opponents who disagreed over legitimacy, violence and Milanese custom.",
        "Papal letters, local narratives and the disputed archiepiscopal succession show urban agency joining the wider investiture conflict.",
      ],
      map: { x: 48, y: 63 },
      interaction: {
        kind: "papal-trace",
        prompt: "Follow reform from a sermon into a jurisdictional claim",
        accessibleSummary:
          "Three stops connect public discipline, papal appeal and a disputed episcopal election.",
        stops: [
          {
            id: "discipline",
            label: "Discipline",
            period: "street",
            detail:
              "Lay and clerical supporters treat the conduct of clergy as a condition of valid ministry.",
            instrument: "Preaching, oath, boycott and assembly",
            consequence: "Office becomes answerable to organised public pressure",
            inheritance: "Urban association enters church reform",
          },
          {
            id: "appeal",
            label: "Appeal",
            period: "Rome",
            detail:
              "Papal support gives the reform party authority beyond Milan’s archiepiscopal hierarchy.",
            instrument: "Legates, letters, censures and a papal banner",
            consequence: "A local dispute gains an external court",
            inheritance: "Appeal strengthens Roman jurisdiction",
          },
          {
            id: "succession",
            label: "Succession",
            period: "1070s",
            detail:
              "Rival archbishops embody incompatible royal, papal and urban claims to a single see.",
            instrument: "Election, investiture and recognition",
            consequence: "Appointment becomes the point of collision",
            inheritance: "Milan enters the conflict between Henry and Gregory",
          },
        ],
      },
    },
    {
      id: "bishop-serves-altar-crown",
      actId: "two-burdens",
      order: 5,
      period: "c. AD 1060–1075",
      place: "Speyer · an imperial bishop’s church and estates",
      title: "A Bishop Serves Altar and Crown",
      thesis:
        "A bishop received sacramental office and governed lands, courts and royal obligations, so appointment could not be separated by choosing one loyalty.",
      body: [
        "The bishop at the altar ordained clergy, guarded doctrine, presided over worship and carried pastoral responsibility for a diocese. The same man held an episcopal estate with tenants, tolls, immunities and rights of justice. He might advise the king, host the travelling court, supply mounted service, keep a fortress or administer territory. Cathedral clergy and local elites depended on how he distributed offices and property.",
        "Kings valued bishops because their office did not pass to legitimate heirs and because educated clerics could govern. Royal protection and gifts made many churches powerful; rulers expected service in return. A king’s presentation of ring and staff made that relationship visible. Reformers increasingly argued that symbols of pastoral marriage and care could not come from a lay hand, especially when access to office involved payment or political bargain.",
        "The conflict did not oppose spiritual people to secular people. Bishops, cathedral chapters, princes, monks and royal servants divided across both camps. The office itself joined different kinds of authority. Any settlement had to distinguish the sacramental act from the public resources and obligations attached to the see without pretending that either side could abandon the bishop.",
      ],
      image: `${imageRoot}/05-bishop-serves-altar-crown.avif`,
      imageAlt:
        "An eleventh-century bishop stands between a cathedral altar and a royal court where charters, estate keys and a sceptre mark his public burdens.",
      imagePosition: "58% center",
      visualTone: "altar-and-regalia",
      side: "left",
      sourceIds: ["blumenthal-1991", "robinson-henry-1999"],
      evidence: [
        "Charters and narrative sources place bishops inside royal assemblies, estate government, justice and military obligation as well as sacramental office.",
        "Ring and staff acquired controversial meaning because a single ceremony appeared to transfer an office with both spiritual and temporal consequences.",
      ],
      map: { x: 47, y: 55 },
      interaction: {
        kind: "bishop-burden",
        prompt: "Open the four burdens carried by one bishop",
        accessibleSummary:
          "Four states distinguish sacramental office, landed regalia, public justice and royal service without asking the reader to choose a side.",
        states: [
          {
            id: "altar",
            label: "Altar",
            period: "ordination",
            detail:
              "Consecration makes a bishop responsible for teaching, sacraments, clergy and the care of a diocese.",
            possession: "A spiritual office expressed by ring, staff and laying on of hands",
            churchClaim: "Only ecclesiastical authority can confer pastoral office",
            royalClaim: "The ruler protects the church in which the office operates",
            consequence: "A sacred act requires canonical legitimacy",
          },
          {
            id: "estate",
            label: "Estate",
            period: "possession",
            detail:
              "The see controls lands, rents, tolls, immunities and buildings needed to sustain its household and worship.",
            possession: "Temporal resources later described as regalia",
            churchClaim: "Church property must not be bought or treated as lay inheritance",
            royalClaim: "Royal gifts and protection carry enforceable obligations",
            consequence: "Property makes appointment politically valuable",
          },
          {
            id: "court",
            label: "Court",
            period: "government",
            detail:
              "A bishop hears disputes, preserves charters and exercises jurisdiction over people and places.",
            possession: "Courts, immunities and delegated public rights",
            churchClaim: "The office needs freedom to judge clerical and ecclesiastical causes",
            royalClaim: "Public jurisdiction remains inside the king’s peace",
            consequence: "Two forums can claim competence over one dispute",
          },
          {
            id: "service",
            label: "Service",
            period: "realm",
            detail:
              "The bishop advises the ruler and supplies hospitality, administration and material service from the see.",
            possession: "A place in assemblies and a bundle of royal obligations",
            churchClaim: "Service cannot turn pastoral office into a royal appointment",
            royalClaim: "The realm cannot lose the government attached to episcopal lands",
            consequence: "The settlement must divide acts without dissolving the office",
          },
        ],
      },
    },
    {
      id: "gregory-forbids-kings-hand",
      actId: "two-burdens",
      order: 6,
      period: "AD 1073–1075",
      place: "The Lateran and the royal court · Rome and Germany",
      title: "Gregory Forbids the King’s Hand",
      thesis:
        "Gregory VII joined reform discipline to obedience toward Rome and treated Henry’s appointments as acts subject to apostolic judgment.",
      body: [
        "Hildebrand became Gregory VII in 1073 after decades inside the reform circle. He expanded the use of legates, letters and Roman synods and demanded that bishops obey judgments from the apostolic see. His register records the propositions later called Dictatus papae in 1075. They include exceptional claims about Roman authority, but the list was a register entry, not a constitution formally promulgated to all Christendom.",
        "Lay investiture emerged inside a wider struggle over simony, clerical discipline, disputed bishops and Henry’s relations with excommunicated counsellors. The chronology of Gregory’s early prohibition is not simple: the first surviving general decrees against lay investiture are later, although his government was already rejecting royal appointment in particular cases. Milan brought the issue directly into the correspondence.",
        "In December 1075 Gregory warned Henry in the language of pastoral correction and obedience. The king answered from a court that understood episcopal appointment as part of sacred kingship and government. The argument was moving beyond a ceremony. Each court claimed the authority to judge whether the other had acted within the Christian order.",
      ],
      image: `${imageRoot}/06-gregory-forbids-kings-hand.avif`,
      imageAlt:
        "Pope Gregory VII dictates a letter beside a register while a royal messenger waits under a rough Romanesque arch.",
      imagePosition: "38% center",
      visualTone: "letter-and-warning",
      side: "right",
      sourceIds: ["cowdrey-1998", "howe-2025", "investiture-documents"],
      evidence: [
        "Gregory’s register preserves letters, synodal acts and the Dictatus papae propositions in the working archive of his pontificate.",
        "The surviving evidence does not support treating Dictatus papae as a promulgated constitution or every disputed appointment as one uniform policy from 1073.",
      ],
      map: { x: 50, y: 69 },
      interaction: {
        kind: "papal-trace",
        prompt: "Trace how correction becomes a claim to judge",
        accessibleSummary:
          "Three stops connect reform discipline, a Roman register and a royal appointment dispute.",
        stops: [
          {
            id: "discipline",
            label: "Correct",
            period: "synod",
            detail:
              "Roman councils condemn practices and summon bishops to answer before a wider ecclesiastical authority.",
            instrument: "Canon, summons, censure and absolution",
            consequence: "Reform depends on obedience to judgments",
            inheritance: "The papacy acts as a court of correction",
          },
          {
            id: "register",
            label: "Record",
            period: "1075",
            detail:
              "Claims entered in the papal register state an expansive understanding of Roman authority.",
            instrument: "Dictatus papae as a register entry",
            consequence: "Principles are preserved inside an administrative archive",
            inheritance: "A court can cite and develop its own jurisdiction",
          },
          {
            id: "appointment",
            label: "Judge",
            period: "Milan",
            detail:
              "Royal action over bishops is treated as conduct that Rome can examine and condemn.",
            instrument: "Letter, legate and threatened censure",
            consequence: "Sacred kingship is no longer immune from papal process",
            inheritance: "Appointment becomes a jurisdictional conflict",
          },
        ],
      },
    },
    {
      id: "king-pope-depose",
      actId: "broken-communion",
      order: 7,
      period: "January–February AD 1076",
      place: "Worms and Rome · two assemblies",
      title: "King and Pope Depose One Another",
      thesis:
        "Henry’s bishops rejected Gregory, and Gregory excommunicated Henry and released subjects from their oaths, forcing every sentence to seek political enforcement.",
      body: [
        "At Worms in January 1076, Henry and a group of bishops declared that Gregory had lost the papal office. Their letter attacked his election, government and treatment of bishops and ordered him to descend. The king wrote as one ordained by God, defended the traditional protection of the Church and denied that Gregory had authority to strip him of kingship.",
        "At the Roman Lenten synod, Gregory answered before Saint Peter. He excommunicated Henry, forbade him to govern Germany and Italy and released Christians from oaths of service. The sentence joined a spiritual censure to a political claim of extraordinary reach. Its words did not remove the king by themselves. Bishops, princes and communities had to decide whether to observe the ban and how to act on the release of fidelity.",
        "German princes used the breach to reopen their own disputes with Henry. At Tribur and Oppenheim they required him to secure absolution and prepared a meeting at Augsburg under papal judgment. Excommunication mattered because it altered alliances and made obedience contestable. Both courts had issued universal language; enforcement now belonged to a fragmented political field.",
      ],
      image: `${imageRoot}/07-king-pope-depose.avif`,
      imageAlt:
        "Opposed assemblies in Worms and Rome dictate letters of deposition across tables crowded with bishops, seals and witnesses.",
      imagePosition: "60% center",
      visualTone: "opposed-sentences",
      side: "left",
      sourceIds: ["investiture-documents", "robinson-henry-1999", "cowdrey-1998"],
      evidence: [
        "The letters of Henry, the bishops and Gregory preserve opposed accounts of legitimate office and obedience rather than neutral transcripts of the conflict.",
        "The political effect of excommunication depended on princely action, episcopal reception and Henry’s capacity to retain followers.",
      ],
      map: { x: 47, y: 55 },
    },
    {
      id: "road-ends-canossa",
      actId: "broken-communion",
      order: 8,
      period: "January AD 1077",
      place: "Canossa · Matilda of Tuscany’s castle",
      title: "The Road Ends at Canossa",
      thesis:
        "Henry’s penance restored communion before the princes could judge him, but absolution settled neither the German kingship nor the boundary between the two powers.",
      body: [
        "Henry crossed the Alps in winter with Queen Bertha and a small following while Gregory travelled north toward the proposed assembly at Augsburg. The pope withdrew to Canossa, a fortress of Matilda of Tuscany. Matilda and Abbot Hugh of Cluny, Henry’s godfather, mediated between a penitent king, a cautious pope and German princes expecting a political judgment.",
        "Gregory’s own letter says that Henry waited for three days before the gate without royal dress and sought mercy with tears until those present pressed the pope to receive him. The language follows penitential convention and serves Gregory’s account to the German princes. Inside, Henry swore terms and received absolution. The sacramental act returned him to communion.",
        "Absolution also frustrated opponents who had relied on the ban, but it did not decide whether Henry remained a legitimate king. Princes elected Rudolf of Rheinfelden in March, and civil war followed. Canossa revealed a papacy capable of imposing penance on an anointed ruler and a king capable of using penance to change the political field. Neither side absorbed the other’s authority.",
      ],
      image: `${imageRoot}/08-road-ends-canossa.avif`,
      imageAlt:
        "Henry IV waits in winter before Canossa while Matilda of Tuscany, Hugh of Cluny and clerics mediate inside the gatehouse.",
      imagePosition: "54% center",
      visualTone: "snow-and-absolution",
      side: "right",
      sourceIds: ["gregory-register", "cowdrey-1998", "robinson-henry-1999"],
      evidence: [
        "Gregory’s Registrum IV.12 reports penance, mediation, an oath and absolution while telling the German princes that no final political decision had been made.",
        "Later visual memory intensified the snowbound encounter; the secure institutional distinction is between restored communion and unresolved kingship.",
      ],
      map: { x: 48, y: 63 },
      interaction: {
        kind: "canossa-sequence",
        prompt: "Separate what happened at Canossa from what remained open",
        accessibleSummary:
          "Four states distinguish mediation, penance, absolution and the unresolved German kingship.",
        states: [
          {
            id: "mediation",
            label: "Mediate",
            period: "arrival",
            detail:
              "Matilda of Tuscany and Hugh of Cluny connect parties who cannot safely meet without trusted intermediaries.",
            actor: "Matilda, Hugh, Henry and Gregory",
            act: "Messages and assurances pass across the gate",
            politicalEffect: "A meeting becomes possible before Augsburg",
            unsettled: "What judgment the German princes will accept",
          },
          {
            id: "penance",
            label: "Penance",
            period: "three days",
            detail:
              "Henry adopts the ritual position of a Christian seeking release from ecclesiastical censure.",
            actor: "The excommunicated king as penitent",
            act: "Waiting, petition and sworn submission to terms",
            politicalEffect: "Refusal becomes harder for a pastor to sustain",
            unsettled: "Whether penitence confirms or compromises royal authority",
          },
          {
            id: "absolution",
            label: "Absolve",
            period: "28 January",
            detail:
              "Gregory restores Henry to communion after oath and mediation.",
            actor: "The pope as dispenser of absolution",
            act: "Sacramental reconciliation",
            politicalEffect: "The ban can no longer organise opposition in the same way",
            unsettled: "The validity of Henry’s rule",
          },
          {
            id: "kingship",
            label: "Kingship",
            period: "after Canossa",
            detail:
              "German princes continue their political process and elect a rival king.",
            actor: "Princes, bishops and armed followings",
            act: "Election, alliance and civil war",
            politicalEffect: "Absolution changes the contest without ending it",
            unsettled: "Who can command the realm and invest its bishops",
          },
        ],
      },
    },
    {
      id: "henry-takes-rome",
      actId: "broken-communion",
      order: 9,
      period: "AD 1080–1085",
      place: "Rome and Salerno · war around the apostolic see",
      title: "Henry Takes Rome; Gregory Dies in Exile",
      thesis:
        "Military victory put Henry in Rome and an imperial pope at the altar, while Gregory’s exile showed that papal jurisdiction had outrun papal control of the city.",
      body: [
        "Gregory again excommunicated and declared against Henry in 1080. Henry’s supporters answered at Brixen by choosing Wibert of Ravenna, later Clement III. The dispute now had rival kings, rival popes and armed campaigns. Bishops changed sides under local pressure; princes pursued dynastic and territorial interests; universal claims travelled through unstable coalitions.",
        "Henry entered Rome in 1084. Clement III crowned him emperor in Saint Peter’s. Norman forces under Robert Guiscard rescued Gregory, but their sack of parts of the city turned Romans against the pope they had saved. Gregory left with his allies and died at Salerno in 1085, unable to return to his see. Canossa had not placed the emperor beneath permanent papal command.",
        "The reform papacy nevertheless survived Gregory’s defeat. Cardinals, monasteries, legates and allied rulers preserved offices and arguments that did not depend on possession of Rome every day. Clement also retained support and institutional standing for years. Rival obediences proved that a jurisdiction could survive through records, consecrations and networks even when force decided who occupied a building.",
      ],
      image: `${imageRoot}/09-henry-takes-rome.avif`,
      imageAlt:
        "Henry IV and Clement III hold a tense imperial coronation in a smoky Roman basilica while messengers report fighting outside.",
      imagePosition: "64% center",
      visualTone: "occupied-basilica",
      side: "left",
      sourceIds: ["cowdrey-1998", "robinson-henry-1999", "robinson-papacy-1990"],
      evidence: [
        "Narratives, letters and subscriptions document competing papal obediences rather than a simple sequence of universally accepted pontiffs.",
        "Gregory died in exile after Henry’s Roman coronation; his institutional programme endured without converting his final years into political victory.",
      ],
      map: { x: 50, y: 69 },
      interaction: {
        kind: "papal-trace",
        prompt: "Follow authority when possession of Rome changes",
        accessibleSummary:
          "Three stops distinguish military occupation, sacramental recognition and institutional survival.",
        stops: [
          {
            id: "occupy",
            label: "Occupy",
            period: "1084",
            detail:
              "Henry’s army gives his party access to Rome and Saint Peter’s.",
            instrument: "Siege, negotiation and armed entry",
            consequence: "Force determines which court can perform public acts in the city",
            inheritance: "Territorial possession remains indispensable",
          },
          {
            id: "crown",
            label: "Crown",
            period: "Easter",
            detail:
              "Clement III crowns Henry, joining a rival papal obedience to imperial legitimacy.",
            instrument: "Election, consecration and coronation",
            consequence: "Ritual authority cannot be separated from recognition",
            inheritance: "Competing institutions can produce competing validities",
          },
          {
            id: "survive",
            label: "Survive",
            period: "after 1085",
            detail:
              "Gregory’s allies continue through cardinals, monasteries, legates and reform rulers.",
            instrument: "Networks, registers, ordinations and alliance",
            consequence: "Exile does not erase an organised jurisdiction",
            inheritance: "The conflict outlives both Gregory and Henry",
          },
        ],
      },
    },
    {
      id: "compromise-beyond-empire",
      actId: "divided-ceremony",
      order: 10,
      period: "AD 1090s–1107",
      place: "France and England · negotiated royal churches",
      title: "Compromise Advances Beyond the Empire",
      thesis:
        "French practice and the English settlement showed that rulers could retain political influence while surrendering the spiritual symbols of investiture.",
      body: [
        "France produced no prolonged conflict matching Germany’s. Reformers pressed for canonical election and opposed lay investiture, while bishops and royal government continued to negotiate appointments. Thinkers such as Ivo of Chartres helped distinguish the sacramental office from the temporal possessions attached to a bishopric. Practice could separate moments that polemic treated as one indivisible act.",
        "In England, Archbishop Anselm and King Henry I disputed whether bishops and abbots could receive ring and staff from the king. The settlement announced at London in 1107 ended royal investiture with those symbols. The king retained homage from prelates for their temporal holdings, and royal influence over elections remained substantial. Neither church office nor royal government withdrew from the relationship.",
        "These arrangements mattered because they preserved both institutions. A canonical election could be recognised as ecclesiastical; a ruler could receive fidelity and enforce the obligations of lands. The distinction did not create a private religious sphere and a secular state. It created separate acts through which two jurisdictions met around the same office.",
      ],
      image: `${imageRoot}/10-compromise-beyond-empire.avif`,
      imageAlt:
        "A bishop-elect moves between cathedral clergy and King Henry I’s court as ring, staff and a charter of temporal lands are handled separately.",
      imagePosition: "44% center",
      visualTone: "homage-and-office",
      side: "right",
      sourceIds: ["blumenthal-1991", "robinson-papacy-1990", "cowdrey-1998"],
      evidence: [
        "French arrangements varied by case and did not form one single concordat; their significance lies in the practical distinction of spiritual office and temporal possession.",
        "The English settlement of 1107 ended royal investiture with ring and staff while preserving homage and strong royal influence.",
      ],
      map: { x: 41, y: 53 },
    },
    {
      id: "emperor-makes-pope-prisoner",
      actId: "divided-ceremony",
      order: 11,
      period: "AD 1111",
      place: "Saint Peter’s and a royal camp · Rome",
      title: "Henry V Makes the Pope a Prisoner",
      thesis:
        "An attempt to strip bishops of regalia collapsed at the coronation, and Henry V’s coercion proved that a forced privilege could not settle what both governments needed.",
      body: [
        "Pope Paschal II and Henry V attempted a stark bargain. The emperor would renounce investiture; bishops and abbots would return regalia and public rights received from the crown. When the terms were read before the imperial coronation in Saint Peter’s, prelates and princes resisted the loss of lands, courts and services on which both church households and royal government depended.",
        "The ceremony broke into disorder. Henry seized Paschal and members of his court and held them until the pope conceded imperial investiture and performed the coronation. The resulting privilege carried the form of papal authorization and the fact of captivity. Reform councils soon condemned it, and Paschal struggled to defend an act extracted under force.",
        "The failed bargain exposed the material centre of the controversy. Bishops could not become landless spiritual officers without dismantling established government. The emperor could not create an accepted spiritual investiture through custody of the pope. A durable settlement required public acts that each institution could recognise as its own.",
      ],
      image: `${imageRoot}/11-emperor-makes-pope-prisoner.avif`,
      imageAlt:
        "Henry V’s armed retainers close around Pope Paschal II and cardinals after a failed coronation agreement in Saint Peter’s.",
      imagePosition: "62% center",
      visualTone: "captivity-and-privilege",
      side: "left",
      sourceIds: ["investiture-documents", "blumenthal-1991", "robinson-papacy-1990"],
      evidence: [
        "The 1111 negotiations survive as formal texts whose proposed surrender of regalia must be read alongside the resistance and captivity that followed.",
        "Subsequent reform assemblies rejected the coerced privilege, demonstrating that a document required institutional reception as well as a seal.",
      ],
      map: { x: 50, y: 69 },
      interaction: {
        kind: "papal-trace",
        prompt: "Test why the forced settlement fails",
        accessibleSummary:
          "Three stops connect the proposed surrender of regalia, papal captivity and the rejection of a coerced privilege.",
        stops: [
          {
            id: "surrender",
            label: "Surrender",
            period: "proposal",
            detail:
              "Prelates are asked to return the public rights and lands that support their offices and royal service.",
            instrument: "A reciprocal agreement tied to coronation",
            consequence: "Bishops and princes see established government threatened",
            inheritance: "Spiritual office cannot simply be made landless",
          },
          {
            id: "capture",
            label: "Capture",
            period: "force",
            detail:
              "Henry detains the pope and cardinals until they concede investiture and coronation.",
            instrument: "Armed custody and compelled consent",
            consequence: "The king obtains the act but damages its legitimacy",
            inheritance: "Possession of a person is not possession of a jurisdiction",
          },
          {
            id: "reject",
            label: "Reject",
            period: "reception",
            detail:
              "Councils condemn the privilege and refuse to let coercion define the Church’s rule.",
            instrument: "Synodal judgment and collective refusal",
            consequence: "The sealed concession cannot command stable obedience",
            inheritance: "Settlement needs recognition by both institutions",
          },
        ],
      },
    },
    {
      id: "worms-divides-ring-sceptre",
      actId: "divided-ceremony",
      order: 12,
      period: "AD 1122–1123",
      place: "Worms and the Lateran · empire and papal council",
      title: "Worms Divides Ring from Sceptre",
      thesis:
        "Two reciprocal instruments distinguished canonical election and spiritual investiture from the ruler’s grant of regalia while preserving royal presence and regional variation.",
      body: [
        "At Worms on 23 September 1122, Henry V renounced investiture with ring and staff and granted canonical election and free consecration. Pope Calixtus II allowed elections of bishops and abbots in the German kingdom to occur in the emperor’s presence without simony or violence. If a dispute arose, the ruler could assist the sounder party with metropolitan and provincial counsel.",
        "The temporal grant used a sceptre. In Germany, the elected bishop received regalia from the ruler before consecration; in other parts of the empire, he was to receive them within six months after consecration. The difference preserved distinct political conditions in Germany, Burgundy and Italy. Royal influence remained, and cathedral elections could still be contested. Ring and staff no longer expressed that influence.",
        "Worms was an exchange of promises, not a philosophical division of society. The First Lateran Council received the settlement in 1123. Pope, emperor, bishops and princes continued to govern the same Christian world through overlapping persons, lands and obligations. They now possessed a recognised distinction of acts with which each court could defend its competence.",
      ],
      image: `${imageRoot}/12-worms-divides-ring-sceptre.avif`,
      imageAlt:
        "At Worms, papal and imperial representatives exchange sealed instruments while ring and staff remain apart from a sceptre.",
      imagePosition: "50% center",
      visualTone: "ring-and-sceptre",
      side: "right",
      sourceIds: ["investiture-documents", "blumenthal-1991", "robinson-papacy-1990"],
      evidence: [
        "The surviving papal and imperial instruments contain reciprocal promises rather than one modern constitutional document.",
        "Different timing for the grant of regalia inside and outside the German kingdom prevents a single uniform ceremony from being projected across the empire.",
      ],
      map: { x: 47, y: 55 },
      interaction: {
        kind: "investiture-settlement",
        prompt: "Divide one investiture into acts both courts can recognise",
        accessibleSummary:
          "Four states distinguish election, spiritual investiture, temporal regalia and the regional timing preserved at Worms.",
        states: [
          {
            id: "election",
            label: "Elect",
            period: "chapter",
            detail:
              "The church chooses through a canonical election that must be free from simony and violence.",
            election: "Cathedral or monastic electors act canonically",
            spiritualAct: "Not yet conferred",
            temporalAct: "The ruler may be present in the German kingdom",
            limit: "Presence and counsel preserve influence without a right to use ring and staff",
          },
          {
            id: "spiritual",
            label: "Consecrate",
            period: "church",
            detail:
              "Consecration and the spiritual symbols belong to ecclesiastical authority.",
            election: "The elected candidate has a canonical title",
            spiritualAct: "Ring and staff no longer come from the emperor",
            temporalAct: "Regalia remain a separate question",
            limit: "Ecclesiastical freedom does not remove the bishop’s public obligations",
          },
          {
            id: "regalia",
            label: "Enfeoff",
            period: "realm",
            detail:
              "The ruler grants temporal regalia through the sceptre and receives the services attached to them.",
            election: "The candidate is not created bishop by this act",
            spiritualAct: "The sacramental office remains intact",
            temporalAct: "Sceptre marks lands, rights and obligations",
            limit: "The ruler cannot convert temporal grant into spiritual investiture",
          },
          {
            id: "regions",
            label: "Apply",
            period: "empire",
            detail:
              "The order of acts differs because German, Burgundian and Italian politics cannot be reduced to one formula.",
            election: "Canonical principle applies across the settlement",
            spiritualAct: "Free consecration is guaranteed",
            temporalAct: "Before consecration in Germany; within six months elsewhere",
            limit: "Worms regulates coexistence rather than creating modern separation",
          },
        ],
      },
    },
  ],
};
