# Score- og soundscape-kjede

Denne mappen er backstage produksjonsdata for P1.09. Ingen fil her er offentlig
fortelling eller godkjent shippinglyd.

## Metode

Score begynner i `harvest-score-technique.json`. Kilden har navngitte motiver,
noter i vitenskapelig tonehøyde, tempoendringer, dynamikk, artikulasjon,
instrumentbinding og selvstendige stems. Verktøyet lager én standard MIDI-fil
per stem og renderer den uten nett gjennom den låste FluidSynth- og
SoundFont-kjeden. En ferdiggenerert musikklåt kan ikke importeres som erstatning
for denne kilden.

Soundscape begynner i `harvest-soundscape-technique.json`. Regn, ild, korn,
tekstil og synlig arbeid har hvert sitt kildebundne lag, seed og parametere.
Verktøyet renderer dem uavhengig med prosjektets lokale DSP. Stillhet er en
navngitt tidsperiode med bestemt inn- og utgang; den oppstår ikke ved at et
musikkspor tilfeldigvis tar slutt.

Alle tekniske WAV-prøver er stereo PCM ved 48 kHz og 24 bit. Cache og lydfiler
er reproducerbare byggeprodukter og holdes utenfor versjonert kilde. Den
versjonerte receipt-en binder kildefiler, verktøybytes, SoundFont og hvert
prøveresultat til eksakte hasher.

```sh
cd native/tooling
npm run validate:audio
npm run render:audio-probe
```

`bootstrap` laster bare den eksakt låste SoundFont-filen fra det offisielle
MuseScore-repoet og avviser avvik i antall bytes eller SHA-256:

```sh
node src/audio-production-cli.mjs bootstrap
```

## Rettighetsgrunnlag

- FluidSynth 2.5.6 kjøres lokalt som et uendret kommandolinjeverktøy. Den
  offisielle koden er LGPL-2.1-or-later. Verktøyet eller biblioteket sendes ikke
  i appen.
- MS Basic 0.2.0 kommer fra MuseScores offisielle repo ved commit
  `03c4afd5c9ae72b2698f6716e9e244ce53550495`. Den eksakte filen er
  MIT-lisensiert. Endelig distribusjon må beholde hele upstream-opphavs- og
  tillatelsesnotisen, ikke bare en kort henvisning. Den bytebundne lokale
  kopien ligger i `licenses/MS-Basic-0.2.0-LICENSE.md`; verken validering eller
  rendering består dersom den mangler eller er endret.
- Prosjektets symbolske score, prosedurale patches og redigeringer har
  `PROJECT_AUTHORED_AUDIO`-lineage. Et eksternt råopptak kan bare brukes gjennom
  `OPEN_LICENSE_AUDIO_SOURCE` med eksakt URL, bytes, hash og lisensbevis.
  `CC0-1.0` og `MIT` er de eneste åpne lydlisensene schema v3 tillater nå.
- Apple-lyd har ingen tillatt lineage-variant. En systemlyd, DLS-bank eller
  annen Apple-fil forblir blokkert til et konkret avtaleledd dokumenterer at
  det ferdige lydderivatet kan redistribueres i appen.

## Åpne porter

Den tekniske prøven beviser redigerbarhet, stems, materiallag, format og den
registrerte lisenskjeden. Tre responsive arbeidsobjekter fører kjeden inn i
runtime: [Harvest](harvest-responsive-v1/work-object.json),
[Longhouse](longhouse-responsive-v1/longhouse-responsive-work-object.json) og
[A Continent Remade](continent-remade-responsive-v1/continent-remade-responsive-work-object.json).
Hvert objekt har fem runtime-regioner, tre sample-like tilstandsbed,
scorestems, soundscape, spatialdetaljer, eksplisitt stillhet og semantiske
haptikkbindinger. Hver master er rendret offline og byteverifisert i to
komplette pass. Objektene er `PROVISIONAL_NON_SHIPPING`; ingen komposisjon
eller samlet lydopplevelse er redaktørgodkjent. Følgende arbeid gjenstår:

- erstatte eller videreutvikle hvert lag som ikke holder kunstnerisk eller
  materiell kvalitet;
- binde den valgte fortellerens eksakte ordmaster til de to åpne
  narrasjonsslottene;
- kalibrere integrert nivå med den valgte fortelleren i den samlede miksen;
- registrere shippingmastere med eksakte kilder, notices og editor-godkjenning.

P1.09 er åpen til dette finnes i godkjente `AudioTimeline`-objekter sammen med
valgt fortellerstemme og de semantiske haptikksettene.
