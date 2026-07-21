import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/europe-holds-the-line";

export const europeHoldsTheLine: ChapterDefinition = {
  slug: "europe-holds-the-line",
  number: "13",
  title: "The Frontiers Hold",
  openingTitleLines: ["The Frontiers", "Hold"],
  period: "AD 711–1699",
  claim:
    "Christian Europe survived centuries of conquest from the south and east because kingdoms, cities, military orders and frontier peoples kept rebuilding the line. At last the direction of pressure turned.",
  openingClaim:
    "Europe’s survival was never assured. Its peoples held mountains, walls, islands and river gates until defence became recovery.",
  hero: {
    image: `${imageRoot}/01-kingdom-falls-one-campaign.avif`,
    mobileImage: `${imageRoot}/01-kingdom-falls-one-campaign-mobile.avif`,
    imageAlt:
      "Organised Umayyad columns cross from Gibraltar into a relief map of Visigothic Iberia as roads toward Toledo break apart.",
    imagePosition: "center center",
    mobileImagePosition: "68% center",
    visualLabel: "Evidence-led reconstruction · the frontier hinge",
  },
  theme: {
    id: "frontier",
    label: "The frontier hinge",
  },
  openingAction: "Hold the line",
  mapLabel:
    "The ridges, walls, islands, rivers and fortress belts through which Europe survived conquest and recovered the frontier",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Campaign accounts · royal chronicles · settlement charters · siege journals · frontier ordinances · fleet orders · diplomatic instruments",
  acts: [
    {
      id: "western-edge-survives",
      number: "I",
      label: "The western edge survives",
      period: "AD 711–1492",
      title: "The Western Edge Survives",
      detail:
        "Northern Iberian kingdoms endure conquest, turn refuge into settled frontier and carry Christian sovereignty back to Granada.",
    },
    {
      id: "eastern-wall-calls",
      number: "II",
      label: "The eastern wall calls for aid",
      period: "AD 1071–1456",
      title: "The Eastern Wall Calls for Aid",
      detail:
        "Turkish expansion breaks Anatolia, the West answers, Latin crusaders ruin Constantinople, and Belgrade holds after New Rome falls.",
    },
    {
      id: "europe-becomes-fortress",
      number: "III",
      label: "Europe becomes a fortress",
      period: "AD 1521–1565",
      title: "Europe Becomes a Fortress",
      detail:
        "Ottoman armies reach the Danube and the Mediterranean centre; permanent border communities and fortified Malta deny the next advance.",
    },
    {
      id: "coalition-turns-line",
      number: "IV",
      label: "Coalition turns the line",
      period: "AD 1571–1699",
      title: "Coalition Turns the Line",
      detail:
        "Lepanto, Vienna, the Holy League and Karlowitz transform separate acts of defence into a durable south-eastern recovery.",
    },
  ],
  ending: {
    period: "AD 1699",
    title: "Europe Has Survived the Long Assault",
    detail:
      "Granada stood inside Christian Iberia, Vienna remained behind the Danube line and the frontier fixed at Karlowitz lay farther south-east. Survival had produced a continental repertoire: chartered settlement, armed pilgrimage, fortified harbours, permanent border communities, coalition fleets and armies supplied across many jurisdictions. Europe had learned to answer distance with alliance and repeated defeat with stronger institutions. The next generation carried that accumulated naval, financial and cartographic power beyond the defended coast. Europeans would stop waiting for the world’s trade to reach them and open an ocean road of their own.",
    image: `${imageRoot}/15-europe-survives-long-assault.avif`,
    nextPeriod: "AD 1415–1700",
  },
  returnHash: "frontiers-hold",
  nextHash: "europe-turns-seaward",
  nextTitle: "Europe Turns Seaward",
  nextSlug: "europe-turns-seaward",
  movements: [
    {
      id: "kingdom-falls-one-campaign",
      actId: "western-edge-survives",
      order: 1,
      period: "AD 711–718",
      place: "Gibraltar, Guadalete, Toledo and Iberia",
      title: "A Kingdom Falls in One Campaign",
      thesis:
        "The Umayyad crossing destroyed the Visigothic monarchy and made Christian survival an exposed northern undertaking.",
      body: [
        "In 711, Tariq ibn Ziyad crossed the strait with an army drawn largely from the recently conquered Berbers of North Africa and acting under Umayyad command. King Roderic met him in the south and lost the battle commonly placed near the Guadalete. The king disappeared with the field army. A monarchy that had ruled most of Iberia from Toledo suddenly lacked the force, succession and common purpose required to close the roads into its own heartland.",
        "The conquerors advanced with speed and calculation. Córdoba fell, Toledo was occupied and Musa ibn Nusayr brought further forces across the strait. Some towns resisted, others capitulated under terms, and rival Visigothic elites pursued local survival after the royal centre had broken. Within a few years, Muslim governors commanded nearly the whole peninsula and sent expeditions beyond the Pyrenees. Churches, estates and communities entered a new order in which Islam ruled and Christians lived as a subordinated population under tribute.",
        "For the people whose kingdom had vanished, these were the barbarians at the gate in the oldest and plainest meaning: foreign armed men who had crossed the sea, killed resistance, taken captives and imposed rule by conquest. Their commanders possessed strategy, administration and an imperial purpose; those strengths made the danger greater. No Christian field army in Iberia could now reverse the campaign. Nothing guaranteed that the surviving fragments would endure. Survival passed to lands beyond the secure reach of Córdoba, where mountains, weather and political memory might keep one crown alive long enough to begin again.",
      ],
      image: `${imageRoot}/01-kingdom-falls-one-campaign.avif`,
      mobileImage: `${imageRoot}/01-kingdom-falls-one-campaign-mobile.avif`,
      imageAlt:
        "Umayyad cavalry and infantry advance along broken Visigothic roads from Gibraltar toward an abandoned royal seal and Toledo.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "broken-kingdom",
      side: "left",
      sourceIds: ["kennedy-1996", "reilly-1993", "collins-1989"],
      evidence: [
        "The army led by Tariq in 711 defeated Roderic and was followed by Musa’s forces; the Visigothic political centre collapsed as cities were taken or capitulated.",
        "Coins, charters and the rapid appearance of Umayyad governors record the replacement of the Visigothic monarchy by a new ruling power across almost the whole peninsula.",
      ],
      map: { x: 21, y: 72 },
    },
    {
      id: "northern-valleys-keep-crown",
      actId: "western-edge-survives",
      order: 2,
      period: "c. AD 718–910",
      place: "Asturias, Covadonga, Oviedo and León",
      title: "The Northern Valleys Keep a Crown",
      thesis:
        "Asturias turned difficult refuge into a Christian monarchy capable of moving the frontier south.",
      body: [
        "Rain crossed the Cantabrian ridges, paths narrowed above wooded ravines and an army accustomed to open country lost the advantage of numbers. In this northern terrain, Pelagius and a small Christian following established resistance. The encounter remembered as Covadonga did not reconquer Iberia in a day. It preserved something more necessary: an armed centre beyond Córdoba’s dependable control, a leader around whom loyalty could gather and a victory from which a kingdom could narrate its right to exist.",
        "Asturian kings converted endurance into government. They founded a court at Oviedo, raised churches, endowed monasteries and claimed succession from the lost Visigothic order. Clergy kept books and royal memory; strong places guarded valleys and routes; tribute, service and land joined households to the crown. Royal building gave stone and ceremony to a polity its enemies had dismissed. The kingdom absorbed refugees and local peoples, fought rivals, and used moments of weakness farther south to widen its reach. Survival became an institution before it became a great army.",
        "By the early tenth century, royal power had crossed toward León and the Duero basin. Settlers occupied defended sites, restored fields and churches, and carried charters into lands exposed to raid. A monastery stored grain and title; a watch point bought warning; a fortified town held the road after the campaigning force departed. Generation after generation moved the viable line. The crown kept in the northern valleys was no relic. It became the political instrument through which Christian Iberia recovered space, population and confidence.",
      ],
      image: `${imageRoot}/02-northern-valleys-keep-crown.avif`,
      imageAlt:
        "A narrow Asturian valley opens from a defended mountain pass toward a hill church, royal hall and newly cultivated fields.",
      imagePosition: "59% center",
      mobileImagePosition: "65% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "mountain-refuge",
      side: "right",
      sourceIds: ["reilly-1993", "collins-1983"],
      evidence: [
        "Asturian royal centres, churches, chronicles and archaeology document the consolidation of a northern Christian monarchy after the conquest.",
        "Asturian kings made Covadonga a founding memory and carried its promise south through rule, fortification and settlement across generations.",
      ],
      map: { x: 21, y: 58 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "northern-valleys",
        prompt: "Hold the northern valleys",
        accessibleSummary:
          "Four cumulative layers show terrain, a fortified royal centre, a monastery and resettled fields turning an Asturian refuge into a kingdom reaching León.",
        initialId: "terrain",
        mapImage: `${imageRoot}/02-northern-valleys-keep-crown.avif`,
        records: [
          {
            id: "terrain",
            label: "Keep the pass",
            period: "c. AD 718",
            kicker: "Terrain denies easy conquest",
            detail:
              "Wet ridges, narrow approaches and local knowledge reduce the advantage of a larger expedition entering the Cantabrian valleys.",
            fields: [
              { label: "Defence", value: "Pass, ravine and concealed route" },
              { label: "Reach", value: "A refuge capable of armed resistance" },
            ],
            outcome:
              "A surviving force retains a place around which loyalty can gather.",
            points: [
              {
                id: "covadonga",
                label: "Covadonga",
                detail: "Mountain resistance",
                x: 64,
                y: 38,
              },
            ],
          },
          {
            id: "fortified-centre",
            label: "Raise the centre",
            period: "late eighth century",
            kicker: "Refuge becomes monarchy",
            detail:
              "A court, churches and defended approaches at Oviedo give the surviving crown a seat, a ritual language and officers.",
            fields: [
              { label: "Institution", value: "Royal hall, church and guard" },
              { label: "Reach", value: "Valleys joined to one crown" },
            ],
            outcome:
              "Rule can now endure between campaigns and beyond one leader.",
            points: [
              {
                id: "covadonga",
                label: "Covadonga",
                detail: "Mountain resistance",
                x: 64,
                y: 38,
              },
              {
                id: "oviedo",
                label: "Oviedo",
                detail: "Royal centre",
                x: 57,
                y: 48,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "monastery",
            label: "Store the memory",
            period: "ninth century",
            kicker: "Church and archive deepen rule",
            detail:
              "Monastic houses preserve worship, grain, gifts and written title while royal claims acquire a history longer than one reign.",
            fields: [
              { label: "Institution", value: "Monastery, store and archive" },
              { label: "Reach", value: "Land held and remembered" },
            ],
            outcome:
              "The kingdom gains material reserves and a durable account of its inheritance.",
            points: [
              {
                id: "oviedo",
                label: "Oviedo",
                detail: "Royal centre",
                x: 57,
                y: 48,
              },
              {
                id: "samos",
                label: "Monastic belt",
                detail: "Houses and estates",
                x: 48,
                y: 57,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "resettled-field",
            label: "Move the line",
            period: "c. AD 850–910",
            kicker: "Settlement carries the frontier",
            detail:
              "Defended fields, restored churches and a royal centre at León turn seasonal reach into inhabited Christian territory.",
            fields: [
              {
                label: "Institution",
                value: "Land grant, field and fortified town",
              },
              { label: "Reach", value: "From Asturias toward the Duero" },
            ],
            outcome:
              "The mountain refuge has become a kingdom capable of recovery.",
            points: [
              {
                id: "oviedo",
                label: "Oviedo",
                detail: "Northern court",
                x: 57,
                y: 48,
              },
              {
                id: "leon",
                label: "León",
                detail: "Southern royal centre",
                x: 54,
                y: 69,
              },
              {
                id: "duero",
                label: "Duero fields",
                detail: "Defended settlement",
                x: 58,
                y: 82,
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
      id: "toledo-changes-hands",
      actId: "western-edge-survives",
      order: 3,
      period: "AD 1085–1212",
      place: "Toledo and the central Iberian frontier",
      title: "Toledo Changes Hands",
      thesis:
        "Conquest endured when charters, settlers and local defence converted a captured city into held ground.",
      body: [
        "Alfonso VI entered Toledo in 1085 and recovered the old Visigothic capital without destroying the city he intended to rule. Its height above the Tagus commanded a bridge, roads and the centre of the peninsula. Its population included Muslims, Christians and Jews; its walls, craftsmen and markets were prizes as important as its royal memory. The frontier had moved through one of Europe’s great urban gates, and the recovered city gave the northern kingdoms a base south of the central mountains.",
        "A gate key did not hold a province. Kings issued fueros that defined rights, dues, military obligations and the conditions on which settlers would inhabit exposed towns. Land allotments brought cultivators and mounted defenders; councils organised walls, markets and local justice; military orders guarded roads and castles. The walls became a civic obligation shared across generations. The charter joined liberty to danger. Men accepted frontier service because the recovered town offered property and a public order worth defending after the royal host had ridden elsewhere.",
        "The advance drew a formidable answer from North Africa. Almoravid armies crossed the strait and defeated Alfonso at Sagrajas in 1086. Almohad power followed in the twelfth century and renewed imperial pressure from the south. The plateau became a moving field of raids, sieges, lost castles and recovered towns. Toledo held because occupation had become society: inhabitants, walls, law, worship and surrounding fields reinforced one another. Christian recovery had found its working mechanism. An army opened the gate; a chartered community kept it open.",
      ],
      image: `${imageRoot}/03-toledo-changes-hands.avif`,
      imageAlt:
        "Toledo rises above the Tagus beside gate keys, a settlement charter and marked field allotments as North African routes approach from the south.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "chartered-frontier",
      side: "left",
      sourceIds: ["ocallaghan-2003", "reilly-1993", "kennedy-1996"],
      evidence: [
        "Alfonso VI took Toledo in 1085 and preserved a socially diverse city whose bridge, roads and fortifications made it a strategic frontier centre.",
        "Fueros, land grants, municipal militias and military orders helped turn conquest into defended settlement across the central Iberian frontier.",
      ],
      map: { x: 22, y: 67 },
    },
    {
      id: "las-navas-opens-south",
      actId: "western-edge-survives",
      order: 4,
      period: "AD 1212–1492",
      place: "Las Navas de Tolosa, Córdoba, Seville and Granada",
      title: "Las Navas Opens the South",
      thesis:
        "Coalition victory broke Almohad ascendancy and opened the road to the great cities of the Guadalquivir.",
      body: [
        "In July 1212, Alfonso VIII of Castile brought his army through the Sierra Morena to face the Almohad caliph al-Nasir. Pedro II of Aragon and Sancho VII of Navarre stood with him, joined by military orders, townsmen and crusaders. The pass had been found and the coalition had kept its ranks. At Las Navas de Tolosa the Christian coalition broke the Almohad field army and shattered the power capable of driving the frontier back toward Toledo. Its political shock reached every power on the peninsula.",
        "The next generation converted opportunity into conquest. Ferdinand III took Córdoba in 1236 and Seville in 1248, while Aragon advanced through Valencia and Portugal completed its southern recovery in the Algarve. Rivers, ports and fertile districts passed under Christian crowns. Every recovered city extended the roads and revenues available to the next. Settlement, parish, council and lordship followed the armies. The Nasrid kingdom of Granada survived behind mountain approaches through tribute, diplomacy, internal skill and the changing rivalries of its stronger neighbours.",
        "Granada’s endurance ended under Ferdinand of Aragon and Isabella of Castile. A sustained campaign took the surrounding strongholds and denied the Nasrid capital room to recover. On 2 January 1492, the Catholic Monarchs received the city and the keys of the Alhambra. Nearly eight centuries after the crossing at Gibraltar, no Muslim sovereign remained in Iberia. The western edge had done more than survive: small northern crowns had recovered an entire peninsula through alliance, law, settlement and the stubborn inheritance of a lost kingdom.",
      ],
      image: `${imageRoot}/04-las-navas-opens-south.avif`,
      imageAlt:
        "A frontier map links the Sierra Morena pass to Córdoba, Seville and the keys of Granada before the Alhambra.",
      imagePosition: "60% center",
      mobileImagePosition: "67% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "recovered-south",
      side: "right",
      sourceIds: ["ocallaghan-2003", "kennedy-1996", "reilly-1993"],
      evidence: [
        "Castilian, Aragonese and Navarrese forces defeated the Almohad army at Las Navas de Tolosa in 1212, opening a period of major Christian conquests.",
        "The Nasrid kingdom remained sovereign until the capitulation of Granada and the formal handover to Ferdinand and Isabella on 2 January 1492.",
      ],
      map: { x: 23, y: 75 },
    },
    {
      id: "anatolia-breaks-open",
      actId: "eastern-wall-calls",
      order: 5,
      period: "AD 1071–1095",
      place: "Manzikert, Anatolia, Constantinople and Piacenza",
      title: "Anatolia Breaks Open",
      thesis:
        "Military defeat and Roman civil war exposed the Anatolian heartland and drove Alexios I to seek western soldiers.",
      body: [
        "At Manzikert in 1071, Sultan Alp Arslan defeated and captured the eastern Roman emperor Romanos IV. The civil wars that followed converted a battlefield defeat into strategic collapse. The frontier lost its chain of command. Roman factions recruited Turkish forces against one another, provincial command fractured and armed settlers entered pasture, road and town across the plateau. Fortresses that once guarded the interior became isolated islands of authority. Within a generation, imperial rule had receded from lands that furnished taxes, grain, horses and soldiers to Constantinople.",
        "The Turkish advance created new powers rather than one continuous occupation. Nicaea itself became the Seljuk capital by 1081, within striking distance of the Bosporus, while other dynasties and war bands took territory farther east. The Bosporus now looked directly toward a Turkish court. Communities faced raid, tribute, displaced authority and changing masters. Emperor Alexios I Komnenos restored discipline around the capital and the western provinces, but his army lacked the men required to recover the interior and hold every road after victory.",
        "Alexios looked west. At the Council of Piacenza in 1095, his envoys appealed to Pope Urban II and the assembled churchmen for military help against the Turks. The request travelled through a Christendom whose warriors possessed horses, arms and a violent appetite the reforming papacy hoped to direct toward sacred service. New Rome had carried Europe’s eastern wall for centuries. Its emperor now asked the Latin West to recognise that the broken Anatolian frontier was a danger shared across the Christian world.",
      ],
      image: `${imageRoot}/05-anatolia-breaks-open.avif`,
      imageAlt:
        "A dated relief map shows Manzikert, fractured Roman roads across Anatolia and an imperial appeal travelling from Constantinople to Piacenza.",
      imagePosition: "63% center",
      mobileImagePosition: "69% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "broken-anatolia",
      side: "left",
      sourceIds: ["smith-2024", "tyerman-2006", "frankopan-2012"],
      evidence: [
        "Manzikert removed Romanos IV; the ensuing civil wars fractured imperial command while Turkish settlement opened most of Anatolia.",
        "Accounts of the Council of Piacenza record an eastern Roman appeal for western military assistance before Urban II preached at Clermont.",
      ],
      map: { x: 72, y: 68 },
    },
    {
      id: "europe-answers-clermont",
      actId: "eastern-wall-calls",
      order: 6,
      period: "AD 1095–1099",
      place: "Clermont, Constantinople, Nicaea, Antioch and Jerusalem",
      title: "Europe Answers at Clermont",
      thesis:
        "The First Crusade converted an eastern appeal into an armed pilgrimage of astonishing continental reach.",
      body: [
        "At Clermont in November 1095, Urban II summoned western warriors to aid eastern Christians and carry armed pilgrimage to Jerusalem. Men and women took the cross across France, Lotharingia, Norman Italy and other lands. Great lords sold or mortgaged property, households gathered supplies and columns began roads longer than any western army had recently attempted. No king commanded the expedition. The response crossed political borders because the vow attached each warrior to a shared destination. Preaching, lordship and faith assembled separate contingents around a common, dangerous purpose.",
        "They converged on Constantinople, where Alexios required leaders to swear oaths and supplied markets, guides, ships and passage into Asia. Crusaders and Roman forces recovered Nicaea in 1097. Roman engineers also directed crucial siege work there. The western army then crossed Anatolia, endured thirst and battle, and besieged Antioch through a winter of hunger. Cooperation repeatedly strained, but Byzantine logistics and local Christian knowledge helped carry the first advance while western numbers and siege endurance supplied the striking force.",
        "In July 1099, the crusaders stormed Jerusalem after a campaign that had consumed armies and leaders along the road. The victors killed many Muslim and Jewish inhabitants and established Latin rule in the captured city. The expedition had grown beyond Alexios’s request and created western states on the eastern Mediterranean frontier. Its central fact remained extraordinary: a divided Europe had answered a danger beyond Constantinople, moved armed societies across a continent and won each of the fortified objectives on which the whole enterprise depended.",
      ],
      image: `${imageRoot}/06-europe-answers-clermont.avif`,
      imageAlt:
        "Four western crusading routes converge at Constantinople before continuing through the siege landscapes of Nicaea, Antioch and Jerusalem.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "armed-pilgrimage",
      side: "right",
      sourceIds: [
        "tyerman-2006",
        "riley-smith-1986",
        "france-1994",
        "smith-2024",
      ],
      evidence: [
        "The crusading contingents formed through vows and lordship rather than a single royal command, then travelled by distinct routes to Constantinople.",
        "Byzantine markets, transport, guides and military cooperation supported the advance, while multiple traditions record the mass killing after Jerusalem’s capture in 1099.",
      ],
      map: { x: 69, y: 67 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "eastern-call",
        prompt: "Answer the eastern call",
        accessibleSummary:
          "Five stages bring four western contingents to Constantinople, then follow the combined expedition through Nicaea, Antioch and Jerusalem.",
        initialId: "four-roads",
        mapImage: `${imageRoot}/06-europe-answers-clermont.avif`,
        records: [
          {
            id: "four-roads",
            label: "Four roads",
            period: "AD 1096–1097",
            kicker: "Separate vows converge",
            detail:
              "Contingents from northern France and Flanders, Lotharingia, southern France and Norman Italy approach the eastern capital by different roads.",
            fields: [
              { label: "North-west", value: "Godfrey, Robert and Stephen" },
              { label: "South-west", value: "Raymond of Toulouse" },
              { label: "South", value: "Bohemond and the Normans" },
              { label: "Meeting point", value: "Constantinople" },
            ],
            outcome:
              "A continental mobilisation gathers at the gate of the eastern Roman Empire.",
            points: [
              {
                id: "france",
                label: "France",
                detail: "Northern contingents",
                x: 18,
                y: 29,
              },
              {
                id: "lotharingia",
                label: "Lotharingia",
                detail: "Rhine road",
                x: 30,
                y: 22,
              },
              {
                id: "provence",
                label: "Southern France",
                detail: "Raymond’s road",
                x: 23,
                y: 49,
              },
              {
                id: "norman-italy",
                label: "Norman Italy",
                detail: "Adriatic crossing",
                x: 42,
                y: 58,
              },
              {
                id: "constantinople",
                label: "Constantinople",
                detail: "Imperial rendezvous",
                x: 70,
                y: 47,
              },
            ],
            links: [
              [0, 4],
              [1, 4],
              [2, 4],
              [3, 4],
            ],
          },
          {
            id: "constantinople",
            label: "Constantinople",
            period: "AD 1097",
            kicker: "Oath, market and passage",
            detail:
              "Alexios receives the leaders, requires promises over recovered lands and supplies the passage from Europe into Asia.",
            fields: [
              { label: "Western force", value: "Vow, cavalry and manpower" },
              {
                label: "Roman system",
                value: "Markets, ships, guides and command",
              },
            ],
            outcome:
              "Zeal acquires the logistics required to cross the imperial frontier.",
          },
          {
            id: "nicaea",
            label: "Nicaea",
            period: "June AD 1097",
            kicker: "The first gate returns",
            detail:
              "Crusaders invest the Seljuk capital while Roman ships close the lake; the city surrenders to Alexios’s officers.",
            fields: [
              { label: "Obstacle", value: "Walls and an open lake route" },
              { label: "Cooperation", value: "Western siege and Roman fleet" },
            ],
            outcome:
              "The city nearest Constantinople returns to eastern Roman rule.",
          },
          {
            id: "antioch",
            label: "Antioch",
            period: "AD 1097–1098",
            kicker: "The army survives the winter",
            detail:
              "A long siege, famine and a counter-siege test the expedition until the crusaders secure the great Syrian fortress.",
            fields: [
              {
                label: "Obstacle",
                value: "Vast walls, hunger and relief armies",
              },
              { label: "Resource", value: "Siege endurance and local supply" },
            ],
            outcome:
              "The road south remains open because the army refuses to dissolve.",
          },
          {
            id: "jerusalem",
            label: "Jerusalem",
            period: "15 July AD 1099",
            kicker: "The armed pilgrimage reaches its end",
            detail:
              "Siege towers breach the walls and the crusaders take the city, kill many inhabitants and establish Latin rule.",
            fields: [
              { label: "Objective", value: "The holy city" },
              {
                label: "Cost",
                value: "A brutal sack after a four-year mobilisation",
              },
            ],
            outcome:
              "Europe has projected an army from the Atlantic world to Jerusalem and won.",
          },
        ],
      },
    },
    {
      id: "christians-break-eastern-wall",
      actId: "eastern-wall-calls",
      order: 7,
      period: "AD 1204–1261",
      place: "Constantinople",
      title: "Christians Break the Eastern Wall",
      thesis:
        "The Fourth Crusade inflicted the internal catastrophe that left the eastern Roman defence divided and poor.",
      body: [
        "In April 1204, Latin crusaders and Venetian ships attacked Constantinople after a campaign diverted by debt, dynastic intrigue and ambition. They forced the sea walls and entered the greatest Christian city in the world. The sack continued for three days under the rights claimed by conquest. Churches, palaces, houses and treasuries were stripped. Relics and artworks travelled west; fires and plunder ruined whole districts. Men who had taken the cross entered a Christian capital as allies of a claimant and behaved as barbarians once its defences broke.",
        "The victors divided the imperial inheritance. A Latin emperor held Constantinople while Venice claimed ports and islands; Roman successor states formed at Nicaea, Epirus and Trebizond. Their rulers spent men and revenue against one another as Turkish powers consolidated in Anatolia. Nicaea recovered the capital in 1261, but recovery restored a diminished centre. Trade privileges drained income, provinces had acquired separate interests and the resources once concentrated behind the Theodosian walls had scattered. The eastern balance never fully recovered.",
        "The sack’s consequence extended far beyond 1204. It broke the scale on which eastern Rome had defended Europe. The empire that returned to Constantinople possessed less territory, a smaller treasury, rival claimants and a wound between Latin and Greek Christians that diplomacy never fully healed. That wound became a strategic condition for many generations. Europe’s eastern wall had been breached from inside. Every later defence of the city began with fewer ships, fewer soldiers and less trust because crusaders had mistaken possession for rescue.",
      ],
      image: `${imageRoot}/07-christians-break-eastern-wall.avif`,
      imageAlt:
        "The breached sea wall of Constantinople opens onto stripped bronze doors and divided imperial seals, with Roman successor routes beyond.",
      imagePosition: "63% center",
      mobileImagePosition: "69% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "eastern-wall-breached",
      side: "left",
      sourceIds: ["phillips-2004", "herrin-2013"],
      evidence: [
        "The Fourth Crusade captured and sacked Constantinople in April 1204, establishing a Latin regime and distributing territories and privileges among conquerors.",
        "Roman recovery in 1261 restored the capital without restoring the empire’s former fiscal, territorial or maritime strength.",
      ],
      map: { x: 69, y: 66 },
    },
    {
      id: "constantinople-falls-belgrade-holds",
      actId: "eastern-wall-calls",
      order: 8,
      period: "AD 1453–1456",
      place: "Constantinople and Belgrade",
      title: "Constantinople Falls; Belgrade Holds",
      thesis:
        "The eastern Roman state ended at Constantinople, but a Danube coalition denied Mehmed II his next great gate.",
      body: [
        "Mehmed II came against Constantinople in 1453 with a disciplined army, a fleet and cannon large enough to batter ancient masonry day after day. The famous walls had guarded the city through more than a thousand years of attack. Ottoman ships entered the Golden Horn after being hauled overland behind the chain. Constantine XI commanded a small defence of Romans, Genoese and Venetians under the last imperial eagles. Giovanni Giustiniani directed men at the damaged land walls while citizens repaired breaches, carried ammunition and prayed in a capital whose population could no longer fill its circuit.",
        "On 29 May, the final Ottoman assault broke through. Constantine died with the defenders, the eastern Roman state ended and the conquered city endured killing, enslavement and plunder before Mehmed made it his capital. The victor then turned toward the middle Danube. Belgrade stood where the Sava enters that river, commanding the road into Hungary. In July 1456, Ottoman guns and ships closed around a fortress whose fall promised access to the plains beyond.",
        "John Hunyadi brought a relief force and broke the river blockade. John of Capistrano’s crusaders joined soldiers, townspeople and boatmen inside and around the walls. They repaired damage, repelled the main assault and drove into the Ottoman camp until Mehmed abandoned the siege. Constantinople had fallen before overwhelming force; Belgrade proved that the same conqueror could be stopped by a supplied fortress and a relief army arriving at the decisive hour. For another sixty-five years, the Danube gate remained closed.",
      ],
      image: `${imageRoot}/08-constantinople-falls-belgrade-holds.avif`,
      imageAlt:
        "Paired fortress sections show Ottoman cannon breaching Constantinople and a river relief force reaching Belgrade at the Danube and Sava.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "two-fortress-gates",
      side: "right",
      sourceIds: ["philippides-hanak-2011", "agoston-2021"],
      evidence: [
        "Ottoman artillery, mining, fleet operations and repeated assaults overcame Constantinople’s small multinational defence on 29 May 1453.",
        "At Belgrade in 1456, Hunyadi’s river action, the garrison and a crusading relief force defeated Mehmed II’s siege and preserved the middle Danube barrier.",
      ],
      map: { x: 61, y: 62 },
    },
    {
      id: "road-reaches-vienna",
      actId: "europe-becomes-fortress",
      order: 9,
      period: "AD 1521–1529",
      place: "Belgrade, Mohács, Buda and Vienna",
      title: "The Road Reaches Vienna",
      thesis:
        "Ottoman conquest opened the central Danube corridor, then a prepared city and exhausted supply line stopped the first siege of Vienna.",
      body: [
        "Süleyman I returned to Belgrade in 1521 with the weight the earlier siege had lacked. Guns, river craft and systematic assault forced the fortress to capitulate, opening the Danube road. Five years later the Hungarian royal army met him near Mohács. Ottoman firepower, command and reserves destroyed it in a short battle; King Louis II died during the retreat. Hungary’s succession split between Ferdinand of Habsburg and John Zápolya while Ottoman power entered the broken kingdom as arbiter and conqueror.",
        "In 1529, Süleyman restored Zápolya at Buda and continued west toward Vienna. Rain turned roads to mud, animals died and heavy siege pieces fell behind the march. The army that reached the Habsburg capital remained formidable. Its miners attacked beneath walls strengthened by earthworks; its infantry assaulted breaches defended under Niklas Salm by landsknechts, Spanish troops, citizens and gunners. Sorties disrupted trenches while defenders listened underground for the sound of Ottoman picks.",
        "The city held through repeated assault. October weather worsened, fodder and food diminished, sickness spread and the extended road back through Hungary threatened the besiegers. Süleyman withdrew without taking the Habsburg gate. Its survival prevented an immediate Ottoman base inside Austria. Belgrade and Mohács had shown the terrible reach of his imperial system; Vienna showed the limit imposed by distance, season and a disciplined urban defence. Central Europe now knew that the frontier stood at its door. Walls alone would never be enough. The lands behind them had to become a permanent machine of warning, supply and service.",
      ],
      image: `${imageRoot}/09-road-reaches-vienna.avif`,
      imageAlt:
        "A Danube campaign table links the key of Belgrade, the broken Hungarian standard at Mohács, Buda and the earthworks of Vienna under rain.",
      imagePosition: "61% center",
      mobileImagePosition: "67% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "danube-pressure",
      side: "left",
      sourceIds: ["agoston-2021", "murphey-1999", "agoston-2025"],
      evidence: [
        "Süleyman’s campaigns took Belgrade in 1521, destroyed the Hungarian royal army at Mohács in 1526 and brought an Ottoman field army to Vienna in 1529.",
        "Weather and supply strain weakened the 1529 siege, while earthworks, mining countermeasures, sorties and a determined garrison denied the assaults.",
      ],
      map: { x: 51, y: 55 },
    },
    {
      id: "living-wall-guards-croatia",
      actId: "europe-becomes-fortress",
      order: 10,
      period: "c. AD 1520s–1578",
      place: "Croatia, Slavonia and the Habsburg Military Frontier",
      title: "A Living Wall Guards Croatia",
      thesis:
        "The Habsburg and Croatian border became a defended society in which land, liberty, tax and military service sustained one another.",
      body: [
        "The Ottoman frontier formed a deep, broken zone rather than a clean line on a map. Raiding parties crossed rivers and forests, fortresses changed hands, villages emptied and warning travelled unevenly toward the interior. The border’s weakness demanded depth, redundancy and men able to move before a main army arrived. Croatian estates, royal captains and the Habsburg rulers answered by building belts of strongpoints from the Adriatic approaches through Croatia and Slavonia. A castle watched a road; smaller posts watched the gaps; beacons and riders carried alarm toward the next captaincy.",
        "People made the wall live. Croats, Serbs, Vlachs and other refugee and frontier families settled exposed districts under varied grants of land, tax privilege and local liberty in return for armed service. They farmed, tended animals, patrolled routes and assembled when warning arrived. Their households gave the defence depth because a garrison existed beside fields, kin and communities with a direct interest in preventing the next Ottoman raid from reaching farther inland.",
        "Money and powder had to travel from safer lands. The estates of Inner Austria raised taxes and supplies; magazines stored grain, shot and weapons; officers inspected walls and musters. Each post existed through the others nearby. In 1578, a strengthened command system at Graz tied major sectors more closely to permanent finance. The result was a living military frontier rather than one continuous rampart. It absorbed repeated pressure, passed intelligence and forced invasion toward defended corridors. Austria and Italy slept behind families whose farm, watch and service formed one European shield.",
      ],
      image: `${imageRoot}/10-living-wall-guards-croatia.avif`,
      imageAlt:
        "A Croatian frontier landscape connects a military family’s field to a beacon, powder road, magazine and stone fortress.",
      imagePosition: "60% center",
      mobileImagePosition: "66% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "living-border",
      side: "right",
      sourceIds: ["rothenberg-1960", "agoston-2025"],
      evidence: [
        "The Croatian and Slavonian frontier developed through captaincies, forts, watch posts and mobile patrols, with major reorganisation under Inner Austrian direction in 1578.",
        "Frontier populations held diverse legal statuses; land and privileges were repeatedly connected to military service, settlement and rapid mobilisation.",
      ],
      map: { x: 53, y: 61 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "military-frontier-supply",
        prompt: "Feed the military frontier",
        accessibleSummary:
          "Five connected records carry food, tax, powder and warning from a settled village through a magazine and fortress to a patrolling garrison.",
        initialId: "village-land",
        mapImage: `${imageRoot}/10-living-wall-guards-croatia.avif`,
        records: [
          {
            id: "village-land",
            label: "Settle the land",
            period: "The exposed district",
            kicker: "A wall begins with households",
            detail:
              "Frontier families receive land and defined liberties in return for cultivation, watch and armed service.",
            fields: [
              { label: "Provides", value: "Food, scouts and fighting men" },
              {
                label: "Receives",
                value: "Land, status and defended community",
              },
            ],
            outcome:
              "The border remains inhabited instead of becoming an empty raiding ground.",
            points: [
              {
                id: "village",
                label: "Village land",
                detail: "Field and service",
                x: 30,
                y: 72,
              },
            ],
          },
          {
            id: "tax-district",
            label: "Raise the tax",
            period: "The safer interior",
            kicker: "Distance finances exposure",
            detail:
              "Estates farther from attack gather money and provisions for men guarding roads they may never see.",
            fields: [
              { label: "Provides", value: "Tax, grain and wagon service" },
              { label: "Connects", value: "Inner Austria to the frontier" },
            ],
            outcome:
              "The defended line becomes a common burden rather than a local sacrifice.",
            points: [
              {
                id: "tax",
                label: "Tax district",
                detail: "Interior finance",
                x: 15,
                y: 42,
              },
              {
                id: "road",
                label: "Supply road",
                detail: "Wagon route",
                x: 42,
                y: 50,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "powder-magazine",
            label: "Fill the magazine",
            period: "Before the alarm",
            kicker: "Stores turn money into endurance",
            detail:
              "Powder, shot, weapons and grain arrive before a siege and remain dry behind an inspected door.",
            fields: [
              { label: "Stores", value: "Powder, shot, grain and tools" },
              { label: "Purpose", value: "Days and weeks of resistance" },
            ],
            outcome: "A fortress can fight after the road behind it closes.",
            points: [
              {
                id: "road",
                label: "Supply road",
                detail: "Wagon route",
                x: 42,
                y: 50,
              },
              {
                id: "magazine",
                label: "Magazine",
                detail: "Stored endurance",
                x: 59,
                y: 44,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "fortress",
            label: "Hold the fortress",
            period: "The defended road",
            kicker: "Stone concentrates the system",
            detail:
              "A captain, walls, artillery and stored supplies deny the route while signals summon help from neighbouring sectors.",
            fields: [
              {
                label: "Receives",
                value: "Men, powder, food and intelligence",
              },
              { label: "Controls", value: "Road, crossing and warning range" },
            ],
            outcome:
              "The attacker must besiege, divert or expose his own supply line.",
            points: [
              {
                id: "magazine",
                label: "Magazine",
                detail: "Stored endurance",
                x: 59,
                y: 44,
              },
              {
                id: "fortress",
                label: "Fortress",
                detail: "Defended corridor",
                x: 75,
                y: 34,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "garrison-patrol",
            label: "Extend the watch",
            period: "Every day",
            kicker: "The line becomes active",
            detail:
              "Garrison patrols and village scouts connect posts, report movement and light the warning chain before a raid reaches the interior.",
            fields: [
              { label: "Action", value: "Watch, patrol, signal and assemble" },
              { label: "Reach", value: "From one wall to a defended belt" },
            ],
            outcome:
              "Land, liberty, finance and service operate as one living frontier.",
            points: [
              {
                id: "village",
                label: "Village",
                detail: "Armed households",
                x: 30,
                y: 72,
              },
              {
                id: "beacon",
                label: "Beacon",
                detail: "Rapid warning",
                x: 55,
                y: 25,
              },
              {
                id: "fortress",
                label: "Fortress",
                detail: "Garrison response",
                x: 75,
                y: 34,
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
      id: "malta-holds-four-months",
      actId: "europe-becomes-fortress",
      order: 11,
      period: "May–September AD 1565",
      place: "Malta",
      title: "Malta Holds Four Months",
      thesis:
        "A small island’s fortified harbours, inhabitants and relief route denied Ottoman mastery of the central Mediterranean.",
      body: [
        "An Ottoman fleet reached Malta in May 1565 carrying soldiers, guns and the expectation that the Hospitaller base could be removed before Sicily intervened. Control of Malta would strengthen the sea road between Ottoman North Africa and the Levant. The order had raided Muslim shipping from the island since losing Rhodes. Piyale Pasha and Mustafa Pasha now brought imperial sea power against its harbours. Their first great target was St Elmo, the fort commanding the entrances between the main anchorages.",
        "St Elmo fell after weeks of bombardment and assault, but its defence consumed time and experienced Ottoman men, including the corsair commander Dragut. Every day bought Sicily more time for its response. Across the water, Birgu and Senglea prepared for the main attack. Knights, Maltese inhabitants, soldiers, sailors and enslaved galley labourers carried earth, repaired walls, served guns, treated wounds and fought at breaches. Cisterns held water inside the stone perimeter; chains and guns contested the harbour; messages crossed to Sicily asking for relief.",
        "Assault after assault failed to break the inner positions before the campaigning season closed. A relief force from Sicily landed in September and moved toward the exhausted siege army. The Ottomans withdrew after four months from an island they had expected to overwhelm. Malta survived because fortification, labour, stored water, naval geography and a European relief route held together under savage pressure. The defenders had denied the sultan a central base and proved that an island smaller than his field of operations could arrest an empire.",
      ],
      image: `${imageRoot}/11-malta-holds-four-months.avif`,
      imageAlt:
        "The harbour forts of St Elmo, Birgu and Senglea surround dark water beside a cistern, repaired breach and the approaching relief route from Sicily.",
      imagePosition: "61% center",
      mobileImagePosition: "67% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "island-fortress",
      side: "left",
      sourceIds: ["allen-2015", "agoston-2021"],
      evidence: [
        "The siege lasted from May into September 1565, with St Elmo’s costly defence preceding repeated attacks on Birgu and Senglea.",
        "Fortifications, water and powder stores, local labour and the arrival of a Sicilian relief force together explain the failure of the Ottoman expedition.",
      ],
      map: { x: 49, y: 76 },
    },
    {
      id: "lepanto-breaks-battle-fleet",
      actId: "coalition-turns-line",
      order: 12,
      period: "7 October AD 1571",
      place: "Gulf of Patras",
      title: "Lepanto Breaks the Battle Fleet",
      thesis:
        "The Holy League united Europe’s galley powers and destroyed the Ottoman fleet assembled before it.",
      body: [
        "The Ottoman invasion of Venetian Cyprus forced old rivals into coalition. Pope Pius V joined Spain, Venice, the papal states, Genoese commanders and other Italian powers in the Holy League. Don John of Austria took command of a fleet whose crews spoke different languages and whose governments distrusted one another. Common danger gave them an order of battle. On 7 October 1571, they met the Ottoman fleet at the entrance to the Gulf of Patras.",
        "The League placed heavy Venetian galleasses ahead of its line and organised centre, wings and reserve for a close galley fight. The formations survived collision because captains understood the common plan. Cannon fire broke formations before soldiers grappled, boarded and fought deck by deck. Don John held the centre; Venetian and allied squadrons survived crisis on the wings; Álvaro de Bazán committed the reserve where it could decide the struggle. The Ottoman commander Ali Pasha was killed, his flagship taken and most of the battle fleet captured, sunk or driven ashore.",
        "Thousands of Christian galley slaves came out of chains aboard captured vessels. News travelled through Europe in celebration. The Ottoman government built new hulls with impressive speed and retained Cyprus, but timber could not immediately replace the experienced commanders, archers, marines and oarsmen lost in one day. Lepanto ended the aura of inevitable Ottoman victory at sea and denied an uncontested conquest route into the western Mediterranean. Europe had answered an imperial fleet with a greater act of coalition, discipline and controlled violence on the water.",
      ],
      image: `${imageRoot}/12-lepanto-breaks-battle-fleet.avif`,
      imageAlt:
        "The Holy League centre, wings, reserve and galleasses close with the Ottoman fleet above the oar benches of newly freed captives.",
      imagePosition: "59% center",
      mobileImagePosition: "66% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "galley-coalition",
      side: "right",
      sourceIds: ["capponi-2006", "agoston-2021"],
      evidence: [
        "The Holy League combined Spanish, Venetian, papal, Genoese and other Italian forces under Don John of Austria in a coordinated battle formation.",
        "The Ottoman navy replaced ships after Lepanto and retained Cyprus, while the battle destroyed a major concentration of trained personnel and secured the western coalition’s maritime position.",
      ],
      map: { x: 59, y: 72 },
    },
    {
      id: "roads-converge-vienna",
      actId: "coalition-turns-line",
      order: 13,
      period: "July–12 September AD 1683",
      place: "Vienna and the Kahlenberg",
      title: "The Roads Converge at Vienna",
      thesis:
        "Vienna’s prolonged defence bought the time required for a multinational European relief army to assemble and strike.",
      body: [
        "Kara Mustafa Pasha’s army encircled Vienna in July 1683 and began a siege designed to open the walls from below. The Ottoman camp spread along the approaches and cut the city off from ordinary relief. Ottoman miners drove galleries toward bastions while artillery and trenches covered the work. Ernst Rüdiger von Starhemberg commanded soldiers, militia and citizens inside a city stripped for defence. Men countermined, rebuilt earth behind damaged masonry and fought over craters while food, ammunition, health and sleep diminished together.",
        "The weeks gained at the wall summoned Europe to the Danube. Imperial forces under Charles of Lorraine manoeuvred north of the river. Bavarian, Saxon, Franconian, Swabian and other German contingents joined them; King John III Sobieski brought the Polish army south. Each contingent kept its command, colours and pride inside the new allied order. Diplomacy settled command, bridges moved men across the Danube and the separate roads met on the Kahlenberg. The coalition existed because the city had denied Kara Mustafa the quick capitulation his campaign required.",
        "On 12 September, the relief army descended from the heights. German and imperial infantry fought through villages and broken ground while the Poles advanced on the allied right. By evening, a vast cavalry charge led by Sobieski’s horsemen drove into the Ottoman position as the garrison struck outward. The siege army abandoned its camp and withdrew from Vienna. A city had endured long enough for kingdoms and imperial estates to become one field army. Defence now possessed the force to pursue.",
      ],
      image: `${imageRoot}/13-roads-converge-vienna.avif`,
      imageAlt:
        "Mine tunnels approach Vienna’s walls while Polish, imperial and German relief routes converge beyond the Danube on the Kahlenberg.",
      imagePosition: "61% center",
      mobileImagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "vienna-relieved",
      side: "left",
      sourceIds: ["stoye-2006", "bassett-2015", "agoston-2021"],
      evidence: [
        "Vienna’s garrison resisted Ottoman mining and assault from July until 12 September, preserving the city while the relief coalition assembled.",
        "Polish, imperial and numerous German forces crossed north of the Danube and attacked from the Kahlenberg under an agreed coalition command.",
      ],
      map: { x: 51, y: 55 },
    },
    {
      id: "frontier-turns",
      actId: "coalition-turns-line",
      order: 14,
      period: "AD 1683–1699",
      place: "Buda, Zenta and Karlowitz",
      title: "The Frontier Turns",
      thesis:
        "Vienna opened a sustained coalition offensive that recovered Hungary and fixed a new south-eastern frontier by treaty.",
      body: [
        "The relief of Vienna opened a campaign beyond the old wall. In 1684, the Habsburg monarchy, Poland-Lithuania, Venice and the papacy formed the Holy League; Russia joined the war in 1686. The agreement bound political wills as firmly as any field fortification. Armies, fleets, taxes and diplomacy now sustained offensives across several fronts. Buda fell after a hard siege in 1686, ending a century and a half of Ottoman rule in the former Hungarian capital and opening the middle Danube to further recovery.",
        "Imperial victories drove the frontier through Hungary and Transylvania. Command, magazines, river transport and the fiscal strength of many Habsburg lands kept armies in the field beyond one campaigning season. The counteroffensive had learned to make victory cumulative. At Zenta in 1697, Eugene of Savoy caught the Ottoman army while it crossed the Tisza and destroyed its vulnerable centre at the river. The victory removed the sultan’s ability to restore the old line by another great offensive and made negotiation unavoidable.",
        "At Karlowitz in 1699, diplomats converted battlefield recovery into a recognised frontier. The settlement recognised Habsburg possession of most of Ottoman Hungary, Transylvania and Slavonia; Poland-Lithuania recovered Podolia, and Venice secured the Morea and gains in Dalmatia. Survey, protocol and seal followed victorious cannon southward. Ottoman sovereignty remained powerful beyond the new boundary, but its long westward advance had ended. The same Europe that once held fragments in Asturian valleys now set terms after victory on the Danube. The hinge had turned from survival to recovery.",
      ],
      image: `${imageRoot}/14-frontier-turns.avif`,
      mobileImage: `${imageRoot}/14-frontier-turns-mobile.avif`,
      imageAlt:
        "A folding frontier atlas rotates south-east from Vienna through recovered Buda and Zenta toward the treaty table at Karlowitz.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "frontier-hinge-turns",
      side: "right",
      sourceIds: ["agoston-2021", "yaycioglu-2025", "bassett-2015"],
      evidence: [
        "The Holy League carried the war beyond Vienna; Buda fell in 1686 and Eugene of Savoy’s victory at Zenta in 1697 broke a major Ottoman field army.",
        "The Karlowitz settlements recognised major territorial transfers to the Habsburg monarchy, Poland-Lithuania and Venice while leaving the Banat under Ottoman rule.",
      ],
      map: { x: 58, y: 62 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "frontier-hinge",
        prompt: "Turn the frontier",
        accessibleSummary:
          "Five dated plates unlock the relief of Vienna, the Holy League, Buda, Zenta and Karlowitz until the direction of strategic pressure rotates south-east.",
        initialId: "vienna-relieved",
        mapImage: `${imageRoot}/14-frontier-turns.avif`,
        records: [
          {
            id: "vienna-relieved",
            label: "Relieve Vienna",
            period: "12 September AD 1683",
            kicker: "The hinge holds",
            detail:
              "The coalition descent from the Kahlenberg breaks the siege and preserves the base from which a counteroffensive can begin.",
            fields: [
              { label: "Pressure", value: "Ottoman advance reaches Vienna" },
              {
                label: "European act",
                value: "City defence and coalition relief",
              },
              { label: "Hinge state", value: "Held at the Danube" },
            ],
            outcome: "The road west closes and the road of pursuit opens.",
            points: [
              {
                id: "vienna",
                label: "Vienna",
                detail: "Siege relieved",
                x: 27,
                y: 28,
              },
            ],
          },
          {
            id: "holy-league",
            label: "Form the League",
            period: "AD 1684–1686",
            kicker: "Relief becomes an institution",
            detail:
              "Habsburg, Polish-Lithuanian, Venetian and papal commitments, later joined by Russia, sustain war on several fronts.",
            fields: [
              { label: "Pressure", value: "One siege has ended" },
              {
                label: "European act",
                value: "Treaty, finance and common campaign",
              },
              { label: "Hinge state", value: "Released for movement" },
            ],
            outcome:
              "The coalition can continue after the armies of 1683 go home.",
            points: [
              {
                id: "vienna",
                label: "Vienna",
                detail: "Habsburg base",
                x: 27,
                y: 28,
              },
              {
                id: "venice",
                label: "Venice",
                detail: "Maritime front",
                x: 20,
                y: 54,
              },
              {
                id: "poland",
                label: "Poland-Lithuania",
                detail: "Northern ally",
                x: 54,
                y: 13,
              },
            ],
            links: [
              [1, 0],
              [2, 0],
            ],
          },
          {
            id: "buda-recovered",
            label: "Recover Buda",
            period: "2 September AD 1686",
            kicker: "The line moves downriver",
            detail:
              "A sustained siege takes the former Hungarian capital and gives coalition armies a commanding base on the middle Danube.",
            fields: [
              { label: "Pressure", value: "Ottoman defence of Hungary" },
              { label: "European act", value: "Siege, supply and occupation" },
              { label: "Hinge state", value: "Turning south-east" },
            ],
            outcome:
              "Recovered ground becomes the platform for the next campaign.",
            points: [
              {
                id: "vienna",
                label: "Vienna",
                detail: "Supply base",
                x: 27,
                y: 28,
              },
              {
                id: "buda",
                label: "Buda",
                detail: "Recovered capital",
                x: 45,
                y: 45,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "zenta",
            label: "Win at Zenta",
            period: "11 September AD 1697",
            kicker: "The field army breaks",
            detail:
              "Eugene of Savoy strikes the Ottoman army during its river crossing and destroys the force capable of reversing the recovery.",
            fields: [
              { label: "Pressure", value: "Attempted Ottoman restoration" },
              {
                label: "European act",
                value: "Intelligence, march and decisive attack",
              },
              { label: "Hinge state", value: "Turn completed in war" },
            ],
            outcome:
              "The recovered frontier can now be carried to negotiation from strength.",
            points: [
              {
                id: "buda",
                label: "Buda",
                detail: "Recovered base",
                x: 45,
                y: 45,
              },
              {
                id: "zenta",
                label: "Zenta",
                detail: "Decisive river victory",
                x: 62,
                y: 69,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "karlowitz",
            label: "Fix the frontier",
            period: "26 January AD 1699",
            kicker: "Diplomacy locks the turn",
            detail:
              "The negotiated settlement recognises recovered territory and replaces a moving war zone with a new political boundary.",
            fields: [
              { label: "Pressure", value: "Westward advance ended" },
              {
                label: "European act",
                value: "Coalition gains written into treaty",
              },
              { label: "Hinge state", value: "Fixed toward the south-east" },
            ],
            outcome:
              "A frontier once defended at Vienna now lies beyond most of Hungary.",
            points: [
              {
                id: "vienna",
                label: "Vienna",
                detail: "Surviving capital",
                x: 27,
                y: 28,
              },
              {
                id: "buda",
                label: "Buda",
                detail: "Recovered Hungary",
                x: 45,
                y: 45,
              },
              { id: "zenta", label: "Zenta", detail: "Victory", x: 62, y: 69 },
              {
                id: "karlowitz",
                label: "Karlowitz",
                detail: "Treaty frontier",
                x: 72,
                y: 60,
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
