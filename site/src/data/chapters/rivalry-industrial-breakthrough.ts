import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/rivalry-industrial-breakthrough";

export const rivalryIndustrialBreakthrough: ChapterDefinition = {
  slug: "rivalry-industrial-breakthrough",
  number: "20",
  title: "Rivalry and the Industrial Breakthrough",
  openingTitleLines: ["Rivalry and the", "Industrial Breakthrough"],
  period: "AD 1709–1862",
  claim:
    "Europe joined coal, experiment, precision manufacture, transport and company law into a system that multiplied power, capital and output. Steam released industry from the limits of muscle and falling water; the registered limited-liability company gathered fortunes large and small behind works no household could finance alone.",
  openingClaim:
    "A furnace opened the coal seam, an engine drained the mine, the factory multiplied the machine, the railway synchronized the market and company law gave dispersed savings a durable body.",
  hero: {
    image: `${imageRoot}/opening-capital-line.avif`,
    mobileImage: `${imageRoot}/opening-capital-line-mobile.avif`,
    imageAlt:
      "A fine copper line crosses a black industrial drawing from a coke furnace and beam engine to a railway prospectus, share ledger and distant signal lamps.",
    imagePosition: "center center",
    mobileImagePosition: "61% center",
    visualLabel: "The Capital Line · energy, machinery, transport and law",
  },
  theme: {
    id: "capital-line",
    label: "The Capital Line",
  },
  openingAction: "Set power in motion",
  mapLabel:
    "Furnaces, mines, workshops, mills, railways and registries through which Europe made industrial power compound",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Furnace records · engine models · workshop papers · mill plans · railway trials · exhibition catalogues · company statutes",
  acts: [
    {
      id: "power-from-stone",
      number: "I",
      label: "Power from stone",
      period: "AD 1709–1769",
      title: "Power from Stone",
      detail:
        "Coke iron, mine drainage and a European culture of useful knowledge turn Britain’s coalfields into a new source of mechanical power.",
    },
    {
      id: "machine-learns-to-multiply",
      number: "II",
      label: "The machine learns to multiply",
      period: "AD 1765–1801",
      title: "The Machine Learns to Multiply",
      detail:
        "Fuel-saving steam, precise manufacture and factory organisation convert individual devices into repeatable systems of production.",
    },
    {
      id: "line-conquers-distance",
      number: "III",
      label: "The line conquers distance",
      period: "AD 1784–1851",
      title: "The Line Conquers Distance",
      detail:
        "Regular wrought iron and scheduled railways bind mines, mills, ports and markets into one timed industrial order.",
    },
    {
      id: "capital-becomes-institution",
      number: "IV",
      label: "Capital becomes an institution",
      period: "AD 1811–1862",
      title: "Capital Becomes an Institution",
      detail:
        "Registration, incorporation, transferable shares and limited liability give large enterprises a life and estate distinct from their changing members.",
    },
  ],
  ending: {
    period: "AD 1862",
    title: "Europe Can Finance the Impossible",
    detail:
      "At night, a signalman closes the lever and two lamps answer along the cutting. The rails beneath them embody a century and a half of accumulated power: coke-fed iron, steam raised from water, cylinders bored to measure, machines arranged through whole buildings and traffic governed by a public timetable. Beside the engineer’s plan lies another instrument of equal consequence, a registered share certificate marked Limited. The company can hold the land, contract for the bridge, call unpaid capital and survive the death or departure of any subscriber. Each investor’s exposure ends at a stated boundary while the common undertaking continues. In 1862 Europe possesses the mechanical and legal means to sustain projects larger than a private fortune and longer than a working life. The copper line follows the railway to the harbour, enters a cable house and passes beneath the sea toward a world waiting to be placed on schedule.",
    image: `${imageRoot}/ending-europe-can-finance-the-impossible.avif`,
    mobileImage: `${imageRoot}/ending-europe-can-finance-the-impossible-mobile.avif`,
    nextPeriod: "AD 1802–1914",
  },
  returnHash: "rivalry-industrial-breakthrough",
  nextHash: "european-world",
  nextTitle: "The European World",
  nextSlug: "european-world",
  movements: [
    {
      id: "the-furnace-takes-coal",
      actId: "power-from-stone",
      order: 1,
      period: "AD 1709",
      place: "Coalbrookdale, Shropshire",
      title: "The Furnace Takes Coal",
      thesis:
        "Abraham Darby’s coke-fired furnace broke ironmaking’s dependence on charcoal and joined Britain’s metal industry to the energy stored in its coal seams.",
      body: [
        "Coke baskets reached the charging floor at Coalbrookdale in 1709, beside iron ore and limestone. Abraham Darby I had taken over an old blast furnace in the Severn gorge and adapted knowledge acquired around malt kilns and metal casting to a stubborn ironmaking problem. Mineral coal carried impurities that damaged the charge; coke, produced by heating coal away from air, offered a cleaner, stronger and more porous fuel. Under a continuous blast it supported the weight of the furnace burden and supplied the heat needed to release liquid iron.",
        "Darby’s first commercial advantage lay in cast goods, especially thin-walled pots made with moulding methods he had patented. The wider consequence appeared as the technique spread and improved. Charcoal tied every furnace to woodland that required years to regrow, and rising output competed for that acreage. Coke connected smelting instead to coalfields whose seams could feed many larger furnaces. Coalbrookdale also concentrated ore, limestone, waterpower, skilled founders and access to the Severn, so each difficulty could be answered within one working district.",
        "The substitution created demand for its own enlargement. Furnaces required coal; collieries required iron tools, rails, pumps and cylinders; better iron allowed engines and mines to reach greater scale. Coal did not enter industry as a solitary fuel waiting to be burned. European craft and enterprise made it part of a reinforcing material system. The first obstruction lay underground, where water collected in every deepening shaft and stopped miners before they could reach the next seam.",
      ],
      image: `${imageRoot}/01-the-furnace-takes-coal.avif`,
      imageAlt:
        "Workers charge coke, iron ore and limestone into the low-lit Coalbrookdale blast furnace as molten cast iron runs into sand moulds below.",
      imagePosition: "56% center",
      mobileImagePosition: "63% center",
      visualLabel: "Coalbrookdale furnace · coke, blast and liquid iron",
      visualTone: "furnace-black",
      side: "left",
      sourceIds: [
        "allen-industrial-2009",
        "mokyr-enlightened-economy-2009",
        "ironbridge-darby-furnace",
      ],
      evidence: [
        "The surviving Coalbrookdale furnace is the site where Abraham Darby I began smelting iron with coke in 1709.",
        "Coke ultimately released British iron output from the renewable but land-intensive charcoal supply and joined smelting to the expanding coal economy.",
      ],
      map: { x: 34, y: 44 },
    },
    {
      id: "the-mine-breathes",
      actId: "power-from-stone",
      order: 2,
      period: "AD 1712",
      place: "Dudley, West Midlands",
      title: "The Mine Breathes",
      thesis:
        "Newcomen’s atmospheric engine used coal to drain the mine, opening deeper coal reserves that could feed further engines.",
      body: [
        "Water rose through the workings near Dudley as quickly as pumps could lift it. In 1712 Thomas Newcomen erected the first documented practical engine able to work the problem stroke after stroke. A boiler admitted low-pressure steam beneath a piston in a vertical cylinder. A jet of cold water condensed the steam inside; the pressure of the surrounding atmosphere then drove the piston downward. The rocking beam lifted the heavy pump rods hanging in the shaft while the returning weight prepared the next cycle.",
        "The engine consumed coal extravagantly because its cylinder was heated by steam and chilled by injection water at every stroke. At a coal mine that weakness could be borne. Fuel stood close to the boiler, and every additional depth drained by the machine exposed fuel for another day’s pumping. Owners could measure the bargain in accessible seams rather than elegant thermodynamics. Engines spread through British mining districts because they performed one costly task with a steadiness that horses and waterwheels could not match underground.",
        "Newcomen combined experimental knowledge of air pressure and condensation with the established skills of boiler makers, blacksmiths, carpenters, masons and pump builders. Ironfounders learned to cast larger cylinders; mechanics improved valves and linkages; engine minders converted the cycle into routine. Heat had produced useful motion without wind, river or muscle, though most of that heat escaped. The waste inside the alternating hot and cold cylinder became the exact problem James Watt would isolate half a century later.",
      ],
      image: `${imageRoot}/02-the-mine-breathes.avif`,
      imageAlt:
        "A sectional Newcomen engine house near Dudley shows boiler, open-topped cylinder, rocking beam, pump rods and a flooded mine shaft in one mechanical line.",
      imagePosition: "58% center",
      mobileImagePosition: "66% center",
      visualLabel: "Atmospheric engine · steam, vacuum and mine pump",
      visualTone: "engine-house",
      side: "right",
      sourceIds: [
        "rolt-allen-newcomen-1977",
        "science-museum-newcomen-engine",
        "allen-industrial-2009",
      ],
      evidence: [
        "The first documented practical Newcomen engine was erected near Dudley in 1712 to pump water from a mine.",
        "Condensing steam inside the cylinder created a partial vacuum so atmospheric pressure drove the piston and beam that raised the mine pump rods.",
      ],
      map: { x: 35, y: 44 },
      interaction: {
        kind: "chapter-v2",
        family: "split",
        variant: "steam-condensation-sequence",
        prompt: "Condense the steam",
        accessibleSummary:
          "Four cutaway states follow steam power from Newcomen’s repeatedly cooled cylinder through Watt’s separate condenser and rotary motion to a factory drive shaft, identifying the fuel saved and work unlocked at each step.",
        initialId: "atmospheric-stroke",
        records: [
          {
            id: "atmospheric-stroke",
            label: "Work the atmospheric stroke",
            period: "Dudley · AD 1712",
            kicker: "Condensation occurs in the cylinder",
            detail:
              "Steam fills the cylinder, injection water collapses it and atmospheric pressure pushes the piston down to lift pump rods in the shaft.",
            stageImage: `${imageRoot}/02-the-mine-breathes.avif`,
            fields: [
              { label: "Hot chamber", value: "Working cylinder" },
              { label: "Cold chamber", value: "The same cylinder" },
              { label: "Work released", value: "Reciprocating mine pump" },
            ],
            outcome:
              "A dependable engine reaches deeper coal while repeated heating and cooling consume large quantities of fuel.",
          },
          {
            id: "separate-the-condenser",
            label: "Separate the condenser",
            period: "Glasgow · AD 1765",
            kicker: "The working cylinder stays hot",
            detail:
              "Watt draws spent steam into a permanently cool chamber, preserving the heat already invested in the main cylinder.",
            stageImage: `${imageRoot}/04-watt-closes-the-cylinder.avif`,
            fields: [
              { label: "Hot chamber", value: "Insulated working cylinder" },
              { label: "Cold chamber", value: "Separate condenser" },
              { label: "Capacity added", value: "Far lower coal consumption" },
            ],
            outcome:
              "Fuel economy carries steam power beyond coalfields where waste coal had concealed the engine’s appetite.",
          },
          {
            id: "turn-the-shaft",
            label: "Turn the shaft",
            period: "Soho · AD 1780s",
            kicker: "Reciprocation becomes rotation",
            detail:
              "Double-acting power, gearing and a flywheel translate the beam’s stroke into continuous rotary motion.",
            stageImage: `${imageRoot}/04-watt-closes-the-cylinder.avif`,
            fields: [
              { label: "Input", value: "Alternating piston stroke" },
              { label: "Transfer", value: "Beam, gear and flywheel" },
              { label: "Work released", value: "A turning line shaft" },
            ],
            outcome:
              "Steam can now drive machinery designed around repeated rotation rather than pumping alone.",
          },
          {
            id: "drive-the-factory",
            label: "Drive the factory",
            period: "Manchester · AD 1785–1801",
            kicker: "One engine supplies a whole floor",
            detail:
              "A central shaft distributes rotary power through gears and belts to ordered banks of textile machinery.",
            stageImage: `${imageRoot}/06-manchester-multiplies.avif`,
            fields: [
              { label: "Power source", value: "Coal-fired engine" },
              { label: "Distribution", value: "Shafts, gears and belts" },
              {
                label: "Capacity added",
                value: "Many machines at one address",
              },
            ],
            outcome:
              "The mill’s location, scale and working rhythm can be designed around power supplied on demand.",
          },
        ],
      },
    },
    {
      id: "improvement-becomes-a-calling",
      actId: "power-from-stone",
      order: 3,
      period: "AD 1750–1769",
      place: "Birmingham and Glasgow",
      title: "Improvement Becomes a Calling",
      thesis:
        "Natural philosophers, instrument makers and manufacturers made useful knowledge cumulative by moving measured problems between lecture room, workshop, correspondence and market.",
      body: [
        "At the University of Glasgow, instruments passed continually between the lecture room and James Watt’s workshop. Joseph Black’s investigations of heat gave names and measured relations to changes that an engine builder could feel in metal and steam. Watt repaired quadrants, balances and a model Newcomen engine; each commission trained the same habits of calibration, close fit and comparison. A philosophical proposition became valuable when a crafted object could expose its consequence and another operator could repeat the result.",
        "Birmingham supplied a denser commercial laboratory. Matthew Boulton organised hundreds of specialised operations at Soho; Josiah Wedgwood tested clays, glazes, kilns and markets; John Roebuck, James Keir and Joseph Priestley moved among chemistry, medicine, mines and manufacture. The circle later known as the Lunar Society met, dined, argued and exchanged letters with correspondents across Britain and continental Europe. Dissenting academies, provincial societies, printed proceedings and patent specifications carried useful knowledge outside the older universities and court workshops.",
        "This culture rewarded an improvement that could survive contact with material and customer. Makers compared fuel bills, tolerances, breakages and output; investors supplied time for trials; patents offered a temporary property in a working principle; correspondence recruited skills unavailable in one town. Europe’s Republic of Letters had learned to preserve and challenge knowledge in print. Britain’s workshops placed that habit beside coal users willing to pay for efficiency. When Watt recognised heat thrown away inside the Newcomen cylinder, he could draw upon learned correspondence and workshop practice at once.",
      ],
      image: `${imageRoot}/03-improvement-becomes-a-calling.avif`,
      imageAlt:
        "A Glasgow instrument bench and Birmingham workshop table meet across letters, calipers, heat apparatus, engine drawings and a Lunar Society dinner invitation.",
      imagePosition: "54% center",
      mobileImagePosition: "61% center",
      visualLabel: "Useful knowledge · lecture, workshop and correspondence",
      visualTone: "drawing-blue",
      side: "left",
      sourceIds: [
        "mokyr-enlightened-economy-2009",
        "mokyr-2016",
        "uglow-lunar-men-2002",
      ],
      evidence: [
        "Watt worked as a mathematical-instrument maker at Glasgow while Joseph Black’s investigations helped establish a measured science of heat around him.",
        "Birmingham manufacturers and natural philosophers exchanged experimental, mechanical and commercial knowledge through meetings, letters, societies and workshops.",
      ],
      map: { x: 34, y: 39 },
    },
    {
      id: "watt-closes-the-cylinder",
      actId: "machine-learns-to-multiply",
      order: 4,
      period: "AD 1765–1776",
      place: "Glasgow and Soho, Birmingham",
      title: "Watt Closes the Cylinder",
      thesis:
        "Watt’s separate condenser saved the cylinder’s heat, while Boulton’s capital and Soho’s manufacturing network turned that thermal insight into a commercial engine.",
      body: [
        "While repairing Glasgow’s model Newcomen engine, Watt measured the steam sacrificed whenever cold water entered the working cylinder. His decisive arrangement of 1765 moved condensation into a separate chamber kept cold and connected by a valve. The main cylinder could remain hot. Steam completed its work, passed into the condenser and collapsed there without forcing the engine to reheat a large mass of metal on the next stroke. Watt’s 1769 patent described the principle as a method for lessening the consumption of steam and fuel.",
        "A model could establish the idea; a saleable full-sized engine demanded accurate cylinders, durable seals, working capital and access to mines that would risk replacing established equipment. Matthew Boulton brought those resources at Soho. After Parliament extended the patent in 1775, the partners organised specialist suppliers and sent trained erectors to customers. John Wilkinson’s boring methods produced cylinders whose roundness allowed a piston to hold its seal. The first commercial Boulton & Watt engines entered service in 1776.",
        "The firm sold measured fuel economy as well as iron. Its royalty commonly related to the coal saved against an equivalent Newcomen engine, making measurement part of the contract and the engine counter part of the business. Early installations remained pumping machines, particularly valuable where coal was dear. Boulton saw a wider market in rotary power for mills and workshops, and Watt continued to develop double action, controlled motion and gearing. Scientific heat, precision manufacture, patent, credit and customer had become inseparable parts of one invention.",
      ],
      image: `${imageRoot}/04-watt-closes-the-cylinder.avif`,
      imageAlt:
        "A measured cutaway keeps Watt’s steam cylinder hot while a copper pipe leads to the cool separate condenser and Soho order books lie beyond.",
      imagePosition: "59% center",
      mobileImagePosition: "67% center",
      visualLabel: "Separate condenser · heat preserved, fuel saved",
      visualTone: "copper-and-steel",
      side: "right",
      sourceIds: [
        "science-museum-watt-condenser",
        "mokyr-enlightened-economy-2009",
        "uglow-lunar-men-2002",
      ],
      evidence: [
        "Watt’s surviving 1765 condenser model embodies the separation of a hot working cylinder from a permanently cool condensing chamber.",
        "Boulton and Watt formed their partnership after the 1775 patent extension, and their first commercial engines were installed in 1776 with precision cylinders supplied through specialist manufacture.",
      ],
      map: { x: 34, y: 41 },
    },
    {
      id: "the-building-becomes-a-machine",
      actId: "machine-learns-to-multiply",
      order: 5,
      period: "AD 1771–1785",
      place: "Cromford, Derbyshire",
      title: "The Building Becomes a Machine",
      thesis:
        "At Cromford, Arkwright and his partners arranged power, machinery, materials and disciplined labour through one building, creating a factory system others could copy.",
      body: [
        "Richard Arkwright and his partners leased a narrow site at Cromford in August 1771. The water draining nearby lead workings supplied a modest but unusually constant flow, and channels directed it to an overshot wheel beside a five-storey stone mill. Inside, the water frame drew cotton through successive pairs of rollers and twisted it on rapidly turning spindles. Strong, regular warp thread emerged from machinery that required continuous power and careful coordination rather than the intermittent motion of a household wheel.",
        "The mill organised space as rigorously as the frame organised fibre. Preparing, carding, drawing, roving and spinning occupied connected stages; shafts and gearing carried one source of motion across floors; warehouses received material and protected output. A bell and fixed shifts brought workers to the speed of the machinery. Maintenance crews kept water, gears and frames in order while successive teams prepared and spun fibre. Housing, a market and later a school helped recruit families to a rural site whose machinery Arkwright guarded closely.",
        "Cromford concentrated operations already known separately and made their relation reproducible. Investors could inspect a complete system, hire mechanics who had worked within it and adapt the plan beside another reliable power source. Arkwright’s patents were eventually struck down, allowing the machinery to spread more freely; the organisational pattern had already escaped the Derwent valley. A factory could now be designed as a single productive instrument composed of building, power train, machines, stores, supervision and measured time.",
      ],
      image: `${imageRoot}/05-the-building-becomes-a-machine.avif`,
      imageAlt:
        "A tall section through Cromford Mill traces water from the sough to the wheel, vertical shafts, preparation rooms and ordered banks of water frames.",
      imagePosition: "57% center",
      mobileImagePosition: "64% center",
      visualLabel: "Cromford Mill · one power source, ordered production",
      visualTone: "mill-section",
      side: "left",
      sourceIds: [
        "berg-age-manufactures-1994",
        "fitton-wadsworth-1958",
        "derwent-cromford-mill",
      ],
      evidence: [
        "Arkwright and his partners leased the Cromford site in 1771 and built a water-powered cotton-spinning complex around a constant supply from mine drainage and local streams.",
        "The Cromford system joined mechanised preparation and spinning, central power transmission, multi-storey architecture and a disciplined workforce in a model copied elsewhere.",
      ],
      map: { x: 35, y: 42 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "spindle-multiplication",
        prompt: "Multiply the spindle",
        accessibleSummary:
          "Four production states hold one worker’s time constant while the household wheel, spinning jenny, water frame and steam-driven mill place progressively larger groups of spindles under coordinated motion.",
        initialId: "household-wheel",
        records: [
          {
            id: "household-wheel",
            label: "Turn the household wheel",
            period: "Domestic spinning",
            kicker: "Hand and foot govern one thread",
            detail:
              "The spinner controls drafting, twist and winding at a single wheel, fitting production around the household’s other work.",
            stageImage: `${imageRoot}/05-the-building-becomes-a-machine.avif`,
            fields: [
              { label: "Power", value: "Human treadle and hand" },
              { label: "Spindles in motion", value: "One" },
              { label: "Organisation", value: "Household rhythm" },
            ],
            outcome:
              "Skill remains concentrated in one spinner and one continuously tended thread.",
          },
          {
            id: "spinning-jenny",
            label: "Extend the spinning jenny",
            period: "Lancashire · from the 1760s",
            kicker: "One hand tends several spindles",
            detail:
              "A moving carriage and row of spindles multiply the spinner’s reach while human power continues to set the pace.",
            stageImage: `${imageRoot}/05-the-building-becomes-a-machine.avif`,
            fields: [
              { label: "Power", value: "Human arm" },
              { label: "Spindles in motion", value: "A growing row" },
              { label: "Best suited", value: "Softer weft yarn" },
            ],
            outcome:
              "Mechanical arrangement multiplies output before production leaves the workshop or home.",
          },
          {
            id: "water-frame",
            label: "Engage the water frame",
            period: "Cromford · from AD 1771",
            kicker: "Rollers and water impose continuity",
            detail:
              "Powered rollers draw the fibre at controlled rates while banks of spindles twist strong, regular yarn.",
            stageImage: `${imageRoot}/05-the-building-becomes-a-machine.avif`,
            fields: [
              { label: "Power", value: "Waterwheel and shaft" },
              { label: "Spindles in motion", value: "A powered bank" },
              { label: "Organisation", value: "Purpose-built mill" },
            ],
            outcome:
              "Output grows through continuous power, ordered preparation and workers assigned to linked stages.",
          },
          {
            id: "steam-driven-mill",
            label: "Drive the whole floor",
            period: "Manchester · by AD 1801",
            kicker: "The river no longer chooses the address",
            detail:
              "Rotary steam supplies shafts across successive floors, letting machines, labour, coal and orders concentrate in the city.",
            stageImage: `${imageRoot}/06-manchester-multiplies.avif`,
            fields: [
              { label: "Power", value: "Coal-fired rotary engine" },
              { label: "Spindles in motion", value: "Multiple machine banks" },
              { label: "Organisation", value: "Urban factory system" },
            ],
            outcome:
              "The same working hour enters a coordinated installation whose scale can rise with engines, floors and capital.",
          },
        ],
      },
    },
    {
      id: "manchester-multiplies",
      actId: "machine-learns-to-multiply",
      order: 6,
      period: "AD 1785–1801",
      place: "Manchester",
      title: "Manchester Multiplies",
      thesis:
        "Rotary steam freed cotton mills from isolated water sites and allowed Manchester’s machinery, labour, trade, coal and credit to enlarge one another.",
      body: [
        "Rotary steam altered the geography of the factory. Water remained valuable, but a manufacturer no longer had to place every new bank of machinery beside a remote fall and accept its seasonal limits. From the mid-1780s engines began turning cotton machinery in and around Manchester. Coal could be delivered, boilers fired and shafts extended where merchants, mechanics and workers already gathered. One engine supplied an organised building; several mills created a concentrated market for engine builders, founders, repairers and tool makers.",
        "Manchester’s enlargement depended upon routes as well as machines. The Bridgewater Canal carried coal cheaply from the Duke of Bridgewater’s mines, while Liverpool connected the district to Atlantic shipping. Raw cotton from plantations in the Americas entered through the port; yarn and cloth returned to national and overseas markets. Warehouses, insurers, brokers and banks translated shipments into orders and credit. A merchant with news of demand could find a spinner, dyer, carrier and lender within the same dense commercial field.",
        "The first national census in 1801 recorded an industrial town transformed within a generation. Factory bells and powered machinery fixed hours with a regularity domestic production had never required. Streets filled with migrant households; smoke, housing and sanitation became engineering problems created by concentration itself. Manchester’s decisive achievement was the feedback among its parts: each mill enlarged demand for coal, iron, transport, finance and precision, and every stronger supplier lowered the difficulty of building the next mill.",
      ],
      image: `${imageRoot}/06-manchester-multiplies.avif`,
      imageAlt:
        "An early Manchester cotton mill opens in section at dawn, with its steam engine, line shafts, workers, canal basin, warehouse and counting house visibly connected.",
      imagePosition: "55% center",
      mobileImagePosition: "63% center",
      visualLabel: "Manchester · engine, mill, canal, warehouse and credit",
      visualTone: "urban-gunmetal",
      side: "right",
      sourceIds: [
        "allen-industrial-2009",
        "berg-age-manufactures-1994",
        "orourke-2010",
      ],
      evidence: [
        "Rotative steam engines entered British textile production from the 1780s and allowed mills to concentrate near urban labour, markets and coal deliveries rather than at waterpower sites alone.",
        "Manchester’s cotton cluster linked Liverpool’s imported raw material, canal-borne coal, specialised machinery, warehousing, merchant credit and factory labour.",
      ],
      map: { x: 34, y: 42 },
    },
    {
      id: "iron-takes-a-new-form",
      actId: "line-conquers-distance",
      order: 7,
      period: "AD 1784–1815",
      place: "Portsmouth and Merthyr Tydfil",
      title: "Iron Takes a New Form",
      thesis:
        "Puddling and rolling converted coke-smelted pig iron into larger, more regular supplies of wrought bars and plates for machinery, structures and rails.",
      body: [
        "Inside a reverberatory furnace, flame swept across the iron without mixing the metal directly with the coal. Henry Cort’s 1784 puddling patent organised this separation into a process for refining pig iron. A puddler stirred the molten charge through heat and glare as carbon burned away and pasty iron gathered into balls. Hammering expelled slag; grooved rolls, covered by Cort’s earlier patent, squeezed and shaped the blooms into bars with greater speed and regularity than repeated work beneath a forge hammer.",
        "The patents supplied a framework rather than a finished recipe. Ironmasters and puddlers altered furnace dimensions, tools, temperatures and sequences as the process moved into new works. In South Wales, the coal and iron district around Merthyr Tydfil expanded through great integrated plants such as Cyfarthfa, Dowlais and Penydarren. Furnaces, forges, rolling mills, tramroads and skilled crews formed a landscape capable of answering naval and military orders during the long wars with France, then turning the same capacity toward civil construction.",
        "Cast iron could carry compression and assume complex moulded forms; wrought iron could be forged, rolled, joined and endure tension and shock. Cheaper, more regular bars and plates improved boilers, engine parts, tools and bridges. Rolled rails gave wheeled loads a durable path from pit and furnace to canal and port. Industry had acquired material bones produced by its own fuel and machines. When locomotive builders sought a line able to carry moving engines at unprecedented speed, ironworks could answer with miles of repeated section.",
      ],
      image: `${imageRoot}/07-iron-takes-a-new-form.avif`,
      imageAlt:
        "Puddlers work a reverberatory furnace while an incandescent bloom passes through grooved rolls toward finished bars, boiler plate and rail sections.",
      imagePosition: "58% center",
      mobileImagePosition: "65% center",
      visualLabel: "Puddling and rolling · iron refined into regular form",
      visualTone: "rolling-mill",
      side: "left",
      sourceIds: [
        "evans-labyrinth-flames-2005",
        "tylecote-metallurgy-1992",
        "allen-industrial-2009",
      ],
      evidence: [
        "Cort’s rolling patent of 1783 and puddling patent of 1784 helped establish a coal-fuelled route from pig iron to wrought iron bars, with later ironworkers substantially improving practice.",
        "Large South Wales works integrated coke furnaces, refining, rolling and transport to supply growing wartime and industrial demand.",
      ],
      map: { x: 34, y: 47 },
    },
    {
      id: "the-railway-takes-time",
      actId: "line-conquers-distance",
      order: 8,
      period: "AD 1829–1830",
      place: "Rainhill, Liverpool and Manchester",
      title: "The Railway Takes Time",
      thesis:
        "The Liverpool and Manchester Railway joined tested locomotives, engineered track, subscribed capital and a public timetable into a transport system that made distance reliably shorter.",
      body: [
        "At Rainhill in October 1829, judges weighed locomotives and their loads, measured fuel and water, and required repeated runs before investors, engineers and a large public. The trial asked which moving engine could serve a railway already cut and built between Liverpool and Manchester. Rocket, produced by Robert Stephenson & Co under George and Robert Stephenson with the railway’s treasurer Henry Booth contributing to its boiler arrangement, combined a multi-tubular boiler, blast pipe and light construction. It completed the prescribed work and won the prize.",
        "The line opened on 15 September 1830 as a double-track interurban railway worked by steam locomotives. Surveyors and navvies had driven cuttings, crossed Chat Moss and built embankments, bridges and termini; Parliament had authorised the company to assemble land and capital along the route. The death of William Huskisson during the ceremonial opening exposed the physical danger of a speed for which public behaviour and operating rules were unprepared. Regular trains nevertheless began carrying passengers and freight between the port and the manufacturing city.",
        "Canal boats had taken about twelve hours between the two cities and horse-drawn coaches around three or four. Scheduled railway journeys brought the passage toward two hours and added dependable departure to speed. A bale, letter, passenger and price could arrive within the same planned interval. Timetables, signalling, maintenance and coordinated stations made the locomotive useful as a system. European engineers and investors came to inspect it; within two decades railways were joining Belgian, French and German industrial districts by the same union of iron, steam, capital and time.",
      ],
      image: `${imageRoot}/08-the-railway-takes-time.avif`,
      imageAlt:
        "Stephenson’s Rocket runs at credible scale on the Rainhill track while judges record load, fuel, water and elapsed time before a watching crowd.",
      imagePosition: "54% center",
      mobileImagePosition: "62% center",
      visualLabel: "Rainhill and the Liverpool–Manchester line · tested speed",
      visualTone: "rail-and-copper",
      side: "right",
      sourceIds: [
        "science-industry-liverpool-manchester",
        "national-railway-museum-rocket",
        "simmons-railway-1978",
      ],
      evidence: [
        "The October 1829 Rainhill Trials compared locomotive performance under specified loads and repeated runs; Rocket won the contest.",
        "The Liverpool and Manchester Railway opened on 15 September 1830 as a steam-worked, double-track interurban line carrying passengers and freight on scheduled services.",
      ],
      map: { x: 33, y: 42 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "journey-clock",
        prompt: "Compress the journey",
        accessibleSummary:
          "Three synchronized route states carry the same bale between Liverpool and Manchester by canal, turnpike and the 1830 railway, comparing elapsed time, carrying method and the certainty of arrival.",
        initialId: "canal-freight",
        records: [
          {
            id: "canal-freight",
            label: "Load the canal boat",
            period: "Before AD 1830",
            kicker: "Bulk moves cheaply at water’s pace",
            detail:
              "A bale follows the navigation from Liverpool toward Manchester through a long, steady passage shaped by water level, locks and towpath.",
            stageImage: `${imageRoot}/08-the-railway-takes-time.avif`,
            fields: [
              { label: "Typical elapsed time", value: "About 12 hours" },
              { label: "Motive power", value: "Towed boat" },
              { label: "Strength", value: "Heavy freight in one load" },
            ],
            outcome:
              "The canal carries bulk economically, while its long interval ties mill orders to half-day movements.",
            points: [
              {
                id: "liverpool",
                label: "Liverpool",
                detail: "Dock and loading point",
                x: 20,
                y: 57,
              },
              {
                id: "manchester",
                label: "Manchester",
                detail: "Warehouse and mill market",
                x: 79,
                y: 38,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "turnpike-coach",
            label: "Take the turnpike",
            period: "Before AD 1830",
            kicker: "Road gains speed at limited scale",
            detail:
              "A horse-drawn coach or wagon follows a congested engineered road, changing the balance between speed, load and cost.",
            stageImage: `${imageRoot}/08-the-railway-takes-time.avif`,
            fields: [
              { label: "Passenger elapsed time", value: "About 3–4 hours" },
              { label: "Motive power", value: "Teams of horses" },
              { label: "Constraint", value: "Small loads and road congestion" },
            ],
            outcome:
              "The turnpike moves people quickly enough for a day’s business, with capacity bounded by horses and road space.",
            points: [
              {
                id: "liverpool",
                label: "Liverpool",
                detail: "Coach departure",
                x: 20,
                y: 57,
              },
              {
                id: "manchester",
                label: "Manchester",
                detail: "Coach arrival",
                x: 79,
                y: 38,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "scheduled-railway",
            label: "Release the scheduled train",
            period: "From AD 1830",
            kicker: "Speed and capacity share one line",
            detail:
              "A steam locomotive carries passengers and goods over a dedicated double track under a published sequence of departures.",
            stageImage: `${imageRoot}/08-the-railway-takes-time.avif`,
            fields: [
              { label: "Scheduled elapsed time", value: "Toward 2 hours" },
              { label: "Motive power", value: "Steam locomotive" },
              {
                label: "Institution",
                value: "Timetable, signals and stations",
              },
            ],
            outcome:
              "Reliable arrival lets merchants, mills and connecting carriers plan around the same clock.",
            points: [
              {
                id: "liverpool",
                label: "Liverpool",
                detail: "Crown Street terminus",
                x: 20,
                y: 57,
              },
              {
                id: "rainhill",
                label: "Rainhill",
                detail: "Locomotive proving ground",
                x: 42,
                y: 50,
              },
              {
                id: "manchester",
                label: "Manchester",
                detail: "Liverpool Road station",
                x: 79,
                y: 38,
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
      id: "the-continent-enters-the-hall",
      actId: "line-conquers-distance",
      order: 9,
      period: "AD 1851",
      place: "Hyde Park, London",
      title: "The Continent Enters the Hall",
      thesis:
        "The Great Exhibition assembled Europe’s machines, materials and instruments beneath one measured roof, turning Britain’s breakthrough into a continental programme of inspection and emulation.",
      body: [
        "Joseph Paxton’s Crystal Palace rose in Hyde Park from repeated iron columns, trusses and panes manufactured to standard dimensions. The building covered the exhibition without masonry walls or a traditional roof span; parts arrived, fitted and could later be taken down. When the Great Exhibition opened on 1 May 1851, its own structure stood as the first exhibit. A mature industrial system had supplied glass, cast iron, transport, drawings and contractual coordination quickly enough to enclose trees and crowds beneath a vast transparent hall.",
        "Inside, visitors encountered machine tools, locomotives, pumps, textile machinery, scientific instruments, steel, chemicals, ceramics and finished goods arranged by material, function and country. British machinery occupied imposing courts, while France, Belgium, the German states, Switzerland and other European producers displayed distinct strengths in precision work, metallurgy, design and manufacture. The official catalogue fixed names, makers, addresses and specifications on paper, allowing an object seen in London to become an order, comparison or model elsewhere.",
        "The turnstiles counted over six million admissions before the exhibition closed in October. Engineers measured mechanisms; manufacturers studied finish and cost; artisans and families saw operations previously hidden inside distant works. Belgium had already built the continent’s first dense railway and industrial belt, French workshops joined machinery to exact craft, and German technical schools and firms were gathering strength. The hall made enlargement appear teachable. It also revealed the cost of the next step: railways, mines and factories now required capital on a scale the ordinary partnership could not safely hold.",
      ],
      image: `${imageRoot}/09-the-continent-enters-the-hall.avif`,
      imageAlt:
        "The Crystal Palace central transept opens onto working machinery, iron, textiles, instruments and multilingual catalogues under clear modular glass.",
      imagePosition: "51% center",
      mobileImagePosition: "59% center",
      visualLabel:
        "Great Exhibition · machine, catalogue and continental comparison",
      visualTone: "exhibition-glass",
      side: "left",
      sourceIds: [
        "great-exhibition-catalogue-1851",
        "auerbach-great-exhibition-1999",
        "orourke-2010",
      ],
      evidence: [
        "The prefabricated iron-and-glass Crystal Palace opened in Hyde Park on 1 May 1851 and housed manufactured goods, machinery, materials and instruments from Britain and foreign exhibitors.",
        "The exhibition recorded over six million admissions, while its official catalogues identified makers and objects for comparison beyond the hall.",
      ],
      map: { x: 37, y: 48 },
    },
    {
      id: "capital-outgrows-the-partnership",
      actId: "capital-becomes-institution",
      order: 10,
      period: "AD 1811–1844",
      place: "London",
      title: "Capital Outgrows the Partnership",
      thesis:
        "Factories and railways required transferable pools of capital and contracts that survived changing investors, exposing the partnership as a legal vessel too small for industrial works.",
      body: [
        "By the 1810s, British enterprise operated through several legal bodies that fitted together awkwardly. Partners owned a firm’s assets and answered personally for its debts; a death, retirement or dispute could disturb both ownership and litigation. Unincorporated joint-stock associations divided interests into shares and used elaborate deeds and trusts to approximate continuity, but the law often treated their numerous proprietors as partners. A chartered corporation possessed a distinct body and succession, though obtaining a royal charter or private Act required influence, expense and delay.",
        "Railways made every weakness visible. A line had to raise subscriptions from hundreds or thousands of people, survey a route, acquire land across many estates, contract for earthworks and iron, call instalments over years and continue after original promoters sold or died. Parliament incorporated each major railway through its own Act because compulsory land powers required public authority. The resulting company could hold property and sue in one name, while its transferable shares moved through an expanding securities market. Industrial capital was becoming collective and long-lived before general law supplied a simple form.",
        "Parliament repealed the Bubble Act in 1825, then confronted a boom of promotions and failures that made publicity and orderly winding-up urgent. The Joint Stock Companies Act 1844 created a general route to registration and incorporation for qualifying joint-stock businesses. A public registrar received the deed and lists of shareholders; complete registration produced one incorporated body. Members remained ultimately exposed to company debts without a general statutory cap. Registration had supplied the name, record and continuing legal estate. The private fortune of each subscriber remained inside the creditor’s reach.",
      ],
      image: `${imageRoot}/10-capital-outgrows-the-partnership.avif`,
      imageAlt:
        "A London railway subscription desk holds a route survey, partnership deed and share book whose widening list of names extends beyond the paper boundary.",
      imagePosition: "56% center",
      mobileImagePosition: "64% center",
      visualLabel: "Subscription room · route, deed, calls and changing names",
      visualTone: "engraved-ledger",
      side: "right",
      sourceIds: [
        "harris-industrializing-law-2000",
        "joint-stock-companies-act-1844",
        "simmons-railway-1978",
      ],
      evidence: [
        "Before general incorporation, large English joint-stock enterprises often relied on partnership, trust and deed arrangements or sought an individual charter or private Act.",
        "The 1844 Act introduced registration and incorporation for qualifying joint-stock companies while leaving shareholders without a general statutory limit on liability.",
      ],
      map: { x: 37, y: 48 },
    },
    {
      id: "liability-finds-a-boundary",
      actId: "capital-becomes-institution",
      order: 11,
      period: "AD 1855–1856",
      place: "Westminster and the City of London",
      title: "Liability Finds a Boundary",
      thesis:
        "The statutes of 1855 and 1856 drew a public boundary around each shareholder’s exposure, allowing subscribed capital to face enterprise risk while the investor’s other property remained outside the company.",
      body: [
        "The Limited Liability Act received royal assent in August 1855 after Parliament decided that a disclosed boundary could draw savings toward productive enterprise. A registered company needed at least twenty-five members, shares with a nominal value of £10 or above and 20 per cent paid on each share to obtain limited status; banking and insurance were excluded. The qualifying company used Limited in its name. Members remained responsible for amounts unpaid on their shares, while creditors could no longer pursue every shareholder without limit after the company’s own estate failed.",
        "The Joint Stock Companies Act 1856 supplied that simpler form. For businesses within its scope, seven or more people could subscribe a memorandum and register an incorporated company with or without limited liability. The document stated the company’s name, registered office, objects, nominal capital, shares and the chosen liability of members; a limited company had to place Limited last in its name. Share certificates, a register of shareholders, filed resolutions, accounts and winding-up rules placed the boundary inside a public legal architecture rather than a private promise among partners.",
        "The boundary divided risks without dissolving obligation. The company held property and remained answerable for its debts; subscribed money, unpaid share capital and assets acquired in business stood inside the creditor’s claim. A shareholder risked the amount committed to the enterprise, including any portion not yet called, while house, workshop and unrelated savings stood outside. This finite exposure made an industrial share intelligible to people unable to inspect every bridge foundation or guarantee every manager. Europe had fashioned a legal machine capable of gathering strangers’ capital without merging their entire lives.",
      ],
      image: `${imageRoot}/11-liability-finds-a-boundary.avif`,
      imageAlt:
        "The enacted 1855 statute lies on an ivory desk as a copper boundary closes around subscribed shares and company property, leaving a household key and workshop tools outside.",
      imagePosition: "53% center",
      mobileImagePosition: "60% center",
      visualLabel:
        "Limited liability · subscribed risk inside a public boundary",
      visualTone: "statute-ivory",
      side: "left",
      sourceIds: [
        "limited-liability-act-1855",
        "joint-stock-companies-act-1856",
        "harris-industrializing-law-2000",
      ],
      evidence: [
        "The Limited Liability Act 1855 required at least twenty-five members, shares of £10 or above and 20 per cent paid on each share before a qualifying registered company could obtain limited status.",
        "Within its statutory scope, the 1856 Act allowed seven subscribers to form an incorporated company by memorandum and registration, with liability stated as limited or unlimited and Limited required as the last word of a limited company’s name.",
      ],
      map: { x: 37, y: 48 },
      interaction: {
        kind: "chapter-v2",
        family: "assembly",
        variant: "raise-capital-line",
        prompt: "Raise the capital line",
        accessibleSummary:
          "Four cumulative legal instruments alter one engraved railway prospectus: a registered name, share ledger, corporate estate and liability boundary extend the proposed line while distinguishing company assets from each subscriber’s private property.",
        initialId: "register-the-name",
        records: [
          {
            id: "register-the-name",
            label: "Register the name",
            period: "General registration · AD 1844",
            kicker: "The undertaking enters a public record",
            detail:
              "The promoters file the company’s governing deed, office and membership so contracts can attach to an identified incorporated body.",
            stageImage: `${imageRoot}/10-capital-outgrows-the-partnership.avif`,
            fields: [
              { label: "Instrument", value: "Registered company name" },
              {
                label: "Capacity added",
                value: "One identity in public records",
              },
              { label: "Capital line", value: "Promoters to surveyed route" },
            ],
            outcome:
              "The enterprise can be found and governed as one registered undertaking rather than a shifting list of partners.",
          },
          {
            id: "open-the-share-ledger",
            label: "Open the share ledger",
            period: "Subscription and transfer",
            kicker: "A large work is divided into stated interests",
            detail:
              "The ledger records who holds each numbered share, how much has been paid and what further capital the company may call.",
            stageImage: `${imageRoot}/10-capital-outgrows-the-partnership.avif`,
            fields: [
              { label: "Instrument", value: "Register of shareholders" },
              {
                label: "Capacity added",
                value: "Transferable units of capital",
              },
              { label: "Capital line", value: "Survey to first earthworks" },
            ],
            outcome:
              "Many subscriptions can finance one route while ownership changes without dividing the railway itself.",
          },
          {
            id: "separate-the-estate",
            label: "Separate the company estate",
            period: "Incorporation",
            kicker: "Land and contracts outlive the members",
            detail:
              "The incorporated body holds the route, rails, cash and contractual claims in its own name as shareholders enter and leave.",
            stageImage: `${imageRoot}/12-the-company-becomes-a-machine-for-the-future.avif`,
            fields: [
              { label: "Instrument", value: "Distinct corporate estate" },
              {
                label: "Capacity added",
                value: "Continuity and property holding",
              },
              {
                label: "Capital line",
                value: "Earthworks to bridge and track",
              },
            ],
            outcome:
              "The undertaking survives transfer, retirement and death because its property belongs to the continuing company.",
          },
          {
            id: "close-the-liability-boundary",
            label: "Close the liability boundary",
            period: "Statutory sequence · AD 1855–1862",
            kicker: "The subscribed amount defines exposure",
            detail:
              "The company and its committed capital answer for failure; each member’s liability ends at the unpaid amount on the shares held.",
            stageImage: `${imageRoot}/11-liability-finds-a-boundary.avif`,
            fields: [
              { label: "Instrument", value: "Limited liability by shares" },
              {
                label: "Inside the line",
                value: "Subscription and company estate",
              },
              {
                label: "Outside the line",
                value: "Other household and business property",
              },
            ],
            outcome:
              "Finite personal exposure lets a wider body of investors commit capital to works whose technical risks they cannot individually command.",
          },
        ],
      },
    },
    {
      id: "the-company-becomes-a-machine-for-the-future",
      actId: "capital-becomes-institution",
      order: 12,
      period: "AD 1862",
      place: "London, Paris, Brussels and Berlin",
      title: "The Company Becomes a Machine for the Future",
      thesis:
        "By 1862 European legislators had assembled registration, corporate continuity, transferable shares and limited exposure into a durable technology for financing industrial time.",
      body: [
        "The Companies Act received royal assent on 7 August 1862 and consolidated Britain’s recent statutes into a single working code. Seven subscribers could form an incorporated company by registering a memorandum. The registrar’s certificate brought a body corporate into being with perpetual succession, a common seal and power to hold land. Shares were personal property capable of transfer under the company’s rules. In a company limited by shares, each member’s remaining exposure was the amount unpaid on the shares recorded in the register.",
        "European company law developed through several legislatures rather than one copied text. French and Belgian commerce used the société anonyme and commandite traditions under codes and systems of public authorisation; Prussian and other German laws regulated joint-stock enterprise, while the General German Commercial Code of 1861 supplied common rules across participating states. Britain’s registration acts made incorporation and limited liability broadly accessible through filed documents. Banks, bourses and share markets connected these legal forms to savers who would never enter the mine or mill they financed.",
        "The resulting institution converted duration into an economic resource. A railway could demand capital in instalments, complete a route years after the first subscription, replace directors, transfer shares and maintain bridges after founders had died. The same form could hold a mine, dock, gasworks, waterworks or factory as one estate with accounts and succession. Europe’s industrial achievement rested equally on heat moving through a cylinder and obligation moving through a register. In 1862 the two lines met: mechanical power could enlarge production, and the limited company could keep the enlargement financed into the future.",
      ],
      image: `${imageRoot}/12-the-company-becomes-a-machine-for-the-future.avif`,
      imageAlt:
        "An 1862 company register opens into industrial and railway corridors toward London, Paris, Brussels and Berlin, each linked by distinct share certificates and one copper line.",
      imagePosition: "50% center",
      mobileImagePosition: "58% center",
      visualLabel: "Companies Act 1862 · incorporation, shares and succession",
      visualTone: "certificate-ivory",
      side: "right",
      sourceIds: [
        "companies-act-1862",
        "guinnane-corporation-place-2007",
        "hannah-corporate-economy-1976",
      ],
      evidence: [
        "The Companies Act 1862 consolidated incorporation, registration and winding-up law and defined companies with liability limited by shares or guarantee alongside unlimited companies.",
        "Registration under the Act created a body corporate with perpetual succession and power to hold land, while shares were transferable personal property and member exposure in a company limited by shares was tied to unpaid share capital.",
      ],
      map: { x: 45, y: 47 },
    },
  ],
};
