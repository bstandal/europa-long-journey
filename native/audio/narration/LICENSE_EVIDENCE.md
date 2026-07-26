# Narration toolchain licence record

This is a backstage production record. It does not enter a shipping content
package.

## Synthesis models

The casting chain uses two BF16 MLX conversions:

- `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`, revision
  `7d3824abff87e49756bb0f83fb5411de75d160c4`. Its model card declares
  `Apache-2.0`, names `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` as the source and
  records MLX-Audio `0.3.0` as the converter. [Pinned model card](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16/blob/7d3824abff87e49756bb0f83fb5411de75d160c4/README.md)
- `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16`, revision
  `a6eb4f68e4b056f1215157bb696209bc82a6db48`. Its model card declares
  `Apache-2.0`, names `Qwen/Qwen3-TTS-12Hz-1.7B-Base` as the source and records
  the same converter. [Pinned model card](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16/blob/a6eb4f68e4b056f1215157bb696209bc82a6db48/README.md)

The corresponding upstream Qwen model cards declare `Apache-2.0` at revisions
`5ecdb67327fd37bb2e042aab12ff7391903235d3` and
`fd4b254389122332181a7c3db7f27e918eec64e3`.
[VoiceDesign](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign/tree/5ecdb67327fd37bb2e042aab12ff7391903235d3),
[Base](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base/tree/fd4b254389122332181a7c3db7f27e918eec64e3).
The [official Qwen3-TTS repository](https://github.com/QwenLM/Qwen3-TTS/tree/022e286b98fbec7e1e916cb940cdf532cd9f488e)
is Apache-2.0 and documents the VoiceDesign-then-clone workflow used here.

`pipeline-config.json` records the SHA-256 and byte count of each model and
speech-tokenizer weight. Synthesis stops if a cached or downloaded byte differs.

## OpenVoice V2 comparison

The stopped V10 comparison used only the following pinned publisher releases:

- OpenVoice source revision `74a1d147b17a8c3092dd5430504bd83ef6c7eb23`
  and OpenVoice V2 model revision
  `f36e7edfe1684461a8343844af60babc2efbb727`, both under MIT. The selected
  model files were the converter configuration and checkpoint, the built-in
  `en-br` source-speaker embedding and the model card.
  [Source licence](https://github.com/myshell-ai/OpenVoice/blob/74a1d147b17a8c3092dd5430504bd83ef6c7eb23/LICENSE),
  [model card](https://huggingface.co/myshell-ai/OpenVoiceV2/tree/f36e7edfe1684461a8343844af60babc2efbb727)
- MeloTTS source revision `209145371cff8fc3bd60d7be902ea69cbdb7965a`
  and English model revision
  `bb4fb7346d566d277ba8c8c7dbfdf6786139b8ef`, both under MIT.
  [Source licence](https://github.com/myshell-ai/MeloTTS/blob/209145371cff8fc3bd60d7be902ea69cbdb7965a/LICENSE),
  [model card](https://huggingface.co/myshell-ai/MeloTTS-English/tree/bb4fb7346d566d277ba8c8c7dbfdf6786139b8ef)
- `google-bert/bert-base-uncased` revision
  `86b5e0934494bd15c9632b12f734a8a67f723594` under Apache-2.0.
  [Pinned model files and licence](https://huggingface.co/google-bert/bert-base-uncased/tree/86b5e0934494bd15c9632b12f734a8a67f723594)

The exact source-and-model snapshot is sixteen files and 789,435,291 bytes.
Its isolated CPU runtime uses CPython 3.9.25 and 44 selected wheel files, each
locked by SHA-256. The recorded package licences are permissive; the audit
found no unavoidable GPL, LGPL or AGPL runtime dependency. CPython retains the
PSF-2.0 licence and the pinned python-build-standalone distribution is
MPL-2.0. The process used no hosted synthesis, billing credential or external
reference speaker and incurred zero incremental kroner.

The model cards do not identify the complete MeloTTS training corpus, the
English base speaker or every individual source used for OpenVoice converter
training. That provenance limit remains in the backstage record. The pinned
publisher licences nevertheless grant commercial use of the selected code and
weights. The V10 audio failed the unchanged quality gate and is prohibited as a
master parent; no generated V10 audio ships.

The compact record at `v10-openvoice-negative-evidence.json` binds the exact
primary-source, snapshot, runtime, pronunciation, model-load, generation and
audit receipt hashes. It preserves these licence findings without checking the
ignored model snapshot or diagnostic audio into the repository.

## V11 remaining-candidate gate

The V11 comparison retrieved publisher documents and model-repository metadata
only. It did not resolve a model, voice or audio file URL.

- Kokoro code revision `dfb907a02bba8152ca444717ca5d78747ccb4bec`
  and model revision `f3ff3571791e39611d31c381e3a41a3af07b4987`
  are Apache-2.0. The publisher documents fixed voice tensors and numeric speed,
  but no arbitrary reference-WAV conditioning. [Code](https://github.com/hexgrad/kokoro/tree/dfb907a02bba8152ca444717ca5d78747ccb4bec),
  [weights](https://huggingface.co/hexgrad/Kokoro-82M/tree/f3ff3571791e39611d31c381e3a41a3af07b4987)
- Parler-TTS code revision `d108732cd57788ec86bc857d99a6cabd66663d68`
  and Mini v1 revision `0392b9451a601e528fd863bbb0598431fee810d9`
  are Apache-2.0. The checkpoint provides named training speakers and
  description-based pace and recording control, not conditioning on the two
  frozen references. [Code](https://github.com/huggingface/parler-tts/tree/d108732cd57788ec86bc857d99a6cabd66663d68),
  [weights](https://huggingface.co/parler-tts/parler-tts-mini-v1/tree/0392b9451a601e528fd863bbb0598431fee810d9)
- StyleTTS2 source revision `5cedc71c333f8d8b8551ca59378bdcc7af4c9529`
  is MIT, but the official LibriTTS weight repository at
  `3aa7ba7f8f275ec13dce21682a61494c35089e2a` has no model card, licence tag or
  licence file. The source README also states that the demonstrated inference
  depends on a separate GPL package and describes the MIT alternative as lower
  quality. That is not a commercially closed production chain.
  [Source](https://github.com/yl4579/StyleTTS2/tree/5cedc71c333f8d8b8551ca59378bdcc7af4c9529),
  [weight repository](https://huggingface.co/yl4579/StyleTTS2-LibriTTS/tree/3aa7ba7f8f275ec13dce21682a61494c35089e2a)
- Pocket TTS source tag `v2.1.0`, commit
  `058886528d0b6f2f2d4022de2e244a5260729e6e`, is MIT. Model revision
  `4c8ad48f8a003909bc4f1122cbe88a4252124621` is CC-BY-4.0 with additional
  gated prohibited-use terms and requires contact sharing and a use
  declaration before access. The project has not authorised Codex to accept
  those terms on the user's behalf. [Source](https://github.com/kyutai-labs/pocket-tts/tree/058886528d0b6f2f2d4022de2e244a5260729e6e),
  [model card and gate](https://huggingface.co/kyutai/pocket-tts/tree/4c8ad48f8a003909bc4f1122cbe88a4252124621)
- VoxCPM source tag `2.0.3`, commit
  `19b6bf7590025418821a86dcb817504e0ad7e5df`, and VoxCPM2 model revision
  `bffb3df5a29440629464e5e839f4d214c8714c3d` are Apache-2.0 and not gated.
  The publisher documents MPS execution, direct reference-WAV and transcript
  conditioning, and pace and expression control. The selected model file set
  is 4,960,731,703 bytes. [Source release](https://github.com/OpenBMB/VoxCPM/releases/tag/2.0.3),
  [model repository](https://huggingface.co/openbmb/VoxCPM2/tree/bffb3df5a29440629464e5e839f4d214c8714c3d)

OpenBMB states that VoxCPM2 used more than two million hours of speech, but an
official contributor says the specific dataset details are withheld as trade
secrets and places compliance evaluation on the downstream user.
[Publisher response](https://github.com/OpenBMB/VoxCPM/issues/238#issuecomment-4228356331)
That limitation remains in the provenance register. It does not become a
quality or shipping approval.

VoxCPM2 was selected for an exact-byte macOS-arm64 comparison. The complete
4,960,731,703-byte model snapshot and a 59-wheel runtime are now locally bound.
The offline MPS/float32 model-load gate passed with no network attempt. The
first authorised representative job then created one raw WAV and one audit
derivative, but the run stopped before a job receipt when the runtime wrote 46
previously undeclared Numba cache files inside its own tree. V11 is terminal:
zero jobs completed, retry and resume are forbidden, and neither WAV can enter
a comparison, master or shipping lineage.

V12 rebuilt the same method from the locked local archives with
`NUMBA_CACHE_DIR` outside the runtime. Two fresh processes loaded both frozen
references and built their combined reference/prompt caches. Model generation
was blocked and never called; the protected runtime, source and model trees
were byte-identical before and after both runs, and the external 46-file cache
was identical on replay. V12 is a pre-synthesis proof only. It explicitly keeps
`synthesisPermitted=false`, preserves V11 as terminal and requires a new editor
decision before any later comparison authority could exist.

## Local tools

- MLX-Audio `0.4.5`, commit
  `04151c6abb74b886f879a4457ccdc96761f10102`, is MIT-licensed.
  [Repository and licence](https://github.com/Blaizzy/mlx-audio/tree/04151c6abb74b886f879a4457ccdc96761f10102)
- Astral uv `0.11.22` is available under Apache-2.0 or MIT.
  [Repository and licences](https://github.com/astral-sh/uv)
- CPython `3.14.6` uses the Python Software Foundation License Version 2.
  [Python licence](https://docs.python.org/3/license.html)
- The installed FFmpeg `8.1.2` executable is GPL-3.0-or-later. It resamples and
  encodes local PCM files; no FFmpeg library is linked into the app or shipped
  as part of an audio master.

No hosted API, billing credential or external reference speaker enters the
chain. VoiceDesign creates each identity from a non-identifying written
description. The Base model receives only that locally generated reference and
its exact project-owned transcript.

This record clears the model and tool licences for a local commercial
production trial. It does not approve a voice, a generated take or a shipping
asset. Those remain blocked by the word, pronunciation, cadence, artefact and
editor-selection gates in `audio-bible.md`.
