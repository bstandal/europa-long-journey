import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/europe-at-war";

const holocaustArchivalOnlyAssets = [
  `${imageRoot}/13-archival-european-jewry-marked-for-murder.avif`,
  `${imageRoot}/13a-archival-named-family-before-persecution.avif`,
  `${imageRoot}/13b-archival-deportation-property-record.avif`,
  `${imageRoot}/13c-archival-shootings-killing-centres-map.avif`,
  `${imageRoot}/13d-archival-liberation-absence-survivors-record.avif`,
] as const;

const archivalOnlyAssets = [
  `${imageRoot}/11-archival-law-and-terror-reclassify-human-being.avif`,
  `${imageRoot}/12-archival-the-pact-opens-poland.avif`,
  ...holocaustArchivalOnlyAssets,
  `${imageRoot}/14-archival-berlin-falls-and-europe-is-divided.avif`,
] as const;

/**
 * Production contract for the chapter's documentary imagery. The Holocaust
 * sequence is archival-only: every human subject and historical document must
 * have museum- or archive-level provenance before an asset can enter production.
 */
export const europeAtWarAssetContract = {
  direction: "The Continent Split Open",
  root: imageRoot,
  archivalOnly: {
    generated: false,
    static: true,
    assets: archivalOnlyAssets,
  },
  actFourTreatment: {
    mode: "progressively-archival",
    motion: "reduced",
    generatedVictimsOrAtrocitiesAllowed: false,
    generatedDepictionsForbidden: [
      "victim",
      "prisoner",
      "execution",
      "camp",
      "ghetto",
      "atrocity",
    ],
  },
  holocaust: {
    mode: "archival-only",
    generated: false,
    static: true,
    interactive: false,
    autoplay: false,
    parallax: false,
    hoverReveal: false,
    audio: false,
    scrollLock: false,
    requiredProvenance: [
      "institution",
      "source URL",
      "date",
      "location",
      "subject",
      "rights decision",
    ],
    exclusionRule:
      "Exclude every asset whose subject, date, location, institution or rights cannot be verified; name people whenever the archival record preserves their names.",
    archivalOnlyAssets: holocaustArchivalOnlyAssets,
  },
} as const;

