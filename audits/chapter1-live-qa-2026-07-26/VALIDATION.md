# Chapter 1: målbildestatus og iPhone-risiko

Dato: 26. juli 2026

## Beslutning

Chapter 1 kan nå bygges og åpnes gjennom en representativ, Release-optimalisert
ARM64-rute med de virkelige responsive lydprogrammene. Størrelsen er innenfor
produktbudsjettet, og den ordinære Release-appen er fortsatt ren.

Kapittelet er ikke godkjent som ferdig iPhone-opplevelse. Siste komplette
UI-kjøring står på `42/46`. De to lifecycle-feilene passerer i en senere
fokusert `2/2`-kjøring, mens de to cursor-feilene fortsatt reproduseres;
`46/46` er ikke kjørt på nytt. Batteri, varme, fysisk minne,
hard-kill-gjenoppretting og frame pacing er heller ikke målt på den fysiske
testtelefonen.

## Status mot målbildet

| Område | Nå | Evidens | Åpen port |
| --- | --- | --- | --- |
| Kapittelruntime | Delvis pass; integrert port rød | Alle 17 beats åpner gjennom signert produksjonsrute. Seks interaksjoner og seks ekte responsive lydprogrammer er projisert. Lifecycle-restore passerer fokusert `2/2`. En rask Trace-kø kan fortsatt utløse cursor-writerens 250 ms fail-close. | Flytt den aktive cursorbeskyttelsen ut av MainActor, lukk de to cursor-feilene og kjør hele UI-porten på nytt. |
| Representativ live-app | Pass for bygg og simulator | ARM64 `NON_SHIPPING_LIVE_TEST` bygger med `-O`, whole-module optimization og uten testability. Ren simulatorinstallasjon åpner direkte på Three Records uten integritetsfeil. | Signering, installasjon og måling på test-iPhone. |
| Lokal regressjon | Blandet | SwiftPM `806/806`, tooling `235/235`, native scripts `83/83`, fixture `2/2`, A Continent Remade `1/1` og Thread Sanitizer `194/194` passerer. Siste komplette UI-kjøring er `42/46`; en senere lifecycle-kjøring er `2/2`, og de to cursor-testene feiler fortsatt. | Full UI-port må bli grønn. Lokal evidens erstatter fortsatt ikke fysisk port. |
| Redaksjonelt innhold | Delvis | Kapittelkontrakt og 17-beat-struktur finnes. Registeret har 9 `PASS`, 1 `NARROW`, 1 `REMOVE` og 4 `EDITOR_DECISION`. | Fire avgjørelser og endelig editor-gate. |
| Visuell produksjon | Blokkert | Sceneprojeksjoner og tekniske lag finnes. Harvest-underlagene ble visuelt avvist selv om tallportene bestod. Longhouse A5/A6 ble prøvd ved 390 punkter og avvist; A4 står fortsatt som komposisjonsbase. | `778/778` produksjonsassetkrav mangler fortsatt shippingassets. |
| Lyd | Teknisk representativ, kunstnerisk åpen | 91 WAV-arbeidsfiler er kodet til 90 AAC-LC + 1 ALAC og brukes i live-fixturen. | Lydmaster- og kunstnergodkjenning. |
| Narrasjon | Blokkert | Manusprojeksjonen har 37 kanoniske cue-ID-er, men live-fixturen har 0 narrasjonshendelser. Det finnes ingen narrasjonskontroller, brukerflate eller timelinebinding i appen. | V12 forbyr syntese før redaktørbeslutning. Deretter kreves 37 masterfiler, runtimebinding, gjensidig utestenging mot responsiv lyd og restore-bevis. |
| Shippingpakke | Ikke bygget | Den signerte live-fixturen er reproduserbar og eksplisitt `PROHIBITED`. | Godkjent `essential-free-v1`, produksjonstillit og forseglet arkiv. |
| Apple-tjenester | Delvis | StoreKit-, restore-, kø-, integritets- og rollback-logikk er testet mot lokal autoritet. | Ekte produkt, hosted packs, CloudKit og APNs. |
| Fysisk iPhone | Ikke testet | Protokoll, skjema og validator er låst. | `Basta 16` er utilgjengelig; Developer Mode og testprofiler gjenstår. |

