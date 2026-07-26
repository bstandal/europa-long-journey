#!/usr/bin/env python3
"""Offline 25/15/10 decoder-grid experiment for the frozen V8 method.

This experiment changes only the independent Whisper window geometry.  It
preserves the failed 30/15/15 proof, every lexical and timing threshold, the
source audio, and the bounded V8 timestamp-reconciliation method.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from typing import Any

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v7_pipeline as v7
import v8_pipeline as v8


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V8_25_15_10_DECODER_GRID_EXPERIMENT_NON_SHIPPING"
CANDIDATE_ID = "voice-candidate-06"
PRIOR_PROOF = (
    "native/audio/narration/work/provisional-audit-v8/"
    "c06-decoder-proof-r3-2026-07-25/decoder-proof.v8.receipt.json"
)


def _experiment_config(config: dict[str, Any]) -> dict[str, Any]:
    changed = v8._v8_audit_config(config)
    windowed = changed["windowedASR"]
    windowed["windowSeconds"] = 25
    windowed["overlapSeconds"] = 15
    windowed["strideSeconds"] = 10
    windowed["grid"] = (
        "Diagnostic V8 grid only: exact 25-second PCM windows, 15-second "
        "overlap and 10-second stride, starting at sample zero and covering "
        "the final decoded sample"
    )
    return changed


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("V8 decoder-grid experiment requires --offline")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"

    config = v8.load_config()
    output = v8.prepare_output(args.output, config)
    dependencies = v8.validate_dependencies(config)
    stress = v7._validate_shallow_stress_receipt(v7.load_config())
    text, stress_record, cues, _, _ = v6.stress_and_utterance_material(
        v6.load_config()
    )
    candidate = next(
        item for item in stress["records"]
        if item["candidateID"] == CANDIDATE_ID
    )
    master_path = Path(candidate["master"]["file"]["path"])
    prior_path = v8.repository_path(PRIOR_PROOF, directory=False)
    prior = production.load_json(prior_path)

    result = v8.windowed_asr_audit_v8(
        master_path=master_path,
        candidate_directory=output,
        reference_words=v5.normalize_words(text),
        cues=cues,
        cue_sample_ranges=candidate["cueSampleRanges"],
        config=_experiment_config(config),
    )
    result["method"] = (
        "Deterministic 25-second diagnostic windows with 15-second overlap "
        "and 10-second stride, exact PCM coverage, independent pinned "
        "Whisper decodes, unchanged gates and the frozen bounded V8 "
        "seam-prefix timestamp reconciliation"
    )
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "experimentScript": v8.file_binding(SCRIPT_PATH),
        "frozenV8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "frozenV8Config": v8.file_binding(Path(config["_path"])),
        "dependencyBindings": dependencies,
        "stressText": stress_record,
        "candidateID": CANDIDATE_ID,
        "master": v8.file_binding(master_path),
        "priorFailed30_15_15Proof": {
            "receipt": v8.file_binding(prior_path),
            "passesDecoderProof": prior["passesDecoderProof"],
            "failedAggregateGates": [
                key
                for key, passes in prior["audit"]["aggregateGates"].items()
                if not passes
            ],
            "cue06ExactReferenceCoverage": prior["audit"]["cueAlignment"]
            ["cueRecords"][-1]["exactReferenceCoverage"],
        },
        "changedVariableOnly": {
            "windowSeconds": 25,
            "overlapSeconds": 15,
            "strideSeconds": 10,
        },
        "unchanged": {
            "masterBytes": True,
            "whisperRuntimeModelAndDecodeSettings": True,
            "windowGateThresholds": True,
            "boundaryGateThresholds": True,
            "aggregateGateThresholds": True,
            "timestampReconciliationMethodAndBounds": True,
            "answerPromptUsed": False,
            "externalTranscriptUsed": False,
        },
        "audit": result,
        "passesDecoderGridExperiment": (
            result["allWindowGatesPass"]
            and result["stitching"]["allBoundariesPass"]
            and result["aggregatePasses"]
        ),
        "audioChanged": False,
        "productionMethodChanged": False,
        "parentAudioMayBecomeV8Master": False,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }
    receipt_path = output / "decoder-grid-experiment.v8.receipt.json"
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Offline 25/15/10 V8 decoder-grid experiment"
    )
    result.add_argument("--output", required=True, type=Path)
    result.add_argument("--offline", action="store_true")
    return result


def main() -> int:
    try:
        result = run(parser().parse_args())
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (
        v8.V8Error,
        v7.V7Error,
        v6.V6Error,
        v5.V5Error,
        production.PipelineError,
    ) as error:
        print(f"V8 decoder-grid experiment error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
