#!/usr/bin/env python3
"""Validate the terminal, non-shipping V11 VoxCPM2 evidence without synthesis."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
from typing import Any


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
WORK_ROOT = NARRATION_ROOT / "work/provisional-audit-v11"
RUNTIME_ROOT = WORK_ROOT / "voxcpm2-runtime-r4-origin-bytecode-2026-07-25"
REPRESENTATIVE_ROOT = WORK_ROOT / "voxcpm2-representative-r5-2026-07-25"

SNAPSHOT = (
    WORK_ROOT
    / "voxcpm2-exact-snapshot-r1-2026-07-25/voxcpm2-exact-snapshot.v11.receipt.json"
)
RUNTIME = RUNTIME_ROOT / "voxcpm2-runtime-audit.v11.receipt.json"
UNRECEIPTED_R4 = RUNTIME_ROOT / "voxcpm2-model-load-r4-harness-failure.json"
MODEL_LOAD = RUNTIME_ROOT / "voxcpm2-model-load-gate-r5.v11.receipt.json"
AUTHORISATION = REPRESENTATIVE_ROOT / "voxcpm2-synthesis-authorisation.v11.receipt.json"
FAILURE = REPRESENTATIVE_ROOT / "voxcpm2-representative-generation.failure.json"
INCOMPLETE = REPRESENTATIVE_ROOT / "voxcpm2-representative-incomplete-evidence.v11.json"
RAW_AUDIO = REPRESENTATIVE_ROOT / "audio/voice-a/v8-utterance-006/raw-48k-f32.wav"
AUDIT_AUDIO = REPRESENTATIVE_ROOT / "audio/voice-a/v8-utterance-006/audit-24k-f32.wav"

EXPECTED_FILES = {
    SNAPSHOT: (4828, "c28428d02595d9d2ee22c90ffede00105d42c713b07f8ebddcd572bf2e36af39"),
    RUNTIME: (232206, "c0f8e38a91b13bfca0bc33a52458a2ba69be10d1e6cdd1c4883923b722b5d019"),
    UNRECEIPTED_R4: (1619, "ea7791c82aef071df3a0a7c32e547b3be21497666bdc85435993acd9b26b54b8"),
    MODEL_LOAD: (45415, "197eeb401e5b4ee798f36908b3ec2a673b189043faab2414858c29326397fcba"),
    AUTHORISATION: (176093, "24495ec5cb5e723a21343c369123bce746f93c63bcca7e678231740348aba78f"),
    FAILURE: (652, "c9c85595279132a495edaa4b94f65d5b14cae1f69459a1b026ce0ce30db89b24"),
    INCOMPLETE: (2863, "0e947daaad78491da59f4bc6ec1d6f7a59c872c3675fc5736fcbbe4f123b577a"),
    RAW_AUDIO: (1413178, "8c325359d18add04c876c0d040121b021050670fd59ef1b535a904612824365f"),
    AUDIT_AUDIO: (638458, "5cb84b5a73a6d95a7227226c7dffe803a26cdb76dc25e1766cf5521fc569292e"),
}

EXPECTED_REPRESENTATIVE_TREE = {
    "audio/voice-a/v8-utterance-006/audit-24k-f32.wav",
    "audio/voice-a/v8-utterance-006/raw-48k-f32.wav",
    "voxcpm2-representative-generation.failure.json",
    "voxcpm2-representative-incomplete-evidence.v11.json",
    "voxcpm2-synthesis-authorisation.v11.receipt.json",
}
EXPECTED_CACHE_FILE_COUNT = 46
EXPECTED_CACHE_BYTES = 2_192_768
EXPECTED_CACHE_INVENTORY_SHA256 = (
    "b6d912c20ef6c522bb8776babcd9f6ec667fb36c9060d8ec4054413548ea1486"
)


class TerminalEvidenceError(RuntimeError):
    """Raised when the closed V11 authority or its negative evidence drifts."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise TerminalEvidenceError(f"cannot load terminal V11 evidence: {path}") from error


