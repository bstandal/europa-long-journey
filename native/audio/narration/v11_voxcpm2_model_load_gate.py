#!/usr/bin/env python3
"""Load the exact VoxCPM2 snapshot on MPS without entering generation.

This is the final non-synthesis gate before the frozen V11 14-by-2 method may
be considered. The parent process revalidates the exact snapshot, runtime,
licences and one-take binding. A pinned offline child then constructs the
model once with ``optimize=False`` and reports its loaded architecture,
device, dtype and memory state. No prompt is encoded and no audio method is
called.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any

import v11_narration_candidate_preflight as candidate_gate
import v11_voxcpm2_exact_snapshot as snapshot
import v11_voxcpm2_method as method
import v11_voxcpm2_runtime_audit as runtime


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
MODEL_ROOT = snapshot.SNAPSHOT_ROOT / "model"
SOURCE_ROOT = runtime.SOURCE_ROOT / runtime.SOURCE_DIRECTORY / "src"
PYTHON = runtime.VENV_ROOT / "bin/python"
RECEIPT_PATH = (
    runtime.RUNTIME_ROOT / "voxcpm2-model-load-gate-r5.v11.receipt.json"
)
SNAPSHOT_RECEIPT_PATH = snapshot.SNAPSHOT_ROOT / snapshot.RECEIPT_NAME
WORKER_STATUS = "CODEX_V11_VOXCPM2_EXACT_MODEL_LOADED_ON_MPS_NO_SYNTHESIS"
STATUS = "CODEX_V11_VOXCPM2_R5_BYTE_RUNTIME_MODEL_LOAD_GATE_VERIFIED"


class ModelLoadGateError(RuntimeError):
    """Raised when the exact offline model-load gate deviates."""


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


def _worker() -> dict[str, Any]:
    """Run only inside the exact pinned runtime."""
    import resource
    import socket

    network_attempts: list[str] = []

    def blocked(*args: Any, **kwargs: Any) -> Any:
        network_attempts.append("socket")
        raise RuntimeError("network access attempted during V11 model load")

    socket.socket.connect = blocked
    socket.socket.connect_ex = blocked
    socket.create_connection = blocked
    socket.getaddrinfo = blocked

    bytecode_before = runtime.bytecode_cache_gate("model-load-worker-before")

    import torch
    from voxcpm import VoxCPM
    from voxcpm.model.voxcpm2 import VoxCPM2Model

    if sys.version.split()[0] != "3.11.15":
        raise ModelLoadGateError("V11 model-load interpreter drifted")
    if torch.__version__ != "2.10.0":
        raise ModelLoadGateError("V11 model-load torch drifted")
    if not torch.backends.mps.is_built() or not torch.backends.mps.is_available():
        raise ModelLoadGateError("V11 model-load MPS is unavailable")
    if not MODEL_ROOT.is_dir():
        raise ModelLoadGateError("V11 exact model directory is unavailable")

    torch.mps.empty_cache()
    memory_before = {
        "currentAllocatedBytes": int(torch.mps.current_allocated_memory()),
        "driverAllocatedBytes": int(torch.mps.driver_allocated_memory()),
    }
    model = VoxCPM(
        voxcpm_model_path=str(MODEL_ROOT),
        zipenhancer_model_path=None,
        enable_denoiser=False,
        optimize=False,
        device="mps",
        lora_config=None,
        lora_weights_path=None,
    )
    torch.mps.synchronize()

    if not isinstance(model.tts_model, VoxCPM2Model):
        raise ModelLoadGateError("V11 loaded the wrong model architecture")
    parameter_devices = sorted({parameter.device.type for parameter in model.tts_model.parameters()})
    floating_parameter_dtypes = sorted(
        {
            str(parameter.dtype).removeprefix("torch.")
            for parameter in model.tts_model.parameters()
            if parameter.is_floating_point()
        }
    )
    parameter_count = sum(parameter.numel() for parameter in model.tts_model.parameters())
    if parameter_devices != ["mps"]:
        raise ModelLoadGateError(
            f"V11 model parameters escaped MPS: {parameter_devices}"
        )
    if floating_parameter_dtypes != ["float32"]:
        raise ModelLoadGateError(
            f"V11 model dtype escaped float32: {floating_parameter_dtypes}"
        )
    if model.tts_model.config.dtype != "float32":
        raise ModelLoadGateError("V11 model configuration dtype escaped float32")
    if model.tts_model.device != "mps":
        raise ModelLoadGateError("V11 model runtime device escaped MPS")
    if model.tts_model.training:
        raise ModelLoadGateError("V11 model is not in evaluation mode")
    if model.tts_model.sample_rate != 48_000:
        raise ModelLoadGateError("V11 output sample rate drifted")
    if model.tts_model._encode_sample_rate != 16_000:
        raise ModelLoadGateError("V11 conditioning sample rate drifted")
    if model.denoiser is not None:
        raise ModelLoadGateError("V11 denoiser was unexpectedly loaded")
    if network_attempts:
        raise ModelLoadGateError("V11 model load attempted network access")

    bytecode_after = runtime.bytecode_cache_gate("model-load-worker-after")

    memory_after = {
        "currentAllocatedBytes": int(torch.mps.current_allocated_memory()),
        "driverAllocatedBytes": int(torch.mps.driver_allocated_memory()),
        "processPeakRSSBytes": int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss),
    }
    return {
        "status": WORKER_STATUS,
        "python": sys.version.split()[0],
        "torch": torch.__version__,
        "architecture": type(model.tts_model).__name__,
        "runtimeDevice": model.tts_model.device,
        "floatingParameterDtypes": floating_parameter_dtypes,
        "parameterDevices": parameter_devices,
        "parameterCount": parameter_count,
        "modelTraining": model.tts_model.training,
        "encodeSampleRate": model.tts_model._encode_sample_rate,
        "outputSampleRate": model.tts_model.sample_rate,
        "denoiserLoaded": model.denoiser is not None,
        "optimisationEnabled": False,
        "networkAttemptCount": len(network_attempts),
        "memoryBefore": memory_before,
        "memoryAfter": memory_after,
        "bytecodeCacheChecks": [bytecode_before, bytecode_after],
        "promptEncoded": False,
        "generationMethodCalled": False,
        "generatedAudio": False,
    }


def validate_worker_result(worker: dict[str, Any]) -> None:
    expected = {
        "status": WORKER_STATUS,
        "python": "3.11.15",
        "torch": "2.10.0",
        "architecture": "VoxCPM2Model",
        "runtimeDevice": "mps",
        "floatingParameterDtypes": ["float32"],
        "parameterDevices": ["mps"],
        "modelTraining": False,
        "encodeSampleRate": 16_000,
        "outputSampleRate": 48_000,
        "denoiserLoaded": False,
        "optimisationEnabled": False,
        "networkAttemptCount": 0,
        "promptEncoded": False,
        "generationMethodCalled": False,
        "generatedAudio": False,
    }
    for key, value in expected.items():
        if worker.get(key) != value:
            raise ModelLoadGateError(
                f"V11 exact model-load result drifted at {key}: {worker.get(key)!r}"
            )
    if not isinstance(worker.get("parameterCount"), int) or worker["parameterCount"] <= 0:
        raise ModelLoadGateError("V11 exact model-load parameter count is invalid")
    if not isinstance(worker.get("bytecodeCacheChecks"), list):
        raise ModelLoadGateError("V11 model-load bytecode checks are unavailable")


def build_receipt(
    *,
    snapshot_result: dict[str, Any],
    runtime_result: dict[str, Any],
    method_result: dict[str, Any],
    worker: dict[str, Any],
    bytecode_checks: list[dict[str, Any]],
) -> dict[str, Any]:
    validate_worker_result(worker)
    return {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": candidate_gate.TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "modelLoadReplayID": "R5",
        "runtimeInstanceID": runtime.RUNTIME_INSTANCE_ID,
        "script": _binding(SCRIPT_PATH),
        "snapshotReceipt": _binding(SNAPSHOT_RECEIPT_PATH),
        "runtimeReceipt": _binding(runtime.RECEIPT_PATH),
        "methodScript": _binding(method.SCRIPT_PATH),
        "exactSnapshot": snapshot_result,
        "runtime": runtime_result,
        "oneTakeMethod": {
            "status": method_result["status"],
            "callCount": method_result["callCount"],
            "uniqueSeedCount": method_result["uniqueSeedCount"],
            "modelInitialisation": method_result["modelInitialisation"],
            "generationSettings": method_result["generationSettings"],
        },
        "modelLoad": worker,
        "bytecodeCacheChecks": bytecode_checks,
        "priorUnreceiptedR4LoadUsedAsPassEvidence": False,
        "comparisonSynthesisPermitted": True,
        "fullGenerationPermitted": False,
        "generatedAudio": False,
        "incrementalCostNOK": 0,
        "billingCredentialUsed": False,
    }


def write_receipt_and_verify(receipt: dict[str, Any], path: Path) -> dict[str, Any]:
    payload = (json.dumps(receipt, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    path.write_bytes(payload)
    reread = path.read_bytes()
    if reread != payload:
        raise ModelLoadGateError("V11 R5 receipt reread differs from written bytes")
    if json.loads(reread) != receipt:
        raise ModelLoadGateError("V11 R5 receipt JSON reread differs from source record")
    binding = _binding(path)
    if binding["bytes"] != len(payload) or binding["sha256"] != hashlib.sha256(payload).hexdigest():
        raise ModelLoadGateError("V11 R5 receipt binding verification failed")
    return binding


def validate() -> dict[str, Any]:
    before = runtime.bytecode_cache_gate("model-load-gate-before")
    snapshot_before = snapshot.validate(snapshot.SNAPSHOT_ROOT)
    runtime_result = runtime.validate_runtime()
    method_result = method.validate()
    if not PYTHON.is_file() or not SOURCE_ROOT.is_dir():
        raise ModelLoadGateError("V11 exact runtime was not prepared")
    if runtime_result["status"] != runtime.STATUS:
        raise ModelLoadGateError("V11 runtime gate did not pass")
    if method_result["status"] != method.STATUS:
        raise ModelLoadGateError("V11 one-take method gate did not pass")

    env = {
        **os.environ,
        "PYTHONPATH": str(SOURCE_ROOT),
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_HUB_DISABLE_TELEMETRY": "1",
        "DO_NOT_TRACK": "1",
        "NO_PROXY": "*",
        "TOKENIZERS_PARALLELISM": "false",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    completed = subprocess.run(
        [str(PYTHON), "-B", str(SCRIPT_PATH), "worker"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    worker = json.loads(completed.stdout.strip())
    validate_worker_result(worker)
    snapshot_after = snapshot.validate(snapshot.SNAPSHOT_ROOT)
    if snapshot_before != snapshot_after:
        raise ModelLoadGateError("V11 snapshot changed during exact model load")
    after = runtime.bytecode_cache_gate("model-load-gate-after")

    receipt = build_receipt(
        snapshot_result=snapshot_after,
        runtime_result=runtime_result,
        method_result=method_result,
        worker=worker,
        bytecode_checks=[before, *worker["bytecodeCacheChecks"], after],
    )
    receipt_binding = write_receipt_and_verify(receipt, RECEIPT_PATH)
    return {
        "status": STATUS,
        "modelTotalBytes": snapshot_after["modelTotalBytes"],
        "runtimePackageCount": runtime_result["packageCount"],
        "mpsAvailable": runtime_result["mpsAvailable"],
        "architecture": worker["architecture"],
        "runtimeDevice": worker["runtimeDevice"],
        "runtimeDtype": worker["floatingParameterDtypes"],
        "parameterCount": worker["parameterCount"],
        "receipt": receipt_binding,
        "receiptRereadAndHashVerified": True,
        "comparisonSynthesisPermitted": True,
        "fullGenerationPermitted": False,
        "generatedAudio": False,
        "incrementalCostNOK": 0,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "worker"))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = _worker() if args.command == "worker" else validate()
    except (
        ModelLoadGateError,
        snapshot.SnapshotError,
        runtime.RuntimeAuditError,
        method.MethodError,
        candidate_gate.GateError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"V11 VoxCPM2 model-load gate failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            if error.stdout:
                print(error.stdout, file=sys.stderr)
            if error.stderr:
                print(error.stderr, file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
