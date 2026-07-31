import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const checkOnly = process.argv.includes("--check");

function read(name) {
  return JSON.parse(fs.readFileSync(path.join(root, name), "utf8"));
}

function write(name, value) {
  const target = path.join(root, name);
  const serialized = `${JSON.stringify(value, null, 2)}\n`;
  if (checkOnly) {
    if (fs.readFileSync(target, "utf8") !== serialized) {
      throw new Error(`${name} is stale; run node native/blueprint/enrich.mjs`);
    }
    return;
  }
  fs.writeFileSync(target, serialized);
}

function countBy(values) {
  return Object.fromEntries(
    [...new Set(values)].sort().map((value) => [
      value,
      values.filter((candidate) => candidate === value).length
    ])
  );
}

// Every entry is an authored continuation of one concrete world trace. The
// generator must never substitute a target arc's generic consequence for the
// history of the trace itself. Each tuple is:
// [target content ID, target arc ID, operation, resulting world state].
const activationContinuity = {
  "trace-european-farming-belt": [
    ["steppe-comes-west", "steppe-comes-west-arc-01", "contest", "Mobile pastoral households enter the settled Danube world; fields and villages persist while land, descent and power are reordered around incoming groups."],
    ["bronze-europe", "bronze-europe-arc-01", "transform", "Agricultural surplus and settled craft support mines, palace stores and exchange routes; the farming belt becomes the productive ground of the bronze system."],
    ["rome-gathers-europe", "rome-gathers-europe-arc-02", "transform", "Roads, colonies, census and military levies turn cultivated Italy into the manpower and supply base of Roman expansion."],
    ["society-beyond-kin", "society-beyond-kin-arc-03", "transform", "Churches and corporate houses receive fields beyond lineage ownership; settled property gains institutional owners able to outlive their members."]
  ],
  "trace-seasonal-store": [
    ["bronze-europe", "bronze-europe-arc-01", "transform", "Household reserve becomes counted grain in palace stores, supporting specialists, ships and rulers beyond one agricultural year."],
    ["rome-gathers-europe", "rome-gathers-europe-arc-02", "transform", "Tax grain, magazines and scheduled supply extend the store across roads and ports to feed armies and cities."],
    ["medieval-commercial-revolution", "medieval-commercial-revolution-arc-02", "transform", "Ledgers and contracts carry claims on future harvests across distance, turning deferred use into transferable obligation."],
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-01", "supersede", "Coal and steam release productive power from the agricultural year's finite reserve, while food and seed remain bound to the seasons."]
  ],
  "trace-steppe-westward-road": [
    ["bronze-europe", "bronze-europe-arc-02", "transform", "Horse traction, wheeled vehicles and bronze weapons turn the household migration road into far-reaching warrior and exchange networks."]
  ],
  "trace-indo-european-inheritance": [
    ["bronze-europe", "bronze-europe-arc-02", "reactivate", "Inherited divine names, ritual fire, horse prestige and heroic formulae acquire distinct European Bronze Age forms."],
    ["greece-and-the-citizen", "greece-and-the-citizen-arc-01", "transform", "Greek language, epic metre, gods and inherited civic vocabulary give the shared inheritance a durable public form in the polis."],
    ["rome-gathers-europe", "rome-gathers-europe-arc-03", "transform", "Latin carries one Indo-European branch through Roman law, army and city even as the Roman name extends far beyond descent."],
    ["europe-reborn", "europe-reborn-arc-02", "transform", "Copied Latin and rising vernaculars carry related European languages through the written Christian commonwealth."]
  ],
  "trace-bronze-exchange": [
    ["greece-and-the-citizen", "greece-and-the-citizen-arc-01", "transform", "Palace redistribution disappears, but amber routes and Nordic workshops endure while ports, sanctuaries and poleis reopen exchange under civic authorities and private households."]
  ],
  "trace-heroic-memory": [
    ["greece-and-the-citizen", "greece-and-the-citizen-arc-01", "transform", "Sung memory becomes written epic and gives separate poleis a shared company of heroes, gods and exemplary deeds."],
    ["rome-gathers-europe", "rome-gathers-europe-arc-03", "transform", "Roman writers translate Greek epic into Latin ancestry and bind heroic memory to Rome's civic and imperial name."],
    ["europe-reborn", "europe-reborn-arc-02", "reactivate", "Scriptoria preserve Latin epic while courts and vernacular poets make heroic inheritance speak inside new European kingdoms."]
  ],
  "trace-polis-public-ground": [
    ["rome-gathers-europe", "rome-gathers-europe-arc-03", "transform", "Greek civic bodies remain active as Rome scales municipal office, public law and citizenship across the provinces."],
    ["empire-many-liberties", "empire-many-liberties-arc-01", "reactivate", "Chartered towns, councils and estate assemblies make law and office visible again inside the travelling Empire."],
    ["scientific-revolution", "scientific-revolution-arc-02", "transform", "The public register becomes a learned instrument: societies and journals give claims an address where others can inspect and challenge them."],
    ["enlightenment-public-opinion", "enlightenment-public-opinion-arc-02", "transform", "Club, assembly and printed judgment return public authority to organised citizens and make government answer before them."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "reactivate", "Elected chambers, independent courts and municipal government recover public ground inside the western post-war order."]
  ],
  "trace-hellenic-coalition": [
    ["rome-gathers-europe", "rome-gathers-europe-arc-02", "supersede", "Rome absorbs independent alliances into an unequal Italian system; allied service then forces the Social War settlement to widen citizenship."],
    ["europe-holds-the-line", "europe-holds-the-line-arc-02", "reactivate", "Independent European powers combine ships, fortified cities and relief armies against Ottoman advance without surrendering their governments."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "The Atlantic alliance binds sovereign democracies to common defence through standing treaty, planning and command."],
    ["europe-returns", "europe-returns-arc-02", "reactivate", "Allied states combine national forces, logistics and enlargement commitments to hold the eastern line."]
  ],
  "trace-roman-road-system": [
    ["empire-takes-cross", "empire-takes-cross-arc-01", "reactivate", "Imperial roads carry bishops, soldiers and patronage between old cities and Constantine's new capital."],
    ["europe-reborn", "europe-reborn-arc-02", "reactivate", "Kings, envoys and missionaries reuse Roman corridors while repaired roads and river routes connect new political centres."],
    ["empire-many-liberties", "empire-many-liberties-arc-01", "transform", "The itinerant crown follows renewed roads and chartered towns, turning movement itself into a form of imperial government."],
    ["habsburg-europe", "habsburg-europe-arc-01", "transform", "Post roads, Danube crossings and administrative stations overlay old corridors with a permanent dynastic service."],
    ["european-world", "european-world-arc-01", "transform", "Rail, cable and common time overwrite the measured road with a scheduled route able to cross states and oceans."],
    ["europe-returns", "europe-returns-arc-02", "reactivate", "European road and rail corridors carry civilian trade, Ukrainian supply and allied reinforcement toward the defended east."]
  ],
  "trace-roman-citizenship": [
    ["empire-takes-cross", "empire-takes-cross-arc-02", "transform", "A common civic status is joined by public Christianity as bishops and councils acquire authority within Roman cities."],
    ["europe-reborn", "europe-reborn-arc-01", "transform", "Universal Roman citizenship recedes, but city law, baptism and legal memory preserve forms of public personhood across successor kingdoms."],
    ["empire-many-liberties", "empire-many-liberties-arc-01", "transform", "Urban citizenship, chartered right and estate membership place several public statuses inside one imperial constitution."],
    ["enlightenment-public-opinion", "enlightenment-public-opinion-arc-02", "transform", "Public opinion and assembly turn inherited subjecthood toward citizenship as a claim to constitute government."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "National citizenship gains treaty and court protections inside a widening common European legal order."]
  ],
  "trace-constantinople-new-rome": [
    ["europe-reborn", "europe-reborn-arc-03", "reactivate", "New Rome's court, church and missions recognise Christian centres among the Slavs while the eastern Roman capital remains sovereign."],
    ["europe-holds-the-line", "europe-holds-the-line-arc-01", "supersede", "The Latin sack breaks the city's strength; the restored Roman capital endures until Ottoman conquest extinguishes the state in 1453."],
    ["europe-turns-seaward", "europe-turns-seaward-arc-01", "transform", "The Bosporus remains a strategic gate under Ottoman rule as Portugal seeks an ocean road to Asian trade it does not command."]
  ],
  "trace-roman-christian-law": [
    ["europe-reborn", "europe-reborn-arc-01", "reactivate", "Bishops, monasteries and copied law carry Roman Christian office and property through the loss of western imperial command."],
    ["papal-revolution", "papal-revolution-arc-02", "transform", "Canon law and Roman procedure make appointment, prohibition, excommunication and penance recognisable public acts."],
    ["society-beyond-kin", "society-beyond-kin-arc-03", "transform", "Canonists apply office, property, succession and legal personhood to bodies whose members continually change."],
    ["empire-many-liberties", "empire-many-liberties-arc-01", "transform", "Roman title, election, charter and court place plural rights inside a common Christian imperial order."],
    ["europe-holds-the-line", "europe-holds-the-line-arc-01", "reactivate", "Eastern and western Christian institutions organise settlement, armed pilgrimage and frontier rule after territorial catastrophe."],
    ["reformation", "reformation-arc-02", "contest", "Confessional war breaks Christian unity, but negotiation and law preserve a constitutional order in which rival confessions remain governed."],
    ["habsburg-europe", "habsburg-europe-arc-01", "transform", "The Habsburg crowns govern different laws and churches through ratified succession, civil office and a shared defence."]
  ],
  "trace-written-christian-commonwealth": [
    ["papal-revolution", "papal-revolution-arc-01", "transform", "Legates, synods, privileges and registers concentrate a dispersed Latin writing network into repeatable papal government."],
    ["society-beyond-kin", "society-beyond-kin-arc-03", "transform", "Rules, charters, seals and records let autonomous bodies persist inside the same literate Christian order."],
    ["medieval-commercial-revolution", "medieval-commercial-revolution-arc-02", "transform", "Notaries and merchant ledgers turn the written road from royal and ecclesiastical command toward portable private obligation."],
    ["empire-many-liberties", "empire-many-liberties-arc-01", "reactivate", "Charters, election records and written custom govern a plural realm whose crown cannot rule from one capital."]
  ],
  "trace-monastic-rule": [
    ["papal-revolution", "papal-revolution-arc-01", "reactivate", "Reformed monasteries supply personnel, discipline and copied norms to a papacy learning to govern beyond Rome."],
    ["society-beyond-kin", "society-beyond-kin-arc-02", "transform", "Vow, rule, common property and elected office make the monastery a working model for association beyond kin."]
  ],
  "trace-dual-jurisdiction": [
    ["society-beyond-kin", "society-beyond-kin-arc-03", "transform", "Ecclesiastical and civic bodies claim property, office and courts in their own names inside overlapping jurisdictions."],
    ["empire-many-liberties", "empire-many-liberties-arc-02", "reactivate", "Diet, imperial court and confessional settlement govern powers that retain distinct jurisdictions inside one order."],
    ["reformation", "reformation-arc-02", "contest", "Princes, estates and churches fight over worship and obedience until Westphalia resets the legal boundary without abolishing either jurisdiction."],
    ["enlightenment-public-opinion", "enlightenment-public-opinion-arc-01", "transform", "Comparison of European church and state arrangements makes jurisdiction answerable to public arguments about law and liberty."]
  ],
  "trace-canonical-election": [
    ["society-beyond-kin", "society-beyond-kin-arc-02", "transform", "Election becomes a repeatable means by which monasteries, guilds and communes place office above inheritance."],
    ["empire-many-liberties", "empire-many-liberties-arc-01", "transform", "Corporate election reaches the crown itself as prince-electors make succession lawful without making it hereditary."],
    ["reformation", "reformation-arc-01", "contest", "Territorial churches and Catholic reform reorganise ecclesiastical appointment while the older claim that office exceeds its holder survives."]
  ],
  "trace-consent-marriage": [],
  "trace-corporate-body": [
    ["medieval-commercial-revolution", "medieval-commercial-revolution-arc-01", "reactivate", "Merchant guilds and recognised fairs supply offices, records and jurisdiction within which time-bound ventures can be enforced."],
    ["hanseatic-north", "hanseatic-north-arc-02", "transform", "Cities and Kontore act through seals, delegates and common decisions while their changing members retain separate governments."],
    ["empire-many-liberties", "empire-many-liberties-arc-01", "reactivate", "Cities, chapters, estates and principalities carry rights as enduring bodies inside the imperial constitution."],
    ["dutch-republic", "dutch-republic-arc-01", "transform", "The VOC gives pooled capital permanent corporate life while transferable shares let individual investors depart."],
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-02", "transform", "Registration, corporate continuity and limited exposure make the company capable of works larger than one fortune."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "Treaty creates authorities and courts whose offices persist beyond the governments that founded them."]
  ],
  "trace-ledger-road": [
    ["hanseatic-north", "hanseatic-north-arc-01", "reactivate", "Kontor ledgers and reciprocal cargo settle obligations between Bergen, Lübeck and the Baltic without moving coin for every exchange."],
    ["dutch-republic", "dutch-republic-arc-02", "transform", "Municipal bank money and exchange prices make book entries enforceable settlement across a commercial republic."],
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-02", "transform", "Company accounts and scheduled railway receipts coordinate subscribed capital, material and distant work."],
    ["european-world", "european-world-arc-01", "transform", "Postal, telegraph and treaty systems carry recognised addresses, tariffs and settlement across national borders."]
  ],
  "trace-bounded-commercial-risk": [
    ["dutch-republic", "dutch-republic-arc-01", "transform", "The voyage partnership's bounded stake becomes permanent joint capital whose shares can change hands while marine insurance continues to price the hazards borne by the fleet."],
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-02", "transform", "General company law extends bounded shareholder exposure to registered industrial corporations while insurance prices the operational and cargo hazards they carry."],
    ["european-world", "european-world-arc-02", "reactivate", "Registered capital and insured risk finance railways, ports, shipping and administrative infrastructure across the connected world."],
  ],
  "trace-hanseatic-field": [
    ["empire-many-liberties", "empire-many-liberties-arc-02", "reactivate", "Self-governing cities retain their law while diets, circles and courts give their wider field a common peace."],
    ["europe-turns-seaward", "europe-turns-seaward-arc-02", "transform", "Northern commercial routes join the Atlantic as competing states and chartered companies extend trade beyond the Baltic field."],
    ["dutch-republic", "dutch-republic-arc-01", "transform", "Ships, merchant refugees and permanent joint capital consolidate northern commercial capacity in the Dutch Republic."]
  ],
  "trace-delegated-city-covenant": [
    ["empire-many-liberties", "empire-many-liberties-arc-02", "reactivate", "City delegations, estates and circles convert separate mandates into common judgment without erasing the bodies that issued them."],
    ["dutch-republic", "dutch-republic-arc-01", "transform", "Provincial union scales delegated consent into a republic whose members retain their governments and fiscal power."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "European states delegate defined powers to common authorities and courts while retaining their own constitutional seals."]
  ],
  "trace-imperial-liberties": [
    ["europe-holds-the-line", "europe-holds-the-line-arc-02", "reactivate", "Imperial estates and territories contribute roads, money, fortresses and troops to a defence assembled from distinct powers."],
    ["reformation", "reformation-arc-02", "contest", "Confessional war tests estate rights to destruction; Westphalia preserves the Empire by confirming negotiated jurisdiction."],
    ["habsburg-europe", "habsburg-europe-arc-01", "transform", "Habsburg lands retain diets, laws and crowns while common defence and service bind them to one dynasty."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "National governments bind power through treaty and court while retaining constitutional authority within the common order."]
  ],
  "trace-imperial-public-peace": [
    ["europe-holds-the-line", "europe-holds-the-line-arc-02", "reactivate", "Imperial circles and estates coordinate levy, roads and frontier defence through institutions built to replace private feud."],
    ["reformation", "reformation-arc-02", "contest", "The Thirty Years' War destroys the working peace before congress and reciprocal law restore a governable imperial settlement."],
    ["habsburg-europe", "habsburg-europe-arc-01", "transform", "The Habsburg lands carry courts, estates and public-law habits from the Empire into continuous civil service and common defence."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "Treaty and court place disputes between democratic states under common judgment instead of armed settlement."]
  ],
  "trace-christian-frontier": [
    ["habsburg-europe", "habsburg-europe-arc-01", "transform", "Danube forts, frontier service and military communities become permanent institutions of the Habsburg crowns."],
    ["europe-returns", "europe-returns-arc-02", "reactivate", "The defended eastern line now rests on sovereign states, Ukrainian resistance and allied commitments rather than a dynastic military border."]
  ],
  "trace-coalition-defence": [
    ["habsburg-europe", "habsburg-europe-arc-01", "reactivate", "Several crowns and frontier communities combine revenue, roads and troops for sustained defence along the Danube."],
    ["europe-at-war", "europe-at-war-arc-01", "contest", "Alliance commitments and mass mobilisation turn mutual defence into a chain that carries a continental crisis into total war."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "NATO gives coalition defence a permanent treaty, integrated planning and Atlantic reinforcement."],
    ["europe-returns", "europe-returns-arc-02", "reactivate", "Allied enlargement, national forces and continental logistics make defence at the eastern line a standing common obligation."]
  ],
  "trace-atlantic-sea-road": [
    ["dutch-republic", "dutch-republic-arc-01", "transform", "Dutch fluyts, charts and permanent company capital turn Atlantic routes into dense, repeatable commercial circuits."],
    ["european-world", "european-world-arc-01", "transform", "Steam packets, canals and submarine cable place the sea road on a public schedule."],
    ["europe-at-war", "europe-at-war-arc-01", "contest", "Blockade, submarine war, convoy and expeditionary armies weaponise the same ocean routes that connected Europe's world."]
  ],
  "trace-pilot-archive": [
    ["scientific-revolution", "scientific-revolution-arc-01", "transform", "The pilot's cumulative log becomes part of a wider discipline in which tables, instruments and corrected observation answer to the world."],
    ["dutch-republic", "dutch-republic-arc-01", "reactivate", "Commercial charting, soundings and harbour knowledge guide a republic whose power moves by ship."],
    ["european-world", "european-world-arc-02", "transform", "State hydrography and territorial survey standardise local observations into a global administrative archive."]
  ],
  "trace-confessional-print-network": [
    ["scientific-revolution", "scientific-revolution-arc-02", "transform", "The presses and correspondence that reproduced confession now circulate measured claims, diagrams and criticism between investigators."],
    ["dutch-republic", "dutch-republic-arc-01", "reactivate", "Refugee printers and plural cities make the republic a European junction for books, news and confessional argument."],
    ["enlightenment-public-opinion", "enlightenment-public-opinion-arc-01", "transform", "Periodical and refugee press detach continental circulation from church control and place institutions before a reading public."]
  ],
  "trace-westphalian-settlement": [
    ["habsburg-europe", "habsburg-europe-arc-01", "reactivate", "After Westphalia confirms estate jurisdictions inside the Empire, Habsburg rulers concentrate common work in their hereditary crowns."],
    ["dutch-republic", "dutch-republic-arc-01", "reactivate", "Recognition at Münster secures the Dutch Republic's place among European states while its provinces retain their federal compact."],
    ["europe-at-war", "europe-at-war-arc-01", "supersede", "The Empire preserved at Westphalia disappears in 1806, and by 1914 sovereign alliance diplomacy cannot contain industrial mobilisation."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "European states pool specified powers in treaty authorities and courts without dissolving their statehood."]
  ],
  "trace-danube-common-home": [
    ["europe-at-war", "europe-at-war-arc-01", "supersede", "War, hunger and national secession dissolve the dynastic common home in 1918, leaving its peoples, cities and routes divided among successor states."],
    ["continent-rebuilt", "continent-rebuilt-arc-02", "reactivate", "Successor nations separated by Soviet power reopen borders and public life as the eastern European revolutions converge in 1989."],
    ["europe-returns", "europe-returns-arc-01", "transform", "Restored central European states choose a common legal and defensive home through separate accessions to the Union and NATO."]
  ],
  "trace-habsburg-rail-braid": [
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-02", "transform", "Continental iron, railway law and corporate capital enlarge the crownland braid into a European system of scheduled movement."],
    ["european-world", "european-world-arc-01", "transform", "Telegraph, international post and common time make the rail braid interoperable beyond the monarchy's borders."],
    ["europe-at-war", "europe-at-war-arc-01", "contest", "Mobilisation seizes the railway timetable; blockade, military priority and imperial collapse sever the common network."],
    ["continent-rebuilt", "continent-rebuilt-arc-02", "reactivate", "The Iron Curtain cuts inherited routes until opened borders and restored governments reconnect them in 1989."],
    ["europe-returns", "europe-returns-arc-02", "transform", "Central European corridors carry accession trade, Ukrainian supply and allied reinforcement across the old crownland geography."]
  ],
  "trace-measured-page": [
    ["dutch-republic", "dutch-republic-arc-02", "reactivate", "Audited accounts, exchange prices and engineering records make measurement part of republican trust."],
    ["enlightenment-public-opinion", "enlightenment-public-opinion-arc-01", "transform", "Comparison applies the measured page to institutions, placing laws and governments beside observable alternatives."],
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-01", "reactivate", "Instrumented experiment, precision improvement and recorded trials make steam power cumulative rather than accidental."],
    ["european-world", "european-world-arc-02", "transform", "Survey, technical standard and public-health register make measured knowledge an instrument of continental administration."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "Allocation, treaty and court turn measured obligations into repeatable rules for reconstruction and exchange."],
    ["europe-returns", "europe-returns-arc-01", "reactivate", "Accession criteria and monitored reforms make constitutional change answer to recorded European standards."]
  ],
  "trace-republic-of-letters": [
    ["dutch-republic", "dutch-republic-arc-01", "reactivate", "Dutch cities, printers and learned refugees become a dense junction in Europe's correspondence network."],
    ["enlightenment-public-opinion", "enlightenment-public-opinion-arc-01", "transform", "Correspondence and learned journals widen into periodical press, coffeehouse discussion and public comparison."],
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-01", "transform", "Published tables, drawings and workshop reports carry practical improvements between mines, foundries and engineers."]
  ],
  "trace-dutch-credit-machine": [
    ["enlightenment-public-opinion", "enlightenment-public-opinion-arc-01", "reactivate", "Exchange prices, public accounts and financial news give urban readers a continuous judgment on state and commerce."],
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-02", "transform", "Public credit and transferable claims finance railways and registered companies whose needs exceed merchant partnership."],
    ["european-world", "european-world-arc-01", "transform", "Banking and securities mobilise capital for steamship, cable and scheduled infrastructure across the world."],
    ["europe-at-war", "europe-at-war-arc-01", "contest", "Belligerent states commandeer credit, taxation and debt to sustain industrial war beyond ordinary revenue."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "reactivate", "Public accounts, credit and convertible exchange support reconstruction and the widening common market."]
  ],
  "trace-water-government": [
    ["rivalry-industrial-breakthrough", "rivalry-industrial-breakthrough-arc-01", "transform", "Steam pumps and iron machinery enlarge drainage capacity while audited water boards preserve distributed responsibility."]
  ],
  "trace-european-public-opinion": [
    ["europe-at-war", "europe-at-war-arc-02", "contest", "Party monopoly, censorship, racial law and terror close the public spaces through which judgment could oppose total dominion."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "reactivate", "Free elections, parliament and independent press restore organised public judgment within western democratic states."],
    ["europe-returns", "europe-returns-arc-01", "reactivate", "Public mobilisation, constitutional debate and the Maidan make European allegiance an expressed political choice."]
  ],
  "trace-comparative-law": [
    ["continent-rebuilt", "continent-rebuilt-arc-01", "reactivate", "Post-war constitutions, conventions and courts place national systems beside common European standards of government."],
    ["europe-returns", "europe-returns-arc-01", "transform", "The Copenhagen criteria turn comparative judgment of law and institutions into a gate for voluntary accession."]
  ],
  "trace-industrial-power-system": [
    ["european-world", "european-world-arc-01", "transform", "Steamship, railway, cable manufacture and scheduled ports project the connected industrial system across oceans."],
    ["europe-at-war", "europe-at-war-arc-01", "contest", "States reorganise coal, steel, factories and railways for attrition, multiplying supply and destruction through the same system."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "reactivate", "Coal, steel, machinery and power return to civilian reconstruction under shared allocation and market rules."],
    ["europe-returns", "europe-returns-arc-02", "reactivate", "European industry and logistics are mobilised again to sustain Ukrainian defence and replenish the eastern line."]
  ],
  "trace-limited-company": [
    ["european-world", "european-world-arc-02", "reactivate", "Durable corporate bodies finance railways, ports and utilities whose work crosses generations and borders."],
    ["europe-at-war", "europe-at-war-arc-01", "contest", "War ministries direct firms, requisition output and absorb private risk into national mobilisation."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "reactivate", "Registered companies operate across a common market whose treaty rules outlive individual governments."]
  ],
  "trace-global-schedule": [
    ["europe-at-war", "europe-at-war-arc-01", "contest", "Rail timetables become mobilisation plans, and the scheduled world carries armies into a war political leaders cannot quickly stop."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "Repaired transport, trade rules and treaty institutions reconnect western European schedules across former battle lines."],
    ["europe-returns", "europe-returns-arc-02", "reactivate", "Continental rail, road and communications schedules carry commerce, refugees and military support along the eastern route."]
  ],
  "trace-common-protocols": [
    ["europe-at-war", "europe-at-war-arc-01", "contest", "Mobilisation and blockade subordinate cross-border protocols to military command while technical interoperability continues to move armies and messages."],
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "Coal-and-steel rules, treaty administration and court procedure extend protocol logic from technical exchange into governed power."],
    ["europe-returns", "europe-returns-arc-01", "reactivate", "Accession chapters and alliance planning align law, administration and defence through agreed European procedures."]
  ],
  "trace-continent-split-open": [
    ["continent-rebuilt", "continent-rebuilt-arc-01", "transform", "The wartime ruin hardens into two occupation and security orders while western states bind their recovery together."],
    ["europe-returns", "europe-returns-arc-01", "supersede", "The revolutions of 1989 close the imposed division; freely acceding states replace the occupation line before Russian force contests the eastern settlement."]
  ],
  "trace-european-jewry-destroyed": [
    ["continent-rebuilt", "continent-rebuilt-arc-01", "reactivate", "The murdered communities do not return: survivors, empty neighbourhoods and broken family lines remain inside the continent being rebuilt."]
  ],
  "trace-western-legal-order": [
    ["europe-returns", "europe-returns-arc-01", "transform", "Former Soviet-subordinated states enter Union law and NATO through ratified sovereign acts, extending the western legal order east."]
  ],
  "trace-eastern-civic-memory": [
    ["europe-returns", "europe-returns-arc-01", "transform", "The churches, presses and civic networks that preserved national agency supply parties, constitutions and reformers for sovereign accession."]
  ],
  "trace-eastern-return": [],
  "trace-held-eastern-line": []
};

