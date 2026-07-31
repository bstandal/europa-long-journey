#!/usr/bin/env python3
"""Run the unchanged V8 gates over the frozen V10 OpenVoice 14-by-2 set."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys
from typing import Any

import pipeline as production
import v6_pipeline as v6
import v8_chatterbox_comparison as frozen_audit
import v8_pipeline as v8
import v10_openvoice_v2_adapter as adapter
import v10_openvoice_v2_generate_comparison as generation


SCRIPT_PATH = Path(__file__).absolute()
PASS_STATUS = "CODEX_V10_OPENVOICE_UNCHANGED_14_BY_2_GATE_PASSED"
BLOCKED_STATUS = "CODEX_V10_OPENVOICE_UNCHANGED_14_BY_2_GATE_BLOCKED"
RECEIPT_NAME = "openvoice-v2-comparison-audit.v10.receipt.json"
GENERATION_ROOT = (
    v8.REPOSITORY_ROOT
    / "native/audio/narration/work/provisional-audit-v8/"
    "openvoice-v2-comparison-generation-r1-2026-07-25"
)
GENERATION_RECEIPT = GENERATION_ROOT / generation.RECEIPT_NAME


def _validate_file(binding: dict[str, Any]) -> Path:
    path = Path(binding["path"])
    if not path.is_file() or v8.file_binding(path) != binding:
        raise v8.V8Error(f"V10 generated comparison file drifted: {path}")
    return path


def _generation_document() -> dict[str, Any]:
    document = production.load_json(GENERATION_RECEIPT)
    method = adapter.load_config()
    if (
        document.get("status") != generation.STATUS
        or document.get("script") != v8.file_binding(generation.SCRIPT_PATH)
        or document.get("prerequisites", {}).get("adapter")
        != v8.file_binding(adapter.SCRIPT_PATH)
        or document.get("prerequisites", {}).get("methodConfiguration")
        != v8.file_binding(adapter.CONFIG_PATH)
        or document.get("method") != method
        or document.get("synthesisCount") != 28
        or document.get("audioFileCount") != 84
        or document.get("rawConverterOutputsRetainedUnmodified") is not True
        or document.get("onlyAuthoredBoundaryPausesAddedToAuditDerivative")
        is not True
        or document.get("postConversionActivityCropApplied") is not False
        or document.get("postConversionEdgeFadeApplied") is not False
        or document.get("postConversionLoudnessNormalizationApplied") is not False
        or document.get("postConversionInternalSilenceRemovalApplied") is not False
        or document.get("postConversionSpeechTimeStretchApplied") is not False
        or document.get("postConversionDurationPaddingApplied") is not False
        or document.get("oneAttemptPerUtterance") is not True
        or document.get("adaptiveParameterChoiceUsed") is not False
        or document.get("representativeGateRun") is not False
        or document.get("fullGenerationPermitted") is not False
        or [item.get("candidateID") for item in document.get("candidates", [])]
        != ["voice-candidate-05", "voice-candidate-06"]
        or any(len(item.get("utteranceRecords", [])) != 14 for item in document["candidates"])
    ):
        raise v8.V8Error("V10 generation receipt no longer opens the frozen audit")
    for candidate in document["candidates"]:
        for record in candidate["utteranceRecords"]:
            _validate_file(record["baseAudio"])
            _validate_file(record["rawConverterAudio"])
            _validate_file(record["auditAudio"])
            if (
                record.get("rawConverterWaveformModifiedBeforeWrite") is not False
                or record.get("oneDeterministicAttempt") is not True
                or record.get("generationParameters") != method["generation"]
                or record.get("auditProcessing", {}).get("activityCropApplied")
                is not False
                or record.get("auditProcessing", {}).get("edgeFadeApplied")
                is not False
                or record.get("auditProcessing", {}).get(
                    "onlyAuthoredPauseAppended"
                )
                is not True
            ):
                raise v8.V8Error("V10 utterance generation contract drifted")
    return document


def _audit_material(
    *, output: Path, document: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    selected, representative = frozen_audit._selected_material(v8.load_config())
    if (
        len(selected) != 14
        or representative["exactTextManifestSHA256"]
        != adapter.load_config()["comparison"]["exactTextManifestSHA256"]
    ):
        raise v8.V8Error("V10 unchanged representative inventory drifted")
    generated: list[dict[str, Any]] = []
    for candidate in document["candidates"]:
        candidate_root = output / candidate["candidateID"]
        candidate_root.mkdir()
        records = []
        for utterance, source in zip(selected, candidate["utteranceRecords"]):
            public = source["utterance"]
            if (
                public["utteranceID"] != utterance["utteranceID"]
                or source["exactTextInput"] != utterance["text"]
                or public["exactTextSHA256"] != utterance["textSHA256"]
                or public["separatorAfter"] != utterance["separatorAfter"]
            ):
                raise v8.V8Error("V10 audit text order drifted")
            source_path = _validate_file(source["auditAudio"])
            audit_path = candidate_root / source_path.name
            shutil.copyfile(source_path, audit_path)
            if v8.file_binding(audit_path)["sha256"] != source["auditAudio"]["sha256"]:
                raise v8.V8Error("V10 audit derivative copy changed bytes")
            input_phone_count = source["textPreparation"]["modelInputPhoneCount"]
            maximum = source["textPreparation"]["maximumInputPhoneCount"]
            if maximum != 384 or input_phone_count >= maximum:
                raise v8.V8Error("V10 inherited input ceiling failed before ASR")
            records.append(
                {
                    "utterance": {
                        key: value for key, value in utterance.items() if key != "text"
                    },
                    "exactTextInput": source["exactTextInput"],
                    "exactTextSHA256": public["exactTextSHA256"],
                    "generationSeed": source["generationSeed"],
                    "generationResult": {
                        "engine": "MeloTTS model.infer plus OpenVoice convert",
                        "oneDeterministicAttempt": True,
                        "inputPhoneCount": input_phone_count,
                        "nonAutoregressiveOutputTokenCap": False,
                    },
                    "speechTokens": {
                        "derivation": (
                            "Exact fail-closed Melo model input phone count; the "
                            "non-autoregressive model exposes no output token cap."
                        ),
                        "derivedSpeechTokenCount": input_phone_count,
                        "maximumInheritedInputCount": maximum,
                    },
                    "rawConverterAudio": source["rawConverterAudio"],
                    "processedAudio": v8.file_binding(audit_path),
                    "processing": source["auditProcessing"],
                }
            )
        generated.append(
            {
                "candidateID": candidate["candidateID"],
                "utteranceRecords": records,
            }
        )
    return selected, generated


def audit(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("V10 comparison audit requires --offline")
    output = v8.prepare_output(args.output, v8.load_config())
    document = _generation_document()
    selected, generated = _audit_material(output=output, document=document)
    v6_config = v6.load_config()
    v8_config = v8.load_config()
    audited, asr_run = frozen_audit._audit_comparison(
        root=output,
        selected=selected,
        generated=generated,
        v6_config=v6_config,
        v8_config=v8_config,
    )
    if [item["candidateID"] for item in audited] != [
        "voice-candidate-05",
        "voice-candidate-06",
    ]:
        raise v8.V8Error("V10 audit returned the wrong candidate inventory")
    both_pass = len(audited) == 2 and all(item["passes"] for item in audited)
    failed = {
        item["candidateID"]: [
            gate for gate, passed in item["gates"].items() if not passed
        ]
        for item in audited
        if not item["passes"]
    }
    receipt = {
        "schemaVersion": 1,
        "status": PASS_STATUS if both_pass else BLOCKED_STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "generationReceipt": v8.file_binding(GENERATION_RECEIPT),
        "generationScript": v8.file_binding(generation.SCRIPT_PATH),
        "adapter": v8.file_binding(adapter.SCRIPT_PATH),
        "methodConfiguration": v8.file_binding(adapter.CONFIG_PATH),
        "v8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "v8Configuration": v8.file_binding(v8.CONFIG_PATH),
        "v6Pipeline": v8.file_binding(v6.SCRIPT_PATH),
        "v6Configuration": v8.file_binding(v6.CONFIG_PATH),
        "representativeSet": {
            "utteranceCountPerReference": 14,
            "referenceCount": 2,
            "requiredSynthesisCount": 28,
            "exactTextManifestSHA256": adapter.load_config()["comparison"][
                "exactTextManifestSHA256"
            ],
        },
        "unchangedThresholds": v8_config["pauseDensityLab"],
        "sameThresholdsAppliedToBothReferences": True,
        "auditImplementation": {
            "function": "v8_chatterbox_comparison._audit_comparison",
            "functionSource": v8.file_binding(frozen_audit.SCRIPT_PATH),
            "thresholdOrGateModificationApplied": False,
            "identityExtractorAndWhisperPathInheritedUnchanged": True,
        },
        "asrRun": asr_run,
        "candidateRecords": audited,
        "failedGatesByCandidate": failed,
        "bothReferencesPassEveryGate": both_pass,
        "passesFrozenRepresentativeGate": both_pass,
        "technicalBlock": None
        if both_pass
        else (
            "At least one frozen reference failed one or more unchanged V8 "
            "identity, utterance, WER, critical-word, silence or duration gates."
        ),
        "adaptiveRetryUsed": False,
        "parameterChangeAfterListeningUsed": False,
        "fullGenerationPermitted": both_pass,
        "fullGenerationStarted": False,
        "completeMasterCount": 0,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "artisticApproval": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "nextGate": (
            "Both references passed; a separate editor decision is still required "
            "before any full generation."
            if both_pass
            else "Freeze this failure; do not render the full 203-by-two set."
        ),
    }
    receipt_path = output / RECEIPT_NAME
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--offline", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        receipt = audit(parse_args(sys.argv[1:] if argv is None else argv))
    except (OSError, v8.V8Error, json.JSONDecodeError) as error:
        print(f"v10 OpenVoice unchanged comparison audit failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
