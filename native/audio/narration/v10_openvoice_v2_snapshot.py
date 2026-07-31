#!/usr/bin/env python3
"""Download and freeze the exact V10 OpenVoice candidate whitelist.

The primary-source gate must already pass.  This downloader accepts no model
aliases and no unlisted files.  Every byte is streamed to a private staging
file, verified by length and SHA-256, then atomically committed.  It neither
installs the runtime nor imports or executes downloaded code or weights.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from typing import Any
import urllib.parse
import urllib.request

import pipeline as production
import v8_pipeline as v8
import v10_openvoice_v2_preflight as preflight


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V10_OPENVOICE_V2_EXACT_SNAPSHOT_VERIFIED"
TRUST_DOMAIN = v8.TRUST_DOMAIN
RECEIPT_NAME = "openvoice-v2-exact-snapshot.v10.receipt.json"
PREFLIGHT_RECEIPT = (
    "native/audio/narration/work/provisional-audit-v8/"
    "openvoice-v2-primary-source-gate-r1-2026-07-25/"
    "openvoice-v2-primary-source-gate.v10.receipt.json"
)


def _model_url(model_id: str, revision: str, relative: str) -> str:
    encoded = urllib.parse.quote(relative, safe="/")
    return f"https://huggingface.co/{model_id}/resolve/{revision}/{encoded}"


def download_inventory() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for label, spec in preflight.CODE_ARCHIVES.items():
        records.append(
            {
                "kind": "sourceArchive",
                "component": label,
                "relativePath": f"source/{label}.tar.gz",
                "url": spec["url"],
                "revision": spec["revision"],
                "bytes": spec["bytes"],
                "sha256": spec["sha256"],
                "licence": spec["licence"],
            }
        )
    for label, spec in preflight.MODEL_SPECS.items():
        for relative, binding in spec["files"].items():
            records.append(
                {
                    "kind": "modelFile",
                    "component": label,
                    "modelID": spec["modelID"],
                    "revision": spec["revision"],
                    "relativePath": f"models/{label}/{relative}",
                    "sourceRelativePath": relative,
                    "url": _model_url(spec["modelID"], spec["revision"], relative),
                    "bytes": binding["bytes"],
                    "sha256": binding["sha256"],
                    "licence": spec["licence"],
                }
            )
    paths = [item["relativePath"] for item in records]
    if len(paths) != len(set(paths)):
        raise v8.V8Error("V10 download inventory contains a path collision")
    expected = preflight.download_plan()["totalBoundDownloadBytes"]
    if len(records) != 16 or sum(item["bytes"] for item in records) != expected:
        raise v8.V8Error("V10 download inventory escaped the exact whitelist")
    return records


def _download_one(record: dict[str, Any], destination: Path) -> dict[str, Any]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = destination.with_name(destination.name + ".part")
    if destination.exists() or staging.exists():
        raise v8.V8Error(f"snapshot path was not clean: {destination}")
    digest = hashlib.sha256()
    written = 0
    request = urllib.request.Request(
        record["url"],
        headers={"User-Agent": "The-Long-West-narration-snapshot/1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            with staging.open("xb") as handle:
                while block := response.read(8 * 1024 * 1024):
                    handle.write(block)
                    digest.update(block)
                    written += len(block)
                handle.flush()
                os.fsync(handle.fileno())
        current_hash = digest.hexdigest()
        if written != record["bytes"] or current_hash != record["sha256"]:
            raise v8.V8Error(
                f"downloaded bytes failed exact binding: {record['relativePath']}"
            )
        os.replace(staging, destination)
    except BaseException:
        if staging.exists():
            staging.unlink()
        raise
    return {
        **record,
        "path": str(destination.absolute()),
        "downloadedBytes": written,
        "downloadedSHA256": current_hash,
        "exactBindingPassed": True,
    }


def _preflight_binding() -> dict[str, Any]:
    path = v8.repository_path(PREFLIGHT_RECEIPT, directory=False)
    receipt = production.load_json(path)
    if (
        receipt.get("status") != preflight.STATUS
        or receipt.get("candidateGate", {}).get("passesPrimarySourceGate") is not True
        or receipt.get("candidateGate", {}).get("modelDownloadPermitted") is not True
        or receipt.get("executionState", {}).get("modelFilesDownloaded") is not False
    ):
        raise v8.V8Error("V10 primary-source gate does not permit the snapshot")
    return v8.file_binding(path)


def snapshot(args: argparse.Namespace) -> dict[str, Any]:
    if args.network_download is not True:
        raise v8.V8Error("exact V10 snapshot requires --network-download")
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["DO_NOT_TRACK"] = "1"
    config = v8.load_config()
    output = v8.prepare_output(args.output, config)
    preflight_binding = _preflight_binding()
    inventory = download_inventory()

    downloaded: list[dict[str, Any]] = []
    for record in inventory:
        downloaded.append(_download_one(record, output / record["relativePath"]))

    total = sum(item["downloadedBytes"] for item in downloaded)
    expected_total = preflight.download_plan()["totalBoundDownloadBytes"]
    if total != expected_total:
        raise v8.V8Error("verified snapshot byte total drifted")
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "preflightReceipt": preflight_binding,
        "snapshotRoot": str(output.absolute()),
        "files": downloaded,
        "fileCount": len(downloaded),
        "totalBytes": total,
        "everyFileExactlyHashVerifiedBeforeLoading": True,
        "mutableRevisionAliasesUsed": False,
        "unlistedFilesDownloaded": False,
        "sourceCodeExecuted": False,
        "modelWeightsLoaded": False,
        "runtimeInstalled": False,
        "synthesisExecuted": False,
        "audioFilesCreated": 0,
        "incrementalCostNOK": 0,
        "paidAPIUsed": False,
        "nextGate": (
            "Extract only the bound code archives, freeze and licence-check "
            "the exact CPU runtime dependencies, then import the adapter offline."
        ),
    }
    receipt_path = output / RECEIPT_NAME
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--network-download", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        receipt = snapshot(parse_args(sys.argv[1:] if argv is None else argv))
    except (OSError, v8.V8Error, json.JSONDecodeError) as error:
        print(f"v10 OpenVoice V2 snapshot failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