def _require_exact_files() -> None:
    for path, (size, digest) in EXPECTED_FILES.items():
        if not path.is_file() or path.stat().st_size != size or _sha256(path) != digest:
            raise TerminalEvidenceError(f"terminal V11 evidence bytes drifted: {path}")

    tree = {
        path.relative_to(REPRESENTATIVE_ROOT).as_posix()
        for path in REPRESENTATIVE_ROOT.rglob("*")
        if path.is_file()
    }
    if tree != EXPECTED_REPRESENTATIVE_TREE:
        raise TerminalEvidenceError(
            "V11 representative tree changed or acquired an unauthorised job receipt"
        )


def _wav_format(path: Path) -> dict[str, int]:
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise TerminalEvidenceError(f"invalid RIFF/WAVE evidence: {path}")
    offset = 12
    fmt: tuple[int, int, int, int] | None = None
    data_bytes: int | None = None
    while offset + 8 <= len(data):
        chunk_id = data[offset : offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        payload = offset + 8
        end = payload + chunk_size
        if end > len(data):
            raise TerminalEvidenceError(f"truncated WAV evidence: {path}")
        if chunk_id == b"fmt " and chunk_size >= 16:
            format_tag, channels, sample_rate, _, _, bits = struct.unpack_from(
                "<HHIIHH", data, payload
            )
            fmt = (format_tag, channels, sample_rate, bits)
        elif chunk_id == b"data":
            data_bytes = chunk_size
        offset = end + (chunk_size & 1)
    if fmt is None or data_bytes is None:
        raise TerminalEvidenceError(f"WAV evidence lacks fmt or data: {path}")
    format_tag, channels, sample_rate, bits = fmt
    if format_tag != 3 or channels != 1 or bits != 32 or data_bytes % 4:
        raise TerminalEvidenceError(f"WAV evidence is not mono float32: {path}")
    return {
        "sampleRate": sample_rate,
        "channels": channels,
        "bits": bits,
        "sampleCount": data_bytes // 4,
    }


def _cache_inventory() -> dict[str, int | str]:
    files = sorted(
        (
            path
            for path in RUNTIME_ROOT.rglob("*")
            if path.is_file() and path.suffix in {".nbi", ".nbc"}
        ),
        key=lambda path: path.relative_to(RUNTIME_ROOT).as_posix().encode("utf-8"),
    )
    canonical = bytearray()
    total_bytes = 0
    for path in files:
        size = path.stat().st_size
        total_bytes += size
        canonical.extend(
            (
                f"{path.relative_to(RUNTIME_ROOT).as_posix()}\t{size}\t{_sha256(path)}\n"
            ).encode("utf-8")
        )
    return {
        "fileCount": len(files),
        "bytes": total_bytes,
        "sha256": hashlib.sha256(canonical).hexdigest(),
    }


def validate() -> dict[str, Any]:
    _require_exact_files()

    unreceipted_r4 = _load(UNRECEIPTED_R4)
    if (
        unreceipted_r4.get("status") != "HARNESS_POST_RUN_FAILURE_NO_RECEIPT"
        or unreceipted_r4.get("modelLoadAttempted") is not True
        or unreceipted_r4.get("workerProcessCompleted") is not True
        or unreceipted_r4.get("workerResultPersisted") is not False
        or unreceipted_r4.get("passEvidencePermitted") is not False
        or unreceipted_r4.get("promptEncoded") is not False
        or unreceipted_r4.get("generationMethodCalled") is not False
        or unreceipted_r4.get("generatedAudio") is not False
    ):
        raise TerminalEvidenceError("unreceipted R4 load was promoted into pass evidence")

    model_load = _load(MODEL_LOAD)
    if (
        model_load.get("status")
        != "CODEX_V11_VOXCPM2_R5_BYTE_RUNTIME_MODEL_LOAD_GATE_VERIFIED"
        or model_load.get("modelLoadReplayID") != "R5"
        or model_load.get("modelLoad", {}).get("architecture") != "VoxCPM2Model"
        or model_load.get("modelLoad", {}).get("parameterCount") != 2_384_218_498
        or model_load.get("modelLoad", {}).get("networkAttemptCount") != 0
        or model_load.get("modelLoad", {}).get("promptEncoded") is not False
        or model_load.get("modelLoad", {}).get("generationMethodCalled") is not False
        or model_load.get("generatedAudio") is not False
        or model_load.get("comparisonSynthesisPermitted") is not True
        or model_load.get("fullGenerationPermitted") is not False
        or model_load.get("priorUnreceiptedR4LoadUsedAsPassEvidence") is not False
    ):
        raise TerminalEvidenceError("V11 model-load authority no longer proves the frozen gate")

    failure = _load(FAILURE)
    if (
        failure.get("status")
        != "CODEX_V11_VOXCPM2_REPRESENTATIVE_STOPPED_AT_FIRST_DEVIATION"
        or failure.get("completedJobReceipts") != []
        or failure.get("completedJobCount") != 0
        or failure.get("retryPermitted") is not False
        or failure.get("full203By2GenerationStarted") is not False
        or failure.get("nonShipping") is not True
    ):
        raise TerminalEvidenceError("V11 failure receipt was promoted or weakened")

    incomplete = _load(INCOMPLETE)
    expected_terminal_flags = {
        "authoritativeCompletedJobCount": 0,
        "remainingAuthorisedJobCount": 27,
        "resumePermitted": False,
        "retryPermitted": False,
        "regenerationPermitted": False,
        "representativeMachineAuditRun": False,
        "anonymousReviewPackageBuilt": False,
        "full203By2GenerationStarted": False,
        "editorChoiceRequested": False,
        "generatedAudioArtifactsPresent": True,
        "nonShipping": True,
        "shippingPermitted": False,
        "incrementalCostNOK": 0,
    }
    if (
        incomplete.get("status")
        != "CODEX_V11_VOXCPM2_REPRESENTATIVE_INCOMPLETE_NO_RESUME_AUTHORITY"
        or any(incomplete.get(key) != value for key, value in expected_terminal_flags.items())
        or incomplete.get("attemptedButUnreceiptedJob", {}).get(
            "authoritativeJobReceiptPresent"
        )
        is not False
        or incomplete.get("attemptedButUnreceiptedJob", {}).get("countsAsCompleted")
        is not False
    ):
        raise TerminalEvidenceError("V11 incomplete evidence no longer fails closed")

    raw = _wav_format(RAW_AUDIO)
    audit = _wav_format(AUDIT_AUDIO)
    if raw != {"sampleRate": 48_000, "channels": 1, "bits": 32, "sampleCount": 353_280}:
        raise TerminalEvidenceError("V11 raw attempted audio format drifted")
    if audit != {"sampleRate": 24_000, "channels": 1, "bits": 32, "sampleCount": 159_600}:
        raise TerminalEvidenceError("V11 audit attempted audio format drifted")

    cache = _cache_inventory()
    if cache != {
        "fileCount": EXPECTED_CACHE_FILE_COUNT,
        "bytes": EXPECTED_CACHE_BYTES,
        "sha256": EXPECTED_CACHE_INVENTORY_SHA256,
    }:
        raise TerminalEvidenceError("V11 escaped Numba-cache evidence drifted")
    deviation = incomplete.get("firstDeviation", {})
    if (
        deviation.get("newNumbaCacheFileCount") != EXPECTED_CACHE_FILE_COUNT
        or deviation.get("newNumbaCacheBytes") != EXPECTED_CACHE_BYTES
        or deviation.get("newNumbaCacheInventorySHA256")
        != "4e76013c49e9b7400770a3b607b79f02ace5a2b02b1129d18bd815f4f97cff96"
    ):
        raise TerminalEvidenceError("V11 recorded cache deviation drifted")

    return {
        "status": incomplete["status"],
        "modelLoadGate": "PASS",
        "representativeGeneration": "STOPPED_AT_FIRST_DEVIATION",
        "completedJobCount": 0,
        "retryPermitted": False,
        "resumePermitted": False,
        "generatedAudioArtifactsPresent": True,
        "shippingPermitted": False,
        "cacheEvidence": cache,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate",))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = validate()
    except TerminalEvidenceError as error:
        print(f"V11 terminal evidence validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
