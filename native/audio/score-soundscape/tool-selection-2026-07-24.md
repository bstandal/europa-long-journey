# P1.09 tool selection — 24 July 2026

## Selected chain

The score source remains project-authored symbolic data. FluidSynth 2.5.6
renders one Standard MIDI file per stem through the exact MS Basic 0.2.0
SoundFont from MuseScore's official repository. FluidSynth is LGPL-2.1-or-later;
the SoundFont and its substantial derivatives are MIT with retained notices.
Neither production tool ships in the app.

The soundscape source remains project-owned procedural patches or an imported
source with exact CC0-1.0/MIT lineage. Local DSP keeps each material editable
and separated. A later CC0 replacement may improve a layer without changing
the timeline, stem contract or rights gate.

Primary records:

- FluidSynth tag and licence:
  `https://github.com/FluidSynth/fluidsynth/tree/e5b11058a619246cea42976dacb76ca54be3d45d`
- MuseScore SoundFont bytes:
  `https://raw.githubusercontent.com/musescore/MuseScore/03c4afd5c9ae72b2698f6716e9e244ce53550495/share/sound/MS%20Basic.sf3`
- MuseScore SoundFont licence:
  `https://raw.githubusercontent.com/musescore/MuseScore/03c4afd5c9ae72b2698f6716e9e244ce53550495/share/sound/MS%20Basic_License.md`

## Rejected for this production gate

TangoFlux is not a commercial option. Its official model card states that the
checkpoints are for non-commercial research and inherit WavCaps restrictions:
`https://huggingface.co/declare-lab/TangoFlux`.

Stable Audio Open Small is not admitted into the locked zero-cost chain. Its
official card requires a gated licence flow for commercial use, and the linked
Community License adds registration, product attribution and a commercial
licence transition above the revenue threshold:
`https://huggingface.co/stabilityai/stable-audio-open-small` and
`https://huggingface.co/stabilityai/stable-audio-open-1.0/blob/main/LICENSE.md`.
That is a conditional business dependency, not an unconditional production
right. It can be reconsidered only through a later explicit cost/licence
decision.

AudioCraft weights are excluded because Meta's official repository licenses
the model weights under CC-BY-NC 4.0:
`https://github.com/facebookresearch/audiocraft/blob/main/LICENSE_weights`.

These exclusions do not certify the selected technical probe as final art.
They establish a reproducible rights floor. If the score or soundscape fails
the full Harvest listening gate, P1.09 remains open and production stops before
shipping rather than importing a restricted model or lowering the artistic
bar.
