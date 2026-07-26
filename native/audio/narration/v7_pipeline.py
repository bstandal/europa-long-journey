#!/usr/bin/env python3
"""Offline V7 narration audit and silence-map laboratory.

V7 preserves the exact V6 R4 masters as hash-bound evidence.  It replaces the
demonstrably collapsed monolithic Whisper decode with deterministic overlapping
windows that cover every decoded master sample, prove every overlap, and stitch
one monotone transcript only at an exact shared word.  Silence work is mapping
only in this revision: no audio transform is authorised.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys
from typing import Any, Sequence
import wave

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6


SCRIPT_PATH = Path(__file__).absolute()
CONFIG_PATH = SCRIPT_PATH.with_name("v7-audit-config.json")
REPOSITORY_ROOT = SCRIPT_PATH.parents[3]
EXPECTED_CONFIG_BYTES = 7817
EXPECTED_CONFIG_SHA256 = (
    "8349b0c911ec88f9e561badec48c3752c90bbdc965db35e6350e09fa49540b6c"
)

METHOD_STATUS = "CODEX_V7_WINDOWED_MASTER_AUDIT_AND_SILENCE_MAPPING_FROZEN"
TRUST_DOMAIN = "CODEX_V7_DIAGNOSTIC_NON_SHIPPING"
AUDIT_STATUS = "CODEX_V7_COMPLETE_WINDOWED_MASTER_AUDIT_NON_SHIPPING"
CANDIDATE_STATUS = "CODEX_V7_WINDOWED_CANDIDATE_AUDIT_NON_SHIPPING"
SILENCE_STATUS = "CODEX_V7_SILENCE_MAP_NO_TRANSFORM_AUTHORIZED"
EXPECTED_FINALISTS = ["voice-candidate-05", "voice-candidate-06"]


class V7Error(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def file_binding(path: Path) -> dict[str, Any]:
    return v5.file_binding(path)


def write_json(path: Path, value: Any) -> None:
    v5.write_json(path, value)


def repository_path(relative: str, *, directory: bool | None = None) -> Path:
    try:
        return v6.repository_path(relative, directory=directory)
    except v6.V6Error as error:
        raise V7Error(str(error)) from error


def validate_exact_file(
    path: Path, *, byte_count: int, digest: str, label: str
) -> None:
    try:
        v5.validate_exact_file(
            path, byte_count=byte_count, digest=digest, label=label
        )
    except v5.V5Error as error:
        raise V7Error(str(error)) from error


def _validate_master_construction_contract(contract: dict[str, Any]) -> None:
    if contract != {
        "oneSynthesisCallRequired": False,
        "deterministicAssemblyAtAuthoredSemanticBoundariesPermitted": True,
        "everyComponentMustPassBeforeAssembly": True,
        "exactApprovedCharacterPartitionRequired": True,
        "wordOrCharacterChangeProhibited": True,
        "audibleSeamsProhibited": True,
        "durationPaddingProhibited": True,
        "speechTimeStretchProhibited": True,
        "finalDeliverable": "One seamless 18-22 minute master",
        "oldOneCallAndNoTakeAssemblyContractProhibited": True,
    }:
        raise V7Error("V7 seamless-master construction contract drifted")


def validate_config_document(config: dict[str, Any]) -> None:
    if (
        config.get("schemaVersion") != 1
        or config.get("status") != METHOD_STATUS
        or config.get("trustDomain") != TRUST_DOMAIN
        or config.get("language") != "English"
        or config.get("locale") != "en-GB"
    ):
        raise V7Error("V7 config identity drifted")
    parent = config.get("parentChain", {})
    if (
        parent.get("v6R4Role")
        != "HASH_BOUND_NEGATIVE_EVIDENCE_AND_AUDIO_PARENT_PENDING_V7"
        or parent.get("v6GateChangesPermitted") is not False
    ):
        raise V7Error("V6 R4 role or unchanged-gate contract drifted")
    negative = config.get("v6MonolithicNegativeEvidence", {})
    if (
        negative.get("status")
        != "V6_CANDIDATE_05_MONOLITHIC_WHISPER_DECODER_COLLAPSE_NOT_AUDIO_COLLAPSE"
        or negative.get("referenceWordCount") != 3422
        or negative.get("hypothesisWordCount") != 6231
        or negative.get("perUtteranceGateCount") != 123
        or negative.get("perUtterancePassingCount") != 123
        or negative.get("audioMayBeRejectedFromThisTranscriptAlone") is not False
    ):
        raise V7Error("V6 monolithic negative-evidence contract drifted")
    _validate_master_construction_contract(config.get("masterConstructionContract", {}))
    window = config.get("windowedASR", {})
    if (
        window.get("windowSeconds") != 60
        or window.get("overlapSeconds") != 10
        or window.get("strideSeconds") != 50
        or window.get("decodedSampleCoverageRequired") != 1.0
        or window.get("gapsPermitted") is not False
        or window.get("answerPromptProhibited") is not True
        or window.get("externalTranscriptReceiptProhibited") is not True
        or window.get("monolithicWhisperPermittedAsPassingEvidence") is not False
    ):
        raise V7Error("V7 window grid or evidence contract drifted")
    fallback = window.get("segmentTextTimingFallback", {})
    if (
        fallback.get("segmentAndLexicalTokenTextMustNormalizeIdentically") is not True
        or fallback.get("maximumSegmentTailOverrunMilliseconds") != 20
        or fallback.get("invalidSegmentGeometryFails") is not True
        or fallback.get("malformedTokenGeometryRecorded") is not True
    ):
        raise V7Error("V7 segment fallback contract drifted")
    boundary = window.get("boundaryGate", {})
    if (
        boundary.get("minimumExactSharedWords") != 18
        or boundary.get("maximumWordAlignmentErrorRate") != 0.35
        or boundary.get("maximumNonmatchingRunWordsPerSide") != 14
        or boundary.get("maximumWordCountRatio") != 1.55
        or boundary.get("maximumStitchAnchorDistanceFromOverlapMidpointMilliseconds")
        != 750
        or boundary.get("maximumForwardTimestampReconciliationMilliseconds") != 750
        or boundary.get("reconciliationMayAlterAudioOrWords") is not False
        or boundary.get("reconciliationMayAlterInteriorWindowTiming") is not False
        or boundary.get("allBoundariesMustPass") is not True
    ):
        raise V7Error("V7 overlap boundary gate drifted")
    aggregate = window.get("aggregateGate", {})
    inherited = config.get("parentChain", {}).get("v6GateChangesPermitted") is False
    if (
        inherited is not True
        or aggregate.get("maximumWordErrorRate") != 0.03
        or aggregate.get("maximumExcessRepeatedSixGramFraction") != 0.005
        or aggregate.get("minimumExactReferenceCoveragePerCue") != 0.98
        or aggregate.get("minimumExactHypothesisCoveragePerCue") != 0.98
        or aggregate.get("maximumNonmatchingReferenceRunWordsPerCue") != 6
        or aggregate.get("maximumNonmatchingHypothesisRunWordsPerCue") != 12
        or aggregate.get("anchorWords") != 8
        or aggregate.get("minimumExactFirstAnchorWords") != 8
        or aggregate.get("minimumExactLastAnchorWords") != 8
        or aggregate.get("boundaryToleranceMilliseconds") != 750
    ):
        raise V7Error("V7 aggregate or inherited cue gate drifted")
    silence = config.get("silenceMapping", {})
    if (
        silence.get("status") != "MAPPING_ONLY_NO_TRANSFORM_AUTHORIZED"
        or silence.get("thresholdDBFS") != -45
        or silence.get("frameMilliseconds") != 20
        or silence.get("hopMilliseconds") != 10
        or silence.get("maximumTotalSilenceFractionInheritedFromV6") != 0.12
        or silence.get("authoredTerminalPauseMustBePreserved") is not True
        or silence.get("adaptiveSemanticPauseMustBePreserved") is not True
        or silence.get("leadingAndPostSpeechRollMustBePreserved") is not True
        or silence.get("punctuationBreathsMustBePreserved") is not True
        or silence.get("speechTimeStretchProhibited") is not True
        or silence.get("removalAuthorized") is not False
    ):
        raise V7Error("V7 silence-map-only contract drifted")
    runtime = config.get("chatterboxComparisonRuntime", {})
    if (
        runtime.get("comparisonOnly") is not True
        or runtime.get("v7ProductionParentPermitted") is not False
        or runtime.get("editorVoiceSelection") is not False
    ):
        raise V7Error("Chatterbox comparison-only gate drifted")
    if config.get("costPolicy") != {
        "offlineRequiredAfterPinnedDownloads": True,
        "runtimeNetworkProhibited": True,
        "paidAPIProhibited": True,
        "incrementalCostNOK": 0,
    }:
        raise V7Error("V7 zero-cost offline policy drifted")
    if set(config.get("claimsExcluded", [])) != {
        "editor voice selection",
        "final word-accuracy approval",
        "final pronunciation approval",
        "artistic approval",
        "shipping approval",
    }:
        raise V7Error("V7 approval exclusions drifted")


def load_config(path: Path = CONFIG_PATH) -> dict[str, Any]:
    if path.absolute() != CONFIG_PATH:
        raise V7Error("V7 config path is frozen")
    validate_exact_file(
        path,
        byte_count=EXPECTED_CONFIG_BYTES,
        digest=EXPECTED_CONFIG_SHA256,
        label="V7 config",
    )
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise V7Error(f"cannot load V7 config: {error}") from error
    validate_config_document(config)
    config["_path"] = str(path)
    return config


def validate_dependencies(config: dict[str, Any]) -> dict[str, Any]:
    records: dict[str, Any] = {}
    parent = config["parentChain"]
    for label, prefix in [
        ("v6Pipeline", "v6Pipeline"),
        ("v6Config", "v6Config"),
        ("v5AuditUtility", "v5AuditUtility"),
    ]:
        path = repository_path(parent[f"{prefix}Path"], directory=False)
        validate_exact_file(
            path,
            byte_count=parent[f"{prefix}Bytes"],
            digest=parent[f"{prefix}SHA256"],
            label=label,
        )
        records[label] = file_binding(path)
    stress_receipt = repository_path(
        config["paths"]["v6R4StressReceipt"], directory=False
    )
    validate_exact_file(
        stress_receipt,
        byte_count=parent["v6R4StressReceiptBytes"],
        digest=parent["v6R4StressReceiptSHA256"],
        label="V6 R4 stress receipt",
    )
    records["v6R4StressReceipt"] = file_binding(stress_receipt)
    negative = config["v6MonolithicNegativeEvidence"]
    for label, prefix in [("monolithicTranscript", "transcript"), ("monolithicLog", "log")]:
        path = repository_path(negative[f"{prefix}Path"], directory=False)
        validate_exact_file(
            path,
            byte_count=negative[f"{prefix}Bytes"],
            digest=negative[f"{prefix}SHA256"],
            label=label,
        )
        records[label] = file_binding(path)
    runtime = config["chatterboxComparisonRuntime"]
    for label, prefix in [
        ("officialChatterboxSnapshotReceipt", "officialSnapshotReceipt"),
        ("convertedChatterboxPreflight", "convertedPreflight"),
        ("convertedChatterboxSnapshotReceipt", "convertedSnapshotReceipt"),
        ("s3TokenizerSnapshotReceipt", "s3TokenizerReceipt"),
    ]:
        path = repository_path(runtime[f"{prefix}Path"], directory=False)
        validate_exact_file(
            path,
            byte_count=runtime[f"{prefix}Bytes"],
            digest=runtime[f"{prefix}SHA256"],
            label=label,
        )
        records[label] = file_binding(path)
    return records


def pipeline_binding(config: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "trustDomain": TRUST_DOMAIN,
        "script": file_binding(SCRIPT_PATH),
        "config": file_binding(Path(config["_path"])),
        "dependencies": validate_dependencies(config),
    }


def work_root(config: dict[str, Any], *, create: bool) -> Path:
    path = REPOSITORY_ROOT / config["paths"]["workRoot"]
    if create:
        path.mkdir(parents=True, exist_ok=True)
    return path


def prepare_output(path: Path, config: dict[str, Any]) -> Path:
    root = work_root(config, create=True)
    target = v5.confined_path(
        path,
        root=root,
        must_exist=path.exists(),
        expect_directory=True if path.exists() else None,
    )
    if target == root or target.parent != root:
        raise V7Error("V7 output must be one direct child of its work root")
    if target.exists() and any(target.iterdir()):
        raise V7Error("V7 output must be absent or empty")
    target.mkdir(parents=True, exist_ok=True)
    return target


def _validate_shallow_stress_receipt(config: dict[str, Any]) -> dict[str, Any]:
    path = repository_path(config["paths"]["v6R4StressReceipt"], directory=False)
    receipt = production.load_json(path)
    if (
        receipt.get("status") != v6.STRESS_STATUS
        or receipt.get("trustDomain") != v6.TRUST_DOMAIN
        or receipt.get("provisionalFinalistIDs") != EXPECTED_FINALISTS
        or [item.get("candidateID") for item in receipt.get("records", [])]
        != EXPECTED_FINALISTS
        or receipt.get("shippingApproval") is not False
    ):
        raise V7Error("V6 R4 stress receipt identity drifted")
    for candidate in receipt["records"]:
        for label, binding in [
            ("native assembly", candidate["nativeAssembly"]["file"]),
            ("master", candidate["master"]["file"]),
            ("candidate receipt", candidate["candidateCommitReceipt"]),
        ]:
            file_path = Path(binding["path"])
            validate_exact_file(
                file_path,
                byte_count=binding["bytes"],
                digest=binding["sha256"],
                label=f"{candidate['candidateID']} {label}",
            )
        for batch in candidate["batchCommitReceipts"]:
            batch_path = Path(batch["path"])
            validate_exact_file(
                batch_path,
                byte_count=batch["bytes"],
                digest=batch["sha256"],
                label=f"{candidate['candidateID']} batch receipt",
            )
    receipt["_path"] = str(path)
    return receipt


def _window_intervals(sample_count: int, sample_rate: int, config: dict[str, Any]) -> list[dict[str, int]]:
    settings = config["windowedASR"]
    window = settings["windowSeconds"] * sample_rate
    overlap = settings["overlapSeconds"] * sample_rate
    stride = settings["strideSeconds"] * sample_rate
    if window - overlap != stride or sample_count <= overlap:
        raise V7Error("invalid V7 sample grid")
    intervals: list[dict[str, int]] = []
    start = 0
    index = 0
    while True:
        end = min(sample_count, start + window)
        intervals.append(
            {
                "index": index,
                "startSampleInclusive": start,
                "endSampleExclusive": end,
            }
        )
        if end == sample_count:
            break
        start += stride
        index += 1
    if intervals[-1]["endSampleExclusive"] - intervals[-1]["startSampleInclusive"] <= overlap:
        raise V7Error("final V7 ASR window is not longer than its overlap")
    return intervals


def _coverage_audit(
    intervals: list[dict[str, int]], sample_count: int
) -> dict[str, Any]:
    if not intervals or intervals[0]["startSampleInclusive"] != 0:
        raise V7Error("window coverage does not start at sample zero")
    events: list[tuple[int, int]] = []
    previous_end = 0
    for interval in intervals:
        start = interval["startSampleInclusive"]
        end = interval["endSampleExclusive"]
        if start < 0 or end <= start or end > sample_count or start > previous_end:
            raise V7Error("window coverage contains an invalid interval or gap")
        events.extend([(start, 1), (end, -1)])
        previous_end = max(previous_end, end)
    if previous_end != sample_count:
        raise V7Error("window coverage does not reach the final sample")
    events.sort(key=lambda item: (item[0], -item[1]))
    active = 0
    prior = 0
    covered = 0
    minimum = math.inf
    maximum = 0
    for position, delta in events:
        if position > prior:
            if active <= 0:
                raise V7Error("window sample sweep found an uncovered range")
            covered += position - prior
            minimum = min(minimum, active)
            maximum = max(maximum, active)
        active += delta
        prior = position
    if active != 0 or covered != sample_count:
        raise V7Error("window sample sweep did not cover exactly the decoded master")
    return {
        "decodedSampleCount": sample_count,
        "coveredSampleCount": covered,
        "coverageFraction": covered / sample_count,
        "minimumCoverageMultiplicity": int(minimum),
        "maximumCoverageMultiplicity": maximum,
        "gapSampleCount": 0,
        "passes": True,
    }


def extract_windows(
    *, master_path: Path, directory: Path, config: dict[str, Any]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if directory.exists():
        raise V7Error("window extraction directory already exists")
    directory.mkdir()
    try:
        with wave.open(str(master_path), "rb") as source:
            sample_rate = source.getframerate()
            channels = source.getnchannels()
            sample_width = source.getsampwidth()
            compression = source.getcomptype()
            sample_count = source.getnframes()
            if (sample_rate, channels, sample_width, compression) != (48000, 1, 3, "NONE"):
                raise V7Error("V7 master is not 48 kHz 24-bit mono PCM")
            intervals = _window_intervals(sample_count, sample_rate, config)
            records: list[dict[str, Any]] = []
            for interval in intervals:
                index = interval["index"]
                start = interval["startSampleInclusive"]
                end = interval["endSampleExclusive"]
                source.setpos(start)
                frame_bytes = source.readframes(end - start)
                if len(frame_bytes) != (end - start) * sample_width:
                    raise V7Error("master frame slice is incomplete")
                target = directory / f"window-{index:03d}.wav"
                with wave.open(str(target), "wb") as output:
                    output.setnchannels(channels)
                    output.setsampwidth(sample_width)
                    output.setframerate(sample_rate)
                    output.writeframes(frame_bytes)
                with wave.open(str(target), "rb") as check:
                    restored = check.readframes(check.getnframes())
                if restored != frame_bytes:
                    raise V7Error("window WAV serialization changed PCM frame bytes")
                records.append(
                    {
                        **interval,
                        "durationSeconds": (end - start) / sample_rate,
                        "audio": file_binding(target),
                        "pcmFrameBytes": len(frame_bytes),
                        "pcmFrameBytesSHA256": hashlib.sha256(frame_bytes).hexdigest(),
                        "exactMasterFrameSlice": True,
                        "_path": target,
                    }
                )
    except (wave.Error, OSError) as error:
        raise V7Error(f"cannot extract V7 master windows: {error}") from error
    coverage = _coverage_audit(records, sample_count)
    return records, {
        "master": file_binding(master_path),
        "containerBytesBoundByMasterSHA256": True,
        "sampleRate": sample_rate,
        "channels": channels,
        "sampleWidthBytes": sample_width,
        "decodedSampleCoverage": coverage,
        "windowCount": len(records),
        "monolithicWhisperUsed": False,
    }


def _is_special_token(text: str) -> bool:
    return text.startswith("[_") and text.endswith("]")


def segment_timed_words(
    document: dict[str, Any], *, duration_ms: float, config: dict[str, Any]
) -> tuple[list[v5.TimedWord], dict[str, Any]]:
    if document.get("result", {}).get("language") != "en":
        raise V7Error("window transcript is not English")
    segments = document.get("transcription")
    if not isinstance(segments, list) or not segments:
        raise V7Error("window transcript contains no segments")
    tolerance = config["windowedASR"]["segmentTextTimingFallback"][
        "maximumSegmentTailOverrunMilliseconds"
    ]
    words: list[v5.TimedWord] = []
    previous_end = 0.0
    malformed_token_geometry = 0
    token_count = 0
    lexical_parity_checks = 0
    maximum_overrun = 0.0
    for segment_index, segment in enumerate(segments):
        offsets = segment.get("offsets", {})
        start = offsets.get("from")
        end = offsets.get("to")
        text = segment.get("text")
        tokens = segment.get("tokens")
        if (
            type(start) is not int
            or type(end) is not int
            or not isinstance(text, str)
            or not isinstance(tokens, list)
            or start < 0
            or end < start
            or start < previous_end
            or end > duration_ms + tolerance
        ):
            raise V7Error("Whisper segment geometry is invalid")
        maximum_overrun = max(maximum_overrun, max(0.0, end - duration_ms))
        bounded_start = min(float(start), duration_ms)
        bounded_end = min(float(end), duration_ms)
        lexical_pieces: list[str] = []
        prior_token_start = -1
        prior_token_end = -1
        for token in tokens:
            token_text = token.get("text")
            token_offsets = token.get("offsets", {})
            token_start = token_offsets.get("from")
            token_end = token_offsets.get("to")
            if (
                not isinstance(token_text, str)
                or type(token_start) is not int
                or type(token_end) is not int
            ):
                raise V7Error("Whisper token lacks exact text or integer offsets")
            token_count += 1
            if (
                token_start < 0
                or token_end < token_start
                or token_start < prior_token_start
                or token_end < prior_token_end
                or token_start < prior_token_end
            ):
                malformed_token_geometry += 1
            prior_token_start = max(prior_token_start, token_start)
            prior_token_end = max(prior_token_end, token_end)
            if not _is_special_token(token_text):
                lexical_pieces.append(token_text)
        normalized_segment = v5.normalize_words(text)
        normalized_tokens = v5.normalize_words("".join(lexical_pieces))
        lexical_parity_checks += 1
        if normalized_segment != normalized_tokens:
            raise V7Error("Whisper segment text and lexical token text disagree")
        if normalized_segment:
            span = bounded_end - bounded_start
            for word_index, word in enumerate(normalized_segment):
                word_start = bounded_start + span * word_index / len(normalized_segment)
                word_end = bounded_start + span * (word_index + 1) / len(normalized_segment)
                words.append(
                    v5.TimedWord(
                        word,
                        word_start,
                        word_end,
                        segment_index,
                        segment_index + 1,
                    )
                )
        previous_end = bounded_end
    if not words:
        raise V7Error("window transcript contains no normalized words")
    return words, {
        "algorithm": "Pinned Whisper segment text with monotone segment timing and uniform intra-segment normalized-word projection",
        "segmentCount": len(segments),
        "sourceTokenCount": token_count,
        "timedWordCount": len(words),
        "lexicalParityChecks": lexical_parity_checks,
        "allLexicalParityChecksPass": True,
        "malformedTokenGeometryCount": malformed_token_geometry,
        "malformedTokenGeometryUsedForTiming": False,
        "maximumSegmentTailOverrunMilliseconds": maximum_overrun,
        "monotoneSegmentGeometry": True,
        "boundedByDecodedWindow": True,
    }


def _absolute_words(
    words: list[v5.TimedWord], *, start_sample: int, sample_rate: int
) -> list[v5.TimedWord]:
    offset_ms = start_sample * 1000 / sample_rate
    return [
        v5.TimedWord(
            item.text,
            item.start_ms + offset_ms,
            item.end_ms + offset_ms,
            item.source_token_start,
            item.source_token_end_exclusive,
        )
        for item in words
    ]


def _word_mid_sample(word: v5.TimedWord, sample_rate: int) -> float:
    return (word.start_ms + word.end_ms) * sample_rate / 2000


def maximum_false_run(values: Sequence[bool]) -> int:
    maximum = current = 0
    for value in values:
        if value:
            current = 0
        else:
            current += 1
            maximum = max(maximum, current)
    return maximum


def stitch_window_words(
    *,
    windows: list[dict[str, Any]],
    words_by_window: list[list[v5.TimedWord]],
    sample_rate: int,
    config: dict[str, Any],
) -> tuple[list[v5.TimedWord], dict[str, Any]]:
    limits = config["windowedASR"]["boundaryGate"]
    cuts: list[dict[str, Any]] = []
    boundary_records: list[dict[str, Any]] = []
    for boundary_index, (left_window, right_window) in enumerate(
        zip(windows, windows[1:])
    ):
        overlap_start = right_window["startSampleInclusive"]
        overlap_end = left_window["endSampleExclusive"]
        if overlap_start >= overlap_end:
            raise V7Error("adjacent ASR windows do not overlap")
        left_overlap = [
            (index, word)
            for index, word in enumerate(words_by_window[boundary_index])
            if overlap_start <= _word_mid_sample(word, sample_rate) < overlap_end
        ]
        right_overlap = [
            (index, word)
            for index, word in enumerate(words_by_window[boundary_index + 1])
            if overlap_start <= _word_mid_sample(word, sample_rate) < overlap_end
        ]
        if not left_overlap or not right_overlap:
            raise V7Error("overlap contains no words on one side")
        steps, alignment = v5.monotone_global_alignment(
            [item.text for _, item in left_overlap],
            [item.text for _, item in right_overlap],
        )
        exact_left = [False] * len(left_overlap)
        exact_right = [False] * len(right_overlap)
        overlap_mid_ms = (overlap_start + overlap_end) * 500 / sample_rate
        anchors: list[tuple[float, int, int, str, float]] = []
        for step in steps:
            if step.operation != "equal":
                continue
            assert step.reference_index is not None and step.hypothesis_index is not None
            exact_left[step.reference_index] = True
            exact_right[step.hypothesis_index] = True
            left_index, left_word = left_overlap[step.reference_index]
            right_index, right_word = right_overlap[step.hypothesis_index]
            shared_mid = (
                left_word.start_ms
                + left_word.end_ms
                + right_word.start_ms
                + right_word.end_ms
            ) / 4
            anchors.append(
                (
                    abs(shared_mid - overlap_mid_ms),
                    left_index,
                    right_index,
                    left_word.text,
                    shared_mid,
                )
            )
        if not anchors:
            raise V7Error("overlap has no exact shared stitch word")
        anchor = min(anchors, key=lambda item: (item[0], item[1], item[2]))
        left_count = len(left_overlap)
        right_count = len(right_overlap)
        count_ratio = max(left_count, right_count) / min(left_count, right_count)
        left_run = maximum_false_run(exact_left)
        right_run = maximum_false_run(exact_right)
        gates = {
            "minimumExactSharedWords": alignment["equal"]
            >= limits["minimumExactSharedWords"],
            "maximumWordAlignmentErrorRate": alignment["wordAlignmentErrorRate"]
            <= limits["maximumWordAlignmentErrorRate"],
            "maximumLeftNonmatchingRun": left_run
            <= limits["maximumNonmatchingRunWordsPerSide"],
            "maximumRightNonmatchingRun": right_run
            <= limits["maximumNonmatchingRunWordsPerSide"],
            "maximumWordCountRatio": count_ratio <= limits["maximumWordCountRatio"],
            "stitchAnchorNearOverlapMidpoint": anchor[0]
            <= limits["maximumStitchAnchorDistanceFromOverlapMidpointMilliseconds"],
        }
        boundary_records.append(
            {
                "boundaryIndex": boundary_index,
                "leftWindowIndex": left_window["index"],
                "rightWindowIndex": right_window["index"],
                "overlapSampleRange": [overlap_start, overlap_end],
                "overlapDurationSeconds": (overlap_end - overlap_start) / sample_rate,
                "leftOverlapWordCount": left_count,
                "rightOverlapWordCount": right_count,
                "wordCountRatio": count_ratio,
                "alignment": alignment,
                "maximumLeftNonmatchingRunWords": left_run,
                "maximumRightNonmatchingRunWords": right_run,
                "stitchAnchorWord": anchor[3],
                "stitchAnchorAbsoluteMilliseconds": anchor[4],
                "stitchAnchorDistanceFromOverlapMidpointMilliseconds": anchor[0],
                "leftWindowCutEndExclusive": anchor[1] + 1,
                "rightWindowCutStartInclusive": anchor[2] + 1,
                "gates": gates,
                "passes": all(gates.values()),
            }
        )
        cuts.append(
            {
                "leftEndExclusive": anchor[1] + 1,
                "rightStartInclusive": anchor[2] + 1,
            }
        )
    stitched: list[v5.TimedWord] = []
    contribution_records: list[dict[str, Any]] = []
    for index, words in enumerate(words_by_window):
        start = 0 if index == 0 else cuts[index - 1]["rightStartInclusive"]
        end = len(words) if index == len(words_by_window) - 1 else cuts[index]["leftEndExclusive"]
        if start > end:
            raise V7Error("window stitch cuts crossed")
        contribution = list(words[start:end])
        if not contribution:
            raise V7Error("window contributed no words after stitching")
        reconciliation: dict[str, Any] | None = None
        if stitched:
            left_center = (stitched[-1].start_ms + stitched[-1].end_ms) / 2
            original = contribution[0]
            right_center = (original.start_ms + original.end_ms) / 2
            forward_ms = max(0.0, left_center - right_center)
            maximum_forward = limits[
                "maximumForwardTimestampReconciliationMilliseconds"
            ]
            within_bound = forward_ms <= maximum_forward
            if forward_ms > 0 and not within_bound:
                raise V7Error(
                    "independent decoder seam timing exceeds reconciliation bound"
                )
            reconciled = original
            if forward_ms > 0:
                reconciled = v5.TimedWord(
                    original.text,
                    original.start_ms + forward_ms,
                    original.end_ms + forward_ms,
                    original.source_token_start,
                    original.source_token_end_exclusive,
                )
                contribution[0] = reconciled
            reconciled_center = (reconciled.start_ms + reconciled.end_ms) / 2
            next_center = (
                (contribution[1].start_ms + contribution[1].end_ms) / 2
                if len(contribution) > 1
                else None
            )
            preserves_right_order = (
                next_center is None or reconciled_center <= next_center
            )
            if not preserves_right_order:
                raise V7Error(
                    "bounded seam reconciliation would reverse right-window timing"
                )
            reconciliation = {
                "method": "Only the first contributed right-window derived timestamp may move forward to the preceding retained word centre; audio, words and all interior timestamps remain unchanged",
                "required": forward_ms > 0,
                "forwardMilliseconds": forward_ms,
                "maximumPermittedMilliseconds": maximum_forward,
                "originalRightWordCenterMilliseconds": right_center,
                "reconciledRightWordCenterMilliseconds": reconciled_center,
                "precedingLeftWordCenterMilliseconds": left_center,
                "nextRightWordCenterMilliseconds": next_center,
                "preservesRightWindowWordOrder": preserves_right_order,
                "passes": within_bound and preserves_right_order,
            }
            boundary_records[index - 1]["timestampReconciliation"] = reconciliation
            boundary_records[index - 1]["gates"][
                "boundedIndependentDecoderTimestampReconciliation"
            ] = reconciliation["passes"]
            boundary_records[index - 1]["passes"] = all(
                boundary_records[index - 1]["gates"].values()
            )
        stitched.extend(contribution)
        contribution_records.append(
            {
                "windowIndex": index,
                "sourceWordRange": [start, end],
                "contributedWordCount": len(contribution),
                "timestampReconciliationFromPreviousWindow": reconciliation,
            }
        )
    centers = [(item.start_ms + item.end_ms) / 2 for item in stitched]
    monotone_centers = all(left <= right for left, right in zip(centers, centers[1:]))
    if not stitched or not monotone_centers:
        raise V7Error("stitched window transcript is empty or time-reversed")
    return stitched, {
        "method": limits["stitchMethod"],
        "boundaryRecords": boundary_records,
        "contributions": contribution_records,
        "stitchedWordCount": len(stitched),
        "monotoneWordCenters": True,
        "allBoundariesPass": all(item["passes"] for item in boundary_records),
    }


def cue_alignment_v7(
    *,
    reference_words: list[str],
    hypothesis_words: list[v5.TimedWord],
    steps: list[v5.AlignmentStep],
    cues: list[dict[str, Any]],
    cue_sample_ranges: list[dict[str, Any]],
    sample_rate: int,
    config: dict[str, Any],
) -> dict[str, Any]:
    if [item["segmentID"] for item in cue_sample_ranges] != [
        item["segmentID"] for item in cues
    ]:
        raise V7Error("cue sample ranges do not match the stress cue sequence")
    exact_ref_to_hyp: dict[int, int] = {}
    exact_hyp_to_ref: dict[int, int] = {}
    any_ref_to_hyp: dict[int, int] = {}
    for step in steps:
        if step.reference_index is not None and step.hypothesis_index is not None:
            any_ref_to_hyp[step.reference_index] = step.hypothesis_index
        if step.operation == "equal":
            assert step.reference_index is not None and step.hypothesis_index is not None
            exact_ref_to_hyp[step.reference_index] = step.hypothesis_index
            exact_hyp_to_ref[step.hypothesis_index] = step.reference_index
    limits = config["windowedASR"]["aggregateGate"]
    records: list[dict[str, Any]] = []
    for cue_index, (cue, sample_range) in enumerate(
        zip(cues, cue_sample_ranges, strict=True)
    ):
        reference_start = cue["normalizedReferenceStart"]
        reference_end = cue["normalizedReferenceEndExclusive"]
        current_hypothesis = [
            any_ref_to_hyp[index]
            for index in range(reference_start, reference_end)
            if index in any_ref_to_hyp
        ]
        if not current_hypothesis:
            raise V7Error("cue has no aligned hypothesis words")
        partition_start = 0 if cue_index == 0 else min(current_hypothesis)
        if cue_index + 1 < len(cues):
            next_start = cues[cue_index + 1]["normalizedReferenceStart"]
            next_end = cues[cue_index + 1]["normalizedReferenceEndExclusive"]
            next_hypothesis = [
                any_ref_to_hyp[index]
                for index in range(next_start, next_end)
                if index in any_ref_to_hyp
            ]
            if not next_hypothesis:
                raise V7Error("next cue has no aligned hypothesis words")
            partition_end = min(next_hypothesis)
        else:
            partition_end = len(hypothesis_words)
        if partition_start > partition_end:
            raise V7Error("cue hypothesis partition is reversed")
        reference_exact = [
            index in exact_ref_to_hyp
            for index in range(reference_start, reference_end)
        ]
        hypothesis_exact = [
            index in exact_hyp_to_ref
            and reference_start <= exact_hyp_to_ref[index] < reference_end
            for index in range(partition_start, partition_end)
        ]
        reference_coverage = sum(reference_exact) / len(reference_exact)
        hypothesis_coverage = sum(hypothesis_exact) / max(1, len(hypothesis_exact))
        first_reference = range(
            reference_start,
            min(reference_end, reference_start + limits["anchorWords"]),
        )
        last_reference = range(
            max(reference_start, reference_end - limits["anchorWords"]),
            reference_end,
        )
        first_hypothesis = [
            exact_ref_to_hyp[index]
            for index in first_reference
            if index in exact_ref_to_hyp
        ]
        last_hypothesis = [
            exact_ref_to_hyp[index]
            for index in last_reference
            if index in exact_ref_to_hyp
        ]
        actual_start_ms = (
            hypothesis_words[min(first_hypothesis)].start_ms
            if first_hypothesis
            else math.inf
        )
        actual_end_ms = (
            hypothesis_words[max(last_hypothesis)].end_ms
            if last_hypothesis
            else math.inf
        )
        expected_start_ms = sample_range["startSampleInclusive"] * 1000 / sample_rate
        expected_end_ms = sample_range["endSampleExclusive"] * 1000 / sample_rate
        start_error = actual_start_ms - expected_start_ms
        end_error = actual_end_ms - expected_end_ms
        reference_run = maximum_false_run(reference_exact)
        hypothesis_run = maximum_false_run(hypothesis_exact)
        gates = {
            "minimumExactReferenceCoverage": reference_coverage
            >= limits["minimumExactReferenceCoveragePerCue"],
            "minimumExactHypothesisCoverage": hypothesis_coverage
            >= limits["minimumExactHypothesisCoveragePerCue"],
            "maximumNonmatchingReferenceRun": reference_run
            <= limits["maximumNonmatchingReferenceRunWordsPerCue"],
            "maximumNonmatchingHypothesisRun": hypothesis_run
            <= limits["maximumNonmatchingHypothesisRunWordsPerCue"],
            "exactFirstAnchor": len(first_hypothesis)
            >= limits["minimumExactFirstAnchorWords"],
            "exactLastAnchor": len(last_hypothesis)
            >= limits["minimumExactLastAnchorWords"],
            "startBoundaryTolerance": abs(start_error)
            <= limits["boundaryToleranceMilliseconds"],
            "endBoundaryTolerance": abs(end_error)
            <= limits["boundaryToleranceMilliseconds"],
        }
        records.append(
            {
                "segmentID": cue["segmentID"],
                "referenceRange": [reference_start, reference_end],
                "hypothesisRange": [partition_start, partition_end],
                "sampleRange": [
                    sample_range["startSampleInclusive"],
                    sample_range["endSampleExclusive"],
                ],
                "exactReferenceCoverage": reference_coverage,
                "exactHypothesisCoverage": hypothesis_coverage,
                "maximumNonmatchingReferenceRunWords": reference_run,
                "maximumNonmatchingHypothesisRunWords": hypothesis_run,
                "exactFirstAnchorWords": len(first_hypothesis),
                "exactLastAnchorWords": len(last_hypothesis),
                "actualStartMilliseconds": actual_start_ms,
                "actualEndMilliseconds": actual_end_ms,
                "expectedStartMilliseconds": expected_start_ms,
                "expectedEndMilliseconds": expected_end_ms,
                "startBoundaryErrorMilliseconds": start_error,
                "endBoundaryErrorMilliseconds": end_error,
                "gates": gates,
                "passes": all(gates.values()),
            }
        )
    return {
        "method": "Complete global alignment with alignment-derived cue partitions, exact eight-word edge anchors, unchanged V6 coverage/run/timing thresholds",
        "cueRecords": records,
        "allCuesPass": all(item["passes"] for item in records),
    }


def windowed_asr_audit(
    *,
    master_path: Path,
    candidate_directory: Path,
    reference_words: list[str],
    cues: list[dict[str, Any]],
    cue_sample_ranges: list[dict[str, Any]],
    config: dict[str, Any],
) -> dict[str, Any]:
    window_directory = candidate_directory / "windows"
    windows, extraction = extract_windows(
        master_path=master_path, directory=window_directory, config=config
    )
    transcript_paths, asr_run = v6.run_whisper_batch(
        audio_paths=[item["_path"] for item in windows],
        staging=window_directory,
        config=v6.load_config(),
    )
    words_by_window: list[list[v5.TimedWord]] = []
    window_records: list[dict[str, Any]] = []
    window_gate = config["windowedASR"]["windowGate"]
    for window_record, transcript_path in zip(windows, transcript_paths, strict=True):
        document = production.load_json(transcript_path)
        duration_seconds = window_record["durationSeconds"]
        words, grouping = segment_timed_words(
            document, duration_ms=duration_seconds * 1000, config=config
        )
        absolute = _absolute_words(
            words,
            start_sample=window_record["startSampleInclusive"],
            sample_rate=extraction["sampleRate"],
        )
        words_per_minute = len(words) / (duration_seconds / 60)
        gates = {
            "nonemptyTranscript": bool(words),
            "minimumWordsPerMinute": words_per_minute
            >= window_gate["minimumWordsPerMinute"],
            "maximumWordsPerMinute": words_per_minute
            <= window_gate["maximumWordsPerMinute"],
            "lexicalParity": grouping["allLexicalParityChecksPass"],
            "boundedSegmentTiming": grouping["boundedByDecodedWindow"],
        }
        words_by_window.append(absolute)
        public_window = {key: value for key, value in window_record.items() if key != "_path"}
        window_records.append(
            {
                **public_window,
                "transcript": file_binding(transcript_path),
                "timedWordGrouping": grouping,
                "wordCount": len(words),
                "wordsPerMinute": words_per_minute,
                "gates": gates,
                "passes": all(gates.values()),
            }
        )
    hypothesis_timed, stitching = stitch_window_words(
        windows=windows,
        words_by_window=words_by_window,
        sample_rate=extraction["sampleRate"],
        config=config,
    )
    hypothesis_words = [item.text for item in hypothesis_timed]
    steps, alignment = v5.monotone_global_alignment(reference_words, hypothesis_words)
    repetition = v5.reference_aware_repetition(
        reference_words, hypothesis_words, v6.load_config()
    )
    cue_alignment = cue_alignment_v7(
        reference_words=reference_words,
        hypothesis_words=hypothesis_timed,
        steps=steps,
        cues=cues,
        cue_sample_ranges=cue_sample_ranges,
        sample_rate=v6.load_config()["master"]["nativeSampleRate"],
        config=config,
    )
    limits = config["windowedASR"]["aggregateGate"]
    ratio = len(hypothesis_words) / len(reference_words)
    aggregate_gates = {
        "minimumWordRatio": ratio
        >= limits["minimumHypothesisToReferenceWordRatio"],
        "maximumWordRatio": ratio
        <= limits["maximumHypothesisToReferenceWordRatio"],
        "maximumWordErrorRate": alignment["wordAlignmentErrorRate"]
        <= limits["maximumWordErrorRate"],
        "referenceAwareRepetition": repetition["excessOccurrenceFraction"]
        <= limits["maximumExcessRepeatedSixGramFraction"],
        "cueAlignment": cue_alignment["allCuesPass"],
    }
    return {
        "method": "Deterministic overlapping final-master windows with exact sample coverage, independent pinned Whisper decodes, overlap proof, exact-word stitching and aggregate reference audit",
        "extraction": extraction,
        "asrRun": asr_run,
        "windowRecords": window_records,
        "allWindowGatesPass": all(item["passes"] for item in window_records),
        "stitching": stitching,
        "hypothesisWordCount": len(hypothesis_words),
        "referenceWordCount": len(reference_words),
        "hypothesisToReferenceWordRatio": ratio,
        "wholeAlignment": alignment,
        "repetition": repetition,
        "cueAlignment": cue_alignment,
        "aggregateGates": aggregate_gates,
        "aggregatePasses": all(aggregate_gates.values()),
        "monolithicWhisperUsed": False,
        "answerPromptUsed": False,
        "externalTranscriptReceiptUsed": False,
    }


def _public_candidate_record(source: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in source.items() if not key.startswith("_")}


def audit_candidate(
    *,
    candidate_id: str,
    stress_set: dict[str, Any],
    reference_words: list[str],
    candidate_directory: Path,
    config: dict[str, Any],
) -> dict[str, Any]:
    source = stress_set["recordsByID"][candidate_id]
    record = source["record"]
    v6_config = v6.load_config()
    master_relation = v5.verify_native_master_relation(
        source["assemblyPath"],
        source["masterPath"],
        v6_config,
        audit_root=candidate_directory,
        confinement_root=work_root(config, create=False).parent,
    )
    duration_seconds = master_relation["master"]["durationSeconds"]
    parent = stress_set["context"]["parentRecords"][candidate_id]
    reference_audio, reference_record = v5._load_reference_audio(
        Path(parent["_verifiedReferencePath"]),
        v6_config["master"]["nativeSampleRate"],
    )
    identity = v5.audit_voice_identity(
        reference_audio=reference_audio,
        cue_audio=source["cueAudio"],
        sample_rate=v6_config["master"]["nativeSampleRate"],
        extractor=stress_set["extractor"],
        config=v6_config,
    )
    windowed = windowed_asr_audit(
        master_path=source["masterPath"],
        candidate_directory=candidate_directory,
        reference_words=reference_words,
        cues=stress_set["cues"],
        cue_sample_ranges=source["cueSampleRanges"],
        config=config,
    )
    tempo = v5.cue_tempo_audit(
        stress_set["cues"],
        source["cueSampleRanges"],
        v6_config["master"]["nativeSampleRate"],
        v6_config,
    )
    silence = v5.silence_audit(
        source["assemblyAudio"],
        sample_rate=v6_config["master"]["nativeSampleRate"],
        cue_sample_ranges=source["cueSampleRanges"],
        config=v6_config,
    )
    all_utterance_gates = all(
        item["record"]["gate"]["passes"]
        for batch in stress_set["batchCommits"]
        if batch["receipt"]["candidateID"] == candidate_id
        for item in batch["utterances"]
    )
    correction = record["durationCorrection"]
    bounded_correction = (
        1.0
        <= correction["tempoFactor"]
        <= v6_config["durationCorrection"]["maximumTempoFactor"]
        and record["pretempoAssembly"]["decodedDurationSeconds"]
        <= v6_config["durationCorrection"]["hardMaximumUncorrectedSeconds"]
    )
    seam = record["pretempoAssembly"]["seamAudit"]
    gates = {
        "allUtterancesPassedBeforeCommit": all_utterance_gates,
        "pretempoSeams": seam["passes"],
        "boundedWholeAssemblyTempoCorrection": bounded_correction,
        "decodedDuration18To22Minutes": v5.stress_duration_gate(
            duration_seconds, v6_config
        ),
        "deterministicNativeToMaster": master_relation["deterministicByteEquality"],
        "completeDecodedSampleCoverage": windowed["extraction"]
        ["decodedSampleCoverage"]["passes"],
        "allWindowGates": windowed["allWindowGatesPass"],
        "allOverlapBoundaries": windowed["stitching"]["allBoundariesPass"],
        "aggregateWindowedASR": windowed["aggregatePasses"],
        "voiceIdentity": identity["passes"],
        "cueTempo": tempo["passes"],
        "silence": silence["passes"],
    }
    result = {
        "schemaVersion": 1,
        "status": CANDIDATE_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "candidateID": candidate_id,
        "sourceV6Record": _public_candidate_record(record),
        "reference": reference_record,
        "masterRelation": master_relation,
        "decodedDurationSeconds": duration_seconds,
        "utteranceGateSummary": {
            "utteranceCount": len(stress_set["utterances"]),
            "allPassedBeforeCommit": all_utterance_gates,
        },
        "pretempoSeamAudit": seam,
        "durationCorrection": correction,
        "voiceIdentity": identity,
        "windowedASR": windowed,
        "cueTempo": tempo,
        "silence": silence,
        "gates": gates,
        "passesCompleteV7MachineGate": all(gates.values()),
        "editorVoiceSelection": False,
        "artisticApproval": False,
        "shippingApproval": False,
    }
    receipt_path = candidate_directory / "candidate-window-audit.v7.receipt.json"
    write_json(receipt_path, result)
    result["receipt"] = file_binding(receipt_path)
    return result


def audit_v7(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V7Error("V7 audit requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    dependencies = validate_dependencies(config)
    v6_config = v6.load_config()
    parent_chain = v6.validate_parent_chain(v6_config)
    negative_evidence = v6.validate_v5_negative_evidence(v6_config)
    expected_stress = repository_path(
        config["paths"]["v6R4StressSet"], directory=True
    )
    if args.stress_set.absolute() != expected_stress:
        raise V7Error("V7 audit accepts only the hash-bound V6 R4 stress set")
    output = prepare_output(args.output, config)
    stress_set = v6.validate_stress_set(
        expected_stress,
        config=v6_config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
    )
    reference_words = v5.normalize_words(stress_set["stressText"])
    candidate_records: list[dict[str, Any]] = []
    for candidate_id in EXPECTED_FINALISTS:
        candidate_directory = output / candidate_id
        candidate_directory.mkdir()
        record = audit_candidate(
            candidate_id=candidate_id,
            stress_set=stress_set,
            reference_words=reference_words,
            candidate_directory=candidate_directory,
            config=config,
        )
        candidate_records.append(record)
        print(
            f"V7 audited complete windowed master {candidate_id}: "
            f"{'PASS' if record['passesCompleteV7MachineGate'] else 'FAIL'}",
            file=sys.stderr,
            flush=True,
        )
    receipt = {
        "schemaVersion": 1,
        "status": AUDIT_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "dependencyBindings": dependencies,
        "v6R4StressReceipt": file_binding(
            repository_path(config["paths"]["v6R4StressReceipt"], directory=False)
        ),
        "v6MonolithicNegativeEvidence": config["v6MonolithicNegativeEvidence"],
        "masterConstructionContract": config["masterConstructionContract"],
        "candidateRecords": candidate_records,
        "passingCandidateIDs": [
            item["candidateID"]
            for item in candidate_records
            if item["passesCompleteV7MachineGate"]
        ],
        "bothFinalistsMustPassBeforeEditorChoice": True,
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "claimsExcluded": config["claimsExcluded"],
    }
    receipt_path = output / "audit.v7.receipt.json"
    write_json(receipt_path, receipt)
    return {**receipt, "receipt": file_binding(receipt_path)}


def _punctuation_boundaries(text: str) -> set[int]:
    boundaries: set[int] = set()
    for match in re.finditer(r"[,;:!?]|\.(?=\s|$)|[—–-]", text):
        count = len(v5.normalize_words(text[: match.start()]))
        if count:
            boundaries.add(count - 1)
    return boundaries


def _percentile(values: list[float], percentile: float) -> float | None:
    if not values:
        return None
    import numpy as np

    return float(np.percentile(values, percentile))


def silence_map_candidate(
    *,
    candidate_record: dict[str, Any],
    utterances_by_id: dict[str, dict[str, Any]],
    v6_config: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    settings = config["silenceMapping"]
    sample_rate = v6_config["master"]["nativeSampleRate"]
    frame = round(sample_rate * settings["frameMilliseconds"] / 1000)
    hop = round(sample_rate * settings["hopMilliseconds"] / 1000)
    threshold = 10 ** (settings["thresholdDBFS"] / 20)
    run_records: list[dict[str, Any]] = []
    authored_tail_samples = 0
    source_bindings: list[dict[str, Any]] = []
    for batch_binding in candidate_record["batchCommitReceipts"]:
        batch_path = Path(batch_binding["path"])
        batch = production.load_json(batch_path)
        source_bindings.append(file_binding(batch_path))
        for item in batch["utteranceRecords"]:
            utterance_id = item["utterance"]["utteranceID"]
            utterance = utterances_by_id[utterance_id]
            audio_path = Path(item["processedAudio"]["file"]["path"])
            transcript_path = Path(item["transcript"]["file"]["path"])
            validate_exact_file(
                audio_path,
                byte_count=item["processedAudio"]["file"]["bytes"],
                digest=item["processedAudio"]["file"]["sha256"],
                label=f"{candidate_record['candidateID']} {utterance_id} processed audio",
            )
            validate_exact_file(
                transcript_path,
                byte_count=item["transcript"]["file"]["bytes"],
                digest=item["transcript"]["file"]["sha256"],
                label=f"{candidate_record['candidateID']} {utterance_id} transcript",
            )
            audio, decoded = v5.read_native_audio(audio_path, v6_config)
            sample_count = len(audio)
            squared = audio.astype(np.float64) ** 2
            cumulative = np.concatenate(([0.0], np.cumsum(squared)))
            starts = np.arange(0, sample_count - frame + 1, hop, dtype=np.int64)
            rms = np.sqrt(
                (cumulative[starts + frame] - cumulative[starts]) / frame + 1e-15
            )
            silent = rms < threshold
            processing = item["processing"]
            adaptive_samples = processing["adaptiveSemanticPacing"][
                "additionalPauseSamples"
            ]
            terminal_samples = processing["pauseSamples"] + adaptive_samples
            terminal_start = sample_count - terminal_samples
            authored_tail_samples += terminal_samples
            transcript = production.load_json(transcript_path)
            timed_words, grouping = v5.timed_words_from_whisper(
                transcript, master_duration_ms=sample_count * 1000 / sample_rate
            )
            reference_words = v5.normalize_words(utterance["text"])
            hypothesis_words = [item.text for item in timed_words]
            alignment_steps, alignment = v5.monotone_global_alignment(
                reference_words, hypothesis_words
            )
            hypothesis_to_reference = {
                step.hypothesis_index: step.reference_index
                for step in alignment_steps
                if step.hypothesis_index is not None
                and step.reference_index is not None
            }
            punctuation = _punctuation_boundaries(utterance["text"])
            run_index = 0
            frame_index = 0
            while frame_index < len(starts):
                if not silent[frame_index]:
                    frame_index += 1
                    continue
                final_index = frame_index
                while final_index + 1 < len(starts) and silent[final_index + 1]:
                    final_index += 1
                start_sample = int(starts[frame_index])
                end_sample = int(starts[final_index] + frame)
                frame_index = final_index + 1
                if start_sample >= terminal_start - frame:
                    classification = "authored-or-adaptive-terminal-pause"
                elif start_sample == 0:
                    classification = "leading-retained-roll"
                elif end_sample >= terminal_start:
                    classification = "post-speech-retained-roll"
                else:
                    classification = "internal-low-energy"
                start_ms = start_sample * 1000 / sample_rate
                end_ms = end_sample * 1000 / sample_rate
                left_index = max(
                    (
                        index
                        for index, word in enumerate(timed_words)
                        if word.end_ms <= start_ms + settings["frameMilliseconds"]
                    ),
                    default=None,
                )
                right_index = min(
                    (
                        index
                        for index, word in enumerate(timed_words)
                        if word.start_ms >= end_ms - settings["frameMilliseconds"]
                    ),
                    default=None,
                )
                between_words = (
                    left_index is not None
                    and right_index is not None
                    and left_index < right_index
                )
                reference_left = (
                    hypothesis_to_reference.get(left_index)
                    if left_index is not None
                    else None
                )
                after_punctuation = bool(
                    between_words and reference_left in punctuation
                )
                peak = float(np.max(np.abs(audio[start_sample:end_sample])))
                run_records.append(
                    {
                        "candidateID": candidate_record["candidateID"],
                        "utteranceID": utterance_id,
                        "runIndexWithinUtterance": run_index,
                        "sampleRange": [start_sample, end_sample],
                        "startMilliseconds": start_ms,
                        "endMilliseconds": end_ms,
                        "durationMilliseconds": (end_sample - start_sample)
                        * 1000
                        / sample_rate,
                        "classification": classification,
                        "betweenTranscriptWords": between_words,
                        "afterSourcePunctuation": after_punctuation,
                        "leftWord": (
                            timed_words[left_index].text
                            if left_index is not None
                            else None
                        ),
                        "rightWord": (
                            timed_words[right_index].text
                            if right_index is not None
                            else None
                        ),
                        "peakAbsolute": peak,
                        "audio": decoded["file"],
                        "transcript": file_binding(transcript_path),
                        "transcriptAlignmentSHA256": alignment["alignmentSHA256"],
                        "timedWordGroupingBounded": grouping["boundedByDecodedMaster"],
                    }
                )
                run_index += 1
    internal = [
        item for item in run_records if item["classification"] == "internal-low-energy"
    ]
    between = [item for item in internal if item["betweenTranscriptWords"]]
    punctuation = [item for item in between if item["afterSourcePunctuation"]]
    nonpunctuation = [item for item in between if not item["afterSourcePunctuation"]]
    durations = [item["durationMilliseconds"] for item in internal]
    counterfactual = []
    for cap in [250, 280, 300, 320, 350, 400, 450, 500]:
        counterfactual.append(
            {
                "retainedCapMilliseconds": cap,
                "nonPunctuationOnlyRemovalSeconds": sum(
                    max(0.0, item["durationMilliseconds"] - cap)
                    for item in nonpunctuation
                )
                / 1000,
                "allBetweenWordRemovalSeconds": sum(
                    max(0.0, item["durationMilliseconds"] - cap)
                    for item in between
                )
                / 1000,
                "transformAuthorized": False,
            }
        )
    return {
        "candidateID": candidate_record["candidateID"],
        "batchReceiptBindings": source_bindings,
        "runCount": len(run_records),
        "internalRunCount": len(internal),
        "internalTotalSeconds": sum(durations) / 1000,
        "authoredAndAdaptiveTerminalPauseSeconds": authored_tail_samples
        / sample_rate,
        "internalDurationDistributionMilliseconds": {
            "minimum": min(durations),
            "median": _percentile(durations, 50),
            "p90": _percentile(durations, 90),
            "p95": _percentile(durations, 95),
            "p99": _percentile(durations, 99),
            "maximum": max(durations),
        },
        "betweenWordRunCount": len(between),
        "punctuationRunCount": len(punctuation),
        "nonPunctuationRunCount": len(nonpunctuation),
        "counterfactualOnly": counterfactual,
        "runRecords": run_records,
        "removalAuthorized": False,
    }


def silence_map_v7(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V7Error("V7 silence mapping requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    output = prepare_output(args.output, config)
    dependencies = validate_dependencies(config)
    receipt = _validate_shallow_stress_receipt(config)
    v6_config = v6.load_config()
    _, stress_record, cues, utterances, utterance_record = (
        v6.stress_and_utterance_material(v6_config)
    )
    utterances_by_id = {item["utteranceID"]: item for item in utterances}
    candidate_records = [
        silence_map_candidate(
            candidate_record=candidate,
            utterances_by_id=utterances_by_id,
            v6_config=v6_config,
            config=config,
        )
        for candidate in receipt["records"]
    ]
    result = {
        "schemaVersion": 1,
        "status": SILENCE_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "dependencyBindings": dependencies,
        "stressReceipt": file_binding(Path(receipt["_path"])),
        "stressText": stress_record,
        "cueCount": len(cues),
        "utteranceManifest": utterance_record,
        "settings": config["silenceMapping"],
        "candidateRecords": candidate_records,
        "finding": "This receipt maps low-energy intervals and counterfactual cap totals. It does not establish that any internal interval is synthetic and authorises no removal.",
        "audioChanged": False,
        "speechTimeStretchApplied": False,
        "removalAuthorized": False,
        "editorVoiceSelection": False,
        "artisticApproval": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "claimsExcluded": config["claimsExcluded"],
    }
    receipt_path = output / "silence-map.v7.receipt.json"
    write_json(receipt_path, result)
    return {**result, "receipt": file_binding(receipt_path)}


def validate_only(config: dict[str, Any], *, offline: bool) -> dict[str, Any]:
    if offline is not True:
        raise V7Error("V7 validation requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    receipt = _validate_shallow_stress_receipt(config)
    return {
        "schemaVersion": 1,
        "status": METHOD_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "pipelineBinding": pipeline_binding(config),
        "stressReceipt": file_binding(Path(receipt["_path"])),
        "masterConstructionContract": config["masterConstructionContract"],
        "windowedASR": config["windowedASR"],
        "silenceMapping": config["silenceMapping"],
        "chatterboxComparisonRuntime": config["chatterboxComparisonRuntime"],
        "generationExecuted": False,
        "audioChanged": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Frozen offline V7 windowed narration audit and silence map"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--offline", action="store_true", required=True)
    audit = subparsers.add_parser("audit")
    audit.add_argument("--stress-set", type=Path, required=True)
    audit.add_argument("--output", type=Path, required=True)
    audit.add_argument("--offline", action="store_true", required=True)
    silence = subparsers.add_parser("silence-map")
    silence.add_argument("--output", type=Path, required=True)
    silence.add_argument("--offline", action="store_true", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        config = load_config()
        if args.command == "validate":
            result = validate_only(config, offline=args.offline)
        elif args.command == "audit":
            result = audit_v7(args, config)
        elif args.command == "silence-map":
            result = silence_map_v7(args, config)
        else:
            raise V7Error(f"unsupported V7 command: {args.command}")
    except (V7Error, v6.V6Error, v5.V5Error, production.PipelineError) as error:
        print(f"V7 narration error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