const arcMatrix = read("arc-matrix.json");
const interactionMapping = read("interaction-mapping.json");
const worldModel = read("world-traces.json");
const authoredEffectLedgers = [
  read("authored-interaction-effects-01-12.json"),
  read("authored-interaction-effects-13-24.json")
];

const worldTraceIDs = new Set(worldModel.traces.map(({ traceID }) => traceID));
if (worldTraceIDs.size !== worldModel.traces.length) {
  throw new Error("World trace IDs must be unique before enrichment");
}
if (Object.keys(activationContinuity).length !== worldTraceIDs.size) {
  throw new Error("Every world trace must have exactly one authored activation plan");
}
for (const traceID of Object.keys(activationContinuity)) {
  if (!worldTraceIDs.has(traceID)) throw new Error(`Activation plan references unknown trace ${traceID}`);
}

const chapterByID = new Map(
  arcMatrix.chapters.map((chapter) => [chapter.contentID, chapter])
);
const movementPlacement = new Map();

for (const chapter of arcMatrix.chapters) {
  chapter.arcs.forEach((arc) => {
    arc.movementIDs.forEach((movementID, movementIndex) => {
      movementPlacement.set(`${chapter.contentID}/${movementID}`, {
        arcID: arc.arcID,
        movementIndex
      });
    });
  });
}

