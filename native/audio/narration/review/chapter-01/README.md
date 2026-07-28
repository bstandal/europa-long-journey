# Chapter 01 review narration

This directory is the only tracked narration input for the internal
`CHAPTER_01_REVIEW_READY` build. Every file is restricted to
`NON_SHIPPING_REVIEW`; ordinary Release and shipping-package compilation must
reject the directory.

`review-authorization.json` records the editor-in-chief's bounded decision. It
does not modify or reopen the closed V12 production authority. `probes/` holds
the two technical VoxCPM2 comparisons. `manifest.json` binds exactly 37 frozen
manuscript segments to the encoded files in `cues/` and records duration from
the decoded 48 kHz audio, not from an estimate.

The review voice is provisional. No file in this directory is a narration
master, a final voice selection or a shipping asset.

The bounded VoxCPM2 comparison completed one 64.469-second candidate-05 probe
and one 83.349-second candidate-06 probe. Both retained voice identity, but
both failed the frozen word-accuracy, silence and decoder-collapse gates. The
review build therefore uses the authorised Qwen3-TTS Base candidate-05
fallback for all 37 cues. `probe-selection.json` preserves the measured result;
`manifest.json` binds the resulting cue bytes to the frozen segment hashes and
the full review-draft hash.
