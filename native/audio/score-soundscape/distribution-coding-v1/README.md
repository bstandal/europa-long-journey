# Chapter 1 responsive distribution candidate

This backstage chain converts only the 91 responsive Chapter 1 score,
soundscape and spatial-detail PCM masters named by the six render receipts.
The inputs total 750,820,004 bytes at 48 kHz, 24-bit stereo. There were no
pre-existing responsive M4A files in the source cache; the M4A paths elsewhere
in the generated chapter payload remain unfulfilled asset requirements.

The candidate first uses the pinned FFmpeg 8.1.2 native AAC-LC encoder at
384 kbit/s. If that lossy encode breaks the existing 0.005 loop-seam gate or
the -1 dBFS true-peak ceiling, that one asset falls back to lossless ALAC and
must decode byte-identically to the source PCM. Every selected output is
encoded twice and must be byte-identical. The build also checks
the source bytes and hashes, exact 48 kHz container duration, complete scheduled
decode range, bounded decoder tail padding, responsive-loop seam delta and a
maximum encoded true peak of -1 dBFS. Output files live only in the ignored
`distribution-cache/` directory. The versioned receipt contains hashes and
measurements, never shipping authority.

```sh
node native/audio/score-soundscape/distribution-coding-v1/build-first-farmers-candidate.mjs inventory
node native/audio/score-soundscape/distribution-coding-v1/build-first-farmers-candidate.mjs build
node native/audio/score-soundscape/distribution-coding-v1/build-first-farmers-candidate.mjs verify
```

AAC reduces installed bytes, not decoded working memory. Runtime integration,
sample-exact playback on AVFoundation, loop quality, the complete narrated mix,
energy use and thermal behaviour still require the physical iPhone protocol.
The editor and audio approval gates remain open. These candidates cannot enter
a shipping package.
