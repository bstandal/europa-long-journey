#!/usr/bin/env python3
"""Exact offline attribution of candidate-05 V6 R4 silence.

The analysis partitions every silent frame used by the frozen -45 dBFS audit
without changing audio.  It separately records explicit authored/adaptive zero
samples, model-retained low-energy frames, and the zero-duration assembly join.
"""

from __future__ import annotations

import argparse
from bisect import bisect_left, bisect_right
from collections import Counter
import json
import math
import os
from pathlib import Path
import sys
from typing import Any

import numpy as np

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v7_pipeline as v7


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V7_C05_EXACT_SILENCE_ATTRIBUTION_NO_TRANSFORM"
CANDIDATE_ID = "voice-candidate-05"
PRIOR_AUDIT = (
    "native/audio/narration/work/provisional-audit-v7/"
    "audit-v6-r4-windowed-r3-2026-07-25/voice-candidate-05/"
    "candidate-window-audit.v7.receipt.json"
)
PRIOR_MAP = (
    "native/audio/narration/work/provisional-audit-v7/"
    "silence-map-v6-r4-2026-07-25/silence-map.v7.receipt.json"
)


def _boundary_kind(
    *, current: dict[str, Any], following: dict[str, Any] | None
) -> str:
    if following is None:
        return "final-end"
    if following["segmentID"] != current["segmentID"]:
        return "inter-cue-handoff"
    separator = current["separatorAfter"]
    if separator == "\n\n":
        return "paragraph-within-cue"
    if separator == " ":
        return "sentence-within-paragraph"
    raise v7.V7Error("non-final utterance has an unsupported boundary")


def _seconds(samples: int, sample_rate: int) -> float:
    return samples / sample_rate


def _frame_edge_silence(
    *,
    cumulative: np.ndarray,
    threshold: float,
    start: int,
    end: int,
    frame: int,
    hop: int,
    leading: bool,
) -> int:
    if end - start < frame:
        raise v7.V7Error("utterance is too short for join-silence attribution")
    frame_starts = (
        range(start, end - frame + 1, hop)
        if leading
        else range(end - frame, start - 1, -hop)
    )
    count = 0
    for frame_start in frame_starts:
        mean_square = (
            cumulative[frame_start + frame] - cumulative[frame_start]
        ) / frame
        if math.sqrt(mean_square + 1e-15) >= threshold:
            break
        count += 1
    return (count - 1) * hop + frame if count else 0