## Faktisk størrelse

- Shipping-lik ARM64 Release-app uten coverage-instrumentering: `17 383 246`
  byte, 33 filer og ingen M4A-fixturer.
- Representativ ARM64 live-app: `155 677 766` byte, 266 filer og 93 M4A-filer.
- Den signerte fixturen alene: `138 253 495` byte og 232 fysiske filer,
  inkludert manifestet.
- Fixturemanifest: 231 bundne payloadfiler, `manifestDigest`
  `589ea9be981a4bd6b8d8569b0ebd6a98ed1c856d8e54d39dc5281d4e9b513f53`.
- De 91 Chapter 1-lydfilene gikk fra `750 820 004` byte PCM til
  `85 479 069` byte M4A. Reduksjonen er `88,615 %`.
- Det beholdte live-bygget inneholder `137` PNG-filer på til sammen
  `50 462 685` byte. Fem Harvest-teksturer er `1290 × 2796`; resten av den
  tekniske Chapter 1-ruten er i hovedsak `393 × 852`.
- Live-appen avvises med hensikt av Release-skanneren fordi den inneholder
  `NON_SHIPPING`-autoritet. Ordinær Release passerer samme grense.

Disse er de siste bevarte `iphoneos`-målingene. `JourneyModel.swift`,
`ProductionChapterRoute.swift` og cursor-pumpen er endret etter byggene, så en
ny signert måling må bindes til den eksakte kildeversjonen før fysisk port.

Målbudsjettet er 100 MB for skall og motor, 750 MB for de tre inkluderte
gratiskapitlene og 850 MB for hele base-appen. Dagens måling viser at Chapter 1
kan passe inn i den modellen. Narrasjon og endelige bilder mangler, så
`essential-free-v1` kan ennå ikke størrelsesgodkjennes.

De 37 narrasjonssegmentene tilsvarer omtrent 9,6 minutter. En framtidig mono
AAC-LC-kandidat vil anslagsvis legge til 7–9 MB. Det endrer ikke
størrelsesbildet vesentlig, men ingen slik kandidat finnes eller er autorisert
nå.

Installert størrelse gir ikke løpende batteritap. Den påvirker nedlasting,
lagring og førstegangsverifisering. Renderer, lyddekoding, minnepress og
diskaktivitet under bruk avgjør energiforbruket.

## Energi og minne

Det som allerede begrenser forbruk:

- Metal-visningen er pauset når scenen står stille. Den går i 60 fps bare
  under den `220` millisekunder lange snap-back-responsen og stopper selv når
  tidslinjen er ferdig.
- Teksturresidens begrenses til aktiv komposisjon; tidligere scener beholdes
  ikke i GPU-cachen.
- Store assets hashes ved første bruk og gjenbruker verifisert cache.
- Appen laster ett lydprogram om gangen, ikke alle 91 lydfiler samtidig.
- Live-fixturen inneholder `137` PNG-filer på `50 462 685` byte. Kompositoren
  beholder bare teksturene for aktiv komposisjon; de fem største
  Harvest-teksturene er `1290 × 2796`.
- Ingen av fixturens 40 lydtidslinjer har kontinuerlige timeline-haptics.
- `NON_SHIPPING_LIVE_TEST` oppretter ingen framtidig-release-klient og har
  derfor ingen nedlastings- eller CloudKit-arbeid i målerunden.

De største åpne risikoene er konkrete:

- Three Records er beregnet til `97 920 000` byte dekodet lyd i steady state
  og `115 200 000` byte under overgang. Dette er under porten, men ikke en
  fysisk footprint-måling.
- Crash-cursoren kan skrive og `fsync` hvert 125. millisekund for å holde
  hard-kill-avviket under 250 millisekunder. En aktiv 30-minutters økt kan
  utløse opptil `14 400` filbarrierer. Dette er den tydeligste I/O- og
  batteririsikoen.
