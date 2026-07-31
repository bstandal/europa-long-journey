#!/usr/bin/env python3
"""Download and verify the exact non-synthesising VoxCPM2 V11 snapshot.

The download command accepts one attempt for every source, interpreter and
model file. Every byte is written to a temporary path, checked against its
frozen size and SHA-256, and only then activated. It never imports VoxCPM,
loads a model or creates audio.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any
import urllib.request

import v11_narration_candidate_preflight as candidate_gate


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
SNAPSHOT_ROOT = (
    NARRATION_ROOT
    / "work/provisional-audit-v11/voxcpm2-exact-snapshot-r1-2026-07-25"
)
RECEIPT_NAME = "voxcpm2-exact-snapshot.v11.receipt.json"
STATUS = "CODEX_V11_VOXCPM2_EXACT_SNAPSHOT_VERIFIED"
MODEL_ID = "openbmb/VoxCPM2"
MODEL_REVISION = "bffb3df5a29440629464e5e839f4d214c8714c3d"
MODEL_API_URL = (
    "https://huggingface.co/api/models/openbmb/VoxCPM2/revision/"
    f"{MODEL_REVISION}?blobs=true"
)
SOURCE_REVISION = "19b6bf7590025418821a86dcb817504e0ad7e5df"


class SnapshotError(RuntimeError):
    """Raised when any V11 snapshot prerequisite or byte fails closed."""


MODEL_FILES: tuple[dict[str, Any], ...] = (
    {
        "path": ".gitattributes",
        "bytes": 1519,
        "blobID": "a6344aac8c09253b3b630fb776ae94478aa0275b",
        "lfsSHA256": None,
        "sha256": "11ad7efa24975ee4b0c3c3a38ed18737f0658a5f75a0a96787b576a78a023361",
    },
    {
        "path": "README.md",
        "bytes": 7776,
        "blobID": "6cb95d998835257df3e35094395b696842024163",
        "lfsSHA256": None,
        "sha256": "7384fad93ce2d98f47d5c3170597f3b31d414c12c92e7fdf3121fa90f19fe29d",
    },
    {
        "path": "audiovae.pth",
        "bytes": 376951122,
        "blobID": "036ef0b5ced85736b842e31d35bd39606845d830",
        "lfsSHA256": "94b5d51e107e0507d4acc976cfdadb64edd6fd06d1f751dadbf2fd1594274bf1",
        "sha256": "94b5d51e107e0507d4acc976cfdadb64edd6fd06d1f751dadbf2fd1594274bf1",
    },
    {
        "path": "config.json",
        "bytes": 4336,
        "blobID": "792f1c223ed607f9e508c0a0deb15dd9532483be",
        "lfsSHA256": None,
        "sha256": "405f0dcd92f7feba6011ed4eac5c8d4f74cba9712f07fd5cfa3063bbdd95402c",
    },
    {
        "path": "model.safetensors",
        "bytes": 4580080592,
        "blobID": "d53929032ba7405f13a6236df11cd12da17d995a",
        "lfsSHA256": "f7f964cfa9da23653baec6e6f7750719977ad944ed9f95fe52fe3a620506891d",
        "sha256": "f7f964cfa9da23653baec6e6f7750719977ad944ed9f95fe52fe3a620506891d",
    },
    {
        "path": "special_tokens_map.json",
        "bytes": 1632,
        "blobID": "8619dda6f3eb6d60d0a1bb274820054e46f41699",
        "lfsSHA256": None,
        "sha256": "068594063e37662c02b21acf42ebb334ef6a74fb810e68a2368f88f08351de76",
    },
    {
        "path": "tokenization_voxcpm2.py",
        "bytes": 2895,
        "blobID": "e7d768677298d058fa6ef8b160e3ca4430997fad",
        "lfsSHA256": None,
        "sha256": "84489ea32b6ee0cae22ed5480cacb6df85c46624c3119be9a2021c3649a12729",
    },
    {
        "path": "tokenizer.json",
        "bytes": 3676772,
        "blobID": "41a5c2a8dba4058dd1ad73fb898abf5e4f64f0f9",
        "lfsSHA256": None,
        "sha256": "f8984687e4a92a3503d521396d454b7d68e9fdaab2a0288eb3536c7c1aa4bc20",
    },
    {
        "path": "tokenizer_config.json",
        "bytes": 5059,
        "blobID": "fecf4cdae73b57053cac2ad34c67febbe4e4f08b",
        "lfsSHA256": None,
        "sha256": "e78a3ebb48a0b9437efd1823b6b726c823da89e49dd8bcc90c02419d9baa772b",
    },
)


AUXILIARY_FILES: tuple[dict[str, Any], ...] = (
    {
        "relativePath": (
            "source/VoxCPM-19b6bf7590025418821a86dcb817504e0ad7e5df.tar.gz"
        ),
        "url": (
            "https://codeload.github.com/OpenBMB/VoxCPM/tar.gz/"
            f"{SOURCE_REVISION}"
        ),
        "bytes": 3032436,
        "sha256": "e0151722c469fec513f43d760f927de2a548bd0a69012c50d9d50130c4eeae64",
        "kind": "sourceArchive",
    },
    {
        "relativePath": (
            "runtime/cpython-3.11.15+20260610-aarch64-apple-darwin-"
            "install_only_stripped.tar.gz"
        ),
        "url": (
            "https://github.com/astral-sh/python-build-standalone/releases/"
            "download/20260610/cpython-3.11.15%2B20260610-aarch64-apple-"
            "darwin-install_only_stripped.tar.gz"
        ),
        "bytes": 27114282,
        "sha256": "8c56f1f59142e0f9f8861ad897bdfd97fd84403afa7b3d8b0f33b208ec471355",
        "kind": "cpythonArchive",
    },
)


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


def _request(url: str) -> urllib.request.Request:
    return urllib.request.Request(
        url,
        headers={
            "Accept": "application/json, application/octet-stream, */*",
            "User-Agent": "The-Long-West-V11-VoxCPM2-exact-snapshot/1",
        },
    )


def _fetch_json(url: str) -> Any:
    try:
        with urllib.request.urlopen(_request(url), timeout=120) as response:
            return json.load(response)
    except (OSError, json.JSONDecodeError) as error:
        raise SnapshotError(f"cannot retrieve pinned metadata: {url}") from error


def _metadata_record(item: dict[str, Any]) -> dict[str, Any]:
    lfs = item.get("lfs") or {}
    return {
        "path": item.get("rfilename"),
        "bytes": item.get("size"),
        "blobID": item.get("blobId"),
        "lfsSHA256": lfs.get("sha256"),
    }


def _verify_remote_model_metadata() -> dict[str, Any]:
    payload = _fetch_json(MODEL_API_URL)
    if (
        payload.get("id") != MODEL_ID
        or payload.get("sha") != MODEL_REVISION
        or payload.get("gated") is not False
        or (payload.get("cardData") or {}).get("license") != "apache-2.0"
    ):
        raise SnapshotError("VoxCPM2 model identity, revision, gate or licence drifted")
    observed = sorted(
        (_metadata_record(item) for item in payload.get("siblings", [])),
        key=lambda item: item["path"],
    )
    expected = sorted(
        (
            {
                "path": item["path"],
                "bytes": item["bytes"],
                "blobID": item["blobID"],
                "lfsSHA256": item["lfsSHA256"],
            }
            for item in MODEL_FILES
        ),
        key=lambda item: item["path"],
    )
    if observed != expected:
        raise SnapshotError("VoxCPM2 repository inventory or blob metadata drifted")
    return {
        "apiURL": MODEL_API_URL,
        "modelID": MODEL_ID,
        "revision": MODEL_REVISION,
        "licence": "Apache-2.0",
        "gated": False,
        "fileCount": len(expected),
        "totalBytes": sum(item["bytes"] for item in expected),
        "allRepositoryFilesSelected": True,
    }


def _download_once(url: str, destination: Path, expected: dict[str, Any]) -> None:
    if destination.exists() or destination.with_suffix(destination.suffix + ".partial").exists():
        raise SnapshotError(f"download target is not new: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    digest = hashlib.sha256()
    size = 0
    try:
        with urllib.request.urlopen(_request(url), timeout=120) as response:
            with partial.open("xb") as handle:
                while block := response.read(8 * 1024 * 1024):
                    handle.write(block)
                    digest.update(block)
                    size += len(block)
    except OSError as error:
        raise SnapshotError(f"single download attempt failed: {url}") from error
    if size != expected["bytes"] or digest.hexdigest() != expected["sha256"]:
        raise SnapshotError(f"downloaded bytes failed exact verification: {url}")
    partial.replace(destination)


def _model_url(path: str) -> str:
    return (
        f"https://huggingface.co/{MODEL_ID}/resolve/{MODEL_REVISION}/{path}"
        "?download=true"
    )


def _verify_frozen_conditioning_inputs() -> dict[str, Any]:
    gate = json.loads(candidate_gate.GATE_PATH.read_text(encoding="utf-8"))
    transcript = gate["frozenInputs"]["referenceTranscript"]
    transcript_path = REPOSITORY_ROOT / transcript["path"]
    if (
        not transcript_path.is_file()
        or transcript_path.stat().st_size != transcript["bytes"]
        or _sha256(transcript_path) != transcript["sha256"]
    ):
        raise SnapshotError("frozen VoxCPM2 reference transcript drifted")
    references = []
    for item in gate["frozenInputs"]["references"]:
        path = REPOSITORY_ROOT / item["path"]
        if (
            not path.is_file()
            or path.stat().st_size != item["bytes"]
            or _sha256(path) != item["sha256"]
        ):
            raise SnapshotError(f"frozen VoxCPM2 reference drifted: {item['candidateID']}")
        references.append({"candidateID": item["candidateID"], **_binding(path)})
    if len(references) != 2:
        raise SnapshotError("VoxCPM2 requires exactly both frozen references")
    return {"transcript": _binding(transcript_path), "references": references}


def _expected_inventory() -> list[dict[str, Any]]:
    records = [
        {
            "relativePath": f"model/{item['path']}",
            "bytes": item["bytes"],
            "sha256": item["sha256"],
            "kind": "modelRepositoryFile",
        }
        for item in MODEL_FILES
    ]
    records.extend(dict(item) for item in AUXILIARY_FILES)
    return sorted(records, key=lambda item: item["relativePath"])


def _verify_local_inventory(root: Path) -> list[dict[str, Any]]:
    expected = _expected_inventory()
    expected_paths = {item["relativePath"] for item in expected}
    actual_paths = {
        item.relative_to(root).as_posix()
        for item in root.rglob("*")
        if item.is_file() and item.name != RECEIPT_NAME
    }
    if actual_paths != expected_paths:
        raise SnapshotError("VoxCPM2 local snapshot contains missing or unbound files")
    verified = []
    for item in expected:
        path = root / item["relativePath"]
        if (
            path.stat().st_size != item["bytes"]
            or _sha256(path) != item["sha256"]
        ):
            raise SnapshotError(f"VoxCPM2 local snapshot byte drift: {path}")
        verified.append(
            {
                "relativePath": item["relativePath"],
                "bytes": item["bytes"],
                "sha256": item["sha256"],
                "kind": item["kind"],
            }
        )
    return verified


def download(root: Path) -> dict[str, Any]:
    candidate_gate.validate()
    conditioning = _verify_frozen_conditioning_inputs()
    metadata = _verify_remote_model_metadata()
    if root.exists() and any(root.iterdir()):
        raise SnapshotError("VoxCPM2 snapshot root must be new or empty")
    root.mkdir(parents=True, exist_ok=True)

    for item in AUXILIARY_FILES:
        _download_once(item["url"], root / item["relativePath"], item)
    for item in MODEL_FILES:
        _download_once(_model_url(item["path"]), root / "model" / item["path"], item)

    files = _verify_local_inventory(root)
    model_files = [item for item in files if item["kind"] == "modelRepositoryFile"]
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": candidate_gate.TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "script": _binding(SCRIPT_PATH),
        "candidateGate": _binding(candidate_gate.GATE_PATH),
        "snapshotRoot": str(root.absolute()),
        "modelMetadata": metadata,
        "conditioningInputs": conditioning,
        "fileCount": len(files),
        "totalBytes": sum(item["bytes"] for item in files),
        "modelFileCount": len(model_files),
        "modelTotalBytes": sum(item["bytes"] for item in model_files),
        "files": files,
        "allModelRepositoryBytesVerified": True,
        "allSourceAndInterpreterBytesVerified": True,
        "modelLoaded": False,
        "runtimeInstalled": False,
        "generatedAudio": False,
        "comparisonSynthesisPermitted": False,
        "fullGenerationPermitted": False,
        "incrementalCostNOK": 0,
        "billingCredentialUsed": False,
    }
    receipt_path = root / RECEIPT_NAME
    receipt_path.write_text(
        json.dumps(receipt, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return receipt


def validate(root: Path) -> dict[str, Any]:
    candidate_gate.validate()
    conditioning = _verify_frozen_conditioning_inputs()
    receipt_path = root / RECEIPT_NAME
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SnapshotError("VoxCPM2 exact snapshot receipt is unavailable") from error
    files = _verify_local_inventory(root)
    model_files = [item for item in files if item["kind"] == "modelRepositoryFile"]
    if (
        receipt.get("status") != STATUS
        or receipt.get("trustDomain") != candidate_gate.TRUST_DOMAIN
        or receipt.get("conditioningInputs") != conditioning
        or receipt.get("fileCount") != len(files)
        or receipt.get("totalBytes") != sum(item["bytes"] for item in files)
        or receipt.get("modelFileCount") != len(model_files)
        or receipt.get("modelTotalBytes") != sum(item["bytes"] for item in model_files)
        or receipt.get("files") != files
        or receipt.get("allModelRepositoryBytesVerified") is not True
        or receipt.get("allSourceAndInterpreterBytesVerified") is not True
        or receipt.get("modelLoaded") is not False
        or receipt.get("runtimeInstalled") is not False
        or receipt.get("generatedAudio") is not False
        or receipt.get("comparisonSynthesisPermitted") is not False
        or receipt.get("fullGenerationPermitted") is not False
        or receipt.get("incrementalCostNOK") != 0
        or receipt.get("billingCredentialUsed") is not False
    ):
        raise SnapshotError("VoxCPM2 exact snapshot receipt drifted")
    script = receipt.get("script") or {}
    if script != _binding(SCRIPT_PATH):
        raise SnapshotError("VoxCPM2 exact snapshot method source drifted")
    return {
        "status": receipt["status"],
        "fileCount": receipt["fileCount"],
        "totalBytes": receipt["totalBytes"],
        "modelFileCount": receipt["modelFileCount"],
        "modelTotalBytes": receipt["modelTotalBytes"],
        "allCurrentBytesMatch": True,
        "modelLoaded": False,
        "generatedAudio": False,
        "incrementalCostNOK": 0,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("download", "validate"):
        item = subparsers.add_parser(command)
        item.add_argument("--root", type=Path, default=SNAPSHOT_ROOT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = (
            download(args.root.absolute())
            if args.command == "download"
            else validate(args.root.absolute())
        )
    except (SnapshotError, candidate_gate.GateError) as error:
        print(f"V11 VoxCPM2 exact snapshot failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
