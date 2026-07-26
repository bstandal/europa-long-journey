#!/usr/bin/env python3
"""Render the exact frozen fourteen-by-two V10 comparison offline.

This command loads only the already-audited CPU runtime.  It performs one
deterministic MeloTTS inference and one OpenVoice conversion for each of the
fourteen approved utterances and two frozen references.  The raw 22.05 kHz
converter waveform is retained unchanged.  A separately labelled 24 kHz
derivative exists only so the unchanged V8 audit tools can read it; that
derivative receives the exact authored 30/120/0 ms boundary pause and nothing
else.  The command never opens full 203-by-two generation.
"""

from __future__ import annotations

import argparse
import gc
import json
import os
from pathlib import Path
import sys
import time
from typing import Any

import pipeline as production
import v8_chatterbox_comparison as comparison
import v8_pipeline as v8
import v10_openvoice_v2_adapter as adapter
import v10_openvoice_v2_model_load_probe as model_load
import v10_openvoice_v2_pronunciation_gate as pronunciation


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V10_OPENVOICE_FROZEN_14_BY_2_SYNTHESISED_NON_SHIPPING"
RECEIPT_NAME = "openvoice-v2-generation.v10.receipt.json"
MODEL_LOAD_RECEIPT = (
    v8.REPOSITORY_ROOT
    / "native/audio/narration/work/provisional-audit-v8/"
    "openvoice-v2-model-load-r1-2026-07-25/"
    "openvoice-v2-model-load.v10.receipt.json"
)


def _prerequisites() -> dict[str, Any]:
    method = adapter.load_config()
    load_receipt = production.load_json(MODEL_LOAD_RECEIPT)
    pronunciation_receipt = production.load_json(model_load.PRONUNCIATION_RECEIPT)
    if (
        load_receipt.get("status") != model_load.STATUS
        or load_receipt.get("script") != v8.file_binding(model_load.SCRIPT_PATH)
        or load_receipt.get("allRequiredWeightsLoaded") is not True
        or load_receipt.get("allModelsOnCPU") is not True
        or load_receipt.get("bothExactFrozenReferencesExtractedDirectly")
        is not True
        or load_receipt.get("synthesisExecuted") is not False
        or load_receipt.get("representativeGateRun") is not False
        or load_receipt.get("fullGenerationPermitted") is not False
        or pronunciation_receipt.get("status") != pronunciation.STATUS
        or pronunciation_receipt.get("summary", {}).get("unknownTokenCount") != 0
        or pronunciation_receipt.get("summary", {}).get("criticalWordCount") != 15
        or pronunciation_receipt.get("script")
        != v8.file_binding(pronunciation.SCRIPT_PATH)
        or pronunciation_receipt.get("configuration")
        != v8.file_binding(pronunciation.CONFIG_PATH)
        or method["comparison"]["requiredSynthesisCount"] != 28
    ):
        raise v8.V8Error("V10 14-by-2 generation prerequisite drifted")
    return {
        "modelLoadReceipt": v8.file_binding(MODEL_LOAD_RECEIPT),
        "pronunciationReceipt": v8.file_binding(model_load.PRONUNCIATION_RECEIPT),
        "methodConfiguration": v8.file_binding(adapter.CONFIG_PATH),
        "adapter": v8.file_binding(adapter.SCRIPT_PATH),
    }


def _utterance_material() -> list[dict[str, Any]]:
    pronunciation_receipt = production.load_json(model_load.PRONUNCIATION_RECEIPT)
    frozen = pronunciation_receipt["utterances"]
    selected, representative = comparison._selected_material(v8.load_config())
    if (
        len(frozen) != 14
        or len(selected) != 14
        or representative["exactTextManifestSHA256"]
        != pronunciation.EXPECTED_REPRESENTATIVE_SHA256
    ):
        raise v8.V8Error("V10 comparison utterance inventory drifted")
    records: list[dict[str, Any]] = []
    for source, lexical in zip(selected, frozen):
        if (
            source["utteranceID"] != lexical["utteranceID"]
            or source["text"] != lexical["exactText"]
            or source["textSHA256"] != lexical["exactTextSHA256"]
        ):
            raise v8.V8Error("V10 selected text and pronunciation receipt diverged")
        records.append(
            {
                **lexical,
                "order": source["order"],
                "segmentID": source["segmentID"],
                "separatorAfter": source["separatorAfter"],
                "normalizedWordCount": source["normalizedWordCount"],
            }
        )
    return records


def _public_utterance(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "utteranceID": item["utteranceID"],
        "order": item["order"],
        "segmentID": item["segmentID"],
        "separatorAfter": item["separatorAfter"],
        "exactTextSHA256": item["exactTextSHA256"],
        "normalizedTextSHA256": item["normalizedTextSHA256"],
        "normalizedWordCount": item["normalizedWordCount"],
    }