// Correct a concrete chronology error: the four-empires rupture begins in the
// 1918 arc, not the later total-dominion arc.
const continentSplit = worldModel.traces.find(
  (trace) => trace.traceID === "trace-continent-split-open"
);
if (!continentSplit) {
  throw new Error("Missing trace-continent-split-open");
}
continentSplit.introducedBy.arcID = "europe-at-war-arc-01";

// Later activations become explicit, addressable state transitions. Their arc
// placement is fixed here; beat placement remains intentionally unassigned
// until scene writing.
function applyActivationContinuity() {
  for (const trace of worldModel.traces) {
    const inheritedTargets = new Set(trace.laterActivations.map((activation) =>
      typeof activation === "string" ? activation : activation.target.contentID
    ));
    const plan = activationContinuity[trace.traceID];
    if (!plan) throw new Error(`Missing authored activation plan for ${trace.traceID}`);
    if (new Set(plan.map(([contentID]) => contentID)).size !== plan.length) {
      throw new Error(`Activation plan repeats a target chapter for ${trace.traceID}`);
    }
    for (const [contentID] of plan) {
      if (!inheritedTargets.has(contentID)) {
        throw new Error(`Activation plan adds an unauthorised target ${trace.traceID}/${contentID}`);
      }
    }
    let currentState = trace.state;
    trace.laterActivations = plan.map(([contentID, arcID, operation, afterState]) => {
      const targetChapter = chapterByID.get(contentID);
      if (!targetChapter) throw new Error(`Unknown activation target ${contentID}`);
      if (!targetChapter.arcs.some((arc) => arc.arcID === arcID)) {
        throw new Error(`Activation arc ${arcID} is outside ${contentID}`);
      }
      const activation = {
        effectID: `effect-${trace.traceID.replace(/^trace-/, "")}-${contentID}`,
        target: {
          contentID,
          arcID,
          beatID: "UNASSIGNED"
        },
        operation,
        beforeState: currentState,
        afterState
      };
      currentState = afterState;
      return activation;
    });
  }
}

