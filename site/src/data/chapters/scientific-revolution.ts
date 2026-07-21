import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/scientific-revolution";

export const scientificRevolution: ChapterDefinition = {
  slug: "scientific-revolution",
  number: "17",
  title: "The Scientific Revolution",
  openingTitleLines: ["The Scientific", "Revolution"],
  period: "AD 1543–1700",
  claim:
    "European scholars joined print, exact observation, mathematical proof, crafted instruments and organised criticism into a new power over nature. A claim could be measured, reproduced, attacked and improved by people who had never met. By 1700 knowledge had become cumulative at a scale no earlier intellectual system had achieved.",
  openingClaim:
    "Europe made the study of nature cumulative: observation entered a table, discrepancy forced a new figure, experiment travelled in print and one investigator could begin where another had stopped.",
  hero: {
    image: `${imageRoot}/opening-measured-page.avif`,
    mobileImage: `${imageRoot}/opening-measured-page-mobile.avif`,
    imageAlt:
      "Two books printed in 1543 lie open on a dark worktable, with Copernicus’s planetary diagram facing Vesalius’s anatomy and brass dividers spanning the gutter.",
    imagePosition: "center center",
    mobileImagePosition: "59% center",
    visualLabel: "The Measured Page · instrument, table and result",
  },
  theme: {
    id: "measured-page",
    label: "The Measured Page",
  },
  openingAction: "Set the measuring line",
  mapLabel:
    "The observatories, anatomy theatres, workshops, presses, correspondence routes and societies through which European knowledge became cumulative",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Printed folios · observation tables · instrument engravings · experimental reports · correspondence · society minutes · annotated proofs",
  acts: [
    {
      id: "ancient-page-on-trial",
      number: "I",
      label: "The ancient page is put on trial",
      period: "AD 1543–1601",
      title: "The Ancient Page Is Put on Trial",
      detail:
        "Astronomy, anatomy and exact observation make inherited books answer to ordered evidence recorded by eye, hand and instrument.",
    },
    {
      id: "nature-mathematical-voice",
      number: "II",
      label: "Nature acquires a mathematical voice",
      period: "AD 1600–1628",
      title: "Nature Acquires a Mathematical Voice",
      detail:
        "Ellipse, telescope and circulation turn stubborn discrepancies into new systems of the heavens and the living body.",
    },
    {
      id: "experiment-becomes-instrument",
      number: "III",
      label: "Experiment becomes an instrument",
      period: "AD 1637–1662",
      title: "Experiment Becomes an Instrument",
      detail:
        "Geometry, the mercury column and the air pump make controlled operations capable of answering general questions about nature.",
    },
    {
      id: "knowledge-learns-to-accumulate",
      number: "IV",
      label: "Knowledge learns to accumulate",
      period: "AD 1660–1700",
      title: "Knowledge Learns to Accumulate",
      detail:
        "Societies, journals, correspondence, lenses and mathematical physics preserve results, expose them to criticism and make them common equipment.",
    },
  ],
  ending: {
    period: "AD 1700",
    title: "Europe Makes Knowledge Cumulative",
    detail:
      "No prince directed this enterprise from one capital. Its power lay in the route between observatory and table, workshop and anatomy theatre, private letter and printed page. Measurements made on Hven could overturn a circle in Prague; a pump built in Oxford could produce an argument in London; a lens ground in Delft could place a new living world before readers in Paris and Florence. Rival courts paid, rival printers hurried and rival investigators tried to break one another’s claims. What survived did not remain a private possession. It became equipment for the next mind. The ships, paper, credit and news that carried those results were already gathering with unmatched speed in Amsterdam.",
    image: `${imageRoot}/ending-europe-makes-knowledge-cumulative.avif`,
    nextPeriod: "AD 1572–1713",
  },
  returnHash: "scientific-revolution",
  nextHash: "dutch-republic",
  nextTitle: "The Dutch Republic",
  nextSlug: "dutch-republic",
  movements: [
    {
      id: "earth-becomes-a-planet",
      actId: "ancient-page-on-trial",
      order: 1,
      period: "AD 1543",
      place: "Frombork and Nuremberg",
      title: "Earth Becomes a Planet",
      thesis:
        "Copernicus moved Earth from the still centre of the cosmos and made every planetary motion belong to one ordered system.",
      body: [
        "A printer in Nuremberg set circles, numbers and dense Latin around a proposition that displaced the reader beneath his hands. Earth turned once each day and travelled around the Sun once each year. The Moon accompanied it; Mercury and Venus occupied the inner paths; Mars, Jupiter and Saturn moved beyond. Nicolaus Copernicus had worked out the arrangement over decades at Frombork, comparing observations, inherited tables and mathematical models until the planets could be ordered by their periods and distances. In the first book of De revolutionibus, a small diagram made the reversal visible at a glance. The ground under every observatory had become one moving body among others.",
        "The printed system was formidable rather than immediately victorious. Copernicus retained combinations of uniform circles, and no observation available in 1543 simply displayed Earth in motion. Ptolemaic astronomy remained accurate enough for serious work. Heliocentrism joined phenomena that had previously required separate adjustments. The backward loops of Mars arose from Earth overtaking it; the limited elongations of Mercury and Venus followed from their inner paths; the immense distance assigned to the fixed stars answered the absence of visible annual parallax. One rearrangement made the heavens a connected mechanism in which the observer’s own motion mattered.",
        "Print gave that mechanism a career beyond its author. A reader in Wittenberg, Kraków, Paris or Padua could inspect the same propositions, copy the same tables and identify the same weak point. The book did not ask Europe to accept a revelation. It gave calculators a system exact enough to use and exposed enough to improve. The great reversal of 1543 began as disciplined geometry on rag paper: a claim large enough to move the world, divided into steps another trained reader could check.",
      ],
      image: `${imageRoot}/01-earth-becomes-a-planet.avif`,
      imageAlt:
        "Copernicus’s 1543 planetary diagram rests beside calculation sheets, a quadrant and a restrained view from a Frombork tower.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "1543 folio · planetary order and calculation",
      visualTone: "celestial-folio",
      side: "left",
      sourceIds: ["dear-2009", "shapin-1996", "ou-copernicus-1543"],
      evidence: [
        "De revolutionibus was printed at Nuremberg in 1543 and placed a rotating, orbiting Earth among planets ordered around the Sun.",
        "Its solar order gave the planetary sequence and retrograde motion a connected geometrical explanation in which the observer’s own motion became part of the heavens.",
      ],
      map: { x: 56, y: 39 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "paired-1543-folios",
        prompt: "Open the two books of 1543",
        accessibleSummary:
          "Four synchronized folio states compare inherited diagrams with Copernicus’s reordered heavens and Vesalius’s observed anatomy, then show print carrying both corrections to distant readers.",
        initialId: "inherit-the-page",
        records: [
          {
            id: "inherit-the-page",
            label: "Receive the ancient page",
            period: "Before AD 1543",
            kicker: "Authority arrives in diagrams",
            detail:
              "Astronomers and physicians begin with powerful inherited systems preserved through manuscripts, teaching and print.",
            stageImage: `${imageRoot}/opening-measured-page.avif`,
            fields: [
              { label: "Heavens", value: "Earth fixed within ordered spheres" },
              {
                label: "Body",
                value: "Galen interpreted through texts and demonstrations",
              },
              {
                label: "Strength",
                value: "Coherent traditions refined across centuries",
              },
            ],
            outcome:
              "The inherited page supplies the questions, vocabulary and precision against which a correction can be made.",
          },
          {
            id: "reorder-the-heavens",
            label: "Reorder the heavens",
            period: "Nuremberg · AD 1543",
            kicker: "A new diagram changes the observer",
            detail:
              "Copernicus places Earth in daily rotation and annual revolution, making the planets parts of one heliocentric order.",
            stageImage: `${imageRoot}/01-earth-becomes-a-planet.avif`,
            fields: [
              { label: "Operation", value: "Re-centre and calculate" },
              {
                label: "Evidence",
                value: "Periods, positions and inherited observations",
              },
              {
                label: "Open problem",
                value: "No visible annual stellar parallax",
              },
            ],
            outcome:
              "A mathematical system turns Earth itself into a testable astronomical claim.",
          },
          {
            id: "open-the-body",
            label: "Open the body",
            period: "Padua and Basel · AD 1543",
            kicker: "The hand reaches the structure",
            detail:
              "Vesalius joins dissection, description and coordinated woodcuts so that the pictured body can answer to the observed one.",
            stageImage: `${imageRoot}/02-anatomist-takes-the-knife.avif`,
            fields: [
              { label: "Operation", value: "Dissect, compare and draw" },
              {
                label: "Evidence",
                value: "Human structures exposed in sequence",
              },
              {
                label: "Correction",
                value: "Animal anatomy no longer fills every human gap",
              },
            ],
            outcome:
              "The authoritative image can now be corrected at the table where the body is seen.",
          },
          {
            id: "rule-the-gutter",
            label: "Rule the gutter",
            period: "After AD 1543",
            kicker: "Two disciplines share an operation",
            detail:
              "Astronomy and anatomy differ in subject and proof, yet both make an inherited figure answer to ordered observation on a reproducible page.",
            stageImage: `${imageRoot}/opening-measured-page.avif`,
            fields: [
              { label: "Common surface", value: "Printed folio" },
              { label: "Common discipline", value: "Recorded comparison" },
              { label: "Common future", value: "Correction by absent readers" },
            ],
            outcome:
              "The ruled line between the books becomes the chapter’s measuring spine.",
          },
        ],
      },
    },
    {
      id: "anatomist-takes-the-knife",
      actId: "ancient-page-on-trial",
      order: 2,
      period: "AD 1543",
      place: "Padua and Basel",
      title: "The Anatomist Takes the Knife",
      thesis:
        "Vesalius joined dissection, exact description and magnificent printing so that anatomy could be corrected against the human body itself.",
      body: [
        "In the anatomy theatre at Padua, Andreas Vesalius did not leave the decisive work to a barber-surgeon while a professor recited from a distant chair. He stood near the body, directed the sequence and made words answer to structures as they appeared. Bone, muscle, vessel and organ were separated in an order that students could follow. The practice demanded dexterity, memory and repeated comparison, for a body altered under the knife and no single dissection disclosed everything. Authority moved closer to the hand without losing the accumulated learning that taught the anatomist what to seek.",
        "The Fabrica carried that theatre into print. Its large Basel pages coordinated layered woodcuts with descriptions so exact that a reader could move from skeleton to muscle and from part to system. Vesalius still worked deeply within Galenic medicine, but human dissection exposed places where anatomy derived heavily from animals had been transferred incorrectly: the human lower jaw was one bone, for example, and the supposed rete mirabile at the base of the human brain could not be found. A respected ancient text had become a set of propositions that the opened body could confirm or refuse.",
        "The achievement belonged to more hands than the name on the title page. Assistants prepared bodies; artists translated changing tissues into stable lines; cutters reversed those drawings into woodblocks; Johannes Oporinus’s Basel shop aligned type, image and paper. Their combined precision made observation portable. A student who had never entered Vesalius’s theatre could inspect the relation of parts and carry a corrected figure into another dissection. In the same year that astronomy moved the Earth, European anatomy made the body a published field of inquiry.",
      ],
      image: `${imageRoot}/02-anatomist-takes-the-knife.avif`,
      imageAlt:
        "A restrained Padua anatomy demonstration aligns a hand, instrument and human skeletal structure with an open page from Vesalius’s Fabrica.",
      imagePosition: "61% center",
      mobileImagePosition: "68% center",
      visualLabel: "Dissection, drawing and Basel woodcut",
      visualTone: "anatomy-theatre",
      side: "right",
      sourceIds: ["dear-2009", "cunningham-1997", "nlm-vesalius-fabrica"],
      evidence: [
        "Vesalius taught anatomy at Padua and based the 1543 Fabrica on close human dissection while continuing to engage deeply with Galen.",
        "The Fabrica’s coordinated text and woodcuts made observed anatomical corrections durable, copyable and available beyond one demonstration.",
      ],
      map: { x: 51, y: 63 },
    },
    {
      id: "tycho-builds-an-observatory",
      actId: "ancient-page-on-trial",
      order: 3,
      period: "AD 1572–1601",
      place: "Hven and Prague",
      title: "Tycho Builds an Observatory",
      thesis:
        "Tycho Brahe made precision a collective, long-lived resource by building instruments, routines and tables around the naked eye.",
      body: [
        "The new star of 1572 appeared where the supposedly unchanging heavens should have admitted no novelty. Tycho Brahe measured it against familiar stars night after night and found no detectable parallax that would place it in the weather below the Moon. Five years later he followed a comet whose path likewise crossed the old architecture of solid celestial spheres. Each conclusion depended less on spectacle than on position: where exactly did the light stand, from which instrument, at what hour, compared with which reference star? Tycho made the disciplined answer to those questions his life’s work.",
        "King Frederick II of Denmark granted him the island of Hven, where Uraniborg rose from 1576 as residence, workshop, library, laboratory and observatory. Great quadrants, sextants and armillary instruments were divided with exceptional care. Assistants sighted, called values, checked clocks and entered results; instrument makers repaired metal and wood; calculators reduced repeated observations into tables. Stjerneborg later placed instruments lower and more securely against wind. Before a useful astronomical telescope existed, this household of trained labour pushed naked-eye observation toward minute-of-arc precision and sustained it over years.",
        "Patronage failed, but the measurements could move. Tycho left Denmark with books, instruments, assistants and the accumulated record, entered imperial service and established himself near Prague. Johannes Kepler joined him there in 1600. The two men disagreed over access and theory. Tycho died the next year; the observations outlived the island establishment and its founder. Europe had acquired a new kind of intellectual capital: a long, calibrated series too costly for one observer to improvise and exact enough to force a theory to change.",
      ],
      image: `${imageRoot}/03-tycho-builds-an-observatory.avif`,
      imageAlt:
        "A cutaway of Uraniborg aligns a brass quadrant, observing team and growing table of planetary positions, with a document chest routed toward Prague.",
      imagePosition: "57% center",
      mobileImagePosition: "64% center",
      visualLabel: "Uraniborg · instruments, assistants and long series",
      visualTone: "observatory-night",
      side: "left",
      sourceIds: ["dear-2009", "christianson-2000", "shapin-1996"],
      evidence: [
        "Tycho’s observations of the 1572 nova and 1577 comet challenged the traditional placement and immutability of the superlunary heavens.",
        "Uraniborg and Stjerneborg combined purpose-built instruments, trained assistants and repeated procedures into the finest sustained programme of pre-telescopic positional astronomy.",
      ],
      map: { x: 51, y: 31 },
    },
    {
      id: "mars-refuses-the-circle",
      actId: "nature-mathematical-voice",
      order: 4,
      period: "AD 1600–1609",
      place: "Prague",
      title: "Mars Refuses the Circle",
      thesis:
        "Kepler trusted a measured discrepancy over the perfect circle and turned Tycho’s observations into the first two laws of planetary motion.",
      body: [
        "Mars was the hard case. Its orbit is eccentric enough to expose weaknesses that gentler planetary paths can hide, and Tycho had followed it with unmatched care. Kepler first sought a construction from circles that would preserve the ancient demand for uniform circular motion. One model reproduced the planet’s longitudes closely, yet failed in another dimension by eight minutes of arc. Such a gap might once have been absorbed as ordinary observational uncertainty. Tycho’s instruments had made it an accusation. Kepler later wrote that those eight minutes showed the road toward a complete reformation of astronomy.",
        "He took the orbit apart. Rather than asking only where Mars appeared against the stars, he used observations made when Mars returned to the same part of its path to reconstruct the changing relation between Mars, Earth and Sun. He abandoned uniform speed around a displaced centre and found that the line from Sun to planet sweeps equal areas in equal times. The path itself yielded last. An ellipse with the Sun at one focus fitted the measured positions that the circle could not command.",
        "Astronomia nova appeared in Prague in 1609 as an account of labour rather than a polished oracle. It preserved failed constructions, numerical trials and the pressure exerted by the observations. The page showed a theory becoming answerable to a residual small enough to fit beneath the width of a fingernail on an instrument scale. Tycho had built the precision; Kepler accepted its verdict; print carried the data and reasoning to every astronomer able to use them. A planet’s path had become a law because a discrepancy was treated as knowledge.",
      ],
      image: `${imageRoot}/04-mars-refuses-the-circle.avif`,
      imageAlt:
        "Ruled Mars entries from Tycho’s observations face an overlaid circle and ellipse, with an eight-minute residual enlarged beneath a worn brass scale.",
      imagePosition: "54% center",
      mobileImagePosition: "61% center",
      visualLabel: "From measure to law · the eight-minute residual",
      visualTone: "vermilion-residual",
      side: "right",
      sourceIds: ["dear-2009", "voelkel-1999", "christianson-2000"],
      evidence: [
        "Kepler treated an eight-minute discrepancy in his circular Mars construction as significant because Tycho’s observations were substantially more precise than earlier planetary records.",
        "Astronomia nova of 1609 presented the elliptical orbit of Mars and the equal-area rule now known as Kepler’s first two laws.",
      ],
      map: { x: 55, y: 47 },
      interaction: {
        kind: "chapter-v2",
        family: "record",
        variant: "measure-to-law",
        prompt: "Carry the measure into law",
        accessibleSummary:
          "Four ordered operations carry Tycho’s dated Mars observations from a ruled register through Kepler’s circular mismatch to an ellipse and equal-area law.",
        initialId: "observe-mars",
        records: [
          {
            id: "observe-mars",
            label: "Observe",
            period: "Hven · AD 1580–1597",
            kicker: "Positions before theory",
            detail:
              "Repeated sightings place Mars against reference stars with instruments whose divisions and errors have been checked.",
            stageImage: `${imageRoot}/03-tycho-builds-an-observatory.avif`,
            fields: [
              { label: "Instrument", value: "Quadrant and sextant" },
              { label: "Record", value: "Date, time and angular position" },
              { label: "Discipline", value: "Repeat and compare" },
            ],
            outcome:
              "The observations form a durable series rather than isolated marvels.",
            points: [
              {
                id: "mars-a",
                label: "Position A",
                detail: "Dated sighting",
                x: 17,
                y: 62,
              },
              {
                id: "mars-b",
                label: "Position B",
                detail: "Dated sighting",
                x: 35,
                y: 36,
              },
              {
                id: "mars-c",
                label: "Position C",
                detail: "Dated sighting",
                x: 58,
                y: 27,
              },
              {
                id: "mars-d",
                label: "Position D",
                detail: "Dated sighting",
                x: 81,
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
            id: "tabulate-relations",
            label: "Tabulate",
            period: "Prague · after AD 1601",
            kicker: "Separate sight from orbit",
            detail:
              "Kepler compares positions across repeated returns in order to distinguish the motion of Earth from the motion of Mars.",
            fields: [
              { label: "Input", value: "Tycho’s dated planetary positions" },
              { label: "Comparison", value: "Mars, Earth and Sun relations" },
              { label: "Aim", value: "One geometry for the full orbit" },
            ],
            outcome:
              "The table turns appearances from a moving Earth into a reconstructable path.",
          },
          {
            id: "compare-the-circle",
            label: "Compare",
            period: "Prague · c. AD 1602",
            kicker: "The residual remains",
            detail:
              "A powerful circular construction comes close, but a mismatch greater than the expected observational error refuses to disappear.",
            stageImage: `${imageRoot}/04-mars-refuses-the-circle.avif`,
            fields: [
              { label: "Model", value: "Uniform circular construction" },
              { label: "Residual", value: "8 minutes of arc" },
              { label: "Decision", value: "Trust the measured discrepancy" },
            ],
            outcome:
              "The small error defeats the perfect figure and forces the search to continue.",
          },
          {
            id: "derive-the-ellipse",
            label: "Derive",
            period: "Astronomia nova · AD 1609",
            kicker: "The figure answers the sky",
            detail:
              "An ellipse with the Sun at one focus and a radius sweeping equal areas in equal times fits the changing speed and observed positions.",
            stageImage: `${imageRoot}/04-mars-refuses-the-circle.avif`,
            fields: [
              { label: "Path", value: "Ellipse" },
              { label: "Motion", value: "Equal areas in equal times" },
              { label: "Test", value: "Return to the observed positions" },
            ],
            outcome:
              "Measurement, comparison and mathematical form have become one reusable intellectual operation.",
          },
        ],
      },
    },
    {
      id: "glass-adds-new-heavens",
      actId: "nature-mathematical-voice",
      order: 5,
      period: "AD 1609–1610",
      place: "Padua, Venice and Florence",
      title: "Glass Adds New Heavens",
      thesis:
        "Galileo turned a spectacle-makers’ tube into an astronomical instrument and made its unprecedented sights public through disciplined drawing and print.",
      body: [
        "News reached Padua in 1609 of a Dutch tube that made distant things appear near. Galileo Galilei understood the optical arrangement, selected better glass, ground lenses and built instruments of increasing power. From a Venetian bell tower, the tube could identify ships before the naked eye; directed upward, it opened a field no inherited catalogue had recorded. Craft knowledge from spectacle making had become a new organ of astronomy because a mathematician learned how to strengthen, aim and interpret it.",
        "The Moon’s bright and dark boundary was ragged, changing as illumination shifted: Galileo read the pattern as mountains and hollows and used geometry to estimate relief. The Milky Way dissolved into innumerable stars. Beside Jupiter, four small lights changed position from night to night, sometimes disappearing behind the planet and returning on the other side. Their ordered movement revealed bodies circling a centre other than Earth. The observation did not by itself prove every part of Copernicus’s system, but it broke the claim that all celestial revolution must be centred upon the terrestrial globe.",
        "Sidereus Nuncius carried the observations into print in March 1610. Galileo gave dates, sequences and drawings sparse enough for other observers to compare with their own view. Telescopes varied, lenses introduced distortion and learning to see through the narrow field took practice; confirmation therefore required instruments and trained eyes in several places. Within months, astronomers elsewhere recovered the Jovian satellites. The page had gained a new source of evidence: marks made by an eye disciplined through crafted glass and made answerable to another eye far away.",
      ],
      image: `${imageRoot}/05-glass-adds-new-heavens.avif`,
      imageAlt:
        "A worn early telescope on a Venetian workbench leads into Galileo’s engraved lunar surface and dated sequence of Jupiter and its four moving lights.",
      imagePosition: "60% center",
      mobileImagePosition: "68% center",
      visualLabel: "Sidereus Nuncius · focused glass and dated drawings",
      visualTone: "glass-and-moon",
      side: "left",
      sourceIds: ["dear-2009", "biagioli-1993", "shapin-1996"],
      evidence: [
        "Galileo developed improved telescopes in 1609 after learning of the Dutch instrument and published his first astronomical observations in Sidereus Nuncius in March 1610.",
        "His lunar observations, resolution of the Milky Way and dated records of four bodies orbiting Jupiter expanded the kinds of celestial claim that crafted glass could support.",
      ],
      map: { x: 49, y: 65 },
    },
    {
      id: "blood-completes-the-circuit",
      actId: "nature-mathematical-voice",
      order: 6,
      period: "AD 1628",
      place: "London and Frankfurt",
      title: "Blood Completes the Circuit",
      thesis:
        "Harvey joined vivisection, valve demonstrations and quantitative reasoning to show that the heart drives blood around a circuit.",
      body: [
        "William Harvey placed fingers on a living pulse, watched exposed hearts in animals and tightened a band around a human arm. With a loose ligature, veins swelled while the artery continued to feed the limb; pressed blood could be moved along a vein toward the heart but venous valves obstructed movement the other way. Each manipulation isolated a direction. The body was no longer only a set of named parts. It could be made to disclose what happened between one beat and the next.",
        "Quantity supplied the decisive pressure. Harvey estimated the amount expelled by the heart at each contraction and multiplied even conservative measures by the number of beats. In a short time, more blood would pass through the heart than the body could plausibly manufacture from food or consume in its tissues. The old account of continual production and disappearance could not carry that volume. Blood leaving through the arteries had to return through the veins, with the heart maintaining a circulation.",
        "De motu cordis, printed at Frankfurt in 1628, set the case out compactly through observation, intervention and reckoning. Harvey could not see the capillary connections between the smallest arteries and veins; microscopy would reveal them in the next generation. Direction and volume established the circuit before the missing capillary link could be seen. Anatomy had acquired a dynamic proof: a living system inferred from visible valves, controlled pressure and a total that refused the inherited account.",
      ],
      image: `${imageRoot}/06-blood-completes-the-circuit.avif`,
      imageAlt:
        "Harvey’s restrained forearm valve demonstration is rendered in engraved line beside his 1628 figures, a red thread circuit and a brass volume counter.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Valve, ligature and quantitative circuit",
      visualTone: "circulation-proof",
      side: "right",
      sourceIds: ["dear-2009", "cunningham-1997", "westfall-1971"],
      evidence: [
        "Harvey used ligatures and the one-way action of venous valves to demonstrate the direction of blood flow in the limbs.",
        "De motu cordis used estimates of cardiac output to argue that blood must circulate because continual consumption and replacement could not account for the volume passing through the heart.",
      ],
      map: { x: 37, y: 46 },
    },
    {
      id: "geometry-takes-the-page",
      actId: "experiment-becomes-instrument",
      order: 7,
      period: "AD 1637",
      place: "Leiden",
      title: "Geometry Takes the Page",
      thesis:
        "Descartes made relations between number and shape portable, allowing curves to be constructed and investigated through algebraic operations.",
      body: [
        "La Géométrie appeared at Leiden in 1637 as one of three essays attached to René Descartes’s Discourse on Method. Descartes began with geometrical problems, named known and unknown line lengths and used a compact algebraic notation to express their relations. Multiplication, division and roots could be constructed as lengths; equations could classify curves and direct their solution. Shape and symbol had acquired a common working surface.",
        "That translation changed the reach of mathematics. A difficult problem no longer depended entirely on recognising the right ingenious diagram at first sight. Relations could be carried into symbols, transformed by general rules and returned to a constructible line or curve. The page itself became an instrument: inexpensive beside a great quadrant, precise without a metal joint and reproducible wherever a printer could set the signs. Its operation could be learned, criticised and applied to problems its author had never seen.",
        "The measured page now received evidence at several scales. Tycho’s angles, Kepler’s areas, Galileo’s telescopic markings and Harvey’s volume estimates could all enter ordered relations without becoming the same kind of fact. Instruments extended sense; mathematics exposed consequence. European inquiry grew powerful by fastening those different acts together. The next operation would use a column of liquid to turn the invisible atmosphere into a value and a mountain into part of the apparatus.",
      ],
      image: `${imageRoot}/07-geometry-takes-the-page.avif`,
      imageAlt:
        "A page from Descartes’s La Géométrie carries algebraic symbols into one engraved curve as only the necessary ruled lines appear.",
      imagePosition: "53% center",
      mobileImagePosition: "60% center",
      visualLabel: "La Géométrie · relation, operation and curve",
      visualTone: "ruled-geometry",
      side: "left",
      sourceIds: ["dear-2009", "gaukroger-1995", "westfall-1971"],
      evidence: [
        "Descartes published La Géométrie at Leiden in 1637 with the Discourse on Method and two other scientific essays.",
        "Its algebraic treatment of geometrical relations made curves and construction problems available to repeatable symbolic operations.",
      ],
      map: { x: 46, y: 39 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "instrument-resolution",
        prompt: "Make the invisible visible",
        accessibleSummary:
          "Three instrument states compare what the naked eye, telescope and microscope can resolve, what field each sacrifices and what kind of claim can enter the measured page.",
        initialId: "naked-eye",
        records: [
          {
            id: "naked-eye",
            label: "Use the naked eye",
            period: "Tycho’s observatory",
            kicker: "Wide field, calibrated position",
            detail:
              "A trained observer compares bright points across a broad sky while a large divided instrument supplies angular measure.",
            stageImage: `${imageRoot}/03-tycho-builds-an-observatory.avif`,
            fields: [
              {
                label: "Resolution",
                value: "Bright bodies and angular separation",
              },
              { label: "Field", value: "Broad celestial reference frame" },
              { label: "Supports", value: "Long positional series" },
            ],
            outcome:
              "Precision comes from scale, calibration, repetition and trained sight.",
          },
          {
            id: "telescope",
            label: "Focus the telescope",
            period: "Galileo · AD 1609–1610",
            kicker: "Narrow field, distant detail",
            detail:
              "Two lenses enlarge a small part of the sky, revealing relief on the Moon and moving bodies beside Jupiter.",
            stageImage: `${imageRoot}/05-glass-adds-new-heavens.avif`,
            fields: [
              { label: "Resolution", value: "Fine remote structure" },
              { label: "Field", value: "Narrow and demanding to aim" },
              {
                label: "Supports",
                value: "Dated drawings and repeated sightings",
              },
            ],
            outcome:
              "Claims once beyond natural sight can be compared by observers using related instruments.",
          },
          {
            id: "microscope",
            label: "Focus the microscope",
            period: "London and Delft · AD 1665–1680",
            kicker: "Tiny field, nearby worlds",
            detail:
              "Carefully made lenses enlarge minute surfaces and living forms whose scale had kept them outside ordinary description.",
            stageImage: `${imageRoot}/11-lensmakers-open-small-worlds.avif`,
            fields: [
              { label: "Resolution", value: "Minute texture and organisms" },
              { label: "Field", value: "Tiny, lit and carefully prepared" },
              {
                label: "Supports",
                value: "Drawings, specimens and correspondence",
              },
            ],
            outcome:
              "The territory of observable fact expands downward in scale as well as outward in distance.",
          },
        ],
      },
    },
    {
      id: "air-receives-weight",
      actId: "experiment-becomes-instrument",
      order: 8,
      period: "AD 1643–1648",
      place: "Florence, Rouen and Puy de Dôme",
      title: "Air Receives Weight",
      thesis:
        "Torricelli and Pascal made atmospheric pressure visible in a mercury column and used elevation to distinguish competing explanations.",
      body: [
        "A glass tube longer than a man’s arm was filled with mercury, sealed at one end and inverted into a dish. The liquid fell but stopped with a column roughly three quarters of a metre high, leaving an apparently empty space above. Evangelista Torricelli interpreted the suspension in 1643 through the pressure of the surrounding air upon the mercury in the dish. Air, though invisible, acted as a material body with weight. The height of a silver column made that action readable.",
        "Blaise Pascal saw how to separate this account from explanations that placed the cause inside the tube. If the atmosphere supported the column, less air above an instrument should mean a lower height. On 19 September 1648, his brother-in-law Florin Périer carried matched observations from Clermont up the Puy de Dôme, taking readings at stations along the ascent while another instrument remained below. The summit column stood lower; on returning, the base measurement agreed again. The mountain altered one condition while the tube and liquid remained comparable.",
        "The ascent gave experiment a new geography. A workshop had built the glass; a correspondent had framed the test; an observer had followed written instructions; elevation supplied the controlled difference; numbers returned in a report. The conclusion rested on agreement among instruments, stations and repeated base readings. The atmosphere entered the measured page as a variable. The barometer served natural philosophy and kept a practical record of changing weather.",
      ],
      image: `${imageRoot}/08-air-receives-weight.avif`,
      imageAlt:
        "A mercury tube becomes a mountain scale as Florin Périer’s 1648 route climbs Puy de Dôme through a sequence of ruled readings.",
      imagePosition: "55% center",
      mobileImagePosition: "62% center",
      visualLabel: "Mercury column · elevation as controlled difference",
      visualTone: "glass-and-contour",
      side: "right",
      sourceIds: ["dear-2009", "westfall-1971", "shapin-1996"],
      evidence: [
        "Torricelli’s mercury experiment of 1643 produced a sustained column with a space above it and supported an explanation based on atmospheric pressure.",
        "Florin Périer’s Puy de Dôme observations of 19 September 1648 found the mercury column lower at elevation and checked the result against readings below.",
      ],
      map: { x: 42, y: 56 },
    },
    {
      id: "vacuum-enters-the-room",
      actId: "experiment-becomes-instrument",
      order: 9,
      period: "AD 1659–1662",
      place: "Oxford and London",
      title: "Vacuum Enters the Room",
      thesis:
        "Hooke’s air pump and Boyle’s experimental programme created controlled events that witnesses, tables and printed reports could carry beyond the room.",
      body: [
        "Robert Hooke turned the demanding idea of an evacuated receiver into a machine that could be worked before company. For Robert Boyle he designed and improved a pump whose rack, piston, stopcocks and sealed glass vessel removed air through repeated strokes. The apparatus leaked, glass could fail and each trial required skilled hands. That difficulty was part of the achievement. A workshop object made degrees of rarefaction available on command, allowing the same enclosed space to be observed as one condition changed.",
        "Boyle filled the programme with questions. Would a flame persist? Could a bell still be heard? How would a small animal breathe? What force did compressed or expanding air exert? Some demonstrations yielded ambiguity, and the welfare of animals made the effect of lost air severe, but the sequence gave inquiry a stable grammar: describe the apparatus, mark the operation, report the observable change and distinguish what the trial established from what remained uncertain. Invited witnesses could attest that the event had occurred without having to accept every explanation Boyle proposed.",
        "New Experiments Physico-Mechanical appeared in 1660, turning the room into a textual space another investigator might reconstruct. In the enlarged 1662 edition, pressure and volume readings supported the inverse relation associated with Boyle’s law: compressing a fixed quantity of air increased its spring. The pump joined craft, money, witnessing, prose and number. Nature had been made to answer inside an artificial boundary, and the report allowed the answer to travel after the receiver had filled with air again.",
      ],
      image: `${imageRoot}/09-vacuum-enters-the-room.avif`,
      imageAlt:
        "An accurate Hooke-Boyle air pump stands before witnesses beside cards for flame, sound, respiration and pressure-volume readings.",
      imagePosition: "58% center",
      mobileImagePosition: "66% center",
      visualLabel: "Air pump · operation, witness and report",
      visualTone: "experimental-room",
      side: "left",
      sourceIds: ["shapin-1996", "shapin-schaffer-1985", "hunter-1989"],
      evidence: [
        "Hooke constructed and improved the air pump used in Boyle’s programme of experiments on rarefied air, combustion, sound, respiration and pressure.",
        "Boyle’s 1660 and 1662 publications described apparatus and witnessed trials in enough detail to turn a difficult mechanical performance into a public experimental claim.",
      ],
      map: { x: 35, y: 44 },
    },
    {
      id: "observation-enters-the-register",
      actId: "knowledge-learns-to-accumulate",
      order: 10,
      period: "AD 1660–1666",
      place: "London and Paris",
      title: "Observation Enters the Register",
      thesis:
        "Societies, secretaries and journals gave observations an address where they could be preserved, witnessed, challenged and sent onward.",
      body: [
        "In London from 1660, natural philosophers assembled around a table to watch experiments, hear letters, assign further trials and enter decisions into minutes. The Royal Society’s charters followed in 1662 and 1663, but its working strength came from repeated offices: president, council, curators, clerks and especially secretaries who kept correspondence moving. A report from abroad could be read aloud; an instrument could be ordered; a claim could be held over until someone tried it. Curiosity acquired an address and a memory.",
        "Henry Oldenburg, the Society’s first secretary, converted his European correspondence into Philosophical Transactions in March 1665. He initially owned, edited and published the journal himself as an enterprise closely associated with the Royal Society. Monthly issues condensed letters, books and observations, named claimants and dates, and invited further reports. It was a fast public register of priority, testimony and criticism, managed by an editor who knew which reader in another city might answer.",
        "Paris added a different institutional form when Louis XIV founded the Académie royale des sciences in 1666 and supported a small body of investigators through the crown. London’s fellowship and Paris’s salaried academy competed, borrowed and corresponded within a wider landscape that included Italian academies, Dutch workshops and university chairs. Europe did not need one institution to agree before knowledge advanced. It needed durable places where a result could arrive, be kept, meet an objection and depart with a sharper description.",
      ],
      image: `${imageRoot}/10-observation-enters-the-register.avif`,
      imageAlt:
        "A Royal Society minute book, a packet of European letters and the first Philosophical Transactions issue move across a ruled route toward Paris.",
      imagePosition: "55% center",
      mobileImagePosition: "63% center",
      visualLabel: "Minute, letter and monthly printed register",
      visualTone: "public-record",
      side: "right",
      sourceIds: [
        "shapin-1996",
        "hunter-1989",
        "royal-society-transactions-history",
      ],
      evidence: [
        "The Royal Society began regular meetings in 1660 and used minutes, correspondence, appointed trials and officers to preserve and organise experimental work.",
        "Oldenburg launched Philosophical Transactions in March 1665 as an editor-owned enterprise linked to the Royal Society, giving European observations a recurring public register.",
        "The French crown founded the Académie royale des sciences in 1666, establishing a major salaried counterpart to London’s fellowship.",
      ],
      map: { x: 38, y: 43 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "result-goes-public",
        prompt: "Send a result into public",
        accessibleSummary:
          "Five stages carry an observation from a private letter through a society meeting, witnessed repetition and Oldenburg’s journal to a critical answer from another European city.",
        initialId: "private-letter",
        records: [
          {
            id: "private-letter",
            label: "Write the letter",
            period: "Delft to London",
            kicker: "A claim enters the route",
            detail:
              "The observer names the object, method, date and visible result for a correspondent able to find an interested audience.",
            stageImage: `${imageRoot}/10-observation-enters-the-register.avif`,
            fields: [
              { label: "Carries", value: "Description, drawing and date" },
              {
                label: "Risk",
                value: "Private circulation can stop with one recipient",
              },
              { label: "Office", value: "Secretary receives and routes" },
            ],
            outcome:
              "The result leaves the observer without yet becoming a public fact.",
          },
          {
            id: "society-meeting",
            label: "Read it at the meeting",
            period: "London",
            kicker: "The claim acquires witnesses",
            detail:
              "A secretary reads the report, the fellowship examines its terms and the minutes preserve what was heard and requested next.",
            fields: [
              { label: "Audience", value: "Fellows and invited witnesses" },
              { label: "Record", value: "Dated minutes" },
              { label: "Question", value: "What can be tried here?" },
            ],
            outcome:
              "An institution remembers the claim and can commission a response.",
          },
          {
            id: "witnessed-repetition",
            label: "Repeat what can be repeated",
            period: "Meeting and workshop",
            kicker: "Method meets another hand",
            detail:
              "A curator or instrument maker reconstructs the feasible operation before witnesses and records agreement, difference or failure.",
            fields: [
              {
                label: "Needs",
                value: "Apparatus, skill and explicit procedure",
              },
              {
                label: "Produces",
                value: "Corroboration or a sharper discrepancy",
              },
              {
                label: "Limit",
                value: "Not every distant observation can be recreated",
              },
            ],
            outcome:
              "The method becomes part of the evidence rather than remaining backstage.",
          },
          {
            id: "journal-abstract",
            label: "Print the account",
            period: "Philosophical Transactions · from AD 1665",
            kicker: "Priority reaches strangers",
            detail:
              "Oldenburg selects and edits a compact account for his monthly journal, fixing a name, date and claim in circulating print.",
            fields: [
              { label: "Editor", value: "Henry Oldenburg" },
              {
                label: "Ownership",
                value: "Oldenburg’s enterprise in this period",
              },
              {
                label: "Practice",
                value: "Named claims, dates and editorial circulation",
              },
            ],
            outcome:
              "Readers outside the meeting receive a stable version they can cite and challenge.",
          },
          {
            id: "answer-from-another-city",
            label: "Receive an answer",
            period: "Paris, Florence, Leiden or Prague",
            kicker: "The route closes and opens again",
            detail:
              "Another investigator sends a confirming observation, objection, improved instrument or competing interpretation back into correspondence.",
            fields: [
              { label: "Return", value: "Letter, specimen, drawing or table" },
              { label: "Effect", value: "Correction and accumulation" },
              { label: "Next step", value: "Publish the refined question" },
            ],
            outcome:
              "Public knowledge advances through an answerable circuit rather than a single act of proclamation.",
          },
        ],
      },
    },
    {
      id: "lensmakers-open-small-worlds",
      actId: "knowledge-learns-to-accumulate",
      order: 11,
      period: "AD 1656–1680",
      place: "The Hague, London and Delft",
      title: "Lensmakers Open Small Worlds",
      thesis:
        "Huygens, Hooke and Leeuwenhoek joined exact craft to public description, extending measurable nature into time and microscopic life.",
      body: [
        "At The Hague in 1656, Christiaan Huygens applied the regular swing of a pendulum to a clock mechanism and patented the design the next year. The escapement, weight, gearing and pendulum turned a physical regularity into more even divisions of time. Astronomers could compare transits and motions with finer temporal resolution; experimenters could relate a visible change to a measured interval. A natural law had entered brass and become a tool for finding other regularities.",
        "Robert Hooke’s Micrographia of 1665 opened in another direction. With a compound microscope, careful lighting and a practised hand, Hooke made a needle point appear blunt, named the box-like cells of cork and spread the body of a flea across a great engraved plate. The images were arguments about instruments as much as objects. He described preparation and optical limits so readers could understand how the sight had been produced. What ordinary vision dismissed as smooth or minute acquired structure on a public page.",
        "In Delft, Antoni van Leeuwenhoek achieved extraordinary magnification with tiny single lenses that he ground, mounted and held close to the eye. From 1673 his letters to the Royal Society described muscle fibres, blood cells and living animalcules in water and infusions. Secretive craft and unfamiliar sights made trust difficult, so observations drew requests for witnesses and confirmation. The route worked: local viewers attested, London experimenters examined related specimens and further letters refined the claims. By 1680, a clockmaker’s law, an engraver’s plate and a draper’s lens had enlarged the reach of fact in duration and scale.",
      ],
      image: `${imageRoot}/11-lensmakers-open-small-worlds.avif`,
      imageAlt:
        "A pendulum escapement, Hooke’s engraved flea and Leeuwenhoek’s small single-lens instrument occupy three stations joined by one brass measuring rule.",
      imagePosition: "59% center",
      mobileImagePosition: "67% center",
      visualLabel: "Pendulum, engraved plate and single lens",
      visualTone: "small-worlds",
      side: "left",
      sourceIds: ["dear-2009", "hunter-1989", "gest-2004"],
      evidence: [
        "Huygens developed the pendulum clock in 1656 and patented it in 1657, materially improving the regular measurement of time.",
        "Hooke’s Micrographia of 1665 joined detailed accounts of microscopy to large engravings, including cork cells and the flea.",
        "Leeuwenhoek reported microscopic living organisms to the Royal Society from the 1670s, and the society sought witness and corroboration for unfamiliar observations made with his single lenses.",
      ],
      map: { x: 44, y: 35 },
    },
    {
      id: "one-law-binds-earth-and-sky",
      actId: "knowledge-learns-to-accumulate",
      order: 12,
      period: "AD 1684–1687",
      place: "Cambridge and London",
      title: "One Law Binds Earth and Sky",
      thesis:
        "Newton’s Principia joined terrestrial and celestial motion within a mathematical system built from Europe’s accumulated observations, problems and publishing institutions.",
      body: [
        "In 1684 Edmond Halley travelled from London to Cambridge carrying a precise question. If attraction toward the Sun diminished with the square of distance, what path would a planet follow? Robert Hooke and Christopher Wren had discussed the problem with him, and Kepler’s laws defined the result any proof had to recover. Isaac Newton replied that he had derived an ellipse. When the earlier paper could not be found, he reconstructed the argument and sent Halley the short De motu. A question sharpened in one society had reached the mathematician prepared to transform it.",
        "Newton expanded the paper for more than two years. The Principia of 1687 began with definitions and laws of motion, developed its arguments predominantly through geometry and established how forces generate paths. Universal gravitation then joined phenomena previously treated apart: falling bodies and the Moon’s deflection, Kepler’s planetary relations, the motions of comets and the tides. The synthesis did not erase the exacting differences among these problems. It gave them common principles from which quantitative consequences could be derived and checked against observations.",
        "Halley carried the manuscript through the Royal Society, managed the printing and paid its cost when the Society could not. The first edition was already a collective European achievement in its materials: Kepler’s laws from Tycho’s measurements, Galileo’s study of motion, Huygens’s dynamics, Hooke’s challenge, astronomical tables, skilled diagram cutting and the press. Newton’s own copy soon filled with annotations for revision. By 1700 the measured page could hold observation, instrument, mathematical proof, criticism and correction in one continuing enterprise. Earth and sky had entered the same law, and the law remained open on the table.",
      ],
      image: `${imageRoot}/12-one-law-binds-earth-and-sky.avif`,
      imageAlt:
        "Newton’s annotated first edition of the Principia lies beside Halley’s route from London, while one restrained geometric arc joins terrestrial fall to lunar orbit.",
      imagePosition: "55% center",
      mobileImagePosition: "62% center",
      visualLabel: "Principia · geometry, gravitation and revision",
      visualTone: "universal-geometry",
      side: "right",
      sourceIds: ["dear-2009", "westfall-1971", "cambridge-newton-principia"],
      evidence: [
        "Halley’s 1684 visit prompted Newton to produce De motu and then expand the work into the Principia, published in 1687 with Halley’s editorial and financial support.",
        "The Principia argued chiefly through geometry and joined laws of motion and universal gravitation to planetary paths, terrestrial motion, comets and tides.",
        "Newton’s annotated first-edition copy preserves extensive changes prepared for later editions, making revision visible within the work’s own publication history.",
      ],
      map: { x: 35, y: 40 },
    },
  ],
};
