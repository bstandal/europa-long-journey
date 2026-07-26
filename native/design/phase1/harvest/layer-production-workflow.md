# Harvest layer- og maskekjede

Status: `PROVISIONAL_AUTHORITY_PATH_READY_NO_MASTER_FROZEN`

Kjeden har to adskilte autoritetsdomener. Codex kan fryse én eksplisitt valgt,
bytekontrollert kandidat som
`CODEX_PROVISIONAL_NON_SHIPPING_PRODUCTION_MASTER`. Det åpner bare bygging og
deterministisk reproduksjon av en lokal utviklings-DAG. Det gir ingen
kunstnerisk godkjenning, ingen redaktørgodkjenning og ingen rett til å kopiere
resultatet inn i en offentlig innholdskilde eller release.

En shippingkapabel produksjons-DAG krever fortsatt en separat bytebundet
`EDITOR_APPROVED_AS_PRODUCTION_MASTER`. Den endelige launch-pakken krever i
tillegg redaktørens pakkegodkjenning, som binder hele den offentlige
filinventarhashen og dermed hvert bilde og hver lydfil. En provisional authority
kan ikke konverteres, omdøpes eller gjenbrukes som noen av disse godkjenningene.
Ingen Harvest-kandidat er frosset gjennom denne mekanismen ennå, og de 86
sluttfilene er ikke produsert.

Den maskinlesbare kontrakten er
[`layer-production-contract.json`](./layer-production-contract.json). Den er
bundet med SHA-256 til SceneSpec-fixturen og avleder de 86 reserverte
sluttfilene direkte derfra:

- 12 grunnlag;
- 27 grunnmasker;
- 45 tilstandsbilder og deres masker;
- to selvstendige Reduce Motion-plater.

Kontrakt v2 legger i tillegg inn åtte disokklusjonsunderlag, fire
atmosfærekontroller og én lokal endringsmaske for hver av de tretten
tilstandsvariantene. Underlagene avgrenses til faktisk kamerabane og
tilstandsreveal; de er ikke tomme fullformatsverdener. `mechanism-light`
faller utenfor fordi `screen`-laget ikke trenger et normalblandet underlag.
`hands-and-grain` er eneste unntak: laget har null relativ bevegelse og røper
ingen bakgrunn. Disse filene er produksjonsunderlag og skal ikke inn i den
offentlige innholdspakken.

## Produksjonsrekkefølge

1. Bevar de valgte masterbytene urørt. En separat backup må ha samme
   byteantall og SHA-256 før DAG-en kan bygges.
2. Registrer hvert kildebilde og hver håndforfattede maske med eksakt filhash,
   dimensjon, rettighetsgrunnlag og foreldre.
3. En generert kilde må oppgi promptfil og hash, seed, modell-ID,
   modellsnapshot og SHA-256 for den faktiske vekten. En håndforfattet maske må
   peke på sitt symbolske eller rasterbaserte kildeunderlag med hash.
4. Mål kameraskinnens faktiske disokklusjon før objektene trekkes ut. Hvert
   alfa-separert `normal`-lag skal ha nøyaktig ett underlag eller det eksplisitte
   null-bevegelse/null-reveal-unntaket. `central-harvest` dekker hele
   tilstands- og kamerarevealen; de øvrige underlagene er skinneavgrenset. En
   oppskrift merket `PENDING_MEASUREMENT` kan valideres som arbeidskontrakt,
   men stopper enhver asset-DAG. En ventende oppskrift beholder lagets frame
   som uttrykkelig plassholder. Et målt underlag bruker den normaliserte framen
   som avledes eksakt fra pikselcroppen; `central-harvest` bruker nå den målte
   896 × 896-croppen fra `(192, 1752)`, ikke hele lagframen.
5. Normaliser alfa-, dybde-, lys-, okklusjons- og atmosfæremasker i registrert
   laggeometri. En tom, helhvit eller dimensjonsforskjøvet kontroll avvises;
   dybdemasker må inneholde faktisk variasjon.
6. Hold tapsfrie PNG-mellomfiler gjennom uttrekk, variantkontroll og
   rekomposisjon. Lag som skal leveres som HEIF kodes deretter med den pinnede
   lokale Apple-eksportøren. Ekstern alfa og de øvrige maskene forblir PNG.
7. Sammenlign hver variant mot grunnlaget. Enhver endret piksel utenfor den
   variantens autoriserte endringsmaske stopper bygget. Faktisk alfabounds
   lagres i kvitteringen og må ligge inne i lagets avtalte ramme.
8. Rekomponer alle grunnlag i SceneSpec-rekkefølge mot masteren. Den tapsfrie
   arbeidskomposisjonen skal være pikselidentisk. HEIF-eksporten har en separat
   tapsgrense og må gi samme filhash ved ny kjøring med samme verktøyversjon.
9. Skriv én teknisk kvittering med kilde-DAG, transformhash, filhash,
   maskestatistikk, rekomposisjonsdiff, avviste kandidater og backupstatus.
10. Kjør halo-, anatomi-, historisk, kamerabane-, maskekant-, fargeroms- og
    fysisk enhetskontroll. En provisional kvittering forblir eksplisitt
    `CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_REPRODUCTION_PASS`. Den kan aldri
    brukes av shippingkompilatoren eller release-skanneren.