def _model_frame_kind(meta: dict[str, Any], local_center_ms: float) -> str:
    words: list[v5.TimedWord] = meta["timedWords"]
    if local_center_ms < words[0].start_ms:
        return "model-retained-leading-roll"
    if local_center_ms >= words[-1].end_ms:
        return "model-retained-post-speech-roll"
    ends = meta["wordEndsMilliseconds"]
    starts = meta["wordStartsMilliseconds"]
    left = bisect_right(ends, local_center_ms) - 1
    right = bisect_left(starts, local_center_ms)
    if left >= 0 and right < len(words) and right == left + 1:
        reference_index = meta["hypothesisToReference"].get(left)
        if reference_index in meta["punctuationReferenceIndexes"]:
            return "model-internal-after-source-punctuation"
        return "model-internal-between-words-nonpunctuation"
    return "model-low-energy-within-word-or-unmapped"


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v7.V7Error("silence attribution requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    config = v7.load_config()
    dependencies = v7.validate_dependencies(config)
    output = v7.prepare_output(args.output, config)
    stress_receipt = v7._validate_shallow_stress_receipt(config)
    v6_config = v6.load_config()
    _, stress_record, _, utterances, utterance_record = (
        v6.stress_and_utterance_material(v6_config)
    )
    utterances_by_id = {item["utteranceID"]: item for item in utterances}
    candidate = next(
        item for item in stress_receipt["records"]
        if item["candidateID"] == CANDIDATE_ID
    )
    if candidate["durationCorrection"]["applied"] is not False:
        raise v7.V7Error("candidate-05 attribution requires its unchanged native timeline")
    native_binding = candidate["nativeAssembly"]["file"]
    native_path = Path(native_binding["path"])
    v7.validate_exact_file(
        native_path,
        byte_count=native_binding["bytes"],
        digest=native_binding["sha256"],
        label="candidate-05 native assembly",
    )
    audio, decoded = v5.read_native_audio(native_path, v6_config)
    ranges = candidate["utteranceRanges"]
    if len(ranges) != len(utterances):
        raise v7.V7Error("utterance timeline is incomplete")

    items_by_id: dict[str, dict[str, Any]] = {}
    batch_bindings: list[dict[str, Any]] = []
    for batch_binding in candidate["batchCommitReceipts"]:
        batch_path = Path(batch_binding["path"])
        v7.validate_exact_file(
            batch_path,
            byte_count=batch_binding["bytes"],
            digest=batch_binding["sha256"],
            label="candidate-05 batch receipt",
        )
        batch_bindings.append(v7.file_binding(batch_path))
        batch = production.load_json(batch_path)
        for item in batch["utteranceRecords"]:
            utterance_id = item["utterance"]["utteranceID"]
            if utterance_id in items_by_id:
                raise v7.V7Error("duplicate candidate-05 utterance receipt")
            items_by_id[utterance_id] = item
    if set(items_by_id) != set(utterances_by_id):
        raise v7.V7Error("candidate-05 utterance receipt set drifted")

    metadata: list[dict[str, Any]] = []
    exact_boundary_samples: Counter[str] = Counter()
    exact_boundary_counts: Counter[str] = Counter()
    exact_pause_origin_samples: Counter[str] = Counter()
    total_edge_fade_support_samples = 0
    for index, (timeline, utterance) in enumerate(zip(ranges, utterances, strict=True)):
        if timeline["utteranceID"] != utterance["utteranceID"]:
            raise v7.V7Error("utterance order does not match native timeline")
        item = items_by_id[utterance["utteranceID"]]
        processing = item["processing"]
        start = timeline["startSampleInclusive"]
        end = timeline["endSampleExclusive"]
        if (
            start != timeline["pretempoStartSampleInclusive"]
            or end != timeline["pretempoEndSampleExclusive"]
            or end - start != processing["processedSampleCount"]
        ):
            raise v7.V7Error("candidate-05 utterance timeline drifted")
        retained = processing["retainedSampleCountBeforePause"]
        authored = processing["pauseSamples"]
        adaptive = processing["adaptiveSemanticPacing"]["additionalPauseSamples"]
        if retained + authored + adaptive != end - start:
            raise v7.V7Error("utterance pause partition does not sum to its samples")
        boundary_audio = audio[start + retained : end]
        if boundary_audio.size and np.count_nonzero(boundary_audio) != 0:
            raise v7.V7Error("authored/adaptive boundary contains non-zero samples")
        following = utterances[index + 1] if index + 1 < len(utterances) else None
        boundary_kind = _boundary_kind(current=utterance, following=following)
        exact_boundary_samples[boundary_kind] += authored + adaptive
        exact_boundary_counts[boundary_kind] += 1
        exact_pause_origin_samples["authored-boundary-zero"] += authored
        exact_pause_origin_samples["adaptive-tempo-zero"] += adaptive
        total_edge_fade_support_samples += min(
            retained, processing["edgeFadeSamples"] * 2
        )

        transcript_binding = item["transcript"]["file"]
        transcript_path = Path(transcript_binding["path"])
        v7.validate_exact_file(
            transcript_path,
            byte_count=transcript_binding["bytes"],
            digest=transcript_binding["sha256"],
            label=f"candidate-05 {utterance['utteranceID']} transcript",
        )
        document = production.load_json(transcript_path)
        timed_words, grouping = v5.timed_words_from_whisper(
            document,
            master_duration_ms=(end - start) * 1000 / decoded["sampleRate"],
        )
        reference_words = v5.normalize_words(utterance["text"])
        hypothesis_words = [word.text for word in timed_words]
        steps, alignment = v5.monotone_global_alignment(
            reference_words, hypothesis_words
        )
        hypothesis_to_reference = {
            step.hypothesis_index: step.reference_index
            for step in steps
            if step.hypothesis_index is not None
            and step.reference_index is not None
        }
        metadata.append(
            {
                "utteranceID": utterance["utteranceID"],
                "segmentID": utterance["segmentID"],
                "startSampleInclusive": start,
                "endSampleExclusive": end,
                "retainedEndSampleExclusive": start + retained,
                "authoredEndSampleExclusive": start + retained + authored,
                "boundaryKind": boundary_kind,
                "timedWords": timed_words,
                "wordStartsMilliseconds": [word.start_ms for word in timed_words],
                "wordEndsMilliseconds": [word.end_ms for word in timed_words],
                "hypothesisToReference": hypothesis_to_reference,
                "punctuationReferenceIndexes": v7._punctuation_boundaries(
                    utterance["text"]
                ),
                "transcript": v7.file_binding(transcript_path),
                "transcriptAlignmentSHA256": alignment["alignmentSHA256"],
                "timedWordGroupingBounded": grouping["boundedByDecodedMaster"],
                "edgeFadeSamplesPerEdge": processing["edgeFadeSamples"],
                "authoredPauseSamples": authored,
                "adaptivePauseSamples": adaptive,
            }
        )

    sample_rate = decoded["sampleRate"]
    settings = config["silenceMapping"]
    frame = round(sample_rate * settings["frameMilliseconds"] / 1000)
    hop = round(sample_rate * settings["hopMilliseconds"] / 1000)
    threshold = 10 ** (settings["thresholdDBFS"] / 20)
    squared = audio.astype(np.float64) ** 2
    cumulative = np.concatenate(([0.0], np.cumsum(squared)))
    starts = np.arange(0, audio.size - frame + 1, hop, dtype=np.int64)
    rms = np.sqrt(
        (cumulative[starts + frame] - cumulative[starts]) / frame + 1e-15
    )
    silent = rms < threshold
    prior_path = v7.repository_path(PRIOR_AUDIT, directory=False)
    prior = production.load_json(prior_path)
    prior_fraction = prior["silence"]["totalSilenceFraction"]
    measured_fraction = float(np.mean(silent))
    if measured_fraction != prior_fraction:
        raise v7.V7Error("silence attribution does not reproduce frozen V7 fraction")

    end_samples = [item["endSampleExclusive"] for item in metadata]
    frame_categories: Counter[str] = Counter()
    semantic_boundary_frames: Counter[str] = Counter()
    for frame_start in starts[silent]:
        center = int(frame_start) + frame // 2
        utterance_index = bisect_right(end_samples, center)
        if utterance_index >= len(metadata):
            utterance_index = len(metadata) - 1
        meta = metadata[utterance_index]
        if not (
            meta["startSampleInclusive"]
            <= center
            < meta["endSampleExclusive"]
        ):
            raise v7.V7Error("silent frame centre escaped the utterance timeline")
        if center >= meta["retainedEndSampleExclusive"]:
            semantic_boundary_frames[meta["boundaryKind"]] += 1
            if center < meta["authoredEndSampleExclusive"]:
                frame_categories["authored-boundary-zero"] += 1
            else:
                frame_categories["adaptive-tempo-zero"] += 1
        else:
            local_ms = (
                center - meta["startSampleInclusive"]
            ) * 1000 / sample_rate
            frame_categories[_model_frame_kind(meta, local_ms)] += 1
    if sum(frame_categories.values()) != int(np.count_nonzero(silent)):
        raise v7.V7Error("silent frame attribution is not exhaustive")

    join_records: list[dict[str, Any]] = []
    for index, (left, right) in enumerate(zip(metadata, metadata[1:])):
        boundary = left["endSampleExclusive"]
        if boundary != right["startSampleInclusive"]:
            raise v7.V7Error("utterance assembly contains a gap or overlap")
        left_samples = _frame_edge_silence(
            cumulative=cumulative,
            threshold=threshold,
            start=left["startSampleInclusive"],
            end=left["endSampleExclusive"],
            frame=frame,
            hop=hop,
            leading=False,
        )
        right_samples = _frame_edge_silence(
            cumulative=cumulative,
            threshold=threshold,
            start=right["startSampleInclusive"],
            end=right["endSampleExclusive"],
            frame=frame,
            hop=hop,
            leading=True,
        )
        join_records.append(
            {
                "boundaryIndex": index,
                "leftUtteranceID": left["utteranceID"],
                "rightUtteranceID": right["utteranceID"],
                "boundaryKind": left["boundaryKind"],
                "nativeSample": boundary,
                "leftTrailingLowEnergyMilliseconds": left_samples
                * 1000
                / sample_rate,
                "rightLeadingLowEnergyMilliseconds": right_samples
                * 1000
                / sample_rate,
                "combinedObservedJoinLowEnergyMilliseconds": (
                    left_samples + right_samples
                )
                * 1000
                / sample_rate,
                "samplesInsertedByAssembly": 0,
            }
        )
    join_durations = [
        item["combinedObservedJoinLowEnergyMilliseconds"] for item in join_records
    ]

    frame_count = len(starts)
    silent_count = int(np.count_nonzero(silent))
    category_records = [
        {
            "category": category,
            "silentFrameCount": count,
            "fractionOfAllSilentFrames": count / silent_count,
            "analysisFrameEquivalentSecondsAtHop": count * hop / sample_rate,
        }
        for category, count in sorted(frame_categories.items())
    ]
    explicit_frame_count = (
        frame_categories["authored-boundary-zero"]
        + frame_categories["adaptive-tempo-zero"]
    )
    model_frame_count = silent_count - explicit_frame_count
    frame_equivalent_duration = frame_count * hop / sample_rate
    silent_frame_equivalent_duration = silent_count * hop / sample_rate
    minimum_reduction_if_duration_contracts = (
        silent_frame_equivalent_duration
        - settings["maximumTotalSilenceFractionInheritedFromV6"]
        * frame_equivalent_duration
    ) / (1 - settings["maximumTotalSilenceFractionInheritedFromV6"])
    fraction_after_counterfactual_all_explicit_removal = (
        model_frame_count / (frame_count - explicit_frame_count)
    )
    exact_boundary_records = [
        {
            "boundaryKind": kind,
            "boundaryCount": exact_boundary_counts[kind],
            "exactZeroSamples": samples,
            "exactZeroSeconds": _seconds(samples, sample_rate),
            "silentFrameCentreCount": semantic_boundary_frames[kind],
        }
        for kind, samples in sorted(exact_boundary_samples.items())
    ]
    prior_map_path = v7.repository_path(PRIOR_MAP, directory=False)
    result = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v7.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v7.file_binding(SCRIPT_PATH),
        "frozenV7Pipeline": v7.file_binding(v7.SCRIPT_PATH),
        "frozenV7Config": v7.file_binding(v7.CONFIG_PATH),
        "dependencyBindings": dependencies,
        "stressReceipt": v7.file_binding(Path(stress_receipt["_path"])),
        "stressText": stress_record,
        "utteranceManifest": utterance_record,
        "candidateID": CANDIDATE_ID,
        "nativeAssembly": v7.file_binding(native_path),
        "priorFrozenAudit": v7.file_binding(prior_path),
        "priorSilenceMap": v7.file_binding(prior_map_path),
        "settings": {
            "thresholdDBFS": settings["thresholdDBFS"],
            "frameMilliseconds": settings["frameMilliseconds"],
            "hopMilliseconds": settings["hopMilliseconds"],
            "attributionRule": (
                "Every frozen-audit silent frame is assigned by its centre sample "
                "to exactly one byte-bound utterance region."
            ),
        },
        "reproduction": {
            "decodedSampleCount": int(audio.size),
            "analysisFrameCount": frame_count,
            "silentFrameCount": silent_count,
            "totalSilenceFraction": measured_fraction,
            "matchesFrozenV7Exactly": True,
        },
        "silentFrameAttribution": category_records,
        "topLevelAttribution": {
            "modelRetainedAudio": {
                "silentFrameCount": model_frame_count,
                "fractionOfAllSilentFrames": model_frame_count / silent_count,
                "analysisFrameEquivalentSecondsAtHop": model_frame_count
                * hop
                / sample_rate,
            },
            "explicitAuthoredOrAdaptiveBoundaryZero": {
                "silentFrameCount": explicit_frame_count,
                "fractionOfAllSilentFrames": explicit_frame_count / silent_count,
                "analysisFrameEquivalentSecondsAtHop": explicit_frame_count
                * hop
                / sample_rate,
            },
            "assemblyStitchingAddedTime": {
                "silentFrameCount": 0,
                "fractionOfAllSilentFrames": 0.0,
                "analysisFrameEquivalentSecondsAtHop": 0.0,
            },
        },
        "exactExplicitBoundaryZeros": {
            "records": exact_boundary_records,
            "originRecords": [
                {
                    "origin": origin,
                    "exactZeroSamples": samples,
                    "exactZeroSeconds": _seconds(samples, sample_rate),
                }
                for origin, samples in sorted(exact_pause_origin_samples.items())
            ],
            "totalExactZeroSamples": sum(exact_pause_origin_samples.values()),
            "totalExactZeroSeconds": _seconds(
                sum(exact_pause_origin_samples.values()), sample_rate
            ),
            "allSamplesBitExactZero": True,
        },
        "stitching": {
            "method": "Direct contiguous concatenation of processed utterances",
            "boundaryCount": len(join_records),
            "samplesInsertedByAssembly": 0,
            "crossfadeSamples": 0,
            "maximumAbsoluteJoinDiscontinuity": candidate["pretempoAssembly"]
            ["seamAudit"]["maximumAbsoluteDiscontinuity"],
            "edgeFadeSamplesPerUtteranceEdge": metadata[0][
                "edgeFadeSamplesPerEdge"
            ],
            "totalEdgeFadeSupportSamples": total_edge_fade_support_samples,
            "totalEdgeFadeSupportSeconds": _seconds(
                total_edge_fade_support_samples, sample_rate
            ),
            "edgeFadesAlterAmplitudeButAddNoTime": True,
            "observedJoinLowEnergyMilliseconds": {
                "minimum": min(join_durations),
                "median": float(np.percentile(join_durations, 50)),
                "p90": float(np.percentile(join_durations, 90)),
                "p95": float(np.percentile(join_durations, 95)),
                "maximum": max(join_durations),
            },
            "joinRecords": join_records,
        },
        "gateImplication": {
            "maximumTotalSilenceFraction": settings[
                "maximumTotalSilenceFractionInheritedFromV6"
            ],
            "minimumLowEnergyReductionSecondsIfRemovedTimeAlsoContractsMaster": minimum_reduction_if_duration_contracts,
            "counterfactualFractionAfterRemovingEveryExplicitBoundaryZeroFrame": fraction_after_counterfactual_all_explicit_removal,
            "explicitBoundaryRemovalWouldPass": fraction_after_counterfactual_all_explicit_removal
            <= settings["maximumTotalSilenceFractionInheritedFromV6"],
            "transformAuthorized": False,
            "conclusion": (
                "Boundary-pause removal alone cannot pass. A new synthesis or a "
                "newly proven segmentation method must reduce model-retained "
                "low-energy time while preserving text, identity and duration."
            ),
        },
        "finding": (
            "Assembly inserts zero samples. Explicit authored/adaptive boundary "
            "zeros are exact and separately counted; all remaining frozen-audit "
            "silent frames are inside model-retained audio. Reducing the latter "
            "requires new synthesis or a newly proven segmentation method."
        ),
        "batchReceiptBindings": batch_bindings,
        "audioChanged": False,
        "silenceRemoved": False,
        "speechTimeStretchApplied": False,
        "productionGateChanged": False,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }
    receipt_path = output / "silence-attribution.v7.receipt.json"
    v7.write_json(receipt_path, result)
    return {**result, "receipt": v7.file_binding(receipt_path)}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Exact offline candidate-05 V7 silence attribution"
    )
    result.add_argument("--output", required=True, type=Path)
    result.add_argument("--offline", action="store_true")
    return result


def main() -> int:
    try:
        print(json.dumps(run(parser().parse_args()), ensure_ascii=False, indent=2))
        return 0
    except (v7.V7Error, v6.V6Error, v5.V5Error, production.PipelineError) as error:
        print(f"V7 silence attribution error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
