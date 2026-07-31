#!/usr/bin/env python3
"""Validate the durable V11 primary-source candidate selection offline."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any

import v11_narration_candidate_preflight as preflight


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
COST_REGISTRY = REPOSITORY_ROOT / "native/tooling/registries/cost-license.json"

EXPECTED_SOURCE_BINDINGS = {
    "native/audio/narration/v11_narration_candidate_preflight.py": (
        40117,
        "73d5e933bc51d153057271d5aa1e972d8521c7fdd865f2c8b7eed9ff97b5946b",
    ),
    "native/audio/narration/v11-narration-candidate-gate.json": (
        25971,
        "000ff1599649824a8eca2bcdeeca33f811ab619cae6ad379b2c5a1edcddfed3a",
    ),
}


class EvidenceError(RuntimeError):
    """Raised when a durable V11 evidence binding drifts."""


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
        raise EvidenceError(f"cannot load V11 evidence input: {path}") from error


def _validate_cost_registry() -> None:
    registry = _load(COST_REGISTRY)
    entries = {item.get("id"): item for item in registry.get("entries", [])}
    item = entries.get("voxcpm2-narration-preflight")
    if (
        item is None
        or item.get("category") != "model"
        or item.get("version")
        != (
            "source tag 2.0.3 commit 19b6bf7590025418821a86dcb817504e0ad7e5df; "
            "weights bffb3df5a29440629464e5e839f4d214c8714c3d"
        )
        or item.get("incrementalCostNOK") != 0
        or item.get("billingCredentialRequired") is not False
        or item.get("commercialUse") != "allowed"
        or item.get("license") != "Apache License 2.0"
        or "locally locked" not in item.get("source", "")
        or "zero completed job receipts" not in item.get("source", "")
        or "no retry or resume authority" not in item.get("source", "")
        or "training-dataset details remain undisclosed" not in item.get("source", "")
    ):
        raise EvidenceError("V11 VoxCPM2 cost, licence or provenance record drifted")

    unresolved = {
        item.get("id"): item for item in registry.get("unresolvedCapabilities", [])
    }
    narration = unresolved.get("final-narration-synthesis")
    if (
        narration is None
        or narration.get("status")
        != "BLOCKED_UNTIL_ZERO_COST_COMMERCIAL_TOOL_PASSES"
        or narration.get("incrementalCostNOKMaximum") != 0
        or narration.get("billingCredentialPermitted") is not False
    ):
        raise EvidenceError("final narration gate was opened before synthesis proof")


def validate() -> dict[str, Any]:
    for relative, (size, sha256) in EXPECTED_SOURCE_BINDINGS.items():
        path = REPOSITORY_ROOT / relative
        if (
            not path.is_file()
            or path.stat().st_size != size
            or _sha256(path) != sha256
        ):
            raise EvidenceError(f"V11 source binding drifted: {relative}")

    try:
        result = preflight.validate()
    except preflight.GateError as error:
        raise EvidenceError(str(error)) from error
    if result != {
        "status": "CODEX_V11_PRIMARY_SOURCE_CANDIDATE_GATE_PASSED",
        "candidateCount": 5,
        "eligibleCandidateCount": 1,
        "selectedCandidateID": "voxcpm2",
        "primaryDocumentCount": 16,
        "modelMetadataRecordCount": 5,
        "locallyPresentReferenceCount": 2,
        "generatedAudio": False,
        "incrementalCostNOK": 0,
    }:
        raise EvidenceError("V11 offline validation result drifted")
    _validate_cost_registry()
    return {
        **result,
        "sourceBindingCount": len(EXPECTED_SOURCE_BINDINGS),
        "exactByteRuntimePreflightPermitted": True,
        "comparisonSynthesisPermitted": False,
        "fullGenerationPermitted": False,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate",))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = validate()
    except EvidenceError as error:
        print(f"V11 evidence validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
