#!/usr/bin/env python3
"""Generate the authorised VoxCPM2 V11 14-by-2 set exactly once."""

from __future__ import annotations

import gc
import hashlib
import json
import os
from pathlib import Path
import random
import socket
import sys
import time
from typing import Any

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v8_chatterbox_comparison as frozen_audit
import v8_pipeline as v8
import v11_voxcpm2_runtime_audit as runtime
import v11_voxcpm2_method as method
import v11_voxcpm2_synthesis_authorization as authorization


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V11_VOXCPM2_REPRESENTATIVE_14_BY_2_GENERATED_NON_SHIPPING"
RECEIPT_PATH = authorization.OUTPUT_ROOT / "voxcpm2-representative-generation.v11.receipt.json"
FAILURE_PATH = authorization.OUTPUT_ROOT / "voxcpm2-representative-generation.failure.json"
MODEL_ROOT = authorization.snapshot.SNAPSHOT_ROOT / "model"
SOURCE_ROOT = runtime.SOURCE_ROOT / runtime.SOURCE_DIRECTORY / "src"
LM_STEP_OUTPUT_SAMPLES = 7_680
FROZEN_V8_TOKEN_CAP = 384


class GenerationError(RuntimeError):
    """Raised on the first deviation in the one-take representative run."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _binding(path: Path) -> dict[str, Any]:
    return {
        "path": str(path.absolute()),
        "bytes": path.stat().st_size,
        "sha256": _sha256(path),
    }


def _write_json_verified(path: Path, value: dict[str, Any]) -> dict[str, Any]:
    payload = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    path.write_bytes(payload)
    reread = path.read_bytes()
    if reread != payload or json.loads(reread) != value:
        raise GenerationError(f"V11 durable JSON reread failed: {path}")
    return _binding(path)


def _write_float_wav_once(path: Path, sample_rate: int, audio: np.ndarray) -> dict[str, Any]:
    if path.exists() or path.with_suffix(path.suffix + ".partial").exists():
        raise GenerationError(f"V11 one-take output path already exists: {path}")
    partial = path.with_suffix(path.suffix + ".partial")
    wavfile.write(partial, sample_rate, np.ascontiguousarray(audio, dtype=np.float32))
    actual_rate, reread = wavfile.read(partial)
    if (
        actual_rate != sample_rate
        or reread.dtype != np.float32
        or reread.ndim != 1
        or reread.shape != audio.shape
        or not np.array_equal(reread, audio)
    ):
        raise GenerationError(f"V11 written waveform reread drifted: {partial}")
    os.replace(partial, path)
    return {
        **_binding(path),
        "sampleRate": sample_rate,
        "channels": 1,
        "sampleRepresentation": "float32",
        "sampleCount": int(audio.size),
        "durationSeconds": float(audio.size / sample_rate),
        "float32LESHA256": v5.native_float32_sha256(audio),
    }


def _model_contract(model: Any) -> dict[str, Any]:
    parameters = list(model.tts_model.parameters())
    return {
        "architecture": type(model.tts_model).__name__,
        "runtimeDevice": model.tts_model.device,
        "configurationDtype": model.tts_model.config.dtype,
        "parameterDevices": sorted({item.device.type for item in parameters}),
        "floatingParameterDtypes": sorted(
            {
                str(item.dtype).removeprefix("torch.")
                for item in parameters
                if item.is_floating_point()
            }
        ),
        "parameterCount": sum(item.numel() for item in parameters),
        "encodeSampleRate": model.tts_model._encode_sample_rate,
        "outputSampleRate": model.tts_model.sample_rate,
        "modelTraining": model.tts_model.training,
        "denoiserLoaded": model.denoiser is not None,
        "optimisationEnabled": False,
    }


def _validate_model_contract(contract: dict[str, Any]) -> None:
    expected = {
        "architecture": "VoxCPM2Model",
        "runtimeDevice": "mps",
        "configurationDtype": "float32",
        "parameterDevices": ["mps"],
        "floatingParameterDtypes": ["float32"],
        "parameterCount": 2_384_218_498,
        "encodeSampleRate": 16_000,
        "outputSampleRate": 48_000,
        "modelTraining": False,
        "denoiserLoaded": False,
        "optimisationEnabled": False,
    }
    if contract != expected:
        raise GenerationError(f"V11 synthesis model contract drifted: {contract}")


def _generation_authority() -> tuple[dict[str, Any], dict[str, Any]]:
    if not authorization.RECEIPT_PATH.is_file():
        raise GenerationError("V11 synthesis authorisation receipt is unavailable")
    receipt = json.loads(authorization.RECEIPT_PATH.read_text(encoding="utf-8"))
    expected = authorization.build_authorization_document()
    if receipt != expected:
        raise GenerationError("V11 synthesis authorisation receipt drifted")
    if receipt.get("synthesisPermitted") is not True or receipt.get("jobCount") != 28:
        raise GenerationError("V11 synthesis authorisation does not open 28 jobs")
    if _binding(SCRIPT_PATH) != receipt["synthesisScript"]:
        raise GenerationError("V11 synthesis script changed after authorisation")
    return receipt, _binding(authorization.RECEIPT_PATH)


def _block_network() -> list[str]:
    attempts: list[str] = []

    def blocked(*args: Any, **kwargs: Any) -> Any:
        attempts.append("socket")
        raise RuntimeError("network access attempted during V11 synthesis")

    socket.socket.connect = blocked
    socket.socket.connect_ex = blocked
    socket.create_connection = blocked
    socket.getaddrinfo = blocked
    return attempts


def generate() -> dict[str, Any]:
    authority, authority_binding = _generation_authority()
    if RECEIPT_PATH.exists() or FAILURE_PATH.exists():
        raise GenerationError("V11 representative run already has a terminal receipt")
    forbidden = sorted(authorization.OUTPUT_ROOT.rglob("*.wav")) + sorted(
        authorization.OUTPUT_ROOT.rglob("*.job.json")
    )
    if forbidden:
        raise GenerationError("V11 one-take output root is not pristine")

    attempts = _block_network()
    os.environ.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "DO_NOT_TRACK": "1",
            "NO_PROXY": "*",
            "TOKENIZERS_PARALLELISM": "false",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )
    bytecode_before = runtime.bytecode_cache_gate("representative-generation-before-model-load")
    import torch
    from voxcpm import VoxCPM

    if sys.version.split()[0] != "3.11.15" or torch.__version__ != "2.10.0":
        raise GenerationError("V11 exact synthesis runtime drifted")
    if not torch.backends.mps.is_available():
        raise GenerationError("V11 synthesis MPS is unavailable")
    model = VoxCPM(
        voxcpm_model_path=str(MODEL_ROOT),
        zipenhancer_model_path=None,
        enable_denoiser=False,
        optimize=False,
        device="mps",
        lora_config=None,
        lora_weights_path=None,
    )
    contract = _model_contract(model)
    _validate_model_contract(contract)
    if attempts:
        raise GenerationError("V11 model load attempted network access")

    transcript = Path(authority["transcript"]["path"]).read_text(encoding="utf-8")
    v6_config = v6.load_config()
    records: list[dict[str, Any]] = []
    generate_call_count = 0
    started = time.monotonic()
    for job in authority["jobs"]:
        job_id = job["jobID"]
        before = runtime.bytecode_cache_gate(f"{job_id}-before")
        if _model_contract(model) != contract:
            raise GenerationError(f"V11 model contract changed before {job_id}")
        reference_path = Path(job["reference"]["path"])
        kwargs = method.generation_kwargs(
            reference_path, transcript, job["exactTextInput"]
        )
        if kwargs != job["generationArguments"]:
            raise GenerationError(f"V11 generation arguments drifted: {job_id}")
        seed = job["seed"]
        random.seed(seed)
        np.random.seed(seed % (2**32))
        torch.manual_seed(seed)
        job_started = time.monotonic()
        generate_call_count += 1
        result = model.generate(**kwargs)
        torch.mps.synchronize()
        source = np.asarray(result)
        if (
            source.dtype != np.float32
            or source.ndim != 1
            or source.size == 0
            or not np.all(np.isfinite(source))
        ):
            raise GenerationError(f"V11 model returned invalid PCM: {job_id}")
        raw = np.ascontiguousarray(source, dtype=np.float32)
        derived_steps = (raw.size + LM_STEP_OUTPUT_SAMPLES - 1) // LM_STEP_OUTPUT_SAMPLES
        if derived_steps >= FROZEN_V8_TOKEN_CAP:
            raise GenerationError(f"V11 frozen token ceiling failed: {job_id}")

        raw_path = Path(job["rawAudioPath"])
        audit_path = Path(job["auditAudioPath"])
        raw_path.parent.mkdir(parents=True, exist_ok=False)
        raw_binding = _write_float_wav_once(raw_path, 48_000, raw)
        downsampled = np.ascontiguousarray(
            resample_poly(raw, 1, 2), dtype=np.float32
        )
        audit_audio, processing = v6.process_utterance_audio(
            downsampled,
            sample_rate=24_000,
            separator_after=job["separatorAfter"],
            config=v6_config,
            normalized_word_count=None,
        )
        audit_binding = _write_float_wav_once(audit_path, 24_000, audit_audio)
        after = runtime.bytecode_cache_gate(f"{job_id}-after")
        if _model_contract(model) != contract:
            raise GenerationError(f"V11 model contract changed after {job_id}")
        if attempts:
            raise GenerationError(f"V11 synthesis attempted network access: {job_id}")
        record = {
            "job": job,
            "oneModelGenerateCall": True,
            "generateCallOrdinal": generate_call_count,
            "generationSeconds": time.monotonic() - job_started,
            "rawAudio": raw_binding,
            "auditAudio": audit_binding,
            "auditProcessing": {
                **processing,
                "sourceSampleRate": 48_000,
                "auditSampleRate": 24_000,
                "resampleAlgorithm": "scipy.signal.resample_poly",
                "resampleUpFactor": 1,
                "resampleDownFactor": 2,
                "internalSilenceRemovalApplied": False,
                "speechTimeStretchApplied": False,
                "adaptiveDurationPaddingApplied": False,
            },
            "speechTokens": {
                "derivation": "ceil(outputSamples / 7680); four 1920-sample 48 kHz VAE frames per LM step",
                "outputSamples": int(raw.size),
                "derivedSpeechTokenCount": int(derived_steps),
                "frozenV8TokenCap": FROZEN_V8_TOKEN_CAP,
                "passes": derived_steps < FROZEN_V8_TOKEN_CAP,
            },
            "modelContract": contract,
            "bytecodeCacheChecks": [before, after],
            "networkAttemptCount": len(attempts),
            "retryUsed": False,
            "alternateTakeGenerated": False,
            "generatedAudio": True,
        }
        job_receipt_path = raw_path.parent / f"{job_id}.job.json"
        job_receipt = _write_json_verified(job_receipt_path, record)
        records.append({**record, "jobReceipt": job_receipt})
        print(
            f"V11 representative {generate_call_count}/28 {job_id} complete",
            file=sys.stderr,
            flush=True,
        )

    if generate_call_count != 28 or len(records) != 28:
        raise GenerationError("V11 representative run did not execute exactly 28 calls")
    bytecode_after = runtime.bytecode_cache_gate("representative-generation-after-all-jobs")
    if attempts:
        raise GenerationError("V11 representative run attempted network access")
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "script": _binding(SCRIPT_PATH),
        "synthesisAuthorisation": authority_binding,
        "r5ModelLoadAuthority": authority["r5ModelLoadAuthority"],
        "runtimeInstanceID": runtime.RUNTIME_INSTANCE_ID,
        "modelContract": contract,
        "jobManifestSHA256": authority["jobManifestSHA256"],
        "jobCount": len(records),
        "modelGenerateCallCount": generate_call_count,
        "audioFileCount": 56,
        "jobs": records,
        "bytecodeCacheChecks": [bytecode_before, bytecode_after],
        "networkAttemptCount": len(attempts),
        "elapsedSeconds": time.monotonic() - started,
        "oneTakePerJob": True,
        "retryUsed": False,
        "cherryPickingUsed": False,
        "thresholdChangeUsed": False,
        "anonymousReviewOnly": True,
        "nonShipping": True,
        "representativeMachineAuditRun": False,
        "full203By2GenerationPermitted": False,
        "full203By2GenerationStarted": False,
        "generatedAudio": True,
        "incrementalCostNOK": 0,
        "billingCredentialUsed": False,
    }
    binding = _write_json_verified(RECEIPT_PATH, receipt)
    del model
    gc.collect()
    torch.mps.empty_cache()
    return {
        "status": STATUS,
        "jobCount": 28,
        "audioFileCount": 56,
        "receipt": binding,
        "generatedAudio": True,
        "full203By2GenerationStarted": False,
    }


def _record_failure(error: BaseException) -> None:
    if FAILURE_PATH.exists() or RECEIPT_PATH.exists() or not authorization.OUTPUT_ROOT.is_dir():
        return
    completed = sorted(authorization.OUTPUT_ROOT.rglob("*.job.json"))
    value = {
        "schemaVersion": 1,
        "status": "CODEX_V11_VOXCPM2_REPRESENTATIVE_STOPPED_AT_FIRST_DEVIATION",
        "recordedAt": "2026-07-25",
        "script": _binding(SCRIPT_PATH),
        "failureType": type(error).__name__,
        "failure": str(error),
        "completedJobReceipts": [_binding(path) for path in completed],
        "completedJobCount": len(completed),
        "retryPermitted": False,
        "full203By2GenerationStarted": False,
        "nonShipping": True,
    }
    _write_json_verified(FAILURE_PATH, value)


def main() -> int:
    try:
        result = generate()
    except Exception as error:
        _record_failure(error)
        print(f"V11 VoxCPM2 representative generation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