Automatisk segmentering kan foreslå et maskeutgangspunkt. Den kan ikke lukke
anatomiske kanter, disokklusjon, hår, hender, korn, kurvfletting, regn, røyk
eller historisk materialitet på egen hånd. `autoMasksRequireArtReview` og
`pipelineCannotApproveShipping` er derfor låst til `true`.

## Asset-DAG

En lokal utviklings-DAG får `buildMode`
`CODEX_PROVISIONAL_NON_SHIPPING_DEVELOPMENT` og status
`CODEX_PROVISIONAL_NON_SHIPPING_INPUTS_LOCKED`. En shippingkapabel DAG bruker
`EDITOR_APPROVED_PRODUCTION_MASTER` og `PRODUCTION_INPUTS_LOCKED`. Begge
inneholder:

- nøyaktig kontraktsti og kontrakthash;
- én master-ID som samsvarer med DAG-ens autoritetsdomene;
- kildefiler med rettigheter, opphavsmåte, verktøy, modell/vekt, seed,
  prompt eller symbolsk kilde og foreldrehasher;
- acykliske operasjoner med eksplisitte inputs, registrert frame,
  masketype, verktøy-ID og kanonisk transformhash;
- alle 86 SceneSpec-filer, disokklusjonsunderlag og kontrollmasker uten
  uregistrerte tillegg; underlagskilder registreres som `layer-plate` og
  arbeidsutganger som `working-layer` uten å utvide DAG-skjemaets enum;
- én eksakt `authorization`-maske og bundet maskeoperasjon for hvert målt
  disokklusjonsunderlag; enhver endret piksel utenfor masken stopper bygget;
- lokal endringsmaske for hver state-variant;
- avviste kandidater med eksakte bytes, hash, produksjonstrinn og feilkoder;
- separat, hashverifisert masterbackup;
- rekomposisjons- og diffsti.

Den lukkede filformen ligger i
[`native/schemas/visual-production-dag.schema.json`](../../../schemas/visual-production-dag.schema.json);
den provisional masterautoriteten ligger i
[`native/schemas/visual-production-master-authority.schema.json`](../../../schemas/visual-production-master-authority.schema.json).
Den separate redaktørporten for en shippingkapabel master ligger i
[`native/schemas/visual-production-master-approval.schema.json`](../../../schemas/visual-production-master-approval.schema.json).
runtimevalidatoren kontrollerer i tillegg filbytes, kryssreferanser, sykler,
registrerte verktøy og pikselregler som JSON Schema ikke kan uttrykke.

Kjeden bruker Node.js 26.3.1, FFmpeg 8.1.2 og Apples `sips` 316 lokalt. HEIF
går gjennom Apples dokumenterte systemgrensesnitt for bildebehandling og
ColorSync. Modellgenerering er bundet til MFLUX 0.18.0 og det offisielle
FLUX.2-klein-4B-snapshotet dersom den godkjente masteren faktisk kommer fra
den kjeden. Verktøyene forblir registrert med null ny kostnad og klarert
kommersiell bruk. [Apple om sips og fargestyring](https://developer.apple.com/library/archive/technotes/tn2313/_index.html),
[FFmpeg legal](https://ffmpeg.org/legal.html),
[FLUX.2-klein-4B model card](https://huggingface.co/black-forest-labs/FLUX.2-klein-4B).

## Kommandoer

Kontrakten kontrolleres uten å lage assets:

```sh
node native/scripts/visual-asset-production.mjs validate-contract
```

Etter at Codex uttrykkelig har valgt én kandidat, kan dens eksakte bilde,
kandidatmetadata og Codex-preflight fryses uten å lage lag eller masker:

```sh
node native/scripts/visual-asset-production.mjs freeze-provisional-master \
  --candidate <exact-candidate.png> \
  --metadata <exact-candidate.metadata.json> \
  --authority native/content/backstage/harvest/provisional-master-authority.json
```

Kommandoen nekter å skrive autoriteten utenfor `native/content/backstage`,
nekter å overskrive en annen frossen autoritet og kontrollerer kandidatsti,
bytes, SHA-256, preflight, `shippingAllowed: false`, åpen kunstnerisk port og
eksakt `1290 × 2796` SceneSpec-lerret.

Når master, masker og en domene-matchet DAG finnes:

```sh
node native/scripts/visual-asset-production.mjs build \
  --dag native/content/backstage/harvest/visual-production-dag.json \
  --output native/.build/visual-assets/harvest \
  --receipt native/content/backstage/harvest/visual-production-receipt.json
```

En senere ren reproduksjonskontroll bygger i en ny midlertidig mappe og krever
samme kvittering:

```sh
node native/scripts/visual-asset-production.mjs verify \
  --dag native/content/backstage/harvest/visual-production-dag.json \
  --receipt native/content/backstage/harvest/visual-production-receipt.json
```

Development-output og kvittering forblir under `.build` og `backstage`.
Shippingkompilatoren krever en separat redaktørgodkjenning over den komplette
offentlige filinventarhashen. Release-skanneren avviser provisional- og
non-shipping-markører dersom de finnes i appbytene. En referanse, modellfeil,
testfixture eller Codex-authority kan derfor ikke få shippingstatus gjennom
navnebytte eller filflytting.
