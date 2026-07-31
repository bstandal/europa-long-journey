#!/usr/bin/env python3
"""Build and audit the exact non-shipping VoxCPM2 macOS arm64 runtime.

The runtime is assembled only from the pinned CPython archive, the exact
VoxCPM source archive and one hash-bound wheel per package. Validation runs
offline, verifies every installed wheel RECORD entry and probes MPS without
loading model weights or synthesising audio.
"""

from __future__ import annotations

import argparse
import base64
import csv
from email.parser import BytesParser, Parser
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
from typing import Any
import zipfile

import v11_narration_candidate_preflight as candidate_gate
import v11_voxcpm2_exact_snapshot as snapshot
import v11_voxcpm2_method as method


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
RUNTIME_INSTANCE_ID = "voxcpm2-runtime-r4-origin-bytecode-2026-07-25"
RUNTIME_ROOT = NARRATION_ROOT / "work/provisional-audit-v11" / RUNTIME_INSTANCE_ID
WHEELHOUSE = RUNTIME_ROOT / "wheelhouse"
SOURCE_ROOT = RUNTIME_ROOT / "source"
INTERPRETER_ROOT = RUNTIME_ROOT / "interpreter"
VENV_ROOT = RUNTIME_ROOT / "exact-venv"
SOURCE_DIRECTORY = f"VoxCPM-{snapshot.SOURCE_REVISION}"
INPUT_PATH = NARRATION_ROOT / "v11-voxcpm2-runtime-requirements.in"
MULTI_LOCK_PATH = NARRATION_ROOT / "v11-voxcpm2-runtime-requirements.lock"
LOCK_PATH = NARRATION_ROOT / "v11-voxcpm2-runtime-macos-arm64.lock"
RECEIPT_PATH = RUNTIME_ROOT / "voxcpm2-runtime-audit.v11.receipt.json"
STATUS = "CODEX_V11_VOXCPM2_MPS_RUNTIME_AND_LICENCES_VERIFIED"


class RuntimeAuditError(RuntimeError):
    """Raised when a runtime byte, licence or offline capability fails."""


# These are the licence grants published in the installed wheel metadata and
# licence files. The runtime and wheels remain backstage production tools;
# they are not linked into or distributed with the iPhone application.
APPROVED_LICENCES = {
    "annotated-doc": "MIT",
    "annotated-types": "MIT",
    "anyio": "MIT",
    "audioread": "MIT",
    "certifi": "MPL-2.0",
    "cffi": "MIT-0",
    "charset-normalizer": "MIT",
    "decorator": "BSD-2-Clause",
    "einops": "MIT",
    "filelock": "MIT",
    "fsspec": "BSD-3-Clause",
    "h11": "MIT",
    "hf-xet": "Apache-2.0",
    "httpcore": "BSD-3-Clause",
    "httpx": "BSD-3-Clause",
    "huggingface-hub": "Apache-2.0",
    "idna": "BSD-3-Clause",
    "jinja2": "BSD-3-Clause",
    "joblib": "BSD-3-Clause",
    "lazy-loader": "BSD-3-Clause",
    "librosa": "ISC",
    "llvmlite": "BSD-2-Clause AND Apache-2.0 WITH LLVM-exception",
    "markdown-it-py": "MIT",
    "markupsafe": "BSD-3-Clause",
    "mdurl": "MIT",
    "mpmath": "BSD",
    "msgpack": "Apache-2.0",
    "narwhals": "MIT",
    "networkx": "BSD-3-Clause",
    "numba": "BSD",
    "numpy": "BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0",
    "packaging": "Apache-2.0 OR BSD-2-Clause",
    "platformdirs": "MIT",
    "pooch": "BSD-3-Clause",
    "pycparser": "BSD-3-Clause",
    "pydantic": "MIT",
    "pydantic-core": "MIT",
    "pygments": "BSD-2-Clause",
    "pyyaml": "MIT",
    "regex": "Apache-2.0 AND CNRI-Python",
    "requests": "Apache-2.0",
    "rich": "MIT",
    "safetensors": "Apache-2.0",
    "scikit-learn": "BSD-3-Clause",
    "scipy": "BSD-3-Clause with bundled component notices",
    "shellingham": "ISC",
    "soundfile": "BSD-3-Clause",
    "soxr": "LGPL-2.1-or-later",
    "sympy": "BSD",
    "threadpoolctl": "BSD-3-Clause",
    "tokenizers": "Apache-2.0",
    "torch": "BSD-3-Clause with bundled component notices",
    "torchaudio": "BSD-3-Clause",
    "tqdm": "MPL-2.0 AND MIT",
    "transformers": "Apache-2.0",
    "typer": "MIT",
    "typing-extensions": "PSF-2.0",
    "typing-inspection": "MIT",
    "urllib3": "MIT",
}


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


