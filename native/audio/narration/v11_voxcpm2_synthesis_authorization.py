#!/usr/bin/env python3
"""Write the durable authority for the one-take VoxCPM2 V11 14-by-2 run."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
from typing import Any

import v6_pipeline as v6
import v8_chatterbox_comparison as frozen_audit
import v8_pipeline as v8
import v11_narration_candidate_preflight as candidate_gate
import v11_voxcpm2_exact_snapshot as snapshot
import v11_voxcpm2_method as method
import v11_voxcpm2_model_load_gate as model_gate
import v11_voxcpm2_runtime_audit as runtime


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
OUTPUT_ROOT = (
    NARRATION_ROOT
    / "work/provisional-audit-v11/voxcpm2-representative-r5-2026-07-25"
)
RECEIPT_PATH = OUTPUT_ROOT / "voxcpm2-synthesis-authorisation.v11.receipt.json"
SYNTHESIS_SCRIPT = NARRATION_ROOT / "v11_voxcpm2_generate_representative.py"
AUDIT_SCRIPT = NARRATION_ROOT / "v11_voxcpm2_audit_representative.py"
STATUS = "CODEX_V11_VOXCPM2_REPRESENTATIVE_SYNTHESIS_AUTHORISED"
EXPECTED_R5_RECEIPT_BYTES = 45_415
EXPECTED_R5_RECEIPT_SHA256 = (
    "197eeb401e5b4ee798f36908b3ec2a673b189043faab2414858c29326397fcba"
)
ANONYMOUS_VOICES = {
    "voice-candidate-05": "voice-a",
    "voice-candidate-06": "voice-b",
}


class AuthorisationError(RuntimeError):
    """Raised when any prerequisite or one-take job binding drifts."""


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


def _canonical_sha(value: Any) -> str:
    payload = json.dumps(
        value, sort_keys=True, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _r5_authority() -> tuple[dict[str, Any], dict[str, Any]]:
    binding = _binding(model_gate.RECEIPT_PATH)
    if (
        binding["bytes"] != EXPECTED_R5_RECEIPT_BYTES
        or binding["sha256"] != EXPECTED_R5_RECEIPT_SHA256
    ):
        raise AuthorisationError("V11 R5 model-load authority bytes drifted")
    document = json.loads(model_gate.RECEIPT_PATH.read_text(encoding="utf-8"))
    load = document.get("modelLoad", {})
    if (
        document.get("status") != model_gate.STATUS
        or document.get("modelLoadReplayID") != "R5"
        or document.get("runtimeInstanceID") != runtime.RUNTIME_INSTANCE_ID
        or document.get("comparisonSynthesisPermitted") is not True
        or document.get("fullGenerationPermitted") is not False
        or document.get("generatedAudio") is not False
        or document.get("priorUnreceiptedR4LoadUsedAsPassEvidence") is not False
        or load.get("architecture") != "VoxCPM2Model"
        or load.get("runtimeDevice") != "mps"
        or load.get("floatingParameterDtypes") != ["float32"]
        or load.get("parameterCount") != 2_384_218_498
        or load.get("networkAttemptCount") != 0
        or load.get("promptEncoded") is not False
        or load.get("generationMethodCalled") is not False
        or load.get("generatedAudio") is not False
        or document.get("snapshotReceipt")
        != _binding(snapshot.SNAPSHOT_ROOT / snapshot.RECEIPT_NAME)
        or document.get("runtimeReceipt") != _binding(runtime.RECEIPT_PATH)
        or document.get("methodScript") != _binding(method.SCRIPT_PATH)
    ):
        raise AuthorisationError("V11 R5 model-load authority contract drifted")
    return document, binding


def build_authorization_document() -> dict[str, Any]:
    r5_document, r5_binding = _r5_authority()
    method_result = method.validate()
    gate = json.loads(candidate_gate.GATE_PATH.read_text(encoding="utf-8"))
    selected, representative = frozen_audit._selected_material(v8.load_config())
    if (
        method_result["callCount"] != 28
        or method_result["uniqueSeedCount"] != 28
        or representative["utteranceCount"] != 14
        or representative["exactTextManifestSHA256"]
        != "822786bfaa942aec932686929d2ece3a7122d5215db654862cad3e28d9a8cb62"
    ):
        raise AuthorisationError("V11 frozen representative method drifted")
    transcript_record = gate["frozenInputs"]["referenceTranscript"]
    transcript_path = REPOSITORY_ROOT / transcript_record["path"]
    transcript_binding = _binding(transcript_path)
    if transcript_binding != {
        "path": str(transcript_path.absolute()),
        "bytes": transcript_record["bytes"],
        "sha256": transcript_record["sha256"],
    }:
        raise AuthorisationError("V11 exact reference transcript drifted")
    transcript = transcript_path.read_text(encoding="utf-8")
    references = gate["frozenInputs"]["references"]
    if [item["candidateID"] for item in references] != list(method.EXPECTED_FINALISTS):
        raise AuthorisationError("V11 reference order drifted")

    v6_config = v6.load_config()
    jobs = []
    for candidate_index, reference in enumerate(references):
        candidate_id = reference["candidateID"]
        reference_path = REPOSITORY_ROOT / reference["path"]
        reference_binding = _binding(reference_path)
        if (
            reference_binding["bytes"] != reference["bytes"]
            or reference_binding["sha256"] != reference["sha256"]
        ):
            raise AuthorisationError(f"V11 reference drifted: {candidate_id}")
        for utterance_index, utterance in enumerate(selected):
            seed = method.generation_seed(candidate_index, utterance_index)
            arguments = method.generation_kwargs(
                reference_path, transcript, utterance["text"]
            )
            alias = ANONYMOUS_VOICES[candidate_id]
            job_id = f"r5-{alias}-{utterance['utteranceID']}"
            job_root = OUTPUT_ROOT / "audio" / alias / utterance["utteranceID"]
            pause_ms = (
                v6_config["join"]["paragraphPauseMilliseconds"]
                if utterance["separatorAfter"] == "\n\n"
                else v6_config["join"]["intraParagraphPauseMilliseconds"]
                if utterance["separatorAfter"] == " "
                else v6_config["join"]["finalPauseMilliseconds"]
            )
            jobs.append(
                {
                    "jobIndex": len(jobs) + 1,
                    "jobID": job_id,
                    "candidateID": candidate_id,
                    "anonymousVoiceID": alias,
                    "utteranceIndex": utterance_index,
                    "utteranceID": utterance["utteranceID"],
                    "segmentID": utterance["segmentID"],
                    "exactTextInput": utterance["text"],
                    "exactTextSHA256": utterance["textSHA256"],
                    "targetTextSHA256": hashlib.sha256(
                        arguments["text"].encode("utf-8")
                    ).hexdigest(),
                    "separatorAfter": utterance["separatorAfter"],
                    "authoredBoundaryPauseMilliseconds": pause_ms,
                    "seed": seed,
                    "reference": reference_binding,
                    "generationArguments": arguments,
                    "rawAudioPath": str((job_root / "raw-48k-f32.wav").absolute()),
                    "auditAudioPath": str((job_root / "audit-24k-f32.wav").absolute()),
                    "oneModelGenerateCall": True,
                    "retryPermitted": False,
                    "alternateTakePermitted": False,
                    "cherryPickingPermitted": False,
                }
            )
    if len(jobs) != 28 or len({item["seed"] for item in jobs}) != 28:
        raise AuthorisationError("V11 synthesis job inventory is not exact 14-by-2")
    method_calls = {
        (item["candidateID"], item["utteranceID"]): item
        for item in method_result["calls"]
    }
    for job in jobs:
        call = method_calls[(job["candidateID"], job["utteranceID"])]
        if (
            call["seed"] != job["seed"]
            or call["reference"] != job["reference"]
            or call["targetTextSHA256"] != job["targetTextSHA256"]
        ):
            raise AuthorisationError("V11 synthesis job escaped frozen method call")

    bytecode = runtime.bytecode_cache_gate("representative-synthesis-authorisation")
    return {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": candidate_gate.TRUST_DOMAIN,
        "recordedAt": "2026-07-25",
        "authorisationScript": _binding(SCRIPT_PATH),
        "synthesisScript": _binding(SYNTHESIS_SCRIPT),
        "auditScript": _binding(AUDIT_SCRIPT),
        "r5ModelLoadAuthority": r5_binding,
        "r5ModelLoadStatus": r5_document["status"],
        "snapshotReceipt": r5_document["snapshotReceipt"],
        "runtimeReceipt": r5_document["runtimeReceipt"],
        "methodScript": _binding(method.SCRIPT_PATH),
        "candidateGate": _binding(candidate_gate.GATE_PATH),
        "transcript": transcript_binding,
        "references": [
            {
                "candidateID": item["candidateID"],
                "anonymousVoiceID": ANONYMOUS_VOICES[item["candidateID"]],
                "file": _binding(REPOSITORY_ROOT / item["path"]),
            }
            for item in references
        ],
        "modelInitialisation": method_result["modelInitialisation"],
        "generationSettings": method_result["generationSettings"],
        "controlInstruction": method_result["controlInstruction"],
        "representativeSet": representative,
        "frozenAudit": {
            "v8Implementation": _binding(frozen_audit.SCRIPT_PATH),
            "v8Configuration": _binding(v8.CONFIG_PATH),
            "v6Implementation": _binding(v6.SCRIPT_PATH),
            "v6Configuration": _binding(v6.CONFIG_PATH),
            "unchangedPauseDensityThresholds": v8.load_config()["pauseDensityLab"],
            "unchangedUtteranceThresholds": v6_config["utteranceGate"],
            "authoredBoundaryPauses": v6_config["join"],
            "rawSampleRate": 48_000,
            "auditSampleRate": 24_000,
            "auditDownsample": {
                "algorithm": "scipy.signal.resample_poly",
                "upFactor": 1,
                "downFactor": 2,
            },
            "auditDerivative": "v6.process_utterance_audio with normalized_word_count=None",
            "internalSilenceRemovalPermitted": False,
            "speechTimeStretchPermitted": False,
            "adaptiveDurationPaddingPermitted": False,
        },
        "bytecodeCacheGate": bytecode,
        "jobs": jobs,
        "jobCount": len(jobs),
        "jobManifestSHA256": _canonical_sha(jobs),
        "oneTakePerJob": True,
        "runtimeNetworkPermitted": False,
        "synthesisPermitted": True,
        "anonymousReviewOnly": True,
        "nonShipping": True,
        "representativeMachineAuditRun": False,
        "full203By2GenerationPermitted": False,
        "full203By2GenerationStarted": False,
        "incrementalCostNOK": 0,
        "billingCredentialUsed": False,
    }


def authorize() -> dict[str, Any]:
    if OUTPUT_ROOT.exists():
        raise AuthorisationError("V11 synthesis output root is not new")
    document = build_authorization_document()
    OUTPUT_ROOT.mkdir(parents=True)
    payload = (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    RECEIPT_PATH.write_bytes(payload)
    if RECEIPT_PATH.read_bytes() != payload or json.loads(RECEIPT_PATH.read_bytes()) != document:
        raise AuthorisationError("V11 synthesis authorisation reread failed")
    return {
        "status": STATUS,
        "jobCount": 28,
        "jobManifestSHA256": document["jobManifestSHA256"],
        "receipt": _binding(RECEIPT_PATH),
        "generatedAudio": False,
    }


def main() -> int:
    try:
        result = authorize()
    except Exception as error:
        print(f"V11 VoxCPM2 synthesis authorisation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
