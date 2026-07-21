import type { ChapterDefinition } from "../../types/chapter";

const imageRoot = "assets/chapters/europe-returns";

export const europeReturns: ChapterDefinition = {
  slug: "europe-returns",
  number: "24",
  title: "Europe Returns",
  openingTitleLines: ["Europe", "Returns"],
  period: "AD 1989–20 July 2026",
  claim:
    "The nations freed in 1989 returned to Europe through two distinct institutions: European Union law and markets, and NATO collective defence. Russia answered that settlement with force, and Europe learned again that an open order endures only where sovereign choice can be defended.",
  openingClaim:
    "Europe carried freedom east through accession law, common markets and collective defence. From Georgia in 2008 to Ukraine after 2014, Russian force made the eastern line the test of whether those institutions could also hold.",
  hero: {
    image: `${imageRoot}/opening-the-eastern-line.avif`,
    mobileImage: `${imageRoot}/opening-the-eastern-line-mobile.avif`,
    imageAlt:
      "A midnight institutional atlas follows separate cobalt European Union legal and ice-blue NATO defence lines from the opened Brandenburg Gate through Warsaw and Tallinn toward Tbilisi and Kyiv.",
    imagePosition: "center center",
    mobileImagePosition: "62% center",
    visualLabel: "The Eastern Line · dated institutional atlas",
  },
  theme: {
    id: "eastern-line",
    label: "The Eastern Line",
  },
  openingAction: "Carry the line east",
  mapLabel:
    "The separate legal, economic and defensive routes by which free European states joined the European Union and NATO—and the frontier on which Russia tried to reverse their choice",
  routeImage: "assets/europe-relief.webp",
  openingRouteImage: "assets/europe-relief.webp",
  sourcesEyebrow:
    "Restoration acts · accession dossiers · alliance treaties · monitoring maps · ceasefire texts · United Nations resolutions · support ledgers · summit declarations",
  acts: [
    {
      id: "return-made-by-choice",
      number: "I",
      label: "The return is made by choice",
      period: "AD 1989–2004",
      title: "The Return Is Made by Choice",
      detail:
        "Restored states choose constitutional government, European Union accession and NATO protection; institutions move east by application, negotiation and consent.",
    },
    {
      id: "russia-tests-settlement",
      number: "II",
      label: "Russia tests the settlement",
      period: "AD 2008–2014",
      title: "Russia Tests the Settlement",
      detail:
        "War in Georgia, pressure on Ukraine and the seizure of Crimea reveal a Russian state prepared to reverse its neighbours’ sovereign choices by force.",
    },
    {
      id: "war-returns",
      number: "III",
      label: "War returns to Europe",
      period: "AD 2015–2024",
      title: "War Returns to Europe",
      detail:
        "The unfinished war in the Donbas becomes a full-scale invasion; Ukraine’s resistance and Europe’s institutional answer transform the continent’s security.",
    },
    {
      id: "europe-holds-line",
      number: "IV",
      label: "Europe learns to hold the line",
      period: "AD 2024–20 July 2026",
      title: "Europe Learns to Hold the Line",
      detail:
        "Accession work, sustained finance, defence industry and a strengthened eastern flank convert solidarity into the capacity to endure.",
    },
  ],
  ending: {
    period: "As of 20 July 2026",
    title: "The Line Is Open Because It Is Held",
    detail:
      "At first light, the railway and fibre corridor still runs east. European Union milestones remain cobalt pages of law, market access, budget and reform. NATO nodes remain ice-blue commitments of collective defence, planning and allied force. Ukraine is not yet a member of the Union and is not covered by Article 5. It remains a sovereign European state in accession negotiations, sustained by institutions and nations that have chosen to make distance, winter and attrition bearable. Behind the illuminated line lies an inheritance accumulated across centuries: the city that governed itself, the law that outlived rulers, the experiment that made nature answer, the company that gathered capital, the nation that survived conquest and the alliance that made defence a common promise. Europe returned when its nations were free to choose. It will endure where that choice can be defended.",
    image: `${imageRoot}/ending-the-line-is-open-because-it-is-held.avif`,
    mobileImage: `${imageRoot}/ending-the-line-is-open-because-it-is-held-mobile.avif`,
  },
  returnHash: "europe-returns",
  movements: [
    {
      id: "the-states-return-to-the-map",
      actId: "return-made-by-choice",
      order: 1,
      period: "AD 1989–1991",
      place: "Warsaw, Tallinn, Riga and Vilnius",
      title: "The States Return to the Map",
      thesis:
        "The eastern nations emerged from communist rule not as blank territories but as political communities recovering the right to govern themselves.",
      body: [
        "In June 1989, Polish voters used the space permitted by a negotiated election to break the communist monopoly. Across the two voting rounds, Solidarity candidates won all 161 freely contestable seats in the Sejm and ninety-nine of the hundred seats in the restored Senate. A government led by a Solidarity adviser followed. Hungary opened its border and proclaimed a republic; Czechoslovakia’s civic revolution carried Václav Havel from prison and theatre into the presidency. The states that had been treated as a Soviet glacis recovered voices of their own, and each voice spoke first in the grammar of national law.",
        "Farther north, that recovery reached beneath the post-war map. Estonia, Latvia and Lithuania had possessed republics before their annexation by the Soviet Union in 1940. Their diplomats, legal claims and civic memory had survived occupation. The Baltic Way of August 1989 joined roughly two million people in a human chain across the three countries. Lithuania declared the restoration of independence in March 1990; Estonia and Latvia completed their restorations as Soviet power failed in August 1991. Old flags rose above parliaments because the public act was a return of sovereignty, not the invention of states from administrative provinces.",
        "The first work of freedom was exact and practical. Legislatures rewrote constitutions, restored property and citizenship rules, created central banks, opened archives and submitted governments to elections whose outcomes could remove them. Diplomats sought recognition; border guards took responsibility for national frontiers; municipalities learned to act without instructions from a party hierarchy. Economic dislocation was severe, and institutions could not be recovered by ceremony alone. The direction had become unmistakable. Nations once assigned to an empire by force now asked to enter European institutions by choice, carrying their own names, languages and constitutional claims with them.",
      ],
      image: `${imageRoot}/01-the-states-return-to-the-map.avif`,
      mobileImage: `${imageRoot}/01-the-states-return-to-the-map-mobile.avif`,
      imageAlt:
        "A dated atlas joins Poland’s June 1989 ballot, the Baltic Way, restored Baltic state seals and the diplomatic routes of renewed independence.",
      imagePosition: "54% center",
      mobileImagePosition: "61% center",
      visualLabel:
        "1989–1991 · ballot, human chain, restoration act, recognition",
      visualTone: "restored-sovereignty",
      side: "left",
      sourceIds: ["spohr-2020", "lieven-baltic-1993", "eu-history"],
      evidence: [
        "Poland’s 1989 election, negotiated before it was fought, produced an overwhelming Solidarity victory and the first non-communist-led government in the Soviet bloc.",
        "The Baltic republics framed independence as legal restoration after the Soviet annexation of 1940, and international recognition followed the failed Moscow coup of August 1991.",
      ],
      map: { x: 61, y: 27 },
    },
    {
      id: "copenhagen-writes-the-doorway",
      actId: "return-made-by-choice",
      order: 2,
      period: "AD 1993",
      place: "Copenhagen and Brussels",
      title: "Copenhagen Writes the Doorway",
      thesis:
        "The European Union turned the promise of reunion into published conditions that candidate states could translate into national reform.",
      body: [
        "When the European Council met at Copenhagen in June 1993, the eastern candidates needed terms of entry. The Council declared that associated countries in central and eastern Europe could become members, then placed the doorway on paper. A candidate needed stable democratic institutions, the rule of law, respect for rights, a functioning market economy and the capacity to accept the obligations of membership. The Union also had to be able to absorb new members. Enlargement ceased to be a sentiment and became a reciprocal undertaking with standards visible before admission.",
        "Those lines reached deep into the candidate state. Ministries compared national statutes with the acquis communautaire; parliaments enacted competition, customs, environmental and commercial law; judges and civil servants learned procedures that would continue after the accession ceremony. Privatised economies required regulators and enforceable contracts. Elections required durable administrations rather than a single heroic ballot. The work was unglamorous because its object was permanence. A country entered not by declaring itself European, but by making thousands of public decisions legible to citizens, firms, courts and the other members of the Union.",
        "Conditionality could be demanding because the reward was substantial. Membership promised access to a vast common market, structural funds, free movement and a place in institutions where rules were negotiated rather than received from an imperial centre. Candidate governments chose to accept constraints because those constraints came with representation and law. The eastward line therefore advanced through folders, translations, inspection missions and votes. No army carried it. Europe’s old frontier of force was being replaced by an architecture in which a sovereign state applied, reformed, negotiated and finally consented to the treaty that admitted it.",
      ],
      image: `${imageRoot}/02-copenhagen-writes-the-doorway.avif`,
      imageAlt:
        "The 1993 Copenhagen criteria open into four cobalt-lit stations: a polling register, a court docket, a competition office and a customs declaration.",
      imagePosition: "51% center",
      visualLabel: "Accession dossier · criteria become public institutions",
      visualTone: "accession-paper",
      side: "right",
      sourceIds: ["copenhagen-conclusions-1993", "grabbe-2006"],
      evidence: [
        "The June 1993 Copenhagen conclusions established political and economic conditions and the capacity to assume membership obligations as the basis for eastward enlargement.",
        "The accession process used screening, monitoring and adoption of the acquis to connect membership to concrete legal and administrative change.",
      ],
      map: { x: 48, y: 28 },
      interaction: {
        kind: "chapter-v2",
        family: "record",
        variant: "open-accession-dossier",
        prompt: "Open the accession dossier",
        accessibleSummary:
          "Four dossier states turn the Copenhagen promise into criteria, screening, negotiated legal chapters and an accession treaty ratified by the candidate and existing members.",
        initialId: "write-criteria",
        records: [
          {
            id: "write-criteria",
            label: "Write the doorway",
            period: "Copenhagen · June AD 1993",
            kicker: "The promise acquires conditions",
            detail:
              "The European Council states in advance what a candidate must build and preserve before it can enter the Union.",
            fields: [
              {
                label: "Political",
                value: "Democracy, rule of law and rights",
              },
              { label: "Economic", value: "A functioning market economy" },
              { label: "Legal", value: "Capacity to assume EU obligations" },
            ],
            outcome:
              "Membership becomes a route governed by published standards rather than geopolitical favour.",
          },
          {
            id: "screen-the-law",
            label: "Screen the law",
            period: "Candidate capital and Brussels",
            kicker: "Every field enters comparison",
            detail:
              "Officials compare national law with the Union’s acquis and record where legislation, administration and enforcement must change.",
            fields: [
              { label: "Instrument", value: "Analytical screening" },
              { label: "Material", value: "National law and EU acquis" },
              { label: "Result", value: "A dated reform programme" },
            ],
            outcome:
              "A broad civilisational return becomes a sequence of work that a parliament and ministry can complete.",
          },
          {
            id: "negotiate-chapters",
            label: "Negotiate the chapters",
            period: "Accession conference",
            kicker: "Progress must be demonstrated",
            detail:
              "Negotiating positions, benchmarks and monitoring reports test whether enacted rules can operate in courts, offices and markets.",
            fields: [
              { label: "Forum", value: "Candidate and all member states" },
              { label: "Test", value: "Alignment and implementation" },
              { label: "Control", value: "Unanimous opening and closure" },
            ],
            outcome:
              "Consent remains national and collective at every decisive stage.",
          },
          {
            id: "ratify-accession",
            label: "Ratify accession",
            period: "Candidate and member states",
            kicker: "The doorway becomes treaty",
            detail:
              "The accession treaty fixes terms and enters force only after ratification under the constitutional rules of every signatory.",
            fields: [
              {
                label: "Candidate act",
                value: "Signature and national consent",
              },
              { label: "Union act", value: "Ratification by every member" },
              { label: "New status", value: "Member state under common law" },
            ],
            outcome:
              "The line moves east by law through the entrant’s decision and the existing Union’s consent.",
          },
        ],
      },
    },
    {
      id: "article-five-moves-east",
      actId: "return-made-by-choice",
      order: 3,
      period: "AD 1997–1999",
      place: "Madrid, Washington, Prague, Warsaw and Budapest",
      title: "Article Five Moves East",
      thesis:
        "Poland, Czechia and Hungary entered a security alliance of their choosing, placing national defence inside a transatlantic promise.",
      body: [
        "The European Union’s doorway did not answer the oldest eastern security question: whether allies would come if armies crossed the frontier. Poland, Czechia and Hungary sought entry into the North Atlantic Treaty Organization because the memory of Munich, invasion, occupation and abandonment remained close. At Madrid in 1997, the allies invited the three states to begin accession talks. Their governments then negotiated military, legal and security requirements, secured national approval and deposited instruments of accession in March 1999. The act was sovereign, but the protection it sought was deliberately common.",
        "NATO was not another name for European integration. It was a defensive alliance founded on the North Atlantic Treaty and anchored by American power. Its Article 5 treated an armed attack on one ally as an attack on all, while leaving each state to take the action it deemed necessary. New members entered defence planning, command arrangements, exercises and the long practical labour of making forces able to operate together. Civilian control, secure communications, logistics and standards mattered because a treaty promise becomes credible only when governments and armed forces have prepared to honour it.",
        "The first enlargement beyond the former inner-German line reversed the logic of the Soviet glacis. Warsaw, Prague and Budapest would no longer have alliances assigned to them by a stronger neighbour. They selected partners, ratified obligations and took seats at the common table. The United States remained indispensable to the guarantee; European allies supplied geography, forces and political consent. Together they extended a zone in which no member’s defence began at its own border alone. The EU route would carry law and market east. This second route carried warning, planning and the promise that conquest would meet an alliance.",
      ],
      image: `${imageRoot}/03-article-five-moves-east.avif`,
      imageAlt:
        "Accession instruments for Poland, Czechia and Hungary lie beside a civilian defence committee table, interoperable radio plan and a sharply bounded Article 5 map.",
      imagePosition: "58% center",
      visualLabel: "1999 accession instruments · a separate security road",
      visualTone: "alliance-ice",
      side: "left",
      sourceIds: ["nato-madrid-1997", "nato-treaty-1949", "asmus-2002"],
      evidence: [
        "The Madrid Summit invited Czechia, Hungary and Poland in July 1997; their accessions became effective on 12 March 1999.",
        "NATO enlargement extended Article 5, integrated planning and interoperability obligations, not membership in the European Union or its legal order.",
      ],
      map: { x: 58, y: 30 },
    },
    {
      id: "the-great-enlargement-rejoins-the-continent",
      actId: "return-made-by-choice",
      order: 4,
      period: "AD 2004",
      place: "Brussels and the capitals of central and eastern Europe",
      title: "The Great Enlargement Rejoins the Continent",
      thesis:
        "In 2004 the Union and alliance each crossed the old divide through separate treaties, reconnecting most of central Europe and the Baltic to the institutions of the West.",
      body: [
        "Two accession tables stood open in 2004. On 29 March, Bulgaria, Estonia, Latvia, Lithuania, Romania, Slovakia and Slovenia joined NATO. Their flags entered an alliance of twenty-six, and defence plans moved to the Baltic and Black Sea regions. On 1 May, Cyprus, Czechia, Estonia, Hungary, Latvia, Lithuania, Malta, Poland, Slovakia and Slovenia joined the European Union. Eight had lived under communist rule. Their citizens and firms entered a common legal and economic space after years of screening, negotiation, treaty ratification and national preparation.",
        "The lists overlapped, but they were not identical. Czechia, Hungary and Poland had entered NATO five years before they entered the Union. Bulgaria and Romania entered NATO in 2004 but would wait until 2007 for EU membership. Cyprus and Malta joined the EU without joining the alliance. One institution offered treaty-based collective defence; the other shared legislation, courts, budget, market and representation. The distinction was not a bureaucratic nicety. It defined what each state could expect in danger, what obligations it had accepted and which table possessed authority to act.",
        "Across central Europe, accession altered the scale of ordinary life. Customs posts disappeared inside the Union; investment followed enforceable rules; infrastructure funds rebuilt roads, railways, water systems and town centres; students and workers crossed borders that had once required political permission. NATO staffs joined exercises and revised reinforcement plans. National politics remained vigorous and prosperity remained uneven, while the recovered states gained a permanent share in institutions they had chosen. Two eastward circuits of consent replaced much of the post-1945 line across Europe.",
      ],
      image: `${imageRoot}/04-the-great-enlargement-rejoins-the-continent.avif`,
      mobileImage: `${imageRoot}/04-the-great-enlargement-rejoins-the-continent-mobile.avif`,
      imageAlt:
        "Two precisely separated 2004 accession tables show seven NATO entrants and ten European Union entrants, linked to distinct ice-blue defence and cobalt legal circuits.",
      imagePosition: "50% center",
      mobileImagePosition: "50% center",
      visualLabel: "2004 · two institutions, two treaties, exact memberships",
      visualTone: "paired-accession",
      side: "right",
      sourceIds: ["eu-enlargement-2004", "nato-enlargement"],
      evidence: [
        "Seven states joined NATO on 29 March 2004; ten states joined the European Union on 1 May 2004, including eight former communist countries.",
        "The different entrant lists demonstrate that NATO collective defence and European Union membership remained legally separate despite a shared eastward direction.",
      ],
      map: { x: 67, y: 27 },
    },
    {
      id: "russia-crosses-into-georgia",
      actId: "russia-tests-settlement",
      order: 5,
      period: "August AD 2008",
      place: "Tskhinvali, Gori and Tbilisi",
      title: "Russia Crosses into Georgia",
      thesis:
        "The five-day war showed that Russia would use overwhelming force and permanent military presence to limit a neighbour’s freedom of action.",
      body: [
        "The new European settlement reached the Caucasus as aspiration before it reached it as protection. Georgia had left the Soviet Union with unresolved conflicts in South Ossetia and Abkhazia, where separatist authorities, Russian peacekeepers, local armed groups and displaced populations inhabited a dangerous arrangement. Tension rose through the summer of 2008. On the night of 7 August, Georgian forces attacked Tskhinvali after exchanges of fire. Russia answered by sending large formations through the Roki Tunnel and opening operations by land, air and sea. A local conflict became an interstate war in hours.",
        "Russian forces did not stop after driving Georgian troops from South Ossetia. They crossed deeper into Georgia, occupied Gori and other positions beyond the disputed regions, struck military and transport targets and opened a second front from Abkhazia. French diplomacy on behalf of the European Union produced a six-point agreement on 12 August. Russian forces later withdrew from some areas, but Moscow recognised South Ossetia and Abkhazia as independent and established a lasting military presence there. The EU Monitoring Mission deployed in October; it could patrol Georgian-controlled territory but was denied access to the two regions.",
        "The warning lay in the outcome. Georgia was not protected by Article 5 and held no EU membership guarantee. Its assault on Tskhinvali gave Moscow the opening; Russia used that error to impose a far larger and lasting territorial fact. Russian forces remained where the recognised Georgian government could not return, protected by Moscow’s recognition and military presence. Europe mediated the halt and monitored the line. It did not reverse the territorial result. From 2008, the eastern question was no longer whether Russia disliked the post-1989 order. It was how far Moscow would go to break a neighbour’s choice.",
      ],
      image: `${imageRoot}/05-russia-crosses-into-georgia.avif`,
      mobileImage: `${imageRoot}/05-russia-crosses-into-georgia-mobile.avif`,
      imageAlt:
        "An iron-red Russian advance cuts across a midnight map of Georgia toward Gori beside the six-point ceasefire route and the monitoring boundary.",
      imagePosition: "57% center",
      mobileImagePosition: "63% center",
      visualLabel: "Georgia · dated ceasefire document and monitoring boundary",
      visualTone: "iron-warning",
      side: "left",
      sourceIds: [
        "tagliavini-georgia-2009",
        "eumm-georgia-history",
        "echr-georgia-russia-ii-2021",
      ],
      evidence: [
        "The independent fact-finding mission identified the Georgian assault on Tskhinvali as the beginning of large-scale hostilities while also documenting Russia’s subsequent military operations far beyond South Ossetia.",
        "The EU-mediated agreement halted the fighting, but Russian forces remained in South Ossetia and Abkhazia; EUMM has had no access to either region.",
      ],
      map: { x: 82, y: 45 },
    },
    {
      id: "ukraine-chooses-the-european-square",
      actId: "russia-tests-settlement",
      order: 6,
      period: "November AD 2013–February AD 2014",
      place: "Kyiv",
      title: "Ukraine Chooses the European Square",
      thesis:
        "The Maidan transformed an association agreement into a public claim that Ukraine’s constitutional direction belonged to its citizens.",
      body: [
        "Ukraine’s European choice first arrived as hundreds of pages of association law. The negotiated agreement with the European Union promised political association and a deep and comprehensive free-trade area, requiring changes in competition, procurement, customs and regulation. In November 2013, President Viktor Yanukovych’s government suspended preparations to sign it after intense pressure from Moscow. Students gathered on Kyiv’s Independence Square beneath European and Ukrainian flags. When riot police beat protesters on the night of 30 November, a dispute over an agreement became a larger revolt against arbitrary government.",
        "The square acquired kitchens, medical posts, stages, chapels and self-defence groups. People arrived from many regions, bringing different languages and political histories into a common demand for accountable government. Winter, intimidation and new restrictions failed to clear the centre. In February, violence killed protesters and police. European ministers helped negotiate an agreement for constitutional change and early elections, but authority collapsed as Yanukovych left Kyiv. Parliament declared that he had withdrawn from performing his constitutional duties and scheduled a presidential election. Ukraine would settle the transfer through ballot and law rather than accept the direction chosen in Moscow.",
        "Maidan did not make Ukraine European; it revealed how many Ukrainians understood the state they already possessed. The Union offered no automatic membership and no military shield. Its association agreement was powerful because it attached trade to a different practice of government: published rules, reviewable decisions and institutions capable of surviving an officeholder. In the square, that legal route became visible as national independence. Citizens had defended the proposition that a Ukrainian government could not dispose of the country’s alignment against their will. Russia now faced a neighbour whose political centre had openly rejected a subordinate place in Moscow’s order.",
      ],
      image: `${imageRoot}/06-ukraine-chooses-the-european-square.avif`,
      imageAlt:
        "A winter civic square in Kyiv glows amber beside the European association route, a parliamentary vote and a dated election marker.",
      imagePosition: "52% center",
      visualLabel: "Kyiv 2013–2014 · agreement, square, parliament, election",
      visualTone: "civic-amber",
      side: "right",
      sourceIds: [
        "eu-ukraine-association-2014",
        "wilson-ukraine-crisis-2014",
        "osce-ukraine-election-2014",
      ],
      evidence: [
        "The government’s suspension of preparations for the EU association agreement in November 2013 initiated protests that widened after police violence against demonstrators.",
        "After Yanukovych left Kyiv, the Verkhovna Rada scheduled an early presidential election that international observers assessed as genuine and largely in line with international commitments.",
      ],
      map: { x: 73, y: 37 },
    },
    {
      id: "russia-seizes-crimea-and-opens-the-donbas-war",
      actId: "russia-tests-settlement",
      order: 7,
      period: "February–September AD 2014",
      place: "Crimea, Donetsk and Luhansk",
      title: "Russia Seizes Crimea and Opens the Donbas War",
      thesis:
        "Russia answered Ukraine’s political turn by taking territory, annexing Crimea and sustaining an armed conflict inside the Ukrainian east.",
      body: [
        "Armed men without national insignia appeared around Crimean airports, government buildings and Ukrainian bases in late February 2014. They were Russian forces. Under their control, local authorities organised a referendum in March that offered no option to retain the existing constitutional settlement and took place during occupation. Moscow annexed the peninsula. The United Nations General Assembly affirmed Ukraine’s territorial integrity and declared that the vote could not alter Crimea’s status. A European frontier had been changed by military seizure for the first time since the post-Cold War order began.",
        "The next operation was less uniform and more prolonged. Armed groups seized buildings in Donetsk, Luhansk and other eastern cities. Ukraine recovered some centres but faced formations supplied, directed and reinforced from Russia, joined by local militants and Russian citizens. In July, Malaysia Airlines flight MH17 was destroyed over separatist-held territory by a Buk missile system brought from the Russian Federation. In August, regular Russian units intervened at decisive points as Ukrainian forces approached the separatist centres. A ceasefire signed at Minsk in September stopped neither the fighting nor Russia’s leverage.",
        "Crimea and the Donbas war used different instruments toward the same end. In Crimea, Russia revealed its soldiers only after they had secured the peninsula. In the Donbas, Moscow combined deniability, weapons, personnel, political direction and direct intervention to prevent Kyiv from restoring control. Sanctions imposed costs, monitors recorded violations and negotiators sought terms, yet occupied ground gave Russia a continuing hold on Ukraine’s future. Georgia had established the method’s first warning. Ukraine demonstrated its larger purpose: a neighbour moving toward European law would be forced to carry an open territorial wound.",
      ],
      image: `${imageRoot}/07-russia-seizes-crimea-and-opens-the-donbas-war.avif`,
      mobileImage: `${imageRoot}/07-russia-seizes-crimea-and-opens-the-donbas-war-mobile.avif`,
      imageAlt:
        "A static atlas sets the date of United Nations Resolution 68/262, the seizure of Crimea and the 2014 Donbas monitoring line against the warning from Georgia in 2008.",
      imagePosition: "58% center",
      mobileImagePosition: "56% center",
      visualLabel: "2008 · 2014 · 2022 warnings held against official records",
      visualTone: "evidence-atlas",
      side: "left",
      sourceIds: [
        "unga-68-262",
        "ohchr-ukraine-reports",
        "freedman-ukraine-strategy-2019",
      ],
      evidence: [
        "United Nations General Assembly Resolution 68/262 affirmed Ukraine’s territorial integrity and stated that the March 2014 Crimean referendum had no validity.",
        "United Nations and OSCE reporting documented the armed conflict in eastern Ukraine, while subsequent investigations established the movement of Russian personnel and weapons across the border.",
      ],
      map: { x: 76, y: 42 },
      interaction: {
        kind: "chapter-v2",
        family: "atlas",
        variant: "read-three-warnings",
        prompt: "Read the warnings",
        accessibleSummary:
          "Three dated atlas records compare Russian action in Georgia in 2008, Crimea and the Donbas in 2014, and the full-scale invasion of Ukraine in 2022 against official agreements and United Nations resolutions.",
        initialId: "georgia-2008",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "georgia-2008",
            label: "Georgia",
            period: "August AD 2008",
            kicker: "Force outruns the conflict zone",
            detail:
              "Russian formations enter through South Ossetia, operate deeper inside Georgia and remain after an EU-mediated agreement behind the boundaries of two breakaway regions.",
            fields: [
              { label: "Record", value: "Six-point agreement · 12 August" },
              { label: "European instrument", value: "EU mediation and EUMM" },
              { label: "Result", value: "Russian military presence remains" },
            ],
            outcome:
              "A neighbour’s western direction meets a territorial fact imposed by Russian force.",
            points: [
              {
                id: "tbilisi",
                label: "Tbilisi",
                detail:
                  "The sovereign capital remains outside alliance protection.",
                x: 82,
                y: 45,
              },
              {
                id: "gori",
                label: "Gori",
                detail: "Russian forces move beyond the disputed region.",
                x: 81,
                y: 44,
              },
              {
                id: "tskhinvali",
                label: "Tskhinvali",
                detail: "The conflict expands into interstate war.",
                x: 81,
                y: 43,
              },
            ],
            links: [
              [2, 1],
              [1, 0],
            ],
          },
          {
            id: "ukraine-2014",
            label: "Ukraine",
            period: "February–September AD 2014",
            kicker: "Annexation and deniable war",
            detail:
              "Russian forces seize Crimea while personnel, weapons and political direction sustain armed territorial seizure in the Donbas.",
            fields: [
              { label: "Record", value: "UNGA Resolution 68/262" },
              {
                label: "European instrument",
                value: "Sanctions and OSCE monitoring",
              },
              {
                label: "Result",
                value: "Crimea annexed; Donbas war remains open",
              },
            ],
            outcome:
              "A second attack shows that Georgia was not an isolated exception.",
            points: [
              {
                id: "kyiv",
                label: "Kyiv",
                detail:
                  "Ukraine’s government retains constitutional continuity.",
                x: 73,
                y: 37,
              },
              {
                id: "crimea",
                label: "Crimea",
                detail: "Russia occupies and annexes the peninsula.",
                x: 76,
                y: 44,
              },
              {
                id: "donbas",
                label: "Donbas",
                detail: "Armed seizure opens a long war in the east.",
                x: 78,
                y: 39,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
            ],
          },
          {
            id: "ukraine-2022",
            label: "Full-scale invasion",
            period: "24 February AD 2022",
            kicker: "The state itself becomes the target",
            detail:
              "Russia attacks from north, east and south while the United Nations identifies the act as aggression against Ukraine.",
            fields: [
              { label: "Record", value: "UNGA Resolution ES-11/1" },
              {
                label: "European instrument",
                value: "Support, sanctions and refuge",
              },
              {
                label: "Result",
                value: "Ukraine survives and continues to choose",
              },
            ],
            outcome:
              "The three warnings resolve into one strategic fact: the eastern line must be held as well as declared.",
            points: [
              {
                id: "kyiv",
                label: "Kyiv",
                detail: "The capital refuses to fall.",
                x: 73,
                y: 37,
              },
              {
                id: "belarus-border",
                label: "Northern axis",
                detail: "Russian columns attack toward the capital.",
                x: 73,
                y: 32,
              },
              {
                id: "eastern-axis",
                label: "Eastern axis",
                detail: "The existing war expands across a national front.",
                x: 79,
                y: 39,
              },
              {
                id: "southern-axis",
                label: "Southern axis",
                detail: "Forces advance from occupied Crimea.",
                x: 76,
                y: 44,
              },
            ],
            links: [
              [1, 0],
              [2, 0],
              [3, 0],
            ],
          },
        ],
      },
    },
    {
      id: "the-ceasefire-conceals-an-unfinished-war",
      actId: "war-returns",
      order: 8,
      period: "AD 2015–2021",
      place: "Minsk and the Donbas contact line",
      title: "The Ceasefire Conceals an Unfinished War",
      thesis:
        "The Minsk process regulated violence without restoring Ukrainian sovereignty, leaving Russia time and leverage behind a line inside Ukraine.",
      body: [
        "After severe fighting at Debaltseve, the leaders of Germany and France joined Ukraine and Russia in negotiating a renewed package at Minsk in February 2015. The text required a ceasefire, withdrawal of heavy weapons, OSCE monitoring, exchanges of detainees, political provisions and eventual restoration of Ukrainian control over its international border. The United Nations Security Council endorsed the package. On paper, military and political steps formed a route out of war. On the ground, their sequence became a field of dispute and their conditions were never completed.",
        "The contact line nevertheless acquired institutions. OSCE monitors travelled patrol routes, operated cameras, recorded explosions and published daily reports. Crossing points allowed civilians to reach pensions, relatives, homes and markets through a militarised landscape. Ceasefires lowered violence for periods and then eroded. People lived beside trenches while separatist authorities, Russian passports, command structures, finance and supply drew occupied areas closer to Moscow. The line remained wholly inside internationally recognised Ukraine; monitoring could describe what occurred around it but could not restore control of the border through which Russia sustained the conflict.",
        "Europe invested in diplomacy because containing violence mattered. Management preserved the wound instead of healing it. The unresolved war narrowed Ukraine’s resources, tested its politics and gave Moscow a permanent means of pressure while Russia denied being a party in the form demanded by its role. By 2021, large Russian formations gathered around Ukraine. Minsk had shown Europe’s capacity for negotiation, observation and sanctions, and exposed the limit of paper where one signatory preferred an unfinished conflict to a sovereign neighbour. The quiet line concealed preparation for an assault intended to settle the question on a far greater scale.",
      ],
      image: `${imageRoot}/08-the-ceasefire-conceals-an-unfinished-war.avif`,
      imageAlt:
        "The Minsk ceasefire line lies across a restrained monitoring map, a daily patrol ledger and the amber route of a civilian crossing point.",
      imagePosition: "56% center",
      visualLabel:
        "2015–2021 · agreement, monitor, crossing point, unresolved border",
      visualTone: "ceasefire-grey",
      side: "right",
      sourceIds: [
        "minsk-package-2015",
        "osce-smm-ukraine",
        "ohchr-ukraine-reports",
      ],
      evidence: [
        "The 2015 Package of Measures combined security and political obligations but was never fully implemented, and Ukraine did not recover control of the affected international border.",
        "OSCE monitoring documented repeated ceasefire violations and restrictions on observation until the mission ended after the full-scale invasion in 2022.",
      ],
      map: { x: 77, y: 39 },
    },
    {
      id: "kyiv-refuses-to-fall",
      actId: "war-returns",
      order: 9,
      period: "24 February–April AD 2022",
      place: "Kyiv, Bucha and the northern approaches",
      title: "Kyiv Refuses to Fall",
      thesis:
        "Russia’s full-scale invasion failed at its first political objective because Ukraine preserved its capital, government and national will.",
      body: [
        "Before dawn on 24 February 2022, Russian missiles struck across Ukraine and ground forces attacked from north, east and south. Columns descending from Belarus aimed at Kyiv while airborne troops tried to seize Hostomel airport and open a bridge to the capital. Moscow presented the sovereign Ukrainian state as an error that could be corrected by force. The United Nations General Assembly named the act as aggression and demanded Russia’s immediate, complete and unconditional withdrawal. The legal language was exact because the event was exact: one member state had launched a war to break another’s political independence.",
        "The capital remained at work. The government stayed in Kyiv; parliament continued to meet; rail workers evacuated civilians and brought supplies; local defence joined regular formations while Ukrainian units fought for the airport, roads, bridges and towns on the approaches. Russian planning had counted on paralysis, rapid decapitation and a public unwilling to defend the state. It encountered an army transformed since 2014, institutions that did not dissolve and citizens who understood the invasion as an attack on their right to decide. By early April, Russian forces had withdrawn from Kyiv, Chernihiv and Sumy regions.",
        "Liberated towns revealed the nature of occupation. At Bucha and elsewhere, investigators documented civilians killed during the Russian presence, including victims found with hands bound, as well as unlawful confinement, torture and disappearances. The evidence entered United Nations reports, criminal investigations and a public record that could not be dissolved into the language of competing claims. Kyiv’s survival did not end the war; Russia redirected its main effort east and south. It ensured that Ukraine possessed a government able to fight, negotiate and receive support in its own name. The European question had changed from whether the state would survive to whether its partners could sustain the distance.",
      ],
      image: `${imageRoot}/09-kyiv-refuses-to-fall.avif`,
      mobileImage: `${imageRoot}/09-kyiv-refuses-to-fall-mobile.avif`,
      imageAlt:
        "A static February 2022 map places Russian invasion axes around an illuminated Kyiv government district and a restrained evidence ledger.",
      imagePosition: "55% center",
      mobileImagePosition: "61% center",
      visualLabel:
        "24 February–April 2022 · invasion axis, capital, withdrawal, record",
      visualTone: "capital-held",
      side: "left",
      sourceIds: [
        "unga-es11-1",
        "ohchr-northern-ukraine-2022",
        "freedman-ukraine-strategy-2019",
      ],
      evidence: [
        "United Nations General Assembly Resolution ES-11/1 deplored Russia’s aggression against Ukraine and demanded the withdrawal of Russian forces.",
        "OHCHR documented killings of civilians in areas of Kyiv, Chernihiv and Sumy regions occupied by Russian forces, including unlawful killings in Bucha.",
      ],
      map: { x: 73, y: 37 },
    },
    {
      id: "the-invasion-enlarges-european-resolve",
      actId: "war-returns",
      order: 10,
      period: "AD 2022–2024",
      place: "Brussels, Kyiv, Helsinki and Stockholm",
      title: "The Invasion Enlarges European Resolve",
      thesis:
        "Ukraine’s resistance activated different European instruments at once: Union candidacy and support for Ukraine, allied arms and training, and NATO membership for Finland and Sweden.",
      body: [
        "The first European answer crossed borders in trains, bank transfers, sanctions regulations and open doors. European Union members granted temporary protection to millions of Ukrainians, financed the Ukrainian state, connected its electricity grid, sustained trade corridors and imposed successive restrictions on Russia. In June 2022, the European Council granted Ukraine candidate status. The decision did not confer membership. It opened a demanding legal route through reform, screening and unanimous decisions, declaring that a country defending its sovereignty could also work toward a permanent place inside the Union.",
        "The military route remained separate. NATO did not extend Article 5 to Ukraine, and the alliance as an institution did not become a belligerent. Individual allies supplied weapons, ammunition and training through bilateral and coordinated arrangements; NATO improved interoperability, planning and long-term assistance. The distinction protected the boundary of collective defence while allowing members to help Ukraine resist. It also made the strategic fact visible: support could be extensive without pretending that a partner possessed the treaty guarantee reserved for an ally.",
        "Two states drew a different conclusion for themselves. Finland, with its long Russian frontier and tradition of military non-alignment, applied to join NATO alongside Sweden in May 2022. Finland deposited its instrument of accession on 4 April 2023; Sweden followed on 7 March 2024, bringing the alliance to thirty-two members. Russia had launched war while demanding a narrower field for sovereign alignment. It produced a stronger northern flank, a longer NATO border and a Ukrainian candidacy that tied national survival to institutional reform. The eastern line had widened because free states chose to strengthen it.",
      ],
      image: `${imageRoot}/10-the-invasion-enlarges-european-resolve.avif`,
      mobileImage: `${imageRoot}/10-the-invasion-enlarges-european-resolve-mobile.avif`,
      imageAlt:
        "Three documentary planes remain visibly separate: the European Council’s Ukraine candidate decision, a European rail and grid support corridor, and Finnish and Swedish NATO accession instruments.",
      imagePosition: "50% center",
      mobileImagePosition: "48% center",
      visualLabel:
        "2022–2024 · Union candidate, supported partner, two new allies",
      visualTone: "separate-circuits",
      side: "right",
      sourceIds: [
        "eu-ukraine-candidate-2022",
        "nato-member-countries-2026",
        "nato-ukraine-relations-2026",
      ],
      evidence: [
        "The European Council granted Ukraine candidate status on 23 June 2022, beginning a Union accession path rather than conferring membership.",
        "Finland joined NATO on 4 April 2023 and Sweden on 7 March 2024; as of 20 July 2026, Ukraine remained a NATO partner outside Article 5.",
      ],
      map: { x: 68, y: 29 },
      interaction: {
        kind: "chapter-v2",
        family: "network",
        variant: "hold-the-eastern-line",
        prompt: "Hold the Eastern Line",
        accessibleSummary:
          "Four network states distinguish European Union law and market access, NATO collective defence, Ukraine’s non-member partnership and candidate status, and the lawful support links that connect them without erasing institutional boundaries.",
        initialId: "union-route",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "union-route",
            label: "Carry Union law",
            period: "European Union circuit",
            kicker: "Membership is negotiated through the acquis",
            detail:
              "The cobalt route links member capitals through common law, market, budget and representation; a candidate can approach it only through accession stages.",
            fields: [
              { label: "Authority", value: "EU treaties and institutions" },
              {
                label: "Member guarantee",
                value: "Rights and obligations under Union law",
              },
              {
                label: "Ukraine · 20 July 2026",
                value: "Candidate in negotiations",
              },
            ],
            outcome:
              "The line reaches Kyiv as a dossier under active negotiation, not as completed membership.",
            points: [
              {
                id: "brussels-eu",
                label: "European Union · Brussels",
                detail:
                  "The accession process is governed here by member consent and Union law.",
                x: 48,
                y: 31,
              },
              {
                id: "warsaw-eu",
                label: "Warsaw · EU member",
                detail:
                  "A 2004 member carries market, budget and legal links east.",
                x: 61,
                y: 31,
              },
              {
                id: "tallinn-eu",
                label: "Tallinn · EU member",
                detail: "Union law reaches a restored Baltic republic.",
                x: 65,
                y: 22,
              },
              {
                id: "kyiv-candidate",
                label: "Kyiv · candidate",
                detail: "Negotiations are open; membership is not complete.",
                x: 73,
                y: 37,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [1, 3],
            ],
          },
          {
            id: "alliance-route",
            label: "Lock collective defence",
            period: "NATO circuit",
            kicker: "Article 5 belongs to allies",
            detail:
              "The ice-blue route joins treaty members through integrated plans, exercises, reinforcement and an American-backed defence guarantee.",
            fields: [
              { label: "Authority", value: "North Atlantic Treaty" },
              {
                label: "Member guarantee",
                value: "Article 5 collective defence",
              },
              {
                label: "Ukraine · 20 July 2026",
                value: "Partner, not ally",
              },
            ],
            outcome:
              "The defence boundary encloses Warsaw, Tallinn, Helsinki and Stockholm but does not falsely enclose Kyiv or Tbilisi.",
            points: [
              {
                id: "brussels-nato",
                label: "NATO · Brussels",
                detail:
                  "Allied defence planning begins at a separate headquarters.",
                x: 48,
                y: 31,
              },
              {
                id: "warsaw-nato",
                label: "Warsaw · ally",
                detail: "Poland entered Article 5 in 1999.",
                x: 61,
                y: 31,
              },
              {
                id: "tallinn-nato",
                label: "Tallinn · ally",
                detail: "Estonia entered Article 5 in 2004.",
                x: 65,
                y: 22,
              },
              {
                id: "helsinki-nato",
                label: "Helsinki · ally",
                detail: "Finland entered Article 5 in 2023.",
                x: 64,
                y: 19,
              },
              {
                id: "stockholm-nato",
                label: "Stockholm · ally",
                detail: "Sweden entered Article 5 in 2024.",
                x: 60,
                y: 20,
              },
            ],
            links: [
              [0, 1],
              [1, 2],
              [2, 3],
              [3, 4],
            ],
          },
          {
            id: "ukraine-status",
            label: "Read Ukraine’s status",
            period: "Status · 20 July AD 2026",
            kicker: "Connected without false membership",
            detail:
              "Ukraine holds a sovereign position between the two circuits: accession negotiations with the Union and deep partnership with the alliance, but membership in neither.",
            fields: [
              {
                label: "European Union",
                value: "Candidate; Clusters 1 and 6 open",
              },
              { label: "NATO", value: "Partner outside Article 5" },
              {
                label: "Sovereign right",
                value: "Chooses its own institutional future",
              },
            ],
            outcome:
              "Legal status, not colour or proximity, determines which promise can be made.",
            points: [
              {
                id: "kyiv",
                label: "Kyiv",
                detail: "A candidate and partner defending a sovereign choice.",
                x: 73,
                y: 37,
              },
              {
                id: "brussels-eu",
                label: "EU accession table",
                detail: "Two of six negotiating clusters are open.",
                x: 48,
                y: 30,
              },
              {
                id: "brussels-nato",
                label: "NATO partnership table",
                detail: "Support and interoperability do not confer Article 5.",
                x: 49,
                y: 32,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
            ],
          },
          {
            id: "support-links",
            label: "Connect lawful support",
            period: "AD 2022–20 July 2026",
            kicker: "Institutions act through different powers",
            detail:
              "Union finance, energy, trade and accession instruments meet national and allied military assistance without pretending that one organisation possesses the powers of the other.",
            fields: [
              {
                label: "EU route",
                value: "Budget, law, market, grid and refuge",
              },
              {
                label: "Allied route",
                value: "Equipment, training and military planning",
              },
              { label: "Destination", value: "A sovereign Ukrainian state" },
            ],
            outcome:
              "The eastern line holds because exact institutions contribute exact capacities to the same national survival.",
            points: [
              {
                id: "brussels",
                label: "Brussels",
                detail: "Separate councils authorise different instruments.",
                x: 48,
                y: 31,
              },
              {
                id: "rzeszow",
                label: "Rzeszów corridor",
                detail: "National and allied logistics move military support.",
                x: 63,
                y: 34,
              },
              {
                id: "solidarity-lanes",
                label: "Solidarity Lanes",
                detail: "EU transport routes sustain trade and supply.",
                x: 67,
                y: 36,
              },
              {
                id: "kyiv",
                label: "Kyiv",
                detail: "The supported state retains command and choice.",
                x: 73,
                y: 37,
              },
            ],
            links: [
              [0, 1],
              [0, 2],
              [1, 3],
              [2, 3],
            ],
          },
        ],
      },
    },
    {
      id: "accession-becomes-working-law",
      actId: "europe-holds-line",
      order: 11,
      period: "June AD 2024–20 July AD 2026",
      place: "Brussels, Luxembourg and Kyiv",
      title: "Accession Becomes Working Law",
      thesis:
        "Ukraine’s European future moved from declaration into a dated legal process, while support became budget, administration, energy and transport measured over years.",
      body: [
        "The European Union formally opened accession negotiations with Ukraine on 25 June 2024. Screening had already begun to compare Ukrainian law with the acquis, and the negotiating framework fixed the principles under which the work would proceed. War did not suspend the requirement for courts, public administration, financial control, procurement and democratic institutions. It made them more necessary. A state directing mobilisation and reconstruction while seeking membership had to show that emergency power could coexist with reform and that European support could enter accountable systems.",
        "On 15 June 2026, the accession conference opened Cluster 1, the Fundamentals. It covers the functioning of democratic institutions, public administration, economic criteria and five negotiating chapters: public procurement; judiciary and fundamental rights; justice, freedom and security; statistics; and financial control. On 14 July, Cluster 6 opened external relations, including trade and foreign, security and defence policy. As of 20 July 2026, two of six clusters were open. The other four were not. Progress remained merit-based, benchmarked and subject to the consent of the member states.",
        "The legal route travelled beside a material one. The Commission’s ledger dated 15 July placed total European Union support to Ukraine since the beginning of Russia’s war of aggression at €216.7 billion. The total included sums made available for economic, social and financial resilience, military assistance by the Union and member states, support for Ukrainians in the EU, the Ukraine Support Loan and proceeds from immobilised Russian assets; it was not a single cash transfer. Europe’s promise had acquired the durable forms that survive speeches: multi-year finance, procurement, rail corridors, grid connection, administrative benchmarks and work entered against a date.",
      ],
      image: `${imageRoot}/11-accession-becomes-working-law.avif`,
      mobileImage: `${imageRoot}/11-accession-becomes-working-law-mobile.avif`,
      imageAlt:
        "A dated Ukraine accession dossier shows six clusters with only Fundamentals and External Relations opened, beside a separate European Commission support ledger checked on 20 July 2026.",
      imagePosition: "53% center",
      mobileImagePosition: "50% center",
      visualLabel:
        "20 July 2026 · two clusters open · support ledger dated 15 July",
      visualTone: "working-law",
      side: "left",
      sourceIds: [
        "eu-ukraine-accession-2024",
        "eu-ukraine-cluster1-2026",
        "eu-ukraine-cluster6-2026",
        "eu-assistance-ukraine-2026",
      ],
      evidence: [
        "Accession negotiations opened in June 2024; Cluster 1 opened on 15 June 2026 and Cluster 6 on 14 July 2026, leaving four clusters unopened as of 20 July 2026.",
        "The Commission’s €216.7 billion total, updated 15 July 2026, aggregates several instruments and statuses, including amounts made available or committed.",
      ],
      map: { x: 59, y: 34 },
    },
    {
      id: "europe-builds-the-power-to-endure",
      actId: "europe-holds-line",
      order: 12,
      period: "June AD 2025–20 July AD 2026",
      place: "The Hague, Ankara and NATO’s eastern flank",
      title: "Europe Builds the Power to Endure",
      thesis:
        "The final European achievement is organized endurance: resources promised for a decade, forces placed where defence begins and support carried to Ukraine through a working continental system.",
      body: [
        "At The Hague on 25 June 2025, NATO allies accepted a larger measure of what defence required. They committed to invest five per cent of gross domestic product annually by 2035 across two categories: at least 3.5 per cent for core defence requirements and up to 1.5 per cent for security-related capacity such as infrastructure, networks, civil preparedness, resilience, innovation and industry. The percentages were promises to build usable power—forces, stocks, factories, ports, rail, fuel, communications and trained people—on a path reviewed through annual plans and again in 2029.",
        "Geography acquired corresponding structure. NATO listed nine multinational battlegroups on its eastern flank by June 2026, in Bulgaria, Estonia, Finland, Hungary, Latvia, Lithuania, Poland, Romania and Slovakia. Their composition differed, and reinforcement remained essential, but each linked a frontier ally to soldiers and planning from other members before a crisis began. Finland’s new group, led by Sweden as framework nation, completed a chain from the Baltic north to the Black Sea region. The alliance line remained strictly on allied territory; its purpose was to ensure that Russia could not mistake any member’s border for an isolated test.",
        "Ukraine required endurance beyond that border. At Ankara on 8 July 2026, NATO allies pledged €70 billion in military equipment, assistance and training for Ukraine in 2026 and affirmed sovereign commitments to sustain at least equivalent levels in 2027. European allies and Canada financed the large majority of security assistance through bilateral and multilateral means, while Union finance supplied a different multi-year route. The lesson of the eastern line was older than any summit and modern in every instrument: peace depends on institutions able to decide, raise resources, manufacture, move and defend. Europe had recovered the confidence to turn danger into capacity.",
      ],
      image: `${imageRoot}/12-europe-builds-the-power-to-endure.avif`,
      mobileImage: `${imageRoot}/12-europe-builds-the-power-to-endure-mobile.avif`,
      imageAlt:
        "The Hague commitment, nine eastern-flank battlegroup nodes and the Ankara pledge resolve into a dawn logistics corridor of rail crews, engineers and civil planners.",
      imagePosition: "58% center",
      mobileImagePosition: "64% center",
      visualLabel: "2025–20 July 2026 · commitment, flank, industry, corridor",
      visualTone: "dawn-logistics",
      side: "right",
      sourceIds: [
        "nato-hague-2025",
        "nato-eastern-flank-2026",
        "nato-ankara-2026",
      ],
      evidence: [
        "The Hague declaration committed allies to five per cent of GDP annually by 2035, divided between at least 3.5 per cent for core defence and up to 1.5 per cent for wider defence- and security-related investment.",
        "The Ankara declaration recorded allied sovereign pledges of €70 billion for Ukraine in 2026 and at least equivalent support in 2027; NATO listed nine eastern-flank battlegroups as of June 2026.",
      ],
      map: { x: 67, y: 27 },
      interaction: {
        kind: "chapter-v2",
        family: "flow",
        variant: "sustain-the-distance",
        prompt: "Sustain the distance",
        accessibleSummary:
          "Five dated stages follow support from democratic authorization through an industrial order, continental transport, training and accountable Ukrainian receipt, showing organized endurance without depicting combat.",
        initialId: "authorize-years",
        mapImage: "assets/europe-relief.webp",
        records: [
          {
            id: "authorize-years",
            label: "Authorize years",
            period: "National capitals and European institutions",
            kicker: "Endurance begins before the order",
            detail:
              "A parliament, government or common instrument allocates resources under a dated authority and makes the commitment visible beyond one news cycle.",
            fields: [
              { label: "Input", value: "Budget and sovereign decision" },
              { label: "Control", value: "Published authority and audit" },
              { label: "Output", value: "A funded multi-year requirement" },
            ],
            outcome:
              "Political solidarity becomes an order that industry and logistics can plan against.",
            points: [
              {
                id: "the-hague",
                label: "The Hague",
                detail: "Allies set a long investment horizon.",
                x: 47,
                y: 30,
              },
              {
                id: "brussels",
                label: "Brussels",
                detail: "Union and alliance authorities remain separate.",
                x: 48,
                y: 31,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "place-industrial-order",
            label: "Place the industrial order",
            period: "European factory network",
            kicker: "A pledge acquires a production slot",
            detail:
              "Contracts schedule materials, skilled labour, components, maintenance and replenishment across a supply chain able to repeat delivery.",
            fields: [
              { label: "Instrument", value: "Procurement contract" },
              { label: "Constraint", value: "Capacity, components and time" },
              { label: "Output", value: "Inspected equipment and spares" },
            ],
            outcome:
              "The continent’s industrial base turns money into sustained material capacity.",
            points: [
              {
                id: "rheinmetall-corridor",
                label: "Industrial corridor",
                detail: "Production joins components, labour and inspection.",
                x: 51,
                y: 33,
              },
              {
                id: "polish-logistics",
                label: "Polish logistics hub",
                detail:
                  "A completed order enters the eastern transport system.",
                x: 62,
                y: 33,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "cross-the-continent",
            label: "Cross the continent",
            period: "Rail and road corridor",
            kicker: "Distance becomes a timetable",
            detail:
              "Manifests, gauges, border procedures, depots and maintenance windows carry equipment and supplies east without turning the route into spectacle.",
            fields: [
              { label: "Carrier", value: "Rail, road and secured depot" },
              { label: "Record", value: "Manifest and custody transfer" },
              { label: "Output", value: "Delivery at the training network" },
            ],
            outcome:
              "A continent organised by standards can sustain a frontier far from the authorizing capital.",
            points: [
              {
                id: "warsaw",
                label: "Warsaw",
                detail: "The European rail network converges eastward.",
                x: 61,
                y: 31,
              },
              {
                id: "rzeszow",
                label: "Rzeszów",
                detail: "Logistics move toward the Ukrainian border.",
                x: 63,
                y: 34,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "train-and-maintain",
            label: "Train and maintain",
            period: "Allied training network",
            kicker: "Equipment becomes usable capacity",
            detail:
              "Ukrainian personnel train with systems, maintenance plans, spare parts and doctrine before the handover is complete.",
            fields: [
              { label: "Work", value: "Training and maintenance" },
              {
                label: "Continuity",
                value: "Spares, repair and replenishment",
              },
              { label: "Output", value: "A supported Ukrainian capability" },
            ],
            outcome:
              "Support endures because skill and repair travel with the equipment.",
            points: [
              {
                id: "training-site",
                label: "European training site",
                detail:
                  "Ukrainian crews acquire operation and maintenance skill.",
                x: 59,
                y: 32,
              },
              {
                id: "ukraine-border",
                label: "Ukrainian receipt",
                detail: "Custody passes to the sovereign recipient.",
                x: 68,
                y: 36,
              },
            ],
            links: [[0, 1]],
          },
          {
            id: "record-the-receipt",
            label: "Record the receipt",
            period: "Ukraine · accountable delivery",
            kicker: "The chain closes in a sovereign state",
            detail:
              "The recipient records custody, assigns the capability and reports through the controls attached to the authorizing instrument.",
            fields: [
              { label: "Recipient", value: "Ukrainian state authority" },
              { label: "Record", value: "Receipt, inventory and use controls" },
              {
                label: "Return signal",
                value: "Need, repair and replenishment data",
              },
            ],
            outcome:
              "One delivery becomes part of a repeatable continental system rather than an isolated gesture.",
            points: [
              {
                id: "kyiv",
                label: "Kyiv",
                detail: "Ukraine directs support within its own defence.",
                x: 73,
                y: 37,
              },
              {
                id: "brussels",
                label: "Authorizing institutions",
                detail: "Accountability closes the circuit westward.",
                x: 48,
                y: 31,
              },
            ],
            links: [[0, 1]],
          },
        ],
      },
    },
  ],
};