const traceByID = new Map(worldModel.traces.map((trace) => [trace.traceID, trace]));
for (const trace of worldModel.traces) {
  trace.arcEffects = [];
  trace.introducedBy = {
    ...trace.introducedBy,
    beatID: "UNASSIGNED",
    effectID: `effect-introduce-${trace.traceID.replace(/^trace-/, "")}`
  };
}

const authoredEffects = authoredEffectLedgers.flatMap((ledger) => ledger.effects ?? []);
const authoredBySourceID = new Map();
for (const effect of authoredEffects) {
  if (authoredBySourceID.has(effect.sourceInteractionID)) {
    throw new Error(`Duplicate authored effect ${effect.sourceInteractionID}`);
  }
  if (!/^interaction-[a-z0-9]+(?:-[a-z0-9]+)*$/.test(effect.nativeInteractionID)) {
    throw new Error(`Invalid authored native interaction ID ${effect.nativeInteractionID}`);
  }
  if (!["prepare", "establish", "transform"].includes(effect.operation)) {
    throw new Error(`Invalid authored operation ${effect.sourceInteractionID}/${effect.operation}`);
  }
  if (typeof effect.beforeState !== "string" || effect.beforeState.length < 60
      || typeof effect.afterState !== "string" || effect.afterState.length < 60) {
    throw new Error(`Authored state is not concrete enough ${effect.sourceInteractionID}`);
  }
  authoredBySourceID.set(effect.sourceInteractionID, effect);
}

