import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/habsburg-europe";

export const habsburgEurope: ChapterDefinition = {
  slug: "habsburg-europe",
  number: "16",
  title: "Habsburg Europe",
  openingTitleLines: ["Habsburg", "Europe"],
  period: "AD 1526–1918",
  claim:
    "The Habsburg monarchy joined old kingdoms, local liberties, imperial service and modern infrastructure without requiring its peoples to become one nation. Its greatest achievement was a common political home capacious enough for several languages, laws and loyalties at once. Total war destroyed that home in 1918.",
  openingClaim:
    "Along the Danube, several crowns learned to share a dynasty, a service and eventually a modern common life without surrendering every law, language or loyalty of their own.",
  hero: {
    image: `${imageRoot}/opening-braided-danube.avif`,
    mobileImage: `${imageRoot}/opening-braided-danube-mobile.avif`,
    imageAlt:
      "At dawn beside Vienna, blue, burgundy, black-gold and green documentary ribbons enter the Danube and braid beneath a bridge carrying crown seals, post routes and rails.",
    imagePosition: "57% center",
    mobileImagePosition: "63% center",
    visualLabel: "The Braided Danube · evidence-led reconstruction",
  },
  theme: {
    id: "danube",
    label: "The Braided Danube",
  },
  openingAction: "Enter the braided current",
  mapLabel:
    "The crowns, frontier roads, district offices, courts, railways and multilingual cities through which Habsburg Europe made a common political home",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Coronation oaths · diet acts · military maps · cadastral surveys · school ordinances · court petitions · railway timetables · parliamentary records",
  acts: [
    {
      id: "three-crowns",
      number: "I",
      label: "Three crowns find one house",
      period: "AD 1526–1740",
      title: "Three Crowns Find One House",
      detail:
        "Succession, frontier defence and dynastic law assemble a composite monarchy in which each kingdom enters by its own constitutional door.",
    },
    {
      id: "monarchy-learns-scale",
      number: "II",
      label: "The monarchy learns scale",
      period: "AD 1740–1815",
      title: "The Monarchy Learns Scale",
      detail:
        "Survey, district office, school, post, disciplined service and diplomacy give inherited lands the practical reach of a European great power.",
    },
    {
      id: "liberty-enters",
      number: "III",
      label: "Liberty enters the Empire",
      period: "AD 1848–1876",
      title: "Liberty Enters the Empire",
      detail:
        "Emancipation, constitutional bargain and public law draw subjects into a modern order whose government can itself be brought before a court.",
    },
    {
      id: "common-home",
      number: "IV",
      label: "The Danube becomes a common home",
      period: "AD 1873–1918",
      title: "The Danube Becomes a Common Home",
      detail:
        "Railways, cities, currency and parliament intensify layered belonging until total war consumes the ordinary bargains that kept it alive.",
    },
  ],
  ending: {
    period: "AD 1918",
    title: "A Common Home Passes Into Memory",
    detail:
      "The monarchy had never asked Prague to become Trieste or Lviv to become Vienna. It asked roads, courts, offices and a crown to hold them in one political house, and generations made that house more habitable than its founders could have imagined. Total war brought hunger, coercion and military defeat through every room. The doors became borders, the sleeping-car routes became international journeys and the common state passed into memory. Its railway arches, universities, civil codes, municipal theatres and many-named streets remained. Long before those rails crossed the Danube, another European network had begun to master distance on a measured page.",
    image: `${imageRoot}/ending-common-home-memory.avif`,
    nextPeriod: "AD 1543–1700",
  },
  returnHash: "habsburg-europe",
  nextHash: "scientific-revolution",
  nextTitle: "The Scientific Revolution",
  nextSlug: "scientific-revolution",
  movements: [
    {
      id: "three-crowns-seek-a-king",
      actId: "three-crowns",
      order: 1,
      period: "AD 1526–1527",
      place: "Mohács, Prague, Pressburg and Vienna",
      title: "Three Crowns Seek a King",
      thesis:
        "A dynastic accident joined Austria, Bohemia and a contested Hungary beneath one ruler without merging their crowns or cancelling their rights.",
      body: [
        "Louis II of Hungary and Bohemia rode from the field of Mohács in August 1526 while his army collapsed before Sultan Süleyman. He drowned in the retreat at the age of twenty, leaving two crowns and no child. His brother-in-law Ferdinand of Habsburg possessed a family compact and the immense advantage of his elder brother Charles V, yet neither kingdom passed to him like a private estate. Bohemian lords elected Ferdinand at Prague after hearing promises to defend their crown and observe its privileges. Austria was his inheritance. Hungary opened a civil contest between two elected kings.",
        "Most Hungarian nobles assembled at Székesfehérvár and chose the Transylvanian magnate John Zápolya. Another group met at Pressburg and elected Ferdinand, invoking earlier succession agreements and the urgent need for Habsburg resources against the Ottomans. Each claimant was crowned, each gathered adherents and each described his title as lawful. The resulting war divided Hungary while the Ottoman occupation of its centre hardened into a fact. Royal Hungary in the north and west adhered to Ferdinand; the eastern kingdom under Zápolya and his heirs became an Ottoman tributary principality; the middle plain came under direct Ottoman rule. The Habsburg monarchy was born beside a broken kingdom, not on an uncontested marriage bed.",
        "Its first strength lay in the incompleteness of the union. The Bohemian crown comprised Bohemia, Moravia, Silesia and the Lusatias, each with estates and offices. Hungary guarded the authority of its diet, counties and coronation oath. The Austrian hereditary lands possessed their own diets and fiscal bargains. Ferdinand had to be accepted in several places, ask for taxation through several bodies and govern with men who spoke for historic communities older than his new monarchy. One dynasty supplied continuity across the tables; three crowns kept their seals upon them. Europe acquired a political house assembled by promises that could be renewed because they had never been made identical.",
      ],
      image: `${imageRoot}/01-three-crowns-seek-a-king.avif`,
      imageAlt:
        "Bohemian, Austrian and Hungarian document tables are joined by election acts and a Danube route, while the Hungarian crown visibly divides between Ferdinand and John Zápolya.",
      imagePosition: "60% center",
      mobileImagePosition: "66% center",
      visualLabel: "Election acts, oaths and separate crown seals",
      visualTone: "three-crown-table",
      side: "left",
      sourceIds: ["ingrao-2019", "evans-1979", "fichtner-2003"],
      evidence: [
        "After Louis II died at Mohács in 1526, the Bohemian estates elected Ferdinand while rival Hungarian assemblies elected John Zápolya and Ferdinand.",
        "Austria, the Bohemian crown and Royal Hungary retained distinct diets, laws, offices and coronation obligations beneath the Habsburg ruler.",
      ],
      map: { x: 55, y: 51 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "three-crowns",
        prompt: "Assemble the three crowns",
        accessibleSummary:
          "Four documentary states join the Austrian inheritance, Bohemian election and contested Hungarian election beneath Ferdinand while their diets, oaths and tax bargains remain separate.",
        initialId: "austrian-inheritance",
        records: [
          {
            id: "austrian-inheritance",
            label: "Receive the Austrian lands",
            period: "Inheritance",
            kicker: "One house, several duchies",
            detail:
              "Ferdinand governs hereditary lands already held by his dynasty, each with provincial estates that negotiate taxation and local administration.",
            fields: [
              { label: "Title", value: "Archduke and territorial lord" },
              { label: "Instrument", value: "Dynastic inheritance" },
              { label: "Retained", value: "Provincial diets and privileges" },
            ],
            outcome:
              "The house has an Austrian base, not a uniform central state.",
          },
          {
            id: "bohemian-election",
            label: "Accept the Bohemian election",
            period: "October AD 1526",
            kicker: "The estates choose",
            detail:
              "Bohemian lords elect Ferdinand after receiving undertakings concerning defence, offices and the lands of their crown.",
            fields: [
              { label: "Title", value: "King of Bohemia" },
              { label: "Instrument", value: "Election and coronation oath" },
              { label: "Retained", value: "Crown lands, diet and offices" },
            ],
            outcome:
              "Bohemia enters through an election whose promises remain politically usable.",
          },
          {
            id: "hungarian-contest",
            label: "Open the Hungarian contest",
            period: "November–December AD 1526",
            kicker: "One crown, two elections",
            detail:
              "Separate noble assemblies elect John Zápolya and Ferdinand, placing the Crown of Saint Stephen at the centre of civil and frontier war.",
            fields: [
              { label: "Title", value: "Rival kings of Hungary" },
              {
                label: "Instrument",
                value: "Election, coronation and compact",
              },
              { label: "Retained", value: "Diet, counties and coronation law" },
            ],
            outcome:
              "Hungary joins the Habsburg story through a disputed kingship rather than quiet succession.",
          },
          {
            id: "composite-monarchy",
            label: "Join without merging",
            period: "AD 1527",
            kicker: "The common work begins",
            detail:
              "Ferdinand carries one dynastic authority among several constitutional tables and must obtain men, taxes and consent through each land’s forms.",
            fields: [
              { label: "Shared", value: "Ruler, court and frontier need" },
              { label: "Separate", value: "Crowns, laws, diets and bargains" },
              { label: "Obligation", value: "Defend every inherited land" },
            ],
            outcome:
              "The monarchy exists because distinct authorities cooperate without becoming one authority.",
          },
        ],
      },
    },
    {
      id: "frontier-becomes-an-institution",
      actId: "three-crowns",
      order: 2,
      period: "AD 1529–1699",
      place: "Vienna, Croatia, Slavonia and Royal Hungary",
      title: "The Frontier Becomes an Institution",
      thesis:
        "Ottoman pressure made defence a permanent common service sustained by court, estates, fortified towns and soldier-settler communities.",
      body: [
        "Süleyman reached Vienna in 1529 after bringing Buda under his influence and driving Ferdinand’s position back toward the Austrian frontier. Rain, distance, damaged roads and the resistance of the garrison denied the Ottoman army a quick success; the siege ended before winter. The danger did not end with the withdrawal. Central Hungary became an Ottoman province after 1541, Buda an Ottoman capital, and the border ran for hundreds of miles through broken fortresses, rivers and wooded hills. Vienna could no longer treat war as a campaign summoned only when a ruler chose. The frontier became a standing institution.",
        "The Aulic War Council coordinated from Vienna, while captains, engineers and paymasters worked through fortress districts in Royal Hungary and the Croatian-Slavonian lands. Graz and the Inner Austrian estates financed stretches of the Croatian defence; Hungarian and Bohemian taxes supported war far from their own boundaries. Magazines stored grain and powder, watch posts exchanged signals and surveyors recut medieval walls for artillery. Along the Military Frontier, Orthodox and Catholic settlers received land and defined privileges in return for armed service. Uskoks, Grenzer, Hungarian hajdús, Croatian nobles, German officers and local towns entered the same defensive system without losing their separate communities.",
        "The arrangement was demanding and often harsh. Soldiers waited for pay, villagers supplied carts and food, commanders quarrelled with diets, and border raiding scarred communities on both sides. Its achievement rested in endurance rather than administrative neatness. A court without enough revenue drew resources from several kingdoms; estates defended liberties while voting taxes for a common danger; migrants made farms under military obligation; engineers translated Italian fortification knowledge into Danubian ground. For a century and a half, one crownland repeatedly sustained another. The monarchy learned its first common language in lists of powder, bridge timber, garrison wages and grain sent toward a frontier none of its peoples could have held alone.",
      ],
      image: `${imageRoot}/02-frontier-becomes-an-institution.avif`,
      imageAlt:
        "A long Danube frontier section joins bastioned fortresses, grain magazines, patrol roads and tax routes arriving from Austrian, Bohemian, Hungarian and Croatian lands.",
      imagePosition: "63% center",
      mobileImagePosition: "70% center",
      visualLabel: "Military Frontier plans and supply records",
      visualTone: "frontier-service",
      side: "right",
      sourceIds: [
        "ingrao-2019",
        "hochedlinger-2003",
        "agoston-2021",
        "rothenberg-1960",
      ],
      evidence: [
        "After the 1529 siege and the Ottoman occupation of central Hungary, the Habsburg lands developed a permanent fortified border coordinated through war councils, captaincies and provincial taxation.",
        "The Military Frontier settled armed communities under special obligations and privileges, joining local service to resources supplied from several Habsburg lands.",
      ],
      map: { x: 60, y: 61 },
    },
    {
      id: "danube-opens-eastward",
      actId: "three-crowns",
      order: 3,
      period: "AD 1683–1718",
      place: "Vienna, Buda, Karlowitz and the middle Danube",
      title: "The Danube Opens Eastward",
      thesis:
        "The relief of Vienna and a sustained allied war carried the frontier down the Danube, transforming the monarchy’s territory and European weight.",
      body: [
        "An Ottoman army encircled Vienna again in July 1683. Count Ernst Rüdiger von Starhemberg held a damaged, crowded city while miners fought beneath the bastions and couriers sought the allied army gathering beyond the hills. On 12 September a coalition descended from the Vienna Woods. Imperial forces and troops from Bavaria, Saxony and other German lands fought beside the army of the Polish-Lithuanian Commonwealth under King John III Sobieski. The attack broke the Ottoman camp and lifted the siege. Vienna had survived through an alliance wider than the monarchy, and the victory opened a road no Habsburg ruler had previously been able to hold.",
        "The Holy League continued the war instead of stopping at the rescued walls. Buda fell in 1686 after a destructive siege, ending nearly a century and a half of Ottoman government there. Imperial armies pushed through Hungary and Transylvania while the Hungarian kingdom endured occupation, requisition and the replacement of one ruling order by another. The treaties of Karlowitz in 1699 confirmed Habsburg possession of most of Hungary and Transylvania; Passarowitz in 1718 moved the line farther for a time. Sobieski’s Polish standard, Hungarian regiments, imperial officers, Serbian militia, Croatian border troops and German contingents had all entered the campaigns by different roads.",
        "Recovery changed the scale of the monarchy. The Danube carried officials, merchants, settlers and military supplies toward Buda, Peterwardein and Belgrade. Crown estates surveyed reclaimed lands, noble titles were reassigned, counties returned, new bishoprics and towns took form, and populations moved into districts emptied or rearranged by war. Confessional and fiscal pressure accompanied reconstruction; liberation for one institution could mean dispossession for another. The larger result endured beyond each grievance. Austria, Bohemia, Hungary, Croatia and the frontier now occupied a continuous strategic space. A dynasty that had survived by borrowing strength among separate lands possessed the depth, population and river corridor of a European great power.",
      ],
      image: `${imageRoot}/03-danube-opens-eastward.avif`,
      imageAlt:
        "A dated river map carries distinct Polish and imperial relief routes into Vienna, then follows campaigns through Buda toward the treaty tables at Karlowitz and Passarowitz.",
      imagePosition: "59% center",
      mobileImagePosition: "66% center",
      visualLabel: "Campaign routes and treaty settlements",
      visualTone: "river-recovery",
      side: "left",
      sourceIds: ["ingrao-2019", "hochedlinger-2003", "agoston-2021"],
      evidence: [
        "John III Sobieski commanded the Polish-Lithuanian army within the allied force that relieved Vienna on 12 September 1683.",
        "The capture of Buda in 1686 and the settlements of Karlowitz in 1699 and Passarowitz in 1718 shifted most of Hungary and additional Danubian lands from Ottoman to Habsburg rule.",
      ],
      map: { x: 59, y: 54 },
    },
    {
      id: "succession-becomes-common-law",
      actId: "three-crowns",
      order: 4,
      period: "AD 1713–1740",
      place: "Vienna and the crownland diets",
      title: "Succession Becomes Common Law",
      thesis:
        "The Pragmatic Sanction turned the succession of one daughter into a promise, ratified by distinct lands, that their monarchy would possess a common future.",
      body: [
        "Charles VI had no surviving son. The laws and customs of his lands did not deliver one automatic answer to that fact, and the Habsburg family compact first favoured the daughters of his elder brother. In 1713 Charles announced a new order. The Habsburg hereditary lands were to remain indivisible, and his own daughters could inherit when the male line failed. The Pragmatic Sanction began as a dynastic declaration inside a court that feared partition. It became constitutional only as the monarchy’s separate political bodies received it through the procedures by which they recognised a ruler.",
        "The Austrian and Bohemian lands accepted the settlement in their own assemblies. The Hungarian Diet did so in 1723 through paired laws that recognised female succession and the inseparable possession of the lands ruled by the Habsburg house, while reaffirming Hungary’s constitution and the king’s obligations. Croatia, Transylvania and other territories entered through their own instruments. Seals accumulated beneath one proposition, not beneath one new code. Charles then spent years securing recognition from European powers through treaties and concessions, making the future of the monarchy an object of continental diplomacy before Maria Theresa had inherited it.",
        "The signatures could not prevent the War of the Austrian Succession when Charles died in 1740. Prussia invaded Silesia, Bavaria challenged the inheritance and foreign guarantees proved conditional. They did determine what Maria Theresa could claim and what her peoples had already undertaken. Hungarian nobles could answer her appeal as members of a kingdom that had accepted her lawful title, not as subjects recoloured on a Viennese map. The common future survived the test even as rich Silesia was lost. A set of crowns once joined by one fortunate marriage had learned to describe its own continuity: indivisible in succession, plural in law, and bound by promises made land after land.",
      ],
      image: `${imageRoot}/04-succession-becomes-common-law.avif`,
      imageAlt:
        "The Pragmatic Sanction lies beneath a fan of Austrian, Bohemian, Hungarian, Croatian and Transylvanian ratification tabs arriving with distinct seals.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Pragmatic Sanction and crownland ratifications",
      visualTone: "ratified-succession",
      side: "right",
      sourceIds: [
        "ingrao-2019",
        "fichtner-2003",
        "austrian-state-archives-pragmatic-sanction",
      ],
      evidence: [
        "Charles VI’s Pragmatic Sanction declared the Habsburg lands indivisible and established female succession in default of a male heir.",
        "The several lands accepted the succession through separate constitutional forms, including the Hungarian Diet’s laws of 1723, which joined recognition to Hungary’s own rights and obligations.",
      ],
      map: { x: 55, y: 49 },
    },
    {
      id: "maria-theresa-counts-the-realm",
      actId: "monarchy-learns-scale",
      order: 5,
      period: "AD 1740–1765",
      place: "Vienna, Prague and the Austrian-Bohemian lands",
      title: "Maria Theresa Counts the Realm",
      thesis:
        "Military crisis taught the monarchy to know its land, revenue and recruits through permanent offices staffed for service rather than emergency.",
      body: [
        "Maria Theresa inherited at twenty-three and immediately fought to keep what the Pragmatic Sanction had promised. Prussia seized Silesia, French and Bavarian forces entered Bohemia, and the treasury revealed how poorly the centre understood the resources beneath its titles. Provincial estates assessed taxes through old quotas, military accounts arrived late and offices divided responsibility along lines no campaign would wait to untangle. The queen preserved her crowns, lost most of Silesia and emerged from the war with an exacting conclusion: a great power required continuous knowledge of the lands on which its army depended.",
        "Friedrich Wilhelm von Haugwitz’s reforms joined Austrian and Bohemian fiscal and administrative business more closely. The crown negotiated longer tax grants, reached beyond estate committees through district offices and began to count land and liability with greater regularity. Cadastral surveys measured fields whose value had previously been stated through inherited exemptions and local convention. The army acquired standing regiments, a clearer recruitment system and institutions for training officers. Noble privilege did not disappear, Hungary retained its separate administration, and reform advanced differently across the monarchy. The achievement was a dependable working capacity where a stack of temporary bargains had once stood.",
        "Clerks made the change durable. A district officer compared a village return with a cadastral sheet; an accountant placed revenue beside expenditure; a commissary connected a regiment’s men to uniforms, bread and horses; a provincial office answered Vienna in a regular form. Service offered educated nobles and commoners a vocation whose horizon extended beyond one estate or town. Maria Theresa ruled personally and guarded dynastic authority, while her boards supplied a more impersonal continuity. The monarchy began to see itself through trained hands, numbered districts and files that could outlive the official who opened them. Scale entered government as the patient discipline of making distant facts answer one another.",
      ],
      image: `${imageRoot}/05-maria-theresa-counts-the-realm.avif`,
      imageAlt:
        "A walnut reform desk brings a cadastral grid, district report, tax column and regimental return together over an Austrian-Bohemian crownland map.",
      imagePosition: "61% center",
      mobileImagePosition: "67% center",
      visualLabel: "Cadastre, district return and military account",
      visualTone: "reform-desk",
      side: "left",
      sourceIds: ["ingrao-2019", "hochedlinger-2003", "judson-2016"],
      evidence: [
        "The loss of Silesia and the War of the Austrian Succession drove Maria Theresa’s government to reform taxation, military organisation and central administration, especially in the Austrian and Bohemian lands.",
        "District offices, cadastral work and longer fiscal grants increased the crown’s knowledge and capacity while Hungary and other lands retained important constitutional distinctions.",
      ],
      map: { x: 54, y: 47 },
    },
    {
      id: "school-road-post",
      actId: "monarchy-learns-scale",
      order: 6,
      period: "AD 1749–1774",
      place: "Vienna, provincial towns and village districts",
      title: "School, Road, Post",
      thesis:
        "Roads, regular post, district offices and elementary schools made the reforming monarchy present in ordinary journeys, letters and learned skills.",
      body: [
        "A decree reached the countryside only if a road carried it, a postmaster accounted for it and an official could read the answer. Maria Theresa’s monarchy built capacity through that chain. Existing postal routes were regularised and extended; paved roads and bridges shortened journeys between capitals, district towns and markets; printed schedules made departure less dependent on private favour. The post carried official packets beside merchants’ letters and family news. A wax seal impressed in Vienna could arrive at a provincial desk with its route, charge and custody recorded at each stage.",
        "District officers turned movement into administration. They inspected tax rolls, recruitment, public order and local compliance, then translated particular circumstances into reports that a provincial board could compare. Surveys placed roads, plots and villages on common sheets. The office did not erase the crownland. Bohemian forms, Austrian provincial institutions and local seigneurial rights remained visible beneath the new columns, and the Hungarian kingdom followed a separate constitutional course. Reform worked by laying common practices across jurisdictions sturdy enough to resist any pretense that the whole monarchy was one province.",
        "The General School Ordinance of 1774 gave the Austrian and Bohemian hereditary lands a connected scheme of elementary instruction, teacher preparation and graded schools. Attendance and provision varied widely, classrooms could be poor and confessional supervision remained strong. The ambition was momentous: the state accepted responsibility for reproducing the literacy and numeracy its service required. A village child sounding out a primer, a postilion changing horses and a district clerk ruling a register participated in the same enlargement of reach. Government no longer appeared only when a tax was demanded or troops passed. It arrived as a road maintained, a letter delivered, a school expected and an office obliged to answer.",
      ],
      image: `${imageRoot}/06-school-road-post.avif`,
      imageAlt:
        "A sealed postal packet travels along a measured road through a district office into a village school, acquiring a milestone mark, route stamp, survey grid and primer.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "Postal route, district register and school ordinance",
      visualTone: "service-route",
      side: "right",
      sourceIds: ["judson-2016", "melton-1988", "ingrao-2019"],
      evidence: [
        "Eighteenth-century Habsburg reforms extended regular postal, road, survey and district administration across the Austrian and Bohemian hereditary lands while preserving significant local and crownland law.",
        "Maria Theresa’s General School Ordinance of 1774 joined teacher training, graded curricula and inspected classrooms in a state-directed elementary school structure.",
      ],
      map: { x: 51, y: 46 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "realm-service",
        prompt: "Put the realm into service",
        accessibleSummary:
          "Survey, district office, post and school are applied in sequence to a Bohemian district, extending common administrative reach while local law and language remain visible on every record.",
        initialId: "survey-land",
        records: [
          {
            id: "survey-land",
            label: "Survey the land",
            period: "Knowledge before instruction",
            kicker: "The village enters a measured sheet",
            detail:
              "Surveyors join fields, roads, mills and tax liabilities to named settlements on a cadastral map that can be compared beyond one estate.",
            fields: [
              { label: "Instrument", value: "Cadastre and route survey" },
              { label: "Adds", value: "Comparable land and distance" },
              { label: "Retains", value: "Local parcels and obligations" },
            ],
            outcome:
              "The crownland becomes more legible without becoming featureless.",
          },
          {
            id: "open-district-office",
            label: "Open the district office",
            period: "A permanent local address",
            kicker: "A report can receive an answer",
            detail:
              "A salaried officer gathers returns, inspects implementation and sends provincial circumstances upward in a regular documentary form.",
            fields: [
              { label: "Instrument", value: "Register, docket and inspection" },
              { label: "Adds", value: "Continuity between visits" },
              { label: "Retains", value: "Crownland law and local names" },
            ],
            outcome:
              "Government acquires a responsible office between village and capital.",
          },
          {
            id: "regularise-post",
            label: "Regularise the post",
            period: "A dependable route",
            kicker: "Distance acquires a schedule",
            detail:
              "Post stations, charges and custody marks move official and private letters along the same maintained road.",
            fields: [
              { label: "Instrument", value: "Packet, post road and timetable" },
              { label: "Adds", value: "Predictable communication" },
              { label: "Retains", value: "Provincial and municipal addresses" },
            ],
            outcome:
              "The centre can reach the district, and the district can answer the centre.",
          },
          {
            id: "establish-school",
            label: "Establish the school",
            period: "The service reproduces its skills",
            kicker: "Reading enters public provision",
            detail:
              "A trained teacher, graded primer and supervised classroom give children the literacy and numeracy required by worship, trade and administration.",
            fields: [
              { label: "Instrument", value: "Ordinance, teacher and primer" },
              { label: "Adds", value: "Reproducible public skill" },
              { label: "Retains", value: "Local language and confession" },
            ],
            outcome:
              "Reach becomes durable because the next generation can read and carry it.",
          },
        ],
      },
    },
    {
      id: "joseph-makes-service-a-vocation",
      actId: "monarchy-learns-scale",
      order: 7,
      period: "AD 1780–1790",
      place: "Vienna and the hereditary lands",
      title: "Joseph Makes Service a Vocation",
      thesis:
        "Joseph II pressed toleration, legal equality and useful administration into a demanding ideal: government existed to work for all the ruler’s subjects.",
      body: [
        "Joseph II began work before dawn and expected his monarchy to keep the same hours. He travelled without a grand court, questioned provincial officials, read petitions and covered memoranda with decisions. The austere performance expressed a political creed. Rank inherited from a family could no longer justify an idle office; privilege had to answer usefulness; subjects who cultivated land, raised children or practised a permitted faith strengthened the state when law allowed them to work. Government became a vocation measured in files completed, abuses corrected and institutions made to serve a public purpose.",
        "The Toleration Patents of 1781 gave defined Protestant communities and the Orthodox wider freedom of private worship and access to trades, property and education, while further measures eased restrictions on Jewish life. The serfdom patent removed hereditary personal subjection in the Austrian and Bohemian lands, permitting peasants to marry, move and learn trades without a lord’s consent, though labour dues and manorial burdens survived. Joseph reorganised parishes, hospitals and poor relief, redirected contemplative monastic wealth and sought more uniform courts and administration. Each measure made the individual subject more visible to the crown across the corporate body that had once spoken for him.",
        "Speed exposed the limits of enlightened service. Joseph avoided coronation in Hungary, governed there by decree and attempted to replace established languages and procedures with German administration. Resistance gathered from nobles, counties, clergy and provinces that saw useful reform arriving as violated law. Revolt in the Austrian Netherlands and crisis in Hungary forced him to revoke much of the programme before his death; toleration and the end of personal serfdom remained. His uniform schemes receded while his ethic entered the service. An official should inspect, reason, record and accept responsibility for every subject reached by his seal. The monarchy retained that demanding standard after it recovered the older art of bargaining.",
      ],
      image: `${imageRoot}/07-joseph-makes-service-a-vocation.avif`,
      imageAlt:
        "Joseph II’s working desk at first light carries the Toleration Patent, a peasant petition, an inspection schedule and rapidly ordered crownland dockets.",
      imagePosition: "62% center",
      mobileImagePosition: "69% center",
      visualLabel: "Patent, petition and service docket",
      visualTone: "useful-government",
      side: "left",
      sourceIds: ["ingrao-2019", "fichtner-2003", "judson-2016"],
      evidence: [
        "Joseph II’s toleration measures widened civil and religious possibilities for Protestant, Orthodox and Jewish communities within Habsburg law.",
        "The 1781 serfdom reforms ended hereditary personal dependence in the Austrian and Bohemian lands, allowing peasants to marry, move and learn trades without a lord’s consent.",
      ],
      map: { x: 53, y: 50 },
    },
    {
      id: "vienna-balances-europe",
      actId: "monarchy-learns-scale",
      order: 8,
      period: "AD 1814–1815",
      place: "Congress of Vienna",
      title: "Vienna Balances Europe",
      thesis:
        "Habsburg diplomacy helped turn victory over Napoleon into a negotiated continental balance whose powers learned to consult before one could dominate the rest.",
      body: [
        "Vienna filled with sovereigns, ministers, secretaries and petitioners after two decades of revolutionary and Napoleonic war. Maps covered palace tables while printers issued invitations and police registered strangers. Emperor Francis hosted; Prince Klemens von Metternich directed Austrian diplomacy; Castlereagh represented Britain, Alexander I spoke with the weight of Russian armies, Hardenberg defended Prussian claims and Talleyrand returned defeated France to the circle of great powers. The entertainments supplied meeting places. The settlement emerged from memoranda, private conferences, shifting combinations and the recognition that no victorious power could safely receive everything it demanded.",
        "Poland and Saxony nearly divided the allies. Austria joined Britain and France to resist a Russian- and Prussian-led solution, demonstrating the balance it hoped to preserve. The final act redrew borders, established a Kingdom of the Netherlands, recognised Swiss neutrality and created a German Confederation whose presidency belonged to Austria. The Habsburg monarchy relinquished the distant Austrian Netherlands and consolidated its central European and Italian position. Restored rulers gained authority, while constitutional and national hopes found little general satisfaction. Diplomacy served order before liberty.",
        "The larger achievement lay in procedure. The principal states accepted that a European settlement required reciprocal restraint, agreed frontiers and continuing consultation. Congresses at Aix-la-Chapelle, Troppau, Laibach and Verona carried that practice into the following years, sometimes defending peace and sometimes suppressing revolution. Europe suffered wars after 1815, and the concert repeatedly divided. No general conqueror again gathered the continent beneath one command. Vienna had made negotiation among great powers a regular instrument of security. A monarchy built by bringing separate claims to one table now offered that constitutional instinct to Europe: remain distinct, recognise a common order and bargain before victory destroys the room in which all must live.",
      ],
      image: `${imageRoot}/08-vienna-balances-europe.avif`,
      imageAlt:
        "Credentials and boundary ribbons from Austria, Britain, Russia, Prussia and France settle around a circular diplomatic table laid over an 1815 map of Europe.",
      imagePosition: "60% center",
      mobileImagePosition: "66% center",
      visualLabel: "Congress credentials and negotiated map",
      visualTone: "concert-table",
      side: "right",
      sourceIds: ["jarrett-2013", "vick-2014", "ingrao-2019"],
      evidence: [
        "The Congress of Vienna restored a European balance through multilateral bargaining among the great powers, with France re-entering negotiation before the settlement was complete.",
        "The Final Act reorganised central Europe and created the German Confederation under Austrian presidency, while later congresses extended consultation into a continuing diplomatic practice.",
      ],
      map: { x: 51, y: 45 },
    },
    {
      id: "revolution-frees-the-field",
      actId: "liberty-enters",
      order: 9,
      period: "AD 1848–1849",
      place: "Vienna, Prague, Budapest and the crownlands",
      title: "Revolution Frees the Field",
      thesis:
        "Revolution failed to displace the dynasty, yet it abolished the manorial order and carried millions into the monarchy’s future as freer landholders and citizens.",
      body: [
        "News from Paris reached a monarchy alive with harvest failures, industrial distress, educated petitioners and national programmes. Crowds in Vienna demanded a constitution in March 1848 and forced Metternich from office. Prague formed a national committee and hosted a Slav congress. At Pressburg, the Hungarian Diet passed the April Laws under Lajos Kossuth’s driving rhetoric, creating responsible government, representative institutions and civil reform within the lands of the Hungarian crown. Imperial promises summoned an elected Reichstag. Censorship fell, newspapers multiplied and political life occupied streets, assembly halls and village taverns in languages the old court had rarely heard together.",
        "The revolutions divided over the shape of freedom. German liberals sought constitutional union, Czech leaders defended Bohemia against absorption, Hungary asserted a unified political nation, and Croatian, Slovak, Romanian and Serbian movements demanded recognition within lands Budapest claimed to govern. General Windisch-Grätz bombarded insurgent Prague and later Vienna. Ban Josip Jelačić led Croatian forces against the Hungarian government. The young Francis Joseph replaced Ferdinand in December. Imperial armies recovered most of Hungary, and Russian intervention in 1849 completed the revolution’s military defeat. Executions, imprisonment and neo-absolutist government followed victory.",
        "One transformation survived every bayonet. The Austrian Reichstag abolished robot labour and other feudal burdens with compensation arrangements; Hungarian legislation also ended the legal core of serfdom. Peasant households became owners freed from a lord’s personal jurisdiction across much of the monarchy. Land registers recorded the change plot by plot, translating revolutionary principle into an enduring rural settlement. The crown had defeated assemblies and national armies, though it could not restore the social world from which those challenges had risen. Millions who entered 1848 owing labour and obedience through a manor entered the next reign as subjects of a state and holders of civil property. Liberty first secured its ground in the field.",
      ],
      image: `${imageRoot}/09-revolution-frees-the-field.avif`,
      imageAlt:
        "Broadsheets from Vienna, Prague and Budapest open onto a cadastral field where robot labour and manorial jurisdiction are struck from a land register.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "Revolutionary broadsheets and emancipation register",
      visualTone: "freed-field",
      side: "left",
      sourceIds: ["judson-2016", "sked-2001", "beller-2018"],
      evidence: [
        "The revolutions of 1848 created representative governments and mass political mobilisation across Vienna, Prague, Hungary and other crownlands before imperial and Russian forces restored dynastic rule.",
        "Legislation in the Austrian and Hungarian lands abolished the central legal burdens of the manorial order, and this emancipation survived the revolutions’ defeat.",
      ],
      map: { x: 56, y: 50 },
    },
    {
      id: "two-governments-share-a-crown",
      actId: "liberty-enters",
      order: 10,
      period: "AD 1867–1868",
      place: "Vienna, Budapest and Zagreb",
      title: "Two Governments Share a Crown",
      thesis:
        "The Compromise divided domestic government between Austria and Hungary while preserving one ruler, three common ministries and another negotiated place for Croatia.",
      body: [
        "Francis Joseph’s army defeated revolution in 1849 and then lost the diplomatic foundations on which central rule depended. Defeat by France and Piedmont in 1859 cost Lombardy; defeat by Prussia at Königgrätz in 1866 removed Austria from leadership in Germany. Hungarian politicians, led in negotiation by Ferenc Deák, had refused to treat the suspended laws of their kingdom as dead. The emperor could impose administration and collect some taxes, though he could not obtain the settled legitimacy, credit and recruitment that a great power needed. A dynasty accustomed to survival through constitutional bargains returned to that art.",
        "The Austro-Hungarian Compromise of 1867 restored a responsible Hungarian ministry and parliament. Francis Joseph was crowned king at Buda in the form required by the Hungarian constitution. The lands represented in the Vienna Reichsrat received their own ministry and, through the December Constitution, a parliamentary order. Foreign affairs, war and the finance required for those common responsibilities remained under three shared ministries accountable through parallel delegations. A customs and commercial union linked the two halves for terms subject to renegotiation, and agreed quotas divided common expenditure. The ruler joined two cabinets and two legislatures without pretending they had become one.",
        "The settlement gave Hungarian constitutional statehood a durable place and opened broad parliamentary life in the Austrian half. It also privileged German-Austrian and Magyar leadership over demands for an equal Czech or South Slav arrangement. The Croatian-Hungarian Settlement of 1868 answered one such demand with another layer: Croatia-Slavonia retained its Sabor, territorial administration and recognised political nation under the Crown of Saint Stephen while sharing specified affairs with Hungary. Conflict remained inside every formula, and formulas could be revised. The monarchy’s characteristic achievement was visible in brass conduits between separate desks. Difference did not always receive equality; it received institutions in which further claims could be framed, resisted and sometimes turned into another agreement.",
      ],
      image: `${imageRoot}/10-two-governments-share-a-crown.avif`,
      imageAlt:
        "Separate cabinet tables in Vienna and Budapest share three brass conduits for foreign affairs, war and common finance, while a Croatian-Slavonian constitutional folio opens beside them.",
      imagePosition: "61% center",
      mobileImagePosition: "68% center",
      visualLabel: "The Dual Monarchy’s constitutional desks",
      visualTone: "dual-bargain",
      side: "right",
      sourceIds: [
        "judson-2016",
        "sked-2001",
        "beller-2018",
        "austrian-parliament-1848-1918",
      ],
      evidence: [
        "The 1867 Compromise created separate Austrian and Hungarian governments and legislatures under one ruler, with foreign affairs, war and shared finance administered in common.",
        "The Croatian-Hungarian Settlement of 1868 preserved a Croatian-Slavonian parliament and territorial administration while defining affairs shared with Hungary.",
      ],
      map: { x: 57, y: 53 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "dual-monarchy",
        prompt: "Balance the Dual Monarchy",
        accessibleSummary:
          "Five constitutional layers place the ruler, Austrian and Hungarian governments, three common ministries and Croatia-Slavonia within a system of divided domestic power and negotiated common business.",
        initialId: "common-ruler",
        records: [
          {
            id: "common-ruler",
            label: "Seat the common ruler",
            period: "AD 1867",
            kicker: "Two constitutional titles",
            detail:
              "Francis Joseph acts as Emperor of Austria and apostolic King of Hungary, crowned and advised through each half’s constitutional form.",
            fields: [
              { label: "Vienna", value: "Emperor and Austrian ministry" },
              { label: "Budapest", value: "King and Hungarian ministry" },
              {
                label: "Joins",
                value: "Dynasty and sanctioned common affairs",
              },
            ],
            outcome:
              "One person occupies two constitutional offices rather than one undivided throne.",
          },
          {
            id: "austrian-government",
            label: "Open the Austrian parliament",
            period: "The lands represented in the Reichsrat",
            kicker: "Crownlands enter a constitutional half",
            detail:
              "An Austrian cabinet governs through imperial law and a Reichsrat whose deputies come from Bohemia, Galicia, Dalmatia, the Alpine lands and the Adriatic coast.",
            fields: [
              { label: "Domestic", value: "Austrian ministry and Reichsrat" },
              { label: "Revenue", value: "Austrian budget and taxation" },
              { label: "Retains", value: "Crownland diets and administration" },
            ],
            outcome:
              "The western half shares public law while its crownlands keep political form.",
          },
          {
            id: "hungarian-government",
            label: "Restore the Hungarian government",
            period: "The lands of the Crown of Saint Stephen",
            kicker: "Historic statehood returns",
            detail:
              "A Hungarian cabinet answers to the parliament at Budapest for domestic policy, law, taxation and most administration within its half.",
            fields: [
              { label: "Domestic", value: "Hungarian ministry and parliament" },
              { label: "Revenue", value: "Hungarian budget and taxation" },
              {
                label: "Retains",
                value: "Hungarian constitutional continuity",
              },
            ],
            outcome: "The kingdom governs itself inside the dynastic union.",
          },
          {
            id: "common-ministries",
            label: "Route the common affairs",
            period: "The union between the halves",
            kicker: "Three conduits cross the division",
            detail:
              "Foreign affairs, the armed forces and the finance of their common costs pass through joint ministries supervised by parallel delegations.",
            fields: [
              { label: "Common", value: "Foreign affairs and war" },
              { label: "Common finance", value: "Only shared expenditure" },
              {
                label: "Contribution",
                value: "Negotiated quotas from both halves",
              },
            ],
            outcome:
              "Austria-Hungary acts abroad as one great power while governing at home through two states.",
          },
          {
            id: "croatian-settlement",
            label: "Add the Croatian layer",
            period: "AD 1868",
            kicker: "Another agreement fits inside the first",
            detail:
              "Croatia-Slavonia keeps its Sabor, administration and official territorial identity while specified financial and economic affairs remain shared with Hungary.",
            fields: [
              { label: "Own", value: "Sabor and autonomous departments" },
              { label: "Shared", value: "Defined Hungarian-Croatian affairs" },
              {
                label: "Unsettled",
                value: "Authority, language and representation",
              },
            ],
            outcome:
              "The dual structure proves capable of holding a further constitutional compact inside it.",
          },
        ],
      },
    },
    {
      id: "rights-enter-the-court",
      actId: "liberty-enters",
      order: 11,
      period: "AD 1867–1876",
      place: "Vienna and the Austrian crownlands",
      title: "Rights Enter the Court",
      thesis:
        "The December Constitution placed civil rights, national equality and judicial review inside Austrian public law, giving subjects forums in which government itself had to answer.",
      body: [
        "The December Constitution of 1867 gave the Austrian half more than a parliament. Its Basic Law on the General Rights of Citizens guaranteed equality before the law, personal liberty, property, conscience, expression, association and petition within the terms of public legislation. Article 19 declared the equality of the national groups of the state and recognised each people’s right to preserve and cultivate its nationality and language. The promise entered a monarchy whose schools, courts and offices worked in German, Czech, Polish, Ruthenian, Slovene, Italian, Croatian, Romanian and other languages. Every administrative choice could now touch a constitutional word.",
        "Institutions gave the words a place to work. The Imperial Court, operating from 1869, heard complaints that constitutionally guaranteed political rights had been violated and decided conflicts of competence among public authorities. The Administrative Court began work in 1876 and reviewed whether officials had acted lawfully. Ordinary courts possessed their own independence under the constitutional laws. A municipality challenging a provincial order, an association denied recognition or a newspaper contesting official action could turn grievance into a file, identify a legal rule and require the state to defend its act before judges.",
        "Rights did not settle the national question. Article 19 generated disputes over school languages, official communication and what equality required in a mixed district; governments sometimes suspended rights under emergency provisions, and judgments could protect procedure without satisfying a political movement. The court record nonetheless changed the relation between subject and office. Ruthenian petitioners in Galicia, Czech municipalities in Bohemia, Slovene associations in Carniola and Italian speakers on the coast could argue from the same printed law while demanding different outcomes. The monarchy offered no single national ownership of the state. It offered a legal space in which several peoples could address power as citizens and hear power answer in reasons.",
      ],
      image: `${imageRoot}/11-rights-enter-the-court.avif`,
      imageAlt:
        "A multilingual municipal petition rises through crownland offices to Vienna, where articles from the 1867 Basic Law and the seals of the Imperial and Administrative Courts become visible.",
      imagePosition: "59% center",
      mobileImagePosition: "65% center",
      visualLabel: "Constitutional article, petition and court seal",
      visualTone: "rights-petition",
      side: "left",
      sourceIds: [
        "judson-2016",
        "beller-2018",
        "austrian-parliament-1848-1918",
      ],
      evidence: [
        "The Austrian Basic Law of 1867 guaranteed civil rights and declared the equality of national groups, including their rights to preserve language and nationality.",
        "The Imperial Court and the Administrative Court supplied forums for rights claims, competence disputes and review of the legality of administrative action.",
      ],
      map: { x: 54, y: 48 },
    },
    {
      id: "rails-braid-the-crownlands",
      actId: "common-home",
      order: 12,
      period: "AD 1873–1914",
      place: "Prague, Vienna, Budapest, Trieste, Zagreb and Lviv",
      title: "Rails Braid the Crownlands",
      thesis:
        "Rail, post, telegraph, customs and currency made several political homes inhabit one practical geography in which distance could be governed by timetable.",
      body: [
        "The Semmering Railway had carried trains over the Alps from 1854, joining engineered viaducts and tunnels to a line that reached Trieste. By the last decades of the century, main routes and dense branches connected Prague’s factories, Galicia’s oil fields, Budapest’s grain markets, Croatian towns and the Adriatic port with Vienna and one another. State companies, private capital and later nationalisation built the network in uneven stages. A provincial station received the same disciplined objects as a capital terminus: clock, signal, waybill, tariff, telegraph and a timetable that made one departure answer a connection hundreds of kilometres away.",
        "The journey crossed visible differences. Praha and Prag, Lwów, Lemberg and Lviv, Triest and Trieste, Zagreb and Agram named places according to speaker, administration and political claim. Local diets, municipal authorities and the Austrian-Hungarian boundary retained force. Shared technical standards and coordinated commercial arrangements let a wagon continue. The customs union joined the two halves through regularly renewed agreements; the krone currency introduced in 1892 gave travellers familiar value; postal and telegraph services exchanged messages across the whole monarchy; common consular and military documents reached farther still. Cooperation accumulated in the ticket wallet without demanding one national label from its holder.",
        "A commercial clerk could leave Prague in the evening and enter Vienna beneath the same currency; a Galician student could cross the Carpathians toward Budapest; a Croatian recruit and an Italian-speaking merchant could share a carriage north from the Adriatic. Sleeper cars turned imperial distance into hours marked by lamps, dining stops and conductors’ punches. Every route depended on clerks who reconciled accounts, engineers who maintained gauges and bridges, and authorities willing to recognise one another’s paper. The monarchy became most persuasive when it worked quietly. A letter arrived, a transfer cleared, a court appeal travelled and a train met its connection while several languages remained audible on the platform.",
      ],
      image: `${imageRoot}/12-rails-braid-the-crownlands.avif`,
      mobileImage: `${imageRoot}/12-rails-braid-the-crownlands-mobile.avif`,
      imageAlt:
        "A period rail-and-river map braids Prague, Lviv, Budapest, Zagreb, Trieste and Vienna beside a folding ticket wallet, enamel station names, telegraph tape and krone notes.",
      imagePosition: "60% center",
      mobileImagePosition: "50% center",
      visualLabel: "Railway map, travel wallet and multilingual stations",
      visualTone: "braided-journey",
      side: "right",
      sourceIds: ["judson-2016", "beller-2018", "good-1984"],
      evidence: [
        "By the late nineteenth century, railways and telegraph lines connected the monarchy’s major cities and ports within coordinated technical, commercial and postal systems.",
        "The 1892 currency reform introduced the krone/corona across Austria-Hungary, while renewed customs agreements maintained a common economic space across separate Austrian and Hungarian governments.",
      ],
      map: { x: 57, y: 51 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "imperial-journey",
        prompt: "Follow one imperial journey",
        accessibleSummary:
          "Four travel wallets begin in Prague, Lviv, Trieste or Zagreb and reveal the rail, post, currency, court and military systems that carry a traveller toward Vienna or Budapest while local laws and place-names remain visible.",
        initialId: "prague-vienna",
        mapImage: `${imageRoot}/12-rails-braid-the-crownlands.avif`,
        records: [
          {
            id: "prague-vienna",
            label: "Prague to Vienna",
            period: "Bohemia to Lower Austria",
            kicker: "The night train crosses crownlands",
            detail:
              "A Czech-speaking commercial clerk leaves Praha–Prag with a through ticket, posts a contract at the station and reaches Vienna beneath the same Austrian public law.",
            fields: [
              { label: "Shared", value: "Rail standard, post and krone" },
              {
                label: "Local",
                value: "Bohemian diet, Czech and German civic life",
              },
              { label: "Arrival", value: "Vienna ministry or Imperial Court" },
            ],
            outcome:
              "The journey changes crownland and language without leaving the Austrian constitutional space.",
            points: [
              {
                id: "prague",
                label: "Praha · Prag",
                detail: "Bohemian departure",
                x: 39,
                y: 32,
              },
              {
                id: "brno",
                label: "Brno · Brünn",
                detail: "Moravian junction",
                x: 50,
                y: 47,
              },
              {
                id: "vienna",
                label: "Wien · Vienna",
                detail: "Imperial capital",
                x: 57,
                y: 58,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "lviv-budapest",
            label: "Lviv to Budapest",
            period: "Galicia across the Carpathians",
            kicker: "The ticket crosses the dual boundary",
            detail:
              "A Ruthenian student leaves Lviv–Lwów–Lemberg, changes beside the Carpathians and enters the Hungarian half with familiar money and a recognised rail connection.",
            fields: [
              {
                label: "Shared",
                value: "Through route, currency and telegraph",
              },
              { label: "Local", value: "Galician crownland and Hungarian law" },
              { label: "Arrival", value: "Budapest university and ministry" },
            ],
            outcome:
              "Two governments remain real while coordinated systems carry the passenger between them.",
            points: [
              {
                id: "lviv",
                label: "Lviv · Lwów · Lemberg",
                detail: "Galician departure",
                x: 76,
                y: 32,
              },
              {
                id: "munkacs",
                label: "Munkács · Mukačevo",
                detail: "Carpathian crossing",
                x: 71,
                y: 53,
              },
              {
                id: "budapest",
                label: "Budapest",
                detail: "Hungarian capital",
                x: 60,
                y: 67,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "trieste-vienna",
            label: "Trieste to Vienna",
            period: "The Adriatic over Semmering",
            kicker: "The port enters the river capital",
            detail:
              "An Italian-speaking shipping agent closes a customs file at Triest–Trieste and rides through Ljubljana and Graz over the Semmering line.",
            fields: [
              {
                label: "Shared",
                value: "Customs paper, rail and commercial law",
              },
              {
                label: "Local",
                value: "Free-port traditions and coastal languages",
              },
              { label: "Arrival", value: "Vienna bank, exchange and ministry" },
            ],
            outcome:
              "The Adriatic harbour and Danube capital work as parts of one commercial geography.",
            points: [
              {
                id: "trieste",
                label: "Triest · Trieste",
                detail: "Adriatic departure",
                x: 42,
                y: 82,
              },
              {
                id: "graz",
                label: "Graz",
                detail: "Alpine junction",
                x: 49,
                y: 67,
              },
              {
                id: "vienna-south",
                label: "Wien · Vienna",
                detail: "Danube arrival",
                x: 57,
                y: 58,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "zagreb-budapest",
            label: "Zagreb to Budapest",
            period: "Croatia-Slavonia to Hungary",
            kicker: "A compact travels with the passenger",
            detail:
              "A Croatian municipal officer leaves Zagreb–Agram carrying a Sabor petition through shared Hungarian-Croatian administration toward Budapest.",
            fields: [
              {
                label: "Shared",
                value: "Rail, currency and defined joint affairs",
              },
              { label: "Local", value: "Croatian Sabor and official Croatian" },
              { label: "Arrival", value: "Hungarian-Croatian ministry" },
            ],
            outcome:
              "The route works because the constitutional difference is documented rather than ignored.",
            points: [
              {
                id: "zagreb",
                label: "Zagreb · Agram",
                detail: "Croatian departure",
                x: 51,
                y: 78,
              },
              {
                id: "balaton",
                label: "Lake Balaton",
                detail: "Hungarian route",
                x: 58,
                y: 70,
              },
              {
                id: "budapest-north",
                label: "Budapest",
                detail: "Joint-affairs destination",
                x: 60,
                y: 60,
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
      id: "city-holds-several-homes",
      actId: "common-home",
      order: 13,
      period: "AD 1880–1914",
      place: "Vienna, Lviv, Trieste and Czernowitz",
      title: "A City Holds Several Homes",
      thesis:
        "Habsburg cities made layered belonging ordinary through municipalities, schools, theatres, cafés, associations and streets where several public languages met.",
      body: [
        "An imperial city woke to several kinds of bell. A tram sounded at an intersection, a school called children from different streets, a newspaper bundle struck the café table and a train announced arrivals beneath names that changed with the language of the speaker. Municipal government laid water pipes, paved roads, inspected food and built markets, parks and theatres. Taxes collected from local property returned as civic works bearing a city’s chosen style. The monarchy provided courts, currency, universities and routes; the municipality turned those structures into a place its citizens could claim as their own.",
        "Lviv was Lwów in Polish public life, Lemberg in German administration and Lviv to Ukrainians who built schools, societies and political organisations. Poles dominated much of the Galician provincial settlement, while Ruthenian leaders used imperial law and Vienna petitions to press claims against them; a large Jewish population created its own religious, commercial and intellectual worlds. Trieste joined Italian mercantile culture, Slovene hinterlands, Jewish trading houses, Greek and Serbian congregations and an Austrian port administration at the head of the Adriatic. Czernowitz made a provincial capital from Romanian, Ukrainian, German, Polish and Yiddish speech, its university and theatre facing the same formal square.",
        "No pavement dissolved hierarchy or national rivalry. School boards fought over language, census categories became weapons, municipal majorities excluded neighbours and antisemitic politics entered elections. The common state gave these contests addresses: council chamber, crownland diet, ministry, newspaper office and court. A citizen might speak Polish at home, conduct business in German, hear Yiddish in the market, petition for a Ukrainian school and take a train under an imperial timetable. Such lives did not require indifference to nation. They allowed nation, city, confession, profession and dynasty to occupy different rooms of the same house.",
        "The beauty of the order appeared in use. Evening light caught tram wire above a street named twice; an enamel station board promised departure to Vienna; a municipal theatre raised its curtain on a touring company; a civil servant folded a petition whose answer would return through the post. These were modest ceremonies of belonging, repeated until they felt permanent. Habsburg Europe could be cumbersome, unequal and argumentative. It also made a civilization in which difference became inhabitable, and a person could cross several homes in the course of one afternoon without meeting a frontier.",
      ],
      image: `${imageRoot}/13-city-holds-several-homes.avif`,
      imageAlt:
        "A continuous archival street joins Lviv, Trieste, Czernowitz and Vienna through tram wire, bilingual notices, a municipal theatre, café tables, waterworks and a railway canopy.",
      imagePosition: "57% center",
      mobileImagePosition: "63% center",
      visualLabel: "Archive-led imperial city street",
      visualTone: "layered-city",
      side: "left",
      sourceIds: [
        "judson-2016",
        "rady-2020",
        "prokopovych-2009",
        "beller-2018",
      ],
      evidence: [
        "Late Habsburg municipalities built modern utilities, transit, schools and cultural institutions within imperial and crownland legal frameworks.",
        "Cities including Lviv, Trieste and Czernowitz sustained overlapping linguistic, religious and national institutions whose competition usually proceeded through municipal, provincial and imperial forums.",
      ],
      map: { x: 60, y: 48 },
    },
    {
      id: "war-breaks-the-braid",
      actId: "common-home",
      order: 14,
      period: "AD 1907–1918",
      place: "Vienna, the fronts and the dissolving monarchy",
      title: "War Breaks the Braid",
      thesis:
        "Mass suffrage brought the monarchy’s peoples into one chamber; total war then displaced bargaining with military command, hunger and sacrifice until the common state came apart.",
      body: [
        "The Austrian half held its first election under universal and equal male suffrage in 1907. Social Democrats, Christian Socials, German parties, Czech parties, Polish groupings, South Slav representatives, Ruthenians, Italians and Romanians sent more than five hundred deputies to the Reichsrat. Speeches crossed languages, obstruction could paralyse business and governments assembled fragile majorities. The chamber was noisy because the political nation had become large. Hungary retained a much narrower franchise and Magyar parliamentary dominance, exposing the unevenness of reform. Across the Austrian crownlands, a worker or small farmer could now cast an equal ballot for a deputy who carried his locality and language into the imperial capital.",
        "The Sarajevo assassination of June 1914 placed a dynastic murder inside a Balkan struggle and an alliance system prepared for escalation. Vienna’s ultimatum to Serbia opened war; Russian mobilisation, German decisions and declarations drew the monarchy into a continental conflict. The government adjourned the Reichsrat and ruled the Austrian half through emergency powers until 1917. Military authorities censored publications, interned suspect civilians and imposed harsh administration in frontier regions. Armies recruited across the crownlands and often fought with tenacity, while casualty lists returned in every language. Shared service became shared bereavement.",
        "War severed the ordinary circuits that had made imperial life credible. Blockade and the division of food policy between Austria and Hungary left cities hungry; coal failed to reach factories and homes; inflation consumed salaries; railway wagons served fronts before civilian markets. Refugees crowded stations once built for confident travel. Emperor Charles recalled parliament and sought peace after 1916, though the accumulated burdens outran a late return to bargaining. National councils claimed authority as military defeat approached, Allied policy shifted toward successor states and soldiers went home through an administration losing the means to command or supply them.",
        "In October and November 1918, Czechoslovak, South Slav, Polish, Austrian and Hungarian governments took control of lands, offices and regiments. The monarchy did not fall because its peoples had always found common life impossible. Four years of total war had demanded obedience while removing food, security, parliamentary exchange and faith in victory—the practical returns that sustained loyalty. New borders crossed tracks on which one railway administration had carried sleeping cars the year before. Passports and customs posts divided families, markets and universities. On an abandoned timetable, Prague, Vienna, Budapest, Zagreb, Trieste, Lviv and Czernowitz remained joined by ruled lines. The braid survived on the page after the political current had broken.",
      ],
      image: `${imageRoot}/14-war-breaks-the-braid.avif`,
      imageAlt:
        "The crowded 1907 Reichsrat recedes behind wartime ration and requisition stamps that sever a braided railway map, leaving a sleeping-car timetable beside new frontier documents.",
      imagePosition: "63% center",
      mobileImagePosition: "70% center",
      visualLabel: "Parliament, requisition record and severed timetable",
      visualTone: "broken-braid",
      side: "right",
      sourceIds: [
        "judson-2016",
        "sked-2001",
        "beller-2018",
        "austrian-parliament-1848-1918",
      ],
      evidence: [
        "Universal and equal male suffrage governed the 1907 Reichsrat election in the Austrian half, while the Hungarian franchise remained substantially narrower.",
        "During the First World War, parliamentary suspension, emergency rule, military coercion, mass casualties and severe supply failure weakened the institutions and material exchange on which imperial loyalty depended.",
        "The monarchy dissolved amid military defeat and the transfer of authority to national councils in 1918, turning internal rail, legal and commercial routes into routes across new state borders.",
      ],
      map: { x: 57, y: 50 },
    },
  ],
};