def generate(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("V10 comparison generation requires --offline")
    os.environ.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "DO_NOT_TRACK": "1",
            "CUDA_VISIBLE_DEVICES": "",
            "PYTORCH_ENABLE_MPS_FALLBACK": "0",
            "PYTHONDONTWRITEBYTECODE": "1",
            "OMP_NUM_THREADS": "1",
            "VECLIB_MAXIMUM_THREADS": "1",
        }
    )
    sys.dont_write_bytecode = True
    model_load._block_network()
    output = v8.prepare_output(args.output, v8.load_config())
    prerequisites = _prerequisites()
    utterances = _utterance_material()
    method = adapter.load_config()
    live, loaded_model_records = model_load.load_exact_models()
    melo_config = production.load_json(model_load.MELO_CONFIG)

    prepared: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for utterance in utterances:
        tensors, text_record = adapter.prepare_text(
            utterance,
            tokenizer=live["tokenizer"],
            bert_model=live["bert"],
            melo_config=melo_config,
        )
        prepared.append((tensors, text_record))

    candidates: list[dict[str, Any]] = []
    synthesis_count = 0
    audio_file_count = 0
    started = time.monotonic()
    for candidate_index, candidate_id in enumerate(
        method["speaker"]["referenceIDs"]
    ):
        candidate_root = output / candidate_id
        candidate_root.mkdir()
        utterance_records = []
        for utterance_index, (utterance, prepared_item) in enumerate(
            zip(utterances, prepared)
        ):
            tensors, text_record = prepared_item
            seed = adapter.generation_seed(candidate_index, utterance_index)
            utterance_started = time.monotonic()
            base = adapter.synthesize_base(tensors, model=live["melo"], seed=seed)
            base_path = candidate_root / f"{utterance['utteranceID']}.base-44100-f32.wav"
            production.write_float_wav(base_path, 44_100, base)
            raw = adapter.convert_tone_colour(
                base_path,
                converter=live["converter"],
                source_se=live["sourceSE"],
                target_se=live["targetSE"][candidate_id],
            )
            raw_path = candidate_root / f"{utterance['utteranceID']}.converter-22050-f32.wav"
            production.write_float_wav(raw_path, 22_050, raw)
            audit_audio, processing = adapter.audit_derivative(
                raw, utterance["separatorAfter"]
            )
            audit_path = candidate_root / f"{utterance['utteranceID']}.audit-24000-f32.wav"
            production.write_float_wav(audit_path, 24_000, audit_audio)
            elapsed = time.monotonic() - utterance_started
            utterance_records.append(
                {
                    "utterance": _public_utterance(utterance),
                    "exactTextInput": utterance["exactText"],
                    "generationSeed": seed,
                    "generationParameters": method["generation"],
                    "textPreparation": text_record,
                    "baseAudio": v8.file_binding(base_path),
                    "baseSampleCount": int(base.size),
                    "baseFloat32LESHA256": adapter.float32_sha256(base),
                    "rawConverterAudio": v8.file_binding(raw_path),
                    "rawConverterSampleCount": int(raw.size),
                    "rawConverterFloat32LESHA256": adapter.float32_sha256(raw),
                    "rawConverterWaveformModifiedBeforeWrite": False,
                    "auditAudio": v8.file_binding(audit_path),
                    "auditSampleCount": int(audit_audio.size),
                    "auditFloat32LESHA256": adapter.float32_sha256(audit_audio),
                    "auditProcessing": processing,
                    "synthesisElapsedSeconds": elapsed,
                    "oneDeterministicAttempt": True,
                }
            )
            synthesis_count += 1
            audio_file_count += 3
            print(
                f"V10 OpenVoice comparison {candidate_id} "
                f"{utterance['utteranceID']} ({synthesis_count}/28)",
                file=sys.stderr,
                flush=True,
            )
        candidates.append(
            {
                "candidateID": candidate_id,
                "targetSpeakerEmbedding": loaded_model_records[
                    "targetSpeakerEmbeddings"
                ][candidate_id],
                "utteranceRecords": utterance_records,
            }
        )
    if synthesis_count != 28 or audio_file_count != 84:
        raise v8.V8Error("V10 comparison generation did not complete 14 by 2")
    elapsed = time.monotonic() - started
    del live, prepared
    gc.collect()
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "prerequisites": prerequisites,
        "method": method,
        "loadedModels": loaded_model_records,
        "representativeSet": {
            "utteranceCountPerReference": 14,
            "referenceCount": 2,
            "requiredSynthesisCount": 28,
            "exactTextManifestSHA256": pronunciation.EXPECTED_REPRESENTATIVE_SHA256,
        },
        "candidates": candidates,
        "synthesisCount": synthesis_count,
        "audioFileCount": audio_file_count,
        "generationElapsedSeconds": elapsed,
        "rawConverterOutputsRetainedUnmodified": True,
        "auditDerivativesAreNonShipping": True,
        "postConversionActivityCropApplied": False,
        "postConversionEdgeFadeApplied": False,
        "postConversionLoudnessNormalizationApplied": False,
        "postConversionInternalSilenceRemovalApplied": False,
        "postConversionSpeechTimeStretchApplied": False,
        "postConversionDurationPaddingApplied": False,
        "onlyAuthoredBoundaryPausesAddedToAuditDerivative": True,
        "oneAttemptPerUtterance": True,
        "adaptiveParameterChoiceUsed": False,
        "runtimeNetworkUsed": False,
        "synthesisExecuted": True,
        "representativeGateRun": False,
        "fullGenerationPermitted": False,
        "completeMasterCount": 0,
        "candidatePromoted": False,
        "incrementalCostNOK": 0,
        "nextGate": (
            "Run the unchanged V8 identity, utterance, aggregate WER, critical "
            "word, silence and projected-duration thresholds for both references."
        ),
    }
    receipt_path = output / RECEIPT_NAME
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--offline", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        receipt = generate(parse_args(sys.argv[1:] if argv is None else argv))
    except (OSError, RuntimeError, v8.V8Error, json.JSONDecodeError) as error:
        print(f"v10 OpenVoice comparison generation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
