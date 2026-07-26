#!/usr/bin/env python3
"""Exact text and waveform adapter for the frozen V10 OpenVoice method."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import random
from typing import Any

import numpy as np

import pipeline as production
import v8_pipeline as v8
import v10_openvoice_v2_model_load_probe as model_load
import v10_openvoice_v2_pronunciation_gate as pronunciation


SCRIPT_PATH = Path(__file__).absolute()
CONFIG_PATH = SCRIPT_PATH.with_name("v10-openvoice-method-config.json")


def load_config() -> dict[str, Any]:
    config = production.load_json(CONFIG_PATH)
    generation = config.get("generation", {})
    audio = config.get("audio", {})
    comparison = config.get("comparison", {})
    if (
        config.get("status")
        != "CODEX_V10_OPENVOICE_REPRESENTATIVE_METHOD_FROZEN"
        or config.get("device") != "cpu"
        or config.get("locale") != "en-GB"
        or config.get("speaker", {}).get("baseSpeaker") != "EN-BR"
        or config.get("speaker", {}).get("speakerID") != 1
        or generation
        != {
            "speed": 1.0,
            "sdpRatio": 0.2,
            "noiseScale": 0.6,
            "noiseScaleW": 0.8,
            "lengthScale": 1.0,
            "converterTau": 0.3,
            "seedBase": 10_000_000,
            "seedCandidateStride": 100_000,
            "seedUtteranceStride": 10,
            "threadCount": 1,
            "oneDeterministicAttemptPerUtterance": True,
            "parameterSelectionAfterListeningPermitted": False,
            "automaticSentenceSplittingPermitted": False,
            "publicTtsToFilePermitted": False,
            "g2pFallbackPermitted": False,
        }
        or audio.get("meloSampleRate") != 44_100
        or audio.get("converterSampleRate") != 22_050
        or audio.get("frozenAuditSampleRate") != 24_000
        or audio.get("auditSampleRateUpFactor") != 160
        or audio.get("auditSampleRateDownFactor") != 147
        or audio.get("rawConverterOutputMustRemainUnchanged") is not True
        or audio.get("activityCropPermitted") is not False
        or audio.get("edgeFadePermitted") is not False
        or audio.get("loudnessNormalizationPermitted") is not False
        or audio.get("internalSilenceRemovalPermitted") is not False
        or audio.get("speechTimeStretchPermitted") is not False
        or audio.get("durationPaddingPermitted") is not False
        or comparison.get("requiredSynthesisCount") != 28
        or comparison.get("exactTextManifestSHA256")
        != pronunciation.EXPECTED_REPRESENTATIVE_SHA256
        or comparison.get("fullGenerationPermittedBeforeBothPass") is not False
    ):
        raise v8.V8Error("V10 OpenVoice method configuration drifted")
    return config


def _distribute_phone(phone_count: int, wordpiece_count: int) -> list[int]:
    if phone_count <= 0 or wordpiece_count <= 0:
        raise v8.V8Error("V10 phone distribution requires positive counts")
    result = [0] * wordpiece_count
    for _ in range(phone_count):
        minimum = min(result)
        result[result.index(minimum)] += 1
    return result


def _refine_phone(phone: str, symbols: set[str]) -> tuple[str, int]:
    if phone in pronunciation.PUNCTUATION:
        if phone not in symbols:
            raise v8.V8Error("V10 punctuation escaped the Melo symbol table")
        return phone, 0
    base = phone.rstrip("012")
    suffix = phone[len(base):]
    tone = int(suffix) + 1 if suffix else 0
    symbol = base.lower()
    if symbol == "v":
        symbol = "V"
    if symbol not in symbols:
        raise v8.V8Error(f"V10 ARPAbet phone escaped Melo symbols: {phone}")
    return symbol, tone


def _intersperse(values: list[int], item: int = 0) -> list[int]:
    result = [item] * (len(values) * 2 + 1)
    result[1::2] = values
    return result


def prepare_text(
    utterance: dict[str, Any],
    *,
    tokenizer: Any,
    bert_model: Any,
    melo_config: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    import torch

    if production.sha256_text(utterance["exactText"]) != utterance["exactTextSHA256"]:
        raise v8.V8Error("V10 exact utterance text drifted")
    normalized = pronunciation._normalise(utterance["exactText"])
    if (
        normalized != utterance["normalizedText"]
        or production.sha256_text(normalized) != utterance["normalizedTextSHA256"]
    ):
        raise v8.V8Error("V10 normalized utterance drifted")
    groups = pronunciation._wordpiece_groups(tokenizer, normalized)
    frozen_tokens = utterance["tokens"]
    if [item["token"] for item in groups] != [item["token"] for item in frozen_tokens]:
        raise v8.V8Error("V10 BERT wordpiece grouping drifted")

    symbols = set(melo_config["symbols"])
    cmu = pronunciation._read_cmudict()
    overrides = pronunciation.load_config()["projectOverrides"]
    phones: list[str] = []
    tones: list[int] = []
    word2ph: list[int] = []
    token_resolutions: list[dict[str, Any]] = []
    for group, frozen in zip(groups, frozen_tokens):
        resolution = pronunciation._resolve_token(
            group["token"], cmu=cmu, overrides=overrides
        )
        if resolution["source"] != frozen["source"] or resolution["phones"] != frozen["phones"]:
            raise v8.V8Error("V10 frozen pronunciation resolution drifted")
        local_phones = []
        local_tones = []
        for phone in resolution["phones"]:
            symbol, tone = _refine_phone(phone, symbols)
            local_phones.append(symbol)
            local_tones.append(tone)
        phones.extend(local_phones)
        tones.extend(local_tones)
        word2ph.extend(
            _distribute_phone(len(local_phones), group["wordPieceCount"])
        )
        token_resolutions.append(
            {
                "token": group["token"],
                "wordPieces": group["wordPieces"],
                "phones": local_phones,
                "tonesBeforeLanguageOffset": local_tones,
                "source": resolution["source"],
            }
        )

    phones = ["_", *phones, "_"]
    tones = [0, *tones, 0]
    word2ph = [1, *word2ph, 1]
    symbol_to_id = {
        symbol: index for index, symbol in enumerate(melo_config["symbols"])
    }
    phone_ids = [symbol_to_id[item] for item in phones]
    tone_ids = [item + 7 for item in tones]
    language_ids = [2] * len(phone_ids)
    phone_ids = _intersperse(phone_ids)
    tone_ids = _intersperse(tone_ids)
    language_ids = _intersperse(language_ids)
    word2ph = [item * 2 for item in word2ph]
    word2ph[0] += 1
    if sum(word2ph) != len(phone_ids):
        raise v8.V8Error("V10 Melo blank and BERT alignment drifted")

    encoded = tokenizer(normalized, return_tensors="pt")
    if encoded["input_ids"].shape[-1] != len(word2ph):
        raise v8.V8Error("V10 local BERT token count drifted")
    with torch.inference_mode():
        outputs = bert_model(
            **{key: value.to("cpu") for key, value in encoded.items()},
            output_hidden_states=True,
        )
        features = outputs.hidden_states[-3][0].cpu()
    repeated = [
        features[index].repeat(count, 1)
        for index, count in enumerate(word2ph)
    ]
    ja_bert = torch.cat(repeated, dim=0).transpose(0, 1).contiguous()
    if tuple(ja_bert.shape) != (768, len(phone_ids)):
        raise v8.V8Error("V10 English BERT feature shape drifted")
    bert = torch.zeros((1024, len(phone_ids)), dtype=ja_bert.dtype)
    tensors = {
        "phones": torch.LongTensor(phone_ids),
        "tones": torch.LongTensor(tone_ids),
        "languages": torch.LongTensor(language_ids),
        "bert": bert,
        "jaBert": ja_bert,
    }
    record = {
        "normalizedText": normalized,
        "normalizedTextSHA256": production.sha256_text(normalized),
        "wordPieceCountIncludingSpecialTokens": len(word2ph),
        "phoneCountBeforeBlankInsertion": len(phones),
        "modelInputPhoneCount": len(phone_ids),
        "maximumInputPhoneCount": load_config()["comparison"][
            "maximumInputPhoneCount"
        ],
        "tokenCeilingPasses": len(phone_ids)
        < load_config()["comparison"]["maximumInputPhoneCount"],
        "bertFeatureShape": list(bert.shape),
        "englishBertFeatureShape": list(ja_bert.shape),
        "tokenResolutions": token_resolutions,
        "g2pFallbackUsed": False,
        "nltkUsed": False,
    }
    if not record["tokenCeilingPasses"]:
        raise v8.V8Error("V10 model input exceeds the inherited ceiling")
    return tensors, record


def generation_seed(candidate_index: int, utterance_index: int) -> int:
    settings = load_config()["generation"]
    if candidate_index not in (0, 1) or not 0 <= utterance_index < 14:
        raise v8.V8Error("V10 generation seed index escaped the frozen grid")
    return (
        settings["seedBase"]
        + candidate_index * settings["seedCandidateStride"]
        + utterance_index * settings["seedUtteranceStride"]
    )


def synthesize_base(
    tensors: dict[str, Any], *, model: Any, seed: int
) -> np.ndarray:
    import torch

    config = load_config()["generation"]
    random.seed(seed)
    np.random.seed(seed % (2**32))
    torch.manual_seed(seed)
    phones = tensors["phones"].unsqueeze(0).to("cpu")
    tones = tensors["tones"].unsqueeze(0).to("cpu")
    languages = tensors["languages"].unsqueeze(0).to("cpu")
    bert = tensors["bert"].unsqueeze(0).to("cpu")
    ja_bert = tensors["jaBert"].unsqueeze(0).to("cpu")
    lengths = torch.LongTensor([tensors["phones"].size(0)]).to("cpu")
    speaker = torch.LongTensor([1]).to("cpu")
    with torch.inference_mode():
        result = model.infer(
            phones,
            lengths,
            speaker,
            tones,
            languages,
            bert,
            ja_bert,
            sdp_ratio=config["sdpRatio"],
            noise_scale=config["noiseScale"],
            noise_scale_w=config["noiseScaleW"],
            length_scale=config["lengthScale"],
        )[0][0, 0]
    audio = np.ascontiguousarray(result.cpu().float().numpy(), dtype=np.float32)
    if audio.size == 0 or not np.all(np.isfinite(audio)):
        raise v8.V8Error("V10 Melo base waveform is invalid")
    return audio


def convert_tone_colour(
    base_path: Path,
    *,
    converter: Any,
    source_se: Any,
    target_se: Any,
) -> np.ndarray:
    result = converter.convert(
        str(base_path),
        source_se,
        target_se,
        output_path=None,
        tau=load_config()["generation"]["converterTau"],
    )
    audio = np.ascontiguousarray(np.asarray(result).reshape(-1), dtype=np.float32)
    if audio.size == 0 or not np.all(np.isfinite(audio)):
        raise v8.V8Error("V10 raw converter waveform is invalid")
    return audio


def audit_derivative(
    raw_converter_output: np.ndarray, separator_after: str
) -> tuple[np.ndarray, dict[str, Any]]:
    from scipy.signal import resample_poly

    config = load_config()["audio"]
    source = np.ascontiguousarray(raw_converter_output, dtype=np.float32)
    resampled = np.ascontiguousarray(
        resample_poly(
            source,
            config["auditSampleRateUpFactor"],
            config["auditSampleRateDownFactor"],
        ),
        dtype=np.float32,
    )
    if separator_after == "\n\n":
        pause_ms = config["authoredParagraphPauseMilliseconds"]
    elif separator_after == " ":
        pause_ms = config["authoredIntraParagraphPauseMilliseconds"]
    elif separator_after == "":
        pause_ms = config["authoredFinalPauseMilliseconds"]
    else:
        raise v8.V8Error("V10 utterance has an unsupported authored separator")
    pause_samples = round(config["frozenAuditSampleRate"] * pause_ms / 1000)
    derivative = resampled
    if pause_samples:
        derivative = np.concatenate(
            [resampled, np.zeros(pause_samples, dtype=np.float32)]
        )
    derivative = np.ascontiguousarray(derivative, dtype=np.float32)
    record = {
        "rawConverterSampleCount": int(source.size),
        "sampleRateConversion": {
            "sourceSampleRate": config["converterSampleRate"],
            "targetSampleRate": config["frozenAuditSampleRate"],
            "upFactor": config["auditSampleRateUpFactor"],
            "downFactor": config["auditSampleRateDownFactor"],
            "algorithm": "scipy.signal.resample_poly",
            "auditCompatibilityDerivativeOnly": True,
        },
        "retainedSampleCountBeforePause": int(resampled.size),
        "pauseMilliseconds": pause_ms,
        "pauseSamples": pause_samples,
        "processedSampleCount": int(derivative.size),
        "activityCropApplied": False,
        "edgeFadeApplied": False,
        "loudnessNormalizationApplied": False,
        "internalSilenceRemovalApplied": False,
        "speechTimeStretchApplied": False,
        "durationPaddingApplied": False,
        "onlyAuthoredPauseAppended": True,
    }
    return derivative, record


def float32_sha256(audio: np.ndarray) -> str:
    material = np.ascontiguousarray(audio, dtype="<f4")
    return hashlib.sha256(material.tobytes()).hexdigest()
