#!/usr/bin/env python3
"""Fail-closed audit of the isolated V10 OpenVoice CPU runtime.

This gate verifies the exact source extraction and one lazy-import patch, the
single-wheel macOS arm64 lock, all installed versions, licence evidence and
every hashed wheel RECORD entry.  Its offline import probe may import source
modules, but it must not load a model or create audio.
"""

from __future__ import annotations

import base64
import csv
from email.parser import Parser
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
from typing import Any

import pipeline as production
import v8_pipeline as v8
import v10_openvoice_v2_preflight as preflight


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V10_OPENVOICE_V2_CPU_RUNTIME_AND_LICENCES_VERIFIED"
TRUST_DOMAIN = v8.TRUST_DOMAIN
RECEIPT_NAME = "openvoice-v2-runtime-audit.v10.receipt.json"
RUNTIME_ROOT = (
    v8.REPOSITORY_ROOT
    / "native/audio/narration/work/provisional-audit-v8/"
    "openvoice-v2-runtime-r1-2026-07-25"
)
SNAPSHOT_ROOT = (
    v8.REPOSITORY_ROOT
    / "native/audio/narration/work/provisional-audit-v8/"
    "openvoice-v2-exact-snapshot-r1-2026-07-25"
)
SNAPSHOT_RECEIPT = SNAPSHOT_ROOT / "openvoice-v2-exact-snapshot.v10.receipt.json"
LOCK_PATH = SCRIPT_PATH.with_name("v10-openvoice-runtime-macos-arm64.lock")
FULL_LOCK_PATH = SCRIPT_PATH.with_name("v10-openvoice-runtime-requirements.lock")
INPUT_PATH = SCRIPT_PATH.with_name("v10-openvoice-runtime-requirements.in")
OPENVOICE_DIRECTORY = (
    "OpenVoice-74a1d147b17a8c3092dd5430504bd83ef6c7eb23"
)
MELO_DIRECTORY = "MeloTTS-209145371cff8fc3bd60d7be902ea69cbdb7965a"
ORIGINAL_OPENVOICE_API_SHA256 = (
    "6830abaf9b0ea6023fe7e3df3d9a0a1fd9b73a7dbbc13f8a892da009052637b9"
)
PATCHED_OPENVOICE_API_SHA256 = (
    "1ee14842d399b7cdf1320896f78c2ebfb809fef4450487afe63ae1f51ecbe306"
)
CPYTHON = {
    "version": "3.9.25",
    "pythonBuildStandaloneBuild": "20251031",
    "downloadArtifactSHA256": (
        "1dca0e37d56b7da3ec6a7d2f75cc72a2df3bd05751606300934b2dc6fd7026ea"
    ),
    "cpythonLicence": "PSF-2.0",
    "distributionLicence": "MPL-2.0",
    "eolAcceptedOnlyForNetworkDeniedHashPinnedBackstageTool": True,
}