const authoredBeatEffects = authoredEffectLedgers.flatMap(
  (ledger) => ledger.beatEffects ?? []
);
const authoredBeatByMovementID = new Map();
for (const effect of authoredBeatEffects) {
  if (authoredBeatByMovementID.has(effect.sourceMovementID)) {
    throw new Error(`Duplicate authored beat effect ${effect.sourceMovementID}`);
  }
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*\/[a-z0-9]+(?:-[a-z0-9]+)*$/.test(effect.sourceMovementID)
      || !/^effect-[a-z0-9]+(?:-[a-z0-9]+)*$/.test(effect.effectID)) {
    throw new Error(`Invalid authored beat effect ID ${effect.sourceMovementID}`);
  }
  if (!movementPlacement.has(effect.sourceMovementID)) {
    throw new Error(`Authored beat effect references unknown movement ${effect.sourceMovementID}`);
  }
  if (!["prepare", "establish", "transform"].includes(effect.operation)) {
    throw new Error(`Invalid authored beat operation ${effect.sourceMovementID}/${effect.operation}`);
  }
  if (typeof effect.beforeState !== "string" || effect.beforeState.length < 60
      || typeof effect.afterState !== "string" || effect.afterState.length < 60) {
    throw new Error(`Authored beat state is not concrete enough ${effect.sourceMovementID}`);
  }
  const trace = traceByID.get(effect.worldTraceID);
  const [contentID] = effect.sourceMovementID.split("/");
  if (!trace || trace.introducedBy.contentID !== contentID) {
    throw new Error(`Authored beat trace must originate in the same chapter ${effect.sourceMovementID}`);
  }
  authoredBeatByMovementID.set(effect.sourceMovementID, effect);
}

