import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/enlightenment-public-opinion";

export const enlightenmentPublicOpinion: ChapterDefinition = {
  slug: "enlightenment-public-opinion",
  number: "19",
  title: "The Enlightenment",
  openingTitleLines: ["The", "Enlightenment"],
  period: "AD 1680–1789",
  claim:
    "Europe’s presses, coffeehouses, journals, salons, clubs, academies and postal routes created a public able to compare laws, customs and rulers. Arguments acquired readers, reputations and pressure beyond the court that first received them. By 1789 public opinion had become a political power.",
  openingClaim:
    "A sentence marked at a London coffeehouse table could be copied in Amsterdam, disputed in Paris, tested in Edinburgh and carried into law at Vienna or Florence. Europe turned circulation into judgment and judgment into public authority.",
  hero: {
    image: `${imageRoot}/opening-continent-in-conversation.avif`,
    mobileImage: `${imageRoot}/opening-continent-in-conversation-mobile.avif`,
    imageAlt:
      "A London coffeehouse table holds a marked newspaper, shipping list, folded letter and steaming cup while a postal route carries the marked sentence toward continental reading rooms.",
    imagePosition: "center center",
    mobileImagePosition: "58% center",
    visualLabel: "The Continent in Conversation · press, letter and public judgment",
  },
  theme: {
    id: "conversation",
    label: "The Continent in Conversation",
  },
  openingAction: "Send the marked sentence",
  mapLabel:
    "The presses, coffeehouses, postal routes, salons, clubs, academies and government desks through which European argument acquired a public voice",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Newspapers · correspondence · dictionaries · periodical essays · encyclopaedia plates · reviews · reform decrees · pamphlets · electoral instructions",
  acts: [
    {
      id: "news-daily-appetite",
      number: "I",
      label: "News becomes a daily appetite",
      period: "AD 1680–1711",
      title: "News Becomes a Daily Appetite",
      detail:
        "Coffeehouses, refugee presses and critical dictionaries give Europe a faster common present and teach readers to follow an argument across borders.",
    },
    {
      id: "public-learns-to-judge",
      number: "II",
      label: "The public learns to judge",
      period: "AD 1711–1748",
      title: "The Public Learns to Judge",
      detail:
        "Periodical essays, travel and comparative law make manners, custom and government available for recurring public examination.",
    },
    {
      id: "continent-thinks-in-company",
      number: "III",
      label: "The continent thinks in company",
      period: "AD 1740–1786",
      title: "The Continent Thinks in Company",
      detail:
        "Encyclopaedia, university, club and reforming circle organise knowledge for collective use and carry criticism into the statute book.",
    },
    {
      id: "opinion-enters-government",
      number: "IV",
      label: "Opinion enters government",
      period: "AD 1740–1789",
      title: "Opinion Enters Government",
      detail:
        "Rulers answer a European audience through unequal programmes of reform, while the French public moves from criticism to constituent authority.",
    },
  ],
  ending: {
    period: "AD 1789",
    title: "Europe Learns to Judge Aloud",
    detail:
      "Readers sharing news had become a power that rulers courted, measured and feared. Presses, clubs, academies, markets and assemblies carried arguments through institutions no palace could command from end to end. A law now entered a European field of comparison, and a government’s reply could be printed beside its promise. While public opinion learned to judge authority in words, British mines and workshops were joining coal, machines, capital and skilled labour into a new command over material production.",
    image: `${imageRoot}/ending-europe-learns-to-judge-aloud.avif`,
    mobileImage: `${imageRoot}/ending-europe-learns-to-judge-aloud-mobile.avif`,
    nextPeriod: "AD 1700–1850",
  },
  returnHash: "enlightenment-public-opinion",
  nextHash: "rivalry-industrial-breakthrough",
  nextTitle: "Rivalry and the Industrial Breakthrough",
  nextSlug: "rivalry-industrial-breakthrough",
  movements: [
    {
      id: "coffeehouse-makes-a-present",
      actId: "news-daily-appetite",
      order: 1,
      period: "c. AD 1690–1711",
      place: "London",
      title: "The Coffeehouse Makes a Present",
      thesis:
        "Commercial news gathered strangers around the same dated sheets and gave London a common present renewed from one post to the next.",
      body: [
        "A London coffeehouse opened early enough to catch the morning post. For a penny, a customer bought coffee, company and access to papers that few households could gather alone. Shipping lists named vessels expected from the Baltic or the Levant. Advertisements offered books, medicines, auctions and missing property. Parliamentary reports, diplomatic intelligence and prices moved from a messenger’s packet to the proprietor’s table. A merchant looking for an overdue ship and a writer listening for an argument bent over the same sheet.",
        "The room sorted information by use. Marine insurers clustered near Lloyd’s coffeehouse, dealers and brokers developed their own preferred addresses, and political talk gave other houses a partisan reputation. Readers copied items into letters, challenged a report with news from another port and carried a memorable passage into the street. Spoken conversation supplied correction, ridicule and emphasis; print fixed the date and wording long enough for absent readers to answer. Regular posts and repeated publication made yesterday’s uncertainty visible against today’s report.",
        "No invitation from the royal court was required to enter this exchange. The coffeehouse depended on trade, proprietors, printers, carriers and customers whose reasons for reading differed. Their shared attention gave a report consequence. A failed project could become a joke across several rooms; a parliamentary speech could circulate beyond Westminster; the arrival of a fleet could alter prices before an official ceremony announced it. London’s public life acquired a daily pulse because commercial print let strangers inhabit the same moment and judge what belonged in it.",
      ],
      image: `${imageRoot}/01-coffeehouse-makes-a-present.avif`,
      imageAlt:
        "A candlelit London coffeehouse table is divided among a shipping list, parliamentary report, advertisement and essay as readers carry each printed item toward a different group.",
      imagePosition: "57% center",
      mobileImagePosition: "64% center",
      visualLabel: "Newspaper, post packet and four reading tables",
      visualTone: "coffeehouse-night",
      side: "left",
      sourceIds: ["melton-2001", "cowan-2005", "porter-2000"],
      evidence: [
        "Late seventeenth- and early eighteenth-century London coffeehouses supplied access to newspapers, commercial intelligence and conversation for the price of admission and a drink.",
        "Particular houses developed occupational and political clienteles, allowing printed reports to move through specialised communities and then back into wider urban discussion.",
      ],
      map: { x: 35, y: 44 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "coffeehouse-paper",
        prompt: "Make the coffeehouse paper",
        accessibleSummary:
          "Four printed items move from a compositor’s tray to different coffeehouse tables, showing how one issue gives strangers a common present for commerce, politics, purchase and criticism.",
        initialId: "shipping-news",
        records: [
          {
            id: "shipping-news",
            label: "Set the shipping news",
            period: "Morning post",
            kicker: "Arrival becomes public knowledge",
            detail:
              "Names of vessels, ports, cargoes and reported losses give merchants and insurers a dated field of shared uncertainty.",
            stageImage: `${imageRoot}/01-coffeehouse-makes-a-present.avif`,
            fields: [
              {
                label: "From the tray",
                value: "Port arrivals and sailing reports",
              },
              {
                label: "First table",
                value: "Merchants, captains and insurers",
              },
              {
                label: "Judgment",
                value: "Compare report, price and private letter",
              },
            ],
            outcome:
              "Commercial readers turn scattered arrivals into a common account of what has reached London and what remains at risk.",
          },
          {
            id: "parliamentary-report",
            label: "Set the parliamentary report",
            period: "Midday reading",
            kicker: "Westminster enters the room",
            detail:
              "A reported speech or division travels beyond the chamber and acquires comments from readers who hold no seat inside it.",
            stageImage: `${imageRoot}/01-coffeehouse-makes-a-present.avif`,
            fields: [
              {
                label: "From the tray",
                value: "Speech, division and ministerial news",
              },
              {
                label: "First table",
                value: "Partisan readers and office seekers",
              },
              {
                label: "Judgment",
                value: "Compare policy with interest and reputation",
              },
            ],
            outcome:
              "Political conduct gains an audience beyond court and Parliament, joined by the repeatable wording of print.",
          },
          {
            id: "advertisement",
            label: "Set the advertisement",
            period: "Afternoon trade",
            kicker: "The city declares its wants",
            detail:
              "Auctions, books, medicines, services and missing goods place private offers before readers who share no household or guild.",
            stageImage: `${imageRoot}/01-coffeehouse-makes-a-present.avif`,
            fields: [
              { label: "From the tray", value: "Paid notice and address" },
              { label: "First table", value: "Buyers, sellers and projectors" },
              {
                label: "Judgment",
                value: "Trust, compare and carry the notice onward",
              },
            ],
            outcome:
              "The printed issue binds public information to the market that finances its next appearance.",
          },
          {
            id: "periodical-essay",
            label: "Set the essay",
            period: "Evening conversation",
            kicker: "Manners become discussable",
            detail:
              "A compact essay gives conduct, taste or credulity a memorable argument that can be read aloud and answered at another table.",
            stageImage: `${imageRoot}/01-coffeehouse-makes-a-present.avif`,
            fields: [
              {
                label: "From the tray",
                value: "Signed voice or familiar persona",
              },
              { label: "First table", value: "Readers, writers and listeners" },
              {
                label: "Judgment",
                value: "Approve, ridicule, quote and reprint",
              },
            ],
            outcome:
              "The paper carries a common present beyond news into the recurring examination of public manners.",
          },
        ],
      },
    },
    {
      id: "amsterdam-prints-beyond-borders",
      actId: "news-daily-appetite",
      order: 2,
      period: "AD 1685–1710",
      place: "Amsterdam, Rotterdam and the European book routes",
      title: "Amsterdam Prints Beyond Borders",
      thesis:
        "Dutch presses joined refugee skill, commercial distribution and comparative liberty into a publishing engine for readers far beyond the republic.",
      body: [
        "Louis XIV revoked the Edict of Nantes in 1685 and drove French Protestants toward the Dutch Republic, England, Brandenburg and other places of refuge. In Amsterdam and Rotterdam, exiles arrived with French prose, scholarly contacts and knowledge of readers inside the kingdom they had left. Printers and booksellers could address that dispersed market from cities where licensing remained real but fragmented among provinces, towns, churches and guilds. A French manuscript could acquire a Dutch imprint and begin a European life its author’s own government had forbidden.",
        "The book moved through ordinary commerce. Catalogues travelled to fairs; agents negotiated editions and translations; bundles passed among booksellers who extended credit to one another. A suspect title might be packed beneath licensed stock, given a false imprint or broken into consignments that reduced one seizure’s cost. The same routes served devotional works, scholarly journals, scandal, philosophy and political news. Censorship shaped price and method without closing the circuit. Demand inside France helped sustain presses outside it.",
        "Dutch publishing gave the European argument redundancy. A prohibition issued in Paris could redirect a title through The Hague, Geneva, London or a provincial bookseller rather than erase it. Refugee editors compared reports from several states and wrote in a language read at courts and academies across the continent. Authors learned to imagine readers separated by frontier and confession; officials learned that an answer might already be on the road before their ban reached the border. The republic’s commercial infrastructure made intellectual escape reproducible.",
      ],
      image: `${imageRoot}/02-amsterdam-prints-beyond-borders.avif`,
      imageAlt:
        "A Dutch printer’s warehouse aligns a French manuscript, Amsterdam imprint, bookseller catalogue and packed book crate with routes crossing European frontiers.",
      imagePosition: "55% center",
      mobileImagePosition: "61% center",
      visualLabel: "Refugee manuscript, Dutch imprint and bookseller route",
      visualTone: "printer-warehouse",
      side: "right",
      sourceIds: [
        "melton-2001",
        "darnton-1982",
        "darnton-2018",
        "bots-waquet-1997",
      ],
      evidence: [
        "The revocation of the Edict of Nantes in 1685 sent French Protestant writers, editors, printers and readers into a European refugee network in which Dutch cities were major centres.",
        "Books prohibited in France continued to circulate through foreign editions, bookseller credit, fairs, false imprints and concealed consignments across political borders.",
      ],
      map: { x: 43, y: 40 },
    },
    {
      id: "dictionary-teaches-doubt",
      actId: "news-daily-appetite",
      order: 3,
      period: "AD 1697–1702",
      place: "Rotterdam",
      title: "The Dictionary Teaches Doubt",
      thesis:
        "Bayle built contradiction, citation and unresolved dispute into the architecture of a reference book, making disciplined doubt portable.",
      body: [
        "Pierre Bayle wrote in Rotterdam as a Huguenot exile who had also broken with powerful members of his own refugee church. His Historical and Critical Dictionary appeared in 1697 with compact articles rising above immense notes. A reader who looked up a biblical figure, ancient philosopher or recent controversialist soon descended through citations, objections and replies occupying most of the page. The first edition filled two folio volumes; the enlarged edition of 1702 filled four. The book’s physical weight contained an argument about how authority should be read.",
        "Bayle placed claims beside the sources used to support them and then opened the points at which those sources disagreed. Footnotes led into other footnotes; cross-references carried one life into a dispute elsewhere; a pious assertion might be followed by evidence that unsettled its confident use. The method did not require every reader to adopt one doctrine. It required the reader to recognise quotation, inference, contradiction and the remaining distance between them. Learning appeared as an inquiry whose disagreements belonged on the page.",
        "The dictionary moved into private libraries, academies and the working shelves of later writers. Its format rewarded the habit of testing an inherited name against several witnesses and following a citation beyond the sentence that claimed it. Printers could reproduce the architecture, reviewers could challenge a reference, and readers in different countries could enter the same unresolved file. Bayle made erudition into a public instrument: a heavy book designed to prevent one voice from closing the case.",
      ],
      image: `${imageRoot}/03-dictionary-teaches-doubt.avif`,
      imageAlt:
        "An authentic Bayle dictionary page opens across marbled boards as dense footnotes, citations and red reference tabs reveal the architecture beneath a short article.",
      imagePosition: "52% center",
      mobileImagePosition: "57% center",
      visualLabel: "Article, footnote, objection and cross-reference",
      visualTone: "marbled-dictionary",
      side: "left",
      sourceIds: ["bots-waquet-1997", "israel-2001"],
      evidence: [
        "Bayle’s Dictionnaire historique et critique first appeared in two folio volumes in 1697 and expanded to four volumes in its 1702 second edition.",
        "The work’s short articles, extensive notes, citations, objections and cross-references made competing claims and source criticism part of the reader’s route through the book.",
      ],
      map: { x: 42, y: 41 },
    },
    {
      id: "spectator-finds-its-reader",
      actId: "public-learns-to-judge",
      order: 4,
      period: "AD 1711–1712",
      place: "London and the British reading public",
      title: "The Spectator Finds Its Reader",
      thesis:
        "Addison and Steele made the periodical essay a recurring appointment through which readers examined taste, conduct, commerce and conversation.",
      body: [
        "The first number of The Spectator appeared in London on 1 March 1711. Richard Steele and Joseph Addison gave the paper a quiet observer and a small fictional club whose members connected landed society, commerce, law, soldiering and urban fashion. The voice returned each morning with a compact subject: conversation at the theatre, conduct in the coffeehouse, education, dress, credulity, reading or the obligations of polite company. An issue could be finished over coffee and carried whole in memory.",
        "The paper addressed readers as participants in a continuing judgment. Coffeehouses bought copies for many customers; a household could read an essay aloud; provincial posts carried issues beyond London; collected editions gave yesterday’s sheet a place on the shelf. Letters from readers, whether printed, shaped or invented by the editors, allowed the public to appear inside the paper as correspondent and example. The Spectator’s social reach remained bounded by literacy, money and convention, while its prose taught a broadening audience to recognise itself as a tribunal of manners.",
        "Recurrence supplied the force. No single essay governed a reader, and the next number could qualify, redirect or mock the last. The familiar voice made return habitual, while issue numbers and dates joined separated readers to the same sequence. European translations and imitations carried the form outward. The periodical essay turned judgment from an exceptional pamphlet battle into a regular practice, performed in the interval between one post and the next.",
      ],
      image: `${imageRoot}/04-spectator-finds-its-reader.avif`,
      imageAlt:
        "One issue of The Spectator travels from a London press to a coffeehouse and a domestic reading table, gathering a carrier’s fold and small reader marks.",
      imagePosition: "59% center",
      mobileImagePosition: "66% center",
      visualLabel: "Daily issue, carrier’s fold and returning reader",
      visualTone: "periodical-ivory",
      side: "right",
      sourceIds: ["melton-2001", "cowan-2005", "bond-1971", "porter-2000"],
      evidence: [
        "Addison and Steele published the original daily run of The Spectator from March 1711 to December 1712, using a recurring persona and club to address public manners and taste.",
        "Coffeehouse copies, postal distribution, reading aloud, collected editions and imitation abroad extended the relationship between periodical voice and returning reader.",
      ],
      map: { x: 35, y: 44 },
    },
    {
      id: "voltaire-returns-with-england",
      actId: "public-learns-to-judge",
      order: 5,
      period: "AD 1726–1734",
      place: "London, Rouen and Paris",
      title: "Voltaire Returns with England",
      thesis:
        "Voltaire turned travel into comparison, using English institutions and intellectual life as a living standard against which French arrangements could be judged.",
      body: [
        "Voltaire crossed to England in 1726 after a quarrel with the noble Rohan family had brought imprisonment and the prospect of renewed confinement. Exile placed him within a society where Parliament contested public business, several Protestant denominations worshipped under different conditions, merchants claimed civic standing and Newton’s admirers had made mathematical natural philosophy a national achievement. He learned English, met writers and political figures, followed the theatre and stock market, and studied a constitution whose liberties rested on institutions rather than a philosopher’s design.",
        "His Letters Concerning the English Nation arranged those observations as a sequence of contrasts. Quakers, Anglicans and Presbyterians opened a question about toleration; the Royal Exchange joined confession and commerce; Bacon, Locke and Newton supplied rival measures of intellectual authority; Parliament and the nobility made French privilege look less inevitable. England on Voltaire’s page was selected and sharpened for argument. Its importance lay in physical existence. A reader could imagine another arrangement because ships and letters connected France to a country where parts of it already operated.",
        "The French edition of 1734 appeared without authorisation. The Parlement of Paris condemned the book, copies were publicly burned and a warrant pursued the author, who withdrew to Cirey. Suppression confirmed the comparison’s political edge and pushed the Letters through the same clandestine trade that carried other prohibited works. Travel had become an instrument of public criticism. Customs once defended as the character of a kingdom could be placed beside another kingdom’s practice and required to explain the difference.",
      ],
      image: `${imageRoot}/05-voltaire-returns-with-england.avif`,
      imageAlt:
        "A folding letter places a London coffeehouse, Royal Exchange and Newtonian diagram opposite a Paris censorship docket marked for the 1734 Philosophical Letters.",
      imagePosition: "55% center",
      mobileImagePosition: "62% center",
      visualLabel: "English observation and French censorship docket",
      visualTone: "folding-comparison",
      side: "left",
      sourceIds: ["porter-2000", "israel-2001", "davidson-2010"],
      evidence: [
        "Voltaire lived in England from 1726 to 1729 and used English religious, commercial, political and intellectual institutions as comparative material in the Philosophical Letters.",
        "The unauthorised French edition of 1734 was condemned by the Parlement of Paris, publicly burned and followed by a warrant against Voltaire.",
      ],
      map: { x: 39, y: 47 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "comparative-laws",
        prompt: "Compare the laws",
        accessibleSummary:
          "Four period constitutions are opened as linked folios under executive, legislature, court, tax and liberty of print, allowing Montesquieu’s comparative method to reveal relationships instead of assigning a single rank.",
        initialId: "england",
        records: [
          {
            id: "england",
            label: "Open England",
            period: "After AD 1689",
            kicker: "A mixed constitution in practice",
            detail:
              "Crown, Lords and Commons share legislation within a confessional state whose courts, parties and print give political conflict durable forms.",
            stageImage: `${imageRoot}/05-voltaire-returns-with-england.avif`,
            fields: [
              {
                label: "Executive",
                value: "Crown governing through ministers",
              },
              {
                label: "Legislature",
                value: "King-in-Parliament: Commons and Lords",
              },
              {
                label: "Court",
                value: "Common-law courts and statutory settlement",
              },
              {
                label: "Tax",
                value: "Parliamentary grant and funded public credit",
              },
              {
                label: "Print",
                value: "Licensing lapsed; prosecution and patronage remained",
              },
            ],
            outcome:
              "Voltaire finds a working contrast; Montesquieu later interprets liberty through powers able to check one another.",
          },
          {
            id: "france",
            label: "Open France",
            period: "Reign of Louis XV",
            kicker: "Royal legislation meets corporate law",
            detail:
              "The crown issues law through councils and ministers while parlements register edicts and defend jurisdictions, privileges and claims of remonstrance.",
            stageImage: `${imageRoot}/06-laws-enter-comparison.avif`,
            fields: [
              {
                label: "Executive",
                value: "King, royal councils and intendants",
              },
              {
                label: "Legislature",
                value:
                  "Royal ordinance without a regular national estates assembly",
              },
              {
                label: "Court",
                value: "Sovereign courts, seigneurial rights and varied custom",
              },
              {
                label: "Tax",
                value: "Royal levies mediated by privilege and tax farming",
              },
              {
                label: "Print",
                value: "Privilege, censorship and a large illicit trade",
              },
            ],
            outcome:
              "Comparison turns inherited jurisdictions into an order whose powers, exemptions and obstructions can be examined together.",
          },
          {
            id: "dutch-republic",
            label: "Open the Dutch Republic",
            period: "Eighteenth-century republic",
            kicker: "Authority remains distributed",
            detail:
              "Town councils and provincial States send instructed delegates into common institutions, making sovereignty a negotiated possession.",
            stageImage: `${imageRoot}/02-amsterdam-prints-beyond-borders.avif`,
            fields: [
              {
                label: "Executive",
                value:
                  "Provincial officeholders and the stadholder when appointed",
              },
              {
                label: "Legislature",
                value: "Town, provincial and States General resolutions",
              },
              { label: "Court", value: "Provincial and urban jurisdictions" },
              {
                label: "Tax",
                value: "Provincial consent and allocated common charges",
              },
              {
                label: "Print",
                value:
                  "Fragmented controls and comparative room for publication",
              },
            ],
            outcome:
              "The republic displays liberty through divided authority, civic government and commercial interdependence rather than one sovereign centre.",
          },
          {
            id: "habsburg-monarchy",
            label: "Open the Habsburg Monarchy",
            period: "Reigns of Maria Theresa and Joseph II",
            kicker: "Reform proceeds through the ruler’s offices",
            detail:
              "A composite monarchy strengthens central administration while provincial estates, crowns and jurisdictions retain different legal positions.",
            stageImage: `${imageRoot}/10-rulers-answer-the-page.avif`,
            fields: [
              {
                label: "Executive",
                value: "Dynastic ruler, councils and expanding bureaux",
              },
              {
                label: "Legislature",
                value:
                  "Decree within distinct crowns and provincial settlements",
              },
              {
                label: "Court",
                value: "Territorial systems altered by central reform",
              },
              {
                label: "Tax",
                value: "Negotiation, survey and administrative rationalisation",
              },
              {
                label: "Print",
                value: "Licensed discussion under state supervision",
              },
            ],
            outcome:
              "Comparison shows reform widening through administration while public criticism remains dependent on permission from above.",
          },
        ],
      },
    },
    {
      id: "laws-enter-comparison",
      actId: "public-learns-to-judge",
      order: 6,
      period: "AD 1748",
      place: "Geneva and Paris",
      title: "Laws Enter Comparison",
      thesis:
        "Montesquieu placed institutions, customs, commerce and circumstance in one field of inquiry, giving Europe a method for examining how power produced or destroyed liberty.",
      body: [
        "Montesquieu had served as a magistrate in Bordeaux, travelled through Europe and spent years assembling examples from histories, legal texts and reported practice. The Spirit of the Laws appeared anonymously at Geneva in 1748. Its subject was the relation among laws rather than one ideal code. Forms of government depended on animating principles; civil and political rules operated among customs, religion, economy, territory and climate; one institution changed meaning when placed inside another order. The variety of Europe became evidence for comparison.",
        "His account of England gave the book its most influential constitutional mechanism. Liberty required security under law, and power had to encounter power through an arrangement of legislative, executive and judicial functions. Montesquieu described a stylised English constitution as a working balance among offices whose boundaries touched. The analytical gain lay in relation: who could arrest, judge, tax, legislate or veto, and what prevented one holder from joining every power in the same hand? A constitution could be read as moving parts whose checks produced consequences.",
        "The book crossed borders rapidly through editions, translations, reviews and controversy. Administrators, reformers and political writers could now place the English Parliament beside French parlements, a republic beside a monarchy, commercial law beside landed privilege. Comparison did not dissolve local history; it made difference intelligible and therefore available for argument. By asking what a law did inside the whole order, Montesquieu gave public judgment a vocabulary precise enough to move from admiration or complaint toward constitutional reasoning.",
      ],
      image: `${imageRoot}/06-laws-enter-comparison.avif`,
      imageAlt:
        "A period comparison cabinet holds linked folios for executive power, legislature, courts, taxation and liberty of print beside brass balances rather than ranked scores.",
      imagePosition: "53% center",
      mobileImagePosition: "60% center",
      visualLabel: "Powers, laws and customs in comparative relation",
      visualTone: "constitutional-cabinet",
      side: "right",
      sourceIds: ["robertson-2005", "shklar-1987", "melton-2001"],
      evidence: [
        "Montesquieu published De l’esprit des lois anonymously at Geneva in 1748 after extended legal work, travel and comparative study.",
        "His analysis related forms of government and liberty to the distribution of powers and to laws operating among customs, commerce, religion, territory and other circumstances.",
      ],
      map: { x: 49, y: 55 },
    },
    {
      id: "encyclopedie-opens-the-workshop",
      actId: "continent-thinks-in-company",
      order: 7,
      period: "AD 1751–1772",
      place: "Paris and the European book trade",
      title: "The Encyclopédie Opens the Workshop",
      thesis:
        "Diderot and d’Alembert organised articles, cross-references and plates into a collective structure where skilled work entered learned memory.",
      body: [
        "The Encyclopédie began from a plan to translate Ephraim Chambers’s English Cyclopaedia and grew into a new survey of knowledge under Denis Diderot and Jean le Rond d’Alembert. The first text volume appeared in 1751. By 1765 subscribers had received seventeen volumes of articles, and eleven volumes of plates followed through 1772. Editors, named contributors, anonymous specialists, engravers, workshop informants, compositors and booksellers made the enterprise possible. Its alphabetical order gave no single discipline permanent command of the shelf.",
        "Cross-references supplied an intellectual route through that alphabet. An article defined its object, cited authorities, directed the reader toward related terms and sometimes displaced a dangerous implication into another entry. D’Alembert’s preliminary discourse and the system of human knowledge proposed an overall order; the links allowed readers to discover affinities and collisions the tree could not settle in advance. Censorship interrupted publication and the royal privilege was revoked in 1759. Editors continued under guarded arrangements and completed text volumes reached subscribers.",
        "The plates made the workshop part of the learned project. Engraved sequences exposed the tools and operations of mining, metalworking, textile production, printing, glassmaking and instrument construction. A machine could be separated into parts, a hand’s movement fixed at successive stages and a trade’s vocabulary preserved beside philosophy or law. The result honoured skill through exact description. Europe acquired a book in which knowledge belonged to relations among articles and to the ordered intelligence of making things.",
      ],
      image: `${imageRoot}/07-encyclopedie-opens-the-workshop.avif`,
      imageAlt:
        "An Encyclopédie article opens beside authentic cross-references and an engraved workshop plate whose numbered operations remain legible in the original French.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Article, cross-reference and mechanical-arts plate",
      visualTone: "encyclopedie-folio",
      side: "left",
      sourceIds: ["israel-2001", "darnton-1979", "melton-2001"],
      evidence: [
        "The first edition of the Encyclopédie comprised seventeen text volumes published from 1751 to 1765 and eleven plate volumes completed by 1772.",
        "Its cross-references joined entries into an argumentative structure, while detailed plates recorded tools and ordered operations in the mechanical arts.",
      ],
      map: { x: 47, y: 51 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "encyclopedie-cross-references",
        prompt: "Cross-reference the world",
        accessibleSummary:
          "Four linked reading states move from an Encyclopédie article through definitions, related entries and an engraved operation, redrawing a tree of knowledge while preserving the original page.",
        initialId: "open-article",
        records: [
          {
            id: "open-article",
            label: "Open the article",
            period: "Paris · AD 1751–1765",
            kicker: "The alphabet supplies an entrance",
            detail:
              "A headword, definition, attributed text and references place one object inside a volume that readers can enter without following a prescribed beginning.",
            stageImage: `${imageRoot}/07-encyclopedie-opens-the-workshop.avif`,
            fields: [
              { label: "Surface", value: "Original article remains visible" },
              {
                label: "Guide",
                value: "Headword, author mark and cited authorities",
              },
              {
                label: "Next motion",
                value: "Choose a printed cross-reference",
              },
            ],
            outcome:
              "Alphabetical order gives each subject a stable address; cross-references prepare several routes outward.",
            points: [
              {
                id: "article",
                label: "Article",
                detail: "Definition and argument",
                x: 50,
                y: 48,
              },
            ],
          },
          {
            id: "follow-definition",
            label: "Follow the definition",
            period: "From term to term",
            kicker: "Meaning acquires neighbours",
            detail:
              "Related headwords distinguish material, operation, cause and use, replacing an isolated name with a field of connected terms.",
            stageImage: `${imageRoot}/07-encyclopedie-opens-the-workshop.avif`,
            fields: [
              { label: "Route", value: "Term → material → instrument" },
              {
                label: "What accumulates",
                value: "Definitions and distinctions",
              },
              {
                label: "What remains",
                value: "The first article as point of return",
              },
            ],
            outcome:
              "The object becomes legible through the language of its parts, materials and operations.",
            points: [
              {
                id: "term",
                label: "Term",
                detail: "Original headword",
                x: 30,
                y: 52,
              },
              {
                id: "material",
                label: "Material",
                detail: "Substance and preparation",
                x: 52,
                y: 35,
              },
              {
                id: "instrument",
                label: "Instrument",
                detail: "Tool and use",
                x: 72,
                y: 55,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "enter-workshop",
            label: "Enter the workshop",
            period: "Plate volume",
            kicker: "The operation becomes visible",
            detail:
              "A numbered plate separates workplace, tools and successive hand movements so that skilled practice can be inspected in sequence.",
            stageImage: `${imageRoot}/07-encyclopedie-opens-the-workshop.avif`,
            fields: [
              {
                label: "Upper register",
                value: "Workers within the full shop",
              },
              {
                label: "Lower register",
                value: "Tools and components separated",
              },
              {
                label: "Reading order",
                value: "Numbered operation linked to article text",
              },
            ],
            outcome:
              "Craft knowledge enters learned memory without losing the implements and bodily order that make it work.",
            points: [
              {
                id: "shop",
                label: "Workshop",
                detail: "Operation in context",
                x: 28,
                y: 32,
              },
              {
                id: "hand",
                label: "Hand",
                detail: "Ordered action",
                x: 52,
                y: 48,
              },
              {
                id: "tool",
                label: "Tool",
                detail: "Named implement",
                x: 72,
                y: 68,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "redraw-knowledge",
            label: "Redraw the tree",
            period: "Return through the links",
            kicker: "Cross-references make a path",
            detail:
              "Definitions, related articles and plates gather around the first headword, revealing one chosen route through a collective structure.",
            stageImage: `${imageRoot}/07-encyclopedie-opens-the-workshop.avif`,
            fields: [
              { label: "Starting point", value: "One alphabetical article" },
              {
                label: "Added relations",
                value: "Source, concept, tool and operation",
              },
              {
                label: "Public use",
                value: "A route another reader can repeat or contest",
              },
            ],
            outcome:
              "The Encyclopédie becomes an instrument for moving through knowledge rather than a row of settled answers.",
            points: [
              {
                id: "memory",
                label: "Memory",
                detail: "History and record",
                x: 24,
                y: 38,
              },
              {
                id: "reason",
                label: "Reason",
                detail: "Philosophy and relation",
                x: 50,
                y: 27,
              },
              {
                id: "imagination",
                label: "Imagination",
                detail: "Arts and representation",
                x: 76,
                y: 38,
              },
              {
                id: "work",
                label: "Mechanical arts",
                detail: "Material operation",
                x: 50,
                y: 70,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [1, 3],
            ],
          },
        ],
      },
    },
    {
      id: "edinburgh-invents-social-science",
      actId: "continent-thinks-in-company",
      order: 8,
      period: "AD 1740–1776",
      place: "Edinburgh and Glasgow",
      title: "Edinburgh Invents Social Science",
      thesis:
        "Scottish universities, clubs and presses made human conduct, historical development and commercial society objects of sustained collective inquiry.",
      body: [
        "Edinburgh and Glasgow joined universities, courts, churches, medical teaching, booksellers and merchant wealth within compact urban worlds. Professors lectured to students preparing for ministry, law and medicine; advocates and physicians met in societies; manuscripts passed from tavern or drawing room to printer. The Select Society, founded in Edinburgh in 1754, brought landowners and officeholders into debate with lawyers and men of letters. Conversation carried an argument across professions quickly enough for its assumptions to be exposed before publication fixed it.",
        "David Hume examined belief through habit, passion and the evidence of human nature, then wrote a history of England that treated political institutions as products of conflict and time. Adam Smith began from sympathy and the judgments people form in one another’s presence before following division of labour, exchange and the growth of commercial society. Francis Hutcheson, Lord Kames, William Robertson and Adam Ferguson joined moral philosophy to jurisprudence, history and accounts of social development. Human arrangements became open to causal explanation without being reduced to a ruler’s commands.",
        "The Scottish achievement depended on institutions capable of carrying work across a lifetime. University chairs provided teaching, patronage and succession; clubs assembled informed critics; correspondence brought news from London, Paris and the Atlantic world; publishers sent Scottish books into a European market. Hume and Smith wrote in disagreement as well as friendship, and later readers could begin from the distinctions they had made. A small northern intellectual republic built a disciplined language for sympathy, custom, labour, exchange and historical change.",
      ],
      image: `${imageRoot}/08-edinburgh-invents-social-science.avif`,
      imageAlt:
        "An evening route in Edinburgh links a university lecture, debating society and printer through annotated pages by Hume, Smith and their contemporaries.",
      imagePosition: "54% center",
      mobileImagePosition: "60% center",
      visualLabel: "Lecture, club debate and printed moral philosophy",
      visualTone: "edinburgh-evening",
      side: "right",
      sourceIds: ["robertson-2005", "phillipson-2010", "emerson-2008"],
      evidence: [
        "Eighteenth-century Scottish universities, learned societies and clubs linked professors, advocates, physicians, clergy, landowners and merchants in recurring intellectual exchange.",
        "Hume, Smith and their contemporaries developed connected inquiries into human nature, sympathy, history, jurisprudence, labour and commercial society.",
      ],
      map: { x: 32, y: 31 },
    },
    {
      id: "milan-makes-punishment-answer",
      actId: "continent-thinks-in-company",
      order: 9,
      period: "AD 1764–1786",
      place: "Milan, Livorno, Paris, Vienna and Florence",
      title: "Milan Makes Punishment Answer",
      thesis:
        "Beccaria made criminal punishment answer to published reason, and the argument acquired enough European authority to alter law.",
      body: [
        "Cesare Beccaria entered a Milanese circle gathered around Pietro and Alessandro Verri, the Accademia dei Pugni and the periodical Il Caffè. Its members discussed political economy, administration and law within the Habsburg-ruled duchy. Beccaria’s short On Crimes and Punishments appeared anonymously at Livorno in 1764. Its compressed chapters attacked secret accusation, judicial torture, discretionary severity and punishments detached from public law. The state’s power to punish had to serve civil security through rules a citizen could know.",
        "The argument joined moral force to administrative use. Torture tested endurance rather than truth and could make the innocent confess; certainty deterred more effectively than spectacular cruelty; penalties should be proportionate to offences; capital punishment lacked the necessity claimed for it. A French translation published in 1766 rearranged and amplified the book for a wider audience. Reviews, correspondence and new editions placed the same propositions before philosophes, jurists, ministers and rulers from Paris to Vienna.",
        "The route ended in different acts rather than one uniform programme. Maria Theresa’s government abolished judicial torture in the Habsburg lands in 1776. In Tuscany, Grand Duke Leopold promulgated a criminal reform in 1786 that abolished torture and the death penalty. Beccaria did not command either government; circulation made his reasoning available, reputable and difficult for a reforming court to ignore. A private discussion in Milan had crossed translation, review and ministerial reading into European statutes.",
      ],
      image: `${imageRoot}/09-milan-makes-punishment-answer.avif`,
      imageAlt:
        "A marked paragraph from Beccaria’s 1764 book travels from Milan and Livorno through a French translation and review toward dated Habsburg and Tuscan reform documents.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "Argument, translation, review and penal decree",
      visualTone: "wax-red-reform",
      side: "left",
      sourceIds: ["venturi-1972", "beccaria-bellamy-1995", "blanning-2002"],
      evidence: [
        "Beccaria’s Dei delitti e delle pene was first published anonymously at Livorno in 1764 and reached a wide European audience through translations, reviews and correspondence.",
        "The book argued against judicial torture and capital punishment and for legality, certainty and proportionality; Habsburg torture abolition in 1776 and Tuscany’s penal reform of 1786 made related principles law.",
      ],
      map: { x: 53, y: 65 },
    },
    {
      id: "rulers-answer-the-page",
      actId: "opinion-enters-government",
      order: 10,
      period: "AD 1740–1790",
      place: "Berlin and Vienna",
      title: "Rulers Answer the Page",
      thesis:
        "Prussian and Habsburg rulers used law, schooling, toleration and administration to answer a European reforming audience while keeping command of the reforming state.",
      body: [
        "Frederick II entered the Prussian throne in 1740 already known as an author and correspondent of philosophes. His government curtailed judicial torture, strengthened a professional bureaucracy, promoted legal revision and accepted varied confessions where settlement served the state. French prose, academy patronage and correspondence placed the king inside the republic of letters. War, noble privilege and monarchical command remained foundations of Prussian power. Reform gave that power an account of itself in terms Europe’s readers could compare with the practice of other states.",
        "Maria Theresa’s government pursued a different route through Habsburg offices. The General School Ordinance of 1774 sought a wider network of elementary instruction; judicial torture was abolished in 1776; fiscal and administrative surveys strengthened the centre’s knowledge of its territories. Joseph II accelerated the programme after 1780. The Patent of Toleration of 1781 widened the civil position of specified non-Catholic Christians, and reforms of personal servitude, religious institutions and criminal law pressed uniform government into provinces whose rights and customs differed.",
        "Each decree entered a public chronology. Journals reported it, correspondents interpreted it and foreign readers compared announced principle with administrative result. Rulers drew prestige from the language of utility and reason, while officials gained arguments for changing a school, court or tax office. The direction remained downward: the crown selected, issued and could revoke. Publication altered the conditions of rule by making toleration, torture, education and legal clarity visible as common tests before an audience extending beyond the ruler’s own subjects.",
      ],
      image: `${imageRoot}/10-rulers-answer-the-page.avif`,
      imageAlt:
        "Berlin and Vienna decree desks share a dated rail carrying a Prussian law paper, school ordinance, Habsburg torture abolition and Joseph II’s toleration patent.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Review packet, government office and dated decree",
      visualTone: "decree-desks",
      side: "right",
      sourceIds: ["melton-2001", "porter-2000", "blanning-2002"],
      evidence: [
        "Frederick II combined correspondence and academy patronage with Prussian programmes of legal, judicial and administrative reform under continued monarchical command.",
        "Maria Theresa’s and Joseph II’s governments issued major measures on schooling, judicial torture, toleration, personal servitude and criminal law through the central institutions of the Habsburg monarchy.",
      ],
      map: { x: 60, y: 50 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "argument-to-statute",
        prompt: "Follow one argument",
        accessibleSummary:
          "Three propositions from Beccaria’s On Crimes and Punishments travel through publication, translation, review and ministerial reading to a specific Habsburg or Tuscan legal consequence, accumulating visible hands along the route.",
        initialId: "law-before-punishment",
        records: [
          {
            id: "law-before-punishment",
            label: "Punishment must follow law",
            period: "AD 1764–1786",
            kicker: "From known rule to criminal code",
            detail:
              "Beccaria places the authority to define crimes and penalties in public law, restricting the judge to applying a rule established before the case.",
            stageImage: `${imageRoot}/09-milan-makes-punishment-answer.avif`,
            fields: [
              {
                label: "First hand",
                value: "Milanese reform circle · AD 1764",
              },
              {
                label: "Second hand",
                value: "Livorno printer and French translator",
              },
              {
                label: "Third hand",
                value: "Reviewers, jurists and ministerial readers",
              },
              {
                label: "Institutional answer",
                value: "Tuscan criminal law · AD 1786",
              },
            ],
            outcome:
              "The marked proposition reaches a code that states penalties through promulgated law rather than inherited judicial mystery.",
            points: [
              {
                id: "milan-law",
                label: "Milan",
                detail: "Argument drafted",
                x: 54,
                y: 65,
              },
              {
                id: "livorno-law",
                label: "Livorno",
                detail: "Book printed",
                x: 53,
                y: 73,
              },
              {
                id: "paris-law",
                label: "Paris",
                detail: "Translated and reviewed",
                x: 47,
                y: 51,
              },
              {
                id: "florence-law",
                label: "Florence",
                detail: "Code promulgated",
                x: 53,
                y: 70,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
            ],
          },
          {
            id: "torture-cannot-find-truth",
            label: "Torture cannot discover truth",
            period: "AD 1764–1776",
            kicker: "From procedure to abolition",
            detail:
              "The accused person’s endurance cannot establish a fact: pain rewards physical strength, coerces confession and confuses proof with suffering.",
            stageImage: `${imageRoot}/09-milan-makes-punishment-answer.avif`,
            fields: [
              {
                label: "First hand",
                value: "Milanese manuscript and Livorno edition",
              },
              { label: "Second hand", value: "French translation · AD 1766" },
              {
                label: "Third hand",
                value: "Continental reviews and administrative correspondence",
              },
              {
                label: "Institutional answer",
                value: "Habsburg abolition of judicial torture · AD 1776",
              },
            ],
            outcome:
              "The critique enters administrative reason and helps make torture indefensible as a regular instrument of criminal proof.",
            points: [
              {
                id: "milan-torture",
                label: "Milan",
                detail: "Argument drafted",
                x: 54,
                y: 65,
              },
              {
                id: "paris-torture",
                label: "Paris",
                detail: "Translated and reviewed",
                x: 47,
                y: 51,
              },
              {
                id: "vienna-torture",
                label: "Vienna",
                detail: "Abolition ordered",
                x: 60,
                y: 56,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "penalties-in-proportion",
            label: "Penalties should be proportionate",
            period: "AD 1764–1786",
            kicker: "From severity to measured consequence",
            detail:
              "Punishment should preserve civil order through a graded relation to the offence, using certainty and necessity in place of exemplary cruelty.",
            stageImage: `${imageRoot}/09-milan-makes-punishment-answer.avif`,
            fields: [
              { label: "First hand", value: "Beccaria and the Verri circle" },
              {
                label: "Second hand",
                value: "Translators and journal reviewers",
              },
              { label: "Third hand", value: "Leopold’s Tuscan legal advisers" },
              {
                label: "Institutional answer",
                value: "Leopoldine penal reform · AD 1786",
              },
            ],
            outcome:
              "A principle argued in a small book helps organise a penal statute that abolishes torture and death while recalibrating punishment.",
            points: [
              {
                id: "milan-proportion",
                label: "Milan",
                detail: "Proposition composed",
                x: 54,
                y: 65,
              },
              {
                id: "livorno-proportion",
                label: "Livorno",
                detail: "Edition issued",
                x: 53,
                y: 73,
              },
              {
                id: "paris-proportion",
                label: "Paris",
                detail: "European reputation grows",
                x: 47,
                y: 51,
              },
              {
                id: "florence-proportion",
                label: "Florence",
                detail: "Penalty schedule recast",
                x: 53,
                y: 70,
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
      id: "the-letter-stops-at-the-palace",
      actId: "opinion-enters-government",
      order: 11,
      period: "AD 1767–1792",
      place: "St Petersburg and Moscow",
      title: "The Letter Stops at the Palace",
      thesis:
        "Enlightenment language entered Catherine II’s government while Russia’s public authority remained dependent on the throne and unable to make it answer on comparable terms.",
      body: [
        "Catherine II read Montesquieu and Beccaria closely while preparing the Instruction, or Nakaz, for the Legislative Commission summoned in 1767. Its printed clauses described law, liberty, punishment and administration in the language of European reform, and copies circulated in several languages. Deputies from many legally recognised estates and territories brought grievances and proposals to Moscow. Serfs did not receive representation. The commission gathered information and displayed imperial purpose, then the war with the Ottoman Empire interrupted its general sessions without producing the intended new code.",
        "Russia possessed learned institutions and energetic writers. The Academy of Sciences organised scholarship and expeditions; the Free Economic Society solicited practical knowledge; journals translated and debated European work. Nikolay Novikov edited satirical and moral periodicals, published books, supported schools and used the Moscow University press to build a readership beyond one court commission. These enterprises gave Russian Enlightenment culture substance, reach and a language of service and moral judgment.",
        "Their authority remained vulnerable to the sovereign who had encouraged them. Catherine’s government tightened control after the French Revolution began, closed Novikov’s publishing operations and imprisoned him in 1792. No comparably durable constellation of independent presses, corporate bodies and representative institutions could compel the palace to submit its reforming language to sustained public judgment. The continental letter reached Catherine’s desk and entered the Nakaz; the line terminated when imperial favour ended.",
      ],
      image: `${imageRoot}/11-the-letter-stops-at-the-palace.avif`,
      imageAlt:
        "A marked European letter becomes an authenticated page of Catherine II’s Nakaz, then reaches a Moscow printing warehouse closed under an imperial police seal.",
      imagePosition: "60% center",
      mobileImagePosition: "68% center",
      visualLabel: "Nakaz page, court archive and closed press",
      visualTone: "palace-terminus",
      side: "left",
      sourceIds: ["dixon-2001", "de-madariaga-1981", "jones-1984"],
      evidence: [
        "Catherine II drew substantially on Montesquieu and Beccaria in the 1767 Nakaz; the Legislative Commission produced no new code before its general meetings ceased.",
        "Novikov created a significant publishing and educational enterprise centred on the Moscow University press; Catherine’s government closed the operation and imprisoned him in 1792.",
      ],
      map: { x: 72, y: 33 },
    },
    {
      id: "opinion-enters-the-assembly",
      actId: "opinion-enters-government",
      order: 12,
      period: "AD 1789",
      place: "Paris and Versailles",
      title: "Opinion Enters the Assembly",
      thesis:
        "France’s fiscal crisis called representatives together, and a mobilised reading public used pamphlet, electoral instruction and declaration to claim constituent authority for the nation.",
      body: [
        "The French monarchy’s fiscal deadlock forced Louis XVI to summon the Estates-General for May 1789. The electoral process opened an immense documentary labour. Parishes, guilds, towns and assemblies drafted cahiers de doléances recording grievances and desired reforms. The relaxation of political censorship during the crisis filled printers’ shops and stalls with pamphlets. Abbé Sieyès asked what the Third Estate was and answered that it formed the nation, giving a concise formula to readers already arguing over representation, voting and sovereignty.",
        "Deputies arrived at Versailles carrying instructions from local political communities and reputations formed in print. Conflict over verification and voting prevented the three orders from beginning ordinary business. On 17 June, deputies of the Third Estate declared themselves the National Assembly; clerical deputies joined them, and on 20 June those excluded from their hall swore at the tennis court not to separate before giving France a constitution. Printed copies, reports and engravings carried each act back toward the constituencies whose words had come to Versailles.",
        "The Declaration of the Rights of Man and of the Citizen, adopted in August, stated that sovereignty resided essentially in the nation and that law expressed the general will. The claims now issued from an assembly remaking the legal order. Coffeehouse report, clandestine book, periodical essay, comparative constitution, encyclopaedia and reform decree had taught Europeans to follow public reasoning across institutions. In 1789 that public did not wait for the state to request criticism. It claimed the authority to constitute the state itself.",
      ],
      image: `${imageRoot}/12-opinion-enters-the-assembly.avif`,
      imageAlt:
        "Cahiers and pamphlets move from a Paris stall into the Tennis Court oath and the readable text of the Declaration of the Rights of Man and of the Citizen.",
      imagePosition: "51% center",
      mobileImagePosition: "57% center",
      visualLabel: "Cahier, pamphlet, oath and declaration",
      visualTone: "constituent-paper",
      side: "right",
      sourceIds: ["darnton-1982", "blanning-2002", "baker-1990"],
      evidence: [
        "The elections to the Estates-General generated local cahiers and an exceptional volume of pamphlet debate over representation, voting and the political identity of the nation.",
        "The Third Estate declared itself the National Assembly on 17 June 1789, swore the Tennis Court oath three days later and participated in adopting the Declaration of Rights in August.",
      ],
      map: { x: 47, y: 51 },
    },
  ],
};
