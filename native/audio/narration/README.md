# Local narrator casting pipeline

The production route is:

1. Qwen3-TTS VoiceDesign creates one short reference for each anonymous
   candidate from a written, non-identifying voice direction.
2. Qwen3-TTS Base clones that locally generated reference and reads the same
   829-word casting passage for exactly six candidates.
3. After the editor advances exactly two candidates, the same Base model and
   frozen references read one shared stress script. Each finalist delivers one
   seamless 18–22 minute master. The master may be assembled deterministically
   from short, fully audited utterances at authored semantic boundaries. Every
   utterance must pass before assembly; the approved text partition remains
   exact; audible seams, speech time-stretch and silence added merely to fill
   duration are prohibited. Natural punctuation breaths and authored pauses
   remain part of the performance.
4. FFmpeg converts generated 24 kHz audio to 48 kHz, 24-bit mono PCM. The
   candidate stage uses a common −3 dBFS peak target; final loudness mastering
   remains a later production gate.

The casting passage is a non-shipping assembly of exact paragraphs already
present in approved project prose. Its file SHA-256 is
`c473b155b4cd1696c867fae63a036f32026b9abd02228659716d2267e96114df`.
The validator checks each paragraph against its source file and requires the
locked Greek, Latin, Germanic and Slavic name sets. It does not alter a chapter,
its thesis or any public wording.

## Commands

Run all commands from the repository root:

```sh
uv sync --project native/audio/narration --frozen
uv run --project native/audio/narration --frozen --offline \
  python -m unittest discover -s native/audio/narration/test -v
uv run --project native/audio/narration --frozen --offline \
  python native/audio/narration/pipeline.py validate
uv run --project native/audio/narration --frozen --offline \
  python native/audio/narration/pipeline.py plan cast
```

The no-synthesis production preflight validates the exact Python and MLX-Audio
versions, the `uv` executable, the FFmpeg and FFprobe binaries, and every pinned
model and control-file byte already in the local cache:

```sh
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
uv run --project native/audio/narration --frozen --offline \
  python native/audio/narration/pipeline.py preflight --offline
```

It fails closed when the runtime, cache, model, configuration, pipeline source
or lockfile has drifted. It never loads a synthesis model or generates audio.

One short end-to-end technical probe:

```sh
uv run --project native/audio/narration --frozen --offline \
  python native/audio/narration/pipeline.py \
  probe --candidate voice-candidate-01 \
  --output /tmp/long-west-narration-probe --offline
```

The complete anonymous set:

```sh
uv run --project native/audio/narration --frozen --offline \
  python native/audio/narration/pipeline.py \
  cast --output /tmp/long-west-narration-candidates --offline
```

Stress production is unavailable until the complete six-candidate receipt and
all twelve bound audio files validate. It also requires a versioned editor
selection record under `native/audio/narration/editor-selections/`. That record
must approve exactly two finalist IDs and bind the candidate-set receipt by
SHA-256 and byte count. No selection record is supplied by the pipeline.

After that editor decision and an 18–22 minute text have been chosen:

```sh
uv run --project native/audio/narration --frozen --offline \
  python native/audio/narration/pipeline.py \
  stress \
  --candidate-set /tmp/long-west-narration-candidates \
  --selection-record native/audio/narration/editor-selections/<decision>.json \
  --text /absolute/path/to/locked-stress-text.txt \
  --output /tmp/long-west-narration-stress --offline
```

The production commands above require the pinned snapshots to be present in the
local Hugging Face cache. They fail instead of touching the network if either
model is missing.

Every newly generated probe, cast and stress receipt binds the applicable voice
instruction, `pipeline.py`, `pipeline-config.json`, `uv.lock`, and the exact
FFmpeg/FFprobe binaries and version lines. A code, configuration, lockfile,
runtime or candidate-byte change invalidates downstream production rather than
silently reusing it.

## Current gate

The six-candidate cast and the two provisional finalists exist. V6 R4 produced
complete 18–22 minute masters for `voice-candidate-05` and
`voice-candidate-06`, but V7 rejected both: candidate 05 exceeds the inherited
silence ceiling, while candidate 06 also contains long-window decoder collapse.
The independent 30-second check proved that the collapse is a decoder-window
failure rather than repeated source utterances; it did not make either master
eligible.

V8 preserves the exact approved text while repartitioning it into 203 semantic
utterances. Its frozen two-voice pause-density lab has no qualifying synthesis
factor. Every representative word, identity and utterance gate passed, but
model-retained silence remained above the limit for both voices. The 25/15/10
decoder-grid experiment is closed negative evidence; one seam required three
timestamp adjustments and 1011.905 ms against frozen limits of two words and
750 ms. The 30/15/15 grid therefore remains the V8 method.

A pinned offline Chatterbox-Turbo comparison then read the same fourteen V8
representatives from both original references. Every utterance, identity,
aggregate word and named-pronunciation gate passed. Both voices still failed
the silence and maximum projected-duration gates: retained silence was 15.49
percent for each, and projected full duration was 1556.24 and 1523.80 seconds.
The converted model's exact official-source revision is also unresolved.
Chatterbox comparison audio cannot become a master parent.

The subsequent local-only inventory found no eligible third synthesis method.
Apple's installed `say` engine has native rate and inline-pause controls, but
the locally bound macOS 26 licence prohibits recording and distributing System
Voices for this commercial product; it also cannot condition on the two frozen
references. Kokoro, MeloTTS, IndexTTS, Dia and VoxCPM2 exist only as installed
MLX-Audio source code, without cached model weights and complete licence and
control bindings. Every cached speech model is already part of the Qwen or
Chatterbox families. No comparison audio was generated.

