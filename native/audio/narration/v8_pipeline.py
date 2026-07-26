#!/usr/bin/env python3
"""Frozen offline V8 narration remediation method.

V8 authorises no repair of the V6 R4 masters.  It defines a new, exact text
segmentation and resynthesis gate for both finalists, plus a 30/15-second
window audit that keeps every V7 lexical, cue and boundary threshold.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from typing import Any

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v7_pipeline as v7


SCRIPT_PATH = Path(__file__).absolute()
CONFIG_PATH = SCRIPT_PATH.with_name("v8-method-config.json")
REPOSITORY_ROOT = SCRIPT_PATH.parents[3]
EXPECTED_CONFIG_BYTES = 7879
EXPECTED_CONFIG_SHA256 = "43c436765f5d82ed8a9175e57c1c41bc66e0b6d5c51bb4e90ee4a2661997d4fc"

METHOD_STATUS = "CODEX_V8_RESYNTHESIS_AND_SHORT_WINDOW_METHOD_FROZEN"
TRUST_DOMAIN = "CODEX_V8_DIAGNOSTIC_NON_SHIPPING"
DECODER_PROOF_STATUS = "CODEX_V8_C06_30S_15S_OVERLAP_DECODER_PROOF_NON_SHIPPING"
EXPECTED_FINALISTS = ["voice-candidate-05", "voice-candidate-06"]


class V8Error(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def file_binding(path: Path) -> dict[str, Any]:
    return v7.file_binding(path)


def write_json(path: Path, value: Any) -> None:
    v7.write_json(path, value)


def repository_path(relative: str, *, directory: bool | None = None) -> Path:
    return v7.repository_path(relative, directory=directory)


def validate_exact_file(
    path: Path, *, byte_count: int, digest: str, label: str
) -> None:
    v7.validate_exact_file(
        path, byte_count=byte_count, digest=digest, label=label
    )


def _semantic_atoms(text: str, cues: list[dict[str, Any]]) -> list[dict[str, Any]]:
    atoms: list[dict[str, Any]] = []
    cursor = 0
    for match in re.finditer(r".*?(?:\n\n|\Z)", text, flags=re.S):
        block = match.group(0)
        if not block:
            continue
        paragraph_separator = "\n\n" if block.endswith("\n\n") else ""
        paragraph = block[:-2] if paragraph_separator else block
        date_heading = bool(
            re.match(r"^(?:c\.\s+)?(?:AD\s+\d+|\d+\s+BC)\.\s+\S", paragraph)
        )
        chunks: list[str] = []
        if date_heading:
            chunks.append(paragraph + paragraph_separator)
        else:
            start = 0
            boundaries = list(re.finditer(r"(?<=[.!?])(?=\s+\S)", paragraph))
            for index, boundary in enumerate([*boundaries, None]):
                end = boundary.start() if boundary is not None else len(paragraph)
                whitespace = re.match(r"\s+", paragraph[end:])
                separator = whitespace.group(0) if whitespace else ""
                if index == len(boundaries):
                    separator += paragraph_separator
                chunks.append(paragraph[start:end] + separator)
                start = end + len(whitespace.group(0) if whitespace else "")
        for chunk in chunks:
            material = chunk.rstrip()
            separator = chunk[len(material) :]
            start = cursor
            end = start + len(material)
            cue = next(
                (
                    cue
                    for cue in cues
                    if cue["sourceCharacterStartInclusive"]
                    <= start
                    <= cue["sourceCharacterEndExclusive"]
                ),
                None,
            )
            if cue is None:
                raise V8Error("semantic atom escaped the approved cue ranges")
            atoms.append(
                {
                    "sourceCharacterStartInclusive": start,
                    "sourceCharacterEndExclusive": end,
                    "chunk": chunk,
                    "text": material,
                    "separatorAfter": separator,
                    "normalizedWordCount": len(v5.normalize_words(material)),
                    "segmentID": cue["segmentID"],
                }
            )
            cursor += len(chunk)
    if cursor != len(text) or "".join(item["chunk"] for item in atoms) != text:
        raise V8Error("semantic atoms do not preserve every approved character")
    return atoms


def segmentation_material() -> tuple[str, dict[str, Any], list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    text, stress_record, cues, _, _ = v6.stress_and_utterance_material(
        v6.load_config()
    )
    atoms = _semantic_atoms(text, cues)
    minimum = 9
    maximum = 36
    groups: list[list[dict[str, Any]]] = []
    for cue in cues:
        own = [item for item in atoms if item["segmentID"] == cue["segmentID"]]
        index = 0
        local: list[list[dict[str, Any]]] = []
        while index < len(own):
            group = [own[index]]
            word_count = own[index]["normalizedWordCount"]
            index += 1
            if word_count < minimum:
                while index < len(own) and word_count < minimum:
                    group.append(own[index])
                    word_count += own[index]["normalizedWordCount"]
                    index += 1
            local.append(group)
        if len(local) > 1:
            final_words = sum(
                item["normalizedWordCount"] for item in local[-1]
            )
            merged_words = final_words + sum(
                item["normalizedWordCount"] for item in local[-2]
            )
            if final_words < minimum and merged_words <= maximum:
                local[-2].extend(local.pop())
        groups.extend(local)

    utterances: list[dict[str, Any]] = []
    public_manifest: list[dict[str, Any]] = []
    for index, group in enumerate(groups):
        chunk = "".join(item["chunk"] for item in group)
        material = chunk.rstrip()
        separator = chunk[len(material) :]
        word_count = len(v5.normalize_words(material))
        utterance = {
            "utteranceID": f"v8-utterance-{index:03d}",
            "order": index + 1,
            "segmentID": group[0]["segmentID"],
            "sourceCharacterStartInclusive": group[0][
                "sourceCharacterStartInclusive"
            ],
            "sourceCharacterEndExclusive": group[-1][
                "sourceCharacterEndExclusive"
            ],
            "separatorAfter": separator,
            "text": material,
            "textSHA256": hashlib.sha256(material.encode("utf-8")).hexdigest(),
            "wordCount": len(material.split()),
            "normalizedWordCount": word_count,
            "semanticAtomCount": len(group),
        }
        utterances.append(utterance)
        public_manifest.append(
            {key: value for key, value in utterance.items() if key != "text"}
        )
    if "".join(item["text"] + item["separatorAfter"] for item in utterances) != text:
        raise V8Error("V8 utterances changed the approved character stream")
    if any(
        item["segmentID"] != following["segmentID"]
        and item["sourceCharacterEndExclusive"]
        > next(
            cue["sourceCharacterEndExclusive"]
            for cue in cues
            if cue["segmentID"] == item["segmentID"]
        )
        for item, following in zip(utterances, utterances[1:])
    ):
        raise V8Error("V8 segmentation crossed a cue")
    counts = [item["normalizedWordCount"] for item in utterances]
    if min(counts) < minimum or max(counts) > maximum:
        raise V8Error("V8 segmentation escaped its frozen word bounds")
    manifest_hash = hashlib.sha256(canonical_json(public_manifest).encode()).hexdigest()
    record = {
        "algorithmVersion": 2,
        "utteranceCount": len(utterances),
        "minimumNormalizedWords": min(counts),
        "maximumNormalizedWords": max(counts),
        "exactCharacterPartition": True,
        "crossCuePacking": False,
        "manifestSHA256": manifest_hash,
        "manifest": public_manifest,
    }
    return text, stress_record, cues, utterances, record


def validate_config_document(config: dict[str, Any]) -> None:
    if (
        config.get("schemaVersion") != 1
        or config.get("status") != METHOD_STATUS
        or config.get("trustDomain") != TRUST_DOMAIN
        or config.get("language") != "English"
        or config.get("locale") != "en-GB"
    ):
        raise V8Error("V8 method identity drifted")
    remediation = config.get("remediationContract", {})
    required_true = [
        "resynthesiseEveryApprovedCharacterForBothCandidates",
        "v6R4AudioReuseAsV8MasterParentProhibited",
        "exactApprovedCharacterPartitionRequired",
        "wordOrCharacterChangeProhibited",
        "internalSilenceRemovalProhibited",
        "masterOrUtteranceSilenceTrimmingProhibited",
        "durationPaddingProhibited",
        "adaptiveZeroPaddingProhibited",
        "speechTimeStretchProhibited",
        "wholeAssemblyTempoCorrectionProhibited",
        "activityCropOnlyAtRawOuterEdgesWithInheritedRolls",
        "audibleSeamsProhibited",
    ]
    if remediation.get("candidateIDs") != EXPECTED_FINALISTS or any(
        remediation.get(key) is not True for key in required_true
    ):
        raise V8Error("V8 resynthesis/remediation contract drifted")
    segmentation = config.get("segmentation", {})
    if (
        segmentation.get("algorithmVersion") != 2
        or segmentation.get("minimumNormalizedWordsPerUtterance") != 9
        or segmentation.get("maximumNormalizedWordsPerUtterance") != 36
        or segmentation.get("utteranceCount") != 203
        or segmentation.get("exactCharacterPartitionRequired") is not True
        or segmentation.get("crossCuePackingProhibited") is not True
        or segmentation.get("authoredSeparatorsPreservedByteForByte") is not True
    ):
        raise V8Error("V8 segmentation contract drifted")
    lab = config.get("pauseDensityLab", {})
    if (
        lab.get("referenceTempoFactors") != [1.22, 1.26, 1.3, 1.34]
        or lab.get("minimumReferenceIdentityCosine") != 0.98
        or lab.get("minimumUtteranceIdentityCosine") != 0.98
        or lab.get("allInheritedV6UtteranceGatesMustPass") is not True
        or lab.get("maximumAggregateWordErrorRate") != 0.03
        or lab.get("maximumModelRetainedSilenceFraction") != 0.1
        or lab.get("maximumRepresentativeMontageSilenceFraction") != 0.115
        or lab.get("labAudioPermittedAsMasterParent") is not False
        or lab.get("fullGenerationMustRebuildConditionedReferences") is not True
        or lab.get("fullGenerationMustUseNewSeeds") is not True
    ):
        raise V8Error("V8 pause-density lab contract drifted")
    audit = config.get("finalAudit", {})
    expected_audit = {
        "windowSeconds": 30,
        "overlapSeconds": 15,
        "strideSeconds": 15,
        "maximumSegmentTailOverrunMilliseconds": 100,
        "decodedSampleCoverageRequired": 1.0,
        "gapsPermitted": False,
        "minimumExactSharedWords": 18,
        "maximumWordAlignmentErrorRate": 0.35,
        "maximumNonmatchingRunWordsPerSide": 14,
        "maximumWordCountRatio": 1.55,
        "maximumStitchAnchorDistanceFromOverlapMidpointMilliseconds": 750,
        "maximumForwardTimestampReconciliationMilliseconds": 750,
        "maximumReconciledPrefixWords": 2,
        "minimumHypothesisToReferenceWordRatio": 0.97,
        "maximumHypothesisToReferenceWordRatio": 1.03,
        "maximumWordErrorRate": 0.03,
        "maximumExcessRepeatedSixGramFraction": 0.005,
        "minimumExactReferenceCoveragePerCue": 0.98,
        "minimumExactHypothesisCoveragePerCue": 0.98,
        "maximumNonmatchingReferenceRunWordsPerCue": 6,
        "maximumNonmatchingHypothesisRunWordsPerCue": 12,
        "anchorWords": 8,
        "boundaryToleranceMilliseconds": 750,
        "maximumTotalSilenceFraction": 0.12,
        "minimumDurationSeconds": 1080,
        "maximumDurationSeconds": 1320,
        "allV7IdentityTempoSeamAndDeterministicMasterGatesInherited": True,
        "allBoundariesMustPass": True,
        "allCuesMustPass": True,
    }
    if audit != expected_audit:
        raise V8Error("V8 final audit changed a frozen gate")
    promotion = config.get("promotionContract", {})
    if (
        promotion.get("bothCompleteNewMastersMustPassSameFinalGate") is not True
        or promotion.get("singlePassingCandidateCannotOpenEditorChoice") is not True
        or promotion.get("labPassCannotPromoteCandidate") is not True
        or promotion.get("parentAuditOrSpikeCannotPromoteCandidate") is not True
        or promotion.get("editorVoiceSelection") is not False
        or promotion.get("shippingApproval") is not False
    ):
        raise V8Error("V8 promotion contract drifted")
    if config.get("costPolicy") != {
        "offlineRequired": True,
        "networkProhibited": True,
        "paidAPIProhibited": True,
        "incrementalCostNOK": 0,
    }:
        raise V8Error("V8 zero-cost offline contract drifted")


def load_config(path: Path = CONFIG_PATH) -> dict[str, Any]:
    if path.absolute() != CONFIG_PATH:
        raise V8Error("V8 config path is frozen")
    validate_exact_file(
        path,
        byte_count=EXPECTED_CONFIG_BYTES,
        digest=EXPECTED_CONFIG_SHA256,
        label="V8 method config",
    )
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise V8Error(f"cannot read V8 method config: {error}") from error
    validate_config_document(config)
    _, _, _, _, segmentation = segmentation_material()
    expected = config["segmentation"]
    if (
        segmentation["utteranceCount"] != expected["utteranceCount"]
        or segmentation["minimumNormalizedWords"]
        != expected["minimumNormalizedWordsPerUtterance"]
        or segmentation["maximumNormalizedWords"]
        != expected["maximumNormalizedWordsPerUtterance"]
        or segmentation["manifestSHA256"] != expected["utteranceManifestSHA256"]
    ):
        raise V8Error("V8 derived utterance manifest drifted")
    ids = {item["utteranceID"] for item in segmentation["manifest"]}
    representatives = config["pauseDensityLab"]["representativeUtteranceIDs"]
    if len(set(representatives)) != len(representatives) or not set(
        representatives
    ).issubset(ids):
        raise V8Error("V8 pause lab representative set drifted")
    config["_path"] = str(path)
    return config


def validate_dependencies(config: dict[str, Any]) -> dict[str, Any]:
    bindings: dict[str, Any] = {}
    parent = config["parentEvidence"]
    fixed = [
        ("v6Pipeline", "native/audio/narration/v6_pipeline.py"),
        ("v6Config", "native/audio/narration/v6-audit-config.json"),
        ("v7Pipeline", "native/audio/narration/v7_pipeline.py"),
        ("v7Config", "native/audio/narration/v7-audit-config.json"),
        ("v6R4StressReceipt", config["paths"]["v6R4StressReceipt"]),
        ("v7FullAuditReceipt", config["paths"]["v7FullAuditReceipt"]),
        (
            "c05SilenceAttributionReceipt",
            config["paths"]["c05SilenceAttributionReceipt"],
        ),
        ("c06ShortWindowSpikeReceipt", config["paths"]["c06ShortWindowSpikeReceipt"]),
    ]
    for label, relative in fixed:
        path = repository_path(relative, directory=False)
        expected = parent[label]
        validate_exact_file(
            path,
            byte_count=expected["bytes"],
            digest=expected["sha256"],
            label=f"V8 {label}",
        )
        bindings[label] = file_binding(path)
    v7_dependencies = v7.validate_dependencies(v7.load_config())
    bindings["v7ValidatedDependencies"] = v7_dependencies
    full = production.load_json(Path(bindings["v7FullAuditReceipt"]["path"]))
    c05 = production.load_json(
        Path(bindings["c05SilenceAttributionReceipt"]["path"])
    )
    c06 = production.load_json(Path(bindings["c06ShortWindowSpikeReceipt"]["path"]))
    findings = config["findingContract"]
    c05_top = c05["topLevelAttribution"]["modelRetainedAudio"]
    if (
        full.get("passingCandidateIDs") != []
        or c05["reproduction"]["totalSilenceFraction"]
        != findings["c05FrozenSilenceFraction"]
        or c05_top["silentFrameCount"]
        != findings["c05ModelRetainedSilentFrameCount"]
        or c05_top["fractionOfAllSilentFrames"]
        != findings["c05ModelRetainedFractionOfSilentFrames"]
        or c05["gateImplication"]["explicitBoundaryRemovalWouldPass"] is not False
        or c05["gateImplication"]
        ["minimumLowEnergyReductionSecondsIfRemovedTimeAlsoContractsMaster"]
        != findings["c05MinimumLowEnergyReductionSecondsIfDurationContracts"]
        or c06["shortWindowAudit"]["referenceWordCount"]
        != findings["c06ThirtySecondSpikeReferenceWordCount"]
        or c06["shortWindowAudit"]["hypothesisWordCount"]
        != findings["c06ThirtySecondSpikeHypothesisWordCount"]
        or c06["shortWindowAudit"]["wholeAlignment"]["wordAlignmentErrorRate"]
        != findings["c06ThirtySecondSpikeWordErrorRate"]
        or c06["shortWindowAudit"]["repetition"]["excessOccurrenceFraction"]
        != findings["c06ThirtySecondSpikeExcessRepetitionFraction"]
        or c06["shortWindowAudit"]["aggregatePasses"] is not True
    ):
        raise V8Error("V8 parent findings drifted")
    return bindings


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
        raise V8Error("V8 output must be one direct child of its work root")
    if target.exists() and any(target.iterdir()):
        raise V8Error("V8 output must be absent or empty")
    target.mkdir(parents=True, exist_ok=True)
    return target


def _v8_audit_config(config: dict[str, Any]) -> dict[str, Any]:
    changed = copy.deepcopy(v7.load_config())
    audit = config["finalAudit"]
    windowed = changed["windowedASR"]
    windowed["windowSeconds"] = audit["windowSeconds"]
    windowed["overlapSeconds"] = audit["overlapSeconds"]
    windowed["strideSeconds"] = audit["strideSeconds"]
    windowed["grid"] = (
        "V8 exact grid: 30-second PCM windows, 15-second overlap and stride, "
        "starting at sample zero and covering the final decoded sample"
    )
    windowed["segmentTextTimingFallback"][
        "maximumSegmentTailOverrunMilliseconds"
    ] = audit["maximumSegmentTailOverrunMilliseconds"]
    boundary = windowed["boundaryGate"]
    for key in [
        "minimumExactSharedWords",
        "maximumWordAlignmentErrorRate",
        "maximumNonmatchingRunWordsPerSide",
        "maximumWordCountRatio",
        "maximumStitchAnchorDistanceFromOverlapMidpointMilliseconds",
        "maximumForwardTimestampReconciliationMilliseconds",
        "maximumReconciledPrefixWords",
    ]:
        boundary[key] = audit[key]
    aggregate = windowed["aggregateGate"]
    for key in [
        "minimumHypothesisToReferenceWordRatio",
        "maximumHypothesisToReferenceWordRatio",
        "maximumWordErrorRate",
        "maximumExcessRepeatedSixGramFraction",
        "minimumExactReferenceCoveragePerCue",
        "minimumExactHypothesisCoveragePerCue",
        "maximumNonmatchingReferenceRunWordsPerCue",
        "maximumNonmatchingHypothesisRunWordsPerCue",
        "anchorWords",
        "boundaryToleranceMilliseconds",
    ]:
        aggregate[key] = audit[key]
    return changed


def stitch_window_words_v8(
    *,
    windows: list[dict[str, Any]],
    words_by_window: list[list[v5.TimedWord]],
    sample_rate: int,
    config: dict[str, Any],
) -> tuple[list[v5.TimedWord], dict[str, Any]]:
    """V7 lexical stitching plus bounded seam-prefix timestamp reconciliation."""

    limits = config["windowedASR"]["boundaryGate"]
    cuts: list[dict[str, int]] = []
    boundary_records: list[dict[str, Any]] = []
    for boundary_index, (left_window, right_window) in enumerate(
        zip(windows, windows[1:])
    ):
        overlap_start = right_window["startSampleInclusive"]
        overlap_end = left_window["endSampleExclusive"]
        if overlap_start >= overlap_end:
            raise V8Error("adjacent V8 ASR windows do not overlap")
        left_overlap = [
            (index, word)
            for index, word in enumerate(words_by_window[boundary_index])
            if overlap_start <= v7._word_mid_sample(word, sample_rate) < overlap_end
        ]
        right_overlap = [
            (index, word)
            for index, word in enumerate(words_by_window[boundary_index + 1])
            if overlap_start <= v7._word_mid_sample(word, sample_rate) < overlap_end
        ]
        if not left_overlap or not right_overlap:
            raise V8Error("V8 overlap contains no words on one side")
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
            assert step.reference_index is not None
            assert step.hypothesis_index is not None
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
            raise V8Error("V8 overlap has no exact shared stitch word")
        anchor = min(anchors, key=lambda item: (item[0], item[1], item[2]))
        left_count = len(left_overlap)
        right_count = len(right_overlap)
        count_ratio = max(left_count, right_count) / min(left_count, right_count)
        left_run = v7.maximum_false_run(exact_left)
        right_run = v7.maximum_false_run(exact_right)
        gates = {
            "minimumExactSharedWords": alignment["equal"]
            >= limits["minimumExactSharedWords"],
            "maximumWordAlignmentErrorRate": alignment["wordAlignmentErrorRate"]
            <= limits["maximumWordAlignmentErrorRate"],
            "maximumLeftNonmatchingRun": left_run
            <= limits["maximumNonmatchingRunWordsPerSide"],
            "maximumRightNonmatchingRun": right_run
            <= limits["maximumNonmatchingRunWordsPerSide"],
            "maximumWordCountRatio": count_ratio
            <= limits["maximumWordCountRatio"],
            "stitchAnchorNearOverlapMidpoint": anchor[0]
            <= limits[
                "maximumStitchAnchorDistanceFromOverlapMidpointMilliseconds"
            ],
        }
        boundary_records.append(
            {
                "boundaryIndex": boundary_index,
                "leftWindowIndex": left_window["index"],
                "rightWindowIndex": right_window["index"],
                "overlapSampleRange": [overlap_start, overlap_end],
                "overlapDurationSeconds": (overlap_end - overlap_start)
                / sample_rate,
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
    epsilon_ms = 1e-6
    for index, words in enumerate(words_by_window):
        start = 0 if index == 0 else cuts[index - 1]["rightStartInclusive"]
        end = (
            len(words)
            if index == len(words_by_window) - 1
            else cuts[index]["leftEndExclusive"]
        )
        if start > end:
            raise V8Error("V8 window stitch cuts crossed")
        contribution = list(words[start:end])
        if not contribution:
            raise V8Error("V8 window contributed no words after stitching")
        reconciliation: dict[str, Any] | None = None
        if stitched:
            preceding_center = (stitched[-1].start_ms + stitched[-1].end_ms) / 2
            adjustments: list[dict[str, Any]] = []
            for word_index, original in enumerate(contribution):
                center = (original.start_ms + original.end_ms) / 2
                if center + epsilon_ms >= preceding_center:
                    break
                if len(adjustments) >= limits["maximumReconciledPrefixWords"]:
                    raise V8Error(
                        "V8 seam requires more than the bounded prefix reconciliation"
                    )
                forward_ms = preceding_center - center
                if (
                    forward_ms
                    > limits["maximumForwardTimestampReconciliationMilliseconds"]
                ):
                    raise V8Error(
                        "V8 seam timing exceeds the reconciliation bound"
                    )
                shifted = v5.TimedWord(
                    original.text,
                    original.start_ms + forward_ms,
                    original.end_ms + forward_ms,
                    original.source_token_start,
                    original.source_token_end_exclusive,
                )
                contribution[word_index] = shifted
                adjustments.append(
                    {
                        "contributionWordIndex": word_index,
                        "word": original.text,
                        "originalCenterMilliseconds": center,
                        "reconciledCenterMilliseconds": (
                            shifted.start_ms + shifted.end_ms
                        )
                        / 2,
                        "forwardMilliseconds": forward_ms,
                    }
                )
            reconciliation = {
                "method": (
                    "Clamp only the shortest contributed right-window prefix "
                    "whose independent segment centres precede the retained left "
                    "centre; preserve words, audio and every later timestamp"
                ),
                "required": bool(adjustments),
                "maximumPrefixWords": limits["maximumReconciledPrefixWords"],
                "adjustedPrefixWordCount": len(adjustments),
                "maximumPermittedForwardMilliseconds": limits[
                    "maximumForwardTimestampReconciliationMilliseconds"
                ],
                "adjustments": adjustments,
                "audioChanged": False,
                "wordsChanged": False,
                "passes": True,
            }
            boundary_records[index - 1]["timestampReconciliation"] = reconciliation
            boundary_records[index - 1]["gates"][
                "boundedIndependentDecoderTimestampReconciliation"
            ] = True
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
    monotone = all(
        left <= right + epsilon_ms for left, right in zip(centers, centers[1:])
    )
    if not stitched or not monotone:
        raise V8Error("V8 stitched transcript is empty or time-reversed")
    return stitched, {
        "method": (
            "Unchanged V7 exact-word overlap stitching with a maximum two-word, "
            "750 ms derived timestamp-only seam-prefix reconciliation"
        ),
        "boundaryRecords": boundary_records,
        "contributions": contribution_records,
        "stitchedWordCount": len(stitched),
        "monotoneWordCentersWithinMicrosecondTolerance": True,
        "allBoundariesPass": all(item["passes"] for item in boundary_records),
    }


def windowed_asr_audit_v8(
    *,
    master_path: Path,
    candidate_directory: Path,
    reference_words: list[str],
    cues: list[dict[str, Any]],
    cue_sample_ranges: list[dict[str, Any]],
    config: dict[str, Any],
) -> dict[str, Any]:
    window_directory = candidate_directory / "windows"
    windows, extraction = v7.extract_windows(
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
        words, grouping = v7.segment_timed_words(
            document, duration_ms=duration_seconds * 1000, config=config
        )
        absolute = v7._absolute_words(
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
        public_window = {
            key: value for key, value in window_record.items() if key != "_path"
        }
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
    hypothesis_timed, stitching = stitch_window_words_v8(
        windows=windows,
        words_by_window=words_by_window,
        sample_rate=extraction["sampleRate"],
        config=config,
    )
    hypothesis_words = [item.text for item in hypothesis_timed]
    steps, alignment = v5.monotone_global_alignment(
        reference_words, hypothesis_words
    )
    repetition = v5.reference_aware_repetition(
        reference_words, hypothesis_words, v6.load_config()
    )
    cue_alignment = v7.cue_alignment_v7(
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
        "method": (
            "Deterministic 30-second final-master windows with 15-second "
            "overlap, exact PCM coverage, independent pinned Whisper decodes, "
            "unchanged lexical gates and bounded seam-prefix timestamp metadata"
        ),
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


def validate_method(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V8Error("V8 validation requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    dependencies = validate_dependencies(config)
    _, stress_record, cues, _, segmentation = segmentation_material()
    return {
        "schemaVersion": 1,
        "status": METHOD_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "pipelineBinding": {
            "script": file_binding(SCRIPT_PATH),
            "config": file_binding(Path(config["_path"])),
        },
        "dependencies": dependencies,
        "stressText": stress_record,
        "cueCount": len(cues),
        "segmentation": segmentation,
        "remediationContract": config["remediationContract"],
        "pauseDensityLab": config["pauseDensityLab"],
        "finalAudit": config["finalAudit"],
        "promotionContract": config["promotionContract"],
        "generationExecuted": False,
        "candidatePromoted": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }


def decoder_proof(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V8Error("V8 decoder proof requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    output = prepare_output(args.output, config)
    dependencies = validate_dependencies(config)
    stress = v7._validate_shallow_stress_receipt(v7.load_config())
    text, stress_record, cues, _, _ = v6.stress_and_utterance_material(
        v6.load_config()
    )
    candidate = next(
        item for item in stress["records"]
        if item["candidateID"] == "voice-candidate-06"
    )
    master_path = Path(candidate["master"]["file"]["path"])
    result = windowed_asr_audit_v8(
        master_path=master_path,
        candidate_directory=output,
        reference_words=v5.normalize_words(text),
        cues=cues,
        cue_sample_ranges=candidate["cueSampleRanges"],
        config=_v8_audit_config(config),
    )
    receipt = {
        "schemaVersion": 1,
        "status": DECODER_PROOF_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "dependencyBindings": dependencies,
        "stressText": stress_record,
        "candidateID": "voice-candidate-06",
        "master": file_binding(master_path),
        "windowGeometry": {
            "windowSeconds": 30,
            "overlapSeconds": 15,
            "strideSeconds": 15,
        },
        "unchangedBoundaryAndAggregateGates": config["finalAudit"],
        "audit": result,
        "passesDecoderProof": (
            result["allWindowGatesPass"]
            and result["stitching"]["allBoundariesPass"]
            and result["aggregatePasses"]
        ),
        "parentAudioMayBecomeV8Master": False,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }
    receipt_path = output / "decoder-proof.v8.receipt.json"
    write_json(receipt_path, receipt)
    return {**receipt, "receipt": file_binding(receipt_path)}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Frozen offline V8 narration method")
    commands = result.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate")
    validate.add_argument("--offline", action="store_true")
    proof = commands.add_parser("decoder-proof")
    proof.add_argument("--output", required=True, type=Path)
    proof.add_argument("--offline", action="store_true")
    return result


def main() -> int:
    try:
        args = parser().parse_args()
        config = load_config()
        result = (
            validate_method(args, config)
            if args.command == "validate"
            else decoder_proof(args, config)
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (V8Error, v7.V7Error, v6.V6Error, v5.V5Error, production.PipelineError) as error:
        print(f"V8 narration error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
