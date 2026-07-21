import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/medieval-commercial-revolution";

export const medievalCommercialRevolution: ChapterDefinition = {
  slug: "medieval-commercial-revolution",
  number: "10",
  title: "The Medieval Commercial Revolution",
  openingTitleLines: ["The Medieval", "Commercial", "Revolution"],
  period: "AD 950–1350",
  claim:
    "Medieval Europeans made capital, obligation and risk travel farther than the people who owned them. The written road they built made strangers into partners and dangerous voyages into repeatable enterprises.",
  openingClaim:
    "Medieval Europeans made capital, obligation and risk travel farther than the people who owned them.",
  hero: {
    image: `${imageRoot}/01-ledger-road.avif`,
    mobileImage: `${imageRoot}/01-ledger-road-mobile.avif`,
    imageAlt:
      "Merchants weigh coin and enter figures in an open ledger beside a busy medieval Italian harbour.",
    imagePosition: "center center",
    mobileImagePosition: "72% center",
    visualLabel: "The Ledger Road · coin, contract and account",
  },
  theme: {
    id: "ledger",
    label: "The ledger road",
  },
  openingAction: "Follow the written road",
  mapLabel:
    "The ports, fairs, courts and counting houses that carried European capital across distance",
  routeImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Notarial cartularies · partnership contracts · fair privileges · exchange records · account books · marine insurance policies",
  acts: [
    {
      id: "market-keeps-appointment",
      number: "I",
      label: "The market keeps its appointment",
      period: "c. AD 950–1250",
      title: "The Market Keeps Its Appointment",
      detail:
        "Mediterranean ports, public notaries and the ordered fairs of Champagne give long-distance trade known places, known dates and a written memory.",
    },
    {
      id: "risk-acquires-boundary",
      number: "II",
      label: "Risk acquires a boundary",
      period: "c. AD 1100–1300",
      title: "Risk Acquires a Boundary",
      detail:
        "Maritime partnerships divide capital, labour, profit and loss among people who need not belong to one family or travel on one ship.",
    },
    {
      id: "promise-travels",
      number: "III",
      label: "The promise travels",
      period: "c. AD 1180–1350",
      title: "The Promise Travels",
      detail:
        "Safe conduct, commercial judgment, money of account and exchange instructions carry value across borders without sending every coin along the road.",
    },
    {
      id: "enterprise-remembers",
      number: "IV",
      label: "The enterprise remembers",
      period: "c. AD 1250–1350",
      title: "The Enterprise Remembers",
      detail:
        "Ledgers and marine insurance make repeated business visible, calculable and capable of joining Mediterranean finance to the markets of the north.",
    },
  ],
  ending: {
    period: "c. AD 1350",
    title: "The Road Is Written",
    detail:
      "A voyage could now begin in a contract, cross the sea as cargo, return as an obligation and remain in a ledger after every traveller had gone home. In Europe’s commercial cities, capital could be joined without kinship, settlement reached without a wagon of coin and a venture’s ordinary loss confined to its agreed stake. In Bruges the written road met the ships of the North Sea. Its next reach would run through Lübeck and Bergen, where a league of northern towns turned distance into power.",
    image: `${imageRoot}/13-road-is-written.avif`,
    nextPeriod: "AD 1150–1500",
  },
  returnHash: "commercial-revolution",
  nextHash: "hanseatic-north",
  nextTitle: "The Hanseatic North",
  nextSlug: "hanseatic-north",
  movements: [
    {
      id: "ports-wake-before-kingdoms",
      actId: "market-keeps-appointment",
      order: 1,
      period: "c. AD 950–1100",
      place: "Venice, Amalfi, Pisa and Genoa",
      title: "Ports Wake Before Kingdoms",
      thesis:
        "The revival of Mediterranean traffic demanded instruments that could work across rulers, currencies and seas.",
      body: [
        "At dawn in Venice, Amalfi, Pisa or Genoa, commerce began with weight. A sack was opened, a coin tested, a bale marked and a quantity entered beside a name. Beyond the table lay a sea divided among emperors, caliphs, cities, lords and raiders. No western king commanded the whole route. Italian ports grew because their sailors and merchants learned to operate across that political fragmentation, carrying timber, salt, grain, metals, cloth and eastern luxuries between shores governed by different laws.",
        "The longer the voyage, the more expensive uncertainty became. A merchant needed to know whose measure had filled the barrel, which coin had paid for it, who had accepted custody and where a broken promise could be pursued. Spoken reputation remained powerful, especially within families and familiar communities, but a ship soon travelled beyond the reach of a household’s memory. Distance increased the value of the scale, the mark, the witness, the written obligation and the court prepared to recognise them.",
        "European commerce revived through this accumulation of exact habits. Harbour dues recorded arrivals. Brokers found counterparties. Translators crossed languages. Merchants compared coins by silver content and learned the customs of foreign quays. Each successful passage left more than profit: it left a tested route, a known contact and a form that could be used again. Before Europe possessed a single market, its ports had begun to build a commercial order capable of crossing many jurisdictions. The first road was the line a clerk drew beneath a sum.",
      ],
      image: `${imageRoot}/01-ledger-road.avif`,
      mobileImage: `${imageRoot}/01-ledger-road-mobile.avif`,
      imageAlt:
        "Merchants weigh coin and record cargo beside ships loading at a medieval Italian quay.",
      imagePosition: "56% center",
      mobileImagePosition: "72% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "ledger-dawn",
      side: "left",
      sourceIds: ["lopez-1976", "spufford-1988", "lane-1973"],
      evidence: [
        "Port records, coin finds, cargo evidence and surviving commercial instruments trace renewed traffic through the Italian maritime cities from the tenth century onward.",
        "Political division did not disappear; merchants answered it with repeatable practices for weighing, witnessing, recording and enforcing exchange.",
      ],
      map: { x: 48, y: 68 },
    },
    {
      id: "notary-gives-voyage-memory",
      actId: "market-keeps-appointment",
      order: 2,
      period: "c. AD 1100–1200",
      place: "Genoa",
      title: "The Notary Gives the Voyage a Memory",
      thesis:
        "The public notary made a bargain endure after the ship and one of its partners had left the harbour.",
      body: [
        "Near the Genoese harbour, a notary listened while merchants described a future voyage. He named the parties, counted the capital, identified the travelling partner, recorded the destination and fixed the division due after return. Witnesses heard the instrument. The notary placed it in a cartulary among sales, loans, freight agreements and settlements. A private promise had acquired a public memory before the sail rose beyond the mole.",
        "That record changed what absence meant. The investor could remain in Genoa while his goods passed through Sicily, Tunis or the Levant. If the traveller died, delayed his return or disputed the amount received, the terms did not have to be reconstructed from friendship and accusation. The surviving instrument could be read before men who recognised the notary’s office. Its value came from a civic system of trained writers, accepted formulae, archives and tribunals rather than from the beauty of its Latin.",
        "Notarial writing also made commercial knowledge cumulative. Familiar clauses could be adapted to a new partner, cargo or route. The document distinguished capital from expected profit, ownership from custody and a completed voyage from an open obligation. Merchants remained capable of deceit, courts could fail and records could burn, but the bargain no longer vanished when memory did. Genoa filled its books with agreements among people connected by opportunity as well as kinship. The notary gave a mobile society the durable past tense on which its future bargains could be built.",
      ],
      image: `${imageRoot}/04-notary-binds-strangers.avif`,
      imageAlt:
        "A harbour notary records an agreement while merchants and witnesses stand around his table.",
      imagePosition: "65% center",
      mobileImagePosition: "73% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "notarial-bench",
      side: "right",
      sourceIds: ["van-doosselaere-2009", "hunt-murray-1999"],
      evidence: [
        "Genoese notarial cartularies preserve maritime partnerships, loans, sales and settlements in formulae that named parties, sums, duties and destinations.",
        "The evidentiary force of the instrument rested on the recognised notarial office and the civic institutions able to preserve and hear it.",
      ],
      map: { x: 45, y: 66 },
    },
    {
      id: "fair-keeps-its-date",
      actId: "market-keeps-appointment",
      order: 3,
      period: "c. AD 1150–1250",
      place: "Lagny, Bar-sur-Aube, Provins and Troyes",
      title: "The Fair Keeps Its Date",
      thesis:
        "The Champagne fair cycle turned the calendar itself into a commercial institution.",
      body: [
        "The fairs of Champagne joined the tumult of a market to the discipline of an ordered circuit. Lagny, Bar-sur-Aube, Provins and Troyes formed a cycle in which merchants could predict when buyers, sellers and money changers would gather. Each meeting occupied a different place and season. Flemish cloth came south; Italian merchants brought spices, dyestuffs, silk and credit north. The roads were slow, but the dates were known. Hundreds of decisions made in distant towns could therefore converge on the same weeks.",
        "Each fair unfolded through recognisable phases. Merchants arrived and opened their lodgings. Goods were displayed, inspected and sold. Accounts followed the trading days, and settlement followed the accounts. A debt contracted at one fair could be carried toward another date in the cycle. The sequence joined travel time to payment time, allowing a merchant in Florence or Arras to plan a journey, a purchase and a repayment before his pack animals entered Champagne.",
        "The calendar reduced distance without shortening a single road. A missed meeting meant delay and expense; a kept appointment assembled information, goods and claims in one protected place. Repetition made the market deeper because merchants expected other merchants to return. It also connected fairs to fairs, so that business did not end when the booths closed. A market now moved through time as deliberately as a convoy moved through space. The fair’s first promise was simple and immense: on the appointed date, the commercial world would be there.",
      ],
      image: `${imageRoot}/02-fair-calendar.avif`,
      imageAlt:
        "Merchants inspect cloth and written claims at a covered Champagne fair as carts arrive through the gate.",
      imagePosition: "64% center",
      mobileImagePosition: "73% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "seasonal-fair",
      side: "left",
      sourceIds: ["lopez-1976", "hunt-murray-1999", "greif-2006"],
      evidence: [
        "The Champagne fairs formed a recurring sequence whose privileges and recognised phases coordinated merchants from northern and Mediterranean Europe.",
        "Fair business combined the physical exchange of goods with account keeping and the settlement of obligations carried from one meeting to the next.",
      ],
      map: { x: 42, y: 54 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "fair-cycle",
        prompt: "Keep the fair cycle",
        accessibleSummary:
          "Six annual stages follow merchants, goods and payment dates through the recurring Champagne fair circuit in four towns.",
        initialId: "lagny",
        records: [
          {
            id: "lagny",
            label: "Lagny · Winter",
            period: "January",
            kicker: "The circuit begins",
            detail:
              "Merchants arriving from several roads establish prices, buy goods and write obligations that will mature later in the cycle.",
            fields: [
              { label: "Arrives", value: "Cloth, cash, correspondence" },
              { label: "Leaves", value: "Purchases and dated obligations" },
            ],
            outcome:
              "A known winter meeting turns separate journeys into one commercial season.",
          },
          {
            id: "bar-sur-aube",
            label: "Bar-sur-Aube · Lent",
            period: "Mid-Lent",
            kicker: "Credit follows the road",
            detail:
              "Merchants carry unsold goods, price knowledge and promises onward rather than beginning every negotiation again.",
            fields: [
              { label: "Arrives", value: "Goods and open accounts" },
              { label: "Leaves", value: "New sales and reassigned claims" },
            ],
            outcome:
              "The next fair preserves continuity while counterparties and cargo change.",
          },
          {
            id: "provins-may",
            label: "Provins · May",
            period: "Late spring",
            kicker: "The market thickens",
            detail:
              "Northern cloth and Italian merchandise meet a larger field of brokers and money changers as the cycle gathers volume.",
            fields: [
              { label: "Arrives", value: "Flemish cloth and Italian wares" },
              {
                label: "Leaves",
                value: "Converted goods and reckoned balances",
              },
            ],
            outcome:
              "Repeated attendance gives merchants more prices and more possible counterparties.",
          },
          {
            id: "troyes-hot",
            label: "Troyes · Hot Fair",
            period: "Early summer",
            kicker: "The circuit reaches Troyes",
            detail:
              "At the Hot Fair, further sales and exchanges carry goods and claims into the second half of the commercial year.",
            fields: [
              { label: "Arrives", value: "Cloth, wares and summer accounts" },
              { label: "Leaves", value: "New claims and redistributed cargo" },
            ],
            outcome:
              "The summer meeting keeps business moving toward the autumn fairs.",
          },
          {
            id: "provins-saint-ayoul",
            label: "Provins · St Ayoul",
            period: "Early autumn",
            kicker: "The route returns to Provins",
            detail:
              "The second Provins fair receives merchants carrying unsold wares, new orders and obligations created earlier in the year.",
            fields: [
              { label: "Arrives", value: "Autumn goods and open accounts" },
              {
                label: "Leaves",
                value: "Sales and claims due at year’s end",
              },
            ],
            outcome:
              "A second meeting in the same town makes the fair calendar nearly continuous.",
          },
          {
            id: "troyes-cold",
            label: "Troyes · Cold Fair",
            period: "November",
            kicker: "The commercial year closes",
            detail:
              "The Cold Fair brings mature obligations into reckoning and prepares merchants, credit and correspondence for Lagny in January.",
            fields: [
              { label: "Arrives", value: "Maturing debts and remaining stock" },
              { label: "Leaves", value: "Net balances and the next calendar" },
            ],
            outcome:
              "Settlement at Troyes closes the year and feeds the next winter opening at Lagny.",
          },
        ],
      },
    },
    {
      id: "one-stays-one-sails",
      actId: "risk-acquires-boundary",
      order: 4,
      period: "c. AD 1150–1250",
      place: "Genoa and the western Mediterranean",
      title: "One Merchant Stays; Another Sails",
      thesis:
        "The commenda joined sedentary capital to travelling skill for the duration of a single venture.",
      body: [
        "Two merchants met over one contract and entered different futures. The sedentary partner supplied money or goods. The travelling partner took custody, boarded the ship, traded abroad and returned with the proceeds. In a common Genoese commenda form, the investor provided the capital and received an agreed share of the profit; other arrangements varied the contribution and division. The partnership lasted for the venture rather than binding both men into one permanent household.",
        "The division released abilities that rarely occupied the same person. A prosperous citizen could possess savings but lack the health, language, contacts or appetite for a Mediterranean passage. A younger merchant could know the markets of Tunis or Acre yet lack enough capital to fill a hold. The contract joined one man’s resources to another man’s labour and local judgment. Kin remained valuable, but enterprise no longer had to wait for the perfect relative.",
        "The arrangement multiplied enterprise. Several investors could finance separate ventures while remaining in the city; an experienced traveller could build a record that attracted new capital. Each voyage stayed bounded by its stated contribution, route and division of returns. When the travelling merchant sailed, the partnership became mobile agency: one person acted with property entrusted by another under terms both could later prove. Capital could recruit courage at a distance, and commercial ambition no longer had to fit inside the purse or body of the man who conceived it.",
      ],
      image: `${imageRoot}/04-one-stays-one-sails-v2.avif`,
      imageAlt:
        "A seated investor holds a contract while his travelling partner points toward a merchant ship being loaded.",
      imagePosition: "70% center",
      mobileImagePosition: "73% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "divided-partnership",
      side: "right",
      sourceIds: ["van-doosselaere-2009", "greif-2006", "harris-2020"],
      evidence: [
        "Genoese contracts distinguish the capital-providing partner from the merchant who travelled, traded and rendered an account after return.",
        "Terms and profit shares varied across time and place; the durable mechanism was the contractual separation of finance from travelling agency.",
      ],
      map: { x: 45, y: 66 },
    },
    {
      id: "loss-acquires-a-limit",
      actId: "risk-acquires-boundary",
      order: 5,
      period: "twelfth–thirteenth centuries",
      place: "Venice and Genoa",
      title: "A Loss Acquires a Limit",
      thesis:
        "Medieval maritime partnership drew a legal boundary around the passive investor’s exposure.",
      body: [
        "A ship was overdue, and the investor’s money was gone. The crucial question was how far the loss could follow him home. In the commenda and the Venetian colleganza, the passive investor committed a defined contribution to a named venture. If ordinary maritime danger consumed the cargo, that committed stake could be lost; the investor’s other property was not thereby part of the venture fund. The contract made that boundary visible before wind and chance tested it. Invested risk had acquired a limit.",
        "Here Europe discovered the commercial power of limited liability in its medieval form. The boundary was contractual, attached to one venture and one voyage, and it protected chiefly the passive contributor from ordinary maritime loss. The travelling partner carried distinct duties and could still answer for fraud, breach or failure to account. A person could finance perilous trade without placing every field, house, tool and future inheritance in the voyage’s common fund.",
        "That limit widened the reservoir of capital. Savings held by people unwilling or unable to sail could move into shipping, cargo and foreign exchange. Loss remained real, discipline remained severe and the agreement ended with its venture. Later centuries would clothe the same logic in enduring companies, legal personality, transferable shares and statutes. The principle was already alive: capital could answer for the venture without dragging the whole household into the sea.",
      ],
      image: `${imageRoot}/05-loss-acquires-limit.avif`,
      imageAlt:
        "A merchant reports a lost cargo beside a contract and a closed chest while a damaged ship lies in the harbour.",
      imagePosition: "67% center",
      mobileImagePosition: "73% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "bounded-loss",
      side: "left",
      sourceIds: ["puga-trefler-2014", "harris-2020", "lane-1973"],
      evidence: [
        "Commenda and colleganza forms placed the passive investor’s defined contribution at risk in the venture while distinguishing it from the rest of his property.",
        "The protection was contractual and venture-specific; travelling partners retained separate duties, and misconduct could fall outside the ordinary allocation of maritime loss.",
      ],
      map: { x: 47, y: 66 },
    },
    {
      id: "contract-becomes-route",
      actId: "risk-acquires-boundary",
      order: 6,
      period: "c. AD 1260–1300",
      place: "Genoa, Tunis and the Levant",
      title: "The Contract Becomes a Route",
      thesis:
        "A financed voyage possessed a legal structure before it possessed a favourable wind.",
      body: [
        "A thousand florins on a Genoese table did not have to remain one man’s hoard. A sedentary investor and the merchant who sailed could each commit capital, while the traveller supplied the work of the voyage. The agreement identified the capital, assigned custody, described the destination, divided the return and fixed the exposure each party carried. The sum was measurable, and the parties’ obligations were distinct. Once written and witnessed, separate clauses formed one enterprise.",
        "The ship then gave those clauses a geography. Coin became wool cloth, metal or another saleable cargo. The travelling partner exchanged it at an intermediate port, responded to prices and carried the proceeds toward another market. His discretion made the venture useful; his duty to account made discretion financeable. A notary or broker could trace the claim behind each authorised transfer. At every stage, the cargo remained connected to claims waiting in Genoa. The route was physical at sea and juridical on land.",
        "A safe return opened the account for division. Damage reduced the common fund. Capture or wreck could consume the whole subscribed capital while the passive investor’s other property remained outside the venture fund. Savings, labour, information and law had been joined for one hazardous purpose, then separated again according to terms fixed before departure. The contract made courage governable. It could cross the Mediterranean, render its account and be built again for the next departure.",
      ],
      image: `${imageRoot}/06-contract-becomes-route.avif`,
      mobileImage: `${imageRoot}/06-contract-becomes-route-mobile.avif`,
      imageAlt:
        "Three merchants trace clauses across an open account book as cargo ships prepare to leave an Italian harbour.",
      imagePosition: "64% center",
      mobileImagePosition: "69% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "contractual-route",
      side: "right",
      sourceIds: ["van-doosselaere-2009", "puga-trefler-2014", "harris-2020"],
      evidence: [
        "Later thirteenth-century Mediterranean ventures could be denominated in florins after Florence introduced the gold coin in 1252.",
        "Partnership contracts allocated capital, agency, return and loss before departure, giving the voyage a provable structure across distance.",
      ],
      map: { x: 45, y: 66 },
      interaction: {
        kind: "ledger-voyage",
        prompt: "Finance the voyage",
        accessibleSummary:
          "A hypothetical thousand-florin maritime partnership separates passive investment from travelling capital, then shows where four possible losses stop.",
        capital: 1000,
        ventureLabel: "Genoa to Tunis and the Levant",
        allocations: [
          {
            id: "passive-capital",
            label: "Passive capital",
            amount: 800,
            role: "Sedentary investor",
            liability:
              "The 800 florins committed to this voyage are exposed; under ordinary maritime loss, the investor’s other property is not part of the venture fund.",
          },
          {
            id: "travelling-capital",
            label: "Travelling capital",
            amount: 200,
            role: "Travelling partner",
            liability:
              "His 200 florins, labour and contractual duties travel with the cargo and remain separately exposed.",
          },
        ],
        outcomes: [
          {
            id: "safe-return",
            label: "Safe return",
            loss: 0,
            detail:
              "The cargo is sold, the account is rendered and capital plus gain can be divided under the agreed shares.",
            householdEffect:
              "Neither household absorbs a capital loss; the venture closes according to its profit clause.",
          },
          {
            id: "damaged-cargo",
            label: "Damaged cargo",
            loss: 180,
            detail:
              "Water and delay reduce the common fund before either partner receives a return.",
            householdEffect:
              "Under ordinary maritime loss, the 180 florins reduce the subscribed venture capital rather than becoming part of a claim on the investor’s other property.",
          },
          {
            id: "captured-consignment",
            label: "Captured consignment",
            loss: 650,
            detail:
              "Part of the cargo is taken; recovered proceeds leave only 350 florins to close the account.",
            householdEffect:
              "The passive investor loses through his committed stake, while the travelling partner’s capital and labour carry their own agreed exposure.",
          },
          {
            id: "total-loss",
            label: "Total loss",
            loss: 1000,
            detail:
              "Wreck or capture consumes the entire subscribed fund under the venture’s ordinary maritime risk.",
            householdEffect:
              "The thousand florins are gone; under ordinary maritime loss, the passive investor’s other property is not part of this venture fund.",
          },
        ],
      },
    },
    {
      id: "count-guards-the-fair",
      actId: "promise-travels",
      order: 7,
      period: "c. AD 1180–1280",
      place: "Champagne",
      title: "The Count Guards the Fair",
      thesis:
        "Safe conduct and swift commercial judgment made political protection a productive asset.",
      body: [
        "A merchant approaching Champagne carried goods, letters and the knowledge that robbery could erase a season’s work. The counts answered with protection attached to the fair. Safe-conduct privileges covered merchants travelling toward the market. Officers guarded roads and fairgrounds. The ruler’s peace gave foreign traders a reason to enter his territory with portable wealth, and the tolls they paid gave him a reason to make that peace credible.",
        "Protection continued beneath the timber awnings. Fair courts heard claims while business was still in motion. Speed preserved the value of a judgment before merchants and assets left town. A seller facing non-payment did not have to begin an indefinite appeal to a distant lord who knew nothing of mercantile custom. Judges and officers could recognise bargains, debts and defaults within the institutional rhythm of the fair. Merchant associations brought their own practices and collective pressure; comital authority supplied the jurisdiction in which different groups could transact.",
        "The bargain between ruler and market strengthened itself. Guarded roads drew more merchants. More merchants produced tolls, rents, information and prestige. Those returns financed the incentive to protect the next gathering and punish conduct that threatened it. Fragmented lordships could therefore compete by offering better commercial order. Sovereignty became valuable to trade when it delivered a road, a forum and an enforceable sentence at the proper moment. The count did not need to command every town from Flanders to Lombardy. He needed to keep faith where their merchants met.",
      ],
      image: `${imageRoot}/05-fair-court.avif`,
      imageAlt:
        "Merchants present cloth and written claims before officers of a Champagne fair court.",
      imagePosition: "67% center",
      mobileImagePosition: "72% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "protected-fair",
      side: "left",
      sourceIds: ["lopez-1976", "hunt-murray-1999", "greif-2006"],
      evidence: [
        "Privileges of the Champagne fairs offered travelling merchants protection, while comital officers and fair courts supported order and adjudication.",
        "Merchant customs and associations operated alongside territorial authority; the fairs worked through their combination rather than through a single universal law.",
      ],
      map: { x: 42, y: 54 },
    },
    {
      id: "money-becomes-language",
      actId: "promise-travels",
      order: 8,
      period: "c. AD 1200–1350",
      place: "Champagne, Florence and Bruges",
      title: "Money Becomes a Language",
      thesis:
        "Money of account translated Europe’s many physical coins into comparable written value.",
      body: [
        "A money changer’s table held Europe in fragments. English sterlings, French deniers, Flemish issues and Italian coins differed in weight, fineness, wear and local acceptance. Clipping, debasement and long circulation complicated every comparison. Their stamped faces declared authority; their silver or gold content determined what a careful merchant would surrender for them. The scale made royal images answer to metal. Every frontier and mint could alter the practical value of a purse. Long-distance exchange required judgment before it required arithmetic.",
        "Merchants answered by reckoning in units that did not need to exist as one physical coin on the table. Pounds, shillings and pence could organise an account while payment arrived in a mixture of circulating pieces. The changer tested metal, followed rates and translated the contents of a pouch into the book’s stable language. A Florentine florin, a sterling penny and a local silver coin could occupy different sides of one transaction because calculation made their relationships legible.",
        "This commercial language of money was made from knowledge rather than decree. Local coinage remained vigorous while merchants learned to cross it. Price lists, account entries and exchange calculations allowed cloth in Bruges to be compared with obligations in Champagne and capital in Florence. The written unit separated value from the particular metal that happened to discharge it. Once money could exist as a dependable relation in an account, a commercial promise could survive the changing coins encountered on its journey.",
      ],
      image: `${imageRoot}/03-coin-becomes-account.avif`,
      imageAlt:
        "Money changers compare medieval coins with scales and enter their values in an account book.",
      imagePosition: "64% center",
      mobileImagePosition: "70% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "money-of-account",
      side: "right",
      sourceIds: ["spufford-1988", "de-roover-1948", "hunt-murray-1999"],
      evidence: [
        "Medieval accounts commonly reckoned in pounds, shillings and pence even when settlement used diverse coins whose metallic and local values differed.",
        "Money changers and merchants compared weight, fineness and exchange conditions, making currency conversion a specialised commercial practice.",
      ],
      map: { x: 45, y: 58 },
    },
    {
      id: "promise-crosses-alps",
      actId: "promise-travels",
      order: 9,
      period: "late thirteenth–fourteenth centuries",
      place: "Florence, Champagne and Bruges",
      title: "A Promise Crosses the Alps",
      thesis:
        "Correspondents and fair settlement allowed obligations to travel farther than the metal that finally discharged them.",
      body: [
        "A purse of silver crossing the Alps announced itself to toll collectors, carriers and thieves. It was heavy, expensive to guard and liable to arrive in a place where its coins traded at a discount. Merchant houses found a more powerful cargo: a written instruction addressed to a correspondent. A claim created in one city could be answered by payment in another, using people and balances already positioned on both sides of the mountains.",
        "The fairs made such obligations meet. One merchant owed for cloth; his creditor owed an Italian house; that house expected payment from another counterparty. Clerks compared the claims and set reciprocal sums against one another. The chain depended on each entry remaining intelligible to the next counterparty. Settlement belonged to repeated fair procedure and correspondent relationships, while each written instrument retained its local form. The achievement was already immense. Writing, correspondence and accepted commercial practice allowed several debts to collapse into a smaller net balance.",
        "Only that balance needed to move in coin. The rest crossed Europe as ordered payment, book entry and recognised claim. This released metal for other uses, reduced transport danger and let merchant houses coordinate resources dispersed across cities they did not rule. Trust had acquired an architecture: named correspondents, repeated dealings, account records, fair procedures and courts behind them. The Alps remained steep, but value no longer had to climb every pass in a guarded chest. A promise could take the road instead.",
      ],
      image: `${imageRoot}/06-value-travels.avif`,
      imageAlt:
        "A courier delivers a sealed payment instruction to a merchant beside scales and an open ledger.",
      imagePosition: "64% center",
      mobileImagePosition: "71% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "written-value",
      side: "left",
      sourceIds: ["rogers-1995", "spufford-1988", "de-roover-1948"],
      evidence: [
        "Exchange transactions and correspondent relationships enabled payment in one place against value received or owed in another.",
        "Fair settlement and bilateral accounting could offset reciprocal claims, reducing the amount of specie that had to be transported between markets.",
      ],
      map: { x: 43, y: 57 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "settlement-netting",
        prompt: "Settle without hauling every coin",
        accessibleSummary:
          "Four stages record, connect and offset obligations between merchant houses until only the net balances require payment in metal.",
        initialId: "record",
        records: [
          {
            id: "record",
            label: "Record the claims",
            period: "At the fair table",
            kicker: "Four obligations",
            detail:
              "Clerks identify each debtor, creditor, currency and due date before any claim can be compared with another.",
            fields: [
              { label: "Florence house", value: "Owes the cloth seller" },
              { label: "Cloth seller", value: "Owes the wool exporter" },
              { label: "Wool exporter", value: "Owes the shipper" },
              { label: "Shipper", value: "Has a claim on Florence" },
            ],
            outcome:
              "Every obligation is visible as a named claim rather than an anonymous pile of coin.",
          },
          {
            id: "connect",
            label: "Connect correspondents",
            period: "Across the Alps",
            kicker: "Payment changes place",
            detail:
              "Houses with balances in different cities instruct trusted correspondents to receive or discharge value locally.",
            fields: [
              { label: "South", value: "Florence records the instruction" },
              { label: "North", value: "Bruges recognises the counterparty" },
            ],
            outcome:
              "The claim crosses the mountains while most of the metal remains where it already circulates.",
          },
          {
            id: "offset",
            label: "Offset reciprocal debts",
            period: "Reckoning day",
            kicker: "Gross becomes net",
            detail:
              "Opposing claims are set against one another under the recognised settlement practices of the fair and the merchant houses.",
            fields: [
              { label: "Before", value: "Four separate gross payments" },
              { label: "After", value: "Only unmatched differences remain" },
            ],
            outcome:
              "Several journeys of coin disappear into one documented reckoning.",
          },
          {
            id: "pay",
            label: "Pay the balances",
            period: "Account closed",
            kicker: "Metal moves last",
            detail:
              "Coin settles the remaining differences, and each house enters the completed payment against the original obligation.",
            fields: [
              { label: "Moves", value: "Net balances only" },
              { label: "Remains", value: "The written chain of discharge" },
            ],
            outcome:
              "Value has travelled farther than the specie used to close the account.",
          },
        ],
      },
    },
    {
      id: "ledger-sees-the-house",
      actId: "enterprise-remembers",
      order: 10,
      period: "c. AD 1300–1350",
      place: "Florence and Genoa",
      title: "The Ledger Sees the House",
      thesis:
        "Developing account books made a dispersed enterprise visible to the people directing it.",
      body: [
        "A merchant house no longer fit inside one room. Wool waited in a warehouse, cloth stood with a dyer, cash sat with a correspondent, a partner sailed with cargo and debts approached maturity in another city. Letters reported fragments. The ledger gathered them into a field that could be inspected. Names, ventures, goods, payments and withdrawals acquired places in a durable record rather than remaining separate memories in separate heads.",
        "Medieval bookkeeping developed through several books and changing practices. A memorandum caught the day’s transaction; a journal or working book arranged it; a ledger assigned entries to people, goods or ventures. Command over complexity came from the relationship among these books, carried balances and repeated checks. The books created a view across time as well as distance. By placing related claims together, merchants could see who owed the house, what the house owed, which voyage remained open and where capital had ceased to earn.",
        "The account book became an instrument of government. Partners could demand a reckoning. Heirs and successors could recover unfinished business. A clerk could compare a correspondent’s letter with the house’s entry and expose an omission. Profit emerged from recorded relations among purchase, expense, sale and time rather than from the coins visible in a chest. Commercial houses had acquired memory at scale. The ledger saw an enterprise no single merchant could see with his eyes, and that vision made larger, longer and more disciplined cooperation possible.",
      ],
      image: `${imageRoot}/10-ledger-sees-house.avif`,
      imageAlt:
        "A merchant and clerks reconcile ledgers, letters, coin and sealed packets in a medieval counting house.",
      imagePosition: "65% center",
      mobileImagePosition: "70% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "counting-house-memory",
      side: "right",
      sourceIds: ["hunt-murray-1999", "de-roover-1948", "murray-2005"],
      evidence: [
        "Surviving Italian merchant records preserve multiple books and account structures used to organise people, goods, ventures and balances.",
        "The evidence preserves several developing bookkeeping practices; their use remained varied among merchant houses in 1350.",
      ],
      map: { x: 46, y: 65 },
    },
    {
      id: "sea-can-be-insured",
      actId: "enterprise-remembers",
      order: 11,
      period: "c. AD 1340–1350",
      place: "Genoa",
      title: "The Sea Can Be Insured",
      thesis:
        "Marine insurance separated the hazard of a voyage from ownership of its cargo and gave danger a price.",
      body: [
        "On 20 February 1343, a Genoese instrument recorded the essential structure of marine insurance: a named interest, a route, a period of exposure and another party prepared to answer for loss in return for payment. The cargo owner kept the goods and the expected gain. The underwriter assumed a stated share of specified danger. The agreement named the circumstances that would trigger compensation before a commercial court. Risk itself had become the subject of a contract before the ship departed.",
        "The price depended on judgment. A short passage in a favourable sailing season did not present the same danger as a long winter route. War, corsairs, convoy protection, the vessel, the cargo and the reputation of those involved could alter the bargain. Merchants assembled information from letters, arrivals, harbour talk and repeated experience. The premium condensed that scattered knowledge into a price paid now for compensation if the named loss later occurred.",
        "Insurance did not calm the sea. It redistributed the economic wound a storm or capture could inflict. An underwriter could accept portions of several voyages rather than sail with one cargo; a merchant could preserve enough capital to continue after disaster. Merchants had advanced from sharing a voyage to trading its hazard as a separate obligation. The achievement required writing, probability judged without formal statistics, enforceable promises and a market of men willing to stand behind them. The sea remained dangerous. Its danger had become legible, divisible and financeable.",
      ],
      image: `${imageRoot}/11-sea-insured.avif`,
      imageAlt:
        "Two Genoese merchants price a marine insurance agreement over route documents as a ship enters rough water.",
      imagePosition: "66% center",
      mobileImagePosition: "72% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "insured-sea",
      side: "left",
      sourceIds: ["botticini-buri-marinacci-2023", "harris-2020", "lane-1973"],
      evidence: [
        "A Genoese contract dated 20 February 1343 is the earliest known surviving marine insurance policy in the developed form documented by current research.",
        "Medieval underwriters assessed route, season and human hazards through commercial information and priced a defined transfer of loss rather than the cargo itself.",
      ],
      map: { x: 45, y: 66 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "price-the-sea",
        prompt: "Price the sea",
        accessibleSummary:
          "Four voyage profiles show how route, season, violence and protection changed an underwriter’s premium judgment without removing maritime risk.",
        initialId: "summer-passage",
        records: [
          {
            id: "summer-passage",
            label: "Short summer passage",
            period: "Favourable season",
            kicker: "Lower exposure",
            detail:
              "A short familiar route in the normal sailing season presents fewer days at sea and more recent information about conditions.",
            fields: [
              { label: "Route", value: "Short and familiar" },
              { label: "Season", value: "Favourable" },
              { label: "Human hazard", value: "No special warning" },
              { label: "Premium judgment", value: "Lower" },
            ],
            outcome:
              "The underwriter assumes the stated loss; ordinary commercial risks remain with the merchant.",
          },
          {
            id: "winter-route",
            label: "Long winter route",
            period: "Difficult season",
            kicker: "Weather raises the price",
            detail:
              "More sea miles and a season of shorter days and harsher weather increase the time and conditions under exposure.",
            fields: [
              { label: "Route", value: "Long" },
              { label: "Season", value: "Winter" },
              { label: "Human hazard", value: "Ordinary" },
              { label: "Premium judgment", value: "Higher" },
            ],
            outcome:
              "The premium rises because the insured danger lasts longer and meets worse sailing conditions.",
          },
          {
            id: "corsair-route",
            label: "Corsair exposure",
            period: "Reported danger",
            kicker: "Violence enters the price",
            detail:
              "Reports of capture along the intended route add a human hazard distinct from wind, shoal and storm.",
            fields: [
              { label: "Route", value: "Exposed waters" },
              { label: "Season", value: "Sailable" },
              { label: "Human hazard", value: "Corsair reports" },
              { label: "Premium judgment", value: "Highest" },
            ],
            outcome:
              "Named exposure to seizure makes the assumed obligation more expensive.",
          },
          {
            id: "armed-convoy",
            label: "Armed convoy",
            period: "Protected passage",
            kicker: "Protection changes the price",
            detail:
              "Sailing with protection reduces vulnerability to attack while preserving the hazards of weather, navigation and delay.",
            fields: [
              { label: "Route", value: "Exposed but escorted" },
              { label: "Season", value: "Sailable" },
              { label: "Human hazard", value: "Reduced by convoy" },
              { label: "Premium judgment", value: "Below an unescorted route" },
            ],
            outcome:
              "Protection lowers one component of the price; it does not erase the sea.",
          },
        ],
      },
    },
    {
      id: "ledger-road-reaches-north",
      actId: "enterprise-remembers",
      order: 12,
      period: "c. AD 1280–1350",
      place: "Bruges",
      title: "The Ledger Road Reaches the North",
      thesis:
        "In Bruges, Mediterranean finance joined the cloth and shipping worlds of northern Europe.",
      body: [
        "Bruges gathered seas and industries that no ruler had designed as one system. Flemish towns produced renowned cloth from English wool. Ships arrived through the North Sea approaches with grain, timber, wax, furs, metals and fish from northern and Baltic routes. Italian merchant houses brought southern wares, correspondence, credit and trained accounting. The encounter made Bruges a hinge between commercial zones with distant centres. On its quays, Mediterranean instruments met a commercial world with its own ships, towns and corporate strength.",
        "The foreign merchant did not need Bruges to resemble Genoa. He needed brokers, lodging, recognised weights, a place to keep records and counterparties capable of answering a promise. Accounts translated currencies; correspondence linked resident agents to distant partners; local and communal authorities supplied forums for business. One house could connect Florence, London and Bruges without placing them under one law. Written obligation served as the common road across their differences.",
        "From Bruges that road turned toward colder water. Lübeck and the German towns were organising the Baltic and North Sea exchange through privileges, convoys, counting houses and common action. Bergen offered the northern system one of its commanding goods: dried cod, preserved by climate and labour for the long journey south. Grain, cloth, salt and credit moved back. The Mediterranean revolution did not end at the Alps. It furnished instruments that northern merchants could combine with their own urban power. The next ledger would open beside the Norwegian harbour.",
      ],
      image: `${imageRoot}/12-road-reaches-north.avif`,
      imageAlt:
        "An Italian merchant reads correspondence beside cloth and ledgers overlooking the busy medieval harbour of Bruges.",
      imagePosition: "66% center",
      mobileImagePosition: "72% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "northern-handoff",
      side: "right",
      sourceIds: ["murray-2005", "de-roover-1948", "lopez-1976"],
      evidence: [
        "Bruges joined Flemish cloth production and English wool to merchant houses and shipping networks extending through the Mediterranean, North Sea and Baltic.",
        "Italian residents brought correspondent finance and accounting into a northern market whose institutions, privileges and maritime organisation also developed on local foundations.",
      ],
      map: { x: 40, y: 50 },
    },
  ],
};
