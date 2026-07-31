#!/usr/bin/env python3
"""Build and verify the V12 VoxCPM2 pre-synthesis trust domain.

This program is deliberately incapable of authorising speech synthesis.  It
inventories already-local alternatives, records the 46 Numba cache files left
inside the prior runtime, assembles a new runtime only from locked local
archives, prewarms both bound reference/prompt encodings without calling a
generation method, and repeats that preflight in a fresh process.  The final
receipt always requires an editor decision and always leaves synthesis closed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import socket
import subprocess
import sys
import tarfile
from typing import Any, Iterable


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
LOCK_PATH = NARRATION_ROOT / "v12-voxcpm2-presynthesis.lock.json"
WORK_ROOT = NARRATION_ROOT / "work/pre-synthesis-v12"
RUNTIME_ROOT = WORK_ROOT / "voxcpm2-runtime-r1-2026-07-25"
INTERPRETER_ROOT = RUNTIME_ROOT / "interpreter"
SOURCE_ROOT = RUNTIME_ROOT / "source"
VENV_ROOT = RUNTIME_ROOT / "exact-venv"
EXTERNAL_CACHE_ROOT = WORK_ROOT / "voxcpm2-external-cache-r1-2026-07-25"
NUMBA_CACHE_ROOT = EXTERNAL_CACHE_ROOT / "numba"
AUX_CACHE_ROOT = EXTERNAL_CACHE_ROOT / "auxiliary"
TEMP_ROOT = EXTERNAL_CACHE_ROOT / "temporary"
EVIDENCE_ROOT = WORK_ROOT / "evidence-r1-2026-07-25"
CANDIDATE_INVENTORY_PATH = EVIDENCE_ROOT / "local-method-inventory.v12.json"
LEGACY_NUMBA_INVENTORY_PATH = EVIDENCE_ROOT / "legacy-numba-cache-inventory.v12.json"
RUNTIME_RECEIPT_PATH = EVIDENCE_ROOT / "fresh-runtime.v12.receipt.json"
PRESYNTHESIS_RECEIPT_PATH = EVIDENCE_ROOT / "presynthesis-authority.v12.receipt.json"

TRUST_DOMAIN = "CODEX_V12_VOXCPM2_PRE_SYNTHESIS_ONLY"
INVENTORY_STATUS = "CODEX_V12_LOCAL_DIFFERENT_METHOD_INVENTORY_VERIFIED_EMPTY"
LEGACY_CACHE_STATUS = "CODEX_V12_LEGACY_NUMBA_CACHE_46_FILES_INVENTORIED"
RUNTIME_STATUS = "CODEX_V12_FRESH_OFFLINE_RUNTIME_PREPARED"
WORKER_STATUS = "CODEX_V12_REFERENCE_PROMPT_ENCODING_PREWARMED_NO_GENERATION"
FINAL_STATUS = "CODEX_V12_PRE_SYNTHESIS_PREFLIGHT_VERIFIED_EDITOR_DECISION_REQUIRED"

AUDIO_EXTENSIONS = {
    ".wav",
    ".wave",
    ".pcm",
    ".aif",
    ".aiff",
    ".caf",
    ".m4a",
    ".mp3",
    ".flac",
    ".ogg",
}


class PresynthesisError(RuntimeError):
    """Raised when the V12 trust boundary fails closed."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _canonical_sha(value: Any) -> str:
    payload = json.dumps(
        value, sort_keys=True, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _binding(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise PresynthesisError(f"required regular file is unavailable: {path}")
    return {
        "path": str(path.absolute()),
        "bytes": path.stat().st_size,
        "sha256": _sha256(path),
    }


def _repository_path(relative: str) -> Path:
    path = (REPOSITORY_ROOT / relative).absolute()
    try:
        path.relative_to(REPOSITORY_ROOT.absolute())
    except ValueError as error:
        raise PresynthesisError(f"locked path escapes repository: {relative}") from error
    return path


def _load_lock() -> dict[str, Any]:
    try:
        document = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PresynthesisError("V12 pre-synthesis lock is unavailable") from error
    if (
        document.get("schemaVersion") != 1
        or document.get("trustDomain") != TRUST_DOMAIN
        or document.get("recordedAt") != "2026-07-25"
    ):
        raise PresynthesisError("V12 pre-synthesis lock identity drifted")
    return document


def _validate_locked_binding(record: dict[str, Any]) -> dict[str, Any]:
    path = _repository_path(record["path"])
    actual = _binding(path)
    if actual["bytes"] != record["bytes"] or actual["sha256"] != record["sha256"]:
        raise PresynthesisError(f"locked input bytes drifted: {record['path']}")
    return actual


def _tree_manifest(root: Path) -> dict[str, Any]:
    if not root.is_dir():
        raise PresynthesisError(f"tree root is unavailable: {root}")
    records: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            records.append(
                {"path": relative, "kind": "symlink", "target": os.readlink(path)}
            )
        elif path.is_file():
            records.append(
                {
                    "path": relative,
                    "kind": "file",
                    "bytes": path.stat().st_size,
                    "sha256": _sha256(path),
                }
            )
    return {
        "root": str(root.absolute()),
        "entryCount": len(records),
        "fileCount": sum(item["kind"] == "file" for item in records),
        "symlinkCount": sum(item["kind"] == "symlink" for item in records),
        "totalFileBytes": sum(item.get("bytes", 0) for item in records),
        "inventorySHA256": _canonical_sha(records),
    }


def _selected_file_manifest(root: Path, suffixes: set[str]) -> dict[str, Any]:
    if not root.is_dir():
        raise PresynthesisError(f"selected-file root is unavailable: {root}")
    records = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and not path.is_symlink() and path.suffix.lower() in suffixes:
            records.append(
                {
                    "path": path.relative_to(root).as_posix(),
                    "absolutePath": str(path.absolute()),
                    "bytes": path.stat().st_size,
                    "sha256": _sha256(path),
                }
            )
    return {
        "root": str(root.absolute()),
        "fileCount": len(records),
        "totalBytes": sum(item["bytes"] for item in records),
        "inventorySHA256": _canonical_sha(records),
        "files": records,
    }


def _model_manifest(lock: dict[str, Any]) -> dict[str, Any]:
    model = lock["model"]
    root = _repository_path(model["root"])
    expected = sorted(model["files"], key=lambda item: item["path"])
    actual_paths = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and not path.is_symlink()
    }
    if actual_paths != {item["path"] for item in expected}:
        raise PresynthesisError("V12 model inventory escaped the exact lock")
    verified = []
    for item in expected:
        binding = _binding(root / item["path"])
        if binding["bytes"] != item["bytes"] or binding["sha256"] != item["sha256"]:
            raise PresynthesisError(f"V12 model byte drift: {item['path']}")
        verified.append(
            {"path": item["path"], "bytes": item["bytes"], "sha256": item["sha256"]}
        )
    return {
        "root": str(root.absolute()),
        "modelID": model["modelID"],
        "revision": model["revision"],
        "fileCount": len(verified),
        "totalBytes": sum(item["bytes"] for item in verified),
        "inventorySHA256": _canonical_sha(verified),
        "allBytesMatchExactLock": True,
    }


def _conditioning_bindings(lock: dict[str, Any]) -> dict[str, Any]:
    transcript = _validate_locked_binding(lock["conditioning"]["transcript"])
    references = []
    for record in lock["conditioning"]["references"]:
        references.append(
            {"candidateID": record["candidateID"], "file": _validate_locked_binding(record)}
        )
    if [item["candidateID"] for item in references] != [
        "voice-candidate-05",
        "voice-candidate-06",
    ]:
        raise PresynthesisError("V12 reference identity or order drifted")
    return {"transcript": transcript, "references": references}


def _runtime_versions_from_metadata(root: Path, expected: dict[str, str]) -> dict[str, Any]:
    site_packages = root / "lib/python3.11/site-packages"
    metadata = {}
    for package in ("torch", "torchaudio", "librosa", "numba", "llvmlite", "numpy", "transformers"):
        candidates = sorted(site_packages.glob(f"{package.replace('-', '_')}-*.dist-info/METADATA"))
        if len(candidates) != 1:
            raise PresynthesisError(f"cannot bind installed runtime metadata: {package}")
        text = candidates[0].read_text(encoding="utf-8")
        match = re.search(r"^Version: (.+)$", text, re.MULTILINE)
        if match is None or match.group(1) != expected[package]:
            raise PresynthesisError(f"runtime version drifted: {package}")
        metadata[package] = {
            "version": match.group(1),
            "metadata": _binding(candidates[0]),
        }
    return {
        "python": expected["python"],
        "packages": metadata,
        "platform": {
            "machine": platform.machine(),
            "macOS": platform.mac_ver()[0],
        },
    }


def legacy_numba_cache_inventory(lock: dict[str, Any]) -> dict[str, Any]:
    config = lock["legacyNumbaCache"]
    root = _repository_path(config["root"])
    suffixes = set(config["extensions"])
    inventory = _selected_file_manifest(root, suffixes)
    if inventory["fileCount"] != config["expectedFileCount"]:
        raise PresynthesisError(
            f"legacy Numba cache count drifted: {inventory['fileCount']}"
        )
    runtime_versions = _runtime_versions_from_metadata(
        root, lock["runtimeVersions"]
    )
    document = {
        "schemaVersion": 1,
        "status": LEGACY_CACHE_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "sourceRuntime": str(root.absolute()),
        "runtimeVersions": runtime_versions,
        "cacheFileCount": inventory["fileCount"],
        "cacheTotalBytes": inventory["totalBytes"],
        "cacheInventorySHA256": inventory["inventorySHA256"],
        "cacheFiles": inventory["files"],
        "inventoryOnly": True,
        "legacyRuntimeModified": False,
        "legacyCacheOpenedAsAudio": False,
        "generatedAudio": False,
        "synthesisPermitted": False,
    }
    return document


def _local_hf_model_roots() -> list[dict[str, Any]]:
    roots = [
        Path.home() / ".cache/huggingface/hub",
        Path.home() / "Library/Caches/huggingface/hub",
    ]
    records = []
    for root in roots:
        if not root.is_dir():
            continue
        for model_root in sorted(root.glob("models--*")):
            if not model_root.is_dir():
                continue
            records.append(
                {
                    "modelID": model_root.name.removeprefix("models--").replace("--", "/", 1),
                    "path": str(model_root.absolute()),
                    "snapshotDirectoryCount": len(
                        [item for item in (model_root / "snapshots").glob("*") if item.is_dir()]
                    ) if (model_root / "snapshots").is_dir() else 0,
                }
            )
    return records


def local_method_inventory(lock: dict[str, Any]) -> dict[str, Any]:
    evidence = {}
    for record in lock["priorMethodEvidence"]:
        binding = _validate_locked_binding(record)
        evidence[record["methodID"]] = binding

    v9 = json.loads(Path(evidence["qwen3-tts"]["path"]).read_text(encoding="utf-8"))
    chatterbox = json.loads(
        Path(evidence["chatterbox-turbo"]["path"]).read_text(encoding="utf-8")
    )
    openvoice = json.loads(
        Path(evidence["openvoice-v2"]["path"]).read_text(encoding="utf-8")
    )
    if (
        v9.get("candidateGate", {}).get("eligibleCandidateIDs") != []
        or v9.get("candidatePromoted") is not False
        or chatterbox.get("passesRepresentativeComparison") is not False
        or chatterbox.get("candidatePromoted") is not False
        or openvoice.get("decision", {}).get("passesFrozenRepresentativeGate") is not False
        or openvoice.get("decision", {}).get("candidatePromoted") is not False
    ):
        raise PresynthesisError("prior local-method evidence no longer fails closed")

    cached_models = _local_hf_model_roots()
    command_names = (
        "say",
        "piper",
        "espeak",
        "espeak-ng",
        "mimic3",
        "festival",
        "flite",
        "kokoro-tts",
        "edge-tts",
    )
    commands = [
        {"name": name, "path": shutil.which(name), "installed": shutil.which(name) is not None}
        for name in command_names
    ]
    methods = [
        {
            "methodID": "voxcpm2",
            "localRuntimeAndWeights": True,
            "differentFromV11": False,
            "terminalQualityGateAlreadyFailedOrUnavailable": True,
            "eligibleDifferentLocalMethod": False,
            "reason": "This is the V11 method and therefore is not a different local method.",
        },
        {
            "methodID": "qwen3-tts",
            "localRuntimeAndWeights": True,
            "differentFromV11": True,
            "terminalQualityGateAlreadyFailedOrUnavailable": True,
            "eligibleDifferentLocalMethod": False,
            "evidence": evidence["qwen3-tts"],
            "reason": "The locally bound Qwen family is prior rejected baseline evidence, not an untried eligible method.",
        },
        {
            "methodID": "chatterbox-turbo",
            "localRuntimeAndWeights": True,
            "differentFromV11": True,
            "terminalQualityGateAlreadyFailedOrUnavailable": True,
            "eligibleDifferentLocalMethod": False,
            "evidence": evidence["chatterbox-turbo"],
            "reason": "The unchanged representative comparison failed and the candidate was not promoted.",
        },
        {
            "methodID": "openvoice-v2",
            "localRuntimeAndWeights": True,
            "differentFromV11": True,
            "terminalQualityGateAlreadyFailedOrUnavailable": True,
            "eligibleDifferentLocalMethod": False,
            "evidence": evidence["openvoice-v2"],
            "reason": "The frozen representative gate failed and the candidate was not promoted.",
        },
        {
            "methodID": "apple-system-voices",
            "localRuntimeAndWeights": shutil.which("say") is not None,
            "differentFromV11": True,
            "commercialNarrationRightsBound": False,
            "conditionsOnBothFrozenReferences": False,
            "eligibleDifferentLocalMethod": False,
            "evidence": evidence["qwen3-tts"],
            "reason": "The exact prior inventory binds the commercial-use restriction and lack of frozen-reference conditioning.",
        },
        {
            "methodID": "installed-code-without-bound-weights",
            "localRuntimeAndWeights": False,
            "differentFromV11": True,
            "eligibleDifferentLocalMethod": False,
            "evidence": evidence["qwen3-tts"],
            "reason": "Kokoro, MeloTTS, IndexTTS and Dia are locally present only as code or lack a bound commercially cleared model snapshot.",
        },
    ]
    eligible = [
        item["methodID"]
        for item in methods
        if item.get("differentFromV11") is True
        and item.get("eligibleDifferentLocalMethod") is True
    ]
    if eligible:
        raise PresynthesisError("a different local synthesis method became eligible")
    return {
        "schemaVersion": 1,
        "status": INVENTORY_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "scope": {
            "offlineOnly": True,
            "networkDownloadsMade": False,
            "hostedAPIsUsed": False,
            "oldGeneratedAudioOpened": False,
            "synthesisExecuted": False,
        },
        "discoveredHuggingFaceModelRoots": cached_models,
        "localSpeechCommands": commands,
        "assessedMethods": methods,
        "eligibleDifferentLocalMethods": eligible,
        "selectedMethod": None,
        "synthesisPermitted": False,
        "generatedAudio": False,
    }


def _write_json(path: Path, document: dict[str, Any]) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    path.write_bytes(payload)
    if path.read_bytes() != payload:
        raise PresynthesisError(f"durable receipt reread failed: {path}")
    return _binding(path)


def write_inventories() -> dict[str, Any]:
    lock = _load_lock()
    candidates = local_method_inventory(lock)
    legacy = legacy_numba_cache_inventory(lock)
    candidate_binding = _write_json(CANDIDATE_INVENTORY_PATH, candidates)
    legacy_binding = _write_json(LEGACY_NUMBA_INVENTORY_PATH, legacy)
    return {
        "status": "CODEX_V12_PRESYNTHESIS_INVENTORIES_WRITTEN",
        "candidateInventory": candidate_binding,
        "legacyNumbaInventory": legacy_binding,
        "eligibleDifferentLocalMethods": [],
        "legacyNumbaCacheFileCount": 46,
        "generatedAudio": False,
        "synthesisPermitted": False,
    }


def _safe_extract(archive_path: Path, destination: Path) -> None:
    if destination.exists():
        raise PresynthesisError(f"archive extraction target is not new: {destination}")
    destination.mkdir(parents=True)
    destination_root = destination.resolve()
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            try:
                target.relative_to(destination_root)
            except ValueError as error:
                raise PresynthesisError("archive member escapes V12 runtime") from error
        archive.extractall(destination, filter="data")


def _wheel_inventory(lock: dict[str, Any]) -> dict[str, Any]:
    wheelhouse = _repository_path(lock["archives"]["wheelhouse"])
    wheel_lock = _validate_locked_binding(lock["archives"]["wheelLock"])
    pattern = re.compile(
        r"^([A-Za-z0-9_.-]+)==([^ ]+) --hash=sha256:([0-9a-f]{64})$"
    )
    expected = {}
    for line in Path(wheel_lock["path"]).read_text(encoding="utf-8").splitlines():
        match = pattern.fullmatch(line)
        if match is None:
            raise PresynthesisError("V12 wheel lock contains an invalid line")
        expected[match.group(3)] = {"package": match.group(1), "version": match.group(2)}
    wheels = []
    for path in sorted(wheelhouse.glob("*.whl")):
        binding = _binding(path)
        identity = expected.get(binding["sha256"])
        if identity is None:
            raise PresynthesisError(f"wheel escaped V12 exact lock: {path}")
        wheels.append({**identity, "file": binding})
    if len(wheels) != 59 or {item["file"]["sha256"] for item in wheels} != set(expected):
        raise PresynthesisError("V12 wheel archive inventory is not exactly 59")
    return {
        "wheelhouse": str(wheelhouse.absolute()),
        "wheelLock": wheel_lock,
        "wheelCount": len(wheels),
        "inventorySHA256": _canonical_sha(wheels),
        "wheels": wheels,
    }


def _offline_environment(source_path: Path) -> dict[str, str]:
    return {
        **os.environ,
        "PYTHONDONTWRITEBYTECODE": "1",
        "UV_COMPILE_BYTECODE": "0",
        "UV_NO_PROGRESS": "1",
        "UV_OFFLINE": "1",
        "PIP_NO_INDEX": "1",
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_HUB_DISABLE_TELEMETRY": "1",
        "DO_NOT_TRACK": "1",
        "NO_PROXY": "*",
        "PYTHONPATH": os.pathsep.join((str(source_path), str(NARRATION_ROOT))),
        "NUMBA_CACHE_DIR": str(NUMBA_CACHE_ROOT.absolute()),
        "HF_HOME": str((AUX_CACHE_ROOT / "huggingface").absolute()),
        "TORCH_HOME": str((AUX_CACHE_ROOT / "torch").absolute()),
        "XDG_CACHE_HOME": str((AUX_CACHE_ROOT / "xdg").absolute()),
        "MPLCONFIGDIR": str((AUX_CACHE_ROOT / "matplotlib").absolute()),
        "TMPDIR": str(TEMP_ROOT.absolute()),
    }


def prepare_runtime() -> dict[str, Any]:
    lock = _load_lock()
    if RUNTIME_ROOT.exists() or EXTERNAL_CACHE_ROOT.exists():
        raise PresynthesisError("V12 fresh runtime or external cache target already exists")
    if not CANDIDATE_INVENTORY_PATH.is_file() or not LEGACY_NUMBA_INVENTORY_PATH.is_file():
        raise PresynthesisError("V12 inventories must be written before runtime preparation")
    candidate_document = json.loads(CANDIDATE_INVENTORY_PATH.read_text(encoding="utf-8"))
    legacy_document = json.loads(LEGACY_NUMBA_INVENTORY_PATH.read_text(encoding="utf-8"))
    if (
        candidate_document.get("eligibleDifferentLocalMethods") != []
        or legacy_document.get("cacheFileCount") != 46
    ):
        raise PresynthesisError("V12 inventory gate drifted before runtime preparation")

    model = _model_manifest(lock)
    conditioning = _conditioning_bindings(lock)
    cpython_archive = _validate_locked_binding(lock["archives"]["cpython"])
    source_archive = _validate_locked_binding(lock["archives"]["source"])
    wheels = _wheel_inventory(lock)

    _safe_extract(Path(cpython_archive["path"]), INTERPRETER_ROOT)
    _safe_extract(Path(source_archive["path"]), SOURCE_ROOT)
    NUMBA_CACHE_ROOT.mkdir(parents=True)
    AUX_CACHE_ROOT.mkdir(parents=True)
    TEMP_ROOT.mkdir(parents=True)

    python = INTERPRETER_ROOT / "python/bin/python3.11"
    source_path = SOURCE_ROOT / "VoxCPM-19b6bf7590025418821a86dcb817504e0ad7e5df/src"
    if not python.is_file() or not source_path.is_dir():
        raise PresynthesisError("V12 extracted interpreter or source is unavailable")
    env = _offline_environment(source_path)
    subprocess.run(
        [str(python), "-B", "-m", "venv", "--without-pip", str(VENV_ROOT)],
        check=True,
        env=env,
    )
    subprocess.run(
        [
            "uv",
            "pip",
            "install",
            "--python",
            str(VENV_ROOT / "bin/python"),
            "--offline",
            "--no-index",
            "--find-links",
            wheels["wheelhouse"],
            "--require-hashes",
            "-r",
            wheels["wheelLock"]["path"],
        ],
        check=True,
        env=env,
    )

    versions = _runtime_versions_from_metadata(VENV_ROOT, lock["runtimeVersions"])
    if _selected_file_manifest(NUMBA_CACHE_ROOT, {".nbc", ".nbi"})["fileCount"] != 0:
        raise PresynthesisError("V12 external Numba cache is not empty before prewarm")
    runtime_manifest = _tree_manifest(RUNTIME_ROOT)
    source_manifest = _tree_manifest(SOURCE_ROOT)
    document = {
        "schemaVersion": 1,
        "status": RUNTIME_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "script": _binding(SCRIPT_PATH),
        "lock": _binding(LOCK_PATH),
        "candidateInventory": _binding(CANDIDATE_INVENTORY_PATH),
        "legacyNumbaInventory": _binding(LEGACY_NUMBA_INVENTORY_PATH),
        "inputArchives": {"cpython": cpython_archive, "source": source_archive},
        "wheelArchives": wheels,
        "model": model,
        "conditioning": conditioning,
        "runtimeVersions": versions,
        "runtime": runtime_manifest,
        "source": source_manifest,
        "numbaCache": {
            "path": str(NUMBA_CACHE_ROOT.absolute()),
            "outsideRuntimeTree": True,
            "initialCacheFileCount": 0,
        },
        "freshRuntimeBuiltFromLockedLocalArchivesOnly": True,
        "networkDownloadsMade": False,
        "modelLoaded": False,
        "referencePromptEncoded": False,
        "modelGenerationCalled": False,
        "generatedAudio": False,
        "synthesisPermitted": False,
        "v11IsTerminal": True,
    }
    receipt = _write_json(RUNTIME_RECEIPT_PATH, document)
    return {
        "status": RUNTIME_STATUS,
        "runtime": runtime_manifest,
        "externalNumbaCache": str(NUMBA_CACHE_ROOT.absolute()),
        "wheelCount": 59,
        "receipt": receipt,
        "generatedAudio": False,
        "synthesisPermitted": False,
    }


def _worker() -> dict[str, Any]:
    import builtins

    lock = _load_lock()
    if Path(os.environ.get("NUMBA_CACHE_DIR", "")).absolute() != NUMBA_CACHE_ROOT.absolute():
        raise PresynthesisError("V12 worker escaped the external Numba cache")
    if NUMBA_CACHE_ROOT.absolute().is_relative_to(RUNTIME_ROOT.absolute()):
        raise PresynthesisError("V12 Numba cache entered the runtime tree")

    network_attempts: list[str] = []

    def blocked_network(*args: Any, **kwargs: Any) -> Any:
        del args, kwargs
        network_attempts.append("socket")
        raise PresynthesisError("network access attempted during V12 prewarm")

    socket.socket.connect = blocked_network
    socket.socket.connect_ex = blocked_network
    socket.create_connection = blocked_network
    socket.getaddrinfo = blocked_network

    audio_write_attempts: list[str] = []
    original_open = builtins.open

    def guarded_open(file: Any, mode: str = "r", *args: Any, **kwargs: Any) -> Any:
        if any(flag in mode for flag in ("w", "a", "x", "+")):
            try:
                suffix = Path(file).suffix.lower()
            except TypeError:
                suffix = ""
            if suffix in AUDIO_EXTENSIONS:
                audio_write_attempts.append(str(file))
                raise PresynthesisError("audio-file creation attempted during V12 prewarm")
        return original_open(file, mode, *args, **kwargs)

    builtins.open = guarded_open

    import torch
    import torchaudio
    import librosa
    import numba
    import llvmlite
    import numpy
    import transformers
    from voxcpm import VoxCPM
    from voxcpm.model.voxcpm2 import VoxCPM2Model

    expected = lock["runtimeVersions"]
    versions = {
        "python": sys.version.split()[0],
        "torch": torch.__version__,
        "torchaudio": torchaudio.__version__,
        "librosa": librosa.__version__,
        "numba": numba.__version__,
        "llvmlite": llvmlite.__version__,
        "numpy": numpy.__version__,
        "transformers": transformers.__version__,
    }
    if versions != expected:
        raise PresynthesisError(f"V12 worker runtime versions drifted: {versions}")
    if not torch.backends.mps.is_built() or not torch.backends.mps.is_available():
        raise PresynthesisError("V12 MPS runtime is unavailable")

    model_root = _repository_path(lock["model"]["root"])
    torch.mps.empty_cache()
    model = VoxCPM(
        voxcpm_model_path=str(model_root),
        zipenhancer_model_path=None,
        enable_denoiser=False,
        optimize=False,
        device="mps",
        lora_config=None,
        lora_weights_path=None,
    )
    if not isinstance(model.tts_model, VoxCPM2Model):
        raise PresynthesisError("V12 loaded an unexpected architecture")

    generation_calls: list[str] = []

    def blocked_generation(*args: Any, **kwargs: Any) -> Any:
        del args, kwargs
        generation_calls.append("blocked")
        raise PresynthesisError("model generation was called during V12 prewarm")

    guarded_methods = (
        "generate",
        "generate_streaming",
        "_generate",
        "generate_with_prompt_cache",
        "generate_with_prompt_cache_streaming",
        "_generate_with_prompt_cache",
        "_inference",
    )
    wrapper_guarded_methods = ("generate", "generate_streaming", "_generate")
    for name in guarded_methods:
        if hasattr(model.tts_model, name):
            setattr(model.tts_model, name, blocked_generation)
    for name in wrapper_guarded_methods:
        if hasattr(model, name):
            setattr(model, name, blocked_generation)

    transcript_record = lock["conditioning"]["transcript"]
    transcript_path = _repository_path(transcript_record["path"])
    transcript = transcript_path.read_text(encoding="utf-8")
    caches = []
    for reference in lock["conditioning"]["references"]:
        reference_path = _repository_path(reference["path"])
        prompt_cache = model.tts_model.build_prompt_cache(
            prompt_text=transcript,
            prompt_wav_path=str(reference_path),
            reference_wav_path=str(reference_path),
            trim_silence_vad=False,
        )
        torch.mps.synchronize()
        if prompt_cache.get("mode") != "ref_continuation":
            raise PresynthesisError("V12 prompt cache escaped combined reference mode")
        ref = prompt_cache.get("ref_audio_feat")
        prompt = prompt_cache.get("audio_feat")
        if not isinstance(ref, torch.Tensor) or not isinstance(prompt, torch.Tensor):
            raise PresynthesisError("V12 prompt cache lacks encoded tensors")
        if not torch.isfinite(ref).all() or not torch.isfinite(prompt).all():
            raise PresynthesisError("V12 prompt cache contains non-finite values")
        caches.append(
            {
                "candidateID": reference["candidateID"],
                "mode": prompt_cache["mode"],
                "keys": sorted(prompt_cache),
                "referenceFeatureShape": list(ref.shape),
                "referenceFeatureDtype": str(ref.dtype).removeprefix("torch."),
                "promptFeatureShape": list(prompt.shape),
                "promptFeatureDtype": str(prompt.dtype).removeprefix("torch."),
                "promptTextSHA256": hashlib.sha256(transcript.encode("utf-8")).hexdigest(),
            }
        )
        del prompt_cache, ref, prompt

    torch.mps.synchronize()
    if generation_calls or audio_write_attempts or network_attempts:
        raise PresynthesisError("V12 prewarm crossed a forbidden boundary")
    return {
        "status": WORKER_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "processID": os.getpid(),
        "runtimeVersions": versions,
        "architecture": type(model.tts_model).__name__,
        "device": model.tts_model.device,
        "runtimeDtype": model.tts_model.config.dtype,
        "modelOptimisationEnabled": False,
        "referencePromptCaches": caches,
        "referencePromptCacheCount": len(caches),
        "generationGuardedMethods": sorted(guarded_methods),
        "modelGenerationCallCount": len(generation_calls),
        "networkAttemptCount": len(network_attempts),
        "audioWriteAttemptCount": len(audio_write_attempts),
        "referencePromptEncoded": True,
        "modelGenerateCalled": False,
        "pcmOrWavCreated": False,
        "generatedAudio": False,
        "synthesisPermitted": False,
    }


def _protected_manifests(lock: dict[str, Any]) -> dict[str, Any]:
    return {
        "runtime": _tree_manifest(RUNTIME_ROOT),
        "model": _model_manifest(lock),
        "source": _tree_manifest(SOURCE_ROOT),
    }


def _audio_manifests(lock: dict[str, Any]) -> dict[str, Any]:
    return {
        "runtime": _selected_file_manifest(RUNTIME_ROOT, AUDIO_EXTENSIONS),
        "model": _selected_file_manifest(_repository_path(lock["model"]["root"]), AUDIO_EXTENSIONS),
        "externalCache": _selected_file_manifest(EXTERNAL_CACHE_ROOT, AUDIO_EXTENSIONS),
    }


def _run_worker() -> dict[str, Any]:
    source_path = SOURCE_ROOT / "VoxCPM-19b6bf7590025418821a86dcb817504e0ad7e5df/src"
    env = _offline_environment(source_path)
    completed = subprocess.run(
        [str(VENV_ROOT / "bin/python"), "-B", str(SCRIPT_PATH), "worker"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
        cwd=str(TEMP_ROOT),
    )
    try:
        result = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as error:
        raise PresynthesisError("V12 prewarm worker returned invalid evidence") from error
    if completed.stderr.strip():
        result["capturedStderrSHA256"] = hashlib.sha256(
            completed.stderr.encode("utf-8")
        ).hexdigest()
    else:
        result["capturedStderrSHA256"] = hashlib.sha256(b"").hexdigest()
    return result


def _validate_worker_result(result: dict[str, Any]) -> None:
    required = {
        "status": WORKER_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "architecture": "VoxCPM2Model",
        "device": "mps",
        "runtimeDtype": "float32",
        "modelOptimisationEnabled": False,
        "referencePromptCacheCount": 2,
        "modelGenerationCallCount": 0,
        "networkAttemptCount": 0,
        "audioWriteAttemptCount": 0,
        "referencePromptEncoded": True,
        "modelGenerateCalled": False,
        "pcmOrWavCreated": False,
        "generatedAudio": False,
        "synthesisPermitted": False,
    }
    for key, expected in required.items():
        if result.get(key) != expected:
            raise PresynthesisError(f"V12 worker result drifted at {key}")
    if not isinstance(result.get("processID"), int) or result["processID"] <= 0:
        raise PresynthesisError("V12 worker process identity is invalid")


def run_presynthesis_preflight() -> dict[str, Any]:
    lock = _load_lock()
    if not RUNTIME_RECEIPT_PATH.is_file() or PRESYNTHESIS_RECEIPT_PATH.exists():
        raise PresynthesisError("V12 runtime receipt is missing or final receipt already exists")
    runtime_receipt = json.loads(RUNTIME_RECEIPT_PATH.read_text(encoding="utf-8"))
    if (
        runtime_receipt.get("status") != RUNTIME_STATUS
        or runtime_receipt.get("synthesisPermitted") is not False
        or runtime_receipt.get("modelGenerationCalled") is not False
    ):
        raise PresynthesisError("V12 runtime gate drifted before prewarm")

    candidate_inventory = json.loads(CANDIDATE_INVENTORY_PATH.read_text(encoding="utf-8"))
    legacy_inventory = json.loads(LEGACY_NUMBA_INVENTORY_PATH.read_text(encoding="utf-8"))
    if (
        candidate_inventory.get("eligibleDifferentLocalMethods") != []
        or legacy_inventory.get("cacheFileCount") != 46
    ):
        raise PresynthesisError("V12 inventory proof drifted before prewarm")

    protected_before = _protected_manifests(lock)
    audio_before = _audio_manifests(lock)
    empty_cache = _selected_file_manifest(NUMBA_CACHE_ROOT, {".nbc", ".nbi"})
    if empty_cache["fileCount"] != 0:
        raise PresynthesisError("V12 external Numba cache was not empty at first prewarm")

    first = _run_worker()
    _validate_worker_result(first)
    cache_after_first = _selected_file_manifest(NUMBA_CACHE_ROOT, {".nbc", ".nbi"})
    if cache_after_first["fileCount"] == 0:
        raise PresynthesisError("V12 prewarm did not produce a bound external Numba cache")
    protected_after_first = _protected_manifests(lock)
    audio_after_first = _audio_manifests(lock)
    if protected_after_first != protected_before or audio_after_first != audio_before:
        raise PresynthesisError("V12 first prewarm mutated protected bytes or created audio")

    second = _run_worker()
    _validate_worker_result(second)
    cache_after_second = _selected_file_manifest(NUMBA_CACHE_ROOT, {".nbc", ".nbi"})
    protected_after_second = _protected_manifests(lock)
    audio_after_second = _audio_manifests(lock)
    if first["processID"] == second["processID"]:
        raise PresynthesisError("V12 replay did not run in a fresh process")
    replay_fields = (
        "runtimeVersions",
        "architecture",
        "device",
        "runtimeDtype",
        "referencePromptCaches",
        "generationGuardedMethods",
        "modelGenerationCallCount",
        "networkAttemptCount",
        "audioWriteAttemptCount",
        "generatedAudio",
        "synthesisPermitted",
    )
    if any(first[field] != second[field] for field in replay_fields):
        raise PresynthesisError("V12 fresh-process prewarm result was not reproducible")
    if (
        cache_after_second != cache_after_first
        or protected_after_second != protected_before
        or audio_after_second != audio_before
    ):
        raise PresynthesisError("V12 replay mutated bound cache, runtime, model, source or audio inventory")

    document = {
        "schemaVersion": 1,
        "status": FINAL_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "script": _binding(SCRIPT_PATH),
        "lock": _binding(LOCK_PATH),
        "runtimeReceipt": _binding(RUNTIME_RECEIPT_PATH),
        "candidateInventory": _binding(CANDIDATE_INVENTORY_PATH),
        "legacyNumbaInventory": _binding(LEGACY_NUMBA_INVENTORY_PATH),
        "eligibleDifferentLocalMethods": [],
        "legacyNumbaCacheFileCount": 46,
        "legacyNumbaCacheInventorySHA256": legacy_inventory["cacheInventorySHA256"],
        "freshRuntime": {
            "root": str(RUNTIME_ROOT.absolute()),
            "builtFromLockedLocalArchivesOnly": True,
            "numbaCacheOutsideRuntimeTree": True,
        },
        "preflightProcesses": [first, second],
        "freshProcessReplay": {
            "processIDsDiffer": True,
            "resultFieldsIdentical": list(replay_fields),
            "runCount": 2,
        },
        "protectedManifests": {
            "beforeFirstPrewarm": protected_before,
            "afterFirstPrewarm": protected_after_first,
            "afterSecondPrewarm": protected_after_second,
            "allIdentical": True,
        },
        "externalNumbaCache": {
            "beforeFirstPrewarm": empty_cache,
            "afterFirstPrewarm": cache_after_first,
            "afterSecondPrewarm": cache_after_second,
            "unchangedDuringFreshProcessReplay": True,
        },
        "audioFileManifests": {
            "beforeFirstPrewarm": audio_before,
            "afterFirstPrewarm": audio_after_first,
            "afterSecondPrewarm": audio_after_second,
            "allIdentical": True,
            "pcmOrWavFilesCreated": 0,
        },
        "networkDownloadsMade": False,
        "networkAttemptCount": 0,
        "modelLoadedForPrewarm": True,
        "referencePromptEncoded": True,
        "modelGenerateCalled": False,
        "modelGenerationCallCount": 0,
        "generatedAudio": False,
        "synthesisExecuted": False,
        "synthesisPermitted": False,
        "comparisonSynthesisPermitted": False,
        "fullGenerationPermitted": False,
        "requiresEditorDecision": True,
        "v11IsTerminal": True,
        "v11TerminalAuthorityOpened": False,
        "v11TerminalAuthorityModified": False,
        "incrementalCostNOK": 0,
        "billingCredentialUsed": False,
    }
    receipt = _write_json(PRESYNTHESIS_RECEIPT_PATH, document)
    return {
        "status": FINAL_STATUS,
        "eligibleDifferentLocalMethods": [],
        "legacyNumbaCacheFileCount": 46,
        "externalNumbaCacheFileCount": cache_after_second["fileCount"],
        "freshProcessReplay": True,
        "protectedBytesUnchanged": True,
        "modelGenerationCallCount": 0,
        "pcmOrWavFilesCreated": 0,
        "synthesisPermitted": False,
        "requiresEditorDecision": True,
        "v11IsTerminal": True,
        "receipt": receipt,
    }


def validate_receipt() -> dict[str, Any]:
    lock = _load_lock()
    try:
        document = json.loads(PRESYNTHESIS_RECEIPT_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PresynthesisError("V12 pre-synthesis authority is unavailable") from error
    exact = {
        "status": FINAL_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "eligibleDifferentLocalMethods": [],
        "legacyNumbaCacheFileCount": 46,
        "networkDownloadsMade": False,
        "networkAttemptCount": 0,
        "modelLoadedForPrewarm": True,
        "referencePromptEncoded": True,
        "modelGenerateCalled": False,
        "modelGenerationCallCount": 0,
        "generatedAudio": False,
        "synthesisExecuted": False,
        "synthesisPermitted": False,
        "comparisonSynthesisPermitted": False,
        "fullGenerationPermitted": False,
        "requiresEditorDecision": True,
        "v11IsTerminal": True,
        "v11TerminalAuthorityOpened": False,
        "v11TerminalAuthorityModified": False,
        "incrementalCostNOK": 0,
        "billingCredentialUsed": False,
    }
    for key, value in exact.items():
        if document.get(key) != value:
            raise PresynthesisError(f"V12 authority drifted at {key}")
    if document.get("script") != _binding(SCRIPT_PATH) or document.get("lock") != _binding(LOCK_PATH):
        raise PresynthesisError("V12 authority source binding drifted")
    if document.get("candidateInventory") != _binding(CANDIDATE_INVENTORY_PATH):
        raise PresynthesisError("V12 candidate inventory binding drifted")
    if document.get("legacyNumbaInventory") != _binding(LEGACY_NUMBA_INVENTORY_PATH):
        raise PresynthesisError("V12 legacy cache inventory binding drifted")
    if document.get("runtimeReceipt") != _binding(RUNTIME_RECEIPT_PATH):
        raise PresynthesisError("V12 runtime receipt binding drifted")
    processes = document.get("preflightProcesses") or []
    if len(processes) != 2 or processes[0].get("processID") == processes[1].get("processID"):
        raise PresynthesisError("V12 authority lacks two fresh preflight processes")
    for process in processes:
        _validate_worker_result(process)
    current_protected = _protected_manifests(lock)
    if current_protected != document["protectedManifests"]["afterSecondPrewarm"]:
        raise PresynthesisError("V12 protected bytes drifted after authorization")
    current_numba = _selected_file_manifest(NUMBA_CACHE_ROOT, {".nbc", ".nbi"})
    if current_numba != document["externalNumbaCache"]["afterSecondPrewarm"]:
        raise PresynthesisError("V12 bound external Numba cache drifted")
    current_audio = _audio_manifests(lock)
    if current_audio != document["audioFileManifests"]["afterSecondPrewarm"]:
        raise PresynthesisError("V12 audio-file inventory drifted")
    candidate = local_method_inventory(lock)
    legacy = legacy_numba_cache_inventory(lock)
    if candidate["eligibleDifferentLocalMethods"] != [] or legacy["cacheFileCount"] != 46:
        raise PresynthesisError("V12 live inventory validation drifted")
    return {
        "status": FINAL_STATUS,
        "authority": _binding(PRESYNTHESIS_RECEIPT_PATH),
        "eligibleDifferentLocalMethods": [],
        "legacyNumbaCacheFileCount": 46,
        "externalNumbaCacheFileCount": current_numba["fileCount"],
        "freshProcessReplay": True,
        "protectedBytesUnchanged": True,
        "modelGenerationCallCount": 0,
        "pcmOrWavFilesCreated": 0,
        "synthesisPermitted": False,
        "requiresEditorDecision": True,
        "v11IsTerminal": True,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("inventory", "prepare", "worker", "preflight", "validate", "run-all"),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "inventory":
            result = write_inventories()
        elif args.command == "prepare":
            result = prepare_runtime()
        elif args.command == "worker":
            result = _worker()
        elif args.command == "preflight":
            result = run_presynthesis_preflight()
        elif args.command == "validate":
            result = validate_receipt()
        else:
            write_inventories()
            prepare_runtime()
            run_presynthesis_preflight()
            result = validate_receipt()
    except (PresynthesisError, OSError, subprocess.SubprocessError) as error:
        print(f"V12 pre-synthesis gate failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
