#!/usr/bin/env python3
"""Freeze a fail-closed pronunciation path for the exact V10 comparison.

This gate runs the pinned MeloTTS normalisers and BERT tokenizer over all
fourteen approved comparison utterances before any model weight is loaded.
Every lexical token must resolve to the hash-bound CMU dictionary or to the
small project pronunciation map.  The discarded g2p_en/NLTK fallback is never
imported, and an unknown token aborts the gate.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
from typing import Any

import pipeline as production
import v8_chatterbox_comparison as comparison
import v8_pipeline as v8
import v10_openvoice_v2_runtime_audit as runtime


SCRIPT_PATH = Path(__file__).absolute()
CONFIG_PATH = SCRIPT_PATH.with_name("v10-openvoice-pronunciations.json")
STATUS = "CODEX_V10_OPENVOICE_PRONUNCIATION_GATE_PASSED"
RECEIPT_NAME = "openvoice-v2-pronunciation-gate.v10.receipt.json"
EXPECTED_CRITICAL_WORDS = comparison.CRITICAL_PRONUNCIATION_WORDS
EXPECTED_REPRESENTATIVE_SHA256 = (
    "822786bfaa942aec932686929d2ece3a7122d5215db654862cad3e28d9a8cb62"
)
RUNTIME_RECEIPT = runtime.RUNTIME_ROOT / runtime.RECEIPT_NAME
MELO_ROOT = runtime.RUNTIME_ROOT / "source" / runtime.MELO_DIRECTORY
BERT_ROOT = runtime.SNAPSHOT_ROOT / "models/bertBaseUncased"
CMU_PATH = MELO_ROOT / "melo/text/cmudict.rep"
NORMALISER_PATHS = {
    "time": MELO_ROOT / "melo/text/english_utils/time_norm.py",
    "number": MELO_ROOT / "melo/text/english_utils/number_norm.py",
    "abbreviations": MELO_ROOT / "melo/text/english_utils/abbreviations.py",
    "english": MELO_ROOT / "melo/text/english.py",
    "symbols": MELO_ROOT / "melo/text/symbols.py",
}
PUNCTUATION = {"!", "?", "…", ",", ".", "'", "-", ":"}
ARPA = {
    "AA", "AE", "AH", "AO", "AW", "AY", "B", "CH", "D", "DH",
    "EH", "ER", "EY", "F", "G", "HH", "IH", "IY", "JH", "K", "L",
    "M", "N", "NG", "OW", "OY", "P", "R", "S", "SH", "T", "TH",
    "UH", "UW", "V", "W", "Y", "Z", "ZH",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _binding(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise v8.V8Error(f"required pronunciation input is unavailable: {path}")
    return {
        "path": str(path.absolute()),
        "bytes": path.stat().st_size,
        "sha256": _sha256(path),
    }


def _require_runtime() -> dict[str, Any]:
    receipt = production.load_json(RUNTIME_RECEIPT)
    if (
        receipt.get("status") != runtime.STATUS
        or receipt.get("modelWeightsLoaded") is not False
        or receipt.get("synthesisExecuted") is not False
        or receipt.get("offlineImportProbe", {}).get("passesOfflineImportProbe")
        is not True
    ):
        raise v8.V8Error("V10 runtime audit does not open pronunciation work")
    return v8.file_binding(RUNTIME_RECEIPT)


def load_config() -> dict[str, Any]:
    config = production.load_json(CONFIG_PATH)
    if (
        config.get("status")
        != "CODEX_V10_OPENVOICE_ENGLISH_PRONUNCIATIONS_FROZEN"
        or config.get("locale") != "en-GB"
        or config.get("tokenizerRevision")
        != "86b5e0934494bd15c9632b12f734a8a67f723594"
        or tuple(config.get("criticalRegister", {})) != EXPECTED_CRITICAL_WORDS
        or config.get("policy", {}).get("unknownTokenIsFatal") is not True
        or config.get("policy", {}).get("g2pEnImportPermitted") is not False
        or config.get("policy", {}).get("nltkImportPermitted") is not False
        or config.get("policy", {}).get("networkFallbackPermitted") is not False
    ):
        raise v8.V8Error("V10 pronunciation configuration drifted")
    return config


def _read_cmudict() -> dict[str, list[list[str]]]:
    dictionary: dict[str, list[list[str]]] = {}
    lines = CMU_PATH.read_text(encoding="utf-8").splitlines()
    if len(lines) < 49 or not lines[48].startswith("!EXCLAMATION-POINT  "):
        raise v8.V8Error("pinned Melo CMU dictionary header drifted")
    for line in lines[48:]:
        parts = line.split("  ")
        if len(parts) != 2:
            raise v8.V8Error("pinned Melo CMU dictionary line is malformed")
        word = parts[0]
        base = word.split("(", 1)[0]
        phones = [item for item in parts[1].replace(" - ", " ").split()]
        dictionary.setdefault(base, []).append(phones)
    return dictionary


def _validate_phones(phones: list[str]) -> None:
    if not phones:
        raise v8.V8Error("empty project pronunciation is prohibited")
    for phone in phones:
        base = phone.rstrip("012")
        stress = phone[len(base):]
        if base not in ARPA or stress not in {"", "0", "1", "2"}:
            raise v8.V8Error(f"invalid ARPAbet phone in pronunciation map: {phone}")
        if stress and base not in {
            "AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY",
            "IH", "IY", "OW", "OY", "UH", "UW",
        }:
            raise v8.V8Error(f"stress marker attached to consonant: {phone}")


def _normalise(text: str) -> str:
    from melo.text.english_utils.abbreviations import expand_abbreviations
    from melo.text.english_utils.number_norm import normalize_numbers
    from melo.text.english_utils.time_norm import expand_time_english

    return expand_abbreviations(
        normalize_numbers(expand_time_english(text.lower()))
    )


def _wordpiece_groups(tokenizer: Any, text: str) -> list[dict[str, Any]]:
    pieces = tokenizer.tokenize(text)
    groups: list[list[str]] = []
    for piece in pieces:
        if piece == "[UNK]":
            raise v8.V8Error("pinned BERT tokenizer produced [UNK]")
        if not piece.startswith("#"):
            groups.append([piece])
        else:
            if not groups:
                raise v8.V8Error("orphan BERT continuation token")
            groups[-1].append(piece.replace("#", ""))
    return [
        {"token": "".join(group), "wordPieces": group, "wordPieceCount": len(group)}
        for group in groups
    ]


def _resolve_token(
    token: str,
    *,
    cmu: dict[str, list[list[str]]],
    overrides: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    if token in PUNCTUATION:
        return {"source": "meloPunctuation", "phones": [token]}
    if token in overrides:
        phones = overrides[token]["phones"]
        _validate_phones(phones)
        return {
            "source": "projectOverride",
            "phones": phones,
            "reason": overrides[token]["reason"],
        }
    entries = cmu.get(token.upper())
    if entries is None:
        raise v8.V8Error(
            f"unknown normalized token has no fail-closed pronunciation: {token}"
        )
    _validate_phones(entries[0])
    return {
        "source": "cmudict",
        "phones": entries[0],
        "cmuVariantCount": len(entries),
        "selectedVariant": 1,
    }


def pronunciation_material() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    from transformers import AutoTokenizer

    config = load_config()
    cmu = _read_cmudict()
    overrides = config["projectOverrides"]
    if set(overrides) != {"ad", "polis", "excommunication", "monasteries", "lepanto", "portuguese"}:
        raise v8.V8Error("V10 project pronunciation override inventory drifted")
    for item in overrides.values():
        _validate_phones(item["phones"])

    selected, representative = comparison._selected_material(v8.load_config())
    if (
        len(selected) != 14
        or representative["exactTextManifestSHA256"]
        != EXPECTED_REPRESENTATIVE_SHA256
    ):
        raise v8.V8Error("V10 representative utterances drifted")
    tokenizer = AutoTokenizer.from_pretrained(
        str(BERT_ROOT), local_files_only=True, use_fast=True
    )
    if tokenizer.name_or_path != str(BERT_ROOT):
        raise v8.V8Error("V10 tokenizer escaped the exact local path")

    records: list[dict[str, Any]] = []
    all_tokens: list[str] = []
    resolution_counts: Counter[str] = Counter()
    for utterance in selected:
        normalized = _normalise(utterance["text"])
        groups = _wordpiece_groups(tokenizer, normalized)
        resolved = []
        for group in groups:
            resolution = _resolve_token(
                group["token"], cmu=cmu, overrides=overrides
            )
            resolution_counts[resolution["source"]] += 1
            all_tokens.append(group["token"])
            resolved.append({**group, **resolution})
        records.append(
            {
                "utteranceID": utterance["utteranceID"],
                "exactText": utterance["text"],
                "exactTextSHA256": production.sha256_text(utterance["text"]),
                "normalizedText": normalized,
                "normalizedTextSHA256": production.sha256_text(normalized),
                "tokenCount": len(resolved),
                "tokens": resolved,
            }
        )

    critical_records = []
    for word, expected in config["criticalRegister"].items():
        tokens = expected["normalizedTokens"]
        if word == "1648":
            occurs = any("1648" in item["exactText"] for item in records)
            matches = any(
                all(token in [entry["token"] for entry in item["tokens"]] for token in tokens)
                for item in records
            )
        else:
            occurs = word in all_tokens
            matches = tokens == [word]
        resolutions = [
            _resolve_token(token, cmu=cmu, overrides=overrides)
            for token in tokens
        ]
        sources = {item["source"] for item in resolutions}
        declared = expected["source"]
        if declared == "cmudictAndPunctuation":
            source_matches = sources == {"cmudict", "meloPunctuation"}
        else:
            source_matches = sources == {declared}
        if not (occurs and matches and source_matches):
            raise v8.V8Error(f"critical pronunciation register drifted: {word}")
        critical_records.append(
            {
                "word": word,
                "normalizedTokens": tokens,
                "resolutions": resolutions,
                "occursInExactRepresentativeSet": True,
                "declarationMatchesResolvedSources": True,
            }
        )

    if "g2p_en" in sys.modules or "nltk" in sys.modules:
        raise v8.V8Error("discarded English pronunciation fallback was imported")
    summary = {
        "utteranceCount": len(records),
        "uniqueNormalizedTokenCount": len(set(all_tokens)),
        "normalizedTokenOccurrenceCount": len(all_tokens),
        "resolutionCounts": dict(sorted(resolution_counts.items())),
        "unknownTokenCount": 0,
        "criticalWordCount": len(critical_records),
        "allTokensResolvedBeforeModelLoad": True,
        "allCriticalWordsExplicitlyRegistered": True,
        "g2pEnImported": False,
        "nltkImported": False,
        "networkFallbackUsed": False,
    }
    return records, {"summary": summary, "criticalRegister": critical_records}


def gate(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("V10 pronunciation gate requires --offline")
    os.environ.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "DO_NOT_TRACK": "1",
            "CUDA_VISIBLE_DEVICES": "",
            "PYTORCH_ENABLE_MPS_FALLBACK": "0",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )
    sys.dont_write_bytecode = True
    socket.socket.connect = lambda *args, **kwargs: (_ for _ in ()).throw(
        RuntimeError("network access attempted during pronunciation gate")
    )
    socket.socket.connect_ex = socket.socket.connect
    socket.create_connection = socket.socket.connect
    output = v8.prepare_output(args.output, v8.load_config())
    runtime_receipt = _require_runtime()
    records, result = pronunciation_material()
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "configuration": v8.file_binding(CONFIG_PATH),
        "runtimeReceipt": runtime_receipt,
        "representativeSet": {
            "utteranceCount": 14,
            "exactTextManifestSHA256": EXPECTED_REPRESENTATIVE_SHA256,
        },
        "inputs": {
            "cmuDictionary": _binding(CMU_PATH),
            "normalisationAndSymbolSources": {
                key: _binding(path) for key, path in NORMALISER_PATHS.items()
            },
            "localTokenizerFiles": [
                _binding(path)
                for path in sorted(BERT_ROOT.iterdir())
                if path.is_file() and path.name in {
                    "config.json", "tokenizer.json", "tokenizer_config.json", "vocab.txt"
                }
            ],
        },
        "utterances": records,
        **result,
        "modelWeightsLoaded": False,
        "synthesisExecuted": False,
        "audioFilesCreated": 0,
        "representativeGateRun": False,
        "fullGenerationPermitted": False,
        "incrementalCostNOK": 0,
        "nextGate": (
            "Load the exact MeloTTS, BERT and OpenVoice converter weights on CPU "
            "through the same pronunciation adapter without rendering audio."
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
        receipt = gate(parse_args(sys.argv[1:] if argv is None else argv))
    except (OSError, RuntimeError, v8.V8Error, json.JSONDecodeError) as error:
        print(f"v10 pronunciation gate failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
