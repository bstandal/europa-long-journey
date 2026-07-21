import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/reformation";

export const reformation: ChapterDefinition = {
  slug: "reformation",
  number: "15",
  title: "The Reformation",
  openingTitleLines: ["The Reformation"],
  period: "AD 1517–1648",
  claim:
    "Print carried religious argument beyond every chamber appointed to contain it. Rival confessions then built schools, courts, ministries and armies into territorial government; after thirty years of fire, Westphalia preserved a divided Christendom through law.",
  openingClaim:
    "A printed argument divided western Christendom, entered the machinery of government and returned a century later as armies marching through a burning Empire.",
  hero: {
    image: `${imageRoot}/opening-burned-empire.avif`,
    mobileImage: `${imageRoot}/opening-burned-empire-mobile.avif`,
    imageAlt:
      "A scorched oak congress table carries a cracked map of the Holy Roman Empire, abandoned army counters, contribution slips and intact treaty instruments.",
    imagePosition: "61% center",
    mobileImagePosition: "68% center",
    visualLabel: "The Burned Empire · tract, contribution and treaty",
  },
  theme: {
    id: "burned-empire",
    label: "The Burned Empire",
  },
  openingAction: "Read the burned Empire",
  mapLabel:
    "The presses, confessional territories, campaign roads, contribution zones and congress cities through which religious fracture became government, war and legal peace",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Early printed theses · imperial edicts · church ordinances · visitation records · contribution demands · siege accounts · diplomatic credentials · treaty instruments",
  acts: [
    {
      id: "argument-escapes",
      number: "I",
      label: "The argument escapes",
      period: "AD 1517–1534",
      title: "The Argument Escapes",
      detail:
        "A university dispute enters print, survives imperial judgment and acquires a vernacular language that can travel through churches and homes.",
    },
    {
      id: "confessions-build-worlds",
      number: "II",
      label: "Confessions build worlds",
      period: "AD 1523–1555/63",
      title: "Confessions Build Worlds",
      detail:
        "Lutheran, Reformed and Catholic renewal acquire clergy, schools, courts, property and territorial protection inside a divided western Christendom.",
    },
    {
      id: "empire-burns",
      number: "III",
      label: "The Empire burns",
      period: "AD 1618–1632",
      title: "The Empire Burns",
      detail:
        "Bohemian revolt opens a war that armies sustain by taxing occupied land, carrying siege, hunger and epidemic disease into civilian homes.",
    },
    {
      id: "peace-in-ruins",
      number: "IV",
      label: "Peace is made in the ruins",
      period: "AD 1634–1648",
      title: "Peace Is Made in the Ruins",
      detail:
        "A confessional war becomes a European contest, while envoys build a settlement strong enough to preserve the Empire and its permanent religious plurality.",
    },
  ],
  ending: {
    period: "AD 1648",
    title: "The Empire Survives the Fire",
    detail:
      "The armies left territories scarred by requisition, hunger, disease, flight and burned towns. They did not leave an empty political field. Catholic, Lutheran and Reformed estates returned to diets, courts and negotiated rights under a peace that made religious plurality part of the imperial constitution. Along the Empire’s south-eastern edge, the Habsburg crowns were already binding another Europe together beside the Danube: old kingdoms, frontier lands and many peoples held beneath one dynasty without surrendering every law of their own.",
    image: `${imageRoot}/ending-empire-survives-fire.avif`,
    nextPeriod: "AD 1526–1918",
  },
  returnHash: "reformation",
  nextHash: "habsburg-europe",
  nextTitle: "Habsburg Europe",
  nextSlug: "habsburg-europe",
  movements: [
    {
      id: "indulgence-enters-print",
      actId: "argument-escapes",
      order: 1,
      period: "October AD 1517–1520",
      place: "Wittenberg, Leipzig, Nuremberg and Basel",
      title: "The Indulgence Enters Print",
      thesis:
        "Printers turned a Latin university dispute over indulgences into a public argument that no single authority could recall.",
      body: [
        "An indulgence arrived near Electoral Saxony as a printed promise with a papal seal behind it. Preachers offered the faithful remission from temporal punishment in return for a prescribed contribution, and agents counted receipts intended in part for Archbishop Albrecht of Mainz and the rebuilding of St Peter’s in Rome. Martin Luther, professor of theology at Wittenberg, answered in Latin. His ninety-five propositions challenged the preaching and theology surrounding the sale and invited learned dispute. He sent them to ecclesiastical authority at the end of October 1517. The secure beginning is a manuscript submitted and an argument released.",
        "Printers supplied the decisive multiplication. Copies reached workshops in Leipzig, Nuremberg and Basel, where compositors set the propositions in movable type, pressmen inked the forms and carriers placed folded sheets on commercial roads. Latin editions served universities and clergy; German summaries and sermons opened the controversy to a larger reading public. A sheet could be read aloud in a tavern, copied in a chancery, refuted from a pulpit and reset in another city without asking Wittenberg for permission. Each new edition turned a local exchange into common knowledge.",
        "Luther learned to write for the new circuit. Short German pamphlets, forceful title pages and Lucas Cranach’s workshop gave reform a recognisable material form, while opponents used the same presses to answer him. Hundreds of editions followed within a few years. Church officers could condemn a text and magistrates could seize a bundle; the distributed type remained in many shops and the argument continued to move. Western Christendom had met controversies before. Print gave this one speed, volume and a market wide enough to outrun the institutions summoned to judge it.",
      ],
      image: `${imageRoot}/01-indulgence-enters-print.avif`,
      mobileImage: `${imageRoot}/01-indulgence-enters-print-mobile.avif`,
      imageAlt:
        "A compositor sets Latin type beside an indulgence, a pressman pulls a thesis sheet and carriers take pamphlets onto roads toward German printing cities.",
      imagePosition: "61% center",
      mobileImagePosition: "68% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "print-escapes",
      side: "left",
      sourceIds: ["rublack-2017", "pettegree-2015", "roper-2016"],
      evidence: [
        "Luther sent his Latin propositions on indulgences to Archbishop Albrecht of Mainz at the end of October 1517, and printed editions carried them rapidly through several cities.",
        "Printers in several cities reproduced the theses rapidly, and Luther’s later German pamphlets joined text, workshop practice and distribution into an unusually effective public campaign.",
      ],
      map: { x: 57, y: 40 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "print-run",
        prompt: "Pull the print run",
        accessibleSummary:
          "Four cumulative workshop stages compose, ink, press and fold a thesis sheet, then place German pamphlets on routes through Leipzig, Nuremberg, Augsburg and Basel.",
        initialId: "compose-type",
        records: [
          {
            id: "compose-type",
            label: "Compose the type",
            period: "The manuscript reaches a shop",
            kicker: "Argument becomes a form",
            detail:
              "A compositor selects metal letters, sets the Latin propositions in lines and locks the completed pages inside an iron chase.",
            fields: [
              { label: "Constraint", value: "Type, skilled labour and copy" },
              { label: "Result", value: "One reusable printing form" },
            ],
            outcome:
              "The manuscript has become an object capable of exact repetition.",
          },
          {
            id: "ink-form",
            label: "Ink the form",
            period: "The press is prepared",
            kicker: "Material fixes the words",
            detail:
              "The pressman works dense ink across the raised type and lays a damp sheet of paper over the form.",
            fields: [
              { label: "Constraint", value: "Ink, paper and even pressure" },
              { label: "Result", value: "A legible impression" },
            ],
            outcome:
              "The argument can now survive the hand that first wrote it.",
          },
          {
            id: "pull-press",
            label: "Pull the press",
            period: "Sheets accumulate",
            kicker: "Repetition changes the scale",
            detail:
              "One pull follows another while corrected type remains locked in place, producing a run large enough for booksellers and messengers.",
            fields: [
              { label: "Constraint", value: "Time, capital and market risk" },
              { label: "Result", value: "Many matching sheets" },
            ],
            outcome:
              "A university exchange enters the commercial supply of news.",
          },
          {
            id: "fold-carry",
            label: "Fold and carry",
            period: "The road multiplies the press",
            kicker: "Every market can begin again",
            detail:
              "Booksellers, students and carriers take sheets through Leipzig, Nuremberg and Augsburg toward Basel, where another workshop can reset them.",
            fields: [
              { label: "Constraint", value: "Carrier, road and local demand" },
              { label: "Result", value: "German and Latin public dispute" },
            ],
            outcome:
              "No single seizure can recover all the copies or silence all the presses.",
          },
        ],
      },
    },
    {
      id: "worms-judges-the-book",
      actId: "argument-escapes",
      order: 2,
      period: "April–May AD 1521",
      place: "Imperial Diet, Worms",
      title: "Worms Judges the Book",
      thesis:
        "The Empire pronounced judgment on Luther, then discovered that constitutional authority could issue a sentence faster than its estates would enforce one.",
      body: [
        "Luther entered Worms under an imperial safe-conduct and found his books arranged on a table before Charles V, the electors, princes and estates. The assembly asked whether he acknowledged the works and would retract them. He accepted authorship, requested time and returned the following day with a divided answer: some writings taught faith, some attacked abuses, some struck individuals too fiercely. A general recantation, he declared, required refutation from scripture and sound reason. The young emperor heard a monk place printed argument before inherited ecclesiastical authority in the Empire’s highest political gathering.",
        "Charles answered from the opposite foundation. Generations of Christian rulers and the Church could not all have erred, and an emperor sworn to defend the faith would act against the dissenter. Luther left Worms under protection. The Edict issued in the emperor’s and Diet’s name declared him an outlaw, prohibited his writings and forbade anyone to print, buy, sell or shelter them. On paper the constitutional machinery had closed around the books: emperor, estates, ban, censor and magistrate each possessed a part in enforcement.",
        "Frederick the Wise of Saxony opened the machinery at its weakest joint. His men intercepted Luther on the homeward road and concealed him at the Wartburg, while other rulers and cities applied the Edict unevenly or ignored it. Local government, privilege and distance gave a territorial protector room to resist a universal sentence without immediately leaving the Empire. The books remained in circulation, presses continued to answer one another and the condemned author kept writing. Worms revealed the next field of conflict. Religious judgment now depended on the rulers, councils and officers who governed Europe place by place.",
      ],
      image: `${imageRoot}/02-worms-judges-the-book.avif`,
      imageAlt:
        "Luther’s books rest on a document table before Charles V and the ranked imperial estates, with the sealed Edict of Worms awaiting enforcement.",
      imagePosition: "64% center",
      mobileImagePosition: "70% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "imperial-judgment",
      side: "right",
      sourceIds: ["roper-2016", "cameron-2012", "ghdi-worms-1521"],
      evidence: [
        "Luther appeared before Charles V and the imperial estates on 17 and 18 April 1521, acknowledged the books laid before him and refused a general retraction.",
        "The Edict of Worms outlawed Luther and his works, while Frederick the Wise’s protection and uneven enforcement prevented the judgment from ending the movement.",
      ],
      map: { x: 43, y: 50 },
    },
    {
      id: "vernacular-enters-the-house",
      actId: "argument-escapes",
      order: 3,
      period: "AD 1522–1534",
      place: "Wartburg, Wittenberg and German households",
      title: "The Vernacular Enters the House",
      thesis:
        "Translation, illustration, preaching and song made reform repeatable wherever a page could be read aloud.",
      body: [
        "Hidden at the Wartburg, Luther worked quickly through Erasmus’s Greek New Testament and fashioned a German version meant to sound clear when spoken. The September Testament appeared from Wittenberg in 1522 with woodcuts from Cranach’s workshop and a price that still placed ownership beyond many households. Demand exhausted the first edition and called forth revisions and reprints. In 1534 the complete Bible joined the New Testament to a translated Old Testament produced through years of collaborative labour. Scripture entered German print as a sustained editorial undertaking rather than one inspired moment.",
        "The page travelled farther through the human voice. A literate householder read beside a table while family, servants and neighbours listened; a pastor carried the new phrasing into a sermon; a schoolchild repeated it from a catechism. Hymns set doctrine to melodies that congregations could remember without holding a book. Woodcuts organised difficult stories into visible sequences. Printers in rival cities copied successful formats and booksellers stocked brief sermons beside larger volumes. Reform thus acquired a language shared across differences of schooling, wealth and local speech.",
        "Translation also created authority and disagreement. Readers compared the words delivered from the pulpit with words present in their own language, while preachers, rulers and theologians argued over who could interpret them rightly. Radical prophets and peasant communities drew conclusions Luther rejected; Catholic translators and controversialists entered the same vernacular arena. The household Bible did not settle western Christianity. It gave confessional communities a durable voice, a repertoire of texts and songs, and the expectation that belief should be taught repeatedly inside ordinary life.",
      ],
      image: `${imageRoot}/03-vernacular-enters-the-house.avif`,
      imageAlt:
        "An authenticated September Testament page lies open as a householder reads aloud beside a woodcut, hymn sheet and listening family.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "vernacular-house",
      side: "left",
      sourceIds: ["rublack-2017", "pettegree-2015", "macculloch-2003"],
      evidence: [
        "The September Testament of 1522 translated the New Testament into vigorous German and was followed, after collaborative revision and further translation, by a complete Bible in 1534.",
        "Reading aloud, preaching, catechisms, hymns and woodcuts carried vernacular reform beyond the smaller population able to purchase and read a substantial book alone.",
      ],
      map: { x: 52, y: 43 },
    },
    {
      id: "reform-takes-second-road",
      actId: "confessions-build-worlds",
      order: 4,
      period: "AD 1523–1541",
      place: "Zürich and Geneva",
      title: "Reform Takes a Second Road",
      thesis:
        "Civic councils in Zürich and Geneva gave Reformed Christianity institutions, discipline and a European reach distinct from Lutheran reform.",
      body: [
        "Zürich’s council called clergy and citizens to a public disputation in January 1523. Huldrych Zwingli placed his programme before civic judges, argued from scripture and won permission to continue preaching. Further decisions followed through council chambers and parish churches. Images were removed under civic order, religious houses and charitable property were reorganised, clerical marriage was accepted and the Mass gave way to a new communion service. A free imperial city had made its magistrates responsible for the public form of Christianity.",
        "Conflict revealed how separate the roads had become. Zwingli and Luther agreed against Rome and divided over Christ’s presence in the Eucharist when they met at Marburg in 1529. Swiss war then killed Zwingli at Kappel in 1531 without erasing the institutional work already embedded in allied cantons and cities. Reform possessed no single Protestant command. Councils, princes, theologians and congregations created settlements whose differences could survive the founders who first argued for them.",
        "Geneva gave the Reformed road a disciplined international centre. After the city accepted reform, John Calvin returned in 1541 under ecclesiastical ordinances that distinguished pastors, teachers, elders and deacons. Ministers preached and administered sacraments; the consistory examined conduct and doctrine in tension and cooperation with the councils; printers carried books outward and refugees carried experience inward. Trained pastors later departed along European routes. A movement born in civic decisions could reproduce itself across borders through schools, correspondence, printed texts and men prepared for ministry.",
      ],
      image: `${imageRoot}/04-reform-takes-second-road.avif`,
      imageAlt:
        "One continuous council bench joins the Zürich disputation to Geneva’s ordinances, consistory papers and outward routes of trained pastors.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "reformed-cities",
      side: "right",
      sourceIds: ["rublack-2017", "cameron-2012", "macculloch-2003"],
      evidence: [
        "Zürich’s councils used disputations and ordinances to enact Zwingli’s reforms, while the 1529 Marburg Colloquy exposed a lasting Eucharistic division with Luther.",
        "Geneva’s 1541 ecclesiastical ordinances established pastors, teachers, elders and deacons and made the city a durable centre of Reformed training and print.",
      ],
      map: { x: 38, y: 65 },
    },
    {
      id: "prince-builds-a-church",
      actId: "confessions-build-worlds",
      order: 5,
      period: "AD 1526–1530s",
      place: "Electoral Saxony, Hesse and Augsburg",
      title: "A Prince Builds a Church",
      thesis:
        "Territorial rulers converted evangelical conviction into a working church through inventories, ordinances, schools and courts.",
      body: [
        "The visitor arrived at a Saxon parish with questions and a ledger. Did the pastor understand the teaching he was expected to preach? Could he lead worship, explain the catechism and keep the parish register? What land, tithe, vessel and book belonged to the church? Lay and clerical commissioners heard complaints, inspected buildings and wrote deficiencies into articles for correction. Reform moved from pamphlet and sermon into a room-by-room account of people, property and practice. A territory could proclaim a confession in a day; making it present in every village required repeated administration.",
        "Electoral Saxony and Hesse built territorial churches from that labour. Rulers issued church ordinances, redirected former monastic revenues, appointed superintendents and supported pastors whose marriages and households embodied the new order. Consistories judged disputes involving clergy, marriage and discipline. Schools prepared boys to read, sing and serve church or chancery, while catechisms gave households a common sequence of commandments, creed, prayer and sacraments. The ruler’s existing officers supplied reach, archives and coercive force; theologians supplied doctrine and trained personnel.",
        "At Augsburg in 1530, allied Protestant estates presented a confession to Charles V that stated their teaching in a form a political body could own. The document did not create agreement across the Empire, although it gave Lutheran territories a shared standard around which diplomacy and defence could organise. Confession now meant a public church supported by law, salary, school and court. Subjects encountered it at baptism, marriage, worship, schooling and burial. Religious division had entered government deeply enough that restoring one western church would require displacing institutions already rooted in daily life.",
      ],
      image: `${imageRoot}/05-prince-builds-a-church.avif`,
      imageAlt:
        "A parish visitation desk connects an inventory, church key, school bench and consistory file to the mapped territory of Electoral Saxony.",
      imagePosition: "60% center",
      mobileImagePosition: "66% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "territorial-church",
      side: "left",
      sourceIds: ["rublack-2017", "cameron-2012", "brady-2009"],
      evidence: [
        "Saxon visitations beginning in the late 1520s examined parish personnel, teaching, worship, finances and property and produced concrete instructions for territorial reform.",
        "Church ordinances, consistories, schools and salaried ministries joined Protestant confession to the administrative reach of territorial rulers.",
      ],
      map: { x: 56, y: 41 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "confessional-territory",
        prompt: "Build a confessional territory",
        accessibleSummary:
          "Four cumulative controls use visitation, church ordinance, school and court to change personnel, property, worship and education across one territorial ledger.",
        initialId: "visitation",
        records: [
          {
            id: "visitation",
            label: "Send the visitors",
            period: "Parish by parish",
            kicker: "Declaration meets the inventory",
            detail:
              "Commissioners question clergy, inspect worship, list property and report what the territorial church still lacks.",
            fields: [
              { label: "Personnel", value: "Pastor examined" },
              {
                label: "Property",
                value: "Land, tithe, vessel and book listed",
              },
              { label: "Worship", value: "Current practice recorded" },
              { label: "Education", value: "Local knowledge tested" },
            ],
            outcome: "The ruler can see where reform exists only on paper.",
          },
          {
            id: "church-ordinance",
            label: "Issue the ordinance",
            period: "One rule across the territory",
            kicker: "Inspection becomes command",
            detail:
              "A printed ordinance sets worship, office, revenue and supervision in a form every district officer can apply.",
            fields: [
              {
                label: "Personnel",
                value: "Pastors and superintendents assigned",
              },
              { label: "Property", value: "Revenues directed to ministry" },
              { label: "Worship", value: "Liturgy and sacraments ordered" },
              { label: "Education", value: "Catechism required" },
            ],
            outcome: "Separate parishes acquire a common public church.",
          },
          {
            id: "school",
            label: "Open the school",
            period: "The next generation",
            kicker: "Confession learns to reproduce itself",
            detail:
              "Teachers join reading, music and catechism while promising pupils move toward university, ministry and chancery service.",
            fields: [
              { label: "Personnel", value: "Teacher and pupils installed" },
              { label: "Property", value: "Room, stipend and books funded" },
              { label: "Worship", value: "Congregational language learned" },
              {
                label: "Education",
                value: "Reading, song and doctrine repeated",
              },
            ],
            outcome:
              "The settlement can endure beyond its first reforming generation.",
          },
          {
            id: "consistory",
            label: "Seat the court",
            period: "Rule between visitations",
            kicker: "The church acquires daily government",
            detail:
              "A consistory hears clerical, marital and disciplinary cases and preserves decisions in a continuing territorial archive.",
            fields: [
              { label: "Personnel", value: "Clergy supervised and replaced" },
              { label: "Property", value: "Rights and stipends adjudicated" },
              { label: "Worship", value: "Public settlement enforced" },
              { label: "Education", value: "School and ministry connected" },
            ],
            outcome:
              "Confession has become a governing institution rather than a prince’s declaration.",
          },
        ],
      },
    },
    {
      id: "catholic-europe-renews",
      actId: "confessions-build-worlds",
      order: 6,
      period: "AD 1534–1563",
      place: "Rome, Trent, Ingolstadt and Catholic Europe",
      title: "Catholic Europe Renews",
      thesis:
        "The Catholic renewal joined clarified doctrine to disciplined clergy, mobile religious orders, schools and a stronger episcopal presence.",
      body: [
        "Catholic renewal gathered forces already active before Luther and gave them sharper institutional form. New and reformed communities pursued preaching, charity, prayer and clerical discipline. The Society of Jesus, approved in 1540 after Ignatius of Loyola and his companions had bound themselves to service, added unusual mobility and exacting education. Its members preached, advised rulers, directed spiritual exercises and founded colleges from Portugal to Poland. A classroom at Ingolstadt or Vienna trained students in languages, rhetoric, philosophy and doctrine for a Catholic public world confident in learned argument.",
        "The Council of Trent met through war, epidemic interruption and papal-imperial tension from 1545 to 1563. Bishops and theologians defined Catholic teaching on scripture and tradition, justification, the sacraments, the Mass and holy orders. Reform decrees demanded residence and visitation from bishops, improved preaching, attacked abuses and ordered diocesan seminaries for the systematic education of clergy. The assembled prelates refused Protestant doctrine while answering failures that had made reform urgent. Definition and discipline came from the same long table.",
        "Implementation belonged to the decades after each decree. Bishops travelled or sent visitors through their dioceses, convened synods and examined parish practice; seminaries and colleges formed clergy able to preach and teach; catechisms carried doctrine to households. Religious art presented sacred history with controlled force inside renewed churches. Catholic rulers supported these institutions through patronage and law, while missionaries carried them beyond Europe. Western Christianity now contained confessions able to educate elites, shape ordinary devotion and reproduce personnel on a continental scale. Catholic recovery matched Protestant reform in administrative depth and cultural confidence.",
      ],
      image: `${imageRoot}/06-catholic-europe-renews.avif`,
      imageAlt:
        "Council decrees cross a long table at Trent toward a Jesuit classroom, diocesan seminary and a bishop’s marked visitation route.",
      imagePosition: "63% center",
      mobileImagePosition: "69% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "catholic-renewal",
      side: "right",
      sourceIds: ["macculloch-2003", "omalley-2013", "hsia-2005"],
      evidence: [
        "The Society of Jesus received papal approval in 1540 and built a mobile ministry whose European colleges became major centres of Catholic education.",
        "The Council of Trent met in three main periods between 1545 and 1563, defining doctrine while requiring episcopal duties, preaching reform and diocesan seminaries.",
      ],
      map: { x: 47, y: 69 },
    },
    {
      id: "augsburg-maps-division",
      actId: "confessions-build-worlds",
      order: 7,
      period: "AD 1555–1618",
      place: "Augsburg and the imperial territories",
      title: "Augsburg Maps the Division",
      thesis:
        "The Religious Peace of Augsburg made Catholic and Lutheran division governable while leaving Reformed communities and ecclesiastical lands as dangerous fault lines.",
      body: [
        "Delegates at Augsburg faced an Empire that repeated war had failed to reunite. The religious peace of 1555 bound Catholic estates and adherents of the Augsburg Confession to refrain from force on account of religion. Imperial estates gained legal security for the public church established under their authority. Subjects unwilling to conform received a regulated right to sell their property and emigrate. The settlement did not make private conscience the source of public religion. It used territorial government to keep rival churches inside a common imperial peace.",
        "The map acquired hard edges. Lutheran princes and cities protected ordinances, clergy and former church property; Catholic estates continued their own worship and increasingly pursued Tridentine reform. An ecclesiastical ruler who converted was expected to surrender his office under the disputed reservation meant to preserve Catholic bishoprics. Mixed imperial cities required special arrangements, and the status of religious practice by some subjects remained contested. Jurists, diets and courts inherited questions whose answers affected lands, revenues and political weight as directly as doctrine.",
        "One growing confession stood outside the named settlement. Reformed rulers and communities, including the Palatinate’s Calvinist court, possessed institutions and alliances without explicit protection under Augsburg’s terms. By the early seventeenth century, the Protestant Union and Catholic League had joined confession to armed association amid a dispute over the Donauwörth settlement and the Jülich succession. Augsburg remained a real achievement: it preserved an imperial constitution across permanent religious division for more than sixty years. Its omissions also marked the places where a later crisis could pull belief, jurisdiction and dynastic fear into war.",
      ],
      image: `${imageRoot}/07-augsburg-maps-division.avif`,
      imageAlt:
        "The 1555 religious peace lies beside an imperial map keyed to Catholic and Lutheran estates, disputed bishoprics, mixed cities and unrecognised Reformed territories.",
      imagePosition: "59% center",
      mobileImagePosition: "65% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "confessional-map",
      side: "left",
      sourceIds: [
        "cameron-2012",
        "brady-2009",
        "wilson-2016",
        "ghdi-augsburg-1555",
      ],
      evidence: [
        "The 1555 peace legally protected Catholic and Lutheran imperial estates, regulated emigration by dissenting subjects and retained contested rules for ecclesiastical territories.",
        "Reformed confession lacked explicit recognition at Augsburg, while disputes over mixed jurisdictions, church property and armed confessional associations sharpened before 1618.",
      ],
      map: { x: 48, y: 57 },
    },
    {
      id: "prague-window-opens-war",
      actId: "empire-burns",
      order: 8,
      period: "AD 1618–1620",
      place: "Prague and White Mountain",
      title: "A Prague Window Opens the War",
      thesis:
        "Bohemian estates defended their confessional and constitutional privileges by revolt, drawing the Empire into a war that outlived their swift defeat.",
      body: [
        "On 23 May 1618, armed Protestant nobles entered the Bohemian Chancellery in Prague Castle and accused the royal governors Jaroslav Bořita of Martinice and Vilém Slavata of violating the Letter of Majesty that protected Bohemian religious rights. They threw both men and the secretary Philip Fabricius from a high window. The victims survived the fall; royal authority in Bohemia did not. The estates formed a directorate, raised troops and made a constitutional defence of privilege into open rebellion against Ferdinand of Styria, soon elected emperor as Ferdinand II.",
        "The rebels deposed Ferdinand as king of Bohemia and offered the crown to Frederick V, the Reformed elector palatine. The choice widened every consequence. Frederick possessed connections to the Protestant Union and was son-in-law to James VI and I; Ferdinand drew support from the Catholic League, Spain and other Habsburg lands. On 8 November 1620, an imperial-League army reached the ridge outside Prague. The Bohemian force broke at White Mountain in a battle lasting scarcely two hours, and Frederick fled the capital that had made him a king for one winter.",
        "Victory closed the Bohemian revolt through execution, exile, confiscation and enforced Catholic reconstruction. Twenty-seven rebel leaders died publicly in Prague in 1621; estates changed hands, the crown tightened its authority and Protestant clergy and many families departed. The war continued because Frederick’s Palatine lands, electoral dignity and allies connected Bohemia to the imperial constitution and the Spanish road. Armies moved west and north after Prague had fallen. A dispute over who could govern religion in one composite kingdom had opened the road to a struggle over power throughout the Empire.",
      ],
      image: `${imageRoot}/08-prague-window-opens-war.avif`,
      imageAlt:
        "The Prague Castle window stands above abandoned estate seals while a campaign route turns toward White Mountain and confiscation ledgers fill the foreground.",
      imagePosition: "64% center",
      mobileImagePosition: "70% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "bohemian-revolt",
      side: "right",
      sourceIds: ["wilson-2009", "asch-1997", "helfferich-2009"],
      evidence: [
        "Bohemian nobles defenestrated two royal governors and a secretary in May 1618, then rejected Ferdinand and elected Frederick V in 1619.",
        "The defeat at White Mountain in November 1620 was followed by executions, property confiscations, political revision and Catholic reconstruction, while the Palatine question carried war onward.",
      ],
      map: { x: 64, y: 48 },
    },
    {
      id: "army-learns-to-feed-itself",
      actId: "empire-burns",
      order: 9,
      period: "AD 1625–1629",
      place: "Lower Saxony, Mecklenburg and imperial contribution zones",
      title: "The Army Learns to Feed Itself",
      thesis:
        "Contribution systems turned armies into mobile fiscal regimes whose survival depended on the land they occupied.",
      body: [
        "King Christian IV of Denmark entered the war as duke of Holstein and leader within the Lower Saxon Circle, hoping to defend Protestant interests and enlarge his family’s position in northern Germany. His coalition met two imperial war machines. Tilly’s Catholic League army defeated Christian at Lutter in 1626. Albrecht von Wallenstein, empowered by Ferdinand II to raise a vast imperial force, defeated Protestant troops at Dessau Bridge, moved through Mecklenburg and pressed toward the Baltic. The emperor could now wage war on a scale his hereditary revenues alone could never sustain.",
        "The missing treasury travelled with the regiments. Commanders assigned a town or district a weekly contribution in coin, grain, fodder, cattle, beer, billets, shoes, wagons and labour. Officials assessed the demand and issued receipts; soldiers enforced it when negotiation failed. Payment could restrain plunder for a time, although another unit might arrive with another order. Wallenstein expanded this system across occupied northern lands, assigning colonels territories from which to draw maintenance. The army behaved as a chain of moving tax districts under arms.",
        "Civilians carried the system’s accumulated failure. A household that surrendered seed grain lost the next harvest; requisitioned horses reduced ploughing and transport; crowded billets spread infection; flight left fields and workshops idle. Hunger weakened bodies before plague, typhus and dysentery arrived. Imperial success encouraged Ferdinand’s Edict of Restitution in 1629, which claimed extensive former Catholic property and frightened Protestant estates beyond the defeated coalition. The army had made a sweeping policy possible. Its appetite also ensured that every operational success widened the zone from which another campaign had to be fed.",
      ],
      image: `${imageRoot}/09-army-learns-to-feed-itself.avif`,
      imageAlt:
        "A quartermaster’s table overlays northern German districts with contribution slips, grain measures, horse requisitions and columns following assigned roads.",
      imagePosition: "61% center",
      mobileImagePosition: "67% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "war-table",
      side: "left",
      sourceIds: ["wilson-2009", "asch-1997", "helfferich-2009"],
      evidence: [
        "Wallenstein’s forces and the Catholic League defeated the Danish-led intervention and carried imperial power into northern Germany between 1625 and 1629.",
        "Military contributions in money and kind supported armies in occupied districts; repeated requisition, billeting, crop loss, displacement and epidemic disease created mortality far beyond the battlefield.",
      ],
      map: { x: 50, y: 36 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "war-table",
        prompt: "Read the war table",
        accessibleSummary:
          "Seven dated states align confession, allegiance, army routes and civilian supply pressure from the Bohemian revolt to Westphalia, where counters withdraw and constitutional guarantees remain.",
        initialId: "prague-1618",
        mapImage: `${imageRoot}/09-army-learns-to-feed-itself.avif`,
        records: [
          {
            id: "prague-1618",
            label: "Open the revolt",
            period: "AD 1618",
            kicker: "Bohemia challenges Ferdinand",
            detail:
              "The estates’ revolt begins inside one crownland and draws supporters toward Prague while imperial forces assemble from Austria.",
            fields: [
              { label: "Confession", value: "Bohemian Protestant privileges" },
              {
                label: "Allegiance",
                value: "Estates against their Habsburg king",
              },
              { label: "Army", value: "Forces converge on Bohemia" },
              {
                label: "Supply pressure",
                value: "Local musters and first levies",
              },
            ],
            outcome:
              "A constitutional revolt acquires the roads and obligations of war.",
            points: [
              {
                id: "prague",
                label: "Prague",
                detail: "Rebel centre",
                x: 63,
                y: 49,
              },
              {
                id: "vienna",
                label: "Vienna",
                detail: "Habsburg centre",
                x: 61,
                y: 66,
              },
            ],
            links: [[1, 0]],
          },
          {
            id: "white-mountain-1620",
            label: "Break Bohemia",
            period: "AD 1620",
            kicker: "Victory widens the conflict",
            detail:
              "The imperial-League victory outside Prague destroys Frederick’s Bohemian position and turns military attention toward his Palatine lands.",
            fields: [
              { label: "Confession", value: "Catholic restoration in Bohemia" },
              { label: "Allegiance", value: "League and Habsburg coalition" },
              { label: "Army", value: "Prague to the Palatinate" },
              {
                label: "Supply pressure",
                value: "Confiscation and occupation",
              },
            ],
            outcome:
              "Bohemia is subdued while the imperial dispute moves west.",
            points: [
              {
                id: "prague",
                label: "White Mountain",
                detail: "Revolt defeated",
                x: 63,
                y: 49,
              },
              {
                id: "palatinate",
                label: "Palatinate",
                detail: "Frederick’s lands",
                x: 42,
                y: 51,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "northern-war-1625",
            label: "Feed the northern war",
            period: "AD 1625–1629",
            kicker: "Armies become fiscal systems",
            detail:
              "Danish intervention meets Tilly and Wallenstein as contribution orders spread across Lower Saxony, Mecklenburg and the Baltic approaches.",
            fields: [
              {
                label: "Confession",
                value: "Protestant defence under Danish arms",
              },
              {
                label: "Allegiance",
                value:
                  "Denmark and northern estates against emperor and League",
              },
              {
                label: "Army",
                value: "Lutter, Mecklenburg and the Baltic coast",
              },
              {
                label: "Supply pressure",
                value: "Coin, grain, fodder, billets and carts",
              },
            ],
            outcome:
              "The army survives by transferring its costs into occupied households.",
            points: [
              {
                id: "lutter",
                label: "Lutter",
                detail: "Danish defeat",
                x: 48,
                y: 37,
              },
              {
                id: "mecklenburg",
                label: "Mecklenburg",
                detail: "Contribution zone",
                x: 58,
                y: 28,
              },
              {
                id: "stralsund",
                label: "Stralsund",
                detail: "Baltic resistance",
                x: 62,
                y: 23,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "magdeburg-breitenfeld-1631",
            label: "Burn and reverse",
            period: "AD 1631",
            kicker: "One campaign contains catastrophe and reversal",
            detail:
              "Magdeburg is destroyed in May; in September, Swedish and Saxon forces break Tilly’s army at Breitenfeld and reopen central Germany.",
            fields: [
              { label: "Confession", value: "Protestant coalition restored" },
              { label: "Allegiance", value: "Sweden gains German allies" },
              { label: "Army", value: "Pomerania through Saxony" },
              {
                label: "Supply pressure",
                value: "Siege loss, refugees and fresh contributions",
              },
            ],
            outcome:
              "The war’s most notorious urban destruction is followed by its sharpest military reversal.",
            points: [
              {
                id: "magdeburg",
                label: "Magdeburg",
                detail: "City destroyed",
                x: 52,
                y: 40,
              },
              {
                id: "breitenfeld",
                label: "Breitenfeld",
                detail: "Swedish-Saxon victory",
                x: 55,
                y: 43,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "lutzen-1632",
            label: "Lose the king",
            period: "AD 1632",
            kicker: "The system survives its commander",
            detail:
              "Gustavus Adolphus dies at Lützen while the Swedish-led army holds the field and continues under coalition government.",
            fields: [
              { label: "Confession", value: "Protestant arms remain viable" },
              { label: "Allegiance", value: "Swedish-German coalition" },
              {
                label: "Army",
                value: "South German advance and return to Saxony",
              },
              {
                label: "Supply pressure",
                value: "Repeated marches through central districts",
              },
            ],
            outcome:
              "The king falls, while administration and alliance keep the war alive.",
            points: [
              {
                id: "munich",
                label: "Munich",
                detail: "Swedish reach",
                x: 49,
                y: 61,
              },
              {
                id: "lutzen",
                label: "Lützen",
                detail: "King killed",
                x: 54,
                y: 44,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "france-enters-1635",
            label: "Outlive confession",
            period: "AD 1634–1635",
            kicker: "European power redraws allegiance",
            detail:
              "Nördlingen breaks the Swedish-led field army, the Peace of Prague reconciles many German estates with Ferdinand and Catholic France enters openly against the Habsburgs.",
            fields: [
              {
                label: "Confession",
                value: "Still powerful, no longer the alliance map",
              },
              {
                label: "Allegiance",
                value: "France and Sweden against Habsburg power",
              },
              {
                label: "Army",
                value: "Rhine, Low Countries and German theatres",
              },
              {
                label: "Supply pressure",
                value: "War spreads across several fronts",
              },
            ],
            outcome:
              "No victory inside the Empire can now end a continental contest.",
            points: [
              {
                id: "nordlingen",
                label: "Nördlingen",
                detail: "Swedish-led defeat",
                x: 49,
                y: 56,
              },
              {
                id: "prague",
                label: "Prague",
                detail: "Imperial settlement",
                x: 63,
                y: 49,
              },
              {
                id: "rhine",
                label: "Rhine",
                detail: "French war front",
                x: 37,
                y: 52,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
            ],
          },
          {
            id: "westphalia-1648",
            label: "Leave law on the table",
            period: "AD 1648",
            kicker: "Counters withdraw; guarantees remain",
            detail:
              "The congress settlements remove armies from the constitutional question and preserve Catholic, Lutheran and Reformed estates inside the imperial peace.",
            fields: [
              {
                label: "Confession",
                value: "Three recognised imperial confessions",
              },
              {
                label: "Allegiance",
                value: "Estates restored inside imperial law",
              },
              {
                label: "Army",
                value: "Demobilisation negotiated after signature",
              },
              {
                label: "Supply pressure",
                value: "Contribution claims give way to restitution",
              },
            ],
            outcome:
              "The burned map retains borders, rights and procedures strong enough to govern division.",
            points: [
              {
                id: "munster",
                label: "Münster",
                detail: "French-imperial instrument",
                x: 41,
                y: 38,
              },
              {
                id: "osnabruck",
                label: "Osnabrück",
                detail: "Swedish-imperial instrument",
                x: 43,
                y: 36,
              },
              {
                id: "empire",
                label: "Imperial estates",
                detail: "Constitutional peace",
                x: 53,
                y: 49,
              },
            ],
            links: [
              [0, 2],
              [1, 2],
            ],
          },
        ],
      },
    },
    {
      id: "magdeburg-becomes-warning",
      actId: "empire-burns",
      order: 10,
      period: "May AD 1631",
      place: "Magdeburg",
      title: "Magdeburg Becomes a Warning",
      thesis:
        "The destruction of Magdeburg gave the war a name for urban catastrophe and a printed warning understood in every camp.",
      body: [
        "Magdeburg had resisted imperial pressure for years and received too little outside help when Tilly and Pappenheim closed around it. Trenches approached the walls through spring 1631 while hunger and exhaustion grew inside. On 20 May, imperial and League troops forced entries during a general assault. Street fighting broke organised defence. Fire spread through densely built quarters under a hard wind as soldiers plundered houses and officers lost command of the assault they had launched.",
        "The city became a furnace from which few structures and inhabitants emerged intact. Thousands died by sword, flame, smoke, falling masonry and suffocation in cellars; others were wounded, assaulted, captured or stripped of everything required to live. The cathedral sheltered a group of survivors, and scattered houses near its mass remained amid ruins. Exact totals cannot be recovered from a city whose registers, dwellings and population had been violently dispersed. The physical result is clear in accounts and engravings: most of Magdeburg’s built fabric was gone, and a major imperial city had been reduced to a remnant in one day.",
        "Printers turned the place-name into a verb. Protestant pamphlets described deliberate Catholic extermination; imperial explanations blamed defenders, fire and the disorder of storm. Woodcuts carried the skyline, smoke and cathedral across Europe, while preachers made Magdeburg a warning about surrender, resistance and divine judgment. The propaganda sharpened confessional fear just as Gustavus Adolphus sought German allies. It also told civilians what military contribution could never promise: payment might postpone violence, walls might delay it and negotiation might redirect it, while a breach could release an army’s accumulated hunger and entitlement against a whole city.",
      ],
      image: `${imageRoot}/10-magdeburg-becomes-warning.avif`,
      imageAlt:
        "A seventeenth-century documentary panorama shows Magdeburg’s ruined streets and surviving cathedral beside printed broadsheets carrying the warning outward.",
      imagePosition: "63% center",
      mobileImagePosition: "69% center",
      visualLabel: "Documentary reconstruction",
      visualTone: "burned-city",
      side: "right",
      sourceIds: ["wilson-2009", "helfferich-2009", "parker-1997"],
      evidence: [
        "Imperial and League troops stormed Magdeburg on 20 May 1631; fire and the collapse of military discipline destroyed most of the city and killed a large share of the people present.",
        "Contemporary pamphlets, sermons and engravings transformed the sack into a confessional warning whose political influence extended far beyond the ruined city.",
      ],
      map: { x: 53, y: 40 },
    },
    {
      id: "sweden-turns-the-field",
      actId: "empire-burns",
      order: 11,
      period: "AD 1630–1632",
      place: "Pomerania, Breitenfeld and Lützen",
      title: "Sweden Turns the Field",
      thesis:
        "Swedish administration, German alliance and battlefield coordination restored Protestant military power after imperial victory had seemed complete.",
      body: [
        "Gustavus Adolphus landed on Usedom in the summer of 1630 with a Swedish army, a Baltic strategy and no guarantee that German Protestants would follow him. Swedish taxation, conscription and crown administration had carried men and matériel across the sea; French subsidies and contributions from occupied German land extended their reach. The destruction of Magdeburg made neutrality more frightening, and Ferdinand’s pressure on Saxony forced Elector John George toward alliance. Sweden had supplied the spear. German territory, money and political choice supplied much of the shaft.",
        "At Breitenfeld on 17 September 1631, Tilly’s veterans drove the Saxon wing from the field and exposed the Swedish line. The line turned rather than broke. Flexible brigades, disciplined cavalry, lighter field guns and reserves shifted to face the threat while captured imperial artillery fired back across the battlefield. Swedish and returning Saxon forces destroyed the League army’s cohesion. The victory opened central and southern Germany, relieved Protestant fear and ended the sequence of imperial victories that had begun at White Mountain.",
        "The advance reached the Main, Rhine and Bavaria before Wallenstein returned to imperial command. At Lützen in November 1632, fog and smoke swallowed formations as the Swedish king rode toward a confused fight and was killed. His army eventually held the field at terrible cost. Chancellor Axel Oxenstierna and German allies continued the coalition because its treaties, officers, supply arrangements and common danger no longer depended on one body. Sweden had changed the military balance and made a general imperial settlement impossible without its consent. The war survived the king who had transformed it.",
      ],
      image: `${imageRoot}/11-sweden-turns-the-field.avif`,
      imageAlt:
        "A cold-steel campaign layer traces the Swedish landing in Pomerania through deployment strips at Breitenfeld toward messengers disappearing in the fog at Lützen.",
      imagePosition: "60% center",
      mobileImagePosition: "66% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "swedish-reversal",
      side: "left",
      sourceIds: ["wilson-2009", "asch-1997", "parker-1997"],
      evidence: [
        "Sweden landed an organised army in Pomerania in 1630 and combined crown resources, foreign subsidy, German alliances and territorial contributions to sustain intervention.",
        "The Swedish-Saxon victory at Breitenfeld in September 1631 reversed the military balance; Gustavus Adolphus died at Lützen in November 1632 while the coalition continued under other leadership.",
      ],
      map: { x: 56, y: 40 },
    },
    {
      id: "war-outlives-confession",
      actId: "peace-in-ruins",
      order: 12,
      period: "AD 1634–1636",
      place: "Nördlingen, Prague and the Rhine",
      title: "The War Outlives Confession",
      thesis:
        "Nördlingen and the Peace of Prague narrowed the imperial religious quarrel as Catholic France widened the struggle against Habsburg power.",
      body: [
        "At Nördlingen in September 1634, the Swedish-led army attacked a strongly held position before it understood the strength of the Spanish and imperial forces assembled there. Repeated assaults failed against the hill of Albuch; cavalry and infantry became compressed, exposed and finally routed. Thousands were killed or captured. South German allies lost protection, Swedish garrisons withdrew and the Habsburg road between Italy, the Empire and the Low Countries reopened. After thirteen years of expanding war, a decisive imperial victory again appeared to offer Ferdinand II the authority to make peace.",
        "The Peace of Prague in 1635 brought Saxony and many other imperial estates back into agreement with the emperor. Ferdinand suspended the Edict of Restitution’s harshest reach, joined princely forces to an imperial army and offered amnesty with exclusions. The settlement reduced the confessional machinery of armed leagues and answered grievances inside the Empire. It could not bind Sweden, settle the Palatine inheritance or remove the Habsburg power that France had spent years containing through diplomacy and subsidy.",
        "Cardinal Richelieu’s Catholic France entered open war against Spain in 1635 and then deepened military cooperation against the Austrian Habsburgs. Armies now campaigned along the Rhine, in the Low Countries, northern Italy, the Pyrenees and within German lands under alliances that no confessional map could explain. Religion still ordered churches, loyalties and fears; raison of dynasty and European security determined the main coalition. A general peace had to satisfy imperial estates, emperor, Sweden and France together. Until that machinery existed, each army continued to collect its next season from regions already stripped by the last.",
      ],
      image: `${imageRoot}/12-war-outlives-confession.avif`,
      imageAlt:
        "Dispatches from Nördlingen, the sealed Peace of Prague and a French declaration redraw the same scorched alliance map toward the Rhine.",
      imagePosition: "64% center",
      mobileImagePosition: "70% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "european-war",
      side: "right",
      sourceIds: ["wilson-2009", "asch-1997", "parker-1997"],
      evidence: [
        "Imperial and Spanish forces defeated the Swedish-led army at Nördlingen in September 1634, breaking its position in southern Germany.",
        "The Peace of Prague reconciled many imperial estates with Ferdinand II in 1635, while France’s open entry against the Habsburgs made the continuing conflict an overt European power struggle.",
      ],
      map: { x: 47, y: 53 },
    },
    {
      id: "envoys-negotiate-under-arms",
      actId: "peace-in-ruins",
      order: 13,
      period: "AD 1643–1648",
      place: "Münster and Osnabrück",
      title: "Envoys Negotiate Under Arms",
      thesis:
        "A divided congress converted overlapping wars and constitutional claims into negotiable articles while the armies continued to march.",
      body: [
        "Envoys came to Westphalia carrying credentials for rulers who would not meet. Catholic and French delegations gathered chiefly at Münster; Swedish and Protestant business centred on Osnabrück. Confessional protocol, papal objections and disputes over rank made one hall impossible. Couriers crossed the road between the cities with memoranda, ciphered instructions and amended drafts, while Venetian and papal mediators worked where their standing allowed. Every title on a credential carried a claim, and every seating order announced who had been recognised before a substantive article was read.",
        "Negotiation had no sheltering armistice. French and Swedish armies pressed into Habsburg lands; the Swedish victory at Jankau in 1645 exposed the approaches to Vienna and Prague, while later campaigns burdened Bavaria and the south-west. Regional losses differed brutally. Mecklenburg, Pomerania, Brandenburg, parts of central Germany and Württemberg recorded deep collapse in households and cultivation, while other districts escaped repeated occupation or recovered sooner. Soldiers killed directly, and the larger machinery of death worked through requisition, failed sowing, flight, crowded refuge, hunger and epidemic disease. A village could survive a battle and disappear during the winter that followed it.",
        "The continuation of war gave each dispatch a place in the bargaining. Imperial estates demanded admission to negotiations that concerned their rights; France and Sweden pursued security, territory and satisfaction for armies and allies; Ferdinand III worked to preserve both Habsburg power and the imperial constitution. Drafts separated questions that had arrived knotted together, then joined their answers across two treaty instruments. Five years of courier journeys created a congress without a common sovereign, common confession or common language of trust. Europe made peace by giving disagreement rooms, procedures and documents strong enough to carry it.",
      ],
      image: `${imageRoot}/13-envoys-negotiate-under-arms.avif`,
      imageAlt:
        "Twin negotiating rooms at Münster and Osnabrück are joined by a courier road carrying credentials, ciphered dispatches and amended treaty drafts.",
      imagePosition: "60% center",
      mobileImagePosition: "66% center",
      visualLabel: "Place, date and surviving record",
      visualTone: "westphalian-congress",
      side: "left",
      sourceIds: ["wilson-2009", "helfferich-2009", "ghdi-westphalia-1648"],
      evidence: [
        "The Westphalian congress operated in Münster and Osnabrück through separate delegations, credentials, mediation and constant courier exchange while fighting continued.",
        "Military requisition, displacement, food failure and epidemic disease combined to produce immense civilian mortality whose severity varied sharply from one region to another.",
      ],
      map: { x: 42, y: 38 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "westphalian-peace",
        prompt: "Make the peace",
        accessibleSummary:
          "Credentials open the two-city congress, then three settlement layers align confessional security, the rights of imperial estates and peace among emperor, France and Sweden.",
        initialId: "exchange-credentials",
        mapImage: `${imageRoot}/13-envoys-negotiate-under-arms.avif`,
        records: [
          {
            id: "exchange-credentials",
            label: "Exchange credentials",
            period: "AD 1643–1645",
            kicker: "Recognition comes before agreement",
            detail:
              "Envoys establish whom they represent, which titles will be acknowledged and how drafts can pass between Münster and Osnabrück.",
            fields: [
              { label: "Instrument", value: "Credential and full power" },
              {
                label: "Route",
                value: "Courier road between two congress cities",
              },
              {
                label: "Unresolved",
                value: "Religion, constitution and foreign war",
              },
            ],
            outcome:
              "The parties acquire a procedure for speaking without gathering beneath one authority.",
            points: [
              {
                id: "munster",
                label: "Münster",
                detail: "Catholic and French negotiations",
                x: 35,
                y: 51,
              },
              {
                id: "osnabruck",
                label: "Osnabrück",
                detail: "Swedish and Protestant negotiations",
                x: 66,
                y: 35,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "secure-confessions",
            label: "Secure the confessions",
            period: "Religious settlement",
            kicker: "Plurality receives a legal date",
            detail:
              "Catholic, Lutheran and Reformed estates enter the peace, with 1624 used to judge disputed ecclesiastical possession and practice.",
            fields: [
              {
                label: "Instrument",
                value: "Confessional articles and Normaljahr",
              },
              {
                label: "Protects",
                value: "Public churches and defined minority practice",
              },
              {
                label: "Unresolved",
                value: "Confessional unity is no longer required",
              },
            ],
            outcome:
              "Religious difference becomes a permanent object of imperial law.",
          },
          {
            id: "restore-estates",
            label: "Restore the estates",
            period: "Constitutional settlement",
            kicker: "The Empire keeps its many governments",
            detail:
              "Amnesty, restitution and the estates’ established role in law, taxation, war and alliance return territorial rule to a common constitution.",
            fields: [
              {
                label: "Instrument",
                value: "Amnesty, restitution and estate rights",
              },
              {
                label: "Protects",
                value: "Territorial government inside imperial peace",
              },
              {
                label: "Limit",
                value: "Alliances cannot injure emperor or Empire",
              },
            ],
            outcome:
              "The settlement revises and preserves the imperial constitution.",
          },
          {
            id: "bind-guarantors",
            label: "Bind the guarantors",
            period: "European settlement",
            kicker: "Foreign powers enter the guarantee",
            detail:
              "Emperor, France and Sweden accept linked instruments, territorial terms and duties of execution large enough to end the imperial war.",
            fields: [
              {
                label: "Instrument",
                value: "Treaties of Münster and Osnabrück",
              },
              {
                label: "Protects",
                value: "Settlement backed beyond one promise",
              },
              {
                label: "Next work",
                value: "Demobilisation and implementation",
              },
            ],
            outcome:
              "Three settlements hold together because each is sealed into the same peace.",
          },
        ],
      },
    },
    {
      id: "law-remains-after-armies",
      actId: "peace-in-ruins",
      order: 14,
      period: "October AD 1648",
      place: "Münster, Osnabrück and the Holy Roman Empire",
      title: "Law Remains After the Armies",
      thesis:
        "Westphalia ended the imperial war by placing permanent religious plurality and territorial rights inside a preserved constitutional order.",
      body: [
        "On 24 October 1648, plenipotentiaries signed the linked instruments of Münster and Osnabrück. The emperor and France settled at Münster; the emperor and Sweden settled at Osnabrück, with imperial estates participating in the settlement that governed their realm. Separate Dutch and Spanish peace had already been concluded at Münster. France and Spain would continue their own war until 1659. Westphalia ended the Thirty Years’ War inside the Empire through a structure exact enough to distinguish one peace from the conflicts it could not close.",
        "Its religious articles recognised Catholic, Lutheran and Reformed estates. The normal year of 1624 supplied a baseline for disputed church property and practice; protections for specified minorities limited the territorial ruler’s confessional reach; parity and negotiated procedure guarded imperial institutions when religion divided their members. Amnesty and restitution repaired political standing where the agreed settlement required it. The peace accepted that western Christendom would remain divided and made that fact governable without asking any confession to declare its truth negotiable.",
        "The estates retained their constitutional place and their bounded capacity to make alliances, while emperor, diets and courts remained parts of the same imperial order. Sweden received imperial territories and seats within its institutions; France secured strategic rights and lands, and both crowns became guarantors of the settlement. The familiar later doctrine of a Europe composed of fully sovereign nation-states is absent from these instruments. Westphalia worked through layered authority, corporate rights and external guarantee. The Empire survived its burning by preserving the legal habits through which many governments could inhabit one peace.",
      ],
      image: `${imageRoot}/14-law-remains-after-armies.avif`,
      imageAlt:
        "Authenticated Westphalian treaty pages and seals lie beside Gerard ter Borch’s ratification scene as army counters leave a map retaining imperial and confessional keys.",
      imagePosition: "62% center",
      mobileImagePosition: "68% center",
      visualLabel: "Documentary anchor · treaty and ratification",
      visualTone: "legal-peace",
      side: "right",
      sourceIds: [
        "ghdi-westphalia-1648",
        "wilson-2009",
        "wilson-2016",
        "helfferich-2009",
      ],
      evidence: [
        "The Münster and Osnabrück instruments recognised Catholic, Lutheran and Reformed estates, used 1624 as the normal year and established religious protections within imperial law.",
        "The settlement revised estate rights, territories and guarantees while preserving emperor, estates, diets and courts inside a reconstructed imperial order.",
      ],
      map: { x: 49, y: 42 },
    },
  ],
};