V10 then tested OpenVoice V2 tone-colour conversion over the British MeloTTS
English base speaker. OpenVoice and MeloTTS code and weights are pinned to
official MIT revisions; BERT is pinned to one Apache-2.0 revision. The exact
sixteen-file source and model whitelist contains 789,435,291 bytes. An isolated
CPython 3.9.25 runtime contains 44 hash-locked wheels. Its licence audit found
no unavoidable copyleft dependency and imported the official converter and
Melo synthesizer with network construction disabled.

The adapter calls `MeloTTS.model.infer` directly. It never calls
`tts_to_file`, `audio_numpy_concat`, the sentence splitter, `get_se`, `g2p_en`
or NLTK. All fourteen representative texts normalize before model loading:
280 token occurrences, 185 unique tokens, zero unresolved tokens and an
explicit register for all fifteen named-pronunciation checks. The two exact
project references pass directly through `extract_se`. Generation uses one
fixed CPU method, one attempt per utterance and no choice made after listening.
The raw 22.05 kHz converter waveforms remain unchanged. Separate non-shipping
24 kHz audit derivatives contain only deterministic sample-rate conversion and
the authored 30/120/0-millisecond boundary pauses.

The unchanged fourteen-by-two V8 gate rejected both references. Candidate 05
reached minimum identity 0.98021, aggregate WER 5.63 percent, retained silence
15.97 percent, montage silence 17.18 percent and projected full duration
1449.07 seconds. Its ASR result omitted exact `Habsburg`, `polis` and `Roman`
tokens. Candidate 06 reached minimum identity 0.97836, aggregate WER 3.0303
percent, retained silence 16.65 percent, montage silence 17.86 percent and
projected duration 1448.04 seconds; its ASR result omitted exact `Roman`.
Both exceed the 1320-second duration ceiling. Candidate 06 also misses the
0.98 identity floor, and neither clears the silence ceilings of 0.10 and
0.115. No threshold, seed, pronunciation, speed or parameter was changed after
generation. The complete 203-by-two render is prohibited.

`v10-openvoice-negative-evidence.json` preserves the seven receipt hashes,
method bindings, licence facts and measured gate result outside the ignored
`work/` tree. `v10_openvoice_v2_evidence.py validate` checks that record without
requiring the 789 MB model snapshot or the 84 local diagnostic WAV files.

V11 then compared five remaining zero-cost candidates using publisher sources
only: Kokoro-82M, Parler-TTS Mini v1, StyleTTS2 LibriTTS, Pocket TTS and
VoxCPM2. Kokoro and Parler cannot condition on the two frozen project voices.
StyleTTS2's official weight repository has no licence metadata and its official
README leaves the importable inference path in a separate GPL fork or a stated
lower-quality MIT alternative. Pocket TTS accepts arbitrary WAV references and
runs quickly on a Mac CPU, but model access requires new user assent and the
publisher exposes neither native pace control nor inline authored pauses.

The gate selected VoxCPM2 for one exact-byte macOS-arm64 comparison. Its
official Apache-2.0 source and weights accept the exact reference WAV plus
transcript, expose pace and expression guidance, and support MPS with the
publisher's float32 fix. The bound model repository contains 4,960,731,703
bytes. Publisher-specific training-dataset details are not disclosed, and the
publisher recommends multiple generations for some controls; both facts remain
explicit risks.

V11 loaded the exact model offline on MPS/float32 and opened one single-attempt
representative job. The job created one raw WAV and one non-shipping audit WAV,
then stopped at the first undeclared runtime mutation: 46 Numba cache files
appeared inside the runtime tree before any job receipt could be committed.
Completed job count is zero. Retry, resume, review assembly, the fourteen-by-two
comparison and full-work generation are all forbidden under V11.

V12 is a distinct pre-synthesis trust domain. It rebuilt the runtime from the
59 locked local wheels, placed the Numba cache outside the runtime and encoded
both frozen reference/transcript pairs in two fresh processes. It called no
generation method, created no PCM or WAV, made no network attempt and preserved
the protected bytes and external cache exactly across replay. Its durable
authority keeps `synthesisPermitted=false`, `v11IsTerminal=true` and
`requiresEditorDecision=true`; it does not reopen V11 or promote VoxCPM2.

`v11-narration-candidate-gate.json` contains the five-candidate comparison,
sixteen byte-bound primary documents, five exact model-metadata records and the
stopped selection decision. `v11_voxcpm2_terminal_evidence.py validate`
protects the terminal representative result. `v12_voxcpm2_presynthesis.py
validate` protects the later closed pre-synthesis proof. All three validators
run in the offline native verification path.

Chapter 01 has one separate, editor-authorised review exception under
`NON_SHIPPING_REVIEW`. It does not alter the V12 production authority. Two
bounded VoxCPM2 probes were generated from candidates 05 and 06; neither passed
the word-accuracy, retained-silence and decoder-collapse gates. The authorised
fallback therefore renders all 37 frozen Chapter 01 segments with Qwen3-TTS
Base candidate 05. The decision, probe evidence, exact cue hashes and encoded
valid-frame durations used by AVAudioFile live under
`native/audio/narration/review/chapter-01/`. Ordinary
Release and shipping content packages must reject that directory.

P1.07 and P1.08 remain open. There is no passing narration master, candidate
promotion, editor voice choice, final pronunciation approval, artistic
approval or shipping approval.