const authoredPromotions = authoredEffectLedgers.flatMap(
  (ledger) => ledger.requiredMappingPromotions ?? []
);
const promotionBySourceID = new Map();
for (const promotion of authoredPromotions) {
  if (promotionBySourceID.has(promotion.sourceInteractionID)) {
    throw new Error(`Duplicate mapping promotion ${promotion.sourceInteractionID}`);
  }
  if (!authoredBySourceID.has(promotion.sourceInteractionID)) {
    throw new Error(`Mapping promotion has no authored effect ${promotion.sourceInteractionID}`);
  }
  if (promotion.fromDisposition !== "MERGE"
      || !["KEEP", "REWRITE"].includes(promotion.toDisposition)
      || promotion.nativeRole !== "principal") {
    throw new Error(`Invalid mapping promotion ${promotion.sourceInteractionID}`);
  }
  promotionBySourceID.set(promotion.sourceInteractionID, promotion);
}

const sourceItems = interactionMapping.items.map((item) => {
  const {
    arcID: ignoredArcID,
    beatID: ignoredBeatID,
    movementIndex: ignoredMovementIndex,
    nativeInteractionID: ignoredNativeID,
    nativeRole: ignoredRole,
    mergeGroupID: ignoredMergeGroup,
    mergeTargetNativeInteractionID: ignoredMergeTarget,
    worldTraceID: ignoredTraceID,
    worldEffectID: ignoredEffectID,
    ...source
  } = item;
  return source;
});

