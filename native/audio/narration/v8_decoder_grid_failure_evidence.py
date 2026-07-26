#!/usr/bin/env python3
"""Bind the aborted 25/15/10 V8 decoder grid as exact negative evidence.

The production experiment correctly stopped when one seam exceeded both
frozen timestamp-reconciliation bounds.  This diagnostic reads only the
already-produced local windows and transcripts.  A deliberately relaxed copy
of the bounds is used solely to measure the required reconciliation and can
never constitute passing evidence.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import wave
from typing import Any

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v7_pipeline as v7
import v8_pipeline as v8
import v8_decoder_grid_experiment as experiment


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V8_25_15_10_DECODER_GRID_EXACT_FAILURE_EVIDENCE"


def _window_material(
    *, root: Path, master_path: Path, config: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[list[v5.TimedWord]], list[dict[str, Any]], dict[str, Any]]:
    window_root = root / "windows"
    with wave.open(str(master_path), "rb") as source:
        sample_rate = source.getframerate()
        channels = source.getnchannels()
        width = source.getsampwidth()
        sample_count = source.getnframes()
        if (sample_rate, channels, width, source.getcomptype()) != (48000, 1, 3, "NONE"):
            raise v8.V8Error("decoder-grid parent master format drifted")
        intervals = v7._window_intervals(sample_count, sample_rate, config)
        windows: list[dict[str, Any]] = []
        words_by_window: list[list[v5.TimedWord]] = []
        window_records: list[dict[str, Any]] = []
        gate = config["windowedASR"]["windowGate"]
        for interval in intervals:
            index = interval["index"]
            audio_path = window_root / f"window-{index:03d}.wav"
            transcript_path = Path(str(audio_path) + ".json")
            if not audio_path.is_file() or not transcript_path.is_file():
                raise v8.V8Error("decoder-grid failure inventory is incomplete")
            source.setpos(interval["startSampleInclusive"])
            expected_pcm = source.readframes(
                interval["endSampleExclusive"] - interval["startSampleInclusive"]
            )
            with wave.open(str(audio_path), "rb") as check:
                actual_pcm = check.readframes(check.getnframes())
            if actual_pcm != expected_pcm:
                raise v8.V8Error("decoder-grid window no longer matches master PCM")
            duration = len(actual_pcm) / (sample_rate * width)
            document = production.load_json(transcript_path)
            if not v6._transcript_document_is_pinned(document, v6.load_config()):
                raise v8.V8Error("decoder-grid transcript runtime drifted")
            words, grouping = v7.segment_timed_words(
                document, duration_ms=duration * 1000, config=config
            )
            absolute = v7._absolute_words(
                words,
                start_sample=interval["startSampleInclusive"],
                sample_rate=sample_rate,
            )
            words_per_minute = len(words) / (duration / 60)
            gates = {
                "nonemptyTranscript": bool(words),
                "minimumWordsPerMinute": words_per_minute
                >= gate["minimumWordsPerMinute"],
                "maximumWordsPerMinute": words_per_minute
                <= gate["maximumWordsPerMinute"],
                "lexicalParity": grouping["allLexicalParityChecksPass"],
                "boundedSegmentTiming": grouping["boundedByDecodedWindow"],
            }
            record = {
                **interval,
                "durationSeconds": duration,
                "audio": v8.file_binding(audio_path),
                "pcmFrameBytes": len(actual_pcm),
                "pcmFrameBytesSHA256": hashlib.sha256(actual_pcm).hexdigest(),
                "exactMasterFrameSlice": True,
                "_path": audio_path,
            }
            windows.append(record)
            words_by_window.append(absolute)
            window_records.append(
                {
                    **{key: value for key, value in record.items() if key != "_path"},
                    "transcript": v8.file_binding(transcript_path),
                    "timedWordGrouping": grouping,
                    "wordCount": len(words),
                    "wordsPerMinute": words_per_minute,
                    "gates": gates,
                    "passes": all(gates.values()),
                }
            )
    return windows, words_by_window, window_records, {
        "master": v8.file_binding(master_path),
        "sampleRate": sample_rate,
        "channels": channels,
        "sampleWidthBytes": width,
        "windowCount": len(windows),
        "decodedSampleCoverage": v7._coverage_audit(windows, sample_count),
        "allWindowsReverifiedAsExactMasterSlices": True,
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("decoder-grid failure evidence requires --offline")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    config = v8.load_config()
    root = v8.repository_path(args.existing, directory=True)
    receipt_path = root / "decoder-grid-failure.v8.receipt.json"
    if receipt_path.exists():
        raise v8.V8Error("decoder-grid failure receipt already exists")
    audit_config = experiment._experiment_config(config)
    stress = v7._validate_shallow_stress_receipt(v7.load_config())
    text, stress_record, cues, _, _ = v6.stress_and_utterance_material(
        v6.load_config()
    )
    candidate = next(
        item for item in stress["records"]
        if item["candidateID"] == experiment.CANDIDATE_ID
    )
    master_path = Path(candidate["master"]["file"]["path"])
    windows, words, window_records, extraction = _window_material(
        root=root, master_path=master_path, config=audit_config
    )

    # Attribution only: expose the whole required prefix and displacement.
    diagnostic = copy.deepcopy(audit_config)
    boundary = diagnostic["windowedASR"]["boundaryGate"]
    boundary["maximumForwardTimestampReconciliationMilliseconds"] = 100_000
    boundary["maximumReconciledPrefixWords"] = 100
    hypothesis_timed, stitching = v8.stitch_window_words_v8(
        windows=windows,
        words_by_window=words,
        sample_rate=extraction["sampleRate"],
        config=diagnostic,
    )
    original = config["finalAudit"]
    reconciliations: list[dict[str, Any]] = []
    for record in stitching["boundaryRecords"]:
        reconciliation = record.get("timestampReconciliation")
        if reconciliation is None or not reconciliation["required"]:
            continue
        maximum = max(
            item["forwardMilliseconds"]
            for item in reconciliation["adjustments"]
        )
        prefix = reconciliation["adjustedPrefixWordCount"]
        reconciliations.append(
            {
                "boundaryIndex": record["boundaryIndex"],
                "leftWindowIndex": record["leftWindowIndex"],
                "rightWindowIndex": record["rightWindowIndex"],
                "adjustedPrefixWordCount": prefix,
                "maximumForwardMilliseconds": maximum,
                "adjustments": reconciliation["adjustments"],
                "withinFrozenPrefixBound": prefix
                <= original["maximumReconciledPrefixWords"],
                "withinFrozenDisplacementBound": maximum
                <= original[
                    "maximumForwardTimestampReconciliationMilliseconds"
                ],
            }
        )
    violations = [
        item
        for item in reconciliations
        if not item["withinFrozenPrefixBound"]
        or not item["withinFrozenDisplacementBound"]
    ]
    if len(violations) != 1:
        raise v8.V8Error("decoder-grid failure attribution did not reproduce exactly")
    failure = violations[0]
    if (
        failure["boundaryIndex"] != 115
        or failure["adjustedPrefixWordCount"] != 3
        or abs(failure["maximumForwardMilliseconds"] - 1011.9047619048506)
        > 1e-6
    ):
        raise v8.V8Error("decoder-grid exact seam failure drifted")

    hypothesis = [item.text for item in hypothesis_timed]
    reference = v5.normalize_words(text)
    steps, alignment = v5.monotone_global_alignment(reference, hypothesis)
    repetition = v5.reference_aware_repetition(
        reference, hypothesis, v6.load_config()
    )
    cue_alignment = v7.cue_alignment_v7(
        reference_words=reference,
        hypothesis_words=hypothesis_timed,
        steps=steps,
        cues=cues,
        cue_sample_ranges=candidate["cueSampleRanges"],
        sample_rate=v6.load_config()["master"]["nativeSampleRate"],
        config=audit_config,
    )
    prior_path = v8.repository_path(experiment.PRIOR_PROOF, directory=False)
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "evidenceScript": v8.file_binding(SCRIPT_PATH),
        "experimentScript": v8.file_binding(experiment.SCRIPT_PATH),
        "frozenV8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "frozenV8Config": v8.file_binding(v8.CONFIG_PATH),
        "priorFailed30_15_15Proof": v8.file_binding(prior_path),
        "stressText": stress_record,
        "candidateID": experiment.CANDIDATE_ID,
        "master": v8.file_binding(master_path),
        "changedVariableOnly": {
            "windowSeconds": 25,
            "overlapSeconds": 15,
            "strideSeconds": 10,
        },
        "unchangedFrozenThresholds": original,
        "extraction": extraction,
        "windowRecords": window_records,
        "allWindowGatesPass": all(item["passes"] for item in window_records),
        "requiredTimestampReconciliations": reconciliations,
        "frozenBoundViolations": violations,
        "exactFailure": {
            "exception": "V8 seam timing exceeds the reconciliation bound",
            "boundaryIndex": 115,
            "leftWindowIndex": 115,
            "rightWindowIndex": 116,
            "requiredPrefixWords": ["disease", "flight", "and"],
            "requiredPrefixWordCount": 3,
            "frozenMaximumPrefixWordCount": original[
                "maximumReconciledPrefixWords"
            ],
            "requiredMaximumForwardMilliseconds": failure[
                "maximumForwardMilliseconds"
            ],
            "frozenMaximumForwardMilliseconds": original[
                "maximumForwardTimestampReconciliationMilliseconds"
            ],
        },
        "relaxedAttributionOnly": {
            "purpose": (
                "Measure the exact failed seam after the frozen implementation "
                "stopped; never pass evidence and never a proposed gate change"
            ),
            "stitchedHypothesisWordCount": len(hypothesis),
            "referenceWordCount": len(reference),
            "alignment": alignment,
            "repetition": repetition,
            "cueAlignment": cue_alignment,
        },
        "passesDecoderGridExperiment": False,
        "productionMethodChanged": False,
        "gateChangeProposed": False,
        "audioChanged": False,
        "parentAudioMayBecomeV8Master": False,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Bind exact negative evidence from a stopped V8 decoder grid"
    )
    result.add_argument("--existing", required=True)
    result.add_argument("--offline", action="store_true")
    return result


def main() -> int:
    try:
        print(json.dumps(run(parser().parse_args()), ensure_ascii=False, indent=2))
        return 0
    except (
        v8.V8Error,
        v7.V7Error,
        v6.V6Error,
        v5.V5Error,
        production.PipelineError,
        wave.Error,
        OSError,
    ) as error:
        print(f"V8 decoder-grid evidence error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