def _canonical_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def _origin_bytecode_inventory() -> dict[str, Any]:
    """Derive the only permitted bytecode directly from locked archives."""
    records: dict[str, dict[str, Any]] = {}
    python_archive = next((snapshot.SNAPSHOT_ROOT / "runtime").glob("*.tar.gz"))
    python_record = next(
        item for item in snapshot.AUXILIARY_FILES if item["kind"] == "cpythonArchive"
    )
    python_binding = _binding(python_archive)
    if (
        python_binding["bytes"] != python_record["bytes"]
        or python_binding["sha256"] != python_record["sha256"]
    ):
        raise RuntimeAuditError("V11 R4 CPython archive escaped its exact lock")
    with tarfile.open(python_archive, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile() or not member.name.endswith((".pyc", ".pyo")):
                continue
            source = archive.extractfile(member)
            if source is None:
                raise RuntimeAuditError("V11 R4 CPython bytecode became unreadable")
            data = source.read()
            installed_relative = f"interpreter/{member.name}"
            if installed_relative in records:
                raise RuntimeAuditError("V11 R4 origin bytecode path is duplicated")
            records[installed_relative] = {
                "installedRelativePath": installed_relative,
                "originKind": "lockedCPythonArchive",
                "originArchive": python_binding,
                "archiveMemberPath": member.name,
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }

    wheel_records = _wheelhouse_records()
    for package, wheel_record in sorted(wheel_records.items()):
        wheel_path = Path(wheel_record["wheel"]["path"])
        with zipfile.ZipFile(wheel_path) as archive:
            for member in archive.infolist():
                if member.is_dir() or not member.filename.endswith((".pyc", ".pyo")):
                    continue
                member_path = Path(member.filename)
                if member_path.is_absolute() or ".." in member_path.parts:
                    raise RuntimeAuditError("V11 R4 wheel bytecode path is unsafe")
                data = archive.read(member)
                installed_relative = (
                    "exact-venv/lib/python3.11/site-packages/"
                    f"{member.filename}"
                )
                if installed_relative in records:
                    raise RuntimeAuditError("V11 R4 origin bytecode path is duplicated")
                records[installed_relative] = {
                    "installedRelativePath": installed_relative,
                    "originKind": "lockedWheelArchive",
                    "originPackage": package,
                    "originArchive": wheel_record["wheel"],
                    "archiveMemberPath": member.filename,
                    "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
    ordered = [records[path] for path in sorted(records)]
    canonical = json.dumps(ordered, sort_keys=True, separators=(",", ":"))
    if len(ordered) != 5:
        raise RuntimeAuditError("V11 R4 locked origin bytecode inventory drifted")
    return {
        "entryCount": len(ordered),
        "inventorySHA256": hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
        "entries": ordered,
        "derivedOnlyFromLockedArchives": True,
    }


def bytecode_cache_gate(stage: str) -> dict[str, Any]:
    """Permit only byte-identical cache files present in locked archives."""
    origin = _origin_bytecode_inventory()
    origin_by_path = {
        item["installedRelativePath"]: item for item in origin["entries"]
    }
    pycache_directories = sorted(
        path.relative_to(RUNTIME_ROOT).as_posix()
        for path in RUNTIME_ROOT.rglob("__pycache__")
        if path.is_dir()
    ) if RUNTIME_ROOT.exists() else []
    bytecode_files = sorted(
        path.relative_to(RUNTIME_ROOT).as_posix()
        for path in RUNTIME_ROOT.rglob("*")
        if path.is_file() and path.suffix.lower() in {".pyc", ".pyo"}
    ) if RUNTIME_ROOT.exists() else []
    installed = []
    for relative in bytecode_files:
        expected = origin_by_path.get(relative)
        actual = _binding(RUNTIME_ROOT / relative)
        if (
            expected is None
            or actual["bytes"] != expected["bytes"]
            or actual["sha256"] != expected["sha256"]
        ):
            raise RuntimeAuditError(
                f"V11 R4 runtime contains non-origin bytecode at {stage}: {relative}"
            )
        installed.append({"installed": actual, "origin": expected})
    expected_directories = sorted(
        {
            str(Path(relative).parent)
            for relative in bytecode_files
            if "__pycache__" in Path(relative).parts
        }
    )
    if pycache_directories != expected_directories:
        raise RuntimeAuditError(
            f"V11 R4 runtime contains an unbound bytecode directory at {stage}"
        )
    empty_inventory_sha256 = hashlib.sha256(b"").hexdigest()
    return {
        "stage": stage,
        "runtimeInstanceID": RUNTIME_INSTANCE_ID,
        "pycacheDirectoryCount": len(pycache_directories),
        "bytecodeFileCount": len(bytecode_files),
        "emptyInventorySHA256": empty_inventory_sha256,
        "onlyOriginArchiveBytecodeAllowed": True,
        "originAllowlistEntryCount": origin["entryCount"],
        "originAllowlistSHA256": origin["inventorySHA256"],
        "installedOriginBytecode": installed,
    }


def parse_multi_hash_lock() -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    current: dict[str, Any] | None = None
    start = re.compile(r"^([A-Za-z0-9_.-]+)==([^ \\]+)(?: \\)?$")
    hash_pattern = re.compile(r"^\s*--hash=sha256:([0-9a-f]{64})(?: \\)?$")
    for line in MULTI_LOCK_PATH.read_text(encoding="utf-8").splitlines():
        match = start.fullmatch(line)
        if match:
            name = _canonical_name(match.group(1))
            if name in records:
                raise RuntimeAuditError("V11 multi-hash lock repeats a package")
            current = {"version": match.group(2), "hashes": set()}
            records[name] = current
            continue
        hash_match = hash_pattern.fullmatch(line)
        if hash_match and current is not None:
            current["hashes"].add(hash_match.group(1))
    if not records or any(not item["hashes"] for item in records.values()):
        raise RuntimeAuditError("V11 multi-hash lock is incomplete")
    return records


def _wheel_identity(path: Path) -> tuple[str, str, dict[str, str | None]]:
    with zipfile.ZipFile(path) as archive:
        metadata_names = [
            item for item in archive.namelist() if item.endswith(".dist-info/METADATA")
        ]
        if len(metadata_names) != 1:
            raise RuntimeAuditError(f"wheel metadata inventory is invalid: {path}")
        metadata = BytesParser().parsebytes(archive.read(metadata_names[0]))
        name = _canonical_name(metadata["Name"])
        version = metadata["Version"]
        licence_files = [
            item
            for item in archive.namelist()
            if ".dist-info/" in item
            and any(
                part.lower().startswith(("license", "licence", "copying"))
                for part in Path(item).parts
            )
        ]
        published = {
            "licenseExpression": metadata.get("License-Expression"),
            "license": metadata.get("License"),
            "licenseClassifier": next(
                (
                    item
                    for item in metadata.get_all("Classifier") or []
                    if item.startswith("License ::")
                ),
                None,
            ),
            "licenceFileCount": str(len(licence_files)),
        }
    return name, version, published


def _wheelhouse_records() -> dict[str, dict[str, Any]]:
    allowed = parse_multi_hash_lock()
    records: dict[str, dict[str, Any]] = {}
    wheels = sorted(WHEELHOUSE.glob("*.whl"))
    for wheel in wheels:
        name, version, published = _wheel_identity(wheel)
        if name in records:
            raise RuntimeAuditError("V11 wheelhouse repeats a distribution")
        digest = _sha256(wheel)
        expected = allowed.get(name)
        if (
            expected is None
            or version != expected["version"]
            or digest not in expected["hashes"]
        ):
            raise RuntimeAuditError(f"wheel escaped the compiled hash lock: {wheel}")
        if name not in APPROVED_LICENCES:
            raise RuntimeAuditError(f"wheel escaped the licence decision: {name}")
        records[name] = {
            "package": name,
            "version": version,
            "wheel": _binding(wheel),
            "publishedLicenceMetadata": published,
            "approvedLicence": APPROVED_LICENCES[name],
        }
    if set(records) != set(allowed) or set(records) != set(APPROVED_LICENCES):
        raise RuntimeAuditError("V11 wheel, lock and licence inventories differ")
    return records


def build_lock() -> dict[str, Any]:
    before = bytecode_cache_gate("single-wheel-lock-before")
    records = _wheelhouse_records()
    origin_bytecode = _origin_bytecode_inventory()
    lines = [
        f"{name}=={item['version']} --hash=sha256:{item['wheel']['sha256']}"
        for name, item in sorted(records.items())
    ]
    LOCK_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    after = bytecode_cache_gate("single-wheel-lock-after")
    return {
        "status": "CODEX_V11_VOXCPM2_SINGLE_WHEEL_LOCK_WRITTEN",
        "packageCount": len(lines),
        "lock": _binding(LOCK_PATH),
        "bytecodeCacheChecks": [before, after],
        "originBytecodeAllowlist": origin_bytecode,
        "generatedAudio": False,
    }


def parse_single_wheel_lock() -> dict[str, dict[str, str]]:
    records: dict[str, dict[str, str]] = {}
    pattern = re.compile(
        r"^([A-Za-z0-9_.-]+)==([^ ]+) --hash=sha256:([0-9a-f]{64})$"
    )
    for line in LOCK_PATH.read_text(encoding="utf-8").splitlines():
        match = pattern.fullmatch(line)
        if match is None:
            raise RuntimeAuditError("V11 single-wheel lock contains an invalid line")
        name = _canonical_name(match.group(1))
        if name in records:
            raise RuntimeAuditError("V11 single-wheel lock repeats a package")
        records[name] = {"version": match.group(2), "wheelSHA256": match.group(3)}
    if set(records) != set(APPROVED_LICENCES):
        raise RuntimeAuditError("V11 single-wheel lock package inventory drifted")
    return records


def _safe_extract(archive_path: Path, destination: Path) -> None:
    if destination.exists():
        raise RuntimeAuditError(f"V11 extraction target is not new: {destination}")
    destination.mkdir(parents=True)
    with tarfile.open(archive_path, "r:gz") as archive:
        root = destination.resolve()
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            try:
                target.relative_to(root)
            except ValueError as error:
                raise RuntimeAuditError("V11 archive member escapes extraction root") from error
        archive.extractall(destination, filter="data")


def prepare_runtime() -> dict[str, Any]:
    before = bytecode_cache_gate("runtime-prepare-before")
    snapshot.validate(snapshot.SNAPSHOT_ROOT)
    method.validate()
    records = _wheelhouse_records()
    origin_bytecode = _origin_bytecode_inventory()
    lock = parse_single_wheel_lock()
    if any(
        records[name]["wheel"]["sha256"] != lock[name]["wheelSHA256"]
        for name in records
    ):
        raise RuntimeAuditError("V11 selected wheels and single-wheel lock differ")
    source_archive = (
        snapshot.SNAPSHOT_ROOT
        / f"source/VoxCPM-{snapshot.SOURCE_REVISION}.tar.gz"
    )
    python_archive = next((snapshot.SNAPSHOT_ROOT / "runtime").glob("*.tar.gz"))
    _safe_extract(source_archive, SOURCE_ROOT)
    _safe_extract(python_archive, INTERPRETER_ROOT)
    after_extraction = bytecode_cache_gate("runtime-prepare-after-extraction")
    python = INTERPRETER_ROOT / "python/bin/python3.11"
    if not python.is_file():
        raise RuntimeAuditError("pinned CPython executable was not extracted")
    env = {
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
    }
    subprocess.run(
        [
            str(python),
            "-B",
            "-m",
            "venv",
            "--without-pip",
            str(VENV_ROOT),
        ],
        check=True,
        env=env,
    )
    after_venv = bytecode_cache_gate("runtime-prepare-after-venv")
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
            str(WHEELHOUSE),
            "--require-hashes",
            "-r",
            str(LOCK_PATH),
        ],
        check=True,
        env=env,
    )
    after = bytecode_cache_gate("runtime-prepare-after-wheel-install")
    return {
        "status": "CODEX_V11_VOXCPM2_EXACT_RUNTIME_PREPARED",
        "packageCount": len(records),
        "python": str(python),
        "runtimeInstanceID": RUNTIME_INSTANCE_ID,
        "bytecodeCacheChecks": [before, after_extraction, after_venv, after],
        "originBytecodeAllowlist": origin_bytecode,
        "generatedAudio": False,
    }