const itemsByArc = new Map();
for (const item of sourceItems) {
  const placement = movementPlacement.get(`${item.chapterID}/${item.movementID}`);
  if (!placement) throw new Error(`Movement has no arc: ${item.sourceInteractionID}`);
  const list = itemsByArc.get(placement.arcID) ?? [];
  list.push({ item, placement });
  itemsByArc.set(placement.arcID, list);
}

const beatEffectsByArc = new Map();
for (const effect of authoredBeatEffects) {
  const placement = movementPlacement.get(effect.sourceMovementID);
  const list = beatEffectsByArc.get(placement.arcID) ?? [];
  list.push({ effect, placement });
  beatEffectsByArc.set(placement.arcID, list);
}

const enrichedItems = [];
for (const chapter of arcMatrix.chapters) {
  chapter.arcs.forEach((arc) => {
    const entries = (itemsByArc.get(arc.arcID) ?? [])
      .sort((a, b) => a.placement.movementIndex - b.placement.movementIndex);
    const principals = entries.filter(({ item }) => authoredBySourceID.has(item.sourceInteractionID));
    if (principals.length < 1 || principals.length > 3) {
      throw new Error(`${arc.arcID} has ${principals.length} principal interactions`);
    }

    const principalByMovement = new Map();
    for (const { item, placement } of principals) {
      const nativeInteractionID = `interaction-${item.chapterID}-${item.movementID}`;
      const worldEffectID = `effect-${nativeInteractionID.replace(/^interaction-/, "")}`;
      const authored = authoredBySourceID.get(item.sourceInteractionID);
      if (authored.nativeInteractionID !== nativeInteractionID) {
        throw new Error(`Authored native ID mismatch ${item.sourceInteractionID}`);
      }
      const trace = traceByID.get(authored.worldTraceID);
      if (!trace || trace.introducedBy.contentID !== chapter.contentID) {
        throw new Error(`Authored trace must originate in the same chapter ${item.sourceInteractionID}`);
      }
      principalByMovement.set(item.movementID, {
        nativeInteractionID,
        worldEffectID,
        worldTraceID: trace.traceID
      });
    }

    const authoredArcEffects = [
      ...principals.map(({ item, placement }) => {
        const ids = principalByMovement.get(item.movementID);
        return {
          movementIndex: placement.movementIndex,
          effectID: ids.worldEffectID,
          worldTraceID: ids.worldTraceID,
          nativeInteractionID: ids.nativeInteractionID,
          sourceMovementID: `${item.chapterID}/${item.movementID}`,
          authored: authoredBySourceID.get(item.sourceInteractionID)
        };
      }),
      ...(beatEffectsByArc.get(arc.arcID) ?? []).map(({ effect, placement }) => ({
        movementIndex: placement.movementIndex,
        effectID: effect.effectID,
        worldTraceID: effect.worldTraceID,
        sourceMovementID: effect.sourceMovementID,
        authored: effect
      }))
    ].sort((left, right) => left.movementIndex - right.movementIndex);

    for (const authoredEffect of authoredArcEffects) {
      const trace = traceByID.get(authoredEffect.worldTraceID);
      if (!trace || trace.introducedBy.contentID !== chapter.contentID) {
        throw new Error(`Authored trace must originate in the same chapter ${authoredEffect.sourceMovementID}`);
      }
      trace.arcEffects.push({
        effectID: authoredEffect.effectID,
        contentID: chapter.contentID,
        arcID: arc.arcID,
        beatID: "UNASSIGNED",
        ...(authoredEffect.nativeInteractionID
          ? { nativeInteractionID: authoredEffect.nativeInteractionID }
          : { sourceMovementID: authoredEffect.sourceMovementID }),
        operation: authoredEffect.authored.operation,
        beforeState: authoredEffect.authored.beforeState,
        afterState: authoredEffect.authored.afterState
      });
    }

    for (const { item, placement } of entries) {
      const nativeInteractionID = `interaction-${item.chapterID}-${item.movementID}`;
      const isPrincipal = authoredBySourceID.has(item.sourceInteractionID);
      const promotion = promotionBySourceID.get(item.sourceInteractionID);
      const effectiveDisposition = promotion?.toDisposition ?? item.disposition;
      if (promotion
          && item.disposition !== promotion.fromDisposition
          && item.disposition !== promotion.toDisposition) {
        throw new Error(`Mapping promotion source disposition drifted ${item.sourceInteractionID}`);
      }
      if (!isPrincipal && effectiveDisposition !== "MERGE") {
        throw new Error(`Principal interaction lacks authored consequence ${item.sourceInteractionID}`);
      }
      let nativeRole = isPrincipal ? "principal" : "supporting";
      let mergeGroupID;
      let mergeTargetNativeInteractionID;
      let worldEffectID;
      let worldTraceID;

      if (!isPrincipal) {
        const target = [...principals].sort((left, right) => {
          const distance = Math.abs(left.placement.movementIndex - placement.movementIndex)
            - Math.abs(right.placement.movementIndex - placement.movementIndex);
          return distance || left.placement.movementIndex - right.placement.movementIndex;
        })[0];
        const targetIDs = principalByMovement.get(target.item.movementID);
        mergeTargetNativeInteractionID = targetIDs.nativeInteractionID;
        mergeGroupID = `merge-group-${targetIDs.nativeInteractionID.replace(/^interaction-/, "")}`;
        worldEffectID = targetIDs.worldEffectID;
        worldTraceID = targetIDs.worldTraceID;
      } else {
        const principalIDs = principalByMovement.get(item.movementID);
        worldEffectID = principalIDs.worldEffectID;
        worldTraceID = principalIDs.worldTraceID;
      }

      enrichedItems.push({
        ...item,
        disposition: effectiveDisposition,
        arcID: arc.arcID,
        beatID: "UNASSIGNED",
        movementIndex: placement.movementIndex,
        nativeInteractionID,
        nativeRole,
        ...(mergeGroupID ? { mergeGroupID, mergeTargetNativeInteractionID } : {}),
        worldTraceID,
        worldEffectID
      });
    }

    arc.principalNativeInteractionIDs = principals.map(({ item }) =>
      `interaction-${item.chapterID}-${item.movementID}`
    );
    arc.supportingSourceInteractionIDs = entries
      .filter(({ item }) => !authoredBySourceID.has(item.sourceInteractionID))
      .map(({ item }) => item.sourceInteractionID);
    arc.worldTraceIDs = [...new Set(authoredArcEffects.map(({ worldTraceID }) => worldTraceID))];
    arc.worldEffectIDs = authoredArcEffects.map(({ effectID }) => effectID);
  });
}