- Under rask Trace-input får den ustrukturerte cursor-writeren ikke alltid
  MainActor-tid før watchdog-fristen. Den stopper korrekt etter omtrent
  250–262 millisekunder, men gjør den integrerte appporten rød. Å senke fristen
  eller legge inn flere writes ville skjule problemet og er ikke godkjent.
- Simulatoren kan bekrefte integritet og flyt, men ikke iPhone-termikk,
  energiforbruk eller reelt minnetrykk.
- First Farmers-evidensvalidatoren krever nå ti parvise, hashbundne
  `audio-restoration`-runder. Kontrollert pause må treffe eksakt sample, og
  hard-kill-avvik over `12 000` samples ved 48 kHz avvises.
- Narrasjon må senere prewarme bare aktivt beats 2–5 filer og aldri spille
  samtidig med det responsive lydprogrammet. Da legges den ikke oppå dagens
  dekodede lydtopp. Denne bindingen er ennå ikke implementert.

Den fysiske porten krever tre parede 30-minutters kapittel-/referanserunder,
vedvarende fysisk minne under 500 MiB, termisk tilstand `nominal` eller `fair`,
høyst 8 prosentpoeng absolutt batterifall og høyst 3 prosentpoeng mer enn den
statiske referansen.

Målerunden skal i tillegg isolere årsaken dersom porten feiler: full Chapter 1
med tyngste lydprogram, samme forløp uten lyd og en Instruments-runde med
Energy Log/File Activity rundt crash-cursoren. Produksjonsintervallet endres
ikke før den målingen viser at `fsync` faktisk er utslagsgivende og en lengre
periode fortsatt kan holde hard-kill-avviket under 250 millisekunder.
En framtidig narrasjonscursor skal heller ikke journalføres hvert 125.
millisekund; eksplisitte pauser kan lagres direkte, mens hard-kill-gjenopptak
må få en egen avgrenset sidecar før shipping.

## Hvor langt kapittelet er kommet

Dette er modenhetsanslag, ikke arbeidstidsregnskap:

- teknisk live-testløype for Chapter 1: omtrent `85–90 %`; den integrerte
  cursor-/lifecycle-porten, fysisk signering og målerunden gjenstår;
- generell native motor og arkitektur: omtrent `80 %` lokalt;
- Chapter 1 som ferdig kunstnerisk og shippingklar opplevelse: omtrent
  `20–30 %`; produksjonsbilder, narrasjon, godkjenninger og fysisk bevis er de
  store gjenværende delene;
- hele 24-kapitlers App Store-målbildet: omtrent `15–20 %`.

## Neste avgjørende port

1. Flytt aktiv cursor-capture og den fysiske 250 ms lydporten ut av MainActor
   uten ekstra writes. Lifecycle-restore er allerede grønn i fokusert `2/2`.
2. Kjør hele den integrerte UI-porten på nytt; `46/46` er inngangskravet til
   den fysiske runden.
3. Koble til og lås opp `Basta 16`, slå på Developer Mode og opprett de to
   isolerte live-testprofilene.
4. Kjør den representative live-appen gjennom den låste fysiske protokollen.
5. Bruk målingen til å beholde eller endre 125 ms-kravet. Ikke gjett på
   batterikostnaden.
6. Fortsett produksjonsbildene uten å promotere avviste Harvest- eller
   Longhouse-kandidater. Narrasjon forblir stengt til V12-redaktørvalget er
   tatt; deretter bygges 37-cue lyd og runtimebinding samlet.

## Evidens

- `native/quality/physical-device-protocol.json`
- `native/phase2/runtime-fixture/compiled/vertical-slice-development-v1.runtimefixture/package-manifest.json`
- `native/audio/score-soundscape/distribution-coding-v1/render-receipt.json`
- `native/ios/Sources/JourneyPersistence/ResponsiveAudioCursorCheckpointPump.swift`
- `native/ios/Sources/ProgressStore/ResponsiveAudioCursorCheckpointStore.swift`
- `native/ios/qa/thread-sanitizer-focused-2026-07-26.receipt.json`
- `native/content/backstage/harvest/destination-underlays-v26.r2.visual-rejection.json`
- `native/design/phase1/longhouse/refinement-review-a5-a6.json`