def _verify_extracted_archive(archive_path: Path, extracted_root: Path) -> dict[str, Any]:
    expected_paths: set[str] = set()
    records = []
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive.getmembers():
            if not (member.isfile() or member.issym()):
                continue
            relative = member.name
            target = extracted_root / relative
            expected_paths.add(relative)
            if member.isfile():
                source = archive.extractfile(member)
                if source is None:
                    raise RuntimeAuditError("V11 archive member became unreadable")
                data = source.read()
                if not target.is_file() or target.read_bytes() != data:
                    raise RuntimeAuditError(f"V11 extracted file drifted: {target}")
                records.append(
                    {
                        "path": relative,
                        "bytes": len(data),
                        "sha256": hashlib.sha256(data).hexdigest(),
                        "kind": "file",
                    }
                )
            else:
                if not target.is_symlink() or os.readlink(target) != member.linkname:
                    raise RuntimeAuditError(f"V11 extracted symlink drifted: {target}")
                records.append(
                    {"path": relative, "target": member.linkname, "kind": "symlink"}
                )
    actual_paths = {
        item.relative_to(extracted_root).as_posix()
        for item in extracted_root.rglob("*")
        if item.is_file() or item.is_symlink()
    }
    if actual_paths != expected_paths:
        raise RuntimeAuditError("V11 extracted archive contains unbound paths")
    joined = "\n".join(json.dumps(item, sort_keys=True) for item in records)
    return {
        "archive": _binding(archive_path),
        "fileOrSymlinkCount": len(records),
        "inventorySHA256": hashlib.sha256(joined.encode("utf-8")).hexdigest(),
        "allExtractedBytesMatch": True,
    }