const sourceInteractionIDs = new Set(sourceItems.map(({ sourceInteractionID }) => sourceInteractionID));
const interactiveMovementIDs = new Set(
  sourceItems.map(({ chapterID, movementID }) => `${chapterID}/${movementID}`)
);
for (const sourceInteractionID of authoredBySourceID.keys()) {
  if (!sourceInteractionIDs.has(sourceInteractionID)) {
    throw new Error(`Authored effect references unknown source interaction ${sourceInteractionID}`);
  }
}
for (const effect of authoredBeatEffects) {
  if (interactiveMovementIDs.has(effect.sourceMovementID)) {
    throw new Error(`Authored beat effect must use a non-interactive movement ${effect.sourceMovementID}`);
  }
}
const allAuthoredEffectIDs = [
  ...authoredEffects.map(({ nativeInteractionID }) =>
    `effect-${nativeInteractionID.replace(/^interaction-/, "")}`
  ),
  ...authoredBeatEffects.map(({ effectID }) => effectID)
];
if (new Set(allAuthoredEffectIDs).size !== allAuthoredEffectIDs.length) {
  throw new Error("Authored interaction and beat effect IDs must be globally unique");
}
for (const item of sourceItems) {
  const effectiveDisposition = promotionBySourceID.get(item.sourceInteractionID)?.toDisposition
    ?? item.disposition;
  if (effectiveDisposition !== "MERGE" && !authoredBySourceID.has(item.sourceInteractionID)) {
    throw new Error(`Principal interaction lacks authored consequence ${item.sourceInteractionID}`);
  }
}

// Every persistent trace is now established by a concrete principal action.
// Effects are a strict chronological state chain and end at the trace state
// consumed by its later activation plan. No synthetic UNASSIGNED effect exists.
for (const trace of worldModel.traces) {
  if (!trace.arcEffects.length) throw new Error(`Trace has no authored principal effect ${trace.traceID}`);
  const establishment = trace.arcEffects.filter(({ operation }) => operation === "establish");
  if (establishment.length !== 1 || establishment[0].arcID !== trace.introducedBy.arcID) {
    throw new Error(`Trace requires one establishment in its origin arc ${trace.traceID}`);
  }
  let established = false;
  let previousAfter;
  for (const effect of trace.arcEffects) {
    if (previousAfter !== undefined && effect.beforeState !== previousAfter) {
      throw new Error(`Broken authored effect state chain ${effect.effectID}`);
    }
    if (effect.operation === "prepare" && established) {
      throw new Error(`Prepare effect follows establishment ${effect.effectID}`);
    }
    if (effect.operation === "establish") {
      if (established) throw new Error(`Trace established twice ${trace.traceID}`);
      established = true;
    }
    if (effect.operation === "transform" && !established) {
      throw new Error(`Transform precedes establishment ${effect.effectID}`);
    }
    previousAfter = effect.afterState;
  }
  trace.state = previousAfter;
  trace.introducedBy.effectID = establishment[0].effectID;
}

// The final authored consequence is the canonical visible trace state. Build
// later continuity only after those endpoints have been installed so the
// first later activation can never retain a stale heuristic before-state.
applyActivationContinuity();

interactionMapping.schemaVersion = 2;
interactionMapping.items = enrichedItems;
interactionMapping.counts = {
  interactions: enrichedItems.length,
  principalNativeInteractions: enrichedItems.filter(({ nativeRole }) => nativeRole === "principal").length,
  supportingMergedInteractions: enrichedItems.filter(({ nativeRole }) => nativeRole === "supporting").length,
  mergeGroups: new Set(enrichedItems.map(({ mergeGroupID }) => mergeGroupID).filter(Boolean)).size,
  arcsCovered: new Set(enrichedItems.map(({ arcID }) => arcID)).size,
  byGrammar: countBy(enrichedItems.map(({ nativeGrammar }) => nativeGrammar)),
  byDisposition: countBy(enrichedItems.map(({ disposition }) => disposition)),
  byRole: countBy(enrichedItems.map(({ nativeRole }) => nativeRole))
};

arcMatrix.schemaVersion = 2;
arcMatrix.interactionCounts = {
  principalNativeInteractions: interactionMapping.counts.principalNativeInteractions,
  supportingMergedInteractions: interactionMapping.counts.supportingMergedInteractions,
  arcsPassingPrincipalRule: arcMatrix.chapters
    .flatMap(({ arcs }) => arcs)
    .filter(({ principalNativeInteractionIDs }) =>
      principalNativeInteractionIDs.length >= 1 && principalNativeInteractionIDs.length <= 3
    ).length
};

const activations = worldModel.traces.flatMap(({ laterActivations }) => laterActivations);
worldModel.schemaVersion = 2;
worldModel.counts = {
  ...worldModel.counts,
  arcEffects: worldModel.traces.reduce((sum, trace) => sum + trace.arcEffects.length, 0),
  laterActivations: activations.length,
  byActivationOperation: countBy(activations.map(({ operation }) => operation))
};

write("interaction-mapping.json", interactionMapping);
write("arc-matrix.json", arcMatrix);
write("world-traces.json", worldModel);

console.log(
  `${checkOnly ? "Verified" : "Enriched"} ${enrichedItems.length} source interactions, `
  + `${interactionMapping.counts.principalNativeInteractions} principal interactions, `
  + `${authoredBeatEffects.length} non-interactive beat effects, `
  + `${worldModel.counts.arcEffects} arc effects and ${activations.length} later activations.`
);