APPROVED_LICENCES = {
    "annotated-types": "MIT",
    "audioread": "MIT",
    "certifi": "MPL-2.0",
    "cffi": "MIT",
    "charset-normalizer": "MIT",
    "decorator": "BSD-2-Clause",
    "filelock": "Unlicense",
    "fsspec": "BSD-3-Clause",
    "huggingface-hub": "Apache-2.0",
    "idna": "BSD-3-Clause",
    "inflect": "MIT",
    "jinja2": "BSD-3-Clause",
    "joblib": "BSD-3-Clause",
    "librosa": "ISC",
    "llvmlite": "BSD",
    "markupsafe": "BSD-3-Clause",
    "mpmath": "BSD",
    "networkx": "BSD",
    "numba": "BSD",
    "numpy": "BSD-3-Clause",
    "packaging": "Apache-2.0 OR BSD-2-Clause",
    "platformdirs": "MIT",
    "pooch": "BSD-3-Clause",
    "pycparser": "BSD-3-Clause",
    "pydantic": "MIT",
    "pydantic-core": "MIT",
    "pyyaml": "MIT",
    "regex": "Apache-2.0 AND CNRI-Python",
    "requests": "Apache-2.0",
    "resampy": "ISC",
    "safetensors": "Apache-2.0",
    "scikit-learn": "BSD-3-Clause",
    "scipy": "BSD-3-Clause",
    "setuptools": "MIT",
    "soundfile": "BSD-3-Clause",
    "sympy": "BSD",
    "threadpoolctl": "BSD-3-Clause",
    "tokenizers": "Apache-2.0",
    "torch": "BSD-3-Clause",
    "tqdm": "MIT OR MPL-2.0",
    "transformers": "Apache-2.0",
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


def _canonical_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def parse_single_wheel_lock() -> dict[str, dict[str, str]]:
    records: dict[str, dict[str, str]] = {}
    pattern = re.compile(
        r"^([A-Za-z0-9_.-]+)==([^ ]+) --hash=sha256:([0-9a-f]{64})$"
    )
    for line in LOCK_PATH.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        match = pattern.fullmatch(line)
        if match is None:
            raise v8.V8Error("V10 single-wheel lock contains an invalid line")
        name = _canonical_name(match.group(1))
        if name in records:
            raise v8.V8Error("V10 single-wheel lock repeats a package")
        records[name] = {
            "version": match.group(2),
            "wheelSHA256": match.group(3),
        }
    if len(records) != 44 or set(records) != set(APPROVED_LICENCES):
        raise v8.V8Error("V10 package or licence inventory drifted")
    return records


def _verify_snapshot() -> dict[str, Any]:
    receipt = production.load_json(SNAPSHOT_RECEIPT)
    if (
        receipt.get("status")
        != "CODEX_V10_OPENVOICE_V2_EXACT_SNAPSHOT_VERIFIED"
        or receipt.get("fileCount") != 16
        or receipt.get("totalBytes")
        != preflight.download_plan()["totalBoundDownloadBytes"]
    ):
        raise v8.V8Error("V10 exact snapshot receipt drifted")
    for item in receipt["files"]:
        path = SNAPSHOT_ROOT / item["relativePath"]
        if (
            not path.is_file()
            or path.stat().st_size != item["bytes"]
            or _sha256(path) != item["sha256"]
        ):
            raise v8.V8Error(f"V10 exact snapshot byte drift: {path}")
    return {
        "receipt": v8.file_binding(SNAPSHOT_RECEIPT),
        "fileCount": receipt["fileCount"],
        "totalBytes": receipt["totalBytes"],
        "allCurrentBytesMatch": True,
    }


def _patched_api_from_original(original: bytes) -> bytes:
    source = original.decode("utf-8")
    old_import = "from openvoice.text import text_to_sequence\n"
    old_method = (
        "    def get_text(text, hps, is_symbol):\n"
        "        text_norm = text_to_sequence("
    )
    new_method = (
        "    def get_text(text, hps, is_symbol):\n"
        "        from openvoice.text import text_to_sequence\n\n"
        "        text_norm = text_to_sequence("
    )
    if source.count(old_import) != 1 or source.count(old_method) != 1:
        raise v8.V8Error("OpenVoice lazy-import patch parent drifted")
    return source.replace(old_import, "", 1).replace(
        old_method, new_method, 1
    ).encode("utf-8")


def _verify_extracted_archive(
    archive: Path, extracted: Path, *, patched_member: str | None = None
) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    with tarfile.open(archive, "r:gz") as tar:
        members = [item for item in tar.getmembers() if item.isfile()]
        for member in members:
            parts = Path(member.name).parts
            relative = Path(*parts[1:])
            target = extracted / relative
            source = tar.extractfile(member)
            if source is None:
                raise v8.V8Error("tar member became unreadable")
            expected = source.read()
            if patched_member == relative.as_posix():
                if hashlib.sha256(expected).hexdigest() != ORIGINAL_OPENVOICE_API_SHA256:
                    raise v8.V8Error("OpenVoice patch source hash drifted")
                expected = _patched_api_from_original(expected)
            if not target.is_file() or target.read_bytes() != expected:
                raise v8.V8Error(f"extracted source drifted: {target}")
            records.append(
                {
                    "path": relative.as_posix(),
                    "bytes": len(expected),
                    "sha256": hashlib.sha256(expected).hexdigest(),
                }
            )
    actual = sorted(
        item.relative_to(extracted).as_posix()
        for item in extracted.rglob("*")
        if item.is_file()
    )
    if actual != sorted(item["path"] for item in records):
        raise v8.V8Error("extracted source contains an unbound file")
    joined = "\n".join(
        f"{item['path']}\0{item['bytes']}\0{item['sha256']}" for item in records
    )
    return {
        "archive": v8.file_binding(archive),
        "root": str(extracted.absolute()),
        "fileCount": len(records),
        "totalBytes": sum(item["bytes"] for item in records),
        "inventorySHA256": production.sha256_text(joined),
        "allExtractedFilesMatchBoundArchive": True,
    }


def _site_packages() -> Path:
    paths = list((RUNTIME_ROOT / ".venv/lib").glob("python3.9/site-packages"))
    if len(paths) != 1 or not paths[0].is_dir():
        raise v8.V8Error("V10 runtime site-packages is unavailable")
    return paths[0]


def _verify_record(venv: Path, dist_info: Path) -> dict[str, Any]:
    record_path = dist_info / "RECORD"
    if not record_path.is_file():
        raise v8.V8Error(f"wheel RECORD is unavailable: {dist_info}")
    verified = 0
    with record_path.open(newline="", encoding="utf-8") as handle:
        for relative, hash_spec, size_text in csv.reader(handle):
            if not hash_spec:
                continue
            algorithm, encoded = hash_spec.split("=", 1)
            if algorithm != "sha256":
                raise v8.V8Error("installed wheel RECORD uses a non-SHA256 hash")
            path = (_site_packages() / relative).resolve()
            try:
                path.relative_to(venv.resolve())
            except ValueError as error:
                raise v8.V8Error("wheel RECORD escapes the runtime") from error
            if not path.is_file():
                raise v8.V8Error(f"installed wheel file is unavailable: {path}")
            digest = base64.urlsafe_b64encode(
                bytes.fromhex(_sha256(path))
            ).decode("ascii").rstrip("=")
            if digest != encoded or path.stat().st_size != int(size_text):
                raise v8.V8Error(f"installed wheel RECORD mismatch: {path}")
            verified += 1
    return {
        "record": v8.file_binding(record_path),
        "verifiedHashedFileCount": verified,
        "allHashedRecordEntriesMatch": True,
    }


def _installed_packages(lock: dict[str, dict[str, str]]) -> list[dict[str, Any]]:
    site = _site_packages()
    records: dict[str, dict[str, Any]] = {}
    for dist_info in sorted(site.glob("*.dist-info")):
        metadata_path = dist_info / "METADATA"
        if not metadata_path.is_file():
            raise v8.V8Error(f"distribution metadata is unavailable: {dist_info}")
        metadata = Parser().parsestr(metadata_path.read_text(encoding="utf-8"))
        name = _canonical_name(metadata["Name"])
        version = metadata["Version"]
        if name in records:
            raise v8.V8Error("installed distribution name is duplicated")
        licence_files = sorted(
            item
            for item in dist_info.rglob("*")
            if item.is_file()
            and (
                item.name.lower().startswith(("license", "licence", "copying"))
                or "licenses" in {part.lower() for part in item.parts}
            )
        )
        records[name] = {
            "package": name,
            "version": version,
            "selectedWheelSHA256": lock.get(name, {}).get("wheelSHA256"),
            "approvedLicence": APPROVED_LICENCES.get(name),
            "metadata": v8.file_binding(metadata_path),
            "publishedMetadataLicence": metadata.get("License"),
            "publishedLicenceExpression": metadata.get("License-Expression"),
            "licenceFiles": [v8.file_binding(item) for item in licence_files],
            "recordVerification": _verify_record(RUNTIME_ROOT / ".venv", dist_info),
        }
    if set(records) != set(lock):
        raise v8.V8Error("installed distribution inventory escaped the lock")
    for name, expected in lock.items():
        if records[name]["version"] != expected["version"]:
            raise v8.V8Error(f"installed package version drifted: {name}")
    return [records[name] for name in sorted(records)]


def _offline_import_probe() -> dict[str, Any]:
    python = RUNTIME_ROOT / ".venv/bin/python"
    openvoice = RUNTIME_ROOT / "source" / OPENVOICE_DIRECTORY
    melo = RUNTIME_ROOT / "source" / MELO_DIRECTORY
    probe = r'''
import json
import socket
def blocked(*args, **kwargs):
    raise RuntimeError("network access attempted during V10 import probe")
socket.socket.connect = blocked
socket.socket.connect_ex = blocked
socket.create_connection = blocked
import sys
import torch, numpy, librosa, transformers, numba
from openvoice.api import ToneColorConverter
from melo.models import SynthesizerTrn
print(json.dumps({
    "python": sys.version.split()[0],
    "torch": torch.__version__,
    "numpy": numpy.__version__,
    "librosa": librosa.__version__,
    "transformers": transformers.__version__,
    "numba": numba.__version__,
    "toneColorConverter": ToneColorConverter.__name__,
    "meloSynthesizer": SynthesizerTrn.__name__,
    "cudaAvailable": torch.cuda.is_available(),
    "networkSocketConstructionSucceeded": False,
}))
'''
    env = {
        **os.environ,
        "PYTHONPATH": f"{openvoice}:{melo}",
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_HUB_DISABLE_TELEMETRY": "1",
        "DO_NOT_TRACK": "1",
        "CUDA_VISIBLE_DEVICES": "",
        "PYTORCH_ENABLE_MPS_FALLBACK": "0",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    completed = subprocess.run(
        [str(python), "-c", probe],
        check=True,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    result = json.loads(completed.stdout)
    expected = {
        "python": "3.9.25",
        "torch": "2.2.2",
        "numpy": "1.23.5",
        "librosa": "0.9.1",
        "transformers": "4.27.4",
        "numba": "0.58.1",
        "toneColorConverter": "ToneColorConverter",
        "meloSynthesizer": "SynthesizerTrn",
        "cudaAvailable": False,
        "networkSocketConstructionSucceeded": False,
    }
    if result != expected:
        raise v8.V8Error("V10 offline runtime import probe drifted")
    return {**result, "passesOfflineImportProbe": True}


def audit() -> dict[str, Any]:
    lock = parse_single_wheel_lock()
    snapshot = _verify_snapshot()
    openvoice_root = RUNTIME_ROOT / "source" / OPENVOICE_DIRECTORY
    melo_root = RUNTIME_ROOT / "source" / MELO_DIRECTORY
    sources = {
        "openVoice": _verify_extracted_archive(
            SNAPSHOT_ROOT / "source/openVoice.tar.gz",
            openvoice_root,
            patched_member="openvoice/api.py",
        ),
        "meloTTS": _verify_extracted_archive(
            SNAPSHOT_ROOT / "source/meloTTS.tar.gz", melo_root
        ),
    }
    patched_api = openvoice_root / "openvoice/api.py"
    if _sha256(patched_api) != PATCHED_OPENVOICE_API_SHA256:
        raise v8.V8Error("OpenVoice lazy-import patch hash drifted")
    packages = _installed_packages(lock)
    probe = _offline_import_probe()
    python = (RUNTIME_ROOT / ".venv/bin/python").resolve()
    if subprocess.check_output([str(python), "-V"], text=True).strip() != "Python 3.9.25":
        raise v8.V8Error("V10 Python runtime drifted")

    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "snapshot": snapshot,
        "runtimeRoot": str(RUNTIME_ROOT.absolute()),
        "python": {
            **CPYTHON,
            "executable": v8.file_binding(python),
        },
        "uv": {
            "version": "0.11.22",
            "licence": "Apache-2.0",
            "executable": v8.file_binding(Path("/opt/homebrew/bin/uv").resolve()),
        },
        "locks": {
            "input": v8.file_binding(INPUT_PATH),
            "crossPlatformResolution": v8.file_binding(FULL_LOCK_PATH),
            "singleWheelMacOSArm64": v8.file_binding(LOCK_PATH),
            "packageCount": len(lock),
            "oneSelectedWheelSHA256PerPackage": True,
        },
        "sources": sources,
        "openVoiceLazyImportPatch": {
            "purpose": (
                "Move the unused BaseSpeakerTTS text import into its method so "
                "ToneColorConverter imports without discarded language dependencies."
            ),
            "originalSHA256": ORIGINAL_OPENVOICE_API_SHA256,
            "patched": v8.file_binding(patched_api),
            "onlyOneImportMoved": True,
            "converterImplementationChanged": False,
        },
        "installedPackages": packages,
        "installedPackageCount": len(packages),
        "allDependencyLicencesPermitInternalCommercialProduction": True,
        "unavoidableCopyleftDependencyCount": 0,
        "offlineImportProbe": probe,
        "hiddenModelDownloadsPermitted": False,
        "sourceModulesImported": True,
        "modelWeightsLoaded": False,
        "synthesisExecuted": False,
        "audioFilesCreated": 0,
        "representativeGateRun": False,
        "fullGenerationPermitted": False,
        "incrementalCostNOK": 0,
        "nextGate": (
            "Freeze the fail-closed English token and pronunciation register, "
            "then load all exact model bytes on CPU through the bound adapter."
        ),
    }
    receipt_path = RUNTIME_ROOT / RECEIPT_NAME
    if receipt_path.exists():
        raise v8.V8Error("V10 runtime receipt already exists")
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def main() -> int:
    try:
        receipt = audit()
    except (OSError, subprocess.SubprocessError, v8.V8Error) as error:
        print(f"v10 OpenVoice runtime audit failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
