import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/society-beyond-kin";

export const societyBeyondKin: ChapterDefinition = {
  slug: "society-beyond-kin",
  number: "09",
  title: "A Society Beyond Kin",
  openingTitleLines: ["A Society", "Beyond Kin"],
  period: "AD 500–1300",
  claim:
    "The Western Church broke the institutions that kept marriage, inheritance and obligation inside the clan. Europeans rebuilt social life through monasteries, fraternities, communes, guilds and universities—communities made by oath, rule and office rather than blood.",
  openingClaim:
    "By remaking marriage, the Western Church weakened the clan. Europeans rebuilt social life through oath, rule and office rather than blood.",
  theme: {
    id: "kin",
    label: "From blood to oath",
  },
  openingAction: "Cross the forbidden line",
  mapLabel:
    "The marriage courts, abbeys, guildhalls, communes and universities that opened society beyond the clan",
  routeImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Marriage canons · penitentials · charters · monastic rules · fraternity statutes · communal oaths · seals · legal glosses · university privileges",
  acts: [
    {
      id: "break-clan",
      number: "I",
      label: "The Church breaks the clan",
      period: "AD 500–1215",
      title: "Marriage Crosses the Forbidden Line",
      detail:
        "A widening field of forbidden kin, the suppression of inherited marriage strategies and the rule of mutual consent pull marriage out of the lineage’s exclusive control.",
    },
    {
      id: "chosen-brothers",
      number: "II",
      label: "Strangers become brothers",
      period: "AD 900–1250",
      title: "Rule Creates a Chosen House",
      detail:
        "Property leaves the inheritance line, monasteries organise unrelated people under one rule, and fraternities turn mutual aid into a sworn obligation.",
    },
    {
      id: "city-swears",
      number: "III",
      label: "The city swears itself together",
      period: "AD 1050–1250",
      title: "The Oath Makes a Public Body",
      detail:
        "Communes bind rival households into one association, then govern through elected offices, common seals, written decisions and property no family owns.",
    },
    {
      id: "body-endures",
      number: "IV",
      label: "The body becomes immortal",
      period: "AD 1140–1300",
      title: "Law Teaches Institutions to Survive",
      detail:
        "Canonists name the collective body, students organise as nations abroad, and offices, archives and property let an institution outlive every member.",
    },
  ],
  ending: {
    period: "AD 1300",
    title: "Europe has learned to join itself",
    detail:
      "The Church had weakened the world in which blood decided marriage, property and obligation. In its place stood monasteries, fraternities, guilds, communes and universities: bodies entered by promise, governed by rule and made durable by law. Europeans could now cooperate with people they had not been born to trust. The next road would carry those promises farther than the people who made them.",
    image: `${imageRoot}/13-europe-joins-itself.avif`,
    nextPeriod: "AD 950–1350",
  },
  returnHash: "society-beyond-kin",
  nextHash: "commercial-revolution",
  nextTitle: "The Medieval Commercial Revolution",
  nextSlug: "medieval-commercial-revolution",
  movements: [
    {
      id: "marriage-is-forbidden",
      actId: "break-clan",
      order: 1,
      period: "c. AD 500–900",
      place: "Parish churches and episcopal councils · the Latin West",
      title: "The Marriage Is Forbidden",
      thesis:
        "The Western Church made the lineage’s most useful marriages unlawful and placed an expanding circle of kin under ecclesiastical prohibition.",
      body: [
        "A marriage once kept land, protection and vengeance inside the lineage. A cousin was already known; a widow could be taken by her husband’s brother; an alliance could be renewed by marrying into the same household again. Such unions did more than join two people. They tightened a compact group in which property, obligation and authority travelled along remembered lines of blood.",
        "The Western Church entered that machinery and began to stop it. Councils, bishops and penitentials condemned unions between cousins, affines and step-relatives. Spiritual kin created by baptism could also bar a marriage. Levirate unions, polygyny and concubinage lost legitimacy. The prohibited circle widened so far that an elite family planning a match had to look beyond the people with whom it already shared ancestors, marriage ties and ritual kinship.",
        "This was not private advice. A priest could refuse the threshold, a bishop could order separation, and rivals could challenge a union before an ecclesiastical court. Genealogy became a field the Church inspected. Every ruling compelled households to remember the boundary. Every forbidden match cut one path by which a lineage reproduced itself. Across generations, the old closed circuit—kin marrying kin, land returning to kin, protection staying with kin—became harder to maintain.",
      ],
      image: `${imageRoot}/01-marriage-is-forbidden.avif`,
      imageAlt:
        "A priest examines a kinship parchment between a couple and two family groups at a Romanesque church threshold.",
      imagePosition: "center center",
      mobileImagePosition: "66% center",
      visualTone: "forbidden-threshold",
      side: "left",
      sourceIds: ["schulz-2019", "henrich-2020", "goody-1983", "brundage-1987"],
      evidence: [
        "Western conciliar canons and penitentials repeatedly name consanguinity, affinity, spiritual kinship and inherited marriage practices as forbidden unions.",
        "Ecclesiastical jurisdiction turned genealogy into evidence that could prevent a marriage or dissolve an unlawful one.",
      ],
      map: { x: 51, y: 58 },
    },
    {
      id: "circle-opens-outward",
      actId: "break-clan",
      order: 2,
      period: "c. AD 600–1215",
      place: "The Latin West · from local parishes to the Lateran",
      title: "The Circle Opens Outward",
      thesis:
        "By blocking close and repeated unions, the Church forced households to seek spouses, allies and futures beyond the dense core of kin.",
      body: [
        "The rule worked through repetition. One marriage crossed a village boundary; another linked households that had never shared an ancestor anyone could name. Daughters and sons left the tightest circle to found new homes. The web did not disappear, but its threads lengthened. The household had to negotiate with strangers, and the stranger became an in-law before becoming a trusted partner.",
        "The Church’s marriage programme struck the cluster from several sides at once. A widow ceased to be available for automatic absorption into her husband’s lineage. Polygyny and concubinage lost their place as parallel alliances. Divorce became difficult, so a powerful family could not as easily discard one connection and replace it with another. The ban on cousin marriage prevented property and loyalty from being endlessly folded inward.",
        "By the early thirteenth century, the formal prohibited degrees were narrowed, but the old intensive kinship system had already been broken open. The durable result was not one uniform family. It was a different social field: smaller households, more distant marriage partners and a growing need for cooperation that could not rely on common descent. The road beyond kin began at the forbidden line.",
      ],
      image: `${imageRoot}/02-circle-opens-outward.avif`,
      imageAlt:
        "A cleric traces widening circles of prohibited kin on parchment while two families stand apart.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualTone: "opened-circle",
      side: "right",
      sourceIds: ["schulz-2019", "henrich-2020", "goody-1983", "worby-2023"],
      evidence: [
        "Church rules targeted marriage within blood, affinal and spiritual kin while also restricting polygyny, concubinage, levirate and easy repudiation.",
        "The Fourth Lateran Council reduced the canonical prohibition to the fourth degree in 1215, preserving a substantial ban after centuries of wider restriction.",
      ],
      map: { x: 50, y: 54 },
      interaction: {
        kind: "kin-marriage",
        prompt: "Open the four lines the Church drew through the clan",
        accessibleSummary:
          "Four states show how bans on close kin, affines and spiritual kin, followed by the rule of consent, shifted marriage beyond lineage control.",
        states: [
          {
            id: "close-kin",
            label: "Blood kin",
            period: "consanguinity",
            detail:
              "A cousin is an obvious alliance inside a dense lineage. The prohibition makes the household search beyond its inherited circle.",
            rule: "Marriage within prohibited degrees of blood relationship is unlawful",
            oldBond:
              "Land and alliance are folded back into the same descent group",
            newReach: "A spouse must be sought among less familiar households",
            consequence: "Marriage extends cooperation beyond the clan",
          },
          {
            id: "affines",
            label: "Affines",
            period: "marriage kin",
            detail:
              "The Church treats a spouse’s relatives as a barrier to later unions, closing the route by which one lineage repeatedly absorbs another.",
            rule: "Affinity bars unions with a spouse’s close relatives",
            oldBond:
              "Widows and alliances remain available inside the same compact network",
            newReach:
              "Remarriage creates a connection outside the former alliance",
            consequence:
              "Marriage ties stop circulating inside one closed bloc",
          },
          {
            id: "spiritual-kin",
            label: "Godparents",
            period: "ritual kin",
            detail:
              "Baptism creates a relationship the Church treats as real enough to forbid marriage, placing its own ritual bond across lineage strategy.",
            rule: "Spiritual kinship created at baptism can impede marriage",
            oldBond:
              "Ritual alliance is recruited as another route for family consolidation",
            newReach:
              "The Church defines a field of obligation not made by blood",
            consequence:
              "Institutional kinship begins to rival natural kinship",
          },
          {
            id: "consent",
            label: "Consent",
            period: "two voices",
            detail:
              "When the present consent of woman and man makes the bond, their spoken will becomes the act the court must hear.",
            rule: "Mutual present consent creates a valid marriage",
            oldBond:
              "The lineage treats marriage as an exchange it can arrange",
            newReach: "The couple can make a binding union before witnesses",
            consequence: "The household loses exclusive command of the bond",
          },
        ],
      },
    },
    {
      id: "two-voices-make-bond",
      actId: "break-clan",
      order: 3,
      period: "c. AD 1100–1250",
      place: "Church doors and ecclesiastical courts · western Europe",
      title: "Two Voices Make the Bond",
      thesis:
        "Canon law made the present consent of woman and man the decisive act of marriage, moving authority from the lineage to two speaking persons.",
      body: [
        "At the church door, no father’s command could substitute for the two voices. Canon lawyers gathered the inherited rules of the Latin Church and sharpened one principle: marriage was made by the present consent of the man and the woman. A priest blessed it, witnesses remembered it and families celebrated it, but the bond itself arose when the pair gave themselves to one another.",
        "That rule placed a new kind of person before the court. A woman could say she had never consented. A man could be confronted with words he had spoken before witnesses. Secret unions created hard cases and public solemnisation was increasingly demanded, yet the legal centre held: the lineage was not the contracting party. Parents possessed influence, property and force; they no longer possessed the only act that made the marriage.",
        "Consent therefore completed what the kinship bans had begun. The Church first forced marriage outward, then located its decisive act inside the wills of two individuals. The couple did not become modern or independent of household life. They became legible as persons capable of creating an obligation that even their kin had to recognise.",
      ],
      image: `${imageRoot}/03-two-voices-make-bond.avif`,
      imageAlt:
        "A woman and man exchange consent before a priest and witnesses at an open Romanesque church door.",
      imagePosition: "center center",
      mobileImagePosition: "63% center",
      visualTone: "spoken-bond",
      side: "left",
      sourceIds: ["brundage-1987", "donahue-2007", "winroth-reynolds-2022"],
      evidence: [
        "Twelfth-century canon law treated words of present consent as the act that made an indissoluble marriage.",
        "Ecclesiastical litigation repeatedly turned on whether consent had been freely and validly exchanged before witnesses.",
      ],
      map: { x: 48, y: 54 },
      interaction: {
        kind: "kin-trace",
        prompt: "Follow authority from the household to the spoken bond",
        accessibleSummary:
          "Three stops connect mutual consent, remembered words and ecclesiastical judgment.",
        stops: [
          {
            id: "speak",
            label: "Speak",
            period: "consent",
            detail:
              "Woman and man exchange words in the present tense and create the bond between them.",
            instrument: "Mutual spoken consent",
            consequence:
              "No family member can speak the marriage into being for them",
            inheritance:
              "The individual appears as a maker of binding obligation",
          },
          {
            id: "witness",
            label: "Witness",
            period: "memory",
            detail:
              "Neighbors, kin or clergy carry the words into public memory when a union is challenged.",
            instrument: "Testimony and public solemnisation",
            consequence: "A private exchange becomes socially enforceable",
            inheritance:
              "Trust begins to rest on witnessed acts as well as status",
          },
          {
            id: "judge",
            label: "Judge",
            period: "court",
            detail:
              "An ecclesiastical judge asks what was said, whether it was free and what bond the words created.",
            instrument: "Procedure, testimony and sentence",
            consequence:
              "Marriage enters an impersonal forum beyond the lineage",
            inheritance:
              "A court can defend an obligation against family pressure",
          },
        ],
      },
    },
    {
      id: "land-leaves-lineage",
      actId: "chosen-brothers",
      order: 4,
      period: "c. AD 900–1150",
      place: "Cluny and monastic estates · Burgundy and the Latin West",
      title: "Land Leaves the Lineage",
      thesis:
        "Gifts to monasteries carried property out of the inheritance circuit and placed it in a house expected to survive every donor and heir.",
      body: [
        "A dying lord could have divided an estate among sons, nephews and daughters’ husbands. Instead he laid a charter, a clod of earth or a knife upon a monastic altar. The gift passed fields, mills, peasants and rents into a house whose members were not his descendants. His kin might witness, consent or later contest it, but the property had crossed the line.",
        "The attraction was spiritual and institutional at once. Monks promised prayer for the living and the dead. Their liturgy preserved a donor’s name after his household forgot it. Because the community did not produce heirs, its possessions did not fragment at each death. The abbey could accumulate an archive, defend boundaries and manage estates through a succession of abbots and officers.",
        "At Cluny, a foundation became the centre of a vast network of dependent houses. The old lineage had sought endurance by producing descendants. The monastery achieved it by replacing people while keeping rule, office, archive and property intact. Each bequest made that alternative more powerful: wealth no longer had to return to blood in order to survive.",
      ],
      image: `${imageRoot}/04-land-leaves-lineage.avif`,
      imageAlt:
        "An aging landholder transfers a charter and earth to a monk while his kin remain in shadow.",
      imagePosition: "center center",
      mobileImagePosition: "62% center",
      visualTone: "earth-and-charter",
      side: "right",
      sourceIds: ["rosser-2015", "berman-1983", "henrich-2020"],
      evidence: [
        "Monastic cartularies preserve gifts of land, mills, churches, rents and rights made for prayer and institutional memory.",
        "Religious houses held property across generations through offices and archives rather than biological succession.",
      ],
      map: { x: 48, y: 57 },
    },
    {
      id: "rule-makes-strangers-house",
      actId: "chosen-brothers",
      order: 5,
      period: "AD 910–1200",
      place: "Cluny, Cîteaux and their daughter houses · western Europe",
      title: "A Rule Makes Strangers One House",
      thesis:
        "The monastery proved that unrelated people could become one durable community through vow, common property, elected office and a shared rule.",
      body: [
        "The monk entered by leaving something behind: inheritance, household command, marriage and the ordinary future of descendants. At the gate he joined people born in other villages, families and ranks. They did not become one house because they discovered a common ancestor. They became one house because each submitted to the same hours, table, discipline and rule.",
        "The rule turned fraternity into an operating system. Bells divided the day. Offices assigned the cellar, guesthouse, library and fields. An abbot could die and another be chosen; the keys, books and obligations passed on. Property belonged to the house. Correction took place in chapter. The monastery joined personal renunciation to an institution capable of owning, judging, remembering and reproducing itself.",
        "Networks magnified the form. Cluniac houses looked toward one abbot; Cistercian houses used visitations and general chapters to preserve observance across distance. Monks carried letters, customs and trained personnel between foundations. Long before the commune and university, the monastery had shown Europe how to build a body from strangers and keep it alive by rule.",
      ],
      image: `${imageRoot}/05-rule-makes-strangers-house.avif`,
      imageAlt:
        "Monks of different origins sit in chapter around an abbot, a rule book, common bread and shared keys.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualTone: "chosen-house",
      side: "left",
      sourceIds: ["berman-1983", "rosser-2015", "reynolds-1997"],
      evidence: [
        "Monastic rules and customaries organise admission, office, discipline, common property, election and succession without reference to shared descent.",
        "Cluniac and Cistercian networks coordinated houses across local jurisdictions through visitation, chapter and written custom.",
      ],
      map: { x: 47, y: 57 },
      interaction: {
        kind: "chosen-house",
        prompt: "Build one house from four acts that blood cannot supply",
        accessibleSummary:
          "Four states show how vow, common property, office and rule turn unrelated monks into a durable house.",
        states: [
          {
            id: "vow",
            label: "Vow",
            period: "entry",
            detail:
              "A newcomer binds his future to a house composed mostly of people he has never met.",
            act: "A public promise of stability, obedience and a converted life",
            commonThing: "Time, labor, worship and daily provision",
            office: "The novice is received by an authorised community",
            consequence: "Chosen obligation replaces inherited membership",
          },
          {
            id: "common-property",
            label: "Common",
            period: "possession",
            detail:
              "Land and tools cease to belong to individual monks and remain with the house through every death.",
            act: "Renunciation and donation",
            commonThing: "Fields, mills, books, workshops and stores",
            office:
              "Cellarer, sacrist and estate officers administer defined goods",
            consequence: "Property can endure without passing to children",
          },
          {
            id: "office",
            label: "Office",
            period: "succession",
            detail:
              "The abbot and officers can be replaced while the authority and duties of their positions remain.",
            act: "Election, appointment and handover",
            commonThing:
              "Keys, archives, jurisdiction and institutional memory",
            office: "Abbot, prior, cellarer, sacrist and guest master",
            consequence: "Authority separates from the person who carries it",
          },
          {
            id: "rule",
            label: "Rule",
            period: "continuity",
            detail:
              "A shared text and repeated chapter make conduct answerable to something older than every living member.",
            act: "Reading, correction, visitation and common chapter",
            commonThing: "A way of life that can be copied into another house",
            office: "The chapter interprets and enforces observance",
            consequence: "The institution can reproduce itself across distance",
          },
        ],
      },
    },
    {
      id: "guild-creates-chosen-kin",
      actId: "chosen-brothers",
      order: 6,
      period: "c. AD 1150–1300",
      place: "Guildhalls and parish fraternities · England, Flanders and Italy",
      title: "A Guild Creates Chosen Kin",
      thesis:
        "Fraternities and guilds carried the monastic grammar into ordinary life, binding neighbors and craftspeople to mutual aid from apprenticeship to burial.",
      body: [
        "The guild brother was not necessarily a brother by blood. He might be a baker, weaver, widow, shopkeeper or migrant apprentice. Admission placed him inside a sworn circle with a common candle, feast, patron, chest and set of rules. Members paid dues, elected wardens and accepted fines. The association turned fellowship into an obligation that could be counted.",
        "Its work began where the household’s reach failed. A sick member received food. A widow received support. A traveler found companions. A dead member was carried, buried and remembered at an altar. Guilds maintained bridges, schools, chapels and almshouses because a voluntary body could gather small contributions and keep acting after the original donors were gone.",
        "The fraternity did not abolish family. It created another family beside it—chosen, recorded and governed. Its solidarity could cross neighborhood, occupation and origin, yet it also demanded obedience from members who quarrelled or withheld dues. Europe’s associational life grew not from warm feeling alone, but from the hard devices that made strangers dependable: oath, payment, office, sanction and memory.",
      ],
      image: `${imageRoot}/06-guild-creates-chosen-kin.avif`,
      imageAlt:
        "Craftspeople receive a new guild member around an oath book, alms chest, tools and burial cloth.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualTone: "chosen-kin",
      side: "right",
      sourceIds: ["rosser-2015", "reynolds-1997", "henrich-2020"],
      evidence: [
        "Guild and fraternity statutes record admission, dues, elected officers, discipline, worship, sickness relief and burial duties.",
        "Associations included women and men across occupations and ranks while creating enforceable obligations beyond the household.",
      ],
      map: { x: 45, y: 49 },
      interaction: {
        kind: "kin-trace",
        prompt: "Follow a guild member from admission to memory",
        accessibleSummary:
          "Three stops connect the oath of entry, mutual aid and burial into a chosen form of kinship.",
        stops: [
          {
            id: "enter",
            label: "Enter",
            period: "admission",
            detail:
              "A candidate pays, promises and is received before members who will enforce the rule.",
            instrument: "Oath, fee and entry in the roll",
            consequence: "A stranger acquires defined claims on the group",
            inheritance: "Membership can be made rather than inherited",
          },
          {
            id: "aid",
            label: "Aid",
            period: "life",
            detail:
              "Dues become food, care, credit or support when a member’s household cannot carry the burden alone.",
            instrument: "Common chest, wardens and scheduled contributions",
            consequence: "Risk is distributed across unrelated households",
            inheritance: "Mutual aid becomes an institutional duty",
          },
          {
            id: "remember",
            label: "Remember",
            period: "death",
            detail:
              "The guild accompanies the body, supports survivors and keeps the dead inside its liturgical memory.",
            instrument: "Burial cloth, candle, procession and memorial prayer",
            consequence:
              "The association performs the work once monopolised by kin",
            inheritance: "Chosen fraternity reaches beyond an individual life",
          },
        ],
      },
    },
    {
      id: "oath-makes-people",
      actId: "city-swears",
      order: 7,
      period: "c. AD 1050–1150",
      place: "Milan, Pisa and the cities of northern Italy",
      title: "An Oath Makes a People",
      thesis:
        "The commune began when rival households swore a common peace and treated their city as an association they had made together.",
      body: [
        "The medieval city contained blood feuds, episcopal lordship, noble towers, merchant wealth and armed neighborhoods. No single lineage could govern the whole without making enemies of the rest. The commune answered with an act available to people who shared no ancestor: the oath. Citizens promised peace, assistance and obedience to decisions made in common.",
        "The sworn association changed the scale of trust. Men who would not entrust vengeance to a rival family could entrust a gate, market or judgment to a consul chosen under oath. The commune summoned assemblies, raised forces, negotiated with bishops and lords and defended its liberties. Its authority did not descend from one household. It came from the body the households had sworn into existence.",
        "Great families, merchants and guilds fought to control the offices, and many inhabitants remained outside the ruling people. Inside that unequal field, the communal form established a lasting public capacity. A city could name itself, bind members, punish betrayal and renew its government. Strangers had made a body able to govern them.",
      ],
      image: `${imageRoot}/07-oath-makes-people.avif`,
      imageAlt:
        "Citizens from different households extend their hands toward a shared oath in a Romanesque communal square.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualTone: "civic-oath",
      side: "left",
      sourceIds: ["wickham-2015", "reynolds-1997", "berman-1983"],
      evidence: [
        "Communal documents and chronicles describe sworn associations, consuls, assemblies and collective claims against bishops and lords.",
        "The commune converted horizontal oath into public authority across rival households and urban groups.",
      ],
      map: { x: 50, y: 63 },
    },
    {
      id: "commune-governs-own-name",
      actId: "city-swears",
      order: 8,
      period: "c. AD 1100–1200",
      place: "Communal loggias and courts · northern and central Italy",
      title: "The Commune Governs in Its Own Name",
      thesis:
        "Elected consuls, councils, notaries and a common seal let the sworn city act as one authority while officeholders came and went.",
      body: [
        "An oath could found the association; government required machinery. Communes elected consuls for limited terms, assembled councils, appointed notaries and kept written decisions. A citizen no longer dealt only with a named lord. He met an office whose authority would pass to another person next year.",
        "The common seal made that abstraction visible. Pressed into wax, it authenticated a promise made by the city rather than by the current consul’s family. Notaries recorded purchases, alliances, judgments and privileges. The archive let later officers remember obligations they had not witnessed. A council could reverse a proposal, fine a member or send ambassadors in the commune’s name.",
        "Here the associational form became public power. The city owned buildings, walls, roads and revenue. It could sue, bargain, borrow and command. Factions still captured office and families still mattered, but no family could simply inherit the commune. Authority belonged to a body assembled through procedure and represented by replaceable people.",
      ],
      image: `${imageRoot}/08-commune-governs-own-name.avif`,
      imageAlt:
        "Communal consuls hear debate while a notary seals a charter beneath a Romanesque civic loggia.",
      imagePosition: "center center",
      mobileImagePosition: "58% center",
      visualTone: "seal-and-office",
      side: "right",
      sourceIds: ["wickham-2015", "reynolds-1997", "berman-1983"],
      evidence: [
        "Communal charters and chronicles show consuls, councils, assemblies, notaries, seals and collective property operating under the city’s name.",
        "Short terms and handovers distinguished the continuity of office from the careers and families of individual magistrates.",
      ],
      map: { x: 51, y: 63 },
      interaction: {
        kind: "sworn-commune",
        prompt: "Turn a sworn crowd into a government",
        accessibleSummary:
          "Four states show how oath, consuls, council and seal let a commune act as one public body.",
        states: [
          {
            id: "oath",
            label: "Oath",
            period: "found",
            detail:
              "Rival households promise peace and assistance to a body none of them owns alone.",
            instrument: "Collective sworn promise",
            authority: "The members bind one another directly",
            sharedPossession: "Peace, defense and civic obligation",
            consequence: "A people is made by act rather than descent",
          },
          {
            id: "consuls",
            label: "Consuls",
            period: "act",
            detail:
              "Elected magistrates carry authority for a term and then return its instruments to successors.",
            instrument: "Election, term, bench and handover",
            authority: "Office rather than household seniority",
            sharedPossession: "Justice, command and diplomatic voice",
            consequence: "Power becomes replaceable without disappearing",
          },
          {
            id: "council",
            label: "Council",
            period: "decide",
            detail:
              "A defined assembly debates and records decisions that bind members beyond the room.",
            instrument: "Summons, procedure, vote and notarial record",
            authority: "A decision attributed to the assembled commune",
            sharedPossession: "Rules, taxes, walls and common works",
            consequence: "Collective judgment becomes repeatable procedure",
          },
          {
            id: "seal",
            label: "Seal",
            period: "endure",
            detail:
              "Wax carries the city’s promise beyond the presence and lifetime of the people who approved it.",
            instrument: "Common seal, charter and archive",
            authority: "The commune’s name authenticates the act",
            sharedPossession: "Memory, credit and enforceable obligation",
            consequence: "The city can promise a future it will live to meet",
          },
        ],
      },
    },
    {
      id: "common-chest-many-keys",
      actId: "city-swears",
      order: 9,
      period: "c. AD 1150–1250",
      place: "Guildhalls, sacristies and communal archives · western cities",
      title: "The Common Chest Has Many Keys",
      thesis:
        "Shared property became trustworthy when no single officer or lineage could reach it alone.",
      body: [
        "The chest stood under more than one lock. One key belonged to a warden, another to a notary or fellow officer, a third to someone chosen by the members. The money, seal and charters inside could be reached only when the keepers came together. Wood and iron turned mistrust into a procedure.",
        "The device solved a central problem of life beyond kin. A family chest could be guarded by loyalty to the household head. A common chest belonged to people who might scarcely know one another and who expected officers to change. Multiple keys, inventories, witnessed openings and written accounts made collective possession a daily practice.",
        "Every association needed some version of the same discipline. The guild kept dues for sickness and burial. The commune guarded treaties and tax receipts. The chapter protected its seal and privileges. Trust moved out of the body of a patriarch and into arrangements that assumed temptation, divided control and preserved evidence. Strangers could cooperate because the institution did not require them to be saints.",
      ],
      image: `${imageRoot}/09-common-chest-many-keys.avif`,
      imageAlt:
        "Three keepers use separate keys to open a communal chest before a notary and witnesses.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualTone: "many-keys",
      side: "left",
      sourceIds: ["rosser-2015", "reynolds-1997", "berman-1983"],
      evidence: [
        "Guild, confraternity and civic statutes assign separate keys, inventories and accounting duties to multiple officeholders.",
        "Seals, charters and money were protected through divided custody because collective property had to survive each keeper.",
      ],
      map: { x: 48, y: 50 },
      interaction: {
        kind: "kin-trace",
        prompt: "Follow common property from suspicion to trust",
        accessibleSummary:
          "Three stops connect divided keys, witnessed accounts and an archive that survives its keepers.",
        stops: [
          {
            id: "divide",
            label: "Divide",
            period: "keys",
            detail:
              "No officer holds every key, so private access to the common goods is physically blocked.",
            instrument: "Chest with separate locks and custodians",
            consequence: "Control is divided before trust is asked for",
            inheritance: "Institutional design replaces household loyalty",
          },
          {
            id: "witness",
            label: "Witness",
            period: "accounts",
            detail:
              "The chest opens before others while withdrawals, deposits and objects are counted.",
            instrument: "Inventory, tally, notary and public handover",
            consequence: "Misuse leaves evidence and can be judged",
            inheritance: "Accountability becomes a repeated civic ritual",
          },
          {
            id: "preserve",
            label: "Preserve",
            period: "archive",
            detail:
              "New keepers receive the same seal, privileges and accounts from predecessors they need not have known.",
            instrument: "Archive, office term and witnessed succession",
            consequence: "Collective memory survives personal turnover",
            inheritance: "The body can hold a continuous past",
          },
        ],
      },
    },
    {
      id: "law-gives-body-name",
      actId: "body-endures",
      order: 10,
      period: "c. AD 1140–1250",
      place: "The schools and courts of Bologna",
      title: "Law Gives the Body a Name",
      thesis:
        "Canonists and civilians gave the practical association a legal grammar: one collective body could own, decide and act through changing members.",
      body: [
        "Monasteries, chapters and cities had behaved like durable bodies before jurists explained what such a body was. In the schools around Bologna, canon law and revived Roman law supplied a language equal to the fact. A universitas was a whole formed by members, capable of holding things and acting through authorised persons.",
        "The distinction solved succession. If an abbot died, the abbey’s field did not become ownerless. If consuls left office, the commune’s treaty did not vanish. The body remained while its representatives changed. Majority decision, election, delegated authority and common property could now be connected as parts of one legal person.",
        "This language spread through the Church because the Church already consisted of offices, chapters, houses and courts. It then served towns, guilds and universities confronting the same practical need. A charter from one body could be recognised by another, allowing institutions to meet across jurisdictions without reducing each agreement to the personal honour of living principals. Law made the institution visible to other institutions—and therefore able to defend property, jurisdiction and memory in its own name.",
      ],
      image: `${imageRoot}/10-law-gives-body-name.avif`,
      imageAlt:
        "A Bologna canon-law master explains common property and office to students and institutional representatives.",
      imagePosition: "center center",
      mobileImagePosition: "50% center",
      visualTone: "legal-body",
      side: "right",
      sourceIds: [
        "berman-1983",
        "winroth-reynolds-2022",
        "ridder-symoens-1992",
      ],
      evidence: [
        "Medieval canonists used the language of universitas, chapter, office and representation to distinguish a collective body from its members.",
        "Rules for election, majority action, common property and succession gave institutions a legal life through personnel change.",
      ],
      map: { x: 52, y: 63 },
    },
    {
      id: "students-become-nation",
      actId: "body-endures",
      order: 11,
      period: "AD 1155–1231",
      place: "Bologna and Paris · communities of masters and students",
      title: "Students Become a Nation Abroad",
      thesis:
        "Foreign students organised themselves into sworn nations and a university, using election and privilege to make strangers powerful in a city not their own.",
      body: [
        "The student arrived in Bologna without the protection of his household. He needed lodging, credit, books, teachers and a forum when a landlord or creditor pressed him. Others from distant regions faced the same exposure. They grouped themselves into nations, elected counsellors and joined those associations inside a larger universitas.",
        "Their collective strength reversed the ordinary relation between master and pupil. Students could hire teachers, regulate fees, boycott a lecture or threaten to depart together. Imperial privilege protected travelling scholars; later statutes and papal acts recognised corporate liberties. In Paris, the association formed differently around masters, but the answer was recognisably the same: strangers governed themselves through a body.",
        "The university made the chapter’s whole transformation visible. Members were not born into it. They entered, swore, studied, elected and left. The body retained privileges, offices and a name. Learning itself acquired an institutional home that could bargain with bishops, rulers and towns long after any cohort had scattered.",
      ],
      image: `${imageRoot}/11-students-become-nation.avif`,
      imageAlt:
        "Foreign students elect a rector beneath a Bologna portico before a common chest and privilege.",
      imagePosition: "center center",
      mobileImagePosition: "45% center",
      visualTone: "foreign-nation",
      side: "left",
      sourceIds: ["ridder-symoens-1992", "berman-1983", "reynolds-1997"],
      evidence: [
        "Bologna’s student nations and universities elected rectors, regulated members and negotiated collectively with teachers and city authorities.",
        "Privileges for scholars protected movement and recognised a body whose members came from many jurisdictions.",
      ],
      map: { x: 52, y: 63 },
      interaction: {
        kind: "kin-trace",
        prompt: "Follow a stranger into a university",
        accessibleSummary:
          "Three stops show how foreign origin becomes a student nation and then a legally recognised university.",
        stops: [
          {
            id: "arrive",
            label: "Arrive",
            period: "stranger",
            detail:
              "A student reaches a foreign city without the household protection that structured life at home.",
            instrument: "Travel, lodging contract and scholar’s privilege",
            consequence: "Distance exposes the limits of kin-based protection",
            inheritance: "Mobility creates a need for portable association",
          },
          {
            id: "nation",
            label: "Organise",
            period: "nation",
            detail:
              "Students of a broad geographic origin elect officers and discipline members as one sworn group.",
            instrument: "Membership roll, oath, dues and counsellors",
            consequence:
              "Foreigners acquire bargaining power through combination",
            inheritance: "Origin becomes the basis of a chosen legal body",
          },
          {
            id: "university",
            label: "Unite",
            period: "universitas",
            detail:
              "The nations join in a larger corporation able to elect a rector and negotiate in its own name.",
            instrument: "Rector, statute, seal and recognised privilege",
            consequence: "A temporary population gains durable government",
            inheritance:
              "Knowledge receives an institution that outlives its students",
          },
        ],
      },
    },
    {
      id: "institution-outlives-us",
      actId: "body-endures",
      order: 12,
      period: "c. AD 1200–1300",
      place: "Monasteries, guilds, communes and universities · the Latin West",
      title: "The Institution Outlives Us All",
      thesis:
        "Europe’s new bodies endured because membership changed while property, office, rule and record remained.",
      body: [
        "By 1300 the same grammar appeared across radically different communities. A monk took a vow, a guild member swore an oath, a citizen entered the commune and a student joined a nation. Each crossed a threshold from a life given by birth into an obligation made with people beyond the family.",
        "The body then separated the person from the place he held. Abbots, wardens, consuls and rectors died or completed their terms. Their successors received keys, seals, archives and duties. Land belonged to the house; money to the fraternity; walls to the commune; privileges to the university. None had to be divided among the officeholder’s children.",
        "This was Europe’s decisive answer to the clan the Church had broken open. The answer was not isolation. It was a denser world of chosen commitments—houses, brotherhoods, cities and schools able to demand loyalty, survive betrayal and remember the dead. Blood remained powerful. It no longer possessed society’s only durable form.",
      ],
      image: `${imageRoot}/12-institution-outlives-us.avif`,
      imageAlt:
        "An elderly officeholder hands a seal and key to his elected successor while the institution witnesses.",
      imagePosition: "center center",
      mobileImagePosition: "54% center",
      visualTone: "durable-body",
      side: "right",
      sourceIds: [
        "henrich-2020",
        "berman-1983",
        "reynolds-1997",
        "rosser-2015",
      ],
      evidence: [
        "Across religious houses, guilds, communes and universities, entry, election, office, common property and archives recur as instruments of continuity.",
        "The corporation’s decisive achievement was succession without inheritance: persons changed while the body’s rights and obligations remained.",
      ],
      map: { x: 49, y: 56 },
      interaction: {
        kind: "immortal-body",
        prompt: "See what changes—and what the body keeps",
        accessibleSummary:
          "Four states show how changing membership, office, property and jurisdiction produce an institution that outlives every participant.",
        states: [
          {
            id: "membership",
            label: "Members",
            period: "enter · leave",
            detail:
              "People join, serve, depart and die without dissolving the association they entered.",
            memberChanges: "One cohort replaces another",
            bodyKeeps: "Its name, rule and boundary of membership",
            actsThrough: "Admission, oath, discipline and release",
            inheritance: "Belonging can continue without common ancestry",
          },
          {
            id: "office",
            label: "Offices",
            period: "elect · replace",
            detail:
              "Authority passes from one person to another through an act the body controls.",
            memberChanges: "Abbot, warden, consul or rector",
            bodyKeeps: "The office’s competence, duties and instruments",
            actsThrough: "Election, term, account and handover",
            inheritance: "Power survives without becoming family property",
          },
          {
            id: "property",
            label: "Property",
            period: "hold · preserve",
            detail:
              "Land, money, books and buildings remain with the body rather than following members into inheritance.",
            memberChanges: "Donors, keepers and beneficiaries",
            bodyKeeps: "The common estate and the claims attached to it",
            actsThrough: "Seal, chest, charter, inventory and archive",
            inheritance: "Collective wealth accumulates across generations",
          },
          {
            id: "jurisdiction",
            label: "Jurisdiction",
            period: "judge · endure",
            detail:
              "The association can make rules, judge members and defend its liberty before other powers.",
            memberChanges: "Litigants, councillors and judges",
            bodyKeeps: "Its forum, privileges and remembered decisions",
            actsThrough: "Statute, council, court, sentence and appeal",
            inheritance:
              "A made community becomes a recognised part of public order",
          },
        ],
      },
    },
  ],
};
