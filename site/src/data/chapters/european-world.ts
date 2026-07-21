import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/european-world";

export const europeanWorld: ChapterDefinition = {
  slug: "european-world",
  number: "21",
  title: "The European World",
  openingTitleLines: ["The European", "World"],
  period: "AD 1802–1914",
  claim:
    "Europe placed the world on schedule. Steam routes, cables, railways, surveys, public-health agreements, postal rules and administrative law carried European power across the earth—and left a connected institutional world where distance had lost its old command.",
  openingClaim:
    "Europe joined oceans and continents to a working switchboard of routes, clocks, offices and common rules that distant ports and states could operate, adapt and inherit.",
  hero: {
    image: `${imageRoot}/01-the-sea-acquires-a-law.avif`,
    mobileImage: `${imageRoot}/01-the-sea-acquires-a-law-mobile.avif`,
    imageAlt:
      "A Royal Navy anti-slavery patrol boards a slave ship at dawn while an Admiralty chart, signal flags and a brass switchboard connect the Atlantic approaches to Freetown.",
    imagePosition: "center center",
    mobileImagePosition: "58% center",
    visualLabel: "The World’s Switchboard · patrol, cable, rail and protocol",
  },
  theme: {
    id: "switchboard",
    label: "The World’s Switchboard",
  },
  openingAction: "Open the Atlantic circuit",
  mapLabel:
    "The sea lanes, cables, railways, surveys, ports and international offices through which Europe joined the world to common schedules and rules",
  routeImage: "assets/world-relief.jpg",
  openingRouteImage: "assets/world-relief.jpg",
  sourcesEyebrow:
    "Patrol logs · sailing tables · cable records · treaties · postal conventions · survey sheets · railway reports · sanitary agreements · port plans",
  acts: [
    {
      id: "oceans-obey-schedule",
      number: "I",
      label: "The oceans obey a schedule",
      period: "AD 1815–1869",
      title: "The Oceans Obey a Schedule",
      detail:
        "Naval command, steam propulsion, submarine cable and the Suez Canal turn the sea from an interval into a managed route.",
    },
    {
      id: "world-learns-protocols",
      number: "II",
      label: "The world learns common protocols",
      period: "AD 1865–1884",
      title: "The World Learns Common Protocols",
      detail:
        "European states give messages, letters and clocks common rules that allow them to cross frontiers without losing their meaning.",
    },
    {
      id: "steel-enters-continents",
      number: "III",
      label: "Steel enters the continents",
      period: "AD 1802–1907",
      title: "Steel Enters the Continents",
      detail:
        "Railways, surveys, canals, ports, schools, hospitals and administrative offices carry command inland and create durable public capacities.",
    },
    {
      id: "europe-takes-central-desk",
      number: "IV",
      label: "Europe takes the central desk",
      period: "AD 1884–1914",
      title: "Europe Takes the Central Desk",
      detail:
        "European capitals organise territory, capital, exhibitions, shipping and information on a scale that makes the earth answer to one working day.",
    },
  ],
  ending: {
    period: "Summer 1914",
    title: "The World Has a European Centre",
    detail:
      "The cable clerk closes the last circuit and the switchboard stands complete. Steam lanes meet railways; surveyed ports meet banks; postal bags, sanitary notices and telegrams pass through offices trained to recognise the same address, tariff and hour. Europe’s enduring overseas work was this common order across distance: institutions that could be learned, copied and inherited wherever the lines reached. One red lamp remains lit after the clerks leave. A mobilisation telegram is entering the same wires that carried prices and passenger lists, turning the world’s European nervous system toward continental war.",
    image: `${imageRoot}/15-world-has-european-centre.avif`,
    mobileImage: `${imageRoot}/15-world-has-european-centre-mobile.avif`,
    nextPeriod: "AD 1914–1945",
  },
  returnHash: "european-world",
  nextHash: "europe-at-war",
  nextTitle: "The European Civil War",
  nextSlug: "europe-at-war",
  movements: [
    {
      id: "the-sea-acquires-a-law",
      actId: "oceans-obey-schedule",
      order: 1,
      period: "AD 1815–1869",
      place: "London, Freetown and the Atlantic approaches",
      title: "The Sea Acquires a Law",
      thesis:
        "British command of the Atlantic gave abolition a fleet, a treaty system and courts able to strike at the slave trade on the water.",
      body: [
        "At first light, a Royal Navy boat pulled across the Atlantic swell toward a vessel that had altered course at the sight of a cruiser. Sailors climbed the side with pistols, cutlasses and written orders. Below deck they found enslaved captives whom the captain had tried to carry beyond British reach. After Parliament abolished the British slave trade in 1807, the West Africa Squadron made such pursuit a permanent duty. From bases including Freetown, its ships searched routes, examined papers, seized suspected slavers and carried captured vessels before courts empowered to condemn them.",
        "Naval strength alone could not make every seizure lawful. British ministers negotiated bilateral treaties granting rights of search, pressed allied and rival governments to prohibit the traffic, and established mixed commissions with foreign judges. The work was slow, dangerous and exacting. Slave traders changed flags, forged papers, built faster ships and shifted embarkation points; fever killed many patrol sailors, while armed crews sometimes resisted boarding. Every treaty widened the water on which a slaver could be stopped, and every condemned hull converted a moral prohibition into an enforceable rule of the sea.",
        "Thousands of Africans taken from intercepted ships landed at Freetown and other ports instead of crossing the Atlantic into slavery. Plantations, credit and complicit governments kept the traffic alive, while naval pursuit made every continued voyage harder, costlier and less secure as abolition advanced through Brazil, Cuba and the wider Atlantic world. Europe’s most powerful navy had once guarded profitable movement. It now spent ships, money and lives to suppress one of the cruellest forms of commerce, proving that a principle proclaimed in Parliament could acquire reach far beyond Europe’s shore.",
      ],
      image: `${imageRoot}/01-the-sea-acquires-a-law.avif`,
      mobileImage: `${imageRoot}/01-the-sea-acquires-a-law-mobile.avif`,
      imageAlt:
        "Royal Navy sailors board an Atlantic slave ship at dawn as rescued captives wait under protection beside the ship’s register.",
      imagePosition: "57% center",
      mobileImagePosition: "62% center",
      visualLabel: "Patrol chart, boarding order and captured-ship register",
      visualTone: "atlantic-patrol",
      side: "left",
      sourceIds: ["eltis-1987", "rees-2009"],
      evidence: [
        "The Royal Navy’s West Africa Squadron intercepted slave ships for more than half a century after British abolition of the trade, operating with Admiralty instructions and expanding treaty rights.",
        "Mixed-commission courts at Freetown and elsewhere adjudicated captured vessels and recorded Africans released from intercepted Atlantic crossings.",
      ],
      map: { x: 36, y: 45 },
    },
    {
      id: "steam-keeps-the-appointment",
      actId: "oceans-obey-schedule",
      order: 2,
      period: "AD 1838–1840",
      place: "Bristol, Liverpool and the North Atlantic",
      title: "Steam Keeps the Appointment",
      thesis:
        "Regular steam packets replaced the sailing estimate with a published departure and an arrival window narrow enough to organise business around it.",
      body: [
        "In April 1838, smoke appeared on the New York horizon above two vessels arriving from Britain under steam. Sirius had left Cork; Great Western had sailed from Bristol and reached New York soon after her smaller rival. Their crossings showed that a purpose-built steamship could carry enough coal for the North Atlantic and retain motive power when the wind failed. Sail remained useful and storms remained sovereign, but the engine supplied a continuous source of motion that a captain could measure against distance, fuel and time.",
        "Samuel Cunard’s contract for the British mail converted that feat into a service. From 1840, packets left Liverpool for Halifax and Boston on announced dates, carrying letters, passengers and high-value cargo. Coal bunkers, engineering watches, shore agents and mail offices became parts of the same promise. Merchants could arrange credit before departure, insurers could price a known vessel and route, and correspondents could anticipate when an answer should return. Reliability mattered more than a record passage because repeated appointments allowed other institutions to attach their work to the ship.",
        "Weather kept its power; the schedule organised preparation for its effects. Spare machinery, reserve coal, harbour tugs, coaling contracts and coordinated rail or coach connections narrowed the uncertainty around each voyage. Competing British, French, German and other European lines extended the method across the Atlantic and then along imperial and commercial routes. The printed table on a quay wall became an instrument of world power. Cargo, people, news and official orders could now enter an ocean crossing as one stage in a planned chain instead of a disappearance of unknowable length.",
      ],
      image: `${imageRoot}/02-steam-keeps-the-appointment.avif`,
      imageAlt:
        "A North Atlantic steam packet leaves Liverpool beside a printed sailing table, coal plan and engine-room watch bill aligned to the same clock.",
      imagePosition: "61% center",
      mobileImagePosition: "68% center",
      visualLabel: "Packet schedule, coal plan and engine watch",
      visualTone: "steam-schedule",
      side: "right",
      sourceIds: ["headrick-1981", "darwin-2009"],
      evidence: [
        "Sirius and Great Western completed pioneering westbound Atlantic steam crossings in April 1838.",
        "Cunard’s subsidised mail service began in 1840 and made regular advertised departures the organising principle of North Atlantic steam navigation.",
      ],
      map: { x: 48, y: 25 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "ocean-schedule",
        prompt: "Put the ocean on schedule",
        accessibleSummary:
          "Four dated states follow a North Atlantic passage from wind-dependent sailing through steam assistance to a regular packet service supported by coal, mail offices and onward connections.",
        initialId: "sailing-window",
        mapImage: "assets/world-relief.jpg",
        records: [
          {
            id: "sailing-window",
            label: "Wait for the wind",
            period: "c. AD 1830",
            kicker: "Departure begins with weather",
            detail:
              "A packet captain can estimate a passage, but contrary winds may delay both the day of sailing and the day on which a reply becomes possible.",
            fields: [
              { label: "Power", value: "Sail and prevailing wind" },
              {
                label: "Promise",
                value: "An intended passage, not a fixed arrival",
              },
            ],
            outcome:
              "Every business attached to the voyage carries the ocean’s uncertainty.",
            points: [
              {
                id: "liverpool",
                label: "Liverpool",
                detail: "A packet waits on wind and tide.",
                x: 49,
                y: 24,
              },
              {
                id: "new-york",
                label: "New York",
                detail: "The receiving office can only watch for sail.",
                x: 29,
                y: 31,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "steam-crossing",
            label: "Carry the engine",
            period: "AD 1838",
            kicker: "Motive power crosses the ocean",
            detail:
              "Purpose-built steamships allot hull space to engines and coal, sustaining progress through calms while retaining sail for economy and security.",
            fields: [
              {
                label: "Power",
                value: "Paddle engine, coal and auxiliary sail",
              },
              {
                label: "Constraint",
                value: "Fuel carried for the full crossing",
              },
            ],
            outcome:
              "The crossing becomes calculable in machinery watches and coal consumption.",
            points: [
              {
                id: "bristol",
                label: "Bristol",
                detail: "Great Western departs under steam in April 1838.",
                x: 48,
                y: 25,
              },
              {
                id: "new-york",
                label: "New York",
                detail: "Steam arrives after a measured ocean passage.",
                x: 29,
                y: 31,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "mail-contract",
            label: "Publish the departure",
            period: "AD 1840",
            kicker: "A voyage becomes a service",
            detail:
              "The mail contract joins packet, crew, shore office and announced sailing date in a repeated Liverpool–Halifax–Boston circuit.",
            fields: [
              { label: "Standard", value: "Advertised departures" },
              {
                label: "Cargo",
                value: "Mail, passengers and valuable freight",
              },
            ],
            outcome:
              "Merchants and correspondents can arrange their own work around the ship.",
            points: [
              {
                id: "liverpool",
                label: "Liverpool",
                detail: "The packet leaves on the published date.",
                x: 49,
                y: 24,
              },
              {
                id: "halifax",
                label: "Halifax",
                detail: "Mail and passengers enter the first receiving port.",
                x: 32,
                y: 27,
              },
              {
                id: "boston",
                label: "Boston",
                detail: "The scheduled circuit reaches its American terminus.",
                x: 30,
                y: 29,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "connected-service",
            label: "Join the timetable",
            period: "c. AD 1870",
            kicker: "The quay becomes one transfer point",
            detail:
              "Coaling stations, rail connections, agents, bills of lading and telegraph notices attach inland journeys and other sea routes to the packet’s arrival.",
            fields: [
              {
                label: "Infrastructure",
                value: "Coal, dock, rail and telegraph",
              },
              {
                label: "Result",
                value: "One journey assembled from timed stages",
              },
            ],
            outcome:
              "The ocean now carries a schedule that reaches beyond either shore.",
            points: [
              {
                id: "liverpool",
                label: "Liverpool",
                detail: "Rail, dock and packet share a timed transfer.",
                x: 49,
                y: 24,
              },
              {
                id: "new-york",
                label: "New York",
                detail:
                  "Arrival notices release mail, passengers and freight onward.",
                x: 29,
                y: 31,
              },
            ],
            links: [[0, 1]],
          },
        ],
      },
    },
    {
      id: "the-wire-crosses-water",
      actId: "oceans-obey-schedule",
      order: 3,
      period: "AD 1850–1866",
      place: "Dover, Valentia and Heart’s Content",
      title: "The Wire Crosses Water",
      thesis:
        "Insulated cable detached information from the speed of a ship and turned an ocean into a chain of electrical relays.",
      body: [
        "On the floor of a cable works, copper wire disappeared beneath layers of gutta-percha, jute and iron armour. The conductor had to carry a weak signal for miles; the insulation had to keep seawater from consuming it; the outer strands had to survive paying out from a rolling ship into depths no diver could reach. A first attempt across the Channel failed in 1850. The improved cable laid between Dover and Calais in 1851 held, allowing Britain and France to exchange market news and official messages in minutes.",
        "The Atlantic demanded a cable long enough to span an unseen seabed and strong enough to bear its own weight. The celebrated line of 1858 failed after a few weeks, exposing the limits of insulation, electrical testing and high-voltage signalling. Engineers learned from the wreck. In 1866, Great Eastern carried a new cable west from Valentia, Ireland, while electricians watched mirror galvanometers register faint currents aboard ship. At Heart’s Content in Newfoundland, the landing party brought the end ashore and joined Europe permanently to North America by telegraph.",
        "Information now moved without its messenger. A government could receive news before the vessel named in it arrived; a merchant could compare prices on two continents before committing a cargo; a newspaper could print an event while its witnesses were still an ocean away. Cable companies, landing stations, repair ships and trained operators gave the conductor an institutional body. Passengers still endured the Atlantic’s physical distance; information no longer accepted the same delay. The world’s switchboard began wherever a wet cable end entered a shore office.",
      ],
      image: `${imageRoot}/03-the-wire-crosses-water.avif`,
      imageAlt:
        "The armoured 1866 Atlantic cable passes from Great Eastern toward a Newfoundland landing station as a mirror galvanometer records the signal.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Cable section, paying-out gear and landing relay",
      visualTone: "cable-depth",
      side: "left",
      sourceIds: ["headrick-1991", "itu-submarine-telegraphy"],
      evidence: [
        "A durable submarine telegraph connection between Britain and France entered service in 1851 after the first experimental cable failed.",
        "Great Eastern completed the successful 1866 Atlantic cable between Valentia and Heart’s Content and recovered the lost 1865 line soon afterward.",
      ],
      map: { x: 39, y: 29 },
    },
    {
      id: "the-isthmus-opens",
      actId: "oceans-obey-schedule",
      order: 4,
      period: "AD 1869",
      place: "Port Said, Ismailia and Suez",
      title: "The Isthmus Opens",
      thesis:
        "The Suez Canal removed the voyage around Africa from the direct sea road between Europe and the Indian Ocean.",
      body: [
        "At the Mediterranean edge of the Egyptian desert, dredgers bit into sand while labourers carried baskets from the cut. Ferdinand de Lesseps’s concession and a French-led company supplied finance and direction; the Egyptian government supplied land, money and, during the early years, corvée labour summoned by authority. Fresh-water works, workshops and new settlements had to advance beside the maritime trench. The canal was an engineering project and an act of state power, built through harsh conditions that exacted sickness and death before mechanical excavation replaced much of the forced hand labour.",
        "On 17 November 1869, an international procession of ships entered the opened waterway. The canal ran without locks from Port Said to Suez, joining seas whose levels required no staircase. A voyage from western Europe to India no longer needed to round the Cape of Good Hope. Steamships benefited first because engines could hold a course through the narrow channel and scheduled coaling stops could support the remaining route. Marseille, Trieste, Brindisi and British ports acquired a shorter eastern road; Aden, Colombo and Singapore gained new value as stations along it.",
        "A cut through one isthmus rearranged strategy across half the world. Britain, initially suspicious of the French enterprise, soon became its greatest user and bought the Egyptian ruler’s shares in 1875. Egyptian debt and European intervention then drew the canal into the crisis that ended with British occupation in 1882. The waterway carried commerce and imperial command through the same banks: cotton, mail, pilgrims, troops and passengers all entered its measured channel. Geography had acquired an office, toll schedule and traffic rules, making the Mediterranean the western chamber of a route to the Indian Ocean.",
      ],
      image: `${imageRoot}/04-the-isthmus-opens.avif`,
      imageAlt:
        "An oblique view of the Suez Canal shows dredgers, Egyptian labourers, freshwater works and the first procession of steamships between marked banks.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Canal profile, labour record and measured sea route",
      visualTone: "isthmus-cut",
      side: "right",
      sourceIds: ["headrick-1981", "osterhammel-2014"],
      evidence: [
        "Construction of the Suez Canal began in 1859 under a concession from the Egyptian government and used Egyptian corvée labour extensively before mechanised excavation expanded.",
        "The lockless canal opened in November 1869 and greatly shortened the European steam route to the Red Sea and Indian Ocean.",
      ],
      map: { x: 59, y: 38 },
    },
    {
      id: "twenty-states-agree-on-the-signal",
      actId: "world-learns-protocols",
      order: 5,
      period: "17 May AD 1865",
      place: "Quai d’Orsay, Paris",
      title: "Twenty States Agree on the Signal",
      thesis:
        "The first International Telegraph Convention made permanent cooperation as important to communication as wire and electricity.",
      body: [
        "A telegram arriving at a frontier could stop for reasons invisible to the sender. The next administration might use another tariff, code, apparatus or method of accounting; an operator might have to copy the message onto paper and submit it again. European governments had negotiated regional agreements, but the growing network required rules broad enough for traffic from the Atlantic to the eastern Mediterranean. In 1865, delegates of twenty states met at the French foreign ministry in Paris with tables of charges, technical instructions and the accumulated failures of incompatible systems.",
        "The convention they signed established common provisions for accepting, transmitting, prioritising and charging international telegrams. Its accompanying regulations reached into daily work: how offices opened, how words were counted, how service messages passed and how administrations settled accounts. The delegates also created the International Telegraph Union, a permanent body able to revise the rules as instruments and routes changed. Sovereign states retained their networks, but each accepted procedures that allowed a message to leave one jurisdiction and remain recognisable in the next.",
        "The union was a European invention with planetary consequences. New members and colonial networks extended its standards, later conferences adapted them, and a small international bureau preserved technical memory between diplomatic meetings. This was institution-building at its most exact: no universal government, only an agreed convention, administrators instructed to obey it and recurring revision when practice exposed a fault. Copper supplied connection; protocol supplied continuity. Once alphabet, tariff and account could cross the frontier together, a telegraph line became part of one interoperable world rather than a row of national machines touching at their edges.",
      ],
      image: `${imageRoot}/05-twenty-states-agree-on-the-signal.avif`,
      imageAlt:
        "Delegates at the 1865 Paris telegraph conference compare tariff sheets and code tables as twenty labelled circuits enter a brass switchboard.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "Convention table, tariff sheet and twenty circuits",
      visualTone: "protocol-gold",
      side: "left",
      sourceIds: ["itu-1865-conference", "itu-pre-1865-agreements"],
      evidence: [
        "Delegates of twenty states signed the first International Telegraph Convention in Paris on 17 May 1865.",
        "The convention and its regulations standardised operational and financial procedures and created a permanent international union to maintain them.",
      ],
      map: { x: 50, y: 28 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "common-protocol",
        prompt: "Make one protocol",
        accessibleSummary:
          "Four cumulative records add a shared alphabet, tariff, accounting method and permanent revision office until a telegram can cross a frontier without being rebuilt at every border.",
        initialId: "recognise-signal",
        records: [
          {
            id: "recognise-signal",
            label: "Recognise the signal",
            period: "Paris · AD 1865",
            kicker: "The next office must read it",
            detail:
              "Administrations agree how an international telegram is written, counted and handed from one instrument or office to another.",
            fields: [
              { label: "Socket", value: "Alphabet and operating instruction" },
              {
                label: "Fault removed",
                value: "The signal no longer loses its form",
              },
            ],
            outcome: "The message crosses the border with its words intact.",
          },
          {
            id: "price-signal",
            label: "Price the signal",
            period: "Paris · AD 1865",
            kicker: "The sender must know the charge",
            detail:
              "Common tariff principles define what is counted and how each administration receives its share of the payment.",
            fields: [
              { label: "Socket", value: "Tariff and word count" },
              {
                label: "Fault removed",
                value: "Unpredictable frontier charges",
              },
            ],
            outcome:
              "An office can accept the telegram for a route beyond its own state.",
          },
          {
            id: "settle-account",
            label: "Settle the account",
            period: "Paris · AD 1865",
            kicker: "Every relay must be paid",
            detail:
              "Administrations keep comparable traffic records and reconcile what each one carried for the others.",
            fields: [
              { label: "Socket", value: "International accounting" },
              { label: "Fault removed", value: "A chain of unpaid relays" },
            ],
            outcome:
              "Separate national systems can carry one service without sharing one treasury.",
          },
          {
            id: "keep-protocol",
            label: "Keep the protocol",
            period: "After AD 1865",
            kicker: "Agreement acquires a memory",
            detail:
              "A permanent union, international bureau and later conferences preserve the rules and revise them as technology changes.",
            fields: [
              {
                label: "Socket",
                value: "Union, bureau and revision conference",
              },
              { label: "Fault removed", value: "A treaty frozen at signature" },
            ],
            outcome:
              "The world gains a protocol able to outlive the equipment that first required it.",
          },
        ],
      },
    },
    {
      id: "the-earth-becomes-one-postal-territory",
      actId: "world-learns-protocols",
      order: 6,
      period: "AD 1874–1878",
      place: "Bern",
      title: "The Earth Becomes One Postal Territory",
      thesis:
        "The Treaty of Bern replaced a maze of bilateral bargains with one postal territory governed by common carriage and accounting rules.",
      body: [
        "A letter from Lisbon to St Petersburg could accumulate rates, stamps and claims as each frontier handed it to the next administration. The sender had to depend on a mesh of bilateral agreements whose terms differed by route. German postal reformer Heinrich von Stephan proposed a simpler order: each member would treat the others as part of one territory for the reciprocal exchange of correspondence. Delegates from twenty-two countries met in Bern in 1874, examined the practical burdens of the old system and signed the General Postal Union into existence.",
        "The treaty established a common framework for international postage, transit and the division of payments. Each administration kept the revenue it collected for ordinary international letters while carrying incoming mail under agreed obligations; transit charges were simplified, and the freedom of transit protected a letter passing through intermediate territory. Bags could move sealed between exchange offices instead of being renegotiated at every border. In 1878, the organisation took the name Universal Postal Union as membership spread beyond its founding circle.",
        "The achievement entered ordinary life in a small rectangle of paper. A migrant could write home without mastering a diplomatic atlas. A scholar could send a journal, a manufacturer a catalogue, a family a photograph and a government a printed form through offices that shared a working grammar. Railways and steamships supplied speed, but the union gave every participating clerk authority to carry an unfamiliar person’s page onward. Europe’s states had turned cooperation into a public utility: national posts remained distinct while the correspondence entrusted to them travelled through one widening territory.",
      ],
      image: `${imageRoot}/06-the-earth-becomes-one-postal-territory.avif`,
      imageAlt:
        "A letter bearing successive European postmarks crosses a linen-backed map as bilateral rate sheets give way to one Treaty of Bern postal table.",
      imagePosition: "60% center",
      mobileImagePosition: "67% center",
      visualLabel: "Exchange bag, postmarks and Treaty of Bern table",
      visualTone: "postal-ivory",
      side: "right",
      sourceIds: ["upu-history", "golden-2009"],
      evidence: [
        "Twenty-two countries signed the Treaty of Bern in 1874 and established a General Postal Union based on a single postal territory.",
        "The organisation became the Universal Postal Union in 1878 as common rules for transit, exchange and accounting expanded internationally.",
      ],
      map: { x: 52, y: 27 },
    },
    {
      id: "noon-is-made-common",
      actId: "world-learns-protocols",
      order: 7,
      period: "October AD 1884",
      place: "Washington, Greenwich and the world’s ports",
      title: "Noon Is Made Common",
      thesis:
        "A shared prime meridian gave navigation, charts, telegraphs and timetables one reference from which to reckon position and time.",
      body: [
        "Every observatory could place zero longitude on its own meridian, and many national charts did. A ship carrying one set of tables and entering a port using another had to translate its position. Railways and telegraphs exposed a related confusion on land, where local noon shifted from town to town. By 1884, a large majority of the world’s shipping tonnage already used charts reckoned from Greenwich. The International Meridian Conference assembled delegates from twenty-five nations in Washington to decide whether practice should become a common rule.",
        "The delegates selected the meridian through the Royal Observatory at Greenwich as the prime meridian for longitude. They also recommended a universal day beginning at mean midnight on that meridian and counted continuously to twenty-four hours. Local civil time and the later adoption of time zones remained in national hands. The resolutions supplied a common coordinate to which a navigator’s calculation, a cable timestamp, an astronomical table and an international timetable could refer without first asking which zero the writer meant.",
        "An invisible line acquired material force through instruments and institutions. Observatory signals corrected chronometers; telegraph offices distributed time; station clocks and harbour authorities adopted coordinated standards according to national decisions. French, British, German and other European observatories continued their scientific work while sharing a framework that made results comparable. The world could keep many local hours and still meet on one measured earth. Greenwich became a socket on the switchboard because agreement had transformed one European meridian into common navigational language.",
      ],
      image: `${imageRoot}/07-noon-is-made-common.avif`,
      imageAlt:
        "A Greenwich transit instrument, marine chronometer and station clocks align with the prime-meridian chart approved at the 1884 conference.",
      imagePosition: "55% center",
      mobileImagePosition: "61% center",
      visualLabel: "Transit instrument, chronometer and universal day",
      visualTone: "meridian-glass",
      side: "left",
      sourceIds: ["meridian-conference-1884", "ogle-2015"],
      evidence: [
        "The 1884 International Meridian Conference selected Greenwich as the prime meridian and recommended a universal day counted from Greenwich mean midnight.",
        "The conference supplied a common reference for longitude and timekeeping while leaving civil time zones to national governments.",
      ],
      map: { x: 49, y: 24 },
    },
    {
      id: "the-survey-gives-the-state-a-map",
      actId: "steel-enters-continents",
      order: 8,
      period: "AD 1802–1901",
      place: "The Great Trigonometrical Survey and the Punjab canals",
      title: "The Survey Gives the State a Map",
      thesis:
        "European measurement joined territory to a single archive from which roads, boundaries, revenue works and irrigation could be planned.",
      body: [
        "In 1802, surveyors laid a measured baseline near Madras and began building triangles across India. Chains and compensation bars established distance; great theodolites fixed angles; astronomical observations tested position. Teams cleared sight lines, raised signals, climbed towers and carried instruments whose weight demanded crews of bearers. Over decades the Great Trigonometrical Survey connected plains, plateaux and Himalayan peaks to one geodetic frame. Errors became entries to be corrected rather than local mysteries, and separate maps could be related to the same measured skeleton.",
        "Measurement strengthened command. Revenue officers used cadastral sheets to identify fields and obligations; military planners examined passes and roads; engineers aligned bridges, canals and railways. The archive could expose territory to taxation, boundary-making and seizure as well as improvement. In the Punjab, British engineers extended a large irrigation system through headworks, distributaries and planned canal colonies. Water carried cultivation into dry tracts, while officials assigned land, regulated flow and moved cultivators under rules that joined hydraulic engineering to a new social landscape.",
        "A surveyed state acquired the power to remember decisions across distance and succession. Benchmarks remained after a particular officer departed; district maps could be revised; canal discharges and land records could be compared from year to year. Indian surveyors, draftsmen, engineers and clerks mastered the instruments and filled the archive on which government depended. After imperial rule ended, successor states retained rails, canals, departments, records and technical professions. European measurement had supplied a territorial language through which they could maintain works, settle jurisdictions and plan further connections.",
      ],
      image: `${imageRoot}/09-the-survey-gives-the-state-a-map.avif`,
      imageAlt:
        "Surveyors measure an Indian baseline with a great theodolite as triangulation resolves into cadastral sheets, a railway alignment and a Punjab canal plan.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "Baseline, triangulation, cadastral sheet and canal plan",
      visualTone: "survey-ivory",
      side: "left",
      sourceIds: [
        "edney-1997",
        "gilmartin-2015",
        "headrick-1988",
        "headrick-1991",
        "conklin-1997",
        "darwin-2007",
      ],
      evidence: [
        "The Great Trigonometrical Survey began with a baseline near Madras in 1802 and built a geodetic framework for mapping the subcontinent.",
        "Punjab canal works combined hydraulic engineering, land records, settlement and administrative control, creating extensive irrigated districts inherited by later governments.",
        "By 1914, surveys and administrative archives worked beside railways, ports and submarine cables in imperial systems whose physical works and trained services passed to successor governments.",
      ],
      map: { x: 72, y: 37 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "inherit-the-line",
        prompt: "Inherit the line",
        accessibleSummary:
          "Four dated network layers compare the survey and administrative, railway, and cable and port systems operating in 1914 with the governments that inherited their works, archives and trained services after independence.",
        initialId: "survey-administration-1914",
        mapImage: "assets/world-relief.jpg",
        records: [
          {
            id: "survey-administration-1914",
            label: "Read the surveyed state",
            period: "AD 1914",
            kicker: "Territory enters the archive",
            detail:
              "Geodetic frames, cadastral sheets, port plans and district registers let distant offices identify land, works, boundaries and obligations in comparable records.",
            fields: [
              {
                label: "Layer",
                value: "Survey · cadastre · plan · administrative archive",
              },
              {
                label: "Capacity",
                value: "A territory that can be located, recorded and revised",
              },
            ],
            outcome:
              "Government can remember a road, canal, title or district after the officer who recorded it has gone.",
            points: [
              {
                id: "madras-survey",
                label: "Madras",
                detail: "The survey frame begun in 1802 remains in use.",
                x: 73,
                y: 47,
              },
              {
                id: "delhi-archive",
                label: "Delhi",
                detail: "Maps and departmental records meet administration.",
                x: 72,
                y: 39,
              },
              {
                id: "dakar-archive",
                label: "Dakar",
                detail: "Port plans and federal files gather at the capital.",
                x: 45,
                y: 46,
              },
            ],
          },
          {
            id: "railways-1914",
            label: "Follow the railway layer",
            period: "AD 1914",
            kicker: "Fixed corridors enter public use",
            detail:
              "Indian trunk lines join great ports and inland centres while the Dakar–Saint-Louis railway binds a West African harbour to an older capital and river route.",
            fields: [
              {
                label: "Layer",
                value: "Rail · bridge · workshop · station · timetable",
              },
              {
                label: "Capacity",
                value:
                  "Repeatable inland movement for freight, mail and people",
              },
            ],
            outcome:
              "Military corridors also become passenger, commercial and political routes.",
            points: [
              {
                id: "bombay-rail",
                label: "Bombay",
                detail: "Western port and trunk-line origin.",
                x: 70,
                y: 43,
              },
              {
                id: "delhi-rail",
                label: "Delhi",
                detail: "Northern junction and administrative centre.",
                x: 72,
                y: 39,
              },
              {
                id: "calcutta-rail",
                label: "Calcutta",
                detail: "Eastern port and railway centre.",
                x: 75,
                y: 42,
              },
              {
                id: "dakar-rail",
                label: "Dakar",
                detail: "Atlantic terminal of the Saint-Louis line.",
                x: 45,
                y: 46,
              },
              {
                id: "saint-louis-rail",
                label: "Saint-Louis",
                detail: "Older capital and Senegal River gateway.",
                x: 45,
                y: 44,
              },
            ],
            links: [
              [0, 2],
              [0, 1],
              [1, 2],
              [3, 4],
            ],
          },
          {
            id: "cables-ports-1914",
            label: "Open the cable and port layer",
            period: "AD 1914",
            kicker: "The inland line meets the sea",
            detail:
              "Cable landings and engineered ports connect London, Dakar, Suez, Bombay and Singapore to scheduled shipping, finance and government communication.",
            fields: [
              {
                label: "Layer",
                value: "Harbour · coaling berth · cable · relay office",
              },
              {
                label: "Capacity",
                value: "Distant action within one shipping and signalling day",
              },
            ],
            outcome:
              "The port becomes a transfer point between local institutions and a world network.",
            points: [
              {
                id: "london-cable",
                label: "London",
                detail: "Finance, cable companies and ministries meet.",
                x: 49,
                y: 24,
              },
              {
                id: "dakar-port",
                label: "Dakar",
                detail: "Atlantic harbour and administrative capital.",
                x: 45,
                y: 46,
              },
              {
                id: "suez-port",
                label: "Suez",
                detail: "Canal, cable and steam lane intersect.",
                x: 59,
                y: 38,
              },
              {
                id: "bombay-port",
                label: "Bombay",
                detail: "Port, railway and cable office meet.",
                x: 71,
                y: 42,
              },
              {
                id: "singapore-port",
                label: "Singapore",
                detail: "Eastern relay and scheduled harbour.",
                x: 79,
                y: 49,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
              [2, 3],
              [3, 4],
            ],
          },
          {
            id: "successor-governments",
            label: "Receive the connected inheritance",
            period: "AD 1947–1960",
            kicker: "Sovereignty changes; capacity remains",
            detail:
              "India, Pakistan and Senegal take possession of different inherited works and services, then operate, divide, extend and adapt them under independent governments.",
            fields: [
              {
                label: "Inheritance",
                value:
                  "Railways · ports · surveys · archives · technical departments",
              },
              {
                label: "New authority",
                value: "Independent governments and public services",
              },
            ],
            outcome:
              "Imperial connections become public capacities available to new sovereign purposes.",
            points: [
              {
                id: "new-delhi",
                label: "New Delhi",
                detail: "Government of independent India.",
                x: 72,
                y: 39,
              },
              {
                id: "karachi",
                label: "Karachi",
                detail: "First capital of independent Pakistan.",
                x: 69,
                y: 42,
              },
              {
                id: "dakar-independent",
                label: "Dakar",
                detail: "Capital of independent Senegal.",
                x: 45,
                y: 46,
              },
            ],
          },
        ],
      },
    },
    {
      id: "the-railway-enters-india",
      actId: "steel-enters-continents",
      order: 9,
      period: "AD 1853–1900",
      place: "Bombay, Thane and the Indian subcontinent",
      title: "The Railway Enters India",
      thesis:
        "Imperial railways gave India a continental transport frame that served British command and became indispensable to Indian economic and national life.",
      body: [
        "On 16 April 1853, three locomotives drew fourteen carriages out of Bombay toward Thane. The line was short, but the station ceremony announced a programme of continental scale. British companies raised capital under government guarantees; engineers surveyed gradients, bridged rivers and ordered rails and machinery through imperial supply chains. After the rebellion of 1857, strategic lines received added urgency because troops and matériel could move inland faster. Cotton, wheat and other commodities travelled toward ports, while construction costs and guaranteed returns placed heavy obligations on Indian revenues.",
        "The railway escaped the purposes assigned by its builders. Pilgrims filled affordable carriages, merchants reached wider markets, postal bags and newspapers crossed provincial distances, and workers travelled in search of wages. Junction towns grew around workshops, warehouses and refreshment rooms. Gauges, ticket classes and company boundaries introduced friction, but timetables taught thousands of local journeys to meet one another. A person who had known India through a district road could now encounter the scale of the subcontinent from a platform shared with passengers bound for cities, shrines and markets far beyond it.",
        "By 1900, trunk lines joined the great ports to interior regions and to one another. Famine, poverty and imperial inequality persisted, while railway police and troop trains remained instruments of command. The network created a durable capacity that Indian enterprise, public debate and politics learned to use. Newspapers could address distant readers on the same morning; organisers could travel between presidencies; produce could reach a broader field of exchange. Built under foreign rule, the railway became one of the physical structures through which India increasingly experienced and eventually governed itself as a connected country.",
      ],
      image: `${imageRoot}/08-the-railway-enters-india.avif`,
      imageAlt:
        "The first Bombay–Thane train departs beneath a dated Indian railway map with tickets, mail bags, cotton bales and workshop tools in the foreground.",
      imagePosition: "63% center",
      mobileImagePosition: "70% center",
      visualLabel: "Bombay departure, dated network and passenger tickets",
      visualTone: "railway-red",
      side: "right",
      sourceIds: ["kerr-2007", "headrick-1988"],
      evidence: [
        "India’s first passenger railway ran from Bombay to Thane on 16 April 1853, and the network expanded through guaranteed companies and state construction.",
        "Railways served military movement and export traffic while also carrying Indian passengers, mail, newspapers, pilgrims and political organisers across provincial distances.",
      ],
      map: { x: 71, y: 42 },
    },
    {
      id: "dakar-builds-an-administrative-city",
      actId: "steel-enters-continents",
      order: 10,
      period: "AD 1857–1914",
      place: "Dakar and French West Africa",
      title: "Dakar Builds an Administrative City",
      thesis:
        "France concentrated port, railway, medicine, schooling and records at Dakar, creating a western African capital able to organise an immense territory.",
      body: [
        "Dakar occupied a volcanic peninsula with a sheltered approach to the Atlantic routes. The French established the post in 1857, then enlarged jetties, workshops, roads and water supply around the harbour. A railway linked Dakar with Saint-Louis in 1885, binding the new port to the older Senegalese capital and the river corridor. Coal, groundnuts, military stores, mail and passengers moved through facilities built to serve French power. The same concentration drew African labourers, traders, artisans and families into a city whose streets extended beyond the first administrative plan.",
        "In 1902, Dakar became the seat of the government-general of French West Africa. Files from large territories arrived at offices beside maps, legal codes and budget tables; courts, customs services, hospitals and technical departments accumulated around them. Schools trained interpreters, teachers and clerks, while medical services confronted yellow fever and other diseases that threatened residents and shipping. French rule remained coercive: conquest opened much of the hinterland, taxes and labour demands reached villages through colonial administration, and political rights differed sharply by status and place.",
        "The city’s institutions created abilities that outlasted the authority that assembled them. Senegalese employees learned the work of rail, port, school, hospital, archive and municipality. Elected politics in the older communes gave African representatives experience within French institutions, while educated organisers used print and transport to widen public claims. Dakar became the federal capital because its connections allowed decisions to travel and information to return. Independent Senegal later governed from this inherited node, adapting buildings, professions and records made for empire to the work of a sovereign African state.",
      ],
      image: `${imageRoot}/10-dakar-builds-an-administrative-city.avif`,
      imageAlt:
        "A dated Dakar city plan layers harbour works, the Saint-Louis railway, hospital, schools and government-general offices over named streets and workshops.",
      imagePosition: "64% center",
      mobileImagePosition: "71% center",
      visualLabel: "Harbour plan, rail terminal, hospital and archive",
      visualTone: "harbour-administration",
      side: "right",
      sourceIds: ["conklin-1997", "darwin-2007"],
      evidence: [
        "Dakar was established as a French post in 1857, connected by railway to Saint-Louis in 1885 and made capital of French West Africa in 1902.",
        "Port, medical, educational, judicial and administrative services concentrated skills and records later used by Senegalese government and public life.",
      ],
      map: { x: 45, y: 46 },
    },
    {
      id: "disease-enters-a-common-conference",
      actId: "steel-enters-continents",
      order: 11,
      period: "AD 1851–1907",
      place: "Paris, Venice and Europe’s maritime routes",
      title: "Disease Enters a Common Conference",
      thesis:
        "Steam-age danger pushed European states to turn quarantine from isolated port command into shared evidence, notification and procedure.",
      body: [
        "Cholera moved with the passengers, soldiers and cargo whose journeys steam had accelerated. One port imposed quarantine, another relied on inspection, and a third concealed an outbreak for fear of losing trade. In 1851, physicians and diplomats from twelve states met in Paris for the first International Sanitary Conference. They compared theories of transmission, quarantine periods and bills of health for months without producing an agreement that every government would ratify. The failure defined the task: disease crossed borders faster than medical certainty or national regulations could be reconciled.",
        "Conference followed conference as cholera, plague and yellow fever revealed practical points of agreement. Delegates learned to separate sanitary measures by disease and route, to standardise notification and to focus controls on ports and passages where movement concentrated. The Suez Canal made the issue urgent because European commerce and pilgrim traffic shared a narrow corridor between the Mediterranean and Red Sea. Conventions in the 1890s established more workable rules for cholera and plague, limiting some indiscriminate quarantines while preserving measures judged necessary to protect ports.",
        "In 1907, governments agreed in Rome to create the Office International d’Hygiène Publique, which opened in Paris with a permanent secretariat and regular exchange of epidemiological information. Laboratories, consular reports, port doctors and national administrations could now feed knowledge into an institution that remained at work between emergencies. Disease continued to travel, while Europe turned repeated fear into a public office: an administrative ancestor of later international health organisation, based on the proposition that one state’s warning and evidence could protect people beyond its jurisdiction.",
      ],
      image: `${imageRoot}/11-disease-enters-a-common-conference.avif`,
      imageAlt:
        "Port doctors compare quarantine flags, bills of health and a cholera route map at an international sanitary conference before a permanent office register.",
      imagePosition: "57% center",
      mobileImagePosition: "64% center",
      visualLabel: "Bill of health, conference table and notification register",
      visualTone: "sanitary-green",
      side: "left",
      sourceIds: ["who-sanitary-conferences", "huber-2013"],
      evidence: [
        "The first International Sanitary Conference met in Paris in 1851 in response to cross-border epidemic danger and conflicting quarantine regimes.",
        "The 1907 Rome agreement created the Office International d’Hygiène Publique as a permanent centre for sanitary information and international coordination.",
      ],
      map: { x: 51, y: 30 },
    },
    {
      id: "the-map-enters-the-conference-room",
      actId: "europe-takes-central-desk",
      order: 12,
      period: "AD 1884–1885",
      place: "Berlin",
      title: "The Map Enters the Conference Room",
      thesis:
        "European powers brought overseas rivalry under common diplomatic procedures, then gave paper claims force through treaties, armies and occupation.",
      body: [
        "In November 1884, delegates entered the official residence of the German chancellor and took their places around a horseshoe table. Fourteen states were represented; no African ruler held a seat. Bismarck had called the conference because rivalry around the Congo and other African coasts threatened conflict among European powers. The diplomats examined navigation, commerce, missionary protection, the slave trade and the conditions under which a new occupation on the African coast would be notified to the other signatories.",
        "The General Act declared freedom of navigation on the Congo and Niger and committed its signatories to suppress the slave trade. It also established rules of notification and an obligation to maintain sufficient authority in newly occupied coastal possessions to protect existing rights and trade. Later bilateral agreements and conquest fixed many colonial boundaries. Berlin supplied the diplomatic procedures through which European governments recognised claims, negotiated disputes and measured occupation, accelerating a competition already being carried forward by companies, treaties and expeditions.",
        "On the ground, those claims advanced through armed columns, punitive campaigns, imposed treaties and administrative stations. African states resisted, negotiated and sometimes used one European rival against another; modern rifles, steam transport and metropolitan finance increasingly favoured the invaders. By 1914, most of the continent had been brought under European rule. The same apparatus that could suppress slave raiding, survey a port or establish a court could compel labour and collect tax. Europe’s central desk joined law to force across enormous distance, making overseas territory answer to decisions recorded in European capitals.",
      ],
      image: `${imageRoot}/12-the-map-enters-the-conference-room.avif`,
      imageAlt:
        "The 1884 Berlin Conference room contains a geographic African map in muted cartographic tones, treaty clauses and fourteen seated delegations.",
      imagePosition: "59% center",
      mobileImagePosition: "66% center",
      visualLabel: "Conference table, General Act and notification map",
      visualTone: "conference-oxblood",
      side: "right",
      sourceIds: ["berlin-act-1885", "wesseling-1996", "darwin-2007"],
      evidence: [
        "Fourteen states participated in the Berlin Conference, while African political authorities were not represented at its table.",
        "The 1885 General Act addressed Congo and Niger navigation, commerce, suppression of the slave trade, notification of new coastal possessions and effective authority in occupied areas.",
      ],
      map: { x: 52, y: 25 },
    },
    {
      id: "paris-displays-the-system",
      actId: "europe-takes-central-desk",
      order: 13,
      period: "AD 1900",
      place: "Paris",
      title: "Paris Displays the System",
      thesis:
        "The Exposition Universelle assembled European engineering, science, empire and urban order into a future that fifty million admissions could inspect.",
      body: [
        "After dusk, electric lamps traced the new Pont Alexandre III and the exhibition palaces along the Seine. Visitors stepped onto a moving walkway that carried them around the grounds at two speeds, passed halls of machinery and entered displays reached by the new Métro. Dynamos, telescopes, diesel engines, cinematographs, precision instruments and manufactured goods stood beneath roofs whose spans were themselves exhibits. The Exposition Universelle received more than fifty million admissions during 1900, making technical achievement a public landscape open to inspection.",
        "European nations presented their industries, arts and institutions beside invited states and colonial pavilions. France used the fair to display republican confidence and imperial reach; Germany’s exhibits demonstrated industrial strength; Britain’s global commerce remained evident throughout the halls. Colonial sections assembled models of roads, ports, schools, crops and crafts while some staged villages placed colonised people before metropolitan crowds. Across the grounds, competence took material form: a bridge carrying traffic, a generator feeding light, a lens resolving distance and a machine repeating exact work.",
        "Visitors could carry that language home in catalogues, photographs, measurements and ambitions. Municipal officials studied transport and sanitation; engineers inspected rival machines; merchants found suppliers; families experienced electric urban life before it reached their own streets. Paris displayed no single invention capable of explaining Europe’s ascendancy. It displayed the system that joined invention to finance, public works, skilled labour, standards and administrative confidence. The continent appeared as the workshop of a modern future because its institutions could move an experiment from a bench into a bridge, a railway, a city and an overseas network.",
      ],
      image: `${imageRoot}/13-paris-displays-the-system.avif`,
      imageAlt:
        "The illuminated Paris Exposition of 1900 stretches from Pont Alexandre III toward machinery halls, electric lights and the moving walkway.",
      imagePosition: "62% center",
      mobileImagePosition: "69% center",
      visualLabel: "Electric panorama, moving walkway and machinery catalogue",
      visualTone: "exposition-electric",
      side: "left",
      sourceIds: ["bie-paris-1900", "mandell-1967", "osterhammel-2014"],
      evidence: [
        "The 1900 Paris Exposition recorded more than fifty million admissions and displayed electricity, transport, machinery, science, national achievement and empire.",
        "The moving walkway, new Métro and monumental engineering made the exhibition grounds themselves a demonstration of coordinated modern infrastructure.",
      ],
      map: { x: 50, y: 28 },
    },
    {
      id: "the-world-reaches-london-before-dawn",
      actId: "europe-takes-central-desk",
      order: 14,
      period: "Summer AD 1914",
      place: "London",
      title: "The World Reaches London Before Dawn",
      thesis:
        "At Europe’s leading switchboard, cables, steam routes, railways, banks and ministries compressed global action into one working day.",
      body: [
        "Before sunrise, a cable clerk sat beneath enamel circuit labels while paper tape gathered beside his instrument. A grain price arrived from North America, shipping news from Suez and commercial instructions from Bombay; a signal for Singapore passed onward through relay stations maintained by the Eastern Telegraph network. Each message had crossed offices, cables and jurisdictions whose names were absent from the final slip. Standard codes, tariffs, timestamps and addresses allowed the receiving clerk to treat a chain spanning continents as one intelligible transaction.",
        "The message left the cable room and entered other European institutions. A bank released credit against a signature and account; an insurer revised the risk on a ship; a newspaper composed a market column; an Admiralty or colonial office placed an instruction in the next dispatch. London held the densest concentration, while Paris, Berlin, Brussels and other capitals directed their own financial, administrative and communication systems. Europe’s overseas empires controlled and maintained routes and stations, and European-made conventions allowed messages to cross even where imperial jurisdictions met or ended.",
        "By 1914, Europe had joined immense reaches of the earth to regular movement and repeatable procedure. European power had conquered territory and defeated resistance; its durable command also lay in institutions that worked without a battle: the timetable, survey, sanitary notice, postal territory, technical bureau, legal register and cable code. Ports and successor states could inherit those instruments because their operation could be taught and recorded. Europe had made the world answer before dawn. The mobilisation telegram now entering the board would send Europe’s coming conflict along the routes the continent had connected.",
      ],
      image: `${imageRoot}/14-the-world-reaches-london-before-dawn.avif`,
      mobileImage: `${imageRoot}/14-the-world-reaches-london-before-dawn-mobile.avif`,
      imageAlt:
        "A London cable office before dawn receives named circuits from North America, Suez, Bombay and Singapore while banks and ministries begin work beyond the glass.",
      imagePosition: "54% center",
      mobileImagePosition: "60% center",
      visualLabel:
        "Named circuits, message tape and the completed switchboard",
      visualTone: "switchboard-night",
      side: "right",
      sourceIds: ["headrick-1991", "darwin-2009", "osterhammel-2014"],
      evidence: [
        "By 1914, British-led submarine cable systems linked London through Atlantic, Mediterranean, Indian Ocean and East Asian relay stations.",
        "Common codes, tariffs, time references and accounting practices allowed banks, insurers, news organisations and governments to act on distant information within one working day.",
      ],
      map: { x: 49, y: 24 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "route-the-world",
        prompt: "Route the world",
        accessibleSummary:
          "Three dated circuits compare the offices, ships, cables, railways and protocols required to send a London instruction to Bombay, Suez and Singapore in 1840, 1875 and 1910.",
        initialId: "voyage-1840",
        mapImage: "assets/world-relief.jpg",
        records: [
          {
            id: "voyage-1840",
            label: "Carry the instruction",
            period: "AD 1840",
            kicker: "The message changes carriers",
            detail:
              "A London instruction reaches Alexandria by packet, crosses Egypt to Suez by the overland mail route, then boards another vessel for the Red Sea and Bombay.",
            fields: [
              {
                label: "Relays",
                value:
                  "Office · Mediterranean packet · Egyptian overland mail · Red Sea vessel · local courier",
              },
              { label: "Elapsed time", value: "Measured in several weeks" },
              {
                label: "Blocking point",
                value: "Paper must complete every physical transfer",
              },
            ],
            outcome:
              "The sender waits for the same chain to carry an answer home before revising the order.",
            points: [
              {
                id: "london",
                label: "London",
                detail: "The written instruction leaves the office.",
                x: 49,
                y: 24,
              },
              {
                id: "alexandria",
                label: "Alexandria",
                detail: "The Mediterranean packet hands the mail ashore.",
                x: 58,
                y: 36,
              },
              {
                id: "suez",
                label: "Suez",
                detail: "The overland relay crosses Egypt to the next vessel.",
                x: 59,
                y: 38,
              },
              {
                id: "bombay",
                label: "Bombay",
                detail: "A local office receives and acts after the voyage.",
                x: 71,
                y: 42,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
            ],
          },
          {
            id: "cable-1875",
            label: "Join cable to canal",
            period: "AD 1875",
            kicker: "The route acquires electrical relays",
            detail:
              "London reaches Suez and Bombay through connected telegraph administrations while the canal and scheduled steamship carry people and cargo on a shorter sea road.",
            fields: [
              {
                label: "Relays",
                value: "London · Mediterranean cable · Suez · Bombay",
              },
              { label: "Elapsed time", value: "A telegram measured in hours" },
              {
                label: "Required protocol",
                value: "Compatible code, tariff and account",
              },
            ],
            outcome:
              "Credit can be released in Bombay before a London ship has cleared European waters.",
            points: [
              {
                id: "london",
                label: "London",
                detail: "A telegraph office accepts the coded instruction.",
                x: 49,
                y: 24,
              },
              {
                id: "suez",
                label: "Suez",
                detail: "Cable, canal and steam route meet.",
                x: 59,
                y: 38,
              },
              {
                id: "bombay",
                label: "Bombay",
                detail: "The bank confirms receipt by telegraph.",
                x: 71,
                y: 42,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "switchboard-1910",
            label: "Complete the circuit",
            period: "AD 1910",
            kicker: "One instruction moves through one working day",
            detail:
              "The London desk releases credit for a railway consignment in Bombay, redirects a ship at Suez and receives confirmation through Singapore over scheduled, coded and timed relays.",
            fields: [
              {
                label: "Relays",
                value:
                  "Bank · cable · port office · ship agent · railway clerk · local office",
              },
              {
                label: "Elapsed time",
                value: "Operational action within the day",
              },
              {
                label: "Protocols",
                value: "Code · tariff · address · Greenwich reference",
              },
            ],
            outcome:
              "Machinery and institutions now carry one decision across three continents without moving its author.",
            points: [
              {
                id: "london",
                label: "London",
                detail: "The central desk enters the instruction.",
                x: 49,
                y: 24,
              },
              {
                id: "suez",
                label: "Suez",
                detail: "The port office redirects the scheduled ship.",
                x: 59,
                y: 38,
              },
              {
                id: "bombay",
                label: "Bombay",
                detail: "The bank releases credit against the cable.",
                x: 71,
                y: 42,
              },
              {
                id: "singapore",
                label: "Singapore",
                detail: "The final office confirms the completed chain.",
                x: 79,
                y: 49,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
            ],
          },
        ],
      },
    },
  ],
};
