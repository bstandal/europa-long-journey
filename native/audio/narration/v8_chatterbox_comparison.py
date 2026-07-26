#!/usr/bin/env python3
"""Pinned offline Chatterbox-Turbo comparison for the frozen V8 block.

The preflight verifies every local model and tokenizer byte before any audio is
generated.  The representative lab may compare the exact fourteen V8 texts
and the two original finalist references.  Neither the lab audio nor the
converted model may become a master parent: the converted repository does not
declare the exact official source revision used for its conversion.
"""

from __future__ import annotations

import argparse
from collections import Counter
import gc
import hashlib
import json
import math
import os
from pathlib import Path
import sys
from typing import Any

import numpy as np

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v7_pipeline as v7
import v8_pipeline as v8
import v8_pause_lab as pause_lab


SCRIPT_PATH = Path(__file__).absolute()
PREFLIGHT_STATUS = "CODEX_V8_CHATTERBOX_COMPARISON_PREFLIGHT_COMPLETE"
LAB_STATUS = "CODEX_V8_CHATTERBOX_REPRESENTATIVE_COMPARISON_NON_SHIPPING"
EXPECTED_FINALISTS = ("voice-candidate-05", "voice-candidate-06")
OFFICIAL_RECEIPT = "native/audio/narration/chatterbox-turbo-snapshot.receipt.json"
CONVERTED_PREFLIGHT = "native/audio/narration/chatterbox-turbo-fp16-preflight.json"
CONVERTED_RECEIPT = (
    "native/audio/narration/chatterbox-turbo-fp16-snapshot.receipt.json"
)
S3_PREFLIGHT = "native/audio/narration/chatterbox-s3tokenizer-preflight.json"
S3_RECEIPT = "native/audio/narration/chatterbox-s3tokenizer-snapshot.receipt.json"
MLX_AUDIO_ROOT = Path(v8.__file__).parent / ".venv/lib/python3.14/site-packages"
MLX_AUDIO_DIST = MLX_AUDIO_ROOT / "mlx_audio-0.4.5.dist-info"
CHATTERBOX_CODE = MLX_AUDIO_ROOT / "mlx_audio/tts/models/chatterbox_turbo"
S3_RUNTIME_CODE = MLX_AUDIO_ROOT / "mlx_audio/codec/models/s3"
GENERATION_SETTINGS = {
    "repetitionPenalty": 1.2,
    "minimumProbability": 0.0,
    "topP": 0.95,
    "temperature": 0.8,
    "topK": 1000,
    "maximumSpeechTokens": 384,
    "normaliseReferenceLoudness": True,
    "stream": False,
    "splitPattern": None,
    "oneDeterministicAttemptPerUtterance": True,
    "seedBase": 8_500_000,
    "seedCandidateStride": 100_000,
    "seedUtteranceStride": 10,
}
CRITICAL_PRONUNCIATION_WORDS = (
    "polis",
    "roman",
    "christian",
    "excommunication",
    "monasteries",
    "emperor",
    "belgrade",
    "vienna",
    "croatia",
    "malta",
    "lepanto",
    "portuguese",
    "atlantic",
    "1648",
    "habsburg",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _public_utterance(item: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in item.items() if key != "text"}


def _load_bound_json(relative: str) -> tuple[Path, dict[str, Any]]:
    path = v8.repository_path(relative, directory=False)
    return path, production.load_json(path)


def _verify_snapshot(receipt_path: Path, receipt: dict[str, Any]) -> dict[str, Any]:
    snapshot = Path(receipt["snapshotPath"])
    if not snapshot.is_dir():
        raise v8.V8Error(f"pinned snapshot is unavailable: {snapshot}")
    expected = {item["path"]: item for item in receipt["files"]}
    actual_paths = sorted(
        item.relative_to(snapshot).as_posix()
        for item in snapshot.rglob("*")
        if item.is_file()
    )
    if actual_paths != sorted(expected):
        raise v8.V8Error(f"pinned snapshot inventory drifted: {snapshot}")
    verified: list[dict[str, Any]] = []
    for relative in actual_paths:
        path = snapshot / relative
        expected_record = expected[relative]
        record = {
            "path": relative,
            "bytes": path.stat().st_size,
            "sha256": _sha256(path),
        }
        if (
            record["bytes"] != expected_record["bytes"]
            or record["sha256"] != expected_record["sha256"]
        ):
            raise v8.V8Error(f"pinned snapshot byte drift: {path}")
        verified.append(record)
    return {
        "receipt": v8.file_binding(receipt_path),
        "modelID": receipt["modelID"],
        "revision": receipt["revision"],
        "snapshotPath": str(snapshot),
        "fileCount": len(verified),
        "totalBytes": sum(item["bytes"] for item in verified),
        "files": verified,
        "allCurrentBytesMatchReceipt": True,
    }


def _code_inventory(root: Path) -> dict[str, Any]:
    if not root.is_dir():
        raise v8.V8Error(f"runtime code directory is unavailable: {root}")
    files = []
    for path in sorted(root.rglob("*.py")):
        files.append(
            {
                "path": path.relative_to(MLX_AUDIO_ROOT).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": _sha256(path),
            }
        )
    if not files:
        raise v8.V8Error("runtime code inventory is empty")
    digest = hashlib.sha256()
    for item in files:
        digest.update(
            f"{item['path']}\0{item['bytes']}\0{item['sha256']}\n".encode("utf-8")
        )
    return {
        "root": str(root),
        "fileCount": len(files),
        "inventorySHA256": digest.hexdigest(),
        "files": files,
    }


def _selected_material(config: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    _, _, cues, utterances, segmentation = v8.segmentation_material()
    selected_ids = config["pauseDensityLab"]["representativeUtteranceIDs"]
    by_id = {item["utteranceID"]: item for item in utterances}
    try:
        selected = [by_id[item] for item in selected_ids]
    except KeyError as error:
        raise v8.V8Error("V8 representative inventory drifted") from error
    if {item["segmentID"] for item in selected} != {
        item["segmentID"] for item in cues
    }:
        raise v8.V8Error("V8 representative inventory no longer covers all cues")
    joined = "\n".join(
        f"{item['utteranceID']}\0{item['text']}" for item in selected
    )
    return selected, {
        "segmentation": segmentation,
        "utteranceCount": len(selected),
        "orderedUtteranceIDs": selected_ids,
        "exactTextManifestSHA256": production.sha256_text(joined),
        "allSixCuesCovered": True,
    }


def _reference_bindings() -> tuple[dict[str, Any], dict[str, Any]]:
    v6_config = v6.load_config()
    context = v6._generation_context(v6_config)
    bindings: dict[str, Any] = {}
    for candidate_id in EXPECTED_FINALISTS:
        parent = context["parentRecords"][candidate_id]
        path = Path(parent["_verifiedReferencePath"])
        current = v8.file_binding(path)
        expected = parent["reference"]
        if (
            current["bytes"] != expected["bytes"]
            or current["sha256"] != expected["sha256"]
        ):
            raise v8.V8Error("original finalist reference bytes drifted")
        bindings[candidate_id] = {
            "candidateID": candidate_id,
            "file": current,
            "durationSeconds": expected["durationSeconds"],
            "sampleRate": expected["sampleRate"],
            "channels": expected["channels"],
            "syntheticCandidateReference": True,
            "externalHumanVoiceContributor": False,
        }
    return bindings, context


def preflight(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("Chatterbox preflight requires --offline")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["DO_NOT_TRACK"] = "1"
    config = v8.load_config()
    output = v8.prepare_output(args.output, config)
    dependencies = v8.validate_dependencies(config)
    selected, representative = _selected_material(config)
    references, _ = _reference_bindings()

    official_path, official = _load_bound_json(OFFICIAL_RECEIPT)
    converted_preflight_path, converted_preflight = _load_bound_json(
        CONVERTED_PREFLIGHT
    )
    converted_path, converted = _load_bound_json(CONVERTED_RECEIPT)
    s3_preflight_path, s3_preflight = _load_bound_json(S3_PREFLIGHT)
    s3_path, s3 = _load_bound_json(S3_RECEIPT)
    if (
        official.get("modelID") != "ResembleAI/chatterbox-turbo"
        or official.get("revision")
        != "749d1c1a46eb10492095d68fbcf55691ccf137cd"
        or converted.get("modelID") != "mlx-community/chatterbox-turbo-fp16"
        or converted.get("revision")
        != "b2d0a13aa7cfff0a06d9acb247ae91c8f19a6d75"
        or s3.get("modelID") != "mlx-community/S3TokenizerV2"
        or s3.get("revision")
        != "e0c9886f0e1c35ae85b1f27277416fb19fc72bec"
    ):
        raise v8.V8Error("Chatterbox model revision binding drifted")

    code = {
        "mlxAudioDistribution": {
            "package": "mlx-audio",
            "version": "0.4.5",
            "license": "MIT",
            "metadata": v8.file_binding(MLX_AUDIO_DIST / "METADATA"),
            "licenseFile": v8.file_binding(
                MLX_AUDIO_DIST / "licenses/LICENSE"
            ),
            "record": v8.file_binding(MLX_AUDIO_DIST / "RECORD"),
            "uvLock": v8.file_binding(Path(v8.__file__).parent / "uv.lock"),
        },
        "chatterboxTurboRuntime": _code_inventory(CHATTERBOX_CODE),
        "s3Runtime": _code_inventory(S3_RUNTIME_CODE),
    }
    if (
        code["mlxAudioDistribution"]["metadata"]["sha256"]
        != "734fb0cdc3c11446b825f2ec14a09a7abf50b1c9f079b688f979aafc84cea596"
        or code["mlxAudioDistribution"]["licenseFile"]["sha256"]
        != "11d27e0259dec3a323fa6c04c330621d0950ab96c6760d5aac3e2e97229e6f22"
        or code["mlxAudioDistribution"]["uvLock"]["sha256"]
        != "db9a1340d7b9fbdb943d791aad3162e020c66a8212f2e4c129722e2dcd4535dc"
    ):
        raise v8.V8Error("pinned mlx-audio code or licence binding drifted")

    snapshots = {
        "officialUpstream": _verify_snapshot(official_path, official),
        "convertedComparisonRuntime": _verify_snapshot(converted_path, converted),
        "s3Tokenizer": _verify_snapshot(s3_path, s3),
    }
    licence_gate = {
        "officialModelWeightsMIT": (
            official["preflight"]["sha256"]
            == converted_preflight["licenses"]["officialUnderlyingModel"]
            ["officialPreflightSHA256"]
            and converted_preflight["licenses"]["officialUnderlyingModel"]
            ["license"]
            == "MIT"
        ),
        "convertedRepositoryApache2": converted_preflight["licenses"]
        ["convertedRepository"]["license"]
        == "Apache-2.0",
        "s3TokenizerUpstreamApache2": s3_preflight["upstream"]["license"]
        == "Apache-2.0",
        "mlxAudioCodeMIT": code["mlxAudioDistribution"]["license"] == "MIT",
        "commercialUseClearForPinnedComparisonBytes": converted_preflight[
            "licenses"
        ]["commercialUseAndRedistribution"][
            "clearForPinnedConvertedBytes"
        ]
        is True
        and s3_preflight["upstream"]["commercialUseClear"] is True,
        "requiredNoticesStillRequiredForRedistribution": True,
    }
    if not all(licence_gate.values()):
        raise v8.V8Error("Chatterbox comparison licence gate failed")

    inherited = v6.load_config()
    gates = {
        "exactApprovedTextInputAndCharacterPartitionRequired": True,
        "allFourteenRepresentativesAndBothOriginalReferencesRequired": True,
        "allInheritedV6IdentityTempoLexicalAndRepetitionThresholds": inherited[
            "utteranceGate"
        ],
        "engineSpecificTokenCeiling": {
            "tokenRateHz": 25,
            "maximumSpeechTokens": GENERATION_SETTINGS["maximumSpeechTokens"],
            "ceilingHitFails": True,
        },
        "criticalPronunciationWords": list(CRITICAL_PRONUNCIATION_WORDS),
        "allCriticalWordsMustBeExactInIndependentASRAlignment": True,
        "aggregateAndSilenceDurationThresholds": config["pauseDensityLab"],
        "outerActivityCropOnly": inherited["join"],
        "internalSilenceTrimmingProhibited": True,
        "speechTimeStretchProhibited": True,
        "durationPaddingProhibited": True,
        "adaptiveZeroPaddingProhibited": True,
    }
    receipt = {
        "schemaVersion": 1,
        "status": PREFLIGHT_STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "v8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "v8Config": v8.file_binding(v8.CONFIG_PATH),
        "dependencyBindings": dependencies,
        "modelSnapshots": snapshots,
        "modelAndTokenizerPreflights": {
            "converted": v8.file_binding(converted_preflight_path),
            "s3Tokenizer": v8.file_binding(s3_preflight_path),
        },
        "runtimeCode": code,
        "licenceGate": licence_gate,
        "references": references,
        "representativeSet": representative,
        "representativeTexts": [
            {**_public_utterance(item), "text": item["text"]} for item in selected
        ],
        "generationSettings": GENERATION_SETTINGS,
        "qualityGates": gates,
        "runtimeNetworkPermitted": False,
        "telemetryPermitted": False,
        "paidAPIUsed": False,
        "incrementalCostNOK": 0,
        "passesPreflight": True,
        "representativeComparisonPermitted": True,
        "fullChatterboxGenerationPermitted": False,
        "productionParentPermitted": False,
        "lineageBlock": (
            "The converted repository names the official model but does not "
            "declare the exact official source revision. Exact conversion "
            "lineage must be reproduced or otherwise proven before any full "
            "generation or production-parent decision."
        ),
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "finalPronunciationApproval": False,
        "artisticApproval": False,
        "shippingApproval": False,
    }
    receipt_path = output / "chatterbox-comparison-preflight.v8.receipt.json"
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def _seed(candidate_index: int, utterance_index: int) -> int:
    return (
        GENERATION_SETTINGS["seedBase"]
        + candidate_index * GENERATION_SETTINGS["seedCandidateStride"]
        + utterance_index * GENERATION_SETTINGS["seedUtteranceStride"]
    )


def _load_chatterbox(preflight_document: dict[str, Any]) -> Any:
    import huggingface_hub
    from mlx_audio.tts.utils import load_model

    converted = Path(
        preflight_document["modelSnapshots"]["convertedComparisonRuntime"]
        ["snapshotPath"]
    )
    s3 = Path(
        preflight_document["modelSnapshots"]["s3Tokenizer"]["snapshotPath"]
    )
    allowed = {
        item["path"]: s3 / item["path"]
        for item in preflight_document["modelSnapshots"]["s3Tokenizer"]["files"]
    }
    original = huggingface_hub.hf_hub_download

    def local_only_hf_hub_download(*args: Any, **kwargs: Any) -> str:
        repo_id = kwargs.get("repo_id") or (args[0] if args else None)
        filename = kwargs.get("filename") or (args[1] if len(args) > 1 else None)
        if repo_id != "mlx-community/S3TokenizerV2" or filename not in allowed:
            raise v8.V8Error("unexpected network-facing Chatterbox dependency")
        return str(allowed[filename])

    huggingface_hub.hf_hub_download = local_only_hf_hub_download
    try:
        model = load_model(converted)
    finally:
        huggingface_hub.hf_hub_download = original
    if model.sample_rate != 24000 or not hasattr(model, "prepare_conditionals"):
        raise v8.V8Error("pinned Chatterbox runtime contract drifted")
    return model


def _derive_speech_tokens(samples: int) -> dict[str, Any]:
    # S3Gen emits two mel frames per 25 Hz speech token.  Its pinned HiFiGAN
    # emits 480 samples per mel frame and has a fixed 60-sample terminal offset.
    adjusted = samples + 60
    exact = adjusted % 960 == 0
    count = adjusted // 960 if exact else math.ceil(samples / 960)
    return {
        "outputSamples": samples,
        "derivation": "(outputSamples + 60) / 960 for pinned S3Gen/HiFiGAN",
        "integerDerivation": exact,
        "derivedSpeechTokenCount": count,
    }


def _generate_comparison(
    *,
    root: Path,
    selected: list[dict[str, Any]],
    references: dict[str, Any],
    preflight_document: dict[str, Any],
    v6_config: dict[str, Any],
) -> list[dict[str, Any]]:
    import mlx.core as mx

    model = _load_chatterbox(preflight_document)
    records: list[dict[str, Any]] = []
    for candidate_index, candidate_id in enumerate(EXPECTED_FINALISTS):
        candidate_root = root / candidate_id
        candidate_root.mkdir(parents=True)
        reference_path = Path(references[candidate_id]["file"]["path"])
        model.prepare_conditionals(
            str(reference_path),
            exaggeration=0.0,
            norm_loudness=GENERATION_SETTINGS["normaliseReferenceLoudness"],
        )
        candidate_records = []
        for utterance_index, utterance in enumerate(selected):
            seed = _seed(candidate_index, utterance_index)
            production.set_generation_seed(seed)
            results = list(
                model.generate(
                    text=utterance["text"],
                    repetition_penalty=GENERATION_SETTINGS["repetitionPenalty"],
                    min_p=GENERATION_SETTINGS["minimumProbability"],
                    top_p=GENERATION_SETTINGS["topP"],
                    ref_audio=None,
                    exaggeration=0.0,
                    cfg_weight=0.0,
                    temperature=GENERATION_SETTINGS["temperature"],
                    top_k=GENERATION_SETTINGS["topK"],
                    norm_loudness=True,
                    stream=False,
                    split_pattern=None,
                    max_tokens=GENERATION_SETTINGS["maximumSpeechTokens"],
                )
            )
            if len(results) != 1:
                raise v8.V8Error("Chatterbox returned a split comparison utterance")
            result = results[0]
            raw = np.ascontiguousarray(
                np.asarray(result.audio, dtype=np.float32).reshape(-1)
            )
            if (
                int(result.sample_rate) != v6_config["master"]["nativeSampleRate"]
                or int(result.samples) != raw.size
                or raw.size == 0
                or not np.all(np.isfinite(raw))
            ):
                raise v8.V8Error("Chatterbox returned invalid comparison PCM")
            processed, processing = v6.process_utterance_audio(
                raw,
                sample_rate=int(result.sample_rate),
                separator_after=utterance["separatorAfter"],
                config=v6_config,
                normalized_word_count=None,
            )
            if "adaptiveSemanticPacing" in processing:
                raise v8.V8Error("Chatterbox comparison added adaptive padding")
            raw_path = candidate_root / f"{utterance['utteranceID']}.raw-f32.wav"
            processed_path = (
                candidate_root / f"{utterance['utteranceID']}.audio-f32.wav"
            )
            production.write_float_wav(raw_path, int(result.sample_rate), raw)
            production.write_float_wav(
                processed_path, int(result.sample_rate), processed
            )
            token_record = _derive_speech_tokens(raw.size)
            candidate_records.append(
                {
                    "utterance": _public_utterance(utterance),
                    "exactTextInput": utterance["text"],
                    "exactTextSHA256": production.sha256_text(utterance["text"]),
                    "generationSeed": seed,
                    "generationResult": {
                        "reportedTextTokenCount": int(result.token_count),
                        "processingTimeSeconds": result.processing_time_seconds,
                        "realTimeFactor": result.real_time_factor,
                        "peakMemoryGB": result.peak_memory_usage,
                    },
                    "speechTokens": token_record,
                    "rawAudio": v8.file_binding(raw_path),
                    "processedAudio": v8.file_binding(processed_path),
                    "processing": processing,
                }
            )
            print(
                f"Chatterbox comparison {candidate_id} "
                f"{utterance['utteranceID']}",
                file=sys.stderr,
                flush=True,
            )
        records.append(
            {
                "candidateID": candidate_id,
                "originalReference": references[candidate_id],
                "utteranceRecords": candidate_records,
            }
        )
    del model
    gc.collect()
    mx.clear_cache()
    return records


def _critical_word_gate(
    reference: list[str], hypothesis: list[str]
) -> dict[str, Any]:
    reference_counts = Counter(
        item for item in reference if item in CRITICAL_PRONUNCIATION_WORDS
    )
    hypothesis_counts = Counter(hypothesis)
    records = [
        {
            "word": word,
            "requiredOccurrences": count,
            "exactHypothesisOccurrences": hypothesis_counts[word],
            "passes": hypothesis_counts[word] >= count,
        }
        for word, count in sorted(reference_counts.items())
    ]
    return {
        "records": records,
        "allPresentExactly": bool(records) and all(item["passes"] for item in records),
    }


def _audit_comparison(
    *,
    root: Path,
    selected: list[dict[str, Any]],
    generated: list[dict[str, Any]],
    v6_config: dict[str, Any],
    v8_config: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    import mlx.core as mx

    context = v6._generation_context(v6_config)
    qwen_model, extractor = v6._load_runtime(context)
    reference_units, reference_records = v6._reference_material(
        context=context, extractor=extractor, config=v6_config
    )
    identity: dict[tuple[str, str], float] = {}
    for candidate in generated:
        candidate_id = candidate["candidateID"]
        for record in candidate["utteranceRecords"]:
            audio, _ = v5.read_native_audio(
                Path(record["processedAudio"]["path"]), v6_config
            )
            identity[(candidate_id, record["utterance"]["utteranceID"])] = (
                v6._utterance_identity_cosine(
                    audio, reference_units[candidate_id], extractor
                )
            )
    del qwen_model, extractor, reference_units
    gc.collect()
    mx.clear_cache()

    audio_paths = [
        Path(record["processedAudio"]["path"])
        for candidate in generated
        for record in candidate["utteranceRecords"]
    ]
    transcript_paths, asr_run = v6.run_whisper_batch(
        audio_paths=audio_paths, staging=root, config=v6_config
    )
    transcripts = iter(transcript_paths)
    audited: list[dict[str, Any]] = []
    for candidate in generated:
        candidate_id = candidate["candidateID"]
        public_records = []
        reference_words: list[str] = []
        hypothesis_words: list[str] = []
        processed_audio: list[np.ndarray] = []
        retained_audio: list[np.ndarray] = []
        for utterance, record in zip(
            selected, candidate["utteranceRecords"], strict=True
        ):
            transcript_path = next(transcripts)
            transcript = production.load_json(transcript_path)
            audio, _ = v5.read_native_audio(
                Path(record["processedAudio"]["path"]), v6_config
            )
            retained = record["processing"]["retainedSampleCountBeforePause"]
            processed_audio.append(audio)
            retained_audio.append(audio[:retained])
            token_count = record["speechTokens"]["derivedSpeechTokenCount"]
            gate = v6.utterance_asr_gate(
                utterance=utterance,
                transcript=transcript,
                duration_seconds=len(audio)
                / v6_config["master"]["nativeSampleRate"],
                token_count=token_count,
                token_cap=GENERATION_SETTINGS["maximumSpeechTokens"],
                identity_cosine=identity[
                    (candidate_id, utterance["utteranceID"])
                ],
                config=v6_config,
                adaptive_pacing_pass=True,
            )
            timed, grouping = v5.timed_words_from_whisper(
                transcript, master_duration_ms=len(audio) * 1000 / 24000
            )
            reference_words.extend(v5.normalize_words(utterance["text"]))
            hypothesis_words.extend(item.text for item in timed)
            public_records.append(
                {
                    **record,
                    "transcript": v8.file_binding(transcript_path),
                    "identityCosineToOriginalReference": identity[
                        (candidate_id, utterance["utteranceID"])
                    ],
                    "timedWordGrouping": grouping,
                    "gate": gate,
                }
            )
        _, aggregate = v5.monotone_global_alignment(
            reference_words, hypothesis_words
        )
        retained_silence = pause_lab._silence_fraction(
            np.concatenate(retained_audio), sample_rate=24000
        )
        montage_silence = pause_lab._silence_fraction(
            np.concatenate(processed_audio), sample_rate=24000
        )
        critical = _critical_word_gate(reference_words, hypothesis_words)
        full_utterance_count = v8.segmentation_material()[4]["utteranceCount"]
        del full_utterance_count
        _, _, _, full_utterances, _ = v8.segmentation_material()
        full_authored_pause_samples = sum(
            round(
                24000
                * (
                    v6_config["join"]["paragraphPauseMilliseconds"]
                    if item["separatorAfter"] == "\n\n"
                    else v6_config["join"]["intraParagraphPauseMilliseconds"]
                    if item["separatorAfter"] == " "
                    else v6_config["join"]["finalPauseMilliseconds"]
                )
                / 1000
            )
            for item in full_utterances
        )
        projected = (
            sum(len(item) for item in retained_audio)
            / 24000
            / len(reference_words)
            * 3422
            + full_authored_pause_samples / 24000
        )
        lab = v8_config["pauseDensityLab"]
        gates = {
            "allUtteranceGates": all(
                item["gate"]["passes"] for item in public_records
            ),
            "minimumUtteranceIdentity": min(
                item["identityCosineToOriginalReference"]
                for item in public_records
            )
            >= lab["minimumUtteranceIdentityCosine"],
            "maximumAggregateWordErrorRate": aggregate[
                "wordAlignmentErrorRate"
            ]
            <= lab["maximumAggregateWordErrorRate"],
            "criticalPronunciationWords": critical["allPresentExactly"],
            "maximumModelRetainedSilenceFraction": retained_silence[
                "silenceFraction"
            ]
            <= lab["maximumModelRetainedSilenceFraction"],
            "maximumRepresentativeMontageSilenceFraction": montage_silence[
                "silenceFraction"
            ]
            <= lab["maximumRepresentativeMontageSilenceFraction"],
            "minimumProjectedFullDuration": projected
            >= lab["minimumProjectedFullDurationSeconds"],
            "maximumProjectedFullDuration": projected
            <= lab["maximumProjectedFullDurationSeconds"],
        }
        audited.append(
            {
                "candidateID": candidate_id,
                "originalReference": reference_records[candidate_id],
                "utteranceRecords": public_records,
                "aggregateAlignment": aggregate,
                "criticalPronunciationGate": critical,
                "modelRetainedSilence": retained_silence,
                "representativeMontageSilence": montage_silence,
                "projectedFullDurationSeconds": projected,
                "fullAuthoredPauseSeconds": full_authored_pause_samples / 24000,
                "gates": gates,
                "passes": all(gates.values()),
            }
        )
    return audited, asr_run


def comparison(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("Chatterbox comparison requires --offline")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["DO_NOT_TRACK"] = "1"
    v8_config = v8.load_config()
    output = v8.prepare_output(args.output, v8_config)
    preflight_path = v8.repository_path(args.preflight, directory=False)
    preflight_document = production.load_json(preflight_path)
    if (
        preflight_document.get("status") != PREFLIGHT_STATUS
        or preflight_document.get("passesPreflight") is not True
        or preflight_document.get("representativeComparisonPermitted") is not True
        or preflight_document.get("fullChatterboxGenerationPermitted") is not False
        or preflight_document.get("productionParentPermitted") is not False
        or preflight_document.get("runtimeNetworkPermitted") is not False
        or preflight_document.get("incrementalCostNOK") != 0
    ):
        raise v8.V8Error("Chatterbox comparison preflight is not valid")
    selected, representative = _selected_material(v8_config)
    references, _ = _reference_bindings()
    if references != preflight_document["references"]:
        raise v8.V8Error("Chatterbox comparison references drifted after preflight")
    if representative != preflight_document["representativeSet"]:
        raise v8.V8Error("Chatterbox representative text drifted after preflight")
    v6_config = v6.load_config()
    generated = _generate_comparison(
        root=output,
        selected=selected,
        references=references,
        preflight_document=preflight_document,
        v6_config=v6_config,
    )
    audited, asr_run = _audit_comparison(
        root=output,
        selected=selected,
        generated=generated,
        v6_config=v6_config,
        v8_config=v8_config,
    )
    passes = len(audited) == 2 and all(item["passes"] for item in audited)
    receipt = {
        "schemaVersion": 1,
        "status": LAB_STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "preflight": v8.file_binding(preflight_path),
        "v8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "v8Config": v8.file_binding(v8.CONFIG_PATH),
        "representativeSet": representative,
        "generationSettings": GENERATION_SETTINGS,
        "asrRun": asr_run,
        "candidateRecords": audited,
        "passesRepresentativeComparison": passes,
        "technicalConclusion": (
            "Chatterbox passed the same representative identity, timing, "
            "lexical, pronunciation, silence and duration gates for both "
            "voices. Exact official-to-MLX conversion lineage remains a "
            "separate block before any full generation."
            if passes
            else (
                "The pinned Chatterbox comparison failed at least one frozen "
                "representative gate. Full generation is prohibited."
            )
        ),
        "comparisonAudioPermittedAsMasterParent": False,
        "fullChatterboxGenerationPermitted": False,
        "productionParentPermitted": False,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "finalPronunciationApproval": False,
        "artisticApproval": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }
    receipt_path = output / "chatterbox-comparison.v8.receipt.json"
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Pinned offline V8 Chatterbox comparison"
    )
    commands = result.add_subparsers(dest="command", required=True)
    pre = commands.add_parser("preflight")
    pre.add_argument("--output", required=True, type=Path)
    pre.add_argument("--offline", action="store_true")
    lab = commands.add_parser("compare")
    lab.add_argument("--output", required=True, type=Path)
    lab.add_argument("--preflight", required=True)
    lab.add_argument("--offline", action="store_true")
    return result


def main() -> int:
    try:
        args = parser().parse_args()
        result = preflight(args) if args.command == "preflight" else comparison(args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (
        v8.V8Error,
        v7.V7Error,
        v6.V6Error,
        v5.V5Error,
        production.PipelineError,
    ) as error:
        print(f"V8 Chatterbox comparison error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