export const europeAtWar: ChapterDefinition = {
  slug: "europe-at-war",
  number: "22",
  title: "The European Civil War",
  openingTitleLines: ["The European", "Civil War"],
  period: "AD 1871–1945",
  claim:
    "Europe’s two world wars were one continental struggle over power, nation, revolution and order. They became world wars because Europe had global reach; at their centre, European industry and administration were turned from engines of civilization into instruments of total war, terror and the murder of Europe’s Jews.",
  openingClaim:
    "The armed peace formed after 1871 broke into a European civil war from 1914 to 1945, and Europe’s global significance carried that catastrophe across the earth.",
  hero: {
    image: `${imageRoot}/01-an-empire-is-proclaimed-in-a-conquered-palace.avif`,
    mobileImage: `${imageRoot}/01-an-empire-is-proclaimed-in-a-conquered-palace-mobile.avif`,
    imageAlt:
      "A split-open atlas places the imperial proclamation in the Hall of Mirrors beside the siege of Paris and the annexation line through Alsace-Lorraine.",
    imagePosition: "56% center",
    mobileImagePosition: "63% center",
    visualLabel: "Versailles, 1871 · empire, siege and annexation line",
  },
  theme: {
    id: "split-open",
    label: "The Continent Split Open",
  },
  openingAction: "Open the fault lines",
  mapLabel:
    "The borders, mobilisation systems, refugee routes, occupation regimes and fractures that carried Europe from armed peace to ruin",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Treaties · mobilisation orders · railway plans · passports · citizenship law · party records · occupation files · deportation documents · survivor archives",
  acts: [
    {
      id: "armed-peace",
      number: "I",
      label: "The armed peace",
      period: "AD 1871–1914",
      title: "The Armed Peace",
      detail:
        "National power, political antisemitism, alliance systems, mass armies and railway plans accumulate beneath a surface of prosperity.",
    },
    {
      id: "industry-enters-battlefield",
      number: "II",
      label: "Industry enters the battlefield",
      period: "AD 1914–1918",
      title: "Industry Enters the Battlefield",
      detail:
        "Railways, artillery, factories, blockade and mass administration turn war into a contest between whole societies and destroy four imperial orders.",
    },
    {
      id: "peace-loses-authority",
      number: "III",
      label: "Peace loses its authority",
      period: "AD 1919–1933",
      title: "Peace Loses Its Authority",
      detail:
        "New borders create nations and minorities, revolution offers an alternative civilization, and mass movements exploit economic collapse and political abandonment.",
    },
    {
      id: "total-dominion",
      number: "IV",
      label: "Total dominion",
      period: "AD 1935–1945",
      title: "Total Dominion",
      detail:
        "Racial law, Stalinist terror, aggressive war, occupation and genocide reveal states seeking command without limit before victory leaves Europe ruined, diminished and divided.",
    },
  ],
  ending: {
    period: "AD 1945",
    title: "The Continent Lies Open",
    detail:
      "The damaged map table in Berlin carries the whole fracture. Versailles, the mobilisation lines, the trenches, the abandoned passports, the party files and the deportation rails end in one ruined capital. American, British, French and Soviet occupation has destroyed Nazi power, while Europe’s civil war has surrendered the continent’s old primacy. New paper is already being laid on either side of the break: plans for aid, alliance and shared authority in the west; Soviet commands enforced through party and army in the east. Two roads leave the same ruin and run toward 1989.",
    image: `${imageRoot}/15-continent-lies-open.avif`,
    mobileImage: `${imageRoot}/15-continent-lies-open-mobile.avif`,
    nextPeriod: "AD 1945–1989",
  },
  returnHash: "europe-at-war",
  nextHash: "continent-rebuilt",
  nextTitle: "The Continent Rebuilt",
  nextSlug: "continent-rebuilt",
  movements: [
    {
      id: "an-empire-is-proclaimed-in-a-conquered-palace",
      actId: "armed-peace",
      order: 1,
      period: "AD 1871",
      place: "Versailles",
      title: "An Empire Is Proclaimed in a Conquered Palace",
      thesis:
        "German union shifted the balance of Europe while the place and terms of victory bound national achievement to a defeated neighbour’s humiliation.",
      body: [
        "On 18 January 1871, uniforms filled the Hall of Mirrors while Paris endured siege beyond the horizon. German princes acclaimed Wilhelm I of Prussia as German emperor beneath paintings of Louis XIV’s victories. The new Reich joined Prussia’s army, the North German constitution and the resources of the southern kingdoms in the centre of Europe. German national union was a formidable political achievement. Its proclamation inside a conquered French palace made the achievement inseparable from war in the memory of both states.",
        "The settlement transferred Alsace and part of Lorraine to Germany and imposed a vast indemnity on France. Bismarck then worked to preserve the new order through alliances, restraint and the diplomatic isolation of France. The balance held for decades, though its centre had moved. France rebuilt its army and republic; Germany industrialised at extraordinary speed; Austria-Hungary and Russia faced national questions within multinational empires. Every great power governed citizens at home and imperial subjects abroad, carrying rival conceptions of nation, hierarchy and belonging inside the same European system.",
        "Imperial expansion accustomed European governments to racial classification, rule by decree and bureaucratic command in territories denied equal citizenship. Political antisemitism recast Jewish citizens as a hidden nation whose legal equality could never be trusted. The techniques of imperial rule, national rivalry, mass politics and modern administration entered the next crisis as available instruments. A movement that joined them could build an order far more destructive than the conservative settlement of 1871.",
      ],
      image: `${imageRoot}/01-an-empire-is-proclaimed-in-a-conquered-palace.avif`,
      mobileImage: `${imageRoot}/01-an-empire-is-proclaimed-in-a-conquered-palace-mobile.avif`,
      imageAlt:
        "German princes gather around Wilhelm I in the Hall of Mirrors as a dated map marks the new empire and the annexed provinces of Alsace and Lorraine.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Proclamation record, Versailles plan and 1871 boundary",
      visualTone: "cracked-atlas",
      side: "left",
      sourceIds: ["clark-iron-kingdom-2006", "mazower-1998"],
      evidence: [
        "The German Empire was proclaimed at Versailles on 18 January 1871 while Paris remained under siege during the Franco-Prussian War.",
        "The Treaty of Frankfurt transferred Alsace and part of Lorraine to Germany and required France to pay an indemnity of five billion francs.",
      ],
      map: { x: 43, y: 45 },
    },
    {
      id: "the-dreyfus-case-divides-the-street",
      actId: "armed-peace",
      order: 2,
      period: "AD 1894–1906",
      place: "Paris and Rennes",
      title: "The Dreyfus Case Divides the Street",
      thesis:
        "The struggle over Alfred Dreyfus exposed political antisemitism as a modern organising force and tested whether republican citizenship belonged to law or blood.",
      body: [
        "A torn memorandum recovered from the German embassy brought suspicion onto Captain Alfred Dreyfus, one of the few Jewish officers on the French General Staff. In 1894 a military court convicted him of treason after receiving a secret dossier his defence could not examine. He was publicly degraded and sent to Devil’s Island. The proceedings gave an old hatred a modern institutional costume: expert testimony, military secrecy, mass newspapers and the authority of a republic all appeared to certify the fiction that a Jewish officer’s ancestry made betrayal plausible.",
        "Evidence soon pointed to Major Ferdinand Walsin Esterhazy. Lieutenant Colonel Georges Picquart identified the new handwriting and found that the secret case against Dreyfus could not bear scrutiny. The army protected its verdict; Picquart was transferred and imprisoned; Esterhazy was acquitted. Émile Zola’s open letter, J’accuse…!, converted the concealed injustice into a national contest. Anti-Dreyfusard leagues treated Jews as an alien power lodged inside France, while Dreyfusards defended evidence, judicial review and the citizen’s standing before a common law.",
        "The Court of Cassation annulled the judgment in 1906, and Dreyfus returned to the army. Legal institutions had repaired a wrong after twelve years, giving the republic a genuine victory. The mobilisation around the case left another fact in view. Antisemitism no longer lived only in inherited prejudice or religious exclusion. It could bind newspapers, veterans, street organisations, conspiracy theories and electoral ambition into a politics that declared one category of citizen permanently suspect. Law had vindicated equal citizenship; mass politics had learned to imagine belonging through exclusion.",
      ],
      image: `${imageRoot}/02-the-dreyfus-case-divides-the-street.avif`,
      imageAlt:
        "A divided Paris street places a newspaper kiosk, Dreyfus case papers and an Alfred Dreyfus portrait medallion opposite a court docket.",
      imagePosition: "48% center",
      visualLabel: "Portrait medallion, newspaper record and court judgment",
      visualTone: "archive-grey",
      side: "right",
      sourceIds: ["harris-dreyfus-2010", "arendt-totalitarianism-1951"],
      evidence: [
        "Dreyfus was convicted in 1894 after a closed military proceeding that included a secret dossier withheld from the defence.",
        "The Court of Cassation annulled the Rennes judgment in July 1906; Dreyfus was exonerated, reinstated and made a chevalier of the Legion of Honour.",
      ],
      map: { x: 42, y: 44 },
    },
    {
      id: "the-continent-is-written-as-a-schedule",
      actId: "armed-peace",
      order: 3,
      period: "AD 1890–1914",
      place: "Berlin, Paris, Vienna and St Petersburg",
      title: "The Continent Is Written as a Schedule",
      thesis:
        "Alliance commitments, conscription and railway planning joined separate fears into a military system whose speed compressed the time available for political choice.",
      body: [
        "In general-staff offices, Europe became columns of figures. Officers counted active corps, reserve formations, locomotives, sidings, horses, bridges and the days required to place an army at a frontier. Universal or near-universal male service gave continental states millions of trained reservists. Railways could gather them faster than any previous army, provided every train occupied its assigned line and minute. Civilian networks built to carry coal, food, letters and holiday crowds acquired a second existence in sealed plans.",
        "Diplomacy gave those plans direction. The Triple Alliance joined Germany, Austria-Hungary and Italy under defined conditions; the Franco-Russian alliance promised action against a German-led attack; Britain’s understandings with France and Russia settled imperial disputes and created the Triple Entente without becoming one automatic military command. Naval rivalry, Balkan crises and the weakening of Ottoman authority sharpened the stakes. Staffs planned against danger because planning was their duty. Each finished schedule encouraged another staff to assume that delay would place its own country at a fatal disadvantage.",
        "A timetable never declared war. Cabinets, monarchs, ministers and military leaders retained responsibility for every order they issued in 1914. The schedules changed the setting in which they chose. Once mobilisation began, thousands of interlocking movements were hard to pause or redirect; a plan aimed at one enemy could cross another state’s frontier; an ally’s delay could expose an entire flank. Europe had built immense administrative competence. In a crisis, that competence could narrow political time until decision appeared to mean activating the machine or watching an opponent activate first.",
      ],
      image: `${imageRoot}/03-the-continent-is-written-as-a-schedule.avif`,
      imageAlt:
        "French, German, Austro-Hungarian and Russian mobilisation tables align over a railway diagram with alliance obligations kept visually separate from military assumptions.",
      imagePosition: "50% center",
      visualLabel: "Mobilisation tables, railway diagrams and dated orders",
      visualTone: "steel-schedule",
      side: "left",
      sourceIds: ["stevenson-armaments-1996", "strachan-first-world-war-2001"],
      evidence: [
        "European general staffs prepared detailed mobilisation and concentration plans around railway capacity, reservist call-up and fixed sequencing.",
        "The pre-war alliance blocs created expectations and commitments, while political leaders still made the decisions that converted crisis into war.",
      ],
      map: { x: 53, y: 36 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "mobilisation-timetable",
        prompt: "Mobilise by timetable",
        accessibleSummary:
          "Four fixed records compare the strategic railway systems, mobilisation orders and opening movements of France and Germany, showing how prepared schedules compressed political time without causing the war.",
        initialId: "plans-in-cabinets",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "plans-in-cabinets",
            label: "Plans in cabinets",
            period: "AD 1890–1913",
            kicker: "Capacity becomes assumption",
            detail:
              "Both staffs calculate how many formations their railways can place near a frontier and how quickly an opponent can do the same.",
            fields: [
              {
                label: "France",
                value: "Concentrate armies toward the eastern frontier",
              },
              {
                label: "Germany",
                value: "Concentrate first against France, then turn east",
              },
              {
                label: "Political fact",
                value: "No railway plan has authority to declare war",
              },
            ],
            outcome:
              "The plans create powerful expectations about which hours may be lost.",
            points: [
              {
                id: "paris",
                label: "Paris",
                detail: "French command and rail coordination.",
                x: 42,
                y: 45,
              },
              {
                id: "berlin",
                label: "Berlin",
                detail: "German command and rail coordination.",
                x: 56,
                y: 35,
              },
              {
                id: "frontier",
                label: "Franco-German frontier",
                detail: "The principal western concentration zone.",
                x: 48,
                y: 43,
              },
            ],
            links: [
              [0, 2],
              [1, 2],
            ],
          },
          {
            id: "orders-leave-capitals",
            label: "Orders leave the capitals",
            period: "30 July–1 August 1914",
            kicker: "Political decisions activate schedules",
            detail:
              "Russian general mobilisation is followed by German ultimata and mobilisation; France orders general mobilisation while keeping its troops behind the frontier before hostilities.",
            fields: [
              {
                label: "Trigger",
                value: "Signed state orders, not automatic railway motion",
              },
              {
                label: "Pressure",
                value:
                  "Each staff measures delay against the opponent’s mobilisation",
              },
              {
                label: "Consequence",
                value:
                  "Civilian rolling stock and junctions pass under military priority",
              },
            ],
            outcome:
              "Diplomatic time contracts as the transport systems change purpose.",
            points: [
              {
                id: "st-petersburg",
                label: "St Petersburg",
                detail: "Russian general mobilisation is ordered.",
                x: 75,
                y: 22,
              },
              {
                id: "berlin",
                label: "Berlin",
                detail:
                  "Ultimata and mobilisation orders issue from the imperial capital.",
                x: 56,
                y: 35,
              },
              {
                id: "paris",
                label: "Paris",
                detail: "France orders general mobilisation on 1 August.",
                x: 42,
                y: 45,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "german-right-wing",
            label: "Germany turns west",
            period: "2–16 August 1914",
            kicker: "The plan crosses Belgium",
            detail:
              "German railways deliver armies toward the western concentration areas; the operational advance then violates neutral Luxembourg and Belgium in order to reach France from the north.",
            fields: [
              {
                label: "Rail task",
                value: "Concentrate formations, ammunition, horses and supply",
              },
              {
                label: "Operational choice",
                value: "Advance through Luxembourg and Belgium",
              },
              {
                label: "Political consequence",
                value: "Belgian resistance and British entry widen the war",
              },
            ],
            outcome:
              "A schedule built for speed carries a deliberate violation of neutrality into action.",
            points: [
              {
                id: "rhine",
                label: "Rhine railheads",
                detail: "German formations detrain for the western advance.",
                x: 50,
                y: 42,
              },
              {
                id: "liege",
                label: "Liège",
                detail: "Belgian fortifications obstruct the opening route.",
                x: 47,
                y: 41,
              },
              {
                id: "marne",
                label: "Marne",
                detail:
                  "The advance reaches east of Paris before turning back.",
                x: 43,
                y: 46,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "french-concentration",
            label: "France moves east and north",
            period: "2 August–6 September 1914",
            kicker: "Schedules meet events",
            detail:
              "French railways complete the main concentration, then redirect formations as the German advance through Belgium makes the original deployment inadequate.",
            fields: [
              {
                label: "Initial movement",
                value: "Concentration under Plan XVII",
              },
              {
                label: "Correction",
                value: "Emergency transfers toward the threatened left",
              },
              {
                label: "Limit revealed",
                value:
                  "A timetable can deliver an army; it cannot make the enemy obey the forecast",
              },
            ],
            outcome:
              "Rail capacity helps France recover from strategic error, and the campaign fails to end at the Marne.",
            points: [
              {
                id: "paris",
                label: "Paris",
                detail: "A threatened capital and major transport centre.",
                x: 42,
                y: 45,
              },
              {
                id: "lorraine",
                label: "Lorraine",
                detail: "The initial French concentration faces east.",
                x: 48,
                y: 45,
              },
              {
                id: "marne",
                label: "Marne",
                detail: "Transferred forces join the counterstroke.",
                x: 43,
                y: 46,
              },
            ],
            links: [
              [1, 0],
              [0, 2],
            ],
          },
        ],
      },
    },
    {
      id: "sarajevo-enters-vienna",
      actId: "armed-peace",
      order: 4,
      period: "28 June–4 August 1914",
      place: "Sarajevo, Vienna, Berlin, St Petersburg, Paris and London",
      title: "Sarajevo Enters Vienna",
      thesis:
        "Thirty-seven days of deliberate decisions turned a Balkan assassination into a continental war that Europe’s empires carried across the world.",
      body: [
        "On 28 June, Gavrilo Princip shot Archduke Franz Ferdinand and Sophie in Sarajevo. The murder emerged from the politics of Bosnia, Serbian nationalism and the clandestine networks that crossed the Habsburg frontier. Vienna chose to use the crime as an opportunity to break Serbian power. Germany offered Austria-Hungary firm support. The resulting ultimatum demanded concessions designed to penetrate Serbian sovereignty; Serbia accepted much and rejected the points that placed Austro-Hungarian officials inside its legal process. Austria-Hungary declared war on 28 July.",
        "The crisis widened through choices made under fear and incomplete information. Russia moved to protect Serbia and its position in the Balkans, first through partial measures and then general mobilisation. Germany declared war on Russia and France. Its western plan required an advance through Luxembourg and neutral Belgium. Britain, divided until the final days, entered after the Belgian invasion joined treaty obligation, strategic interest and the danger of German control across the Channel. No invisible alliance mechanism pulled a lever. Governments judged the risks of restraint greater than the risks of force and issued the orders themselves.",
        "The war became global because Europe was globally consequential. Britain and France drew soldiers, labour and resources from empires spanning Africa, Asia, the Caribbean and the Pacific; Germany possessed colonies and commercial networks; Russia’s empire reached the Caucasus and Central Asia; the Ottoman decision to join opened fronts across the Middle East; Japan entered against German positions in East Asia under its own strategic aims. The conflict’s European centre never made lives elsewhere secondary. Europe’s command of territory, shipping, finance and cable turned its internal struggle into a world war.",
      ],
      image: `${imageRoot}/04-sarajevo-enters-vienna.avif`,
      imageAlt:
        "Six dated desks carry the Sarajevo report, German assurance, Austro-Hungarian ultimatum, Russian mobilisation order, French cabinet papers and British declaration in sequence.",
      imagePosition: "50% center",
      visualLabel:
        "Telegram, ultimatum, cabinet record and mobilisation notice",
      visualTone: "document-shutter",
      side: "right",
      sourceIds: ["clark-sleepwalkers-2012", "otte-july-crisis-2014"],
      evidence: [
        "Austria-Hungary delivered its ultimatum to Serbia on 23 July, declared war on 28 July and began bombardment of Belgrade the next day.",
        "Germany declared war on Russia on 1 August and France on 3 August; Britain declared war on Germany on 4 August after German forces entered Belgium.",
      ],
      map: { x: 58, y: 56 },
    },
    {
      id: "the-timetable-empties-the-cities",
      actId: "industry-enters-battlefield",
      order: 5,
      period: "August–September 1914",
      place: "Berlin, Paris, Brussels and the Marne",
      title: "The Timetable Empties the Cities",
      thesis:
        "Industrial administration placed millions under arms with extraordinary speed, then met the friction, resistance and strategic error that no schedule could abolish.",
      body: [
        "Mobilisation notices appeared on walls and station clocks acquired military authority. Reservists left farms, factories and offices carrying the card that assigned each man to a depot and each depot to a train. Horses, field kitchens, shells and medical stores followed. Farewell crowds differed by city, day and photographer; some cheered, some wept, many performed the composure expected of them. The archive preserves visible enthusiasm more readily than private dread. What can be measured is the administrative feat: continental states moved armies of unprecedented size toward their borders in a matter of days.",
        "Germany’s armies advanced through Belgium after reducing Liège’s forts with heavy artillery. Belgian resistance disrupted assumptions and made the invasion’s violence visible in burned towns, executed civilians and displaced families. French attacks in Alsace and Lorraine met devastating fire. The British Expeditionary Force withdrew with the French left as the German right wing moved toward and then east of Paris. Supply lines lengthened, formations lost contact and commanders altered the plan. Railways had delivered the armies; marching, combat, destroyed bridges and enemy action now governed them.",
        "French command transferred troops across the rear and struck with the British along the Marne in early September. German armies withdrew to the Aisne. Neither side had secured the quick decision around which its opening campaign had been built. Trenches extended as each attempted to turn the other’s flank, eventually closing the western front from Switzerland to the North Sea. The schedule that emptied Europe’s cities had delivered no decisive peace. It had deposited mass society beside industrial weapons and opened a war whose demands would reach backward into every household and factory.",
      ],
      image: `${imageRoot}/05-the-timetable-empties-the-cities.avif`,
      imageAlt:
        "A 1914 station sequence aligns German and French operational rail movements before ending on a surveyed trench line after the Marne.",
      imagePosition: "51% center",
      visualLabel: "Station notices, rail movement and trench survey",
      visualTone: "mobilisation-grey",
      side: "left",
      sourceIds: ["strachan-first-world-war-2001", "herwig-marne-2009"],
      evidence: [
        "The German invasion of neutral Belgium brought Britain into the war and met Belgian military resistance as well as extensive violence against civilians.",
        "The First Battle of the Marne halted the German advance in early September 1914; subsequent operations produced a continuous entrenched western front.",
      ],
      map: { x: 46, y: 43 },
    },
    {
      id: "the-front-becomes-a-factory-of-fire",
      actId: "industry-enters-battlefield",
      order: 6,
      period: "AD 1915–1917",
      place: "Verdun, the Somme and Europe’s home fronts",
      title: "The Front Becomes a Factory of Fire",
      thesis:
        "Attrition joined factory, railway, gun line and household into a single system for sustaining destruction beyond the endurance of any battlefield army alone.",
      body: [
        "At Verdun, trucks climbed the Bar-le-Duc road in an almost continuous stream while narrow-gauge railways carried ammunition toward the guns. German command intended to seize ground whose defence would compel France to spend men and shells; French command made the fortress zone a test of national endurance. Artillery altered woods, ridges and villages faster than maps could record them. Units entered the line, suffered, withdrew and were replaced. The battle lasted ten months because roads, depots, factories and a rotating army kept feeding a place that could sustain no life by itself.",
        "On the Somme, a week-long British bombardment preceded the assault of 1 July 1916. Wire and German positions survived in many sectors; British forces suffered almost sixty thousand casualties that day, including more than nineteen thousand dead. The battle continued into November as British, French and German armies adjusted tactics and poured fresh divisions into the salient. Soldiers from Canada, Australia, New Zealand, South Africa, Newfoundland, India, North Africa and other parts of European empires fought within the same industrial system. Their service and losses made the western front a global human field.",
        "Total war reached far beyond the gun line. Governments directed metals, chemicals, food, labour, credit and shipping; factories reorganised around munitions; rationing and blockade made nutrition a weapon. On the Ottoman Empire’s eastern roads, the Committee of Union and Progress used wartime emergency to deport Armenian communities and carry out mass killing. More than a million Armenians died through massacre, starvation, exposure and disease. Europe’s civil war had made administrative command, ethnic suspicion and military necessity available as languages through which a government could attack an entire people.",
      ],
      image: `${imageRoot}/06-the-front-becomes-a-factory-of-fire.avif`,
      imageAlt:
        "A measured logistics section joins shell factory, railway, battery, trench and aid post while one named unit’s equipment preserves the scale of individual service.",
      imagePosition: "54% center",
      visualLabel:
        "Factory ledger, railhead plan, battery record and field dressing",
      visualTone: "industrial-attrition",
      side: "right",
      sourceIds: [
        "jankowski-verdun-2013",
        "philpott-bloody-victory-2009",
        "suny-armenian-genocide-2015",
      ],
      evidence: [
        "Verdun lasted from February to December 1916 and depended on continuous French road and rail supply as well as the rotation of divisions through the sector.",
        "British forces sustained 57,470 casualties on 1 July 1916 on the Somme, of whom 19,240 were killed.",
        "The Ottoman deportation and mass murder of Armenians during the First World War killed at least one million people through direct violence and the conditions imposed on deportees.",
      ],
      map: { x: 47, y: 43 },
    },
    {
      id: "four-empires-leave-the-map",
      actId: "industry-enters-battlefield",
      order: 7,
      period: "AD 1917–1918",
      place: "Petrograd, Brest-Litovsk, Vienna, Constantinople and Compiègne",
      title: "Four Empires Leave the Map",
      thesis:
        "Revolution and military exhaustion destroyed four imperial orders, leaving national claims, armed movements and displaced populations to compete for their remains.",
      body: [
        "Bread queues and strikes in Petrograd became a revolution when soldiers refused to fire on demonstrators. Nicholas II abdicated in March 1917, ending Romanov rule. The Provisional Government preserved civil freedoms and continued the war, while soviets represented workers and soldiers and shared power uneasily. Lenin returned with a demand for peace, land and authority to the soviets. In November, the Bolsheviks seized the centres of government and claimed a revolution whose destination was larger than Russia: class rule would replace both empire and the bourgeois nation-state.",
        "The Bolsheviks accepted the Treaty of Brest-Litovsk in March 1918, surrendering immense western territories to escape the war and defend their revolution. Civil war followed, drawing Red and White armies, peasant forces, national movements and foreign intervention into overlapping violence. The old empire did not dissolve into empty space. Finland, Poland, the Baltic lands, Ukraine, the Caucasus and other regions pursued incompatible forms of sovereignty while armies crossed them. Revolution offered universal emancipation and built a party power prepared to use terror against those classified as enemies of history.",
        "Military defeat then ended the Hohenzollern, Habsburg and Ottoman imperial regimes. Sailors mutinied, councils formed, national committees declared independence and rulers departed. Austria-Hungary fragmented before the armistice; the German emperor abdicated; Ottoman ministers accepted defeat. On 11 November, the guns stopped on the western front. The end of battle did not end Europe’s civil war. Borders remained undecided, weapons remained in circulation and millions of veterans, prisoners, refugees and bereaved families entered states that had yet to establish either their territory or their authority.",
      ],
      image: `${imageRoot}/07-four-empires-leave-the-map.avif`,
      imageAlt:
        "Four imperial seals recede from a dated map while the Decree on Peace, Brest-Litovsk map, national declarations and Compiègne armistice page remain sharp.",
      imagePosition: "50% center",
      visualLabel:
        "Revolutionary decree, treaty map, declaration and armistice",
      visualTone: "erased-borders",
      side: "left",
      sourceIds: [
        "gerwarth-vanquished-2016",
        "figes-peoples-tragedy-1996",
        "mazower-1998",
      ],
      evidence: [
        "Nicholas II abdicated in March 1917; the Bolsheviks overthrew the Provisional Government in November and signed the Treaty of Brest-Litovsk in March 1918.",
        "German, Habsburg, Russian and Ottoman imperial authority collapsed during the war and its immediate aftermath, amid revolutions, national declarations and continuing armed conflict.",
      ],
      map: { x: 66, y: 34 },
    },
    {
      id: "the-peace-creates-the-stateless",
      actId: "peace-loses-authority",
      order: 8,
      period: "AD 1919–1923",
      place: "Paris, Geneva and Europe’s new frontiers",
      title: "The Peace Creates the Stateless",
      thesis:
        "The peace settlement enlarged national self-government while exposing people whose rights became fragile once no recognised state accepted them as members.",
      body: [
        "Delegates in Paris worked over maps from empires that no longer governed the ground. Poland returned; Czechoslovakia and the Kingdom of Serbs, Croats and Slovenes appeared; Romania enlarged; Austria and Hungary became separate states; Finland and the Baltic republics consolidated independence. These settlements answered real national aspirations suppressed or divided by imperial rule. They also placed Germans, Hungarians, Poles, Ukrainians, Jews and many others on the minority side of new frontiers. A line could give one people a state while giving its neighbour a minority treaty.",
        "The victorious powers required several new states to guarantee minority rights and placed petitions within the League of Nations system. Enforcement depended on governments that often regarded cultural difference as a threat to national consolidation. Outside Europe, the mandate system redistributed former German and Ottoman territories under European supervision, preserving imperial command behind a language of tutelage. The principle of national self-determination therefore entered an unequal world: powerful nations possessed states and empires, new nations sought homogeneous sovereignty, and colonial peoples encountered promises whose application stopped at strategic interest.",
        "War, revolution, border change and expulsion produced refugees whom no state recognised. Russian exiles received League of Nations travel documents associated with Fridtjof Nansen; Armenians and other displaced groups later used related certificates. The document enabled movement without restoring political membership. Here the universal language of rights met its hidden condition. A person required a public world in which the right to speak, work, reside and appeal would be guaranteed by fellow citizens and institutions. Once nationality disappeared, the bearer could possess rights in principle and find no authority obliged to honour them.",
      ],
      image: `${imageRoot}/08-the-peace-creates-the-stateless.avif`,
      imageAlt:
        "An atlas overlay compares European borders in 1914 and 1919 beside minority treaty terms, a refugee dossier form and a Nansen passport.",
      imagePosition: "50% center",
      visualLabel: "Boundary overlay, minority treaty and refugee document",
      visualTone: "passport-paper",
      side: "right",
      sourceIds: [
        "arendt-totalitarianism-1951",
        "steiner-lights-failed-2005",
        "unhcr-nansen-passport-archives",
      ],
      evidence: [
        "The post-war treaties created or enlarged European nation-states while leaving substantial national minorities outside the states identified with their language or nationality.",
        "The League of Nations introduced the Nansen passport in 1922 for Russian refugees who lacked a recognised national passport; its use later extended to other displaced groups.",
      ],
      map: { x: 57, y: 40 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "redraw-the-peace",
        prompt: "Redraw the peace",
        accessibleSummary:
          "Four dated border records compare the imperial map of 1914 with the treaty map after 1919 and identify minorities and refugees produced by the new settlement.",
        initialId: "imperial-map-1914",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "imperial-map-1914",
            label: "Four empires",
            period: "AD 1914",
            kicker: "Multinational authority",
            detail:
              "German, Habsburg, Russian and Ottoman imperial borders organise most of central and eastern Europe before the war.",
            fields: [
              {
                label: "Political form",
                value: "Dynastic and national empires",
              },
              {
                label: "Population fact",
                value: "Languages and religions cross every frontier",
              },
              {
                label: "Unsettled question",
                value: "Which peoples can claim a state of their own",
              },
            ],
            outcome:
              "War destroys the authorities that had contained competing national programmes.",
            points: [
              {
                id: "berlin",
                label: "German Empire",
                detail:
                  "A national empire with contested eastern and western frontiers.",
                x: 56,
                y: 35,
              },
              {
                id: "vienna",
                label: "Habsburg Empire",
                detail:
                  "A multinational monarchy centred on Vienna and Budapest.",
                x: 58,
                y: 47,
              },
              {
                id: "petrograd",
                label: "Russian Empire",
                detail:
                  "Imperial rule reaches west through Poland, Finland and the Baltic lands.",
                x: 75,
                y: 22,
              },
              {
                id: "constantinople",
                label: "Ottoman Empire",
                detail:
                  "The empire retains European territory and governs across the eastern Mediterranean.",
                x: 65,
                y: 65,
              },
            ],
          },
          {
            id: "treaty-map-1919",
            label: "New and enlarged states",
            period: "AD 1919–1920",
            kicker: "National sovereignty",
            detail:
              "The settlements recognise Poland, Czechoslovakia and the Kingdom of Serbs, Croats and Slovenes while redrawing Austria, Hungary, Romania and their neighbours.",
            fields: [
              {
                label: "Gain",
                value: "Self-government for several historic nations",
              },
              {
                label: "Method",
                value:
                  "Treaty lines, plebiscites in selected areas and military facts",
              },
              {
                label: "Limit",
                value:
                  "No frontier can place every community inside its preferred nation-state",
              },
            ],
            outcome:
              "National liberation and new minority questions arrive in the same settlement.",
            points: [
              {
                id: "warsaw",
                label: "Poland",
                detail:
                  "A restored state with disputed eastern and western limits.",
                x: 62,
                y: 38,
              },
              {
                id: "prague",
                label: "Czechoslovakia",
                detail:
                  "Czechs, Slovaks, Germans, Hungarians, Ruthenians and others inhabit the republic.",
                x: 56,
                y: 43,
              },
              {
                id: "belgrade",
                label: "Kingdom of Serbs, Croats and Slovenes",
                detail:
                  "South Slav union contains several political and national traditions.",
                x: 59,
                y: 55,
              },
              {
                id: "bucharest",
                label: "Enlarged Romania",
                detail:
                  "Territorial gains bring large minority populations inside the kingdom.",
                x: 66,
                y: 51,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
            ],
          },
          {
            id: "minorities-1920",
            label: "Minorities cross the lines",
            period: "AD 1920",
            kicker: "Citizenship changes around people",
            detail:
              "A resident may remain in the same town while the state, official language, schools and legal nationality change around the household.",
            fields: [
              {
                label: "Examples",
                value: "Germans, Hungarians, Poles, Ukrainians and Jews",
              },
              {
                label: "Guarantee",
                value: "Minority treaties under League supervision",
              },
              {
                label: "Weakness",
                value:
                  "Protection relies on state compliance and international attention",
              },
            ],
            outcome:
              "Formal citizenship does not end pressure for cultural uniformity.",
            points: [
              {
                id: "upper-silesia",
                label: "Upper Silesia",
                detail:
                  "German and Polish claims meet a mixed population and industrial frontier.",
                x: 58,
                y: 40,
              },
              {
                id: "sudeten",
                label: "Bohemian borderlands",
                detail:
                  "German-speaking communities become citizens of Czechoslovakia.",
                x: 55,
                y: 44,
              },
              {
                id: "transylvania",
                label: "Transylvania",
                detail:
                  "Hungarian and other minorities enter enlarged Romania.",
                x: 63,
                y: 51,
              },
            ],
          },
          {
            id: "refugees-1923",
            label: "People without a state",
            period: "AD 1921–1923",
            kicker: "A passport without citizenship",
            detail:
              "Revolution, denationalisation, border war and expulsion leave people outside any state willing to issue an ordinary national passport.",
            fields: [
              {
                label: "International answer",
                value: "Nansen travel document",
              },
              {
                label: "What it enables",
                value:
                  "Recognised cross-border travel and legal identification",
              },
              {
                label: "What it cannot restore",
                value: "Membership in a polity that guarantees rights",
              },
            ],
            outcome:
              "The refugee becomes a permanent political figure of the interwar order.",
            points: [
              {
                id: "geneva",
                label: "Geneva",
                detail:
                  "The League develops an international refugee document.",
                x: 47,
                y: 50,
              },
              {
                id: "constantinople",
                label: "Constantinople",
                detail:
                  "Russian and other refugees pass through a major exile centre.",
                x: 65,
                y: 65,
              },
              {
                id: "marseille",
                label: "Marseille",
                detail:
                  "A port of onward travel for displaced Europeans and Armenians.",
                x: 45,
                y: 57,
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
      id: "the-movement-seizes-the-state",
      actId: "peace-loses-authority",
      order: 9,
      period: "AD 1922–1929",
      place: "Rome and Moscow",
      title: "The Movement Seizes the State",
      thesis:
        "Fascist and Bolshevik organisations treated power as the instrument of an unfolding historical mission rather than a bounded office within a plural society.",
      body: [
        "Blackshirt squads had already beaten socialists, burned labour offices and broken local administrations when Fascist columns gathered for the March on Rome in October 1922. The army could have dispersed them. King Victor Emmanuel III declined to sign a state of siege and invited Benito Mussolini to form a government. Appointment gave the movement what street violence alone could not secure: ministries, police authority and legal access to the machinery of the state. Fascists then altered electoral law, murdered or silenced opponents and converted a coalition government into dictatorship.",
        "Italian Fascism fused nationalism, veterans’ violence, spectacle and a leader cult, claiming that party and nation should become one. Its dictatorship retained the monarchy, Church, army and much private property, and it never achieved the degree of social penetration or organised mass murder reached by Stalinism and Nazism. It changed Europe’s political grammar all the same. A movement could present legality as weakness, violence as moral energy and permanent mobilisation as a higher form of citizenship. Parties across the continent learned from its uniforms, rallies and conquest of public space.",
        "In the Soviet Union, the Bolshevik party had arisen as an alternative source of authority before absorbing the state. Lenin’s death opened a struggle in which Stalin accumulated command through party appointments and alliances. By 1929 he had defeated the principal rivals and launched forced collectivisation and rapid industrialisation. The regime claimed access to the law of history itself: classes marked as obsolete could be expropriated, deported or eliminated so that a new society could be built. Ideology ceased to offer an opinion about reality. It became an administrative key that assigned every person a place in history’s supposed movement.",
      ],
      image: `${imageRoot}/09-the-movement-seizes-the-state.avif`,
      imageAlt:
        "A Fascist party card and squad register remain distinct from a Bolshevik congress record and Soviet planning form along a parallel record corridor.",
      imagePosition: "50% center",
      visualLabel: "Party card, violence record, congress minute and plan",
      visualTone: "party-corridor",
      side: "left",
      sourceIds: [
        "gentile-sacralization-1996",
        "fitzpatrick-russian-revolution-2008",
        "arendt-totalitarianism-1951",
      ],
      evidence: [
        "Mussolini became prime minister by royal appointment after the March on Rome; Fascist violence and subsequent legal changes dismantled parliamentary opposition.",
        "By 1929 Stalin had defeated major party rivals and begun forced collectivisation alongside the First Five-Year Plan.",
      ],
      map: { x: 54, y: 54 },
    },
    {
      id: "the-republic-loses-the-street",
      actId: "peace-loses-authority",
      order: 10,
      period: "AD 1929–1933",
      place: "Berlin",
      title: "The Republic Loses the Street",
      thesis:
        "Economic collapse and political abandonment allowed the Nazi movement to turn electoral strength, organised violence and elite miscalculation into state power.",
      body: [
        "Unemployed Berliners waited outside labour exchanges as banks failed, firms closed and parliamentary coalitions broke apart. Germany’s Depression was exceptionally severe. Governments increasingly relied on presidential emergency decrees because the Reichstag could not sustain stable majorities. Communists and Nazis expanded among voters who believed the republic had become incapable of action. Street formations fought for neighbourhoods and meeting halls. Political life offered mass belonging to people whose work, savings and associations had been stripped away, while every failed cabinet taught citizens that ordinary representation produced only drift.",
        "The Nazi movement joined contradictory constituencies through an ideology presented as one total explanation. Defeat in 1918 became betrayal; economic crisis became conspiracy; class conflict became racial unity; antisemitism identified the Jew as the hidden author of both finance capitalism and Bolshevism. Propaganda, disciplined local organisation, ritual and violence gave isolated grievance a collective world. The party never won a majority in a free national election. Its vote peaked in July 1932, declined in November and remained large enough to make conservative elites believe Hitler could supply popular support to a government they would control.",
        "President Hindenburg appointed Hitler chancellor on 30 January 1933. The Reichstag fire decree suspended basic liberties and enabled mass arrest. On 23 March, deputies meeting amid intimidation passed the Enabling Act, allowing the cabinet to legislate without parliament; Communist deputies had been arrested or excluded, and only the Social Democrats present voted against. Trade unions were destroyed, parties dissolved and public institutions coordinated under Nazi authority. The republic did not fall through election alone. Appointment, emergency power, police coercion and legislative surrender carried a mass movement through the legal doors, after which it broke the house around them.",
      ],
      image: `${imageRoot}/10-the-republic-loses-the-street.avif`,
      imageAlt:
        "A Berlin employment office, plural election posters, the Reichstag Fire Decree and the Enabling Act narrow toward a single stamped field of authority.",
      imagePosition: "48% center",
      visualLabel:
        "Employment record, ballot wall, emergency decree and enabling law",
      visualTone: "narrowed-ballot",
      side: "right",
      sourceIds: [
        "evans-coming-third-reich-2003",
        "tooze-wages-destruction-2006",
      ],
      evidence: [
        "The Nazi Party won 37.3 percent of the vote in July 1932, fell to 33.1 percent in November and entered government when Hindenburg appointed Hitler chancellor.",
        "The Reichstag Fire Decree suspended constitutional protections in February 1933; the Enabling Act gave Hitler’s cabinet legislative power the following month under coercive conditions.",
      ],
      map: { x: 56, y: 35 },
    },
    {
      id: "law-and-terror-reclassify-the-human-being",
      actId: "total-dominion",
      order: 11,
      period: "AD 1935–1938",
      place: "Nuremberg and the Soviet Union",
      title: "Law and Terror Reclassify the Human Being",
      thesis:
        "Nazi racial legislation and Stalinist mass operations used distinct systems of classification to place whole categories of people outside ordinary protection.",
      body: [
        "Printed charts translated the Nuremberg Laws into grandparents, marriages and fractions of ancestry. The Reich Citizenship Law of September 1935 reserved full political membership for people classified as being of German or related blood. The Law for the Protection of German Blood and German Honour prohibited marriages and sexual relations between Jews and those the regime defined as German. Later decrees converted a religious and familial past into an administrative fate. A person’s neighbours, war service, profession, baptism or own understanding of identity could not answer a category constructed by the state.",
        "Exclusion advanced through schools, professions, property registers and public space before breaking into organised violence. During the November pogrom of 1938, Nazi organisations and participants across Germany and annexed Austria burned synagogues, smashed Jewish businesses, murdered Jews and sent about thirty thousand Jewish men to concentration camps. The regime presented the violence as spontaneous anger and imposed a collective fine on its victims. Party direction, police orders, racial law and expropriation had converged: citizenship was removed first, making every later assault easier to administer and harder to contest.",
        "Across the Soviet Union, the Great Terror followed a different ideological classification and institutional path. NKVD Order No. 00447 set regional quotas for the arrest, execution or imprisonment of people labelled former kulaks, criminals and anti-Soviet elements; other operations targeted national categories. Confession was manufactured, association became guilt and local officials competed under centrally approved targets. The Nazi and Stalinist systems did not share the same victims, racial doctrine or timetable. Each pushed rule beyond obedience toward total domination, isolating human beings until ideology and terror could decide who they were, what reality meant and whether ordinary law reached them at all.",
      ],
      image: `${imageRoot}/11-archival-law-and-terror-reclassify-human-being.avif`,
      imageAlt:
        "The Nuremberg racial chart and NKVD Order 00447 occupy separate document planes with their dates and systems of classification kept distinct.",
      imagePosition: "50% center",
      visualLabel:
        "Nuremberg racial chart · 14 November 1935 | NKVD Order 00447 · 30 July 1937",
      visualTone: "archival-only-static",
      side: "left",
      sourceIds: [
        "ghdi-nuremberg-laws-1935",
        "getty-naumov-road-terror-1999",
        "arendt-totalitarianism-1951",
      ],
      evidence: [
        "The Nuremberg Laws of September 1935 stripped Jews of Reich citizenship and prohibited marriages and sexual relations between Jews and people classified as German or related blood.",
        "NKVD Order No. 00447 initiated a mass operation in 1937 using centrally approved categories and numerical limits for execution or imprisonment that regional officials sought to expand.",
      ],
      map: { x: 58, y: 42 },
      interaction: {
        kind: "chapter-v2",
        family: "record",
        variant: "lose-the-protecting-document",
        prompt: "Lose the protecting document",
        accessibleSummary:
          "Four static document states follow a recognised citizen, a stateless refugee, a Nansen passport holder and a German Jew deprived of full citizenship, showing what a document can and cannot guarantee.",
        initialId: "recognised-citizen",
        records: [
          {
            id: "recognised-citizen",
            label: "Citizen",
            period: "AD 1914",
            kicker: "A polity stands behind the paper",
            detail:
              "An ordinary passport records identity and nationality because a recognised state accepts the bearer as a member and other states accept that guarantee.",
            fields: [
              { label: "Document", value: "National passport" },
              {
                label: "Status",
                value: "Citizen of an internationally recognised state",
              },
              {
                label: "Protection",
                value:
                  "Domestic rights and diplomatic standing rest on membership",
              },
            ],
            outcome:
              "The paper works because institutions acknowledge the political person it names.",
          },
          {
            id: "stateless-refugee",
            label: "Refugee",
            period: "AD 1921",
            kicker: "The state withdraws",
            detail:
              "Revolution, denationalisation or imperial collapse leaves a person outside the passport system, often unable to cross a border or establish lawful residence.",
            fields: [
              {
                label: "Document",
                value: "Expired paper or no recognised passport",
              },
              {
                label: "Status",
                value: "No state accepts the bearer as its national",
              },
              {
                label: "Exposure",
                value:
                  "Residence, work and movement depend on discretionary permission",
              },
            ],
            outcome:
              "Rights remain written in declarations while no government is answerable for securing them.",
          },
          {
            id: "nansen-holder",
            label: "Nansen passport holder",
            period: "AD 1922",
            kicker: "International recognition without nationality",
            detail:
              "The League-backed certificate gives a stateless refugee an identity that participating governments can recognise for travel.",
            fields: [
              { label: "Document", value: "Nansen passport" },
              {
                label: "Status",
                value: "Recognised refugee, not restored citizen",
              },
              {
                label: "Achievement",
                value: "Lawful cross-border movement becomes possible",
              },
            ],
            outcome:
              "International administration can relieve statelessness without supplying the lost political home.",
          },
          {
            id: "citizenship-stripped",
            label: "Citizenship stripped",
            period: "AD 1935",
            kicker: "Law turns ancestry into fate",
            detail:
              "The Nazi state reclassifies German Jews as subjects without full political rights and uses genealogy to determine exclusion.",
            fields: [
              {
                label: "Document",
                value: "Racial classification and restricted civil status",
              },
              {
                label: "Status",
                value: "German subject denied Reich citizenship",
              },
              {
                label: "Danger",
                value:
                  "The persecuting state controls the records that define the person",
              },
            ],
            outcome:
              "A bureaucracy designed to certify membership becomes an instrument for organised abandonment.",
          },
        ],
      },
    },
    {
      id: "the-pact-opens-poland",
      actId: "total-dominion",
      order: 12,
      period: "AD 1939–1942",
      place: "Moscow, Warsaw and German-occupied Europe",
      title: "The Pact Opens Poland",
      thesis:
        "The German–Soviet pact cleared the way for the destruction of Poland, after which German conquest extended racial occupation and a war of annihilation across Europe.",
      body: [
        "On 23 August 1939, German and Soviet foreign ministers signed a non-aggression pact in Moscow. A secret protocol placed Finland, Estonia and Latvia in the Soviet sphere, Lithuania principally in the German sphere, divided Poland along a proposed line and acknowledged Soviet interest in Bessarabia; a later agreement revised the division. Germany invaded Poland from the west on 1 September; Britain and France declared war two days later; the Soviet Union entered eastern Poland on 17 September. The Polish state fought between two invading powers and was partitioned. Soviet authorities deported civilians and executed Polish prisoners, including thousands murdered by the NKVD at Katyn and related sites.",
        "German occupation attacked the Polish nation and made racial hierarchy a form of government. Officials annexed western districts, expelled Poles, confiscated property, closed institutions and murdered members of the educated and political elite. Jews were marked, dispossessed, concentrated and forced into ghettos under conditions of hunger and disease. Elsewhere, rapid German victories brought Denmark, Norway, the Low Countries, France, Yugoslavia and Greece under direct or collaborating regimes of unequal severity. Occupation did not mean one uniform system; everywhere it subordinated law and human life to German war and racial aims.",
        "Germany invaded the Soviet Union on 22 June 1941, breaking the pact and opening the largest land war in history. Military orders treated Soviet political officers and many civilians as categories outside protection. Einsatzgruppen and other German units, aided in varying places by police, auxiliaries and collaborators, shot Jewish communities behind the front. The invasion joined anti-Bolshevik war to racial colonisation and mass murder. Soviet resistance absorbed catastrophic losses, relocated industry eastward and eventually stopped the advance before Moscow; the war’s centre of gravity moved into eastern Europe.",
        "The European civil war again became inseparable from world power. Britain fought through imperial bases, armies and resources; Commonwealth and colonial troops served across several theatres; the United States supplied the Allies before entering after Japan’s attack on Pearl Harbor; Japan pursued its own empire across China, Southeast Asia and the Pacific. These conflicts had causes and actors beyond Europe. Their conjunction came from a world already organised through imperial territories, maritime command, industrial supply and competing great powers. Europe’s war had opened every circuit at once.",
      ],
      image: `${imageRoot}/12-archival-the-pact-opens-poland.avif`,
      imageAlt:
        "The German–Soviet secret protocol, a dated invasion map and distinct German and Soviet occupation records form a four-part sequence.",
      imagePosition: "50% center",
      visualLabel:
        "Secret protocol · 23 August 1939 | German and Soviet invasion records",
      visualTone: "archival-only-static",
      side: "right",
      sourceIds: [
        "molotov-ribbentrop-pact-1939",
        "snyder-bloodlands-2010",
        "mazower-1998",
      ],
      evidence: [
        "The secret protocol to the German–Soviet pact divided territories in eastern Europe into spheres of interest before Germany and the Soviet Union invaded Poland from west and east.",
        "Operation Barbarossa began on 22 June 1941 and was conceived by Nazi Germany as both a military campaign and a racial-ideological war of destruction.",
      ],
      map: { x: 63, y: 41 },
    },
    {
      id: "european-jewry-is-marked-for-murder",
      actId: "total-dominion",
      order: 13,
      period: "AD 1941–1944",
      place: "German-occupied Europe",
      title: "European Jewry Is Marked for Murder",
      thesis:
        "Nazi Germany joined racial ideology, state offices, occupation power, mass shooting, rail transport and killing centres in an attempt to murder every Jew it could reach.",
      body: [
        "Before the war, about nine and a half million Jews lived in Europe. They spoke many languages, held different religious and political commitments, and belonged to towns, cities and nations from Britain to the Soviet borderlands. German conquest placed most of them within Nazi reach. Registration identified people; decrees removed work and property; badges marked bodies; ghettos concentrated families behind walls and guards. Hunger, disease and forced labour killed many before deportation. Each measure narrowed the space in which a Jewish person could act while making the individual increasingly visible to a persecuting administration.",
        "The invasion of the Soviet Union brought systematic mass shooting. German Einsatzgruppen, Order Police battalions and other units, with local auxiliaries and collaborators in many places, assembled Jewish men, women and children at ravines, pits and forests and murdered them by gunfire. At Babyn Yar outside Kyiv, German units and auxiliaries shot 33,771 Jews on 29 and 30 September 1941 according to the perpetrators’ own report. Similar actions crossed the occupied east. The killing was public enough to require roads, cordons, transport, lists, ammunition and the participation or witness of many institutions and people.",
        "Deportation trains then carried Jews from ghettos and communities across occupied Europe to killing centres. Chełmno used gas vans; Bełżec, Sobibór and Treblinka formed the principal killing sites of Operation Reinhard; Auschwitz-Birkenau combined a vast camp complex with mass killing by gas. The Wannsee meeting of January 1942 coordinated agencies already participating in the Final Solution. Railway offices scheduled cars, police guarded transports, ministries negotiated the surrender of Jews from allied and occupied states, and camp personnel converted arrivals into a repeated procedure of selection and death.",
        "Jews acted under conditions designed to make effective action impossible. Families hid children, preserved diaries and photographs, organised food and schools inside ghettos, escaped to forests, joined partisan groups and revolted at Warsaw, Treblinka, Sobibór and Auschwitz. Individuals, churches, diplomats and resistance networks helped some Jews evade capture; in Denmark, civil society and organised resistance, aided by Swedish reception, carried most of the country’s Jews to safety. Many other authorities and neighbours collaborated, denounced or appropriated. Rescue remained the exception inside a continental system built to close every exit.",
        "Nazi Germany and its collaborators murdered six million Jews, destroying roughly two-thirds of European Jewry. The regime also persecuted and murdered Roma and Sinti, disabled people, Soviet prisoners of war, Polish civilians, political opponents, gay men and others under related and distinct programmes of violence. The Holocaust was the attempt to annihilate the Jews as a people everywhere German power could reach. Liberation ended the killing where Allied armies arrived; it could not restore the murdered families, languages, congregations and neighbourhoods whose absence became part of Europe’s landscape.",
      ],
      image: `${imageRoot}/13-archival-european-jewry-marked-for-murder.avif`,
      imageAlt:
        "The named Münzer family before persecution appears beside a Drancy deportation list, the Stahlecker perpetrator map, the Auschwitz Protocols camp map and named child survivors after liberation.",
      imagePosition: "50% center",
      visualLabel:
        "Münzer family · Drancy list · perpetrator and camp maps · named survivors",
      visualTone: "archival-only-static",
      side: "left",
      sourceIds: [
        "ushmm-final-solution",
        "yad-vashem-shoah-collections",
        "hilberg-destruction-european-jews-2003",
        "friedlander-nazi-germany-jews-1997-2007",
      ],
      evidence: [
        "Nazi Germany and its collaborators murdered six million European Jews through mass shooting, deliberate deprivation, forced labour, deportation and killing centres.",
        "The perpetrators’ report for 29–30 September 1941 recorded 33,771 Jews murdered at Babyn Yar outside Kyiv.",
        "The Wannsee Conference coordinated the participation of German ministries and agencies in a murder programme already under way.",
        "Jewish communities preserved diaries, photographs, underground archives and records of resistance that now form an indispensable documentary account of the persecution and murder.",
      ],
      map: { x: 61, y: 43 },
    },
    {
      id: "berlin-falls-and-europe-is-divided",
      actId: "total-dominion",
      order: 14,
      period: "AD 1945",
      place: "Berlin, Yalta and Potsdam",
      title: "Berlin Falls and Europe Is Divided",
      thesis:
        "The destruction of Nazi Germany ended the European civil war in liberation, occupation and a transfer of continental power to the United States and Soviet Union.",
      body: [
        "Soviet artillery opened against Berlin in April 1945 after an advance that had carried the Red Army from the disasters of 1941 across eastern Europe. American, British, Canadian, French, Polish and other Allied forces had crossed Germany from the west after liberating western Europe; Soviet forces, including soldiers from across the USSR, bore the principal weight of destroying the Wehrmacht on the eastern front. Hitler killed himself on 30 April. Germany signed unconditional surrender in early May. No German state remained capable of governing, and the victorious armies divided responsibility for occupation.",
        "Liberation opened camps and prisons onto a continent already filled with displaced people. Survivors searched lists and railway stations for relatives. Former forced labourers, prisoners of war, refugees, soldiers and civilians moved through ruined transport systems. Hunger and disease persisted. Sexual violence accompanied conquest, especially on the eastern advance, while revenge and expulsion uprooted German populations from territories transferred to Poland and the Soviet Union and from restored Czechoslovakia. Victory removed the criminal regime without returning Europe to the social world that had existed before it.",
        "At Yalta and Potsdam, Allied leaders addressed occupation zones, borders, reparations and the treatment of Germany. Poland shifted west; Soviet authority stood across eastern and central Europe; the United States remained militarily and economically indispensable in the west. Britain and France were victors with empires, armies and global responsibilities, though neither could restore the continent’s former command of world affairs. The war had made American productive power and Soviet military power decisive inside Europe. The global system Europe had built now transmitted influence toward the continent as much as away from it.",
        "The struggle from 1914 to 1945 had been a European civil war because its central questions concerned Europe’s political order: which nations would rule which territories, whether revolution would replace inherited states, whether citizenship rested on law or race, and whether any limit stood above a movement claiming history’s authority. It became two world wars because Europe possessed empires, sea lanes, finance, industries and rival powers with global reach. In 1945 those questions had consumed the institutions that carried them. The continent survived in ruins, divided beneath powers larger than any European state.",
      ],
      image: `${imageRoot}/14-archival-berlin-falls-and-europe-is-divided.avif`,
      imageAlt:
        "Otto Donath’s 1945 panorama of ruined Berlin is overlaid by a United States Army map of the American, British, French and Soviet occupation zones.",
      imagePosition: "50% center",
      visualLabel:
        "Otto Donath · Berlin, 1945 | U.S. Army occupation-zones map",
      visualTone: "archival-only-static",
      side: "right",
      sourceIds: [
        "kershaw-to-hell-and-back-2015",
        "potsdam-agreement-1945",
        "judt-2005",
        "mazower-1998",
      ],
      evidence: [
        "Germany surrendered unconditionally in May 1945 after Soviet forces captured Berlin and the western Allies occupied the remainder of the country from the west and south.",
        "The Potsdam settlement placed Germany and Berlin under four-power occupation and recognised major territorial changes that moved Poland westward.",
        "By 1945 the United States and Soviet Union possessed the military, industrial and political weight that structured Europe’s post-war division.",
      ],
      map: { x: 56, y: 35 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "open-the-fault-lines",
        prompt: "Open the fault lines",
        accessibleSummary:
          "Five complete dated states align state and empire, citizenship, mass politics, industrial mobilisation and party terror from 1871 to 1945, showing how the layers cease to support one another and split the continent.",
        initialId: "balance-1871",
        records: [
          {
            id: "balance-1871",
            label: "A new balance",
            period: "AD 1871",
            kicker: "The layers still align",
            detail:
              "A new German nation-state enters a Europe of dynastic empires, expanding citizenship and global imperial competition.",
            fields: [
              {
                label: "State and empire",
                value: "German union shifts the continental balance",
              },
              {
                label: "Citizenship",
                value:
                  "Legal equality expands within unequal national and imperial orders",
              },
              {
                label: "Mass politics",
                value:
                  "Parties, newspapers and associations enlarge public participation",
              },
              {
                label: "Industrial mobilisation",
                value:
                  "Rail and factory capacity grow under civilian and military planning",
              },
              {
                label: "Party terror",
                value:
                  "No movement yet commands the state as an unlimited instrument",
              },
            ],
            outcome:
              "National achievement and imperial hierarchy coexist inside an armed diplomatic order.",
            points: [
              {
                id: "versailles",
                label: "Versailles",
                detail: "German imperial proclamation inside defeated France.",
                x: 43,
                y: 45,
              },
              {
                id: "berlin",
                label: "Berlin",
                detail: "The new centre of continental power.",
                x: 56,
                y: 35,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "mobilisation-1914",
            label: "The machine activates",
            period: "AD 1914",
            kicker: "Industrial power enters war",
            detail:
              "Alliance crisis and political decisions redirect railways, factories, empires and mass citizenship toward continental war.",
            fields: [
              {
                label: "State and empire",
                value:
                  "Four imperial orders enter a war for security and position",
              },
              {
                label: "Citizenship",
                value:
                  "Mass conscription binds political membership to military service",
              },
              {
                label: "Mass politics",
                value:
                  "Parties and publics rally, divide or submit under emergency",
              },
              {
                label: "Industrial mobilisation",
                value: "Schedules, artillery and production join front to home",
              },
              {
                label: "Party terror",
                value:
                  "Wartime coercion widens while plural institutions remain",
              },
            ],
            outcome:
              "Europe’s globally connected strength transmits its internal war across the earth.",
            points: [
              {
                id: "sarajevo",
                label: "Sarajevo",
                detail: "The assassination opens the diplomatic crisis.",
                x: 59,
                y: 55,
              },
              {
                id: "marne",
                label: "Marne",
                detail: "The opening campaign fails to decide the war.",
                x: 43,
                y: 46,
              },
              {
                id: "petrograd",
                label: "Petrograd",
                detail: "Mobilisation and war strain the Russian Empire.",
                x: 75,
                y: 22,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
            ],
          },
          {
            id: "settlement-1919",
            label: "The peace separates",
            period: "AD 1919",
            kicker: "Nations and minorities",
            detail:
              "Empires fall and new states gain sovereignty while minorities, refugees and stateless people expose the limits of nationally guaranteed rights.",
            fields: [
              {
                label: "State and empire",
                value:
                  "New and enlarged nation-states replace imperial centres",
              },
              {
                label: "Citizenship",
                value:
                  "Nationality becomes the practical gateway to protected rights",
              },
              {
                label: "Mass politics",
                value:
                  "Veterans, revolutionaries and paramilitaries contest the settlement",
              },
              {
                label: "Industrial mobilisation",
                value:
                  "War economies demobilise unevenly amid debt and scarcity",
              },
              {
                label: "Party terror",
                value:
                  "Bolshevik coercion and counter-revolutionary violence persist",
              },
            ],
            outcome:
              "The treaty map carries political abandonment inside its new borders.",
            points: [
              {
                id: "paris",
                label: "Paris",
                detail: "The treaties redraw Europe.",
                x: 42,
                y: 45,
              },
              {
                id: "geneva",
                label: "Geneva",
                detail:
                  "The League administers minority and refugee questions.",
                x: 47,
                y: 50,
              },
              {
                id: "warsaw",
                label: "Warsaw",
                detail: "Restored Poland stands among disputed frontiers.",
                x: 62,
                y: 38,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
            ],
          },
          {
            id: "movement-state-1933",
            label: "The movement becomes law",
            period: "AD 1933–1938",
            kicker: "Ideology enters every office",
            detail:
              "Nazi rule destroys German pluralism while Stalinist terror uses party and police power to remake society through fear and classification.",
            fields: [
              {
                label: "State and empire",
                value:
                  "Government becomes an instrument of ideological expansion",
              },
              {
                label: "Citizenship",
                value: "Nazi racial law withdraws equal membership from Jews",
              },
              {
                label: "Mass politics",
                value:
                  "Organised plurality gives way to compulsory mobilisation and isolation",
              },
              {
                label: "Industrial mobilisation",
                value:
                  "Rearmament and command planning prepare societies for war",
              },
              {
                label: "Party terror",
                value:
                  "Police, denunciation and camps pursue categories of alleged enemies",
              },
            ],
            outcome:
              "The layers no longer restrain power; they carry its claims into the individual life.",
            points: [
              {
                id: "berlin",
                label: "Berlin",
                detail:
                  "Nazi party and state institutions are coordinated under Hitler.",
                x: 56,
                y: 35,
              },
              {
                id: "nuremberg",
                label: "Nuremberg",
                detail: "Racial classification becomes statute.",
                x: 54,
                y: 44,
              },
              {
                id: "moscow",
                label: "Moscow",
                detail:
                  "Party and secret-police command drive mass operations.",
                x: 78,
                y: 35,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
            ],
          },
          {
            id: "ruin-1945",
            label: "The continent lies open",
            period: "AD 1945",
            kicker: "Every layer is broken or seized",
            detail:
              "Defeat, genocide, liberation and occupation leave Europe physically ruined, morally wounded and divided beneath American and Soviet power.",
            fields: [
              {
                label: "State and empire",
                value:
                  "Germany is occupied; European empires face accelerated dissolution",
              },
              {
                label: "Citizenship",
                value:
                  "Survivors and displaced millions search for a political home",
              },
              {
                label: "Mass politics",
                value:
                  "Democratic reconstruction and Soviet-controlled rule begin on opposite roads",
              },
              {
                label: "Industrial mobilisation",
                value:
                  "Destroyed cities and factories stand beside unmatched American capacity",
              },
              {
                label: "Party terror",
                value:
                  "Nazi rule ends; Soviet security power advances with occupation",
              },
            ],
            outcome:
              "The European civil war ends only after destroying the order over which it was fought.",
            points: [
              {
                id: "berlin",
                label: "Berlin",
                detail:
                  "Defeat and four-power occupation meet in the ruined capital.",
                x: 56,
                y: 35,
              },
              {
                id: "auschwitz",
                label: "Auschwitz",
                detail:
                  "The liberated camp complex records the continent-wide programme of murder.",
                x: 60,
                y: 42,
              },
              {
                id: "yalta",
                label: "Yalta",
                detail:
                  "Allied decisions anticipate occupation and post-war division.",
                x: 76,
                y: 58,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
            ],
          },
        ],
      },
    },
  ],
};