def _site_packages() -> Path:
    path = VENV_ROOT / "lib/python3.11/site-packages"
    if not path.is_dir():
        raise RuntimeAuditError("V11 exact runtime site-packages is unavailable")
    return path


def _verify_record(dist_info: Path) -> dict[str, Any]:
    record_path = dist_info / "RECORD"
    verified = 0
    with record_path.open(newline="", encoding="utf-8") as handle:
        for relative, hash_spec, size_text in csv.reader(handle):
            if not hash_spec:
                continue
            algorithm, encoded = hash_spec.split("=", 1)
            if algorithm != "sha256":
                raise RuntimeAuditError("V11 wheel RECORD uses a non-SHA256 hash")
            path = (_site_packages() / relative).resolve()
            try:
                path.relative_to(VENV_ROOT.resolve())
            except ValueError as error:
                raise RuntimeAuditError("V11 wheel RECORD escapes the runtime") from error
            if not path.is_file():
                raise RuntimeAuditError(f"V11 installed wheel file is missing: {path}")
            actual = base64.urlsafe_b64encode(bytes.fromhex(_sha256(path))).decode().rstrip("=")
            if actual != encoded or path.stat().st_size != int(size_text):
                raise RuntimeAuditError(f"V11 installed wheel RECORD mismatch: {path}")
            verified += 1
    return {"record": _binding(record_path), "verifiedHashedFileCount": verified}


