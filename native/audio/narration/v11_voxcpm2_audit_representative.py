#!/usr/bin/env python3
"""Apply the unchanged V8 machine gate to the VoxCPM2 V11 14-by-2 set."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
from typing import Any

import pipeline as production
import v6_pipeline as v6
import v8_chatterbox_comparison as frozen_audit
import v8_pipeline as v8
import v11_voxcpm2_generate_representative as generation
import v11_voxcpm2_synthesis_authorization as authorization


SCRIPT_PATH = Path(__file__).absolute()
AUDIT_ROOT = (
    v8.REPOSITORY_ROOT
    / "native/audio/narration/work/provisional-audit-v11/"
    "voxcpm2-representative-audit-r5-2026-07-25"
)
RECEIPT_PATH = AUDIT_ROOT / "voxcpm2-representative-audit.v11.receipt.json"
PASS_STATUS = "CODEX_V11_VOXCPM2_UNCHANGED_V8_14_BY_2_GATE_PASSED"
BLOCKED_STATUS = "CODEX_V11_VOXCPM2_UNCHANGED_V8_14_BY_2_GATE_BLOCKED"


class AuditError(RuntimeError):
    """Raised when generated evidence cannot enter the frozen V8 audit."""


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


def _validate_binding(binding: dict[str, Any]) -> Path:
    path = Path(binding["path"])
    if not path.is_file() or _binding(path) != {
        "path": str(path.absolute()),
        "bytes": binding["bytes"],
        "sha256": binding["sha256"],
    }:
        raise AuditError(f"V11 generated evidence drifted: {path}")
    return path


def _write_json_verified(path: Path, value: dict[str, Any]) -> dict[str, Any]:
    payload = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    path.write_bytes(payload)
    if path.read_bytes() != payload or json.loads(path.read_bytes()) != value:
        raise AuditError(f"V11 audit receipt reread failed: {path}")
    return _binding(path)


def _generation_document() -> dict[str, Any]:
    if not generation.RECEIPT_PATH.is_file():
        raise AuditError("V11 representative generation receipt is unavailable")
    document = json.loads(generation.RECEIPT_PATH.read_text(encoding="utf-8"))
    if (
        document.get("status") != generation.STATUS
        or document.get("script") != _binding(generation.SCRIPT_PATH)
        or document.get("synthesisAuthorisation") != _binding(authorization.RECEIPT_PATH)
        or document.get("jobCount") != 28
        or document.get("modelGenerateCallCount") != 28
        or document.get("audioFileCount") != 56
        or document.get("oneTakePerJob") is not True
        or document.get("retryUsed") is not False
        or document.get("cherryPickingUsed") is not False
        or document.get("thresholdChangeUsed") is not False
        or document.get("full203By2GenerationStarted") is not False
        or len(document.get("jobs", [])) != 28
    ):
        raise AuditError("V11 generation receipt does not open the frozen audit")
    for record in document["jobs"]:
        _validate_binding(record["rawAudio"])
        _validate_binding(record["auditAudio"])
        _validate_binding(record["jobReceipt"])
        if (
            record.get("oneModelGenerateCall") is not True
            or record.get("retryUsed") is not False
            or record.get("alternateTakeGenerated") is not False
            or record.get("speechTokens", {}).get("passes") is not True
            or record.get("auditProcessing", {}).get("internalSilenceRemovalApplied")
            is not False
            or record.get("auditProcessing", {}).get("speechTimeStretchApplied")
            is not False
            or record.get("auditProcessing", {}).get("adaptiveDurationPaddingApplied")
            is not False
        ):
            raise AuditError("V11 job escaped the frozen one-take contract")
    return document


def _audit_material(
    document: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    selected, representative = frozen_audit._selected_material(v8.load_config())
    authority = json.loads(authorization.RECEIPT_PATH.read_text(encoding="utf-8"))
    if (
        representative["exactTextManifestSHA256"]
        != authority["representativeSet"]["exactTextManifestSHA256"]
        or authority["jobManifestSHA256"] != document["jobManifestSHA256"]
    ):
        raise AuditError("V11 representative text authority drifted")
    by_key = {
        (item["job"]["candidateID"], item["job"]["utteranceID"]): item
        for item in document["jobs"]
    }
    generated = []
    for candidate_id in method_candidate_order():
        records = []
        for utterance in selected:
            source = by_key.get((candidate_id, utterance["utteranceID"]))
            if source is None:
                raise AuditError("V11 audit job inventory is incomplete")
            job = source["job"]
            if (
                job["exactTextInput"] != utterance["text"]
                or job["exactTextSHA256"] != utterance["textSHA256"]
                or job["separatorAfter"] != utterance["separatorAfter"]
            ):
                raise AuditError("V11 audit text or pause boundary drifted")
            records.append(
                {
                    "utterance": {
                        key: value for key, value in utterance.items() if key != "text"
                    },
                    "exactTextInput": utterance["text"],
                    "exactTextSHA256": utterance["textSHA256"],
                    "generationSeed": job["seed"],
                    "generationResult": {
                        "engine": "OpenBMB VoxCPM2 2.0.3",
                        "oneDeterministicAttempt": True,
                        "runtimeDevice": "mps",
                        "runtimeDtype": "float32",
                    },
                    "speechTokens": source["speechTokens"],
                    "rawAudio": source["rawAudio"],
                    "processedAudio": source["auditAudio"],
                    "processing": source["auditProcessing"],
                }
            )
        generated.append({"candidateID": candidate_id, "utteranceRecords": records})
    return selected, generated


def method_candidate_order() -> tuple[str, str]:
    return ("voice-candidate-05", "voice-candidate-06")


def _build_review_package(
    document: dict[str, Any], audited: list[dict[str, Any]]
) -> dict[str, Any]:
    review_root = AUDIT_ROOT / "anonymous-review"
    review_root.mkdir()
    aliases = {
        "voice-candidate-05": "voice-a",
        "voice-candidate-06": "voice-b",
    }
    selected, _ = frozen_audit._selected_material(v8.load_config())
    by_key = {
        (item["job"]["candidateID"], item["job"]["utteranceID"]): item
        for item in document["jobs"]
    }
    public_voices = []
    for candidate_id in method_candidate_order():
        alias = aliases[candidate_id]
        target_root = review_root / alias
        target_root.mkdir()
        files = []
        for index, utterance in enumerate(selected, start=1):
            source = by_key[(candidate_id, utterance["utteranceID"])]["rawAudio"]
            source_path = _validate_binding(source)
            target = target_root / f"{index:02d}-{utterance['utteranceID']}.wav"
            shutil.copyfile(source_path, target)
            target_binding = _binding(target)
            if target_binding["sha256"] != source["sha256"]:
                raise AuditError("V11 anonymous review copy changed audio bytes")
            files.append(
                {
                    "order": index,
                    "utteranceID": utterance["utteranceID"],
                    "text": utterance["text"],
                    "audio": target_binding,
                }
            )
        public_voices.append({"anonymousVoice": alias, "utterances": files})
    public_manifest = {
        "schemaVersion": 1,
        "status": "CODEX_V11_VOXCPM2_ANONYMOUS_REVIEW_PACKAGE_READY",
        "recordedAt": "2026-07-25",
        "voices": public_voices,
        "candidateIDsIncluded": False,
        "editorChoiceRequested": False,
        "nonShipping": True,
        "full203By2GenerationStarted": False,
    }
    manifest_path = review_root / "review-manifest.json"
    manifest_binding = _write_json_verified(manifest_path, public_manifest)
    return {
        "root": str(review_root),
        "manifest": manifest_binding,
        "audioFileCount": 28,
        "anonymousMappingBackstage": aliases,
        "editorChoiceRequested": False,
    }


def audit() -> dict[str, Any]:
    os.environ.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "DO_NOT_TRACK": "1",
            "NO_PROXY": "*",
        }
    )
    if AUDIT_ROOT.exists():
        raise AuditError("V11 representative audit root already exists")
    document = _generation_document()
    selected, generated = _audit_material(document)
    AUDIT_ROOT.mkdir(parents=True)
    audited, asr_run = frozen_audit._audit_comparison(
        root=AUDIT_ROOT,
        selected=selected,
        generated=generated,
        v6_config=v6.load_config(),
        v8_config=v8.load_config(),
    )
    both_pass = len(audited) == 2 and all(item["passes"] for item in audited)
    failed = {
        item["candidateID"]: [
            name for name, passed in item["gates"].items() if not passed
        ]
        for item in audited
        if not item["passes"]
    }
    review = _build_review_package(document, audited) if both_pass else None
    receipt = {
        "schemaVersion": 1,
        "status": PASS_STATUS if both_pass else BLOCKED_STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "script": _binding(SCRIPT_PATH),
        "generationReceipt": _binding(generation.RECEIPT_PATH),
        "synthesisAuthorisation": _binding(authorization.RECEIPT_PATH),
        "v8AuditImplementation": {
            "function": "v8_chatterbox_comparison._audit_comparison",
            "source": _binding(frozen_audit.SCRIPT_PATH),
            "thresholdOrGateModificationApplied": False,
        },
        "v8Configuration": _binding(v8.CONFIG_PATH),
        "v6Configuration": _binding(v6.CONFIG_PATH),
        "unchangedThresholds": v8.load_config()["pauseDensityLab"],
        "candidateRecords": audited,
        "asrRun": asr_run,
        "failedGatesByCandidate": failed,
        "bothReferencesPassEveryGate": both_pass,
        "passesFrozenRepresentativeGate": both_pass,
        "anonymousReviewPackage": review,
        "adaptiveRetryUsed": False,
        "parameterChangeUsed": False,
        "editorChoiceRequested": False,
        "full203By2GenerationPermitted": False,
        "full203By2GenerationStarted": False,
        "candidatePromoted": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }
    binding = _write_json_verified(RECEIPT_PATH, receipt)
    return {
        "status": receipt["status"],
        "passes": both_pass,
        "failedGatesByCandidate": failed,
        "reviewPackageBuilt": review is not None,
        "receipt": binding,
    }


def main() -> int:
    try:
        result = audit()
    except Exception as error:
        print(f"V11 VoxCPM2 representative audit failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0 if result["passes"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
