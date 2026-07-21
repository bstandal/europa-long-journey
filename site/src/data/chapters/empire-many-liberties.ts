import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/empire-many-liberties";

export const empireManyLiberties: ChapterDefinition = {
  slug: "empire-many-liberties",
  number: "12",
  title: "The Empire of Many Liberties",
  openingTitleLines: ["The Empire", "of Many Liberties"],
  period: "AD 962–1806",
  claim:
    "The Holy Roman Empire held central Europe together through election, privilege, assembly and law. Its many rulers and communities kept real liberties because they belonged to a common imperial peace.",
  openingClaim:
    "Central Europe made liberty durable by placing many governments inside one imperial order.",
  hero: {
    image: `${imageRoot}/08-diet-in-session.avif`,
    mobileImage: `${imageRoot}/08-diet-in-session-mobile.avif`,
    imageAlt:
      "Electors, princes, prelates and city envoys deliberate from ranked benches around a document table in an imperial Diet.",
    imagePosition: "68% center",
    mobileImagePosition: "70% center",
    visualLabel: "Evidence-led reconstruction · the Diet in session",
  },
  theme: {
    id: "imperial-diet",
    label: "The Diet in session",
  },
  openingAction: "Enter the imperial assembly",
  mapLabel:
    "The crowns, charters, cities, courts and assemblies that held the imperial mosaic together",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Coronation instruments · royal charters · city laws · the Golden Bull · Diet records · imperial reforms · peace settlements · court judgments",
  acts: [
    {
      id: "crown-travels",
      number: "I",
      label: "The crown travels",
      period: "AD 962–1250",
      title: "The Crown Travels",
      detail:
        "Coronation, royal itinerary and the sealed charter bind a realm whose ruler has no permanent imperial capital.",
    },
    {
      id: "liberty-becomes-right",
      number: "II",
      label: "Liberty becomes a right",
      period: "c. AD 1100–1356",
      title: "Liberty Becomes a Right",
      detail:
        "Cities, princes and electors turn accumulated privileges into portable law, territorial authority and an ordered elective crown.",
    },
    {
      id: "realm-reforms-itself",
      number: "III",
      label: "The realm reforms itself",
      period: "AD 1489–1521",
      title: "The Realm Reforms Itself",
      detail:
        "The Diet, the Perpetual Public Peace, the Imperial Chamber Court and the Circles give common procedure to a realm of many governments.",
    },
    {
      id: "difference-inside-peace",
      number: "IV",
      label: "Difference remains inside the peace",
      period: "AD 1555–1806",
      title: "Difference Remains Inside the Peace",
      detail:
        "Augsburg, Westphalia and the Perpetual Diet preserve an imperial constitution across confessional and dynastic division.",
    },
  ],
  ending: {
    period: "AD 1806",
    title: "Liberty Has Learned to Live Inside Order",
    detail:
      "The crown was laid down, but the habits formed beneath it survived in city halls, territorial governments, archives and courts. Central Europe had spent eight centuries learning how unequal powers could defend their own rights, submit disputes to common judgment and act together without surrendering every difference. The next trial came at Europe’s southern and eastern walls, where this civilisation of kingdoms, cities and estates had to find soldiers, ships, fortresses and money quickly enough to survive attack.",
    image: `${imageRoot}/13-many-liberties-endure.avif`,
    nextPeriod: "AD 711–1699",
  },
  returnHash: "empire-many-liberties",
  nextHash: "frontiers-hold",
  nextTitle: "The Frontiers Hold",
  nextSlug: "europe-holds-the-line",
  movements: [
    {
      id: "rome-crowns-saxon",
      actId: "crown-travels",
      order: 1,
      period: "2 February AD 962",
      place: "Old St Peter’s · Rome",
      title: "Rome Crowns a Saxon",
      thesis:
        "Otto I joined German kingship, Italian rule and the western Roman office beneath one crown.",
      body: [
        "On 2 February 962, Pope John XII placed the imperial crown on Otto I in Old St Peter’s. Otto had crossed the Alps as king of East Francia and Italy, victorious over rival magnates and Magyar raiders. He knelt in the basilica of the apostle and rose as emperor, while his wife Adelaide received the imperial crown beside him. A Saxon dynasty now held the western Roman office. The rite gave lands north and south of the Alps a common summit whose authority reached beyond any one duchy or kingdom.",
        "The crown did not conjure a uniform state. Otto ruled through dukes, counts, bishops, abbots, royal lands and assemblies whose rights differed from place to place. He issued diplomas, confirmed possessions, judged disputes and appointed men capable of carrying his authority when he moved elsewhere. In Italy he required cooperation from bishops, cities and nobles; in Saxony and Franconia he relied on aristocratic households with power of their own. Imperial government lived in these relationships, and the Roman title raised their ruler above the several crowns and lordships that sustained him.",
        "The imperial office joined memory to ambition. It recalled Charlemagne, Christian Rome and the duty to defend the western church; it also demanded repeated journeys across difficult country. Every coronation, assembly and charter renewed a bond that geography continually stretched. The Empire therefore began as a union of rank, law and presence rather than as a capital commanding provinces. Its first durable achievement was to place a multitude of inherited powers beneath an office none of them could wholly possess. The crown stood still only during the ceremony. To govern, it had to travel.",
      ],
      image: `${imageRoot}/01-rome-crowns-saxon.avif`,
      imageAlt:
        "Otto I and Adelaide receive the imperial crowns in the lamplit nave of Old St Peter’s as a road-worn Saxon retinue looks on.",
      imagePosition: "57% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "crown-and-smoke",
      side: "left",
      sourceIds: ["wilson-2016", "stollberg-rilinger-2018"],
      evidence: [
        "The coronation of Otto I and Adelaide at Rome in 962 united the East Frankish, Italian and imperial titles in the Ottonian house.",
        "Ottonian rule operated through itinerant lordship, assemblies, ecclesiastical institutions and written privileges rather than a permanent central administration.",
      ],
      map: { x: 48, y: 67 },
    },
    {
      id: "crown-has-no-capital",
      actId: "crown-travels",
      order: 2,
      period: "tenth–thirteenth centuries",
      place: "Aachen · Goslar · Frankfurt · Regensburg",
      title: "The Crown Has No Capital",
      thesis:
        "An imperial road of assemblies, judgments and charters governed a realm without a permanent seat.",
      body: [
        "The imperial household arrived before the emperor. Clerks carried seals and writing chests; servants arranged fodder, food and lodging; petitioners gathered at the next palace, abbey or episcopal city. Aachen supplied the memory of Charlemagne, Goslar the wealth and royal presence of Saxony, Frankfurt a meeting place on the Main and Regensburg a gate to Bavaria and the Danube. None became an imperial capital. The ruler consumed the resources of one centre, celebrated the great feasts, heard business and moved toward another.",
        "Presence turned a hall into a seat of government. The king or emperor received homage, invested a bishop, reconciled princes, settled a boundary or summoned men for an Italian expedition. His court drew local quarrels upward because a judgment pronounced before the ruler carried the weight of the realm. The meeting also gave magnates a place to bargain over service and reward. Ceremony arranged rank in public: who approached first, who held a sword, who sat near the ruler and whose seal appeared on the resulting instrument all expressed the constitution in action.",
        "Writing remained after the horses departed. A charter preserved a grant; a witness list fixed the company that had seen it; a monastery or city guarded the parchment and produced it when the crown returned in another man’s hands. Successive rulers governed through this accumulated memory, confirming old privileges as they requested new aid. The road joined personal kingship to durable law. Because the crown could not watch every valley, it made distant institutions responsible for keeping what it had declared. The absence of a capital gave the Empire a moving centre and taught authority to leave a written trace wherever it passed.",
      ],
      image: `${imageRoot}/02-crown-has-no-capital.avif`,
      imageAlt:
        "An imperial household with clerks, seal chests and pack animals leaves a royal hall for the next city on the ruler’s itinerary.",
      imagePosition: "56% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "charter-road",
      side: "right",
      sourceIds: ["wilson-2016", "stollberg-rilinger-2018"],
      evidence: [
        "Royal and imperial diplomas, witness lists and dated itineraries record a court moving repeatedly among palaces, monasteries and cities.",
        "Assemblies combined judgment, patronage, ritual and negotiation; sealed instruments extended the consequence of a ruler’s visit beyond his departure.",
      ],
      map: { x: 46, y: 50 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "imperial-itinerary",
        prompt: "Carry the crown",
        accessibleSummary:
          "Four stops follow an itinerant ruler through Aachen, Goslar, Regensburg and Frankfurt, showing the act and written trace left at each place.",
        mapImage: "assets/europe-relief.webp",
        initialId: "aachen-memory",
        records: [
          {
            id: "aachen-memory",
            label: "Aachen",
            period: "Royal feast",
            kicker: "Memory gives rank",
            detail:
              "The ruler enters Charlemagne’s palace church, receives petitioners and places the present reign inside an imperial memory.",
            fields: [
              {
                label: "Presence",
                value: "Feast, audience and public hierarchy",
              },
              {
                label: "Trace",
                value: "Confirmed privilege under the royal seal",
              },
            ],
            outcome:
              "The court moves on; the confirmation remains in the recipient’s archive.",
            points: [
              {
                id: "aachen",
                label: "Aachen",
                detail: "Imperial memory",
                x: 41,
                y: 48,
              },
            ],
            links: [],
          },
          {
            id: "goslar-resources",
            label: "Goslar",
            period: "Palace assembly",
            kicker: "Resources sustain presence",
            detail:
              "At the Saxon palace, the household draws provisions, meets regional princes and hears claims tied to royal lands and mines.",
            fields: [
              { label: "Presence", value: "Hospitality, counsel and judgment" },
              {
                label: "Trace",
                value: "A witnessed grant naming the assembled court",
              },
            ],
            outcome:
              "A local centre supplies imperial government without becoming its permanent capital.",
            points: [
              {
                id: "aachen",
                label: "Aachen",
                detail: "Previous court",
                x: 41,
                y: 48,
              },
              {
                id: "goslar",
                label: "Goslar",
                detail: "Palace assembly",
                x: 47,
                y: 44,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "regensburg-command",
            label: "Regensburg",
            period: "Danube council",
            kicker: "The road gathers service",
            detail:
              "Bavarian and eastern business reaches the ruler at a Danube city where men, money and appointments can be assembled.",
            fields: [
              {
                label: "Presence",
                value: "Council, investiture and military summons",
              },
              {
                label: "Trace",
                value: "Appointments and duties fixed in writing",
              },
            ],
            outcome:
              "The travelling household converts regional power into a command of the realm.",
            points: [
              {
                id: "aachen",
                label: "Aachen",
                detail: "Imperial memory",
                x: 41,
                y: 48,
              },
              {
                id: "goslar",
                label: "Goslar",
                detail: "Saxon palace",
                x: 47,
                y: 44,
              },
              {
                id: "regensburg",
                label: "Regensburg",
                detail: "Danube council",
                x: 50,
                y: 53,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "frankfurt-judgment",
            label: "Frankfurt",
            period: "Realm assembly",
            kicker: "The circuit closes in law",
            detail:
              "At the Main crossing, princes and envoys hear a settlement whose witnesses connect the ruler’s journey to an enforceable memory.",
            fields: [
              {
                label: "Presence",
                value: "Assembly, settlement and renewed allegiance",
              },
              {
                label: "Trace",
                value: "Judgment, witness list and sealed charter",
              },
            ],
            outcome:
              "The crown leaves no capital behind; it leaves a chain of recognised acts.",
            points: [
              {
                id: "aachen",
                label: "Aachen",
                detail: "Imperial memory",
                x: 41,
                y: 48,
              },
              {
                id: "goslar",
                label: "Goslar",
                detail: "Saxon palace",
                x: 47,
                y: 44,
              },
              {
                id: "regensburg",
                label: "Regensburg",
                detail: "Danube council",
                x: 50,
                y: 53,
              },
              {
                id: "frankfurt",
                label: "Frankfurt",
                detail: "Realm assembly",
                x: 44,
                y: 50,
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
      id: "rights-accumulate",
      actId: "liberty-becomes-right",
      order: 3,
      period: "eleventh–thirteenth centuries",
      place: "Central Europe",
      title: "Rights Accumulate",
      thesis:
        "Privilege, inheritance and custom gave the Empire a constitution built from possession rather than uniform command.",
      body: [
        "A traveller crossing the Empire passed through jurisdictions that could change within a day. A duke commanded one road, a bishop held the next market, an abbey possessed immunity around its estates and a city judged its citizens under a charter. Counts, cathedral chapters, knightly lords and village communities exercised powers acquired at different dates and from different sources. These rights overlapped because property, office and lordship did not occupy identical borders. The imperial map grew from documents and remembered usage rather than from straight administrative lines.",
        "Each liberty had a material form. A charter exempted an abbey from an officer’s interference. A mint die expressed the right to coin. A toll gate turned passage into revenue. A wall embodied a city’s power to guard its peace. Holders carried such claims before rulers and courts, displayed old seals and sought confirmation from each new reign. Rights could be contested, inherited, divided, pledged or forfeited. Their endurance depended on recognition, which drew even powerful local rulers back toward the legal summit of the Empire.",
        "The mosaic multiplied centres of initiative. A bishop could found a market, a prince police a territory and a town regulate trades without waiting for one imperial ministry. Smaller bodies valued the realm because its law could protect their distinct standing against a stronger neighbour. Greater rulers valued titles and privileges that elevated their authority above ordinary lordship. The Empire held these possessions together by allowing difference to become constitutional. Its unity did not require every place to be governed alike. It required powers to know what they held, from whom they held it and where a dispute could be carried when local strength was not enough.",
      ],
      image: `${imageRoot}/03-rights-accumulate.avif`,
      imageAlt:
        "A relief map of central Europe is assembled from an abbey charter, a city seal, a princely toll record and local boundary marks.",
      imagePosition: "53% center",
      visualLabel: "Documentary reconstruction",
      visualTone: "chartered-mosaic",
      side: "left",
      sourceIds: ["wilson-2016", "stollberg-rilinger-2018", "whaley-2012"],
      evidence: [
        "Imperial charters and territorial archives preserve immunities, regalian rights, judicial powers and local customs held by many kinds of institution.",
        "Imperial status depended on recognised legal relationships; the realm’s jurisdictions were layered and unequal rather than uniform territorial provinces.",
      ],
      map: { x: 48, y: 50 },
    },
    {
      id: "city-sends-law-east",
      actId: "liberty-becomes-right",
      order: 4,
      period: "c. AD 1188–1400",
      place: "Magdeburg · Central and Eastern Europe",
      title: "A City Sends Its Law East",
      thesis:
        "Magdeburg law carried a tested form of urban self-government across political borders.",
      body: [
        "Magdeburg stood where the Elbe opened routes toward the east. Its merchants, householders and judges lived under privileges associated with Archbishop Wichmann’s charter of 1188 and the legal practice that grew around it. The city’s law ordered property, inheritance, debt, trade and municipal judgment. It gave settlers and rulers a worked example of how a town could govern everyday disputes through its own court while remaining inside a larger lordship. The value lay in the form’s capacity to be copied, adapted and recognised.",
        "Founders granted related law to new and expanding towns across Silesia, Bohemia, Poland and lands farther east. Receiving towns did not become colonies of Magdeburg, and their charters did not reproduce every rule word for word. They joined a legal family. When uncertainty arose, courts could seek an opinion from the Magdeburg bench or from an intermediate mother city whose law descended from the same stock. Written questions travelled west; reasoned answers returned to market squares governed by different princes and speaking several languages.",
        "A civic institution had acquired a reach greater than its walls. The route spread habits of elected or appointed urban office, recorded procedure, protected possession and commercial judgment. Local rulers welcomed towns capable of attracting settlers, collecting revenue and keeping an ordered market. Towns valued a law that distinguished their corporate rights from the surrounding countryside. The Empire’s plurality became a means of transmission: one city’s tested liberty could move through grants and legal consultation without requiring a single code imposed from above. Magdeburg sent no governor with its book. The book taught distant communities how to stand as cities in their own right.",
      ],
      image: `${imageRoot}/04-city-sends-law-east.avif`,
      imageAlt:
        "Clerks copy a Magdeburg law book as its ruled margin extends toward distinct town gates and seals across central and eastern Europe.",
      imagePosition: "58% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "law-road-east",
      side: "right",
      sourceIds: ["wilson-2016", "stollberg-rilinger-2018", "luck-2014"],
      evidence: [
        "Town charters, legal compilations and requests for judgments document a broad family of Magdeburg law across central and eastern Europe.",
        "Receiving towns adapted the model under local rulers; legal consultation joined them without creating a uniform imperial code.",
      ],
      map: { x: 50, y: 46 },
    },
    {
      id: "princes-hold-realm",
      actId: "liberty-becomes-right",
      order: 5,
      period: "AD 1220–1232",
      place: "Royal assemblies in Germany",
      title: "Princes Hold the Realm in Their Own Right",
      thesis:
        "Frederick II gave stronger legal form to princely powers that imperial government already needed.",
      body: [
        "Frederick II ruled an extraordinary collection of lands: Sicily, Germany, northern Italy and an imperial claim reaching to Rome. Distance made the cooperation of German princes indispensable. In 1220 he confirmed powers of ecclesiastical princes while securing the election of his son Henry as king. In 1232 he accepted a comparable settlement with secular princes. Courts, tolls, mints, markets, fortifications and territorial commands received stronger protection. The instruments exchanged princely support for a clearer possession of government within their lands.",
        "The grants did not release princes from the Empire. Their rank, fiefs and public rights remained part of imperial law, and their greatest occasions still drew them to the king’s court. A prince exercised authority in his own right while serving in assemblies, expeditions, elections and judgments that belonged to the whole realm. The settlement made this dual position explicit. Imperial government would act through territorial rulers who were partners with interests to defend, not removable officials posted from a central capital.",
        "That arrangement created durable political depth. A princely court could collect revenue, keep records, hear appeals and command armed men close to the people and resources concerned. The crown retained the power to confirm rank, settle disputes and summon common action. Each level possessed capacities the other lacked. Germany therefore developed governments beneath the imperial summit rather than a bureaucracy descending from it. The result gave ambitious dynasties room to build, but it also tied their authority to a constitutional order shared with bishops, counts and cities. The prince became powerful inside the realm because his powers had become a recognised part of the realm.",
      ],
      image: `${imageRoot}/05-princes-hold-realm.avif`,
      imageAlt:
        "Frederick II presents a sealed charter to spiritual and temporal princes beside a mint die, toll book, court staff and fortification plan.",
      imagePosition: "58% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "granted-command",
      side: "left",
      sourceIds: ["wilson-2016", "stollberg-rilinger-2018", "whaley-2012"],
      evidence: [
        "The 1220 and 1232 instruments confirmed judicial, fiscal and territorial rights of ecclesiastical and secular princes in exchange for political support.",
        "Princely authority remained embedded in imperial titles, fiefs, assemblies and law rather than becoming independent sovereignty.",
      ],
      map: { x: 48, y: 51 },
    },
    {
      id: "seven-electors-make-one-king",
      actId: "liberty-becomes-right",
      order: 6,
      period: "AD 1356",
      place: "Nuremberg · Metz · Frankfurt",
      title: "Seven Electors Make One King",
      thesis:
        "The Golden Bull made an elective crown more durable by giving succession a binding procedure.",
      body: [
        "A contested election could divide the Empire before a reign had begun. Charles IV answered with the Golden Bull, issued through the Diets of Nuremberg and Metz in 1356. It identified seven electors: the archbishops of Mainz, Trier and Cologne, and the king of Bohemia, count palatine of the Rhine, duke of Saxony and margrave of Brandenburg. Their electoral lands were to pass undivided, preserving the offices on which the choice depended. The crown remained elective, but the electorate now had a written shape.",
        "The Bull directed the electors to Frankfurt under sworn safe conduct. The archbishop of Mainz summoned them; the city controlled armed entry; the electors swore to choose without corrupt bargain. A majority could bind the whole college, preventing a minority from producing a rival king. If no choice had been made within thirty days, the electors were to receive only bread and water until they completed their duty. Coronation belonged at Aachen, and the first royal Diet at Nuremberg. Place, time and sequence turned succession into public law.",
        "Each elector also carried a ceremonial office that displayed his place in the constitution. At a solemn court the temporal electors bore cup, platter, sceptre or sword; the archbishops held the chancellorships associated with the Empire’s great kingdoms. Ceremony made the college visible before the realm, while procedure restrained the dynastic struggle within it. No emperor could simply bequeath the imperial title as private property. Seven unequal rulers, spiritual and temporal, had to make one king through an act recognised by them all.",
      ],
      image: `${imageRoot}/06-seven-electors-one-king.avif`,
      imageAlt:
        "Three archbishops and four temporal electors occupy ranked places around a horseshoe table with the Golden Bull open before them.",
      imagePosition: "60% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "golden-procedure",
      side: "right",
      sourceIds: ["golden-bull-1356", "stollberg-rilinger-2018", "wilson-2016"],
      evidence: [
        "The Golden Bull names the seven electors, protects the indivisibility of their electoral territories and prescribes the Frankfurt election.",
        "Its majority rule, safe-conduct duties, timetable and ceremonial offices gave contested succession a recognised constitutional sequence.",
      ],
      map: { x: 44, y: 50 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "electoral-college",
        prompt: "Elect without a dynasty",
        accessibleSummary:
          "Five procedural states show the seven named electors reaching Frankfurt under protection, taking an oath, deciding by majority and producing one King of the Romans.",
        initialId: "summon-seven",
        records: [
          {
            id: "summon-seven",
            label: "Summon",
            period: "The vacancy",
            kicker: "The office calls its electors",
            detail:
              "The archbishop of Mainz summons the three spiritual and four temporal electors named by the Golden Bull.",
            fields: [
              { label: "Spiritual", value: "Mainz · Trier · Cologne" },
              {
                label: "Temporal",
                value: "Bohemia · Palatinate · Saxony · Brandenburg",
              },
            ],
            outcome:
              "The right of election belongs to defined offices, not to the late king’s household.",
          },
          {
            id: "secure-frankfurt",
            label: "Protect",
            period: "Frankfurt",
            kicker: "The city holds the peace",
            detail:
              "Safe conducts protect each elector’s road, while Frankfurt restricts armed entry and guards the place of election.",
            fields: [
              { label: "Escort", value: "Assigned by the territories crossed" },
              {
                label: "City duty",
                value: "Secure the electors and exclude rival forces",
              },
            ],
            outcome:
              "The choice begins inside a protected civic space rather than on a battlefield.",
          },
          {
            id: "swear-election",
            label: "Swear",
            period: "Before deliberation",
            kicker: "The college accepts one duty",
            detail:
              "Each elector swears to choose the temporal head of Christendom according to judgment and without a corrupt agreement.",
            fields: [
              { label: "Electors", value: "Seven offices with one vote each" },
              {
                label: "Limit",
                value: "No hereditary claim decides the crown",
              },
            ],
            outcome:
              "Rank remains unequal across the Empire; within this act the seven votes are defined.",
          },
          {
            id: "reach-majority",
            label: "Decide",
            period: "Within thirty days",
            kicker: "A majority closes the contest",
            detail:
              "Four votes elect one King of the Romans. A minority cannot answer with a second valid king under the same procedure.",
            fields: [
              { label: "Threshold", value: "Four of seven electoral votes" },
              {
                label: "Discipline",
                value: "Bread and water after thirty days without a choice",
              },
            ],
            outcome:
              "The majority binds the electoral college and prevents a lawful double election.",
          },
          {
            id: "make-king",
            label: "Proclaim",
            period: "King of the Romans",
            kicker: "The chosen man receives the office",
            detail:
              "The electors proclaim one king, whose coronation and first Diet follow the places ordered by the Bull.",
            fields: [
              { label: "Coronation", value: "Aachen" },
              { label: "First royal Diet", value: "Nuremberg" },
            ],
            outcome:
              "The crown passes through an election whose offices and sequence survive the dynasty that wins it.",
          },
        ],
      },
    },
    {
      id: "estates-enter-room",
      actId: "realm-reforms-itself",
      order: 7,
      period: "AD 1489–1495",
      place: "Frankfurt · Worms",
      title: "The Estates Enter the Room",
      thesis:
        "A recurring Diet gave imperial government a chamber in which unequal powers could make common business.",
      body: [
        "By the late fifteenth century, the royal court assembly had become the Reichstag, the imperial Diet. Electors arrived with the highest rank. Spiritual and temporal princes came in person or sent authorised envoys. Counts, prelates and the representatives of imperial cities brought claims shaped by their own councils and territories. Seating, procession and address preserved every distinction. The gathering did not pretend that Mainz, Saxony, a count and a small city possessed equal weight. It gave each recognised part a place from which its consent or resistance could matter.",
        "The emperor opened business through propositions: defence against France or the Ottomans, aid for an expedition, reform of coinage, suppression of feud or the collection of money. The estates withdrew into separate deliberations, compared instructions and returned with answers. Electors formed the most elevated council; the princes contained both great individual votes and grouped votes held by lesser estates; cities developed their own corporate voice without enjoying the settled standing they would secure later. Agreement emerged from communication among bodies, not from counting every person in the hall.",
        "The room transformed disagreement into a resource of government. A prince who could obstruct a levy could also make it legitimate by consenting. A city that guarded its purse supplied knowledge of roads, markets and credit. The emperor supplied the office capable of summoning the realm and confirming its common acts. Bargaining took time because the interests were real. It also produced decisions that participating powers could carry home as their own work. In the Diet, the Empire became visible to itself: a hierarchy of distinct governments gathered around one table because none could secure the common peace alone.",
      ],
      image: `${imageRoot}/07-estates-enter-room.avif`,
      imageAlt:
        "Electors, princes, prelates and city envoys take their unequal places on stepped oak benches as document bundles reach the central table.",
      imagePosition: "68% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "benches-before-consent",
      side: "left",
      sourceIds: ["wilson-2016", "stollberg-rilinger-2018", "brady-2009"],
      evidence: [
        "Late-fifteenth-century records show the court assembly becoming a more regular Diet in which imperial estates deliberated through ranked corporate groups.",
        "The colleges were unequal: electors held precedence, the Council of Princes combined different forms of vote and the cities’ decisive standing developed gradually.",
      ],
      map: { x: 43, y: 51 },
    },
    {
      id: "diet-outlaws-feud",
      actId: "realm-reforms-itself",
      order: 8,
      period: "AD 1495",
      place: "Worms",
      title: "The Diet Outlaws the Feud",
      thesis:
        "At Worms, emperor and estates replaced the lawful private feud with a public peace and a common court.",
      body: [
        "Maximilian I came to Worms seeking money and support for war. The estates arrived determined to reform the government that would demand those resources. Months of bargaining joined the two purposes. On 7 August 1495, the Diet proclaimed the Perpetual Public Peace. The older right to pursue certain quarrels by declared feud yielded to a command binding the entire German realm: no estate was to answer injury with burning, seizure or armed revenge. A political order of many jurisdictions had asserted one peace above them all.",
        "Peace required a place where conflict could go. The reform established the Imperial Chamber Court, staffed through a constitutional partnership between crown and estates. Litigants could bring territorial, property and public-law disputes before judges expected to apply recognised imperial law. Enforcement became a duty distributed among rulers, cities and later the Circles, turning judgment into common constitutional work. The court’s authority rested on a decisive conversion. A quarrel that once summoned mounted followers now generated pleadings, files, hearings and a judgment addressed to the powers of the realm.",
        "The Diet also approved the Common Penny, an attempt to distribute imperial taxation more broadly, and continued negotiation over the machinery of reform. Not every levy arrived and not every sentence was obeyed. The constitutional achievement lay in the common acts themselves. Emperor, electors, princes, prelates, counts and cities had carried rival clauses into the chamber and returned with an imperial settlement none had authored alone. The resulting recess was confirmed in the emperor’s name with the estates’ counsel and consent. Negotiation had not weakened the law. It had made a law that many governments were prepared to recognise as their own.",
      ],
      image: `${imageRoot}/08-diet-in-session.avif`,
      mobileImage: `${imageRoot}/08-diet-in-session-mobile.avif`,
      imageAlt:
        "The 1495 Diet deliberates around the Perpetual Public Peace while separate estate papers converge on a central table and weapons remain at the door.",
      imagePosition: "68% center",
      mobileImagePosition: "70% center",
      visualLabel: "Evidence-led reconstruction · Worms, 1495",
      visualTone: "agreement-in-session",
      side: "right",
      sourceIds: ["westphal-2018", "wilson-2016", "imperial-reform-1495"],
      evidence: [
        "The Diet of Worms enacted the Perpetual Public Peace, the Imperial Chamber Court and the Common Penny in 1495 through agreement between Maximilian I and the estates.",
        "The cities carried their knowledge of revenue, markets and enforcement into the Diet while the electoral and princely colleges supplied the agreement on which the reform of 1495 rested.",
      ],
      map: { x: 42, y: 51 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "imperial-decision",
        prompt: "Pass an imperial decision",
        accessibleSummary:
          "Six states carry the Perpetual Public Peace from Maximilian’s proposition through the unequal electoral, princely and city bodies, negotiated correlation and imperial confirmation.",
        initialId: "imperial-proposition",
        records: [
          {
            id: "imperial-proposition",
            label: "Proposition",
            period: "The emperor opens",
            kicker: "The common business enters the room",
            detail:
              "Maximilian places war finance and reform before the estates; their answer joins aid to a binding peace and a court capable of hearing disputes.",
            fields: [
              {
                label: "Crown seeks",
                value: "Money, military support and execution",
              },
              {
                label: "Estates seek",
                value: "Public peace, judgment and a share in government",
              },
            ],
            outcome:
              "The emperor sets the business, but his proposition does not become imperial law by command alone.",
          },
          {
            id: "electoral-council",
            label: "Electors",
            period: "First college",
            kicker: "The highest estates deliberate",
            detail:
              "The electoral council considers the proposal through seven offices whose precedence and constitutional role exceed an ordinary princely vote.",
            fields: [
              {
                label: "Members",
                value: "Three archbishops and four temporal electors",
              },
              {
                label: "Weight",
                value:
                  "The Empire’s highest college, not one bench among equals",
              },
            ],
            outcome:
              "The electors produce a corporate position for comparison with the other estates.",
          },
          {
            id: "council-of-princes",
            label: "Princes",
            period: "Second college",
            kicker: "Different ranks speak through one council",
            detail:
              "Spiritual and temporal princes deliberate beside prelates and counts whose votes are arranged by rank and, for lesser estates, often held collectively.",
            fields: [
              {
                label: "Structure",
                value: "Ecclesiastical and temporal benches",
              },
              {
                label: "Votes",
                value: "Individual princely voices and grouped curial voices",
              },
            ],
            outcome:
              "The council returns an answer shaped by rulers expected to execute the peace in their own lands.",
          },
          {
            id: "imperial-cities",
            label: "Cities",
            period: "Developing third body",
            kicker: "The civic voice enters without equal rank",
            detail:
              "Imperial cities confer over taxation, enforcement and the safety of roads while their decisive constitutional standing remains less secure than it will be after 1648.",
            fields: [
              {
                label: "Contribution",
                value: "Revenue, markets, roads and civic enforcement",
              },
              {
                label: "Standing in 1495",
                value:
                  "Present and influential through a corporate civic voice",
              },
            ],
            outcome:
              "The cities carry market, tax and enforcement knowledge into the imperial settlement through their own corporate voice.",
          },
          {
            id: "correlation",
            label: "Correlate",
            period: "Negotiated text",
            kicker: "Separate answers meet",
            detail:
              "The positions of the electors and princes are compared, civic concerns are carried into the settlement and clerks revise clauses toward common consent.",
            fields: [
              {
                label: "Accepted clause",
                value: "Private feud is forbidden throughout the realm",
              },
              {
                label: "Institution",
                value:
                  "The Imperial Chamber Court receives the displaced quarrels",
              },
            ],
            outcome:
              "No aggregate headcount decides the issue; agreement forms between constituted bodies.",
          },
          {
            id: "imperial-confirmation",
            label: "Confirm",
            period: "Imperial recess",
            kicker: "Consent returns to the crown",
            detail:
              "The agreed text returns to Maximilian and is promulgated in the emperor’s name with the counsel and consent of the imperial estates.",
            fields: [
              {
                label: "Imperial act",
                value: "Confirm, publish and command observance",
              },
              {
                label: "Estate act",
                value: "Consent, finance and carry the settlement home",
              },
            ],
            outcome:
              "A proposition has become imperial law because crown and unequal estates have made it together.",
          },
        ],
      },
    },
    {
      id: "circles-put-peace-on-map",
      actId: "realm-reforms-itself",
      order: 9,
      period: "AD 1500–1521",
      place: "The Imperial Circles",
      title: "Circles Put Peace on the Map",
      thesis:
        "Regional circles gave the Empire a working scale between the individual estate and the whole realm.",
      body: [
        "The Diet first grouped German territories into six Imperial Circles in 1500; by 1512 there were ten. The lines did not redraw the Empire as ten provinces. Electorates and Habsburg lands entered the system through separate circles, while the Bohemian Crown, Swiss Confederacy, imperial Italy and several other lands remained outside it. Inside each circle, princes, bishops, counts and cities faced one another as neighbours with obligations that could be counted. A complicated map had acquired a regional frame for common work.",
        "Circle assemblies assessed military contingents, organised defence, supervised coinage and helped execute judgments and the Public Peace. A court order against one lord no longer had to wait upon the emperor’s personal arrival. Nearby estates could be charged with giving it effect. Coin inspectors compared currencies that crossed the same markets. Muster lists assigned men and money according to recognised quotas. Cooperation remained uneven because the members guarded their resources, but the circle converted a distant imperial command into tasks performed by institutions close enough to know the ground.",
        "The system respected the mosaic while making it governable. Württemberg did not cease to be a duchy when it sat with Swabian bishops, counts and cities. Nuremberg did not surrender its council when it contributed to a Franconian levy. Each member acted from its own legal position, and the shared assembly joined those positions for a defined purpose. The Empire had found a second chamber beyond the Diet: not one building, but ten regions in which neighbours carried the public peace into roads, mints, arsenals and court files.",
      ],
      image: `${imageRoot}/09-circles-put-peace-on-map.avif`,
      imageAlt:
        "Documentary loops trace the Imperial Circles across a relief map while a contingent list, coin inspection and court order open beside one region.",
      imagePosition: "52% center",
      visualLabel: "Documentary map reconstruction",
      visualTone: "circles-and-orders",
      side: "left",
      sourceIds: ["wilson-2016", "westphal-2018", "imperial-reform-1495"],
      evidence: [
        "The Circles were established in stages from 1500 to 1512 and eventually numbered ten; their coverage never included every imperial land.",
        "Circle institutions coordinated defence, quotas, coin supervision and execution of imperial law while their members retained distinct governments.",
      ],
      map: { x: 48, y: 51 },
    },
    {
      id: "augsburg-makes-division-governable",
      actId: "difference-inside-peace",
      order: 10,
      period: "AD 1555",
      place: "Augsburg",
      title: "Augsburg Makes Division Governable",
      thesis:
        "The Empire preserved one political order after western Christendom had divided within its borders.",
      body: [
        "By 1555, Lutheran worship had stood for a generation in territories and cities that remained inside the Empire. Attempts to restore a single confession by persuasion or force had failed, while external war and internal alliances made a permanent settlement urgent. At Augsburg, King Ferdinand negotiated in the name of his brother Charles V with the assembled estates. The resulting peace recognised Catholicism and the Augsburg Confession as lawful territorial confessions within the same imperial constitution.",
        "Territorial rulers received the authority to establish one of those confessions in their lands. Subjects unwilling to conform were granted a right to emigrate with their possessions after meeting their obligations. The ecclesiastical reservation sought to prevent a bishop or abbot who converted from carrying church lands into the Protestant camp, while Ferdinand’s declaration protected specified Protestant practices in certain ecclesiastical territories and cities. These clauses turned confession from an unlimited claim upon the whole realm into a territorial jurisdiction defined by imperial law.",
        "Augsburg made division capable of government. Catholic and Lutheran princes could sit in the same Diet, contribute to the same defence and use the same imperial courts while maintaining different churches at home. Calvinist estates would enter the legal field at Westphalia; Augsburg meanwhile gave central Europe more than six decades without a general confessional war inside the Empire. Political membership no longer demanded restored religious uniformity. The Empire answered the fracture of Christendom with law: defined authorities, protected possessions and a rule by which difference could remain inside the public peace.",
      ],
      image: `${imageRoot}/10-augsburg-division-governable.avif`,
      imageAlt:
        "Catholic and Lutheran worship remain distinct behind the signed Peace of Augsburg as one guarded civic road continues between them.",
      imagePosition: "52% center",
      visualLabel: "Evidence-led reconstruction",
      visualTone: "two-confessions-one-peace",
      side: "right",
      sourceIds: ["whaley-2012", "wilson-2016", "brady-2009"],
      evidence: [
        "The Peace of Augsburg recognised Catholic and Lutheran estates, territorial religious authority and a qualified right of emigration.",
        "Its clauses gave confessional division a durable imperial form that territories, estates and courts could administer inside one public peace.",
      ],
      map: { x: 46, y: 55 },
    },
    {
      id: "westphalia-keeps-mosaic",
      actId: "difference-inside-peace",
      order: 11,
      period: "AD 1648–1663",
      place: "Münster · Osnabrück · Regensburg",
      title: "Westphalia Keeps the Mosaic",
      thesis:
        "Westphalia rebuilt the imperial constitution after war and made negotiation continuous at Regensburg.",
      body: [
        "Thirty years of war had carried armies, requisition, hunger and epidemic through the German lands. The treaties negotiated at Münster and Osnabrück in 1648 ended the great conflict by restoring an imperial order in which Catholic, Lutheran and now Calvinist estates could stand. The confessional settlement used 1624 as a normal year for many questions of possession and worship. It bound religious disputes to documented dates and procedures, replacing campaigns of recovery with rules that courts and governments could apply.",
        "The treaties confirmed the ancient rights, privileges and territorial authority of the imperial estates. They recognised an estate’s power to make alliances for its preservation, provided those alliances were not directed against emperor, Empire or public peace. The qualification preserved a multilevel constitution in which territorial governments possessed broad powers while remaining members of the Reich, subject to its settlements and represented in its institutions. The imperial courts resumed their work, and the Diet remained the place for common business.",
        "In 1663, envoys gathered at Regensburg for a Diet that never formally dissolved. The Perpetual Diet replaced costly journeys by rulers with permanent representation, written instruction and continuous conference. Electoral, princely and city colleges guarded their different standing; the religious bodies provided another path when confession divided the ordinary benches. A proposition could move through months of exchange before emperor and estates reached an act. The slowness belonged to a realm in which consent carried real weight. After Europe’s most destructive internal war, the Empire rebuilt peace by keeping the mosaic and strengthening the procedures that joined it.",
      ],
      image: `${imageRoot}/11-westphalia-keeps-mosaic.avif`,
      imageAlt:
        "Treaty packets from Münster and Osnabrück lie open in a Regensburg chamber where confessional, estate and institutional clauses remain distinct.",
      imagePosition: "57% center",
      visualLabel: "Documentary reconstruction",
      visualTone: "treaty-clauses",
      side: "left",
      sourceIds: ["whaley-2012", "wilson-2016", "westphal-2018"],
      evidence: [
        "The Westphalian treaties admitted Calvinists, established 1624 as a key confessional baseline and confirmed the rights and privileges of imperial estates.",
        "Estate alliance rights remained bounded by obligations to emperor, Empire and public peace; the imperial courts and Diet continued after 1648.",
      ],
      map: { x: 42, y: 48 },
      interaction: {
        kind: "chapter-v2",
        family: "record",
        variant: "westphalian-settlement",
        prompt: "Keep the peace in many laws",
        accessibleSummary:
          "Five clauses show how Westphalia settled confession, protected estate rights, bounded alliances, restored courts and led toward permanent negotiation at Regensburg.",
        initialId: "confessional-baseline",
        records: [
          {
            id: "confessional-baseline",
            label: "Confession",
            period: "1624 / 1648",
            kicker: "A date arrests recovery by force",
            detail:
              "Catholics, Lutherans and Calvinists receive a constitutional settlement whose rules use the normal year 1624 for many possessions and practices.",
            fields: [
              {
                label: "Recognised",
                value: "Catholic · Lutheran · Calvinist estates",
              },
              {
                label: "Instrument",
                value: "Dated possession and reciprocal legal protection",
              },
            ],
            outcome:
              "Confessional claims move from armies toward records, courts and settled procedure.",
          },
          {
            id: "estate-rights",
            label: "Estates",
            period: "Constitutional possession",
            kicker: "Rights remain inside the Reich",
            detail:
              "Electors, princes and estates are confirmed in their privileges, territorial authority and participation in imperial affairs.",
            fields: [
              {
                label: "Protected",
                value:
                  "Ancient rights, regalian powers and territorial government",
              },
              {
                label: "Connection",
                value: "Membership in Diet, courts and imperial peace",
              },
            ],
            outcome:
              "Territorial strength and imperial membership are preserved in the same settlement.",
          },
          {
            id: "bounded-alliances",
            label: "Alliances",
            period: "Right with a limit",
            kicker: "External action keeps an imperial boundary",
            detail:
              "An estate may ally for preservation and security, including with foreign powers, within the treaty’s stated limits.",
            fields: [
              {
                label: "Right",
                value: "Make alliances for preservation and security",
              },
              {
                label: "Limit",
                value: "Never against emperor, Empire, public peace or treaty",
              },
            ],
            outcome:
              "Westphalia enlarges estate action without converting the Reich into unrelated sovereign states.",
          },
          {
            id: "imperial-institutions",
            label: "Courts",
            period: "Peace in operation",
            kicker: "The common forum reopens",
            detail:
              "The imperial courts and the Diet continue to receive disputes and business that cross territorial and confessional lines.",
            fields: [
              {
                label: "Judgment",
                value: "Imperial Chamber Court and Aulic Council",
              },
              {
                label: "Common business",
                value: "Diet, circles and negotiated execution",
              },
            ],
            outcome:
              "The peace has institutions capable of carrying its clauses beyond the signing table.",
          },
          {
            id: "perpetual-diet",
            label: "Remain",
            period: "Regensburg · 1663",
            kicker: "Assembly becomes continuous",
            detail:
              "Permanent envoys act under written instructions as electoral, princely and city colleges negotiate without formally ending the Diet.",
            fields: [
              {
                label: "Representation",
                value: "Resident envoys reporting to their governments",
              },
              {
                label: "Result",
                value: "Continuous constitutional negotiation",
              },
            ],
            outcome:
              "The hall stays in session because the imperial mosaic never stops producing common business.",
          },
        ],
      },
    },
    {
      id: "empire-ends-liberties-remain",
      actId: "difference-inside-peace",
      order: 12,
      period: "6 August AD 1806",
      place: "Vienna · the German lands",
      title: "The Empire Ends; Its Liberties Remain",
      thesis:
        "Napoleon destroyed the imperial office, but he could not erase the governments and legal habits formed beneath it.",
      body: [
        "The French Revolutionary and Napoleonic wars broke the conditions in which the old constitution had lived. The settlement of 1803 secularised bishoprics, mediatized many smaller estates and redistributed votes and lands on an immense scale. Francis II assumed the hereditary title Emperor of Austria in 1804 as Napoleon crowned himself emperor of the French. In July 1806, sixteen German princes left the Reich and joined Napoleon’s Confederation of the Rhine. The imperial bond could no longer command the rulers whose contingents and territory had sustained it.",
        "On 6 August, Francis laid down the imperial crown and released electors, princes and estates from their obligations. He acted from Vienna by declaration, bringing to an end an office first taken by Otto more than eight centuries earlier. No final Diet assembled to preserve it. Napoleon’s armies had made dissolution unavoidable, and the last emperor chose to protect his Habsburg lands and Austrian title from the ruins. The seals, archives, court files and privileges of the Reich remained after its political summit disappeared.",
        "Those records belonged to living governments. Cities kept traditions of corporate administration. Territories retained offices, schools, courts and fiscal systems built through centuries of recognised right. The German Confederation later restored a federal bond among sovereigns rather than reviving the medieval Empire, and the constitutional inheritance changed again under nationalism and industrial power. A deeper habit survived every reconstruction: central Europe expected authority to exist at several levels, rights to be documented and common action to require negotiated forms. The Empire ended in law because it had lived through law. Its crown vanished; its many political societies entered the nineteenth century carrying institutions older than the kings who now claimed them.",
      ],
      image: `${imageRoot}/12-empire-outlives-kings.avif`,
      imageAlt:
        "Francis II’s abdication declaration and the imperial crown rest on a Vienna desk while active city halls, courts and archives remain visible across the map.",
      imagePosition: "55% center",
      visualLabel: "Documentary reconstruction",
      visualTone: "crown-laid-down",
      side: "right",
      sourceIds: ["whaley-2012", "wilson-2016", "stollberg-rilinger-2018"],
      evidence: [
        "Francis II’s declaration of 6 August 1806 relinquished the imperial title and released the estates after the Confederation of the Rhine withdrew major princes from the Reich.",
        "Dissolution ended the imperial constitution while territorial administrations, civic institutions, archives and practices of federal negotiation continued in new forms.",
      ],
      map: { x: 56, y: 57 },
    },
  ],
};