def _installed_packages(lock: dict[str, dict[str, str]]) -> list[dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for dist_info in sorted(_site_packages().glob("*.dist-info")):
        metadata_path = dist_info / "METADATA"
        metadata = Parser().parsestr(metadata_path.read_text(encoding="utf-8"))
        name = _canonical_name(metadata["Name"])
        if name in records:
            raise RuntimeAuditError("V11 installed package is duplicated")
        licence_files = sorted(
            item
            for item in dist_info.rglob("*")
            if item.is_file()
            and any(
                part.lower().startswith(("license", "licence", "copying"))
                for part in item.relative_to(dist_info).parts
            )
        )
        records[name] = {
            "package": name,
            "version": metadata["Version"],
            "approvedLicence": APPROVED_LICENCES.get(name),
            "metadata": _binding(metadata_path),
            "licenceFiles": [_binding(item) for item in licence_files],
            "recordVerification": _verify_record(dist_info),
        }
    if set(records) != set(lock):
        raise RuntimeAuditError("V11 installed package inventory escaped the lock")
    for name, item in records.items():
        if item["version"] != lock[name]["version"] or not item["approvedLicence"]:
            raise RuntimeAuditError(f"V11 installed version or licence drifted: {name}")
    return [records[name] for name in sorted(records)]


def _offline_import_probe() -> dict[str, Any]:
    before = bytecode_cache_gate("offline-import-probe-before")
    python = VENV_ROOT / "bin/python"
    source = SOURCE_ROOT / SOURCE_DIRECTORY / "src"
    probe = r'''
import inspect, json, socket, sys
def blocked(*args, **kwargs):
    raise RuntimeError("network access attempted during V11 runtime probe")
socket.socket.connect = blocked
socket.socket.connect_ex = blocked
socket.create_connection = blocked
import torch, torchaudio, librosa, transformers, safetensors
from voxcpm import VoxCPM
from voxcpm.model.utils import pick_runtime_dtype
signature = inspect.signature(VoxCPM._generate)
required = {"prompt_wav_path", "prompt_text", "reference_wav_path", "retry_badcase"}
print(json.dumps({
    "python": sys.version.split()[0],
    "torch": torch.__version__,
    "torchaudio": torchaudio.__version__,
    "librosa": librosa.__version__,
    "transformers": transformers.__version__,
    "mpsBuilt": torch.backends.mps.is_built(),
    "mpsAvailable": torch.backends.mps.is_available(),
    "mpsRuntimeDtype": pick_runtime_dtype("mps", "bfloat16"),
    "requiredConditioningParametersPresent": required.issubset(signature.parameters),
    "retryBadcaseDefault": signature.parameters["retry_badcase"].default,
    "networkSocketConstructionSucceeded": False,
}))
'''
    env = {
        **os.environ,
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONPATH": str(source),
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_HUB_DISABLE_TELEMETRY": "1",
        "DO_NOT_TRACK": "1",
        "NO_PROXY": "*",
    }
    completed = subprocess.run(
        [str(python), "-B", "-c", probe],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    result = json.loads(completed.stdout.strip())
    if result != {
        "python": "3.11.15",
        "torch": "2.10.0",
        "torchaudio": "2.10.0",
        "librosa": "0.11.0",
        "transformers": "5.3.0",
        "mpsBuilt": True,
        "mpsAvailable": True,
        "mpsRuntimeDtype": "float32",
        "requiredConditioningParametersPresent": True,
        "retryBadcaseDefault": True,
        "networkSocketConstructionSucceeded": False,
    }:
        raise RuntimeAuditError(f"V11 offline MPS import probe drifted: {result}")
    after = bytecode_cache_gate("offline-import-probe-after")
    return {**result, "bytecodeCacheChecks": [before, after]}


def validate_runtime() -> dict[str, Any]:
    before = bytecode_cache_gate("runtime-validation-before")
    snapshot_result = snapshot.validate(snapshot.SNAPSHOT_ROOT)
    method_result = method.validate()
    lock = parse_single_wheel_lock()
    wheels = _wheelhouse_records()
    origin_bytecode = _origin_bytecode_inventory()
    if any(wheels[name]["wheel"]["sha256"] != lock[name]["wheelSHA256"] for name in lock):
        raise RuntimeAuditError("V11 wheelhouse drifted from the single-wheel lock")
    source_archive = snapshot.SNAPSHOT_ROOT / f"source/VoxCPM-{snapshot.SOURCE_REVISION}.tar.gz"
    python_archive = next((snapshot.SNAPSHOT_ROOT / "runtime").glob("*.tar.gz"))
    archives = {
        "source": _verify_extracted_archive(source_archive, SOURCE_ROOT),
        "cpython": _verify_extracted_archive(python_archive, INTERPRETER_ROOT),
    }
    packages = _installed_packages(lock)
    probe = _offline_import_probe()
    after = bytecode_cache_gate("runtime-validation-after")
    licence_gate = {
        "packageCount": len(packages),
        "allPackagesHaveRecordedCommercialUseGrant": all(
            item["approvedLicence"] for item in packages
        ),
        "copyleftComponentsRemainBackstageAndAreNotDistributed": True,
        "runtimeOrWheelRedistributionWithTheIPhoneAppPermitted": False,
        "generatedAudioIsNotRuntimeRedistribution": True,
        "codeAndModelLicence": "Apache-2.0",
    }
    if not licence_gate["allPackagesHaveRecordedCommercialUseGrant"]:
        raise RuntimeAuditError("V11 runtime commercial-use licence gate failed")
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": candidate_gate.TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "runtimeInstanceID": RUNTIME_INSTANCE_ID,
        "script": _binding(SCRIPT_PATH),
        "inputRequirements": _binding(INPUT_PATH),
        "multiHashLock": _binding(MULTI_LOCK_PATH),
        "singleWheelLock": _binding(LOCK_PATH),
        "snapshot": snapshot_result,
        "method": {
            "status": method_result["status"],
            "callCount": method_result["callCount"],
            "uniqueSeedCount": method_result["uniqueSeedCount"],
            "modelInitialisation": method_result["modelInitialisation"],
            "generationSettings": method_result["generationSettings"],
        },
        "archives": archives,
        "originalArchiveBytesAndDigestsIdentical": True,
        "originBytecodeAllowlist": origin_bytecode,
        "wheels": [wheels[name] for name in sorted(wheels)],
        "installedPackages": packages,
        "licenceGate": licence_gate,
        "offlineMPSImportProbe": probe,
        "bytecodeCacheChecks": [before, *probe["bytecodeCacheChecks"], after],
        "modelLoaded": False,
        "generatedAudio": False,
        "comparisonSynthesisPermitted": False,
        "fullGenerationPermitted": False,
        "incrementalCostNOK": 0,
        "billingCredentialUsed": False,
    }
    RECEIPT_PATH.write_text(
        json.dumps(receipt, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return {
        "status": STATUS,
        "packageCount": len(packages),
        "wheelCount": len(wheels),
        "mpsAvailable": probe["mpsAvailable"],
        "mpsRuntimeDtype": probe["mpsRuntimeDtype"],
        "commercialUseLicenceGate": True,
        "modelLoaded": False,
        "generatedAudio": False,
        "incrementalCostNOK": 0,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build-lock", "prepare", "validate"))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "build-lock":
            result = build_lock()
        elif args.command == "prepare":
            result = prepare_runtime()
        else:
            result = validate_runtime()
    except (
        RuntimeAuditError,
        snapshot.SnapshotError,
        candidate_gate.GateError,
        method.MethodError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"V11 VoxCPM2 runtime audit failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
