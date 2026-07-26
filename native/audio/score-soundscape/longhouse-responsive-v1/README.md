# Longhouse responsive audio work object

This directory contains the editable, provisional score and soundscape program
for `Raise the House`. It is backstage production material and cannot enter a
shipping package.

The program makes the assembly dependency audible. Low ground and post tones
remain stable while accepted components add timber work, lashing, hearth and
roof weather. A rejected order narrows into wood strain without advancing the
historical state. Completion leaves the assembled house sounding inhabited,
then holds a named silence before the inherited plot is heard.

`score-source.json` contains every note, phrase, instrument binding and stem.
`soundscape-source.json` binds all material layers to the repository's seeded
local DSP. No field recording or generated music file is imported. The ignored
`../cache/longhouse-responsive-v1/` directory contains deterministic 48 kHz,
24-bit stereo renders, editable MIDI stems and offline previews.

Run:

```sh
cd native/tooling
npm run render:longhouse-audio
npm run validate:longhouse-audio
```

Rendering performs two complete offline passes and accepts the evidence only
when all output bytes match. `longhouse-responsive-work-object.json` and
`render-receipt.json` remain
`PROVISIONAL_NON_SHIPPING`. Missing selected narration, integrated mix
calibration, artistic approval, editor approval, physical-device review and
shipping approval remain open.
