import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/dutch-republic";

export const dutchRepublic: ChapterDefinition = {
  slug: "dutch-republic",
  number: "18",
  title: "The Dutch Republic",
  openingTitleLines: ["The Dutch", "Republic"],
  period: "AD 1572–1713",
  claim:
    "The Dutch Republic turned divided authority into disciplined cooperation. Provinces, towns, water boards, companies, banks and exchanges gave a small European republic the means to command ships, credit and information across the world.",
  openingClaim:
    "A federation built among waterlogged provinces learned to join civic liberty, audited obligation and permanent capital on a scale no European republic had reached before.",
  hero: {
    image: `${imageRoot}/opening-exchange-hall.avif`,
    mobileImage: `${imageRoot}/opening-exchange-hall-mobile.avif`,
    imageAlt:
      "Amsterdam's brick exchange court before the bell, with clerks opening ledgers, messengers pinning shipping notices and routes converging on the flagstones.",
    imagePosition: "center center",
    mobileImagePosition: "57% center",
    visualLabel: "The Exchange Hall · ledger, bell and public price",
  },
  theme: {
    id: "exchange",
    label: "The Exchange Hall",
  },
  openingAction: "Ring the exchange bell",
  mapLabel:
    "The towns, assemblies, polders, shipyards, chambers, ledgers and exchange routes through which the Dutch Republic made divided authority productive",
  routeImage: "assets/world-relief.jpg",
  openingRouteImage: "assets/world-relief.jpg",
  sourcesEyebrow:
    "Union acts · town resolutions · Sound toll books · VOC capital registers · water-board accounts · bank ledgers · exchange notices · provincial bonds",
  acts: [
    {
      id: "republic-rises",
      number: "I",
      label: "A republic rises from revolt",
      period: "AD 1572–1585",
      title: "A Republic Rises from Revolt",
      detail:
        "Maritime seizure, written union and the northward movement of people and skill give provincial resistance the ports, assemblies and urban strength of a state.",
    },
    {
      id: "water-ships-system",
      number: "II",
      label: "Water and ships become a system",
      period: "AD 1590–1612",
      title: "Water and Ships Become a System",
      detail:
        "Specialised hulls, transferable company capital and collective drainage let Dutch cities use distant seas and submerged land with the same exacting coordination.",
    },
    {
      id: "trust-machinery",
      number: "III",
      label: "Trust acquires machinery",
      period: "AD 1609–1650",
      title: "Trust Acquires Machinery",
      detail:
        "Municipal bank money, a public exchange and funded provincial debt turn obligations into visible, transferable and dependable instruments.",
    },
    {
      id: "republic-commands-distance",
      number: "IV",
      label: "The small republic commands distance",
      period: "AD 1620–1713",
      title: "The Small Republic Commands Distance",
      detail:
        "Books, refuge, water defence and an armed North Sea crossing carry Dutch civic and financial practices into the wider European contest.",
    },
  ],
  ending: {
    period: "AD 1713",
    title: "The Exchange Keeps Speaking",
    detail:
      "The republic had made dispersed authority productive. Its towns could drain a lake, fund a fleet, clear a bill and shelter a printer because cooperation had acquired offices, ledgers, schedules and enforceable rules. Dutch methods now worked in London as well as Amsterdam, while newspapers, pamphlets and coffeehouse reports carried judgment beyond the merchants gathered beneath the exchange arcades. European information was becoming a public voice, and that public would soon claim the right to examine laws, customs and rulers.",
    image: `${imageRoot}/ending-exchange-keeps-speaking.avif`,
    mobileImage: `${imageRoot}/ending-exchange-keeps-speaking-mobile.avif`,
    nextPeriod: "AD 1680–1789",
  },
  returnHash: "dutch-republic",
  nextHash: "enlightenment-public-opinion",
  nextTitle: "The Enlightenment",
  nextSlug: "enlightenment-public-opinion",
  movements: [
    {
      id: "beggars-take-brill",
      actId: "republic-rises",
      order: 1,
      period: "1 April AD 1572",
      place: "Brill, Holland and Zeeland",
      title: "The Beggars Take Brill",
      thesis:
        "An improvised seizure of an empty royal port gave revolt the protected waterways, town walls and civic decisions from which a republic could grow.",
      body: [
        "On 1 April 1572, a fleet of exiled rebels entered the Maas estuary looking for food and anchorage. The Sea Beggars found Brill without its Spanish garrison. William van der Marck, lord of Lumey, and Willem Bloys van Treslong brought their men ashore, forced a gate and occupied the town. The seizure had not followed William of Orange's campaign plan, and Brill offered little treasure. It offered a harbour behind walls. Ships that had lived from raids now possessed a place where stores could be landed, guns mounted and a municipal government required to choose a side.",
        "News moved through the water towns faster than a royal army. Flushing expelled its garrison within days; Veere, Enkhuizen and other towns in Holland and Zeeland followed during the spring and summer. Local regents, militia captains, Calvinist exiles and seamen made separate decisions whose force accumulated through connected canals and estuaries. The rebels could supply one town from another, interrupt royal movement by water and admit Orange's officers through gates opened by citizens. Geography converted scattered resistance into a defensible coastal belt.",
        "Delegates from the rebel towns met at Dordrecht in July. They recognised Orange as stadholder of Holland, promised money for the war and began directing taxation and defence through provincial institutions already familiar to their cities. Philip II's government retained formidable armies and much of the Netherlands; it now faced fortified towns able to collect revenue and coordinate soldiers. Brill had supplied the revolt with an address. Every captured key, harbour account and militia watch thereafter made rebellion more capable of enforcing decisions and surviving the departure of the ships that had first opened the gate.",
      ],
      image: `${imageRoot}/01-beggars-take-brill.avif`,
      imageAlt:
        "Sea Beggar vessels enter a rain-dark harbour at Brill while militia carry the town keys toward a coastal map of declaring towns.",
      imagePosition: "60% center",
      mobileImagePosition: "68% center",
      visualLabel: "Harbour, militia watch and town resolutions",
      visualTone: "wet-brick",
      side: "left",
      sourceIds: ["israel-1995", "t-hart-2014", "parker-dutch-revolt-1985"],
      evidence: [
        "Sea Beggars occupied Brill on 1 April 1572 after finding that its Spanish garrison had left the port.",
        "A succession of towns in Holland and Zeeland declared for the revolt, and the Dordrecht meeting of July 1572 recognised William of Orange and organised provincial support for war.",
      ],
      map: { x: 39, y: 47 },
    },
    {
      id: "provinces-make-a-union",
      actId: "republic-rises",
      order: 2,
      period: "AD 1579–1581",
      place: "Utrecht and The Hague",
      title: "The Provinces Make a Union",
      thesis:
        "The Union of Utrecht bound provinces to common defence while preserving the urban and provincial authorities whose consent gave the union strength.",
      body: [
        "Delegates gathered at Utrecht in January 1579 with military collapse close behind them. Alexander Farnese had restored royal power across much of the south, and no remaining province could command its neighbours' laws, taxes or privileges. The articles signed at Utrecht treated the provinces as allies joined for perpetual common defence. They promised mutual aid, a shared military assessment and consultation over peace and war. Sovereignty remained distributed among towns and provinces. The union worked through authorities that entered with their own seals intact.",
        "Government therefore ran through several desks. A town council managed its poor relief, market, militia and local taxes. Provincial States assembled urban and noble delegates, with wealthy Holland dominated by its voting towns. The States General handled diplomacy, common war and the territories administered by the union, while provincial instructions bound the deputies who sat there. Unanimity applied to the gravest shared decisions. Negotiation could be slow because consent had to travel outward for instruction and inward for agreement; once secured, the decision rested on bodies able to raise money and execute it locally.",
        "The Act of Abjuration gave this arrangement a constitutional voice in 1581. Its signatories declared that a ruler who oppressed his subjects and violated their privileges had abandoned the duty for which he had been accepted. Renunciation of Philip II left sovereignty distributed while the provinces searched unsuccessfully for a foreign protector. By the end of the decade the northern provinces governed as a republic. Europe had acquired a federal power whose centre could act because towns and provinces retained enough authority to make their promises real.",
      ],
      image: `${imageRoot}/02-provinces-make-a-union.avif`,
      imageAlt:
        "The Union of Utrecht folio opens between town, provincial States and States General desks joined by waxed instruction cords.",
      imagePosition: "center center",
      mobileImagePosition: "52% center",
      visualLabel: "Union articles, instructions and assembly seals",
      visualTone: "federal-table",
      side: "right",
      sourceIds: ["israel-1995", "t-hart-2014", "parker-dutch-revolt-1985"],
      evidence: [
        "The Union of Utrecht of 1579 established common defence and consultation while leaving extensive government with provincial and urban institutions.",
        "The Act of Abjuration of 1581 renounced Philip II on the ground that a ruler who violated his obligations had forfeited the obedience of his subjects.",
      ],
      map: { x: 41, y: 48 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "united-provinces",
        prompt: "Assemble the provinces",
        accessibleSummary:
          "Four institutional states route local, provincial and common business through town councils, provincial States and the States General, then show why a central question returns to the provinces for unanimous consent.",
        initialId: "town-council",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "town-council",
            label: "Open the town council",
            period: "Local authority",
            kicker: "The city acts through its own officers",
            detail:
              "Regents direct the market, poor relief, militia, harbour works and local levies through offices close to the people and property affected.",
            fields: [
              { label: "Business", value: "Market, militia and municipal tax" },
              { label: "Decision", value: "Town resolution" },
              { label: "Execution", value: "Burgomasters and civic officers" },
            ],
            outcome:
              "The union begins with cities already capable of governing and paying.",
          },
          {
            id: "provincial-states",
            label: "Convene the provincial States",
            period: "Provincial authority",
            kicker: "Several towns form one instructed vote",
            detail:
              "Urban and noble delegates bargain over taxation, appointments and defence before instructing the deputies sent to the general assembly.",
            fields: [
              { label: "Business", value: "Provincial levy and office" },
              { label: "Decision", value: "Mandated provincial position" },
              { label: "Limit", value: "Local privileges remain in force" },
            ],
            outcome:
              "A province can commit resources because its constituent authorities have agreed to provide them.",
          },
          {
            id: "states-general",
            label: "Meet in the States General",
            period: "Common authority",
            kicker: "The union speaks beyond its borders",
            detail:
              "Provincial deputies coordinate diplomacy, the common army, the admiralties and business affecting the union as a whole.",
            fields: [
              { label: "Business", value: "War, peace and foreign relations" },
              { label: "Decision", value: "General resolution" },
              { label: "Authority", value: "Deputies carrying instructions" },
            ],
            outcome:
              "Seven provincial voices can present one policy to another European power.",
          },
          {
            id: "unanimity-lock",
            label: "Secure unanimous consent",
            period: "Constitutional lock",
            kicker: "The centre returns to its members",
            detail:
              "A central question of war, peace or the union's constitutional obligations sends deputies back to the provinces until every instructed vote can be joined.",
            fields: [
              { label: "Requirement", value: "Consent of all provinces" },
              {
                label: "Cost",
                value: "Time, bargaining and renewed instruction",
              },
              {
                label: "Strength",
                value: "Execution by consenting governments",
              },
            ],
            outcome:
              "The completed act binds federal policy to the consent of its constituent governments.",
          },
        ],
      },
    },
    {
      id: "antwerp-moves-north",
      actId: "republic-rises",
      order: 3,
      period: "AD 1585–1600",
      place: "Antwerp, Amsterdam, Leiden and Haarlem",
      title: "Antwerp Moves North",
      thesis:
        "The fall of Antwerp concentrated southern commercial skill, craft knowledge and European correspondence inside the rising northern towns.",
      body: [
        "Alexander Farnese's army closed around Antwerp in 1584, bridging the Scheldt and defeating attempts to break the siege. The city capitulated in August 1585. Protestant inhabitants received a limited period in which to conform or depart, while warfare and the rebel command of the estuary kept ocean-going traffic from returning up the river. Families sorted account books, type, looms, tools and correspondence into portable property. Antwerp had been the great north-western European entrepôt; its commercial knowledge now travelled with the people who knew how to use it.",
        "Amsterdam received merchants with partners in Iberia, Germany and the Baltic. Leiden and Haarlem received textile workers able to organise new mixtures of specialised labour, finishing and export. Printers, engravers, schoolmasters and cartographers carried languages and techniques into a dense urban market. Jodocus Hondius, born in Flanders and trained as an engraver, eventually established his Amsterdam workshop and enlarged the cartographic business associated with Mercator's plates. Each arrival entered an existing northern town, joined a guild or congregation, hired neighbours and placed an old address book beside a new civic ledger.",
        "The transfer accelerated a change already under way. Amsterdam possessed access to the Zuiderzee, Baltic shipping and the rebel-controlled sea approaches; the southern migrants supplied capital and connections fitted to larger commerce. The city's population multiplied across the following decades, its harbour expanded and new districts rose behind successive rings of canal. Leiden's cloth output and university presses reached foreign markets. The achievement belonged to a republic able to receive mobile skill and give it institutions in which to compound. What left Antwerp in separate barges returned to Europe as a northern concentration of workshops, credit and news.",
      ],
      image: `${imageRoot}/03-antwerp-moves-north.avif`,
      imageAlt:
        "Named merchant ledgers, textile tools, type cases and engraving plates travel by barge from Antwerp toward workshops in Amsterdam, Leiden and Haarlem.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "Migration registers, workshop marks and city views",
      visualTone: "northern-arrival",
      side: "left",
      sourceIds: [
        "israel-1995",
        "gelderblom-2013",
        "de-vries-van-der-woude-1997",
      ],
      evidence: [
        "After Antwerp capitulated in 1585, substantial numbers of merchants, artisans, printers and Protestant families moved into the northern provinces.",
        "Southern commercial networks and craft skills reinforced the rapid expansion of Amsterdam, Leiden, Haarlem and other Dutch towns.",
      ],
      map: { x: 39, y: 50 },
    },
    {
      id: "fluyt-carries-the-baltic",
      actId: "water-ships-system",
      order: 4,
      period: "c. AD 1590–1650",
      place: "Amsterdam, the Sound and Baltic ports",
      title: "The Fluyt Carries the Baltic",
      thesis:
        "A capacious hull, economical crew and relentless return schedule made Dutch shipping the low-cost carrier of northern Europe.",
      body: [
        "In the yards of Hoorn, Amsterdam and the Zaan district, shipwrights built merchantmen around the requirements of cargo. The fluyt carried a broad, deep hold beneath a comparatively narrow upper deck, used a manageable rig and sailed with a smaller crew than many vessels of similar capacity. Sawn timber, specialised yards and repeated hull forms reduced construction time and repair uncertainty. The productivity gain joined hull, crew, finance, provisioning and turnaround in a vessel that could earn on frequent, heavily loaded passages.",
        "Its decisive road ran through the Danish Sound. Eastbound ships carried salt, herring, cloth, wine and colonial wares; westbound holds filled with Polish and Prussian grain, Scandinavian timber, tar, pitch, hemp and iron. The Sound Toll clerks recorded thousands of passages, allowing merchants to compare cargo, season and destination. Grain entering Amsterdam's warehouses fed a densely urban republic and could be released when western prices rose. Timber and naval stores returned to the same yards that sent the ships out, so carriage enlarged the capacity for further carriage.",
        "The Baltic became the moedernegotie, the mother trade, because it supplied the daily food and materials beneath more celebrated voyages. By the middle of the seventeenth century the Dutch operated Europe's largest merchant fleet and carried goods for customers whose kingdoms had harbours of their own. Freight margins could be narrow; scale, regularity and low operating cost made them powerful. The fluyt embodies the system at working size: a modest crew enclosed by an immense hold, sailing a route whose profits rested on calculation repeated across an entire maritime economy.",
      ],
      image: `${imageRoot}/04-fluyt-carries-the-baltic.avif`,
      imageAlt:
        "A cutaway fluyt reveals its small working crew and deep grain hold beside a Sound Toll book and Baltic commodity route.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Ship section, cargo tally and Sound route",
      visualTone: "baltic-cargo",
      side: "right",
      sourceIds: ["de-vries-van-der-woude-1997", "unger-1978", "israel-1989"],
      evidence: [
        "Dutch shipyards developed cargo vessels, including the fluyt, whose hold, rig and crew requirements supported economical bulk carriage.",
        "The Baltic mother trade supplied grain, timber and naval stores while sustaining the shipping capacity used throughout Dutch commerce.",
      ],
      map: { x: 50, y: 42 },
    },
    {
      id: "capital-outlives-the-voyage",
      actId: "water-ships-system",
      order: 5,
      period: "AD 1602–1623",
      place: "Amsterdam and the six VOC chambers",
      title: "Capital Outlives the Voyage",
      thesis:
        "The VOC locked large subscriptions into a continuing enterprise while transferable claims let an investor depart without recalling the fleet.",
      body: [
        "Before 1602, Dutch companies commonly raised money for a defined group of ships, reckoned the result after their return and formed another partnership for the next departure. Competition lifted purchase prices in Asia and divided armed protection among rival ventures. The States General answered by chartering the Verenigde Oostindische Compagnie. Six chambers from Amsterdam to Zeeland subscribed over six million guilders, appointed directors and sent delegates to the Heeren XVII. The charter granted a twenty-one-year monopoly east of the Cape and west of the Strait of Magellan, with authority to build forts, make treaties and wage war in the company's name.",
        "The original terms anticipated a general account after ten years, when investors could recover their capital. Ships, factories and Asian commitments refused that tidy ending. In 1612 the States General allowed the capital to remain rather than forcing liquidation; renewal of the charter in 1623 confirmed the company's continuing life. Money subscribed in Europe could therefore support warehouses, garrisons, purchases and fleets across voyages whose durations overlapped. Directors managed the common assets while an investor's entitlement existed as an entry in a chamber's capital book.",
        "Transferability solved the investor's separate problem. A holder who needed cash could sell all or part of that book claim to another buyer; company clerks recorded the transfer while the vessels remained at sea. The secondary market supplied an exit without dismantling the enterprise. Permanent joint capital emerged in stages: mass subscription in 1602, active transfers in the capital books, continuation at the ten-year account in 1612 and charter renewal in 1623. Their combination created an institution able to preserve command across oceans and generations while thousands of private decisions changed the names attached to its capital.",
      ],
      image: `${imageRoot}/05-capital-outlives-the-voyage.avif`,
      imageAlt:
        "A VOC subscription register and transfer entry join six chamber seals to ships remaining on an Asian route beyond the investor's horizon.",
      imagePosition: "center center",
      mobileImagePosition: "54% center",
      visualLabel: "VOC capital book, chamber seals and continuing fleet",
      visualTone: "permanent-capital",
      side: "left",
      sourceIds: [
        "israel-1995",
        "gelderblom-2013",
        "petram-2014",
        "gelderblom-jonker-2004",
      ],
      evidence: [
        "The 1602 VOC charter united earlier companies in six chambers, raised over six million guilders and granted a twenty-one-year monopoly with governmental and military powers overseas.",
        "The charter anticipated an account after ten years; in 1612 the States General left the subscribed capital with the company while investors obtained liquidity by transferring registered shares.",
      ],
      map: { x: 40, y: 47 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "permanent-joint-capital",
        prompt: "Make capital permanent",
        accessibleSummary:
          "Four states combine subscriptions in six VOC chambers, hold the subscribed fund across overlapping voyages, preserve the company at the ten-year account and transfer one investor's claim without recalling a ship.",
        initialId: "subscribe",
        records: [
          {
            id: "subscribe",
            label: "Combine the subscriptions",
            period: "1602",
            kicker: "Six chambers form one fund",
            detail:
              "Investors enter sums in the chamber registers until local subscriptions form a company capital exceeding six million guilders.",
            fields: [
              { label: "Instrument", value: "Signed capital register" },
              { label: "Structure", value: "Six chambers and the Heeren XVII" },
              { label: "Claim", value: "A proportional book entry" },
            ],
            outcome:
              "Competing voyage funds become one enterprise capable of fitting out fleets at scale.",
          },
          {
            id: "commit",
            label: "Commit the common fund",
            period: "1602–1612",
            kicker: "Voyages overlap",
            detail:
              "The company pays for ships, cargo, factories and protection while earlier expeditions remain away and later departures are prepared.",
            fields: [
              { label: "Duration", value: "Longer than one return voyage" },
              {
                label: "Assets",
                value: "Ships, stores and Asian establishments",
              },
              {
                label: "Management",
                value: "Directors act for the common capital",
              },
            ],
            outcome:
              "Capital supplies continuity where a succession of liquidated partnerships would interrupt command.",
          },
          {
            id: "continue",
            label: "Pass the ten-year account",
            period: "1612–1623",
            kicker: "The company remains intact",
            detail:
              "The States General permits the VOC to continue without returning and reassembling its entire fund; charter renewal confirms the durable enterprise.",
            fields: [
              {
                label: "Original horizon",
                value: "A general account after ten years",
              },
              { label: "Decision", value: "No liquidation in 1612" },
              { label: "Result", value: "Continuing joint capital" },
            ],
            outcome:
              "Fleet, establishments and management outlive the first promised reckoning date.",
          },
          {
            id: "transfer",
            label: "Transfer the investor's claim",
            period: "While the ships remain away",
            kicker: "Liquidity changes the name, not the fleet",
            detail:
              "A seller and buyer appear before the chamber bookkeeper, who debits one account and credits another with the agreed portion of VOC capital.",
            fields: [
              {
                label: "Seller receives",
                value: "A market price in cash or credit",
              },
              {
                label: "Buyer receives",
                value: "The registered company claim",
              },
              {
                label: "Company keeps",
                value: "Its ships and working capital",
              },
            ],
            outcome:
              "One investor exits while the common enterprise continues across the ocean.",
          },
        ],
      },
    },
    {
      id: "lake-becomes-a-ledger",
      actId: "water-ships-system",
      order: 6,
      period: "AD 1607–1612",
      place: "The Beemster",
      title: "A Lake Becomes a Ledger",
      thesis:
        "A ring dike, staged wind power and audited maintenance converted a dangerous lake into a measured agricultural landscape.",
      body: [
        "The Beemster had widened from a peat stream into a lake whose waves ate at the settled shore north of Amsterdam. In 1607 the States of Holland authorised a group of investors and officials to reclaim it. Surveyors marked a ring around the water. Labourers dug a canal outside that line and raised the excavated earth into a dike. Dozens of windmills were arranged in stages, each lifting water into a higher basin until the final stream could pass into the ring canal. A single mill could move water; only a governed chain could empty the lake.",
        "The nearly completed work failed its first test in 1610 when storm water broke through and flooded the basin again. The undertakers raised and strengthened the ring dike, repaired the machinery and resumed pumping. In May 1612 the floor lay dry. Surveyors imposed an exact grid of roads and drainage channels, dividing roughly 7,200 hectares into rectangular farms connected to Amsterdam's food market. Maps, numbered plots and assessments translated a shifting sheet of water into property whose boundaries and obligations could be read.",
        "Reclamation began a permanent drainage regime. Peat and clay settled, rain continued to fall and every neglected ditch raised another neighbour's water. The water board inspected levels, apportioned levies, maintained dikes and mills and recorded expenditure against the land that benefited. Investors gained farms because a public institution kept thousands of private acres inside one hydraulic regime. Beemster displayed the republic's governing method in its purest material form: independent owners accepted measurement, assessment and continuous common work, and their agreement produced an inhabitable geometry where ships had floated five years before.",
      ],
      image: `${imageRoot}/06-lake-becomes-a-ledger.avif`,
      imageAlt:
        "The Beemster plan emerges as staged windmills lift water over a ring dike and survey lines divide the dry lake floor into roads, canals and farms.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualLabel: "Polder plan, mill stages and audited assessment",
      visualTone: "delft-water",
      side: "right",
      sourceIds: ["de-vries-van-der-woude-1997", "van-de-ven-2004"],
      evidence: [
        "The Beemster was enclosed and pumped dry between 1607 and 1612 by a ring dike, ring canal and a staged system of over forty windmills.",
        "After a 1610 inundation forced renewed work, the reclaimed lake bed was surveyed into a geometric agricultural grid whose drainage required continuing collective maintenance.",
      ],
      map: { x: 40, y: 46 },
    },
    {
      id: "bank-makes-money-stable",
      actId: "trust-machinery",
      order: 7,
      period: "AD 1609",
      place: "Amsterdam town hall",
      title: "The Bank Makes Money Stable",
      thesis:
        "The Wisselbank replaced judgment over hundreds of worn coins with a municipal ledger unit in which large payments could clear by written transfer.",
      body: [
        "A merchant receiving coin in Amsterdam confronted a metallic archive of Europe. Ducats, rixdollars, patagons and smaller pieces came from many mints; wear, clipping and changing ordinances altered what a stamped face was worth. Money changers weighed and assayed, yet a bill due today could not wait for every coin in a sack to be argued over. Debased pieces tended to circulate while heavier coins disappeared into hoards or export. The confusion imposed a cost on every large bargain made in a city whose commerce depended on accepting the world's money.",
        "Amsterdam founded the Wisselbank in 1609 inside the town hall. A depositor presented approved coin, which the bank valued by weight and fineness before crediting an account in bank guilders. Payment then required no cart of silver. The payer instructed the clerk to debit one ledger balance and credit another; the books preserved the equality of the entries. City rules directed important bills through the bank, enlarging the circle of merchants who held accounts and making its unit the common language of wholesale settlement.",
        "The early bank's authority rested on metal received, exact bookkeeping and the guarantee of Amsterdam's government. Its money held a stable value against the variable current coin used in the street, and merchants willingly valued bank balances at a premium when metallic currency deteriorated. Later generations of managers expanded credit and altered the relation between deposits and reserves. The institution founded in 1609 achieved its first revolution with the simpler act visible on the counter: it inspected heterogeneous coin once, entered reliable value in a public ledger and allowed that value to move through commerce by a pair of written lines.",
      ],
      image: `${imageRoot}/07-bank-makes-money-stable.avif`,
      imageAlt:
        "Assayed European coins settle on a balance beside the Amsterdam Wisselbank ledger, where one payment appears as matched debit and credit entries.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "Coin scale, assay counter and municipal ledger",
      visualTone: "copper-clearing",
      side: "left",
      sourceIds: [
        "quinn-roberds-large-bills",
        "dehing-2012",
        "gelderblom-2013",
      ],
      evidence: [
        "Amsterdam founded the Wisselbank in 1609 to receive and value approved coin and to settle payments through transfers between ledger accounts.",
        "Bank money supplied a dependable wholesale accounting unit amid circulating coins that differed in mint, weight, fineness and market value.",
      ],
      map: { x: 40, y: 47 },
    },
    {
      id: "the-bourse-prices-the-world",
      actId: "trust-machinery",
      order: 8,
      period: "AD 1611–1688",
      place: "Amsterdam exchange",
      title: "The Bourse Prices the World",
      thesis:
        "The exchange gathered counterparties, transferable claims and fresh intelligence at one appointed hour, turning distant uncertainty into a public price.",
      body: [
        "At the exchange bell, Amsterdam's merchants entered Hendrick de Keyser's rectangular court and took familiar positions beneath its arcades. Brokers knew where dealers in Baltic grain, bills on Hamburg, marine insurance or VOC shares were likely to stand. The building supplied no cargo and guaranteed no voyage. It concentrated attendance. A merchant who might otherwise spend a day finding the holder of a compatible obligation could cross the court, compare terms and settle before the trading hour ended. Architecture and schedule made liquidity visible as a crowd.",
        "News arrived in the same space. A skipper reported ice in the Sound; a courier brought a peace rumour from The Hague; an Asian return fleet was sighted or overdue. Merchants tested each report against letters, shipping lists and the willingness of others to buy. Offers changed as information acquired credibility. Bills of exchange translated obligations between cities and currencies, Wisselbank balances supplied dependable settlement, and VOC shares allowed expectations about a continuing enterprise to be bought or sold. Each instrument answered a different problem, yet the hall let them work upon one another.",
        "By 1688, when Joseph de la Vega described Amsterdam share dealings, the market supported forward bargains, options and strategies complex enough to reward speed and punish credulity. Its durable civilizational achievement was public price formation. The bourse exposed a merchant's private estimate to competing estimates and produced a price at which another person would act. A Baltic harvest, Hamburg bill and ship beyond the Cape entered one European room as comparable risks. The exchange made the world's uncertainty legible enough to finance, and the scale of trade grew because thousands of obligations could be cleared without requiring one merchant, bank or government to command them all.",
      ],
      image: `${imageRoot}/08-the-bourse-prices-the-world.avif`,
      imageAlt:
        "Amsterdam's arcaded exchange holds a coin packet, Hamburg bill, VOC transfer and shipping notice at four connected stations around the crowded court.",
      imagePosition: "center center",
      mobileImagePosition: "55% center",
      visualLabel: "The Exchange Hall · bank, bourse, shares and news",
      visualTone: "exchange-gold",
      side: "right",
      sourceIds: ["gelderblom-2013", "petram-2014", "lesger-2006"],
      evidence: [
        "Amsterdam's purpose-built exchange opened in 1611 and concentrated merchants, brokers, bills, commodities, insurance and securities at fixed trading hours.",
        "Transferable VOC shares and a dense information market supported increasingly sophisticated secondary trading during the seventeenth century.",
      ],
      map: { x: 40, y: 47 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "exchange-hall",
        prompt: "Clear the exchange",
        accessibleSummary:
          "Four deliberate stations take a merchant packet from mixed coin through Wisselbank ledger money and a Hamburg bill to a VOC share counterparty, then apply fresh shipping news to the quoted risk without treating profit as the goal.",
        initialId: "assay-coin",
        records: [
          {
            id: "assay-coin",
            label: "Assay the coin",
            period: "Wisselbank counter",
            kicker: "Many mints enter one unit",
            detail:
              "The clerk weighs the merchant's approved coins, judges their fineness and credits the accepted value to a bank account.",
            fields: [
              { label: "Packet", value: "Coins of several standards" },
              { label: "Test", value: "Weight and fineness" },
              { label: "Result", value: "Ledger balance in bank guilders" },
            ],
            outcome:
              "Metallic disagreement is settled once before the value enters wholesale payment.",
          },
          {
            id: "clear-bill",
            label: "Clear the Hamburg bill",
            period: "Bank ledger",
            kicker: "The obligation moves by entry",
            detail:
              "The merchant uses the dependable balance to discharge a bill drawn through Hamburg, matching payer and receiver without moving another sack of coin.",
            fields: [
              { label: "Instrument", value: "Bill of exchange" },
              { label: "Settlement", value: "Debit and credit instruction" },
              {
                label: "Risk exposed",
                value: "Date, currency and counterparty",
              },
            ],
            outcome:
              "A distant debt becomes a completed pair of entries that both parties can recognise.",
          },
          {
            id: "transfer-share",
            label: "Transfer the VOC share",
            period: "Exchange floor and chamber book",
            kicker: "The investor leaves; the fleet remains",
            detail:
              "A broker finds a buyer at the quoted price, and the chamber register moves the claim from seller to purchaser while company capital stays employed overseas.",
            fields: [
              { label: "Counterparty", value: "Buyer found at the bourse" },
              { label: "Price", value: "Agreed against current information" },
              { label: "Continuity", value: "No ship or capital recalled" },
            ],
            outcome:
              "Transferability divides the investor's time from the duration of the enterprise.",
          },
          {
            id: "read-news",
            label: "Price the shipping news",
            period: "Before the bell ends",
            kicker: "Uncertainty becomes public",
            detail:
              "A dated notice changes the expected arrival of a cargo; bids and offers adjust as merchants compare the report with letters, routes and one another's willingness to trade.",
            fields: [
              { label: "Notice", value: "A return fleet reported late" },
              { label: "Revision", value: "Arrival risk rises" },
              { label: "Visible result", value: "A changed bid and offer" },
            ],
            outcome:
              "The packet is cleared with its obligations settled and its remaining risk made visible in a contested price.",
          },
        ],
      },
    },
    {
      id: "republic-borrows-from-its-citizens",
      actId: "trust-machinery",
      order: 9,
      period: "The seventeenth century",
      place: "Holland's towns and provincial offices",
      title: "The Republic Borrows from Its Citizens",
      thesis:
        "Earmarked taxes, public accounts and transferable obligations let a federation without a royal treasury sustain war across generations.",
      body: [
        "War required money before a year's excises and property assessments had arrived. Admiralties ordered hulls, frontier towns demanded repairs and soldiers expected pay whether a tax collector had completed his round or not. Holland met the interval by selling annuities and redeemable bonds to citizens, institutions and office-holders. A purchaser delivered capital now in exchange for a scheduled stream of interest secured on provincial revenues. The document named the obligation; the tax system made the promise credible.",
        "Credit rested on a chain of institutions visible to the lender. Town collectors received excises and other levies, local offices kept accounts, provincial receivers assembled quotas and the States of Holland authorised debt service. Wealthy towns could watch the government in which their regents sat, while widows, orphan chambers and charitable bodies sought dependable income from public securities. Claims could be transferred, so a lender's need for cash did not automatically become the government's need to repay principal at once. Regular service enlarged demand and lowered the interest at which the next loan could be sold.",
        "The republic carried a debt measured in hundreds of millions of guilders by the end of the War of the Spanish Succession. The burden consumed revenue and reveals the astonishing sums a small federation had persuaded its inhabitants to entrust to public offices. Dutch fleets and fortresses could be maintained against monarchies drawing on far larger populations because future taxes had been converted into present force at comparatively low cost. The financial revolution joined citizenship to state capacity through a repeated bargain: accounts made taxes credible, credible taxes supported debt and honoured debt brought the next lender to the provincial desk.",
      ],
      image: `${imageRoot}/09-republic-borrows-from-its-citizens.avif`,
      imageAlt:
        "Excise receipts from a ring of Holland towns enter a provincial account beside an annuity bond whose scheduled payments are marked as honoured.",
      imagePosition: "57% center",
      mobileImagePosition: "63% center",
      visualLabel: "Provincial bond, tax receipts and payment register",
      visualTone: "funded-credit",
      side: "left",
      sourceIds: ["fritschy-2017", "tracy-1985", "gelderblom-jonker-2004"],
      evidence: [
        "Holland and its towns issued annuities and redeemable obligations whose interest was supported by regular provincial and urban taxation.",
        "Transferable public claims and a record of debt service helped the republic borrow at comparatively low rates and sustain long wars without a central royal treasury.",
      ],
      map: { x: 40, y: 47 },
    },
    {
      id: "city-opens-a-market-for-mind",
      actId: "republic-commands-distance",
      order: 10,
      period: "AD 1620–1670",
      place: "Amsterdam, Leiden and The Hague",
      title: "The City Opens a Market for the Mind",
      thesis:
        "Privileged presses, a great university and practical religious latitude made Dutch cities Europe's clearing house for books, images and disputed ideas.",
      body: [
        "A manuscript refused in one European capital could travel to a Dutch printing house with a merchant's letter. Leiden University drew scholars into a town whose printers possessed Greek, Hebrew and Latin type, while Amsterdam offered paper, engraving, finance and shipping on an exceptional scale. The Elzevir workshops produced compact scholarly editions; Willem and Joan Blaeu joined surveying, astronomy, copperplate skill and commercial distribution in atlases made for a continental market. Books left in the same holds as cloth and instruments, and catalogues let distant buyers order an argument they had never seen.",
        "The Reformed Church occupied the recognised public position, and magistrates enforced limits that varied by city and moment. Catholics often worshipped in concealed churches; Mennonites and other dissenters organised congregations; Sephardic Jews built commercial, charitable and intellectual institutions in Amsterdam. Latitude depended on municipal practice: a congregation could gain room to worship and work without receiving equal public standing. That room attracted Huguenots, Jews, Protestants from the southern Netherlands and writers seeking a press. Their languages, trading partners and learning enlarged the cities that admitted them.",
        "The same market rewarded painters, lens grinders, mapmakers and philosophers. Rembrandt sold biblical histories and portraits beyond a single court; domestic buyers filled houses with landscapes, seascapes and scenes of civic life. Descartes worked for years in the republic, and Spinoza's books entered European controversy through Dutch presses and clandestine distribution. Leiden's lecture room, an Amsterdam print shop, a notary's office and a painting auction belonged to one urban information economy. Reputation could attract pupils, patrons and buyers across borders, giving the small republic a cultural reach commensurate with its ships.",
      ],
      image: `${imageRoot}/10-city-opens-a-market-for-mind.avif`,
      imageAlt:
        "An Amsterdam print shop opens toward a Leiden library, Blaeu map cabinet and domestic picture sale, with authenticated pages and plates at each station.",
      imagePosition: "center center",
      mobileImagePosition: "53% center",
      visualLabel: "Press, university, map cabinet and picture market",
      visualTone: "linen-print",
      side: "right",
      sourceIds: ["israel-1995", "frijhoff-spies-2004", "schama-1987"],
      evidence: [
        "Leiden University and Dutch publishing houses made the republic a major European centre for scholarship, cartography and the international book trade.",
        "The Reformed Church held public privilege, while variable municipal toleration allowed several dissenting and migrant communities to worship, work and publish with latitude unusual in seventeenth-century Europe.",
      ],
      map: { x: 40, y: 47 },
    },
    {
      id: "water-line-saves-the-republic",
      actId: "republic-commands-distance",
      order: 11,
      period: "AD 1672–1674",
      place: "The Holland Water Line and the North Sea",
      title: "The Water Line Saves the Republic",
      thesis:
        "Under attack by land and sea, the republic reversed its drainage works into a controlled barrier and coordinated them with forts, field forces and a fighting fleet.",
      body: [
        "In 1672 Louis XIV's army crossed the Rhine and advanced through the eastern provinces while Münster and Cologne attacked from another direction. England opened war at sea. Utrecht fell, panic reached the towns of Holland and the republican government of Johan de Witt collapsed amid political violence. The defensive line protecting the rich western province appeared too thin to hold Europe's strongest army. The Dutch answered by opening sluices, cutting selected dikes and stopping pumps across a band of low polder country from the Zuiderzee toward the great rivers.",
        "The operation demanded exact levels. Too little water left roads passable; too much allowed boats to cross and threatened the towns behind the line. Water-board officers, military engineers, farmers and municipal authorities argued over sluices and sacrificed crops, then held a shallow inundation broken by guarded dikes, causeways and fortified approaches. The same infrastructure that usually expelled water now admitted and retained it by rule. French cavalry and artillery could not deploy across the flooded fields, and the advance stopped before Holland's urban core.",
        "At sea, Michiel de Ruyter's fleet denied the combined Anglo-French forces the freedom needed for an invasion from the west. On land, William III used the breathing space to rebuild field resistance and maintain alliances. The republic lost territory, wealth and two of its leading statesmen while its distributed institutions continued to execute a common defence under extreme pressure. By 1674 England, Münster and Cologne had left the war and French troops had withdrawn from the occupied provinces. Water board, admiralty, town and provincial assembly had turned ordinary civic capacity into strategic survival.",
      ],
      image: `${imageRoot}/11-water-line-saves-the-republic.avif`,
      imageAlt:
        "A dated Holland Water Line map shows sluices opening, shallow inundation spreading between guarded causeways and De Ruyter's fleet holding the sea perimeter.",
      imagePosition: "center center",
      mobileImagePosition: "54% center",
      visualLabel: "Sluice orders, inundation section and naval perimeter",
      visualTone: "inundation-line",
      side: "left",
      sourceIds: ["israel-1995", "t-hart-2014", "rowen-1978"],
      evidence: [
        "France, England, Münster and Cologne attacked the Dutch Republic in 1672, producing military crisis and a change of political leadership.",
        "Controlled inundation along the Old Holland Water Line impeded the French advance, while De Ruyter's fleet helped prevent the maritime coalition from exploiting its naval threat.",
      ],
      map: { x: 41, y: 49 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "common-water",
        prompt: "Command the common water",
        accessibleSummary:
          "Four water states begin with the maintained polder, reverse its sluices into a shallow defensive inundation, secure the exposed causeways and join the water line to the fleet guarding the coast.",
        initialId: "maintained-polder",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "maintained-polder",
            label: "Maintain the common field",
            period: "Ordinary water government",
            kicker: "Drainage keeps the land usable",
            detail:
              "Dikes exclude high water while mills, canals and sluices move rain and seepage outward under water-board inspection and levy.",
            fields: [
              { label: "Obligation", value: "Inspect, assess and repair" },
              { label: "Direction", value: "Water moves out" },
              { label: "Result", value: "Farms and roads remain dry" },
            ],
            outcome:
              "Collective maintenance creates a landscape whose water level can be governed.",
            points: [
              {
                id: "amsterdam",
                label: "Amsterdam",
                detail: "The urban core depends on maintained polder country.",
                x: 40,
                y: 47,
              },
              {
                id: "gouda",
                label: "Gouda",
                detail: "Sluices and river approaches govern the central line.",
                x: 40,
                y: 49,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "reverse-sluices",
            label: "Reverse the sluices",
            period: "June–July 1672",
            kicker: "The drained land becomes a barrier",
            detail:
              "Authorities open selected inlets, stop pumps and retain a shallow sheet of water across the low fields before the French army reaches Holland.",
            fields: [
              { label: "Direction", value: "River and sea water move in" },
              {
                label: "Depth",
                value: "Too deep to march, too shallow to sail",
              },
              { label: "Cost", value: "Farms, roads and harvests submerged" },
            ],
            outcome:
              "The knowledge used to drain a polder supplies the precision required to inundate it.",
            points: [
              {
                id: "muiden",
                label: "Muiden",
                detail: "The northern end anchors the line near the Zuiderzee.",
                x: 41,
                y: 47,
              },
              {
                id: "woerden",
                label: "Woerden",
                detail:
                  "Flooded approaches and guarded works cover the centre.",
                x: 41,
                y: 49,
              },
              {
                id: "gorinchem",
                label: "Gorinchem",
                detail: "River defences support the southern approaches.",
                x: 41,
                y: 51,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "guard-passages",
            label: "Guard the dry passages",
            period: "The line holds",
            kicker: "Every road becomes a gate",
            detail:
              "Troops, guns and earthworks occupy dikes, causeways and higher ground where an attacker could otherwise cross the controlled water.",
            fields: [
              { label: "Weak point", value: "Road, dike or natural rise" },
              { label: "Answer", value: "Fort, battery and patrol" },
              { label: "Coordination", value: "Town, army and water board" },
            ],
            outcome:
              "Hydraulic depth and defended passages combine into a continuous military obstacle.",
            points: [
              {
                id: "naarden",
                label: "Naarden",
                detail: "A fortified approach protects the northern route.",
                x: 42,
                y: 47,
              },
              {
                id: "nieuwpoort",
                label: "Nieuwpoort",
                detail: "River and road works help close a southern passage.",
                x: 40,
                y: 50,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "hold-sea",
            label: "Hold the sea perimeter",
            period: "1672–1673",
            kicker: "The fleet closes the other road",
            detail:
              "De Ruyter's squadrons contest the combined enemy fleets so that the land barrier cannot be bypassed by an unopposed descent on Holland's coast.",
            fields: [
              { label: "Land instrument", value: "Sluice, dike and fortress" },
              {
                label: "Sea instrument",
                value: "Fleet, convoy and shoal knowledge",
              },
              {
                label: "Strategic result",
                value: "Time for alliance and recovery",
              },
            ],
            outcome:
              "The republic survives because its civic water system and maritime system defend one another.",
            points: [
              {
                id: "texel",
                label: "Texel approaches",
                detail: "The fleet protects the republic's maritime entrance.",
                x: 39,
                y: 44,
              },
              {
                id: "holland",
                label: "Holland Water Line",
                detail: "The inundation shields the urban heart by land.",
                x: 41,
                y: 49,
              },
            ],
            links: [[0, 1]],
          },
        ],
      },
    },
    {
      id: "system-crosses-the-north-sea",
      actId: "republic-commands-distance",
      order: 12,
      period: "AD 1688–1713",
      place: "Amsterdam, The Hague and London",
      title: "The System Crosses the North Sea",
      thesis:
        "William III's armed crossing joined two maritime powers, and England adapted Dutch public credit, banking and securities to a larger constitutional state.",
      body: [
        "In autumn 1688, Dutch shipyards, admiralties, financiers and the States General assembled an expedition able to carry roughly fifteen thousand troops across the North Sea under William III. Hundreds of transports and escorts sailed from several ports, crossed under disciplined convoy and landed at Torbay. English opponents of James II had invited intervention; officers, towns and political leaders then shifted toward William as his army advanced. James fled, and the English Convention offered the crown to William and Mary under constitutional terms fixed in the settlement of 1689.",
        "The crossing joined Dutch strategic purpose to English scale. The new regime entered the long war against Louis XIV, demanding armies and fleets whose cost exceeded ordinary revenue. Parliament authorised taxes and loans, creditors gained enforceable claims on future income, and the Bank of England opened in 1694. English ministers and investors drew on practices already mature in the republic—funded obligations, transferable securities, a public bank and an active secondary market—then combined them with parliamentary government and a much larger tax base.",
        "By the Peace of Utrecht in 1713, the alliance had checked French predominance and Britain possessed a financial-military capacity that would surpass the republic's. Amsterdam remained a central market where European bills, securities and intelligence cleared, while Dutch capital helped finance opportunities beyond the provinces. The transfer measures the achievement. A political order created among threatened towns had developed ways to keep capital in motion, government credit credible and information public; those ways could cross a sea and expand inside another European constitution. Beside both exchanges, printed news now invited readers with no share to trade to judge the conduct of states.",
      ],
      image: `${imageRoot}/12-system-crosses-the-north-sea.avif`,
      imageAlt:
        "A Dutch convoy route reaches an English parliamentary document and the 1694 Bank of England ledger, linking the Amsterdam and London exchange floors.",
      imagePosition: "58% center",
      mobileImagePosition: "66% center",
      visualLabel: "Convoy plan, constitutional settlement and bank ledger",
      visualTone: "north-sea-transfer",
      side: "right",
      sourceIds: ["israel-1995", "pincus-2009", "neal-1990"],
      evidence: [
        "William III's Dutch-backed expedition carried an army to England in 1688 and led to the joint monarchy of William and Mary under the constitutional settlement of 1689.",
        "England established funded borrowing and the Bank of England during the ensuing war, adapting financial practices developed in the Dutch Republic to parliamentary institutions and a larger fiscal base.",
      ],
      map: { x: 35, y: 48 },
    },
  ],
};
