#!/usr/bin/env python3
"""Load every exact V10 model byte on CPU without synthesising speech."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
from typing import Any

import numpy as np

import pipeline as production
import v8_pipeline as v8
import v10_openvoice_v2_preflight as preflight
import v10_openvoice_v2_pronunciation_gate as pronunciation
import v10_openvoice_v2_runtime_audit as runtime


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V10_OPENVOICE_EXACT_CPU_MODEL_LOAD_PASSED"
RECEIPT_NAME = "openvoice-v2-model-load.v10.receipt.json"
PRONUNCIATION_RECEIPT = (
    v8.REPOSITORY_ROOT
    / "native/audio/narration/work/provisional-audit-v8/"
    "openvoice-v2-pronunciation-gate-r1-2026-07-25/"
    "openvoice-v2-pronunciation-gate.v10.receipt.json"
)
PREFLIGHT_RECEIPT = (
    v8.REPOSITORY_ROOT
    / "native/audio/narration/work/provisional-audit-v8/"
    "openvoice-v2-primary-source-gate-r1-2026-07-25/"
    "openvoice-v2-primary-source-gate.v10.receipt.json"
)
MODEL_ROOT = runtime.SNAPSHOT_ROOT / "models"
MELO_CONFIG = MODEL_ROOT / "meloEnglish/config.json"
MELO_CHECKPOINT = MODEL_ROOT / "meloEnglish/checkpoint.pth"
BERT_ROOT = MODEL_ROOT / "bertBaseUncased"
CONVERTER_CONFIG = MODEL_ROOT / "openVoiceV2/converter/config.json"
CONVERTER_CHECKPOINT = MODEL_ROOT / "openVoiceV2/converter/checkpoint.pth"
SOURCE_SE = MODEL_ROOT / "openVoiceV2/base_speakers/ses/en-br.pth"


def _block_network() -> None:
    def blocked(*args: Any, **kwargs: Any) -> Any:
        del args, kwargs
        raise RuntimeError("network access attempted during V10 model load")

    socket.socket.connect = blocked
    socket.socket.connect_ex = blocked
    socket.create_connection = blocked


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _tensor_record(tensor: Any) -> dict[str, Any]:
    import torch

    if not isinstance(tensor, torch.Tensor):
        raise v8.V8Error("expected a model tensor")
    material = tensor.detach().cpu().contiguous()
    if not torch.isfinite(material).all():
        raise v8.V8Error("model tensor contains a non-finite value")
    raw = np.ascontiguousarray(material.float().numpy(), dtype="<f4").tobytes()
    return {
        "shape": list(material.shape),
        "dtype": str(material.dtype),
        "device": material.device.type,
        "float32LESHA256": hashlib.sha256(raw).hexdigest(),
    }


def _model_record(model: Any) -> dict[str, Any]:
    import torch

    parameters = list(model.parameters())
    buffers = list(model.buffers())
    tensors = [*parameters, *buffers]
    if not tensors or any(item.device.type != "cpu" for item in tensors):
        raise v8.V8Error("V10 model escaped the CPU")
    if any(not torch.isfinite(item).all() for item in tensors):
        raise v8.V8Error("V10 model contains a non-finite tensor")
    return {
        "parameterCount": sum(item.numel() for item in parameters),
        "bufferElementCount": sum(item.numel() for item in buffers),
        "parameterTensorCount": len(parameters),
        "bufferTensorCount": len(buffers),
        "allParametersAndBuffersOnCPU": True,
        "allParametersAndBuffersFinite": True,
        "evaluationMode": model.training is False,
    }


def _reference_bindings() -> dict[str, dict[str, Any]]:
    document = production.load_json(PREFLIGHT_RECEIPT)
    if (
        document.get("status") != preflight.STATUS
        or document.get("candidateGate", {}).get("passesPrimarySourceGate")
        is not True
    ):
        raise v8.V8Error("V10 primary-source preflight drifted")
    references = document["frozenFourteenByTwoComparison"]["references"]
    if tuple(references) != ("voice-candidate-05", "voice-candidate-06"):
        raise v8.V8Error("V10 reference inventory drifted")
    for item in references.values():
        path = Path(item["file"]["path"])
        if (
            not path.is_file()
            or path.stat().st_size != item["file"]["bytes"]
            or _sha256(path) != item["file"]["sha256"]
        ):
            raise v8.V8Error("V10 frozen reference bytes drifted")
    return references


def _prerequisites() -> dict[str, Any]:
    runtime_receipt = production.load_json(runtime.RUNTIME_ROOT / runtime.RECEIPT_NAME)
    pronunciation_receipt = production.load_json(PRONUNCIATION_RECEIPT)
    if (
        runtime_receipt.get("status") != runtime.STATUS
        or runtime_receipt.get("modelWeightsLoaded") is not False
        or runtime_receipt.get("synthesisExecuted") is not False
        or runtime_receipt.get("script") != v8.file_binding(runtime.SCRIPT_PATH)
        or pronunciation_receipt.get("status") != pronunciation.STATUS
        or pronunciation_receipt.get("summary", {}).get("unknownTokenCount") != 0
        or pronunciation_receipt.get("summary", {}).get(
            "allCriticalWordsExplicitlyRegistered"
        )
        is not True
        or pronunciation_receipt.get("modelWeightsLoaded") is not False
        or pronunciation_receipt.get("script")
        != v8.file_binding(pronunciation.SCRIPT_PATH)
        or pronunciation_receipt.get("configuration")
        != v8.file_binding(pronunciation.CONFIG_PATH)
    ):
        raise v8.V8Error("V10 runtime or pronunciation prerequisite drifted")
    snapshot = runtime._verify_snapshot()
    return {
        "runtimeReceipt": v8.file_binding(runtime.RUNTIME_ROOT / runtime.RECEIPT_NAME),
        "pronunciationReceipt": v8.file_binding(PRONUNCIATION_RECEIPT),
        "primarySourceReceipt": v8.file_binding(PREFLIGHT_RECEIPT),
        "snapshot": snapshot,
    }


def load_exact_models() -> tuple[dict[str, Any], dict[str, Any]]:
    import torch
    from transformers import AutoModelForMaskedLM, AutoTokenizer
    from melo.models import SynthesizerTrn as MeloSynthesizer
    from openvoice.api import OpenVoiceBaseClass, ToneColorConverter

    torch.manual_seed(10_000_000)
    torch.use_deterministic_algorithms(True)
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)

    melo_config = production.load_json(MELO_CONFIG)
    if (
        melo_config["data"]["sampling_rate"] != 44_100
        or melo_config["data"]["spk2id"].get("EN-BR") != 1
        or melo_config["data"].get("add_blank") is not True
        or melo_config.get("num_tones") != 16
        or melo_config.get("num_languages") != 10
    ):
        raise v8.V8Error("V10 Melo configuration drifted")
    melo = MeloSynthesizer(
        len(melo_config["symbols"]),
        melo_config["data"]["filter_length"] // 2 + 1,
        melo_config["train"]["segment_size"]
        // melo_config["data"]["hop_length"],
        n_speakers=melo_config["data"]["n_speakers"],
        num_tones=melo_config["num_tones"],
        num_languages=melo_config["num_languages"],
        **melo_config["model"],
    ).to("cpu")
    checkpoint = torch.load(MELO_CHECKPOINT, map_location="cpu")
    melo.load_state_dict(checkpoint["model"], strict=True)
    melo.eval()
    del checkpoint

    tokenizer = AutoTokenizer.from_pretrained(
        str(BERT_ROOT), local_files_only=True, use_fast=True
    )
    bert, bert_loading = AutoModelForMaskedLM.from_pretrained(
        str(BERT_ROOT),
        local_files_only=True,
        use_safetensors=True,
        output_loading_info=True,
    )
    expected_unused_bert_keys = [
        "cls.seq_relationship.bias",
        "cls.seq_relationship.weight",
    ]
    if (
        sorted(bert_loading["unexpected_keys"]) != expected_unused_bert_keys
        or bert_loading["missing_keys"]
        or bert_loading["mismatched_keys"]
        or bert_loading["error_msgs"]
    ):
        raise v8.V8Error("V10 official MaskedLM loading semantics drifted")
    bert = bert.to("cpu")
    bert.eval()

    # The pinned official ToneColorConverter forwards enable_watermark to its
    # base constructor even though the base does not accept that keyword.  The
    # adapter therefore performs the same base initialisation explicitly and
    # sets the documented disabled-watermark state.  extract_se, convert and
    # the converter model implementation remain the exact official methods.
    converter = ToneColorConverter.__new__(ToneColorConverter)
    OpenVoiceBaseClass.__init__(converter, str(CONVERTER_CONFIG), device="cpu")
    converter.watermark_model = None
    converter.version = getattr(converter.hps, "_version_", "v1")
    converter_checkpoint = torch.load(CONVERTER_CHECKPOINT, map_location="cpu")
    converter.model.load_state_dict(converter_checkpoint["model"], strict=True)
    converter.model.eval()
    del converter_checkpoint
    source_se = torch.load(SOURCE_SE, map_location="cpu").to("cpu")

    references = _reference_bindings()
    target_embeddings = {
        candidate_id: converter.extract_se(item["file"]["path"])
        for candidate_id, item in references.items()
    }
    records = {
        "meloTTS": {
            "config": v8.file_binding(MELO_CONFIG),
            "checkpoint": v8.file_binding(MELO_CHECKPOINT),
            **_model_record(melo),
        },
        "bertBaseUncased": {
            "model": v8.file_binding(BERT_ROOT / "model.safetensors"),
            "tokenizerFileCount": 3,
            "tokenizerClass": tokenizer.__class__.__name__,
            "officialLoaderClass": "AutoModelForMaskedLM",
            "intentionallyUnusedPretrainingHeadKeys": expected_unused_bert_keys,
            "missingRequiredKeys": [],
            "mismatchedKeys": [],
            **_model_record(bert),
        },
        "openVoiceToneColorConverter": {
            "config": v8.file_binding(CONVERTER_CONFIG),
            "checkpoint": v8.file_binding(CONVERTER_CHECKPOINT),
            "watermarkRuntimeEnabled": converter.watermark_model is not None,
            "constructorAdapter": (
                "Explicit OpenVoiceBaseClass initialisation avoids the pinned "
                "constructor's forwarding of enable_watermark; converter methods "
                "and model code are unchanged."
            ),
            **_model_record(converter.model),
        },
        "sourceSpeakerEmbedding": {
            "file": v8.file_binding(SOURCE_SE),
            "tensor": _tensor_record(source_se),
        },
        "targetSpeakerEmbeddings": {
            candidate_id: {
                "reference": references[candidate_id],
                "tensor": _tensor_record(tensor),
            }
            for candidate_id, tensor in target_embeddings.items()
        },
    }
    live = {
        "melo": melo,
        "bert": bert,
        "tokenizer": tokenizer,
        "converter": converter,
        "sourceSE": source_se,
        "targetSE": target_embeddings,
    }
    return live, records


def probe(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("V10 model load probe requires --offline")
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
    _block_network()
    output = v8.prepare_output(args.output, v8.load_config())
    prerequisites = _prerequisites()
    models, records = load_exact_models()
    del models
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "prerequisites": prerequisites,
        "device": "cpu",
        "deterministicAlgorithmsRequired": True,
        "threadCount": 1,
        "models": records,
        "allExactModelFilesOpened": True,
        "allRequiredWeightsLoaded": True,
        "bertPretrainingHeadExcludedByOfficialMaskedLMLoader": True,
        "allModelsOnCPU": True,
        "bothExactFrozenReferencesExtractedDirectly": True,
        "standardGetSeHelperUsed": False,
        "runtimeNetworkPermitted": False,
        "runtimeNetworkUsed": False,
        "modelWeightsLoaded": True,
        "synthesisExecuted": False,
        "audioFilesCreated": 0,
        "representativeGateRun": False,
        "fullGenerationPermitted": False,
        "incrementalCostNOK": 0,
        "nextGate": (
            "Render exactly fourteen approved utterances once for each frozen "
            "reference with fixed parameters and run the unchanged V8 gates."
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
        receipt = probe(parse_args(sys.argv[1:] if argv is None else argv))
    except (OSError, RuntimeError, v8.V8Error, json.JSONDecodeError) as error:
        print(f"v10 exact CPU model load failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
