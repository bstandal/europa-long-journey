#!/usr/bin/env python3
"""Offline 30-second-window decoder spike for the V7 candidate-06 collapse.

This diagnostic does not change a master, a production gate, a finalist, or the
frozen V7 audit.  It changes only the independent Whisper window geometry so we
can distinguish long-window decoder repetition from repetition in the audio.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import sys
from typing import Any

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v7_pipeline as v7


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V7_30S_WINDOW_DECODER_SPIKE_NON_SHIPPING"
CANDIDATE_ID = "voice-candidate-06"


def _spike_config(config: dict[str, Any]) -> dict[str, Any]:
    changed = copy.deepcopy(config)
    changed["windowedASR"]["windowSeconds"] = 30
    changed["windowedASR"]["overlapSeconds"] = 10
    changed["windowedASR"]["strideSeconds"] = 20
    changed["windowedASR"]["grid"] = (
        "Diagnostic grid only: exact 30-second PCM windows, 10-second overlap, "
        "20-second stride, starting at decoded sample zero and ending at the "
        "final decoded sample"
    )
    return changed


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v7.V7Error("short-window spike requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    config = v7.load_config()
    dependencies = v7.validate_dependencies(config)
    output = v7.prepare_output(args.output, config)
    stress_receipt = v7._validate_shallow_stress_receipt(config)
    text, stress_record, cues, _, _ = v6.stress_and_utterance_material(
        v6.load_config()
    )
    candidate = next(
        item for item in stress_receipt["records"]
        if item["candidateID"] == CANDIDATE_ID
    )
    master_path = Path(candidate["master"]["file"]["path"])
    prior_path = v7.repository_path(
        "native/audio/narration/work/provisional-audit-v7/"
        "audit-v6-r4-windowed-r3-2026-07-25/voice-candidate-06/"
        "candidate-window-audit.v7.receipt.json",
        directory=False,
    )
    prior = production.load_json(prior_path)
    changed = _spike_config(config)
    result = v7.windowed_asr_audit(
        master_path=master_path,
        candidate_directory=output,
        reference_words=v5.normalize_words(text),
        cues=cues,
        cue_sample_ranges=candidate["cueSampleRanges"],
        config=changed,
    )
    prior_windowed = prior["windowedASR"]
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v7.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "spikeScript": v7.file_binding(SCRIPT_PATH),
        "frozenV7Pipeline": v7.file_binding(v7.SCRIPT_PATH),
        "frozenV7Config": v7.file_binding(v7.CONFIG_PATH),
        "dependencyBindings": dependencies,
        "stressReceipt": v7.file_binding(Path(stress_receipt["_path"])),
        "stressText": stress_record,
        "candidateID": CANDIDATE_ID,
        "master": v7.file_binding(master_path),
        "reason": (
            "The frozen 60-second V7 audit decoded candidate-06 window 001 at "
            "379 words per minute with one six-word phrase repeated 17 times, "
            "while every source utterance passed its independent gate."
        ),
        "changedVariableOnly": {
            "windowSeconds": 30,
            "overlapSeconds": 10,
            "strideSeconds": 20,
        },
        "unchanged": {
            "masterBytes": True,
            "whisperRuntimeAndModel": True,
            "answerPromptUsed": False,
            "externalTranscriptUsed": False,
            "windowGateThresholds": True,
            "boundaryGateThresholds": True,
            "aggregateGateThresholds": True,
        },
        "priorFrozen60SecondAudit": {
            "receipt": v7.file_binding(prior_path),
            "windowCount": prior_windowed["extraction"]["windowCount"],
            "failedWindowIndexes": [
                item["index"]
                for item in prior_windowed["windowRecords"]
                if not item["passes"]
            ],
            "hypothesisWordCount": prior_windowed["hypothesisWordCount"],
            "wordErrorRate": prior_windowed["wholeAlignment"][
                "wordAlignmentErrorRate"
            ],
            "excessRepeatedSixGramFraction": prior_windowed["repetition"][
                "excessOccurrenceFraction"
            ],
            "aggregatePasses": prior_windowed["aggregatePasses"],
        },
        "shortWindowAudit": result,
        "passesDecoderSpike": (
            result["allWindowGatesPass"]
            and result["stitching"]["allBoundariesPass"]
            and result["aggregatePasses"]
        ),
        "audioChanged": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "productionGateChanged": False,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "shippingApproval": False,
    }
    receipt_path = output / "short-window-spike.v7.receipt.json"
    v7.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v7.file_binding(receipt_path)}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Offline 30-second-window V7 decoder spike"
    )
    result.add_argument("--output", required=True, type=Path)
    result.add_argument("--offline", action="store_true")
    return result


def main() -> int:
    try:
        result = run(parser().parse_args())
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (v7.V7Error, v6.V6Error, v5.V5Error, production.PipelineError) as error:
        print(f"V7 short-window spike error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
