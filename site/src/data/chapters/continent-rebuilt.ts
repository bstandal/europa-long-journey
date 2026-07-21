import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/continent-rebuilt";

export const continentRebuilt: ChapterDefinition = {
  slug: "continent-rebuilt",
  number: "23",
  title: "The Continent Rebuilt",
  openingTitleLines: ["The Continent", "Rebuilt"],
  period: "AD 1945–1989",
  claim:
    "From the same ruin, Europe took two roads. Western Europe bound American protection, national democracy and economic power inside treaties and law; Soviet power held the east through party and army. In 1989, the eastern nations reclaimed their European future and the roads met.",
  openingClaim:
    "One road made rivalry governable through aid, alliance, treaty and court. The other kept nations alive beneath communist rule until faith, memory and civic courage could return them to public life.",
  hero: {
    image: `${imageRoot}/opening-two-roads-to-1989.avif`,
    mobileImage: `${imageRoot}/opening-two-roads-to-1989-mobile.avif`,
    imageAlt:
      "A paired monochrome field begins in the same 1945 rubble: a western road gathers an aid manifest and treaty ledger while an eastern road passes beneath concrete toward duplicated paper, candles and a shipyard gate.",
    imagePosition: "center center",
    mobileImagePosition: "54% center",
    visualLabel: "Two Roads to 1989 · rubble, treaty page and duplicated sheet",
  },
  theme: {
    id: "two-roads",
    label: "Two Roads to 1989",
  },
  openingAction: "Walk the two roads",
  mapLabel:
    "The western institutions and eastern civic awakenings that advanced from the same ruin toward the open gates of 1989",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Recovery accounts · aid manifests · alliance treaties · Community law · court judgments · radio transcripts · pilgrimage homilies · strike bulletins · ballots",
  acts: [
    {
      id: "two-orders-rise",
      number: "I",
      label: "Two orders rise from one ruin",
      period: "AD 1945–1955",
      title: "Two Orders Rise from One Ruin",
      detail:
        "Aid, occupation, security and ideology divide the continent into an Atlantic west and a Soviet east.",
    },
    {
      id: "west-binds-power",
      number: "II",
      label: "The west binds power through law",
      period: "AD 1950–1986",
      title: "The West Binds Power through Law",
      detail:
        "Coal, steel, trade, courts and democratic enlargement make cooperation cumulative and national rivalry governable.",
    },
    {
      id: "east-keeps-nations-alive",
      number: "III",
      label: "The east keeps its nations alive",
      period: "AD 1956–1979",
      title: "The East Keeps Its Nations Alive",
      detail:
        "Budapest, Berlin, Prague and Warsaw expose the coercive limits of Soviet order. National and moral community endures beneath it.",
    },
    {
      id: "roads-meet",
      number: "IV",
      label: "The roads meet",
      period: "AD 1980–1989",
      title: "The Roads Meet",
      detail:
        "Solidarity creates an independent public body, negotiated openings spread and the Soviet barrier falls under the pressure of nations acting in concert.",
    },
  ],
  ending: {
    period: "AD 1989",
    title: "Europe Is No Longer Divided by Force",
    detail:
      "At the opened Brandenburg Gate, the two roads met. The western road arrived with Atlantic protection, treaty, market and court: institutions built by democratic states to make power answer to agreed rules. The eastern road arrived with recovered nations and the authority of people who preserved truth in churches, kitchens, workshops, theatres and duplicated pages when the state demanded a lie. They entered the same field with distinct histories. Beyond Berlin lay Warsaw, Tallinn, Tbilisi and Kyiv. Europe now had to carry freedom eastward and defend each nation’s choice when Russia returned to conquest.",
    image: `${imageRoot}/ending-europe-no-longer-divided-by-force.avif`,
    mobileImage: `${imageRoot}/ending-europe-no-longer-divided-by-force-mobile.avif`,
    nextPeriod: "AD 1989–20 July 2026",
  },
  returnHash: "continent-rebuilt",
  nextHash: "europe-returns",
  nextTitle: "Europe Returns",
  nextSlug: "europe-returns",
  movements: [
    {
      id: "europe-counts-what-remains",
      actId: "two-orders-rise",
      order: 1,
      period: "AD 1945–1946",
      place: "Warsaw, Berlin and Rotterdam",
      title: "Europe Counts What Remains",
      thesis:
        "Reconstruction began when exhausted Europeans counted the living, cleared streets and restored the ordinary offices through which a society could act again.",
      body: [
        "A surveyor stepped through Warsaw with a board, pencil and street plan whose buildings no longer stood. German forces had destroyed the greater part of the capital during the occupation and after crushing the uprising of 1944. Berlin ended the war as a burned and divided administrative centre. Rotterdam’s cleared heart still exposed the violence of 1940. Across the continent, bridges lay in rivers, rails ended at craters and families searched station platforms for people dispersed by battle, deportation, forced labour, border changes and the camps.",
        "Recovery first appeared as lists. Municipal clerks registered residents and assigned rooms in surviving buildings. Engineers marked unstable walls, restored pumps and strung tram wire across cleared avenues. Ration offices converted scarcity into named claims on bread, coal and milk; schools collected children into rooms with repaired windows; railway workers joined short usable lengths of track into longer ones. Citizens carried brick by hand while local authorities, occupation governments and relief agencies brought food, medicine, tools and transport into cities whose tax base and machinery had disappeared.",
        "A working register allowed a family to receive a ration; a repaired line carried coal to a power station; electricity returned workshops to production and gave a city evening light. Europe had lost millions of citizens and much of its material capital, yet it retained engineers, councils, cooperatives, ministries, churches, unions and habits of public administration. Reconstruction began as the deliberate recovery of ordinary competence. Each ruined state could pursue it alone, or resources arriving from across the Atlantic could teach the western half of Europe to plan together.",
      ],
      image: `${imageRoot}/01-europe-counts-what-remains.avif`,
      mobileImage: `${imageRoot}/01-europe-counts-what-remains-mobile.avif`,
      imageAlt:
        "Dated views of Warsaw, Berlin and Rotterdam are joined by a municipal reconstruction ledger, a cleared tram line and a reopened classroom.",
      imagePosition: "55% center",
      mobileImagePosition: "61% center",
      visualLabel: "1945 survey sheets · streets, residents and services",
      visualTone: "shared-ruin",
      side: "left",
      sourceIds: ["judt-2005", "mazower-1998"],
      evidence: [
        "German occupation and deliberate destruction left most of Warsaw’s built fabric in ruins, while Berlin and Rotterdam also faced immense housing, transport and utility damage.",
        "Municipal registration, rationing, debris clearance, transport repair and international relief restored the basic systems on which later economic recovery depended.",
      ],
      map: { x: 55, y: 34 },
    },
    {
      id: "the-atlantic-sends-machines",
      actId: "two-orders-rise",
      order: 2,
      period: "AD 1947–1952",
      place: "Harvard, Paris, Rotterdam and the Ruhr",
      title: "The Atlantic Sends Machines",
      thesis:
        "The Marshall Plan joined American resources to European allocation, making material recovery a lesson in western cooperation.",
      body: [
        "At Harvard on 5 June 1947, the American secretary of state, George Marshall, offered support for a European recovery programme that Europeans would help frame themselves. The proposal addressed a material chain near collapse: farms lacked fertiliser and machinery, mines lacked timber and pumps, railways lacked rolling stock, and factories could not obtain the fuel or imported inputs needed to restart. Dollars mattered because European states had little foreign exchange with which to buy from the productive economy that the war had left intact across the Atlantic.",
        "Sixteen European governments met in Paris to state their requirements together. The Organisation for European Economic Co-operation, founded in 1948, compared national programmes and allocated scarce imports under the European Recovery Program. Ships unloaded wheat, coal, petroleum, industrial equipment, vehicles and machine tools. Governments sold many imported goods in local currency and used the resulting counterpart funds for reconstruction and investment. An American appropriation could therefore become a transformer, a repaired locomotive, an electrified workshop and another train of finished goods rather than a single transfer between treasuries.",
        "The offer sharpened the continental division. The Soviet Union rejected the programme and compelled governments under its control to remain outside; Czechoslovakia withdrew after first accepting the Paris invitation. In the west, American aid accelerated recovery already being driven by European labour, policy and technical skill, while the requirement to compare plans made governments practise cooperation before they possessed permanent common institutions. The Atlantic had delivered protection and machinery. It had also given western Europe a room in which national needs could be entered on one sheet.",
      ],
      image: `${imageRoot}/02-the-atlantic-sends-machines.avif`,
      imageAlt:
        "An ERP timber crate opens beside an aid manifest, Rotterdam unloading gear, a repaired locomotive component and a Ruhr power-station order.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "ERP manifest · allocation, port, rail and production",
      visualTone: "recovery-crate",
      side: "right",
      sourceIds: [
        "marshall-harvard-1947",
        "economic-cooperation-act-1948",
        "oeec-convention-1948",
        "judt-2005",
      ],
      evidence: [
        "Marshall’s Harvard address made a coordinated European programme a condition of the American recovery offer, and sixteen governments answered through negotiations in Paris.",
        "The European Recovery Program supplied commodities and capital goods while counterpart funds and OEEC coordination linked imports to national investment and production plans.",
      ],
      map: { x: 46, y: 36 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "recovery-shipment-chain",
        prompt: "Unload recovery",
        accessibleSummary:
          "Four documentary states follow a Marshall Plan shipment from American authorization through joint European allocation and a western port to rail, power and factory production.",
        initialId: "authorize-programme",
        records: [
          {
            id: "authorize-programme",
            label: "Authorize the programme",
            period: "Washington · April AD 1948",
            kicker: "Congress turns the offer into supply",
            detail:
              "The Economic Cooperation Act gives the recovery offer an appropriation, an administration and the authority to purchase goods for approved European programmes.",
            fields: [
              { label: "Instrument", value: "Economic Cooperation Act" },
              {
                label: "American office",
                value: "Economic Cooperation Administration",
              },
              {
                label: "Capacity released",
                value: "Purchasing power in dollars",
              },
            ],
            outcome:
              "European requirements can now become orders placed in the American market.",
            points: [
              {
                id: "washington",
                label: "Washington",
                detail: "Congress authorizes the recovery programme.",
                x: 22,
                y: 37,
              },
            ],
          },
          {
            id: "allocate-together",
            label: "Allocate together",
            period: "Paris · AD 1948–1949",
            kicker: "National requests enter one comparison",
            detail:
              "OEEC delegates compare shortages, production targets and import needs, forcing governments to explain how each request supports a wider European recovery.",
            fields: [
              { label: "European office", value: "OEEC committees" },
              {
                label: "Documents",
                value: "National programmes and allocation tables",
              },
              {
                label: "Capacity released",
                value: "A coordinated import order",
              },
            ],
            outcome:
              "Scarce dollars and goods follow an agreed programme rather than sixteen separate scrambles.",
            points: [
              {
                id: "paris",
                label: "Paris",
                detail: "European delegates compare programmes.",
                x: 46,
                y: 40,
              },
              {
                id: "washington",
                label: "Washington",
                detail: "The approved request returns for procurement.",
                x: 22,
                y: 37,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "unload-equipment",
            label: "Unload the equipment",
            period: "Rotterdam · c. AD 1949",
            kicker: "The dollar becomes a physical cargo",
            detail:
              "Port records and ERP markings identify industrial equipment, fuel and spare parts as they pass from ship to railway under a national recovery programme.",
            fields: [
              { label: "Carrier", value: "Atlantic freighter" },
              {
                label: "Material",
                value: "Fuel, machinery and replacement parts",
              },
              { label: "Transfer", value: "Quay crane to freight wagon" },
            ],
            outcome:
              "Recovery leaves the ledger and enters Europe’s damaged transport system.",
            points: [
              {
                id: "atlantic",
                label: "Atlantic crossing",
                detail: "The manifest travels with the cargo.",
                x: 33,
                y: 39,
              },
              {
                id: "rotterdam",
                label: "Rotterdam",
                detail: "The port transfers the shipment to rail.",
                x: 45,
                y: 35,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "multiply-production",
            label: "Multiply the shipment",
            period: "The Ruhr · AD 1949–1952",
            kicker: "One import restores several links",
            detail:
              "Fuel and equipment return a power station and rail workshop to steadier output; working trains then carry coal, steel and finished machinery to other producers.",
            fields: [
              { label: "First use", value: "Power and railway repair" },
              { label: "Next use", value: "Coal and steel movement" },
              {
                label: "Capacity released",
                value: "Repeated industrial production",
              },
            ],
            outcome:
              "The value of the shipment persists in the European output it allows to move again.",
            points: [
              {
                id: "rotterdam",
                label: "Rotterdam",
                detail: "Freight enters the continental rail network.",
                x: 45,
                y: 35,
              },
              {
                id: "ruhr",
                label: "Ruhr",
                detail: "Power, rail and factories reinforce one another.",
                x: 48,
                y: 37,
              },
            ],
            links: [[0, 1]],
          },
        ],
      },
    },
    {
      id: "security-draws-two-roads",
      actId: "two-orders-rise",
      order: 3,
      period: "AD 1948–1955",
      place: "Berlin, Washington, Brussels, Moscow and Warsaw",
      title: "Security Draws Two Roads",
      thesis:
        "American commitment and Soviet command hardened wartime occupation lines into two different European security orders.",
      body: [
        "In June 1948, Soviet authorities cut the western land routes into Berlin. American and British aircraft answered with a sustained airlift, landing food, fuel and other necessities inside the western sectors until the blockade ended in May 1949. The contest made the postwar division physical before either side had completed its institutions. Western Europeans saw that reconstruction depended on an American willingness to remain; the Kremlin saw that pressure short of war could consolidate rather than dissolve the western position.",
        "Twelve governments signed the North Atlantic Treaty in Washington on 4 April 1949. Its fifth article treated an armed attack against one as an attack against all while leaving each ally to take the action it deemed necessary. Permanent councils and an integrated military command converted the pledge into consultation, planning and forces. Greece and Turkey joined in 1952; the Federal Republic of Germany entered in May 1955. National governments retained the treaty right to decide, but their defence now rested on American power committed in advance to the Atlantic area.",
        "The Soviet Union answered West German accession by creating the Warsaw Pact with seven eastern European governments in May 1955. Its language also spoke of collective defence, while its commands served a political order installed under Soviet occupation and disciplined through ruling communist parties, security services and the Red Army. The East German workers’ uprising of 1953 had already shown the coercion beneath that order. Europe’s two roads now possessed headquarters, treaties and troops. Their decisive difference would appear when a member nation tried to choose another direction.",
      ],
      image: `${imageRoot}/03-security-draws-two-roads.avif`,
      imageAlt:
        "The Berlin airlift corridor divides into the North Atlantic Treaty table and the later Warsaw Pact command table, each clearly dated and labelled.",
      imagePosition: "55% center",
      mobileImagePosition: "62% center",
      visualLabel: "Berlin air corridor · Atlantic treaty · Soviet command",
      visualTone: "divided-security",
      side: "left",
      sourceIds: ["nato-treaty-1949", "warsaw-treaty-1955", "judt-2005"],
      evidence: [
        "The western allies supplied West Berlin by air throughout the Soviet blockade of 1948–1949, demonstrating an enduring American and British commitment to their sectors.",
        "NATO was founded in 1949 and admitted West Germany in 1955; the Soviet Union then established the Warsaw Pact with its eastern European satellite governments.",
      ],
      map: { x: 51, y: 34 },
    },
    {
      id: "coal-and-steel-enter-one-ledger",
      actId: "west-binds-power",
      order: 4,
      period: "AD 1950–1952",
      place: "Paris, Luxembourg and the Ruhr",
      title: "Coal and Steel Enter One Ledger",
      thesis:
        "The Schuman plan placed the raw materials of Franco-German war under a common authority whose daily work made reconciliation concrete.",
      body: [
        "On 9 May 1950, the French foreign minister Robert Schuman read a proposal prepared through the work of Jean Monnet and a small planning team. France and West Germany would place their entire coal and steel production under a common High Authority in an organisation open to other European countries. The choice went to the centre of the old danger. Ruhr coal fed furnaces; steel armed states and built industrial power. Their control had produced occupation schemes, reparation disputes and recurrent fear between France and Germany.",
        "Belgium, France, Italy, Luxembourg, the Netherlands and West Germany signed the Treaty of Paris in April 1951. The treaty entered into force in July 1952, and the High Authority began work with a Council representing governments, an Assembly and a Court. Common markets for coal opened in February 1953 and for steel in May. Published rules, inspectors, production returns, levy receipts and decisions made cooperation a sequence of ordinary administrative acts rather than an embrace between leaders.",
        "National industries and national interests remained, but each government now pursued them inside a durable common arena. Every completed decision left an office, precedent and account for the next dispute. France acquired confidence that German recovery would occur within supervision; West Germany recovered equality through participation; the smaller states received seats inside the mechanism. Reconciliation had acquired machinery. The western road would now extend that method from two strategic materials into trade, movement and law.",
      ],
      image: `${imageRoot}/04-coal-and-steel-enter-one-ledger.avif`,
      imageAlt:
        "The Schuman Declaration typescript, a Ruhr production card and a Luxembourg High Authority ledger align across one documentary table.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "Declaration, production return and High Authority ledger",
      visualTone: "enamel-ledger",
      side: "right",
      sourceIds: [
        "schuman-declaration-1950",
        "ecsc-treaty-paris-1951",
        "judt-2005",
      ],
      evidence: [
        "The Schuman Declaration proposed pooling French and German coal and steel under a common High Authority open to other European states.",
        "The six-state European Coal and Steel Community’s institutions began work in 1952, and its common markets for coal and steel opened in 1953.",
      ],
      map: { x: 47, y: 37 },
    },
    {
      id: "the-treaty-acquires-a-court",
      actId: "west-binds-power",
      order: 5,
      period: "AD 1957–1964",
      place: "Rome, Luxembourg and The Hague",
      title: "The Treaty Acquires a Court",
      thesis:
        "The common market became a legal order when treaty promises entered national courts and survived the governments that had signed them.",
      body: [
        "The six governments signed two treaties in Rome on 25 March 1957. Euratom addressed the peaceful development of atomic energy; the European Economic Community committed them to a customs union, common policies and the progressive removal of obstacles to movement. A Commission would propose and administer, a Council would decide for the states, an Assembly would scrutinise, and a Court would interpret. Trade negotiations that might once have expired with a ministry were placed inside institutions expected to remain at work.",
        "A Dutch transport company gave the arrangement its constitutional force. Van Gend en Loos challenged a customs charge before a national tribunal, which asked the European Court of Justice what the treaty required. In February 1963, the Court held that the Community constituted a new legal order whose rules could create rights for individuals enforceable by national courts. The following year, in Costa v ENEL, it held that a later national law could not override law flowing from the treaty order. Direct effect gave the rule a claimant; primacy preserved the rule against unilateral reversal.",
        "The transformation occurred through ordinary disputes over chemicals, tariffs and an electricity bill. A firm or citizen no longer depended entirely on a government choosing to enforce a European bargain against itself. National judges became participants in the common order by referring questions and applying the answers. Each treaty article could gather legislation, judgment and administrative practice around it. Western Europe had found a means of making cooperation cumulative: the government of the day could argue over the next rule, but it inherited the legal structure already built.",
      ],
      image: `${imageRoot}/05-the-treaty-acquires-a-court.avif`,
      imageAlt:
        "The Rome treaty signature table leads to a Luxembourg courtroom where a customs form and electricity bill sit beneath layered judgments.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Rome treaty · customs reference · binding judgment",
      visualTone: "treaty-court",
      side: "left",
      sourceIds: ["eec-treaty-1957", "van-gend-loos-1963", "costa-enel-1964"],
      evidence: [
        "The 1957 Treaties of Rome established the EEC and Euratom with permanent institutions and a programme for a common market among six states.",
        "Van Gend en Loos in 1963 established direct effect for qualifying Community rules, and Costa v ENEL in 1964 established the primacy of Community law over conflicting national law.",
      ],
      map: { x: 48, y: 38 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "treaty-ratchet",
        prompt: "Ratchet the treaty",
        accessibleSummary:
          "Four legal states fit coal and steel, the common market, direct effect and primacy into a structure in which every completed step remains operative in the next.",
        initialId: "pool-production",
        records: [
          {
            id: "pool-production",
            label: "Pool coal and steel",
            period: "Paris · AD 1951",
            kicker: "Rival power enters common administration",
            detail:
              "Six states place a strategic market under a High Authority, Council, Assembly and Court rather than returning each dispute to bilateral pressure.",
            fields: [
              { label: "Instrument", value: "Treaty of Paris" },
              { label: "Material", value: "Coal and steel" },
              { label: "Permanent part", value: "Common institutions" },
            ],
            outcome:
              "The first shared offices remain available when integration moves into a larger market.",
          },
          {
            id: "open-common-market",
            label: "Open the common market",
            period: "Rome · AD 1957",
            kicker: "The method widens",
            detail:
              "The EEC treaty sets a customs union and a programme for common rules while retaining institutions able to negotiate, administer and adjudicate them.",
            fields: [
              { label: "Instrument", value: "Treaty establishing the EEC" },
              {
                label: "Reach",
                value: "Goods, policies and economic movement",
              },
              { label: "Retained step", value: "The institutional method" },
            ],
            outcome:
              "Coal-and-steel cooperation becomes the working model for a broader legal economy.",
          },
          {
            id: "give-right-a-claimant",
            label: "Give the right a claimant",
            period: "Luxembourg · AD 1963",
            kicker: "The treaty enters a national courtroom",
            detail:
              "Van Gend en Loos allows an individual company to invoke a qualifying treaty rule before a Dutch court.",
            fields: [
              { label: "Judgment", value: "Case 26/62" },
              { label: "Doctrine", value: "Direct effect" },
              { label: "Permanent part", value: "A right enforceable at home" },
            ],
            outcome:
              "A European promise gains force through claimants and judges beyond the treaty table.",
          },
          {
            id: "keep-rule-operative",
            label: "Keep the rule operative",
            period: "Luxembourg · AD 1964",
            kicker: "A later national law meets the common order",
            detail:
              "Costa v ENEL prevents a member state from cancelling its Community obligation through a later domestic statute.",
            fields: [
              { label: "Judgment", value: "Case 6/64" },
              { label: "Doctrine", value: "Primacy" },
              {
                label: "Retained steps",
                value: "Institution, market and enforceable right",
              },
            ],
            outcome:
              "The legal structure can accumulate because one government cannot dismantle it alone.",
          },
        ],
      },
    },
    {
      id: "democracy-enters-by-the-southern-door",
      actId: "west-binds-power",
      order: 6,
      period: "AD 1974–1986",
      place: "Athens, Lisbon, Madrid and Brussels",
      title: "Democracy Enters by the Southern Door",
      thesis:
        "Greece, Portugal and Spain placed new constitutional orders inside the European Community, making democratic government the western road’s condition of entry.",
      body: [
        "In April 1974, junior officers ended Portugal’s dictatorship in the Carnation Revolution and opened a struggle over elections, empire, property and constitutional rule. Greece’s colonels fell that July after their regime helped provoke the Cyprus crisis; Konstantinos Karamanlis returned from exile to restore civilian government and legalise political competition. Francisco Franco died in November 1975, and Spain’s king, ministers, opposition parties, unions and voters moved through political reform, elections and the Constitution of 1978. Within three years, western Europe’s surviving southern dictatorships had given way to parliamentary states.",
        "Each new democracy sought entry into the European Community. Greece applied in 1975 and joined in 1981. Portugal and Spain applied in 1977, negotiated changes to tariffs, agriculture, fisheries, regulation and public administration, and entered together on 1 January 1986. Membership required governments and parliaments to accept a body of common law and to resolve conflicts through negotiation, legislation and courts. Accession instruments gave domestic reformers a dated programme and placed abrupt reversals against obligations shared with other democracies.",
        "Greek resistance, Portuguese soldiers and parties, and Spanish political actors recovered constitutional government within their own countries. Community entry gave their achievement a continental home and changed the meaning of enlargement. The organisation founded by six states around Franco-German reconciliation could admit different national histories without abandoning its legal form. Western integration now joined prosperity and peace to a visible political standard: European government would be competitive, constitutional and answerable to law.",
      ],
      image: `${imageRoot}/06-democracy-enters-by-the-southern-door.avif`,
      imageAlt:
        "Civic scenes from the Greek parliament, a Portuguese ballot and the Spanish Cortes align with the 1981 and 1986 accession instruments.",
      imagePosition: "55% center",
      mobileImagePosition: "63% center",
      visualLabel: "Ballot, constitution and accession instrument",
      visualTone: "southern-accession",
      side: "right",
      sourceIds: ["ep-enlargement-2026", "judt-2005"],
      evidence: [
        "Authoritarian rule ended in Portugal and Greece in 1974 and Spain entered a negotiated democratic transition after Franco’s death in 1975.",
        "Greece joined the European Communities in 1981; democratic Spain and Portugal joined together in 1986 after accession negotiations and treaty ratification.",
      ],
      map: { x: 45, y: 47 },
    },
    {
      id: "budapest-pulls-down-the-symbol",
      actId: "east-keeps-nations-alive",
      order: 7,
      period: "October–November AD 1956",
      place: "Budapest",
      title: "Budapest Pulls Down the Symbol",
      thesis:
        "Hungary recovered public sovereignty for twelve days before Soviet armour disclosed the force required to keep the eastern order intact.",
      body: [
        "Students marched through Budapest on 23 October 1956 carrying demands for free elections, freedom of speech, economic reform, national symbols and the withdrawal of Soviet troops. Crowds gathered around the radio building and toppled the immense Stalin statue, leaving its boots on the plinth. Workers joined the revolt, local and workers’ councils assumed authority, and soldiers passed weapons or refused orders. What began as a demonstration became a national revolution because institutions appeared wherever the party-state’s command receded.",
        "The reform communist Imre Nagy returned as prime minister and formed a broader government. Political parties reappeared; newspapers spoke freely; Soviet units initially withdrew from Budapest. On 1 November, Nagy declared Hungarian neutrality and the country’s withdrawal from the Warsaw Pact. For a brief interval, a European nation held meetings, issued programmes and expected its government to answer a public no longer organised by the ruling party. The eastern alliance faced the choice its treaty language concealed: accept national decision or preserve the imperial system by force.",
        "Before dawn on 4 November, Soviet forces attacked Budapest and other centres with tanks, artillery and overwhelming numbers. Street resistance continued, workers struck, thousands were killed and about two hundred thousand people fled across the Austrian frontier. Nagy was seized and later executed; János Kádár’s Soviet-backed government rebuilt communist control through arrest, punishment and eventual accommodation. Moscow had restored obedience, but it could not make the event disappear. Hungary left behind demands, broadcasts, council records and graves proving that communist rule had survived a nation’s refusal only through invasion.",
      ],
      image: `${imageRoot}/07-budapest-pulls-down-the-symbol.avif`,
      imageAlt:
        "A monochrome sequence moves from student demands and the fallen Stalin statue to a street radio, workers’ council notice and Soviet armour.",
      imagePosition: "57% center",
      mobileImagePosition: "64% center",
      visualLabel: "Sixteen Points · council notice · invasion order",
      visualTone: "budapest-revolt",
      side: "left",
      sourceIds: ["un-hungary-1957", "judt-2005"],
      evidence: [
        "Students, workers and local councils drove the Hungarian Revolution from 23 October 1956, while Nagy’s government restored political pluralism and announced withdrawal from the Warsaw Pact.",
        "Soviet forces launched a large military intervention on 4 November, crushed organised resistance, installed Kádár’s government and drove roughly two hundred thousand refugees abroad.",
      ],
      map: { x: 56, y: 44 },
    },
    {
      id: "the-wall-confesses-the-system",
      actId: "east-keeps-nations-alive",
      order: 8,
      period: "AD 1961",
      place: "Berlin",
      title: "The Wall Confesses the System",
      thesis:
        "East Germany made division into an architecture because its socialist state could not keep its population by consent.",
      body: [
        "Before dawn on 13 August 1961, East German police and work crews unrolled barbed wire through Berlin. Streets ended at barricades, railway services stopped and doors facing the sector boundary were watched. At Bernauer Strasse, the line ran along house fronts: residents escaped through windows while authorities bricked the openings and later demolished the buildings. Families who had crossed the city for work, worship or a Sunday visit found that an internal occupation boundary had become a closed frontier in a single night.",
        "The German Democratic Republic called the barrier an anti-fascist protection wall. Its practical direction faced inward. Millions had left East Germany through the still-open Berlin route since the state’s creation, including young and trained workers whom the planned economy could not afford to lose. Barbed wire became concrete wall, guard towers, patrol roads, lights, signal fences and a controlled death strip. Border troops received orders and weapons to stop unauthorised departure; escape attempts became matters of surveillance, prison, injury and death.",
        "The Wall stabilised the East German state by preventing a daily vote with one’s feet. It also made the eastern system’s weakness visible to every train and camera in West Berlin. Western institutions could attract members and applicants; Soviet Europe enclosed the route by which its own citizens were leaving. Concrete held the division for twenty-eight years, yet it could not command memory or conviction. Beneath official newspapers and party meetings, other records of Europe continued to pass through radio, literature, family speech and the knowledge that the streets on the far side still existed.",
      ],
      image: `${imageRoot}/08-the-wall-confesses-the-system.avif`,
      imageAlt:
        "A dated Bernauer Strasse panorama shows the boundary changing from barbed wire to blocked windows, concrete, patrol road and guarded border strip.",
      imagePosition: "52% center",
      mobileImagePosition: "59% center",
      visualLabel: "Bernauer Strasse · wire, wall and controlled departure",
      visualTone: "concrete-border",
      side: "right",
      sourceIds: ["chronicle-berlin-wall", "judt-2005"],
      evidence: [
        "East German forces closed the Berlin sector boundary on 13 August 1961 after years in which the city had provided the principal route out of the GDR.",
        "The border system developed from wire and masonry into layered barriers, surveillance and armed enforcement designed to prevent unauthorised movement from east to west.",
      ],
      map: { x: 51, y: 34 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "walk-two-roads",
        prompt: "Walk the two roads",
        accessibleSummary:
          "Five synchronized dates begin in the same 1945 rubble, then preserve western institutional artifacts above the line and eastern civic artifacts beneath suppression until both records align in 1989.",
        initialId: "shared-ruin",
        records: [
          {
            id: "shared-ruin",
            label: "Begin in the same ruin",
            period: "AD 1945",
            kicker: "Neither road yet exists",
            detail:
              "Warsaw, Berlin, Rotterdam and hundreds of other cities count losses, reopen services and recover the minimum capacity for public action.",
            fields: [
              {
                label: "Western road",
                value: "Municipal survey and ration book",
              },
              {
                label: "Eastern road",
                value: "Municipal survey and ration book",
              },
              {
                label: "Common inheritance",
                value: "Ruined European cities and surviving civic skill",
              },
            ],
            outcome:
              "Reconstruction starts from one catastrophe before occupation and ideology separate its institutions.",
          },
          {
            id: "security-orders",
            label: "Enter the security orders",
            period: "AD 1949–1956",
            kicker: "Alliance in the west, command in the east",
            detail:
              "Atlantic governments ratify collective defence while communist governments enter a Soviet-commanded alliance; Budapest then tests whether the eastern treaty permits a nation to leave.",
            fields: [
              { label: "Western artifact", value: "North Atlantic Treaty" },
              { label: "Eastern artifact", value: "Hungarian student demands" },
              {
                label: "What remains",
                value: "The treaty; the crushed revolt’s record",
              },
            ],
            outcome:
              "Western security becomes a standing institution; eastern sovereignty survives as a documented claim beneath Soviet force.",
          },
          {
            id: "law-and-concrete",
            label: "Set law beside concrete",
            period: "AD 1957–1968",
            kicker: "The roads reveal their mechanics",
            detail:
              "The western Community adds market rules and enforceable judgments while Berlin and Prague show the barriers required to contain movement and reform in the east.",
            fields: [
              { label: "Western artifact", value: "Court judgment" },
              {
                label: "Eastern artifact",
                value: "Wall photograph and uncensored newspaper",
              },
              {
                label: "What remains",
                value: "Legal precedent; remembered public speech",
              },
            ],
            outcome:
              "One road accumulates openly; the other preserves what tanks and censorship remove from the public surface.",
          },
          {
            id: "nation-appears",
            label: "Let the nation appear",
            period: "AD 1979–1981",
            kicker: "Moral confidence becomes organisation",
            detail:
              "Poles gather around John Paul II beyond the party’s command, then workers and intellectuals build Solidarity as an independent public body.",
            fields: [
              {
                label: "Western artifact",
                value: "Southern accession instrument",
              },
              {
                label: "Eastern artifact",
                value: "Pilgrimage badge and strike bulletin",
              },
              {
                label: "What remains",
                value: "A democratic standard; a society able to act",
              },
            ],
            outcome:
              "Suppression can drive Solidarity underground, but it can no longer restore the party’s monopoly over Polish public life.",
          },
          {
            id: "archives-align",
            label: "Align the archives",
            period: "AD 1989",
            kicker: "The roads enter a common field",
            detail:
              "Polish ballots, Hungarian border orders, the opened Berlin checkpoint and Prague’s civic proclamations meet the western archive of treaty and law.",
            fields: [
              {
                label: "Western road brings",
                value: "Alliance, market, court and accession",
              },
              {
                label: "Eastern road brings",
                value: "Recovered sovereignty, memory and organised courage",
              },
              {
                label: "Common field",
                value: "Political choice no longer divided by Soviet force",
              },
            ],
            outcome:
              "Europe’s division ends through the meeting of built institutions and nations that recovered the power to choose.",
          },
        ],
      },
    },
    {
      id: "prague-gives-socialism-a-human-voice",
      actId: "east-keeps-nations-alive",
      order: 9,
      period: "AD 1968",
      place: "Prague",
      title: "Prague Gives Socialism a Human Voice",
      thesis:
        "The Prague Spring restored argument from inside the communist system, and invasion proved that Soviet power feared even reform that remained socialist.",
      body: [
        "Alexander Dubček became first secretary of the Czechoslovak Communist Party in January 1968 after economic failure, Slovak dissatisfaction and pressure from writers and reformers had weakened the old leadership. The party’s April Action Programme promised economic change, a federal settlement for Czechs and Slovaks, rehabilitation of victims and a public life less governed by censorship and police power. Reformers called for socialism with a human face. Their programme retained the party-state while trying to make it answer to speech, law and national dignity.",
        "Newspapers, radio and television changed the tempo of the country. Journalists investigated abuses, citizens formed clubs, workers debated management and political questions returned to streets from which official language had excluded them. Moscow and several neighbouring communist leaders saw more than a domestic experiment. If one ruling party accepted uncensored public judgment, associations and meaningful legal limits, the example could cross every border in the bloc. Negotiations at Čierna nad Tisou and Bratislava produced assurances without resolving that fear.",
        "On the night of 20–21 August, Soviet-led Warsaw Pact armies invaded Czechoslovakia. Citizens removed street signs, argued with soldiers and used radio transmitters to coordinate nonviolent resistance, but organised military defence did not follow. Dubček and other leaders were taken to Moscow and compelled to accept the reversal; the ensuing ‘normalisation’ removed reformers and restored censorship. The armies closed the opening, yet their arrival destroyed the claim that communist unity expressed willing agreement. Prague left Europe the sound of a free radio continuing after tanks had entered the square.",
      ],
      image: `${imageRoot}/09-prague-gives-socialism-a-human-voice.avif`,
      imageAlt:
        "A Prague newspaper press and live radio transcript open onto Wenceslas Square before a dated Soviet-led invasion notice closes the official page.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Action Programme · uncensored press · invasion radio",
      visualTone: "prague-broadcast",
      side: "left",
      sourceIds: ["williams-1997", "judt-2005"],
      evidence: [
        "The 1968 Action Programme proposed economic reform, federalisation, rehabilitation and broad liberalisation while retaining a socialist political framework.",
        "Soviet-led Warsaw Pact forces invaded on 20–21 August, arrested the reform leadership and enabled the later restoration of censorship and party discipline.",
      ],
      map: { x: 53, y: 39 },
    },
    {
      id: "the-polish-pope-calls-a-nation-into-view",
      actId: "east-keeps-nations-alive",
      order: 10,
      period: "AD 1978–1979",
      place: "Rome, Warsaw, Częstochowa and Kraków",
      title: "The Polish Pope Calls a Nation Into View",
      thesis:
        "John Paul II’s first Polish pilgrimage gave millions a public language of dignity, history and faith beyond the communist state, making a nation visible to itself.",
      body: [
        "When the conclave elected the archbishop of Kraków on 16 October 1978, Karol Wojtyła became the first Polish pope and the first non-Italian pope in more than four centuries. He had worked under German occupation, entered a clandestine seminary and then served as priest and bishop under a government that claimed authority over Poland’s institutions and historical meaning. His election placed a Polish voice beyond the party’s power to appoint, dismiss or censor. Church bells, crowded streets and improvised celebrations registered a fact the state could manage but could not own.",
        "John Paul II returned from 2 to 10 June 1979. The government negotiated every route and broadcast, hoping protocol would contain the visit. Instead, enormous congregations assembled in Warsaw, Gniezno, Częstochowa, Kraków and other stops through parish organisation, volunteer order and private travel. In Victory Square, beside the Tomb of the Unknown Soldier, he joined Christian faith to Poland’s historical endurance and human dignity. His final invocation asked the Spirit to renew ‘the face of this land’, giving the crowd a short sentence in which national memory and moral agency could be spoken together.",
        "Poland’s opposition already possessed experience and networks. Workers had rebelled before; intellectuals in the Committee for the Defence of Workers were documenting repression and aiding families after the strikes of 1976; underground publications and parish communities kept independent thought in circulation. John Paul II changed the scale on which Poles could recognise those efforts. For nine days, millions stood together peacefully outside the party’s choreography and watched one another do it. The state retained police, factories and television. Society discovered that it possessed numbers, discipline and a source of authority the state could neither grant nor revoke.",
      ],
      image: `${imageRoot}/10-the-polish-pope-calls-a-nation-into-view.avif`,
      imageAlt:
        "A reconstructed Victory Square crowd surrounds John Paul II at the public altar while a restrained pilgrimage route links Warsaw, Częstochowa and Kraków.",
      imagePosition: "53% center",
      mobileImagePosition: "58% center",
      visualLabel: "Victory Square · 2 June 1979 · nation in public",
      visualTone: "polish-crimson",
      side: "right",
      sourceIds: [
        "john-paul-ii-warsaw-1979",
        "garton-ash-polish-revolution-2002",
        "judt-2005",
      ],
      evidence: [
        "John Paul II’s first pilgrimage to Poland ran from 2 to 10 June 1979 and drew mass public gatherings organised beyond the communist party’s ordinary control.",
        "His Victory Square homily placed Polish history, human dignity and Christian faith inside one public address, strengthening confidence that national life exceeded the state’s official account.",
      ],
      map: { x: 58, y: 33 },
    },
    {
      id: "solidarity-builds-a-public-body",
      actId: "roads-meet",
      order: 11,
      period: "AD 1980–1989",
      place: "Gdańsk and Warsaw",
      title: "Solidarity Builds a Public Body",
      thesis:
        "Solidarity converted Poland’s recovered confidence into elected representation, records and negotiation that survived martial law and forced the party back to a table.",
      body: [
        "A strike began at the Lenin Shipyard in Gdańsk in August 1980 after the dismissal of the crane operator and activist Anna Walentynowicz. Lech Wałęsa entered the yard and joined the leadership, but the decisive enlargement came when workers refused to end with a local wage settlement. Delegates from other enterprises formed an Interfactory Strike Committee. Their Twenty-One Demands, written on boards at the gate, asked first for free trade unions and also for the right to strike, freedom of speech, access to media, release of political prisoners and material reforms.",
        "The Gdańsk Agreement of 31 August recognised the right to form independent unions. Solidarity then grew to roughly ten million members: factory committees elected delegates, regional bodies coordinated action, experts advised negotiators, and newspapers carried decisions across a movement embracing workers, farmers, students and intellectuals. The public confidence visible during the papal pilgrimage had acquired membership lists, meeting procedure, dues, printing presses and representatives. A society the party claimed to embody had built an institution able to speak in its own name.",
        "General Wojciech Jaruzelski imposed martial law on 13 December 1981. Security forces detained thousands, occupied workplaces, killed striking miners at Wujek and drove Solidarity underground. Small presses, couriers, families, foreign broadcasters and parish spaces kept its arguments and organisation alive. Economic failure and persistent opposition eventually forced the government into Round Table talks from February to April 1989. The negotiated election of 4 June gave Solidarity a sweeping victory in every freely contested category. Moral awakening had become organisation; organisation had endured repression; endurance now produced a transfer of political authority.",
      ],
      image: `${imageRoot}/11-solidarity-builds-a-public-body.avif`,
      imageAlt:
        "The Gdańsk shipyard gate, Twenty-One Demands boards, a Solidarity membership card, underground press and Round Table nameplate form one documentary sequence.",
      imagePosition: "55% center",
      mobileImagePosition: "61% center",
      visualLabel:
        "Demand board · union card · underground sheet · Round Table",
      visualTone: "shipyard-solidarity",
      side: "left",
      sourceIds: [
        "unesco-solidarity-demands-2003",
        "garton-ash-polish-revolution-2002",
        "judt-2005",
      ],
      evidence: [
        "The Interfactory Strike Committee’s Twenty-One Demands and the Gdańsk Agreement established an independent union that rapidly became a mass social movement of about ten million members.",
        "Solidarity survived martial law through underground organisation and entered the 1989 Round Table settlement that created partially free elections and broke the party’s political monopoly.",
      ],
      map: { x: 56, y: 28 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "forbidden-word-relay",
        prompt: "Relay the forbidden word",
        accessibleSummary:
          "Four dated records follow independent speech from a 1976 workers’ defence bulletin through the 1979 pilgrimage and the 1980 strike press into the underground networks that survived martial law.",
        initialId: "duplicate-kor-bulletin",
        records: [
          {
            id: "duplicate-kor-bulletin",
            label: "Duplicate the bulletin",
            period: "Warsaw · AD 1976",
            kicker: "Repression receives names and addresses",
            detail:
              "The Committee for the Defence of Workers collects testimony, identifies detained workers and sends aid through an openly signed appeal reproduced by typewriter and duplicator.",
            fields: [
              {
                label: "Carrier",
                value: "Carbon copy and hand-to-hand courier",
              },
              {
                label: "Named network",
                value: "Committee for the Defence of Workers",
              },
              {
                label: "State obstruction",
                value: "Censorship, search and arrest",
              },
            ],
            outcome:
              "A local punishment becomes common knowledge and joins workers to intellectual defenders.",
            points: [
              {
                id: "radom",
                label: "Radom and Ursus",
                detail: "Families and dismissed workers supply testimony.",
                x: 58,
                y: 36,
              },
              {
                id: "warsaw",
                label: "Warsaw",
                detail: "KOR compiles, duplicates and relays the record.",
                x: 58,
                y: 33,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "carry-the-invocation",
            label: "Carry the invocation",
            period: "Poland · June AD 1979",
            kicker: "A gathered crowd becomes the carrier",
            detail:
              "John Paul II’s homilies pass through loudspeakers, parish travel, private recordings, memory and foreign radio far beyond the state broadcast selected for viewers.",
            fields: [
              {
                label: "Carrier",
                value: "Congregation, cassette and parish network",
              },
              {
                label: "Named route",
                value: "Warsaw to Częstochowa and Kraków",
              },
              {
                label: "State obstruction",
                value: "Managed access and restricted coverage",
              },
            ],
            outcome:
              "Millions receive the same language of dignity and know that millions of others heard it beside them.",
            points: [
              {
                id: "warsaw",
                label: "Warsaw",
                detail: "Victory Square gives the words a public scale.",
                x: 58,
                y: 33,
              },
              {
                id: "czestochowa",
                label: "Częstochowa",
                detail: "Pilgrims and parishes extend the route.",
                x: 57,
                y: 37,
              },
              {
                id: "krakow",
                label: "Kraków",
                detail: "The pilgrimage returns through Wojtyła’s former see.",
                x: 58,
                y: 40,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "print-the-demands",
            label: "Print the demands",
            period: "Gdańsk · August AD 1980",
            kicker: "One yard speaks for many workplaces",
            detail:
              "The Twenty-One Demands stand at the shipyard gate while strike bulletins and delegates carry recorded decisions among enterprises in the Interfactory Strike Committee.",
            fields: [
              {
                label: "Carrier",
                value: "Gate board, bulletin and elected delegate",
              },
              {
                label: "Named network",
                value: "Interfactory Strike Committee",
              },
              {
                label: "State obstruction",
                value: "Cut telephones and controlled media",
              },
            ],
            outcome:
              "Separated workplace grievances become a common programme and a negotiating body.",
            points: [
              {
                id: "gdansk-yard",
                label: "Lenin Shipyard",
                detail: "The committee records and negotiates the demands.",
                x: 56,
                y: 28,
              },
              {
                id: "coast-enterprises",
                label: "Coastal enterprises",
                detail: "Delegates carry mandates between workplaces.",
                x: 54,
                y: 27,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "survive-martial-law",
            label: "Survive martial law",
            period: "Poland · AD 1981–1988",
            kicker: "The public layer closes; the relay continues",
            detail:
              "Underground printers reduce editions into packets for trusted couriers; foreign radio repeats reports; parish and family networks shelter people, paper and meetings.",
            fields: [
              { label: "Carrier", value: "Samizdat packet, courier and radio" },
              { label: "Named network", value: "Underground Solidarity" },
              {
                label: "State obstruction",
                value: "Internment, seizure and jamming",
              },
            ],
            outcome:
              "When strikes return in 1988, the government confronts representatives whose authority repression failed to erase.",
            points: [
              {
                id: "gdansk",
                label: "Gdańsk",
                detail: "Workplace networks preserve elected legitimacy.",
                x: 56,
                y: 28,
              },
              {
                id: "warsaw",
                label: "Warsaw",
                detail:
                  "Underground presses and negotiating contacts converge.",
                x: 58,
                y: 33,
              },
              {
                id: "munich",
                label: "Munich",
                detail:
                  "Radio Free Europe returns Polish reports across the frontier.",
                x: 51,
                y: 43,
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
      id: "the-gates-open-across-the-continent",
      actId: "roads-meet",
      order: 12,
      period: "AD 1989",
      place: "Warsaw, Sopron, Berlin and Prague",
      title: "The Gates Open Across the Continent",
      thesis:
        "Eastern Europeans turned negotiated openings, elections, migration and mass assembly into a continental revolution once Moscow withheld the tanks.",
      body: [
        "Poles voted on 4 June 1989 under rules that reserved most Sejm seats for the communist governing bloc while opening the rest of the lower house and the new Senate to competition. Across the two rounds, Solidarity won every freely contested Sejm seat and ninety-nine of the hundred Senate seats. The result stripped the party of public authority even before the constitutional arrangement had caught up. By August, Tadeusz Mazowiecki headed the first non-communist-led government in the Soviet bloc. Poland had moved from strike gate to negotiating table to ballot without waiting for permission from another eastern capital.",
        "Hungary’s reform government dismantled sections of the frontier barrier with Austria and, after the Pan-European Picnic near Sopron exposed the route in August, opened the border to East German refugees in September. Their departure intensified demonstrations at home. Leipzig’s Monday crowds demanded freedom to travel and then political change. On 9 November, Günter Schabowski announced confused new travel rules at an East Berlin press conference. Citizens gathered at the checkpoints; guards without clear orders yielded at Bornholmer Strasse, and the Wall opened under the pressure of people who had arrived expecting the announced right to be honoured.",
        "Prague followed. After police attacked a student march on 17 November, theatres, universities and workplaces carried news and organisation across Czechoslovakia. Civic Forum gathered the opposition around Václav Havel; hundreds of thousands filled Wenceslas Square and shook keys as a demand to unlock public life. The Communist Party surrendered its monopoly, and Havel was elected president in December. Mikhail Gorbachev’s Soviet government, burdened by crisis and abandoning armed enforcement of the bloc, sent no invasion. The nations of the east made use of that opening themselves. Ballot, cut wire, crowded checkpoint and civic forum ended Europe’s division by force.",
      ],
      image: `${imageRoot}/12-the-gates-open-across-the-continent.avif`,
      mobileImage: `${imageRoot}/12-the-gates-open-across-the-continent-mobile.avif`,
      imageAlt:
        "Four dated panels show a Polish ballot, cut Hungarian border wire near Sopron, the opened Bornholmer Strasse checkpoint and keys raised in Wenceslas Square.",
      imagePosition: "54% center",
      mobileImagePosition: "60% center",
      visualLabel: "4 June · 19 August · 9 November · 29 December 1989",
      visualTone: "open-gates",
      side: "right",
      sourceIds: [
        "garton-ash-magic-lantern-2019",
        "eu-pan-european-picnic-2022",
        "chronicle-berlin-wall",
        "judt-2005",
      ],
      evidence: [
        "Solidarity’s June 1989 electoral victory led to a non-communist-led Polish government, while Hungary’s border opening accelerated the East German refugee and protest crisis.",
        "Mass pressure opened Berlin’s checkpoints on 9 November and Czechoslovakia’s Civic Forum negotiated the end of communist monopoly without Soviet military intervention.",
      ],
      map: { x: 54, y: 36 },
    },
  ],
};
