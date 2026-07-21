import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/hanseatic-north";

export const hanseaticNorth: ChapterDefinition = {
  slug: "hanseatic-north",
  number: "11",
  title: "The Hanseatic North",
  openingTitleLines: ["The Hanseatic", "North"],
  period: "AD 1150–1500",
  claim:
    "Northern merchants and towns made common power from privilege, discipline and consent. They could close markets, bargain with kings and put fleets to sea while every participating city kept its own government.",
  openingClaim:
    "Northern cities learned to act together without surrendering the freedom that made their alliance worth having.",
  hero: {
    image: `${imageRoot}/01-bryggen-before-sunrise.avif`,
    mobileImage: `${imageRoot}/01-bryggen-before-sunrise-mobile.avif`,
    imageAlt:
      "A Norwegian cargo boat enters medieval Bergen before sunrise as merchants work among stockfish bundles and dark timber warehouses at Bryggen.",
    imagePosition: "center 56%",
    mobileImagePosition: "61% center",
    visualLabel: "The Harbour Covenant · quay, cargo and seal",
  },
  theme: {
    id: "harbour",
    label: "The harbour covenant",
  },
  openingAction: "Enter the northern harbour",
  mapLabel:
    "The harbours, foreign houses and consenting towns that made a common power across the northern seas",
  routeImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Royal privileges · town instructions · Hanseatic recesses · Kontor ordinances · customs records · Bryggen archaeology",
  acts: [
    {
      id: "harbour-feeds-north",
      number: "I",
      label: "The harbour feeds the north",
      period: "c. AD 1150–1360",
      title: "The Harbour Feeds the North",
      detail:
        "Stockfish, grain and disciplined storage turn Bergen into the hinge between a long Norwegian coast and the markets of northern Europe.",
    },
    {
      id: "privilege-builds-house",
      number: "II",
      label: "Privilege builds a foreign house",
      period: "c. AD 1240–1400",
      title: "Privilege Builds a Foreign House",
      detail:
        "Royal grants, timber yards and corporate rules give German merchants a durable place within Bergen and the Norwegian king’s peace.",
    },
    {
      id: "cities-act-together",
      number: "III",
      label: "Cities learn to act together",
      period: "c. AD 1250–1400",
      title: "Cities Learn to Act Together",
      detail:
        "Lübeck’s position, instructed delegates, common recesses, boycotts and contributed ships turn separate councils into a formidable maritime coalition.",
    },
    {
      id: "edges-hold-league",
      number: "IV",
      label: "The edges hold the league",
      period: "c. AD 1350–1500",
      title: "The Edges Hold the League",
      detail:
        "Four autonomous foreign houses gather the intelligence, privileges and commodities that allow many towns to act across the whole northern economy.",
    },
  ],
  ending: {
    period: "c. AD 1500",
    title: "Cities Can Act Together",
    detail:
      "The seals remain separate after the common instrument has been written. That is the Hanseatic achievement: merchants and councils learned to defend a continental field of trade through delegated consent, corporate discipline and selective force, without erecting a throne above their towns. Inland, the same European talent for joining unequal powers would assume a grander political form. An elected emperor, princes, bishops, knights and free cities were already making agreement itself into an enduring constitution.",
    image: `${imageRoot}/13-cities-act-together.avif`,
    nextPeriod: "AD 962–1806",
  },
  returnHash: "hanseatic-north",
  nextHash: "empire-many-liberties",
  nextTitle: "The Empire of Many Liberties",
  nextSlug: "empire-many-liberties",
  movements: [
    {
      id: "dawn-comes-to-bryggen",
      actId: "harbour-feeds-north",
      order: 1,
      period: "c. AD 1240",
      place: "Vågen and Bryggen, Bergen",
      title: "Dawn Comes to Bryggen",
      thesis:
        "Bergen stood where the labour of Norway’s long coast entered the commercial life of Europe.",
      body: [
        "Before sunrise, a northern boat eased into Vågen beneath a square of dark sail. Tar, wet pine and dried cod filled the cold air. Men steadied the hull against the quay while others shouldered bound stockfish toward the deep timber yards of Bryggen. Lanterns moved behind warehouse openings; scales, tally sticks and cargo marks waited on the planks. Low German speech mingled with Norwegian around a catch that had begun its journey hundreds of miles to the north. Bergen was awake before the sky because a continental market had arrived at its waterline.",
        "The cargo looked austere: cod split, cleaned and hardened by wind until it could endure a long voyage without salt. Its durability gave Norway a great export from a coast whose short growing seasons limited grain. Fishermen, boat owners, coastal carriers, royal officers, townsmen and foreign merchants all stood somewhere along its road. In Bergen the scattered yield of northern fisheries became an urban stock that could be sorted by quality, stored in quantity, advanced against credit and sent across the North Sea. A season of labour entered the warehouse as merchandise Europe would buy year after year.",
        "The harbour joined two necessities. European towns wanted preserved protein; Norway wanted grain, malt, cloth, salt and the regular shipping that brought them. No king had designed the entire exchange, and no merchant commanded it from end to end. Royal peace, Norwegian production, German commercial organization and the discipline of the quay fitted together through repeated bargains. Bryggen gave those bargains a physical body: narrow passages, lifting beams, stacked goods and offices facing the water. Here a remote coastline ceased to be an edge. It became one of the northern economy’s commanding entrances.",
      ],
      image: `${imageRoot}/01-bryggen-before-sunrise.avif`,
      mobileImage: `${imageRoot}/01-bryggen-before-sunrise-mobile.avif`,
      imageAlt:
        "A low winter dawn over medieval Vågen, with Norwegian sailors unloading stockfish beside Low German merchants at the dark timber yards of Bryggen.",
      imagePosition: "center 56%",
      mobileImagePosition: "61% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "harbour-night",
      side: "left",
      sourceIds: ["nedkvitne-2014", "oye-bergen-hansa", "unesco-bryggen"],
      evidence: [
        "Archaeology and written records identify Bryggen as the principal setting of Bergen’s medieval overseas trade and the later German Kontor.",
        "Stockfish linked northern Norwegian production to European demand while imported grain and manufactured goods moved through Bergen in return.",
      ],
      map: { x: 43, y: 31 },
    },
    {
      id: "lofoten-sends-summer-cargo",
      actId: "harbour-feeds-north",
      order: 2,
      period: "c. AD 1200–1400",
      place: "Lofoten, Vågan and the sea road to Bergen",
      title: "Lofoten Sends a Summer Cargo",
      thesis:
        "Cold air, patient drying and coastal navigation turned a winter catch into a cargo for distant cities.",
      body: [
        "The northern year began when cod crowded toward the Lofoten spawning grounds in winter. Fishing boats worked short days under steep mountains, bringing ashore a catch far larger than the local population could eat fresh. The climate supplied the means of preservation. Fish were cleaned, paired and hung on timber racks where cold moving air drew out moisture without the salt demanded by warmer shores. Frost, wind and time made the flesh light, hard and resistant to decay. Nature offered abundance for a few months; disciplined labour made that abundance last.",
        "Spring remained part of the harvest. Fish had to dry evenly, survive rain and be judged before bundling. When sailing conditions improved, Norwegian carriers gathered cargo through Vågan and other northern points and followed the sheltered coastal road south. Headlands, sounds and familiar anchorages mattered more than a straight line on a chart. A delayed drying season postponed loading; a missed sailing window could strand value for months. The commercial calendar therefore rested on physical knowledge held by fishermen, shore workers and seamen long before a foreign buyer examined a bundle at Bergen.",
        "Summer brought the preserved catch into Bryggen’s stores. There German merchants and their agents graded, weighed, financed and assembled stockfish for the outward passage to North Sea and Baltic markets. The returning ships carried goods whose production followed a different landscape and season. This circuit did not erase the length of Norway; it gave that length a dependable rhythm. Winter fishing, spring drying, summer carriage and the homeward cargo formed one northern year. Preservation conquered time first, the coastal vessel conquered distance next, and the harbour joined both achievements to Europe.",
      ],
      image: `${imageRoot}/02-lofoten-summer-cargo.avif`,
      imageAlt:
        "A seasonal northern coast with cod drying on timber racks as a loaded Norwegian vessel begins the sheltered voyage toward Bergen.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "rain-blue",
      side: "right",
      sourceIds: ["nedkvitne-2014", "oye-bergen-hansa"],
      evidence: [
        "The Lofoten winter fishery and cold-air drying produced a durable stockfish cargo that could travel without salt.",
        "Norwegian coastal transport carried northern fish toward Bergen, where Hanseatic merchants organized storage, export and return trade.",
      ],
      map: { x: 49, y: 18 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "northern-year",
        prompt: "Carry the northern year",
        accessibleSummary:
          "Four dated states follow cod from the Lofoten winter fishery through spring drying and summer carriage to Bergen, then trace grain and other goods back across the same northern waters.",
        initialId: "winter-catch",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "winter-catch",
            label: "Winter catch",
            period: "January–April",
            kicker: "Abundance enters the boats",
            detail:
              "Spawning cod gather off Lofoten while local crews work the short winter days and land a catch larger than the coast can consume fresh.",
            fields: [
              { label: "Season", value: "Cold, dark and storm-bound" },
              { label: "Task", value: "Catch, clean and split the cod" },
            ],
            outcome:
              "A brief fishery creates a harvest that must outlast its season.",
            points: [
              {
                id: "lofoten",
                label: "Lofoten",
                detail: "The winter spawning grounds concentrate the catch.",
                x: 50,
                y: 17,
              },
            ],
          },
          {
            id: "spring-drying",
            label: "Spring drying",
            period: "March–June",
            kicker: "Cold air preserves the harvest",
            detail:
              "Paired fish hang on outdoor racks until wind and low temperatures reduce them to a hard cargo able to travel without salt.",
            fields: [
              {
                label: "Instrument",
                value: "Timber rack, knife and weather judgment",
              },
              { label: "Result", value: "Light, durable stockfish" },
            ],
            outcome:
              "Preservation releases the catch from the day on which it was taken.",
            points: [
              {
                id: "vagan",
                label: "Vågan",
                detail:
                  "Drying and assembly prepare northern fish for coastal carriage.",
                x: 51,
                y: 18,
              },
            ],
          },
          {
            id: "summer-passage",
            label: "Summer passage",
            period: "June–August",
            kicker: "The coast becomes a road",
            detail:
              "Norwegian carriers move the bundled fish through sheltered sounds and known anchorages toward Bergen when the sailing season opens.",
            fields: [
              { label: "Route", value: "Lofoten and Vågan to Bergen" },
              {
                label: "Constraint",
                value: "Weather, storage and sailing time",
              },
            ],
            outcome: "Many local catches become one export stock at Bryggen.",
            points: [
              {
                id: "lofoten",
                label: "Lofoten",
                detail: "Bundles leave the northern gathering points.",
                x: 50,
                y: 17,
              },
              {
                id: "bergen",
                label: "Bergen",
                detail: "Warehouses receive, grade and assemble the cargo.",
                x: 43,
                y: 31,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "return-cargo",
            label: "Return cargo",
            period: "Late summer–autumn",
            kicker: "The hold comes north again",
            detail:
              "Grain, malt, flour, cloth and salt move from Baltic and North Sea markets toward Bergen after stockfish has travelled outward.",
            fields: [
              { label: "Outward", value: "Preserved Norwegian fish" },
              { label: "Homeward", value: "Foodstuffs and manufactured goods" },
            ],
            outcome:
              "The same water carries two regions through different seasons of need.",
            points: [
              {
                id: "danzig",
                label: "Danzig",
                detail: "Baltic grain enters the Hanseatic shipping system.",
                x: 57,
                y: 47,
              },
              {
                id: "lubeck",
                label: "Lübeck",
                detail:
                  "The Baltic and North Sea circuits meet through the Trave–Elbe corridor.",
                x: 49,
                y: 47,
              },
              {
                id: "bergen",
                label: "Bergen",
                detail:
                  "Return cargo supplies the Norwegian harbour and coast.",
                x: 43,
                y: 31,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
        ],
      },
    },
    {
      id: "grain-returns-same-water",
      actId: "harbour-feeds-north",
      order: 3,
      period: "thirteenth–fourteenth centuries",
      place: "Bergen, Lübeck and the Baltic grain ports",
      title: "Grain Returns on the Same Water",
      thesis:
        "Stockfish and grain made northern trade a reciprocal necessity rather than a procession of empty returning ships.",
      body: [
        "When the stockfish had left Bergen, the emptied space in the hold acquired a second purpose. Rye, wheat, flour, malt and beer came north from the Baltic and the lands behind the German ports. Salt and cloth travelled with them, alongside tools and wares that a growing town could not produce in equal quantity for itself. The sea road worked because the cargo changed direction as well as ownership. A ship that earned on both passages could return more regularly, and regular return mattered to a city living between mountain, ocean and uncertain harvests.",
        "Imported grain gave German merchants real leverage in Bergen. Access to stores and shipping could shape prices, credit and the terms offered to Norwegian sellers. Norwegian society possessed leverage of its own. European demand for durable fish was broad and persistent, and the crown held the authority to grant, interpret or narrow foreign privileges. Producers and coastal carriers controlled the labour and local routes that placed stockfish on the quay. The resulting order rested on dependence in both directions, although the advantages within Bergen were never divided evenly.",
        "Reciprocity made the harbour larger than a seasonal market. Warehouses carried stocks between arrivals; advances connected one year’s catch to another; customs officers and brokers learned to expect the same routes. Fish fed dense towns and religious calendars abroad. Grain strengthened the food supply of Bergen and communities reached through it. Cloth, salt and beer widened the exchange beyond bare subsistence. Each cargo gave the other a reason to return. On the cold water between Bergen and the German ports, northern Europe discovered that interdependence could be organized into durable commercial power.",
      ],
      image: `${imageRoot}/03-grain-returns.avif`,
      imageAlt:
        "Grain sacks rise from the open hold of a medieval merchant vessel at Bergen while bundled stockfish is loaded for the outward voyage.",
      imagePosition: "46% center",
      mobileImagePosition: "52% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "two-way-wake",
      side: "left",
      sourceIds: ["nedkvitne-2014", "oye-bergen-hansa", "dollinger-1970"],
      evidence: [
        "Bergen’s Hanseatic trade exchanged stockfish for grain, malt, flour, beer, cloth and salt carried through North Sea and Baltic networks.",
        "Foreign merchants gained bargaining power from shipping and imported provisions while Norwegian producers and royal authority remained indispensable to the trade.",
      ],
      map: { x: 46, y: 38 },
    },
    {
      id: "crown-grants-door",
      actId: "privilege-builds-house",
      order: 4,
      period: "c. AD 1240–1360",
      place: "Bergen and the Norwegian royal court",
      title: "The Crown Grants a Door",
      thesis:
        "Royal privilege gave foreign merchants a recognized entrance into Bergen’s law, tolls and peace.",
      body: [
        "German merchants became a durable presence in Bergen through rights acknowledged by the Norwegian crown. A privilege was a working instrument: it could define tolls, secure access to trade, recognize procedures and place visiting merchants beneath the protection of the king’s peace. The crown welcomed customs revenue and a dependable stream of goods while retaining the authority to bargain over the conditions. Foreign commerce entered the realm through a legal door, opened by a ruler who could name both the welcome and its limits.",
        "Every grant acquired meaning on the quay. A merchant produced the sealed text when an official demanded a payment he considered unlawful, when a rival challenged an exemption or when a cargo was detained. Royal officers read the same clauses in light of the king’s revenue and Norwegian interests. Confirmations by successive rulers mattered because privilege survived through recognition, precedent and renewed negotiation. The document carried more force than a private promise, yet its use still depended on officials, witnesses and a political relationship that had to be maintained.",
        "During the fourteenth century, the German community at Bryggen gave this legal position a more durable corporate shape. The organization known as the Kontor possessed officers, common rules, assemblies and a seal through which merchants could speak collectively. It remained within a Norwegian city and relied on royal grants; its strength came from joining those grants to self-government and the wider support of Hanseatic towns. Privilege did more than protect a trader for one season. It allowed a foreign commercial body to build memory, discipline and succession beside the king’s harbour.",
      ],
      image: `${imageRoot}/04-crown-grants-door.avif`,
      imageAlt:
        "A Norwegian royal officer presents a sealed privilege at a medieval Bryggen warehouse threshold while merchants inspect its toll marks and clauses.",
      imagePosition: "59% center",
      mobileImagePosition: "66% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "sealed-threshold",
      side: "right",
      sourceIds: ["nedkvitne-2014", "oye-bergen-hansa", "unesco-bryggen"],
      evidence: [
        "Norwegian royal grants and confirmations established the legal conditions under which German merchants traded and resided in Bergen.",
        "The Bergen Kontor developed during the fourteenth century as a self-regulating merchant organization founded on privileges within the Norwegian realm.",
      ],
      map: { x: 43, y: 31 },
    },
    {
      id: "yard-becomes-government",
      actId: "privilege-builds-house",
      order: 5,
      period: "c. AD 1360–1450",
      place: "The German Kontor, Bryggen",
      title: "The Yard Becomes a Government",
      thesis:
        "Bryggen’s deep timber yards joined storage, work, discipline and assembly in one corporate machine.",
      body: [
        "From the quay, a Bryggen yard ran inward as a narrow timber world. The sea-facing rooms received goods and business; passages led between stacked stores, working spaces and chambers farther from the water. Hoists, beams and steep stairs made every part answer to cargo. Stockfish demanded dry storage and careful grading. Ledgers, seals and correspondence required places where a firm could remember obligations through winter. Architecture compressed the commercial road into a sequence from ship to scales, warehouse, account and outward sale.",
        "The German community was overwhelmingly male: merchants, young assistants, apprentices and servants living under Kontor discipline during their stay. Fire posed a mortal threat among dense wooden buildings and valuable dry cargo. Heated life therefore gathered in protected communal rooms, especially the schøtstuer associated with the yards, where men ate, met and heard rules or disputes while open flames were kept away from vulnerable warehouses. The arrangement exchanged private domestic freedom for security, order and the concentration required by a foreign trading station.",
        "Aldermen, a council and assemblies gave the settlement offices through which it could act. Yard rules governed work and conduct; common ordinances guarded weights, credit, reputation and obedience to collective decisions. Internal judgment kept many conflicts from becoming public quarrels with the city or crown. Each opened room reveals part of the institution: the quay accepted the world, the warehouse preserved its goods, the office preserved its claims and the assembly preserved its discipline. Bryggen’s yard was therefore a form of government built from pine, routine and corporate memory.",
      ],
      image: `${imageRoot}/05-bryggen-yard.avif`,
      imageAlt:
        "A cutaway reconstruction of a medieval Bryggen yard showing its quay, stockfish stores, merchant rooms, narrow passage and protected communal fire hall.",
      imagePosition: "center center",
      mobileImagePosition: "52% center",
      visualLabel: "Archaeological reconstruction",
      visualTone: "weathered-pine",
      side: "left",
      sourceIds: ["oye-bergen-hansa", "unesco-bryggen", "nedkvitne-2014"],
      evidence: [
        "Bryggen archaeology preserves the long, narrow tenement pattern that connected waterfront handling, storage, work and living spaces.",
        "Kontor rules, offices and protected communal rooms organized a resident male merchant community amid severe fire risk and valuable dry cargo.",
      ],
      map: { x: 43, y: 31 },
      interaction: {
        kind: "chapter-v2",
        family: "record",
        variant: "bryggen-yard",
        prompt: "Open a Bryggen yard",
        accessibleSummary:
          "Four architectural states move from the quay through storage and merchant rooms to the protected communal hall, explaining the task and rule carried by each part of a Bryggen yard.",
        initialId: "quay",
        records: [
          {
            id: "quay",
            label: "Quay and hoist",
            period: "The waterward threshold",
            kicker: "Cargo enters the yard",
            detail:
              "Boats discharge stockfish beside scales, lifting beams and tallying men who establish the quantity received from the coast.",
            fields: [
              { label: "Task", value: "Unload, weigh and mark" },
              {
                label: "Rule",
                value: "Every bundle enters an accountable chain",
              },
            ],
            outcome:
              "The harbour turns a moving cargo into a recorded possession.",
          },
          {
            id: "warehouse",
            label: "Warehouse",
            period: "The deep timber store",
            kicker: "Time is held indoors",
            detail:
              "Dry rooms keep graded stockfish between arrival, sale and departure while narrow passages preserve access to each firm’s goods.",
            fields: [
              { label: "Task", value: "Grade, stack and guard" },
              { label: "Rule", value: "Cargo and fire must remain apart" },
            ],
            outcome:
              "Storage allows one season’s harvest to meet another market’s date.",
          },
          {
            id: "stue",
            label: "Merchant rooms",
            period: "Office and lodging",
            kicker: "The firm remembers",
            detail:
              "Merchants and assistants keep accounts, correspondence and daily discipline close to the cargo entrusted to their company.",
            fields: [
              { label: "Task", value: "Reckon, write and supervise" },
              {
                label: "Rule",
                value: "The resident company answers for its men",
              },
            ],
            outcome:
              "Written memory survives the departure of any individual merchant.",
          },
          {
            id: "schotstue",
            label: "Schøtstue",
            period: "Communal heat and assembly",
            kicker: "The yard becomes a body",
            detail:
              "A protected common room supplies warmth, meals, meetings and judgment beyond the most vulnerable warehouse range.",
            fields: [
              { label: "Task", value: "Eat, deliberate and enforce" },
              { label: "Rule", value: "Common safety and common discipline" },
            ],
            outcome:
              "The separate firms acquire a place in which they can decide and act together.",
          },
        ],
      },
    },
    {
      id: "privilege-must-be-defended",
      actId: "privilege-builds-house",
      order: 6,
      period: "fourteenth–fifteenth centuries",
      place: "Bergen",
      title: "Privilege Must Be Defended",
      thesis:
        "A privilege became power only when documents, officers and collective discipline kept it alive.",
      body: [
        "A seal in a chest could accomplish nothing by itself. Merchants had to produce the privilege at the right tribunal, preserve earlier confirmations and answer a royal officer’s interpretation with precedent of their own. Kings changed, tolls were disputed and local interests pressed against foreign advantage. The Kontor therefore treated archives and negotiation as instruments of trade. A warehouse door remained open because someone could name the right, show its wording and persuade authority to enforce it through another season.",
        "Bergen contained several jurisdictions in close quarters. The crown guarded revenue and peace. Urban officers represented the town’s interests. The Kontor disciplined its members under common ordinances, while each trading yard governed daily labour and stores. These authorities overlapped without becoming identical. Conflict moved through petitions, embassies, withheld business, confirmations and settlements. A durable arrangement emerged from repeated contact between offices whose powers were recognizable even when their claims collided.",
        "Collective discipline gave foreign privilege its sharpest edge. A merchant who evaded a common rule might win one advantageous bargain and weaken the terms on which every colleague depended. Kontor officers could punish breaches, coordinate demands and present many firms as one counterparty. The crown could then negotiate with a body capable of keeping promises among its own men. The achievement was practical and exact: private ambition submitted to a corporate rule so that the corporate privilege could survive. Bergen’s wet quay became a school in the European art of maintaining liberty through organized obligation.",
      ],
      image: `${imageRoot}/06-privilege-defended.avif`,
      imageAlt:
        "A Norwegian official and German merchant officers compare a royal privilege, city toll record, Kontor seal and yard tally on a Bryggen quay bench.",
      imagePosition: "61% center",
      mobileImagePosition: "67% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "privilege-table",
      side: "right",
      sourceIds: ["nedkvitne-2014", "dollinger-1970", "oye-bergen-hansa"],
      evidence: [
        "Hanseatic privileges required repeated royal confirmation, documentary preservation and negotiation with Norwegian authorities.",
        "Kontor discipline constrained individual merchants in order to preserve common terms, reputation and bargaining strength.",
      ],
      map: { x: 43, y: 31 },
    },
    {
      id: "lubeck-joins-two-seas",
      actId: "cities-act-together",
      order: 7,
      period: "c. AD 1158–1350",
      place: "Lübeck, Hamburg and the Elbe–Trave corridor",
      title: "Lübeck Joins Two Seas",
      thesis:
        "Lübeck’s position made it a meeting place between Baltic trade and the roads toward the North Sea.",
      body: [
        "Lübeck rose on the Trave near the western gate of the Baltic. To the southwest, the land and river corridor toward Hamburg and the Elbe opened a route to the North Sea. Salt came north from Lüneburg; fish, grain, wax, fur, timber and metals moved through the Baltic world; cloth and western wares approached from the opposite direction. Cargo crossed warehouses, carts and waters rather than passing through one uninterrupted canal. The labour of transhipment made Lübeck a hinge whose value increased with every connected port.",
        "The city carried institutions with its goods. Merchants formed partnerships and family connections across towns. Lübeck law, adapted locally, supplied a respected model for newer urban communities around the Baltic. Clerks copied privileges and councils exchanged letters. Familiar procedure lowered the cost of entering a strange harbour because a merchant could recognize offices, forms and civic expectations. Influence spread along a chain of autonomous towns that borrowed what worked while keeping their own councils and interests.",
        "Lübeck became the leading site of many Hanseatic meetings and an important keeper of records. Its authority remained the authority of a powerful participant, not a sovereign capital. Rostock, Wismar, Stralsund, Hamburg, Cologne, Danzig and scores of other towns decided how far a proposal served them. Attendance varied; commitments varied; rival regional groupings endured. Lübeck could summon, persuade, draft and contribute. It could not make distant councils vanish into obedience. The city joined two seas because others chose to use its position, and it led the Hanse by making agreement more useful than command.",
      ],
      image: `${imageRoot}/07-lubeck-two-seas.avif`,
      imageAlt:
        "Merchants transfer barrels and bales between Baltic vessels, carts and the road toward Hamburg along the medieval Trave–Elbe corridor.",
      imagePosition: "50% center",
      mobileImagePosition: "54% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "brick-umber",
      side: "left",
      sourceIds: [
        "hammel-kiesow-2015",
        "dollinger-1970",
        "wubs-mrozewicz-jenks-2013",
      ],
      evidence: [
        "Lübeck’s access to the Baltic and connection toward Hamburg and the Elbe made it a principal transhipment and meeting point.",
        "Lübeck law and merchant connections travelled widely, while the towns that adopted them retained autonomous councils and local variants.",
      ],
      map: { x: 49, y: 47 },
    },
    {
      id: "agreement-becomes-fleet",
      actId: "cities-act-together",
      order: 8,
      period: "fourteenth century",
      place: "Hanseatic diets, often at Lübeck",
      title: "Agreement Becomes a Fleet",
      thesis:
        "Delegated consent allowed independent town councils to turn a common sentence into ships, money and closed markets.",
      body: [
        "Delegates entered a Hanseatic meeting with instructions from the councils that had sent them. They came from cities jealous of their jurisdiction and alert to differences between maritime regions, inland markets and distant foreign houses. No monarch sat above the benches. No permanent executive could tax the towns, and no common treasury waited to obey a central command. A proposal began as a local interest carried into a room where other local interests possessed an equal power to withhold commitment.",
        "Discussion tested the width of possible action. Envoys adjusted dates, contributions, exemptions and language until participating delegations could carry a common wording home. Clerks entered the conclusions in a recess, preserving who had appeared and what had been agreed. The record did not dissolve every town into a single legal person. Councils remained responsible for ratification, ships, money, enforcement and the decision to take part. Absence, delay and refusal remained features of the system, giving common action a changing boundary from one crisis to the next.",
        "Consent could nevertheless produce formidable force. Several councils closing their markets together denied an opponent access no single port could control. Separate assessments could assemble ships into a convoy or war fleet. Shared diplomatic instructions confronted a king with a line of cities rather than one petitioning merchant. The covenant existed only when towns raised it through their own acts, which made every visible wake the consequence of an identifiable commitment. Europe’s northern cities had discovered a power neither dynastic nor territorial: a fleet launched from sentences accepted on many independent benches.",
      ],
      image: `${imageRoot}/08-raise-the-covenant.avif`,
      mobileImage: `${imageRoot}/08-raise-the-covenant-mobile.avif`,
      imageAlt:
        "Delegates with separate sealed town instructions deliberate around an empty centre in a dark medieval timber council chamber.",
      imagePosition: "center center",
      mobileImagePosition: "53% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "covenant-brass",
      side: "right",
      sourceIds: [
        "wubs-mrozewicz-jenks-2013",
        "hammel-kiesow-2015",
        "dollinger-1970",
      ],
      evidence: [
        "Hanseatic delegates represented autonomous councils, often under local instructions, and meeting decisions were preserved in written recesses.",
        "Common measures depended on participation and local execution rather than taxation or command by a permanent Hanseatic central government.",
      ],
      map: { x: 50, y: 46 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "raise-covenant",
        prompt: "Raise the covenant",
        accessibleSummary:
          "Four council states carry a proposal from locally instructed delegates through negotiated wording and a written recess to selective execution by the consenting towns; no central authority commands the result.",
        initialId: "instructions",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "instructions",
            label: "Local instructions",
            period: "Before the meeting",
            kicker: "Every delegate arrives bound",
            detail:
              "Town councils define the grievance they recognize, the contribution they may offer and the terms their envoys may accept.",
            fields: [
              { label: "Authority", value: "The sending town council" },
              { label: "Boundary", value: "No power beyond the local mandate" },
            ],
            outcome:
              "Several independent positions enter the chamber without a sovereign above them.",
            points: [
              {
                id: "hamburg",
                label: "Hamburg",
                detail:
                  "Its council sends a position shaped by North Sea trade.",
                x: 47,
                y: 47,
              },
              {
                id: "lubeck",
                label: "Lübeck",
                detail:
                  "Its council hosts and contributes its own instructions.",
                x: 49,
                y: 47,
              },
              {
                id: "rostock",
                label: "Rostock",
                detail:
                  "Its delegates bring the interests of another Baltic town.",
                x: 51,
                y: 46,
              },
              {
                id: "stralsund",
                label: "Stralsund",
                detail:
                  "Its council retains the right to define its commitment.",
                x: 53,
                y: 45,
              },
            ],
          },
          {
            id: "deliberation",
            label: "Common wording",
            period: "Inside the diet",
            kicker: "Difference enters the sentence",
            detail:
              "Delegates negotiate dates, contributions and exemptions until a clause falls within the mandates of the towns prepared to act.",
            fields: [
              {
                label: "Instrument",
                value: "Proposal, debate and amended clause",
              },
              { label: "Test", value: "Can each participant carry it home?" },
            ],
            outcome:
              "Agreement acquires a precise boundary instead of pretending to universal obedience.",
            points: [
              {
                id: "lubeck-diet",
                label: "Meeting at Lübeck",
                detail:
                  "Instructed envoys search for wording their councils can execute.",
                x: 49,
                y: 47,
              },
            ],
          },
          {
            id: "recess",
            label: "Written recess",
            period: "The meeting closes",
            kicker: "The covenant acquires a memory",
            detail:
              "Clerks record the participating towns and accepted measures so each delegation can present an exact instrument to its council.",
            fields: [
              {
                label: "Record",
                value: "Names, terms, dates and contributions",
              },
              {
                label: "Next authority",
                value: "Each participating town at home",
              },
            ],
            outcome:
              "A common text travels outward while the seals and governments remain separate.",
            points: [
              {
                id: "lubeck",
                label: "Lübeck",
                detail: "The written decision leaves the meeting place.",
                x: 49,
                y: 47,
              },
              {
                id: "hamburg",
                label: "Hamburg",
                detail: "Its council receives the common wording.",
                x: 47,
                y: 47,
              },
              {
                id: "rostock",
                label: "Rostock",
                detail: "Its council receives the common wording.",
                x: 51,
                y: 46,
              },
              {
                id: "stralsund",
                label: "Stralsund",
                detail: "Its council receives the common wording.",
                x: 53,
                y: 45,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
              [0, 3],
            ],
          },
          {
            id: "execution",
            label: "Consenting action",
            period: "After local decisions",
            kicker: "Separate acts raise one wake",
            detail:
              "Councils that consent close markets, assess money or contribute ships; a town outside the compact remains visibly outside this action.",
            fields: [
              {
                label: "Force",
                value: "Locally raised ships, money and enforcement",
              },
              {
                label: "Union",
                value: "Common purpose without common sovereignty",
              },
            ],
            outcome:
              "A coalition appears because independent cities repeatedly choose the same act.",
            points: [
              {
                id: "hamburg",
                label: "Hamburg",
                detail: "The council supplies its pledged contribution.",
                x: 47,
                y: 47,
              },
              {
                id: "lubeck",
                label: "Lübeck",
                detail: "The council supplies its pledged contribution.",
                x: 49,
                y: 47,
              },
              {
                id: "rostock",
                label: "Rostock",
                detail: "The council supplies its pledged contribution.",
                x: 51,
                y: 46,
              },
              {
                id: "stralsund",
                label: "Stralsund",
                detail: "The council supplies its pledged contribution.",
                x: 53,
                y: 45,
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
    {
      id: "markets-close-together",
      actId: "cities-act-together",
      order: 9,
      period: "AD 1361–1370",
      place: "Baltic ports, the Øresund and Stralsund",
      title: "The Markets Close Together",
      thesis:
        "Against Valdemar IV of Denmark, civic agreement matured into embargo, contributed fleets and a negotiated peace.",
      body: [
        "In 1361 Valdemar IV of Denmark conquered Gotland and seized Visby, a trading city whose position mattered across the Baltic. The attack showed every merchant town how quickly a king could alter the conditions of passage. Early resistance ended in reverse, and the interests of Hanseatic towns did not immediately align. The danger had to be translated into commitments that distinct councils considered worth ships, money and interrupted trade. A common enemy supplied urgency; only organized consent could supply a fleet.",
        "The stronger coalition took shape in the Confederation of Cologne in 1367. Participating towns and their allies specified contributions and prepared a new war against Denmark. Markets could be closed to Danish trade; ships were assessed among cities; diplomacy bound maritime towns to other opponents of Valdemar. The coalition’s power lay in combination. An embargo reached through many ports, and a fleet assembled from several civic treasuries could challenge control of the straits on which Baltic commerce depended.",
        "The campaign compelled negotiation, and the Treaty of Stralsund in 1370 restored and confirmed broad trading privileges. Danish strongholds and customs revenues were pledged as security for the settlement, giving the victorious coalition leverage at the passages between the seas. No Hanseatic crown emerged from the victory. The towns returned to their own councils with a greater fact established: northern kings had to reckon with cities capable of closing markets together and making their separate ships arrive as one force. Consent had survived its severest test by becoming strategy.",
      ],
      image: `${imageRoot}/09-markets-close-together.avif`,
      imageAlt:
        "A medieval Baltic sea chart joins shuttered market doors, ships contributed by separate towns and the sealed Treaty of Stralsund.",
      imagePosition: "54% center",
      mobileImagePosition: "59% center",
      visualLabel: "Documentary reconstruction",
      visualTone: "closed-harbours",
      side: "left",
      sourceIds: [
        "dollinger-1970",
        "hammel-kiesow-2015",
        "wubs-mrozewicz-jenks-2013",
      ],
      evidence: [
        "Valdemar IV’s conquest of Gotland in 1361 preceded failed resistance, renewed coalition building and the Confederation of Cologne in 1367.",
        "The Treaty of Stralsund in 1370 confirmed trading privileges and secured them with temporary control of Danish strongholds and customs revenues.",
      ],
      map: { x: 53, y: 45 },
    },
    {
      id: "four-foreign-houses-watch-routes",
      actId: "edges-hold-league",
      order: 10,
      period: "c. AD 1350–1500",
      place: "Bergen, Bruges, London and Novgorod",
      title: "Four Foreign Houses Watch the Routes",
      thesis:
        "The great Kontore gave Hanseatic merchants permanent eyes, stores and legal footholds at the exposed ends of trade.",
      body: [
        "A ship could carry news only after someone at the edge had learned what mattered. The four great Kontore placed resident merchant communities in Bergen, Bruges, London and Novgorod, each beyond the government of the towns that used it. Their officers guarded privileges, regulated their own merchants, settled internal disputes and maintained communication with councils at home. A changed toll, poor harvest, disputed weight or hostile ordinance entered the network through men who had watched it emerge locally.",
        "Each house possessed a different material intelligence. Bergen knew the grades and seasons of stockfish and the politics of Norwegian provision. Novgorod’s Peterhof dealt with wax, fur and the rules of a Russian market reached through Baltic routes. London’s Steelyard stood inside the English wool, cloth and metal trade under privileges negotiated with the crown. Bruges placed Hanseatic merchants beside Europe’s dense exchange of Flemish cloth, credit and shipping. A universal office would have understood these places less well than four specialized communities did.",
        "Reports, letters, envoys and visiting merchants carried knowledge back through the towns. Resident enclaves remembered the wording of local rights and recognized the first signs of danger to them. They also knew opportunity: a price movement, a shortage, a new buyer or a safer route. The Hanse developed continental intelligence without creating a royal bureaucracy. Its watchers belonged to institutions embedded in foreign cities, dependent on local relationships and connected to autonomous councils. Power came inward from the edges before it ever travelled outward as a common decision.",
      ],
      image: `${imageRoot}/10-four-foreign-houses.avif`,
      imageAlt:
        "Four distinct medieval merchant stations show Bergen stockfish, Bruges cloth, London wool and pewter, and Novgorod wax and fur joined by a restrained sea route.",
      imagePosition: "center center",
      mobileImagePosition: "49% center",
      visualLabel: "Material reconstruction",
      visualTone: "four-kontore",
      side: "right",
      sourceIds: [
        "wubs-mrozewicz-jenks-2013",
        "dollinger-1970",
        "hammel-kiesow-2015",
      ],
      evidence: [
        "The major Kontore at Bergen, Bruges, London and Novgorod maintained distinct officers, rules and privileges fitted to their host markets.",
        "Resident merchant communities gathered local information and transmitted it to the towns through correspondence, envoys and commercial traffic.",
      ],
      map: { x: 50, y: 43 },
    },
    {
      id: "edges-write-back",
      actId: "edges-hold-league",
      order: 11,
      period: "fourteenth–fifteenth centuries",
      place: "The four Kontore",
      title: "The Edges Write Back",
      thesis:
        "Local difference made the Hanse intelligent because every foreign house learned a law, commodity and ruler the others did not share.",
      body: [
        "Bergen’s Kontor lived by a Norwegian conjunction of royal privilege, coastal production and imported grain. Its merchants could judge stockfish quality and harbour custom with an intimacy unavailable in Lübeck. Their position also depended on Norwegian sellers, carriers and authority. Every report from Bryggen therefore contained two kinds of knowledge: the value of a northern cargo and the political terms under which foreigners could reach it. The edge spoke in details that a distant council could neither invent nor ignore.",
        "The other houses wrote in different hands. At Novgorod, the Peterhof’s seasonal and communal rules protected trade in fur and wax within a Russian legal environment. London’s Steelyard negotiated recurring privileges with English kings while handling wool, cloth, pewter and other goods. Bruges connected Hanseatic merchants to Flemish industry, international finance and a crowd of foreign nations. Each enclave adapted common merchant interests to its host because the same ordinance could not master four different frontiers.",
        "Difference strengthened the network when information travelled swiftly enough to guide a council’s decision. Opening one Kontor reveals a privilege, an officer, a commodity and a dependency found nowhere else; the active line then runs from that edge toward the towns that need its report. The Hanse’s geography was never a wheel with Lübeck commanding passive spokes. It resembled a set of watchful thresholds whose knowledge could summon selective cooperation. The foreign houses made distance governable by preserving local variation and writing it back into common deliberation.",
      ],
      image: `${imageRoot}/11-edges-write-back.avif`,
      imageAlt:
        "Documents and commodities from Bergen, Bruges, London and Novgorod form four tactile stations whose routes lead inward toward Hanseatic towns.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualLabel: "Documentary reconstruction",
      visualTone: "edge-intelligence",
      side: "left",
      sourceIds: [
        "wubs-mrozewicz-jenks-2013",
        "dollinger-1970",
        "nedkvitne-2014",
      ],
      evidence: [
        "Kontor ordinances varied because each enclave operated under a distinct host authority, commodity structure and pattern of residence.",
        "The network’s common policies drew on information produced at its foreign edges rather than issued by a permanent central administration.",
      ],
      map: { x: 50, y: 43 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "four-kontore",
        prompt: "Hold the four Kontore",
        accessibleSummary:
          "Four selectable foreign houses reveal their principal goods, legal privilege, officers and local dependency; each selection traces intelligence from the edge toward the Hanseatic towns.",
        initialId: "bergen",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "bergen",
            label: "Bergen",
            period: "The stockfish threshold",
            kicker: "Timber, fish and royal privilege",
            detail:
              "The Bryggen Kontor gathers Norwegian stockfish for export and secures imported provisions through rights maintained with the Norwegian crown.",
            fields: [
              {
                label: "Goods",
                value: "Stockfish outward; grain and cloth inward",
              },
              {
                label: "Office",
                value: "Aldermen, council and common assembly",
              },
              {
                label: "Dependency",
                value: "Norwegian producers, carriers and royal peace",
              },
            ],
            outcome:
              "Knowledge of the fish trade and Norwegian politics travels from Bryggen into the network.",
            points: [
              {
                id: "bergen",
                label: "Bergen",
                detail: "The Kontor reads the Norwegian harbour from within.",
                x: 43,
                y: 31,
              },
              {
                id: "lubeck",
                label: "Lübeck",
                detail:
                  "Letters and envoys carry the edge’s intelligence toward the towns.",
                x: 49,
                y: 47,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "bruges",
            label: "Bruges",
            period: "The cloth and credit threshold",
            kicker: "Flemish industry meets many nations",
            detail:
              "Hanseatic merchants enter Europe’s dense cloth and financial market through negotiated collective privileges and resident representation.",
            fields: [
              {
                label: "Goods",
                value: "Cloth, salt, grain and northern wares",
              },
              { label: "Office", value: "Elected merchant representatives" },
              {
                label: "Dependency",
                value: "Flemish production, brokers and urban authority",
              },
            ],
            outcome:
              "Prices and credit conditions travel from the western market toward Baltic councils.",
            points: [
              {
                id: "bruges",
                label: "Bruges",
                detail:
                  "The Kontor watches cloth, finance and international shipping.",
                x: 39,
                y: 50,
              },
              {
                id: "lubeck",
                label: "Lübeck",
                detail:
                  "Correspondence brings western market intelligence eastward.",
                x: 49,
                y: 47,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "london",
            label: "London",
            period: "The royal market threshold",
            kicker: "The Steelyard bargains with a crown",
            detail:
              "The London Kontor maintains collective rights in an English market rich in wool, cloth, metals and royal customs interests.",
            fields: [
              {
                label: "Goods",
                value: "Wool, cloth, pewter and Baltic imports",
              },
              {
                label: "Office",
                value: "Aldermen and the Steelyard community",
              },
              {
                label: "Dependency",
                value: "Royal grants, civic relations and English suppliers",
              },
            ],
            outcome:
              "A change in English policy reaches the continental towns before it becomes a closed door.",
            points: [
              {
                id: "london",
                label: "London",
                detail: "The Steelyard observes the crown and English market.",
                x: 36,
                y: 49,
              },
              {
                id: "lubeck",
                label: "Lübeck",
                detail: "The edge reports into the wider merchant network.",
                x: 49,
                y: 47,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "novgorod",
            label: "Novgorod",
            period: "The fur and wax threshold",
            kicker: "The Peterhof keeps a seasonal rule",
            detail:
              "The enclosed Peterhof regulates residence and exchange at a Russian market reached through Baltic sailing and river routes.",
            fields: [
              {
                label: "Goods",
                value: "Fur and wax westward; cloth and metal goods eastward",
              },
              {
                label: "Office",
                value: "Aldermen under the Peterhof ordinances",
              },
              {
                label: "Dependency",
                value: "Novgorodian suppliers, law and safe passage",
              },
            ],
            outcome:
              "Eastern prices, rules and dangers write back from the network’s farthest great enclave.",
            points: [
              {
                id: "novgorod",
                label: "Novgorod",
                detail: "The Peterhof gathers knowledge at the eastern market.",
                x: 76,
                y: 38,
              },
              {
                id: "lubeck",
                label: "Lübeck",
                detail:
                  "Reports carry the eastern edge toward the Baltic towns.",
                x: 49,
                y: 47,
              },
            ],
            links: [[0, 1]],
          },
        ],
      },
    },
    {
      id: "north-learns-collective-power",
      actId: "edges-hold-league",
      order: 12,
      period: "c. AD 1450–1500",
      place: "North Sea and Baltic towns",
      title: "The North Has Learned Collective Power",
      thesis:
        "Before the balance shifted toward oceanic carriers and territorial states, the northern cities had proved the reach of consent, privilege and common force.",
      body: [
        "By the later fifteenth century, the field of northern trade was changing. Dutch carriers moved bulk cargo with growing efficiency. Territorial rulers pressed harder upon urban privilege, and Atlantic routes began to alter the geography of European opportunity. Hanseatic towns differed over which markets, wars and concessions deserved sacrifice. The same local freedom that made consent meaningful could slow action when interests diverged. Common power narrowed as the cost of achieving a common sentence rose.",
        "The Hanse did not vanish at 1500. Its towns, privileges and foreign houses endured, and its name retained force for centuries. Its command had never been uniform even at its height. The enduring achievement lay in what merchants and councils had already made possible across immense distance. They kept resident institutions abroad, disciplined their own members, shared intelligence, coordinated embargoes, negotiated with kings and raised fleets from civic contributions. A political actor existed whenever enough autonomous cities chose to create it.",
        "Northern Europe carried that knowledge forward. Charter, guild, town council, estate, league and privileged corporation filled the space between household and crown with organized bodies able to own, remember, bargain and resist. The Hanse gave this European plurality a maritime scale from Novgorod to London and from Bergen to Bruges. Its last common seal remained distinct from every seal that sustained it. Beyond the warehouse door stood an inland order built on the same conviction: unequal powers could preserve their liberties by learning how to agree.",
      ],
      image: `${imageRoot}/12-north-collective-power.avif`,
      imageAlt:
        "Councillors and merchants meet inside a late-medieval harbour warehouse while newer deep-sea vessels pass beyond the open doors.",
      imagePosition: "57% center",
      mobileImagePosition: "62% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "late-harbour",
      side: "right",
      sourceIds: [
        "dollinger-1970",
        "hammel-kiesow-2015",
        "wubs-mrozewicz-jenks-2013",
      ],
      evidence: [
        "Dutch competition, stronger territorial governments and divergent urban interests reduced the consistency of Hanseatic common action by the end of the fifteenth century.",
        "Hanseatic privileges and institutions endured beyond 1500, preserving a demonstrated European practice of coordination among autonomous corporate towns.",
      ],
      map: { x: 51, y: 43 },
    },
  ],
};
