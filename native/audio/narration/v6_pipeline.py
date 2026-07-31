#!/usr/bin/env python3
"""Frozen offline V6 narration stress generator and machine audit.

V6 treats the failed V5 long-form masters as negative evidence.  It never uses
V4 or V5 stress audio as a generation parent.  The approved 3,400-word text is
partitioned into short semantic utterances; every utterance must terminate,
retain speaker identity, pass in-process Whisper checks, and survive exact
resume validation before it can enter a candidate master.
"""

from __future__ import annotations

import argparse
from collections import Counter
import copy
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any, Iterable, Sequence

import pipeline as production
import v5_pipeline as v5


SCRIPT_PATH = Path(__file__).absolute()
CONFIG_PATH = SCRIPT_PATH.with_name("v6-audit-config.json")
REPOSITORY_ROOT = SCRIPT_PATH.parents[3]
EXPECTED_CONFIG_BYTES = 11951
EXPECTED_CONFIG_SHA256 = (
    "c7eeb28602fc46fb2538aee770d31302955bacefc7888f85cbf58ee2038bcc13"
)

METHOD_STATUS = "CODEX_V6_METHOD_FROZEN_WITH_UTTERANCE_GATES"
TRUST_DOMAIN = "CODEX_V6_DIAGNOSTIC_NON_SHIPPING"
BATCH_STATUS = "CODEX_V6_UTTERANCE_BATCH_COMMITTED_AFTER_IN_PROCESS_GATES"
CANDIDATE_STATUS = "CODEX_V6_CANDIDATE_COMMITTED_NON_SHIPPING"
STRESS_STATUS = "CODEX_V6_STRESS_SET_GENERATED_AWAITING_FULL_AUDIT"
AUDIT_STATUS = "CODEX_V6_MACHINE_AUDITED_NON_SHIPPING"
PROGRESS_STATUS = "CODEX_V6_DETERMINISTIC_GENERATION_PROGRESS"
FAILURE_LOG_STATUS = "CODEX_V6_DISCARDED_BATCH_ATTEMPTS"
EXPECTED_FINALISTS = ["voice-candidate-05", "voice-candidate-06"]


class V6Error(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return production.sha256_text(value)


def file_binding(path: Path) -> dict[str, Any]:
    return v5.file_binding(path)


def write_json(path: Path, value: Any) -> None:
    v5.write_json(path, value)


def repository_path(relative: str, *, directory: bool | None = None) -> Path:
    try:
        return v5.repository_path(relative, directory=directory)
    except v5.V5Error as error:
        raise V6Error(str(error)) from error


def validate_exact_file(
    path: Path, *, byte_count: int, digest: str, label: str
) -> None:
    try:
        v5.validate_exact_file(
            path, byte_count=byte_count, digest=digest, label=label
        )
    except v5.V5Error as error:
        raise V6Error(str(error)) from error


def validate_config_document(config: dict[str, Any]) -> None:
    if (
        config.get("schemaVersion") != 1
        or config.get("status") != METHOD_STATUS
        or config.get("trustDomain") != TRUST_DOMAIN
        or config.get("language") != "English"
        or config.get("locale") != "en-GB"
    ):
        raise V6Error("V6 config identity drifted")
    if config.get("parentChain", {}).get(
        "v4OrV5StressEvidencePermittedAsParent"
    ) is not False:
        raise V6Error("V4 or V5 stress evidence cannot become a V6 parent")
    if config.get("negativeEvidence", {}) != {
        "status": "V5_REJECTED_DIAGNOSTIC_ONLY_NEVER_A_V6_PARENT",
        "v5AuditReceiptBytes": 229813,
        "v5AuditReceiptSHA256": "55aaa8764651fb83d53b3deb9b1e2e82140bea55b4bac5eacbe69af39fbdcb79",
        "passingCandidateCount": 0,
        "recommendedVoiceID": None,
        "failedGates": [
            "cueAlignment",
            "referenceAwareRepetition",
            "silence",
        ],
    }:
        raise V6Error("V5 negative-evidence contract drifted")
    segmentation = config.get("segmentation", {})
    if (
        segmentation.get("maximumNormalizedWordsPerUtterance") != 36
        or segmentation.get("minimumNormalizedWordsPerUtterance") != 10
        or segmentation.get("utteranceCount") != 123
        or segmentation.get("utteranceManifestSHA256")
        != "570be5df0901c82ceacc18f8c456bade94fd54e72d297431f9150c7c85f48d38"
        or segmentation.get("exactCharacterPartitionRequired") is not True
        or segmentation.get("crossCuePackingProhibited") is not True
        or segmentation.get("wordOrCharacterChangeProhibited") is not True
    ):
        raise V6Error("V6 semantic segmentation contract drifted")
    generation = config.get("generation", {})
    if (
        generation.get("batchSize") != 8
        or generation.get("maximumBatchAttempts") != 3
        or generation.get("maximumTokens") != 384
        or generation.get("derivedTokenMultiplier") != 6
        or generation.get("minimumDerivedTokens") != 75
        or generation.get("repetitionPenaltyAppliedByICLMinimum") != 1.5
        or generation.get("stream") is not False
        or generation.get("firstPassingAttemptWins") is not True
    ):
        raise V6Error("V6 generation contract drifted")
    conditioning = config.get("referenceTempoConditioning", {})
    if (
        conditioning.get("factor") != 1.22
        or conditioning.get("lowestQualifyingFactor") != 1.22
        or conditioning.get("qualifyingFactors") != [1.22, 1.26]
        or conditioning.get("labReceiptBytes") != 282091
        or conditioning.get("labReceiptSHA256")
        != "6db5f61ac366b13e0f4a4e5c7e4265939e93869efc04ea9a8bcaa7e3d8d84534"
        or conditioning.get("priorRejectedLabReceiptBytes") != 367988
        or conditioning.get("priorRejectedLabReceiptSHA256")
        != "753cc1e9771fc2f1a6ed94c2f1e4b16232d4d8d4e76f622249d12d905739d728"
        or conditioning.get("labAudioPermittedAsArtifactParent") is not False
        or conditioning.get("r2AudioPermittedAsArtifactParent") is not False
        or conditioning.get("derivedReferenceMustBeRebuiltFromOriginal") is not True
        or set(conditioning.get("expectedReferences", {}))
        != set(EXPECTED_FINALISTS)
    ):
        raise V6Error("V6 reference-tempo conditioning contract drifted")
    pacing = config.get("adaptiveSemanticPacing", {})
    if (
        pacing.get("targetMaximumWordsPerMinute") != 205
        or pacing.get("hardGateMaximumWordsPerMinute") != 210
        or pacing.get("maximumAdditionalPauseMilliseconds") != 1000
        or pacing.get("appliesAfterAuthoredPause") is not True
        or pacing.get("onlyAddsWhenRequired") is not True
        or pacing.get("targetMustBeReachedBeforeCommit") is not True
        or pacing.get("zeroSignalOnly") is not True
        or pacing.get("speechTimeStretchApplied") is not False
        or pacing.get("recoveryLabReceiptBytes") != 110033
        or pacing.get("recoveryLabReceiptSHA256")
        != "c5ccc585d53b58192029af249a2506f816e4e41b8f4176f9cedb8544d22d5508"
        or pacing.get("rejectedR3FailureReceiptBytes") != 13692
        or pacing.get("rejectedR3FailureReceiptSHA256")
        != "8062c6718c28b2f7820fe5d196f608c1da3e95ee7da1c09b4161e9e2d1ba4920"
        or pacing.get("labOrRejectedAudioPermittedAsArtifactParent") is not False
    ):
        raise V6Error("V6 adaptive semantic-pacing contract drifted")
    gate = config.get("utteranceGate", {})
    if (
        gate.get("minimumIdentityCosineToReference") != 0.98
        or gate.get("minimumWordsPerMinute") != 100
        or gate.get("maximumWordsPerMinute") != 210
        or gate.get("maximumEditDistanceFloor") != 2
        or gate.get("maximumEditDistanceFraction") != 0.12
        or gate.get("maximumExcessRepeatedSixGramOccurrences") != 0
        or gate.get("tokenCeilingFails") is not True
        or gate.get("asrBeforeCommitRequired") is not True
    ):
        raise V6Error("V6 utterance gate drifted")
    if pacing["hardGateMaximumWordsPerMinute"] != gate["maximumWordsPerMinute"]:
        raise V6Error("adaptive pacing cannot change the hard utterance tempo gate")
    join = config.get("join", {})
    if (
        join.get("preSpeechMilliseconds") != 30
        or join.get("postSpeechMilliseconds") != 50
        or join.get("edgeFadeMilliseconds") != 10
        or join.get("intraParagraphPauseMilliseconds") != 30
        or join.get("paragraphPauseMilliseconds") != 120
        or join.get("firstAndLastSamplesMustBeZero") is not True
        or join.get("maximumJoinDiscontinuity") != 0.0
        or join.get("globalPeakGainOnly") is not True
    ):
        raise V6Error("V6 deterministic join contract drifted")
    correction = config.get("durationCorrection", {})
    if (
        correction.get("targetMaximumSeconds") != 1314.0
        or correction.get("hardMaximumUncorrectedSeconds") != 1353.42
        or correction.get("maximumTempoFactor") != 1.03
        or correction.get("slowingProhibited") is not True
    ):
        raise V6Error("V6 bounded duration-correction contract drifted")
    if config.get("costPolicy") != {
        "offlineRequired": True,
        "networkProhibited": True,
        "paidAPIProhibited": True,
        "incrementalCostNOK": 0,
    }:
        raise V6Error("V6 zero-cost offline policy drifted")
    exclusions = {
        "editor voice selection",
        "final word-accuracy approval",
        "final pronunciation approval",
        "artistic approval",
        "shipping approval",
    }
    if set(config.get("claimsExcluded", [])) != exclusions:
        raise V6Error("V6 approval exclusions drifted")


def load_config(path: Path = CONFIG_PATH) -> dict[str, Any]:
    if path.absolute() != CONFIG_PATH:
        raise V6Error("V6 config path is frozen")
    validate_exact_file(
        path,
        byte_count=EXPECTED_CONFIG_BYTES,
        digest=EXPECTED_CONFIG_SHA256,
        label="V6 config",
    )
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise V6Error(f"cannot load V6 config: {error}") from error
    validate_config_document(config)
    config["_path"] = str(path)
    return config


def validate_code_dependencies(config: dict[str, Any]) -> dict[str, Any]:
    dependencies = config["codeDependencies"]
    records: dict[str, Any] = {}
    for label, prefix in [
        ("v5AuditUtility", "v5AuditUtility"),
        ("v5TextExtractionConfig", "v5TextExtractionConfig"),
        ("qwenBatchImplementation", "qwenBatchImplementation"),
    ]:
        path = repository_path(dependencies[f"{prefix}Path"], directory=False)
        validate_exact_file(
            path,
            byte_count=dependencies[f"{prefix}Bytes"],
            digest=dependencies[f"{prefix}SHA256"],
            label=label,
        )
        records[label] = {
            **file_binding(path),
            "role": "CODE_DEPENDENCY_ONLY_NOT_ARTIFACT_PARENT",
        }
    return records


def pipeline_binding(config: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "trustDomain": TRUST_DOMAIN,
        "script": file_binding(SCRIPT_PATH),
        "config": file_binding(Path(config["_path"])),
        "codeDependencies": validate_code_dependencies(config),
    }


def validate_parent_chain(config: dict[str, Any]) -> dict[str, Any]:
    expected = config["parentChain"]
    paths = {
        "productionPipeline": repository_path(
            "native/audio/narration/pipeline.py", directory=False
        ),
        "productionConfig": repository_path(
            "native/audio/narration/pipeline-config.json", directory=False
        ),
        "uvLock": repository_path("native/audio/narration/uv.lock", directory=False),
        "candidateSetReceipt": repository_path(
            config["paths"]["candidateSetReceipt"], directory=False
        ),
    }
    for label, path in paths.items():
        validate_exact_file(
            path,
            byte_count=expected[f"{label}Bytes"],
            digest=expected[f"{label}SHA256"],
            label=label,
        )
    result = {
        "schemaVersion": 1,
        **{label: file_binding(path) for label, path in paths.items()},
        "provisionalFinalistIDs": list(EXPECTED_FINALISTS),
        "v4OrV5StressEvidencePermittedAsParent": False,
    }
    v5_hash = config["negativeEvidence"]["v5AuditReceiptSHA256"]
    if v5_hash in canonical_json(result):
        raise V6Error("V5 negative evidence leaked into the V6 parent chain")
    if expected["provisionalFinalistIDs"] != EXPECTED_FINALISTS:
        raise V6Error("V6 finalist inventory drifted")
    return result


def validate_asr_tools(config: dict[str, Any]) -> dict[str, Any]:
    try:
        return v5.validate_asr_tools(config)
    except v5.V5Error as error:
        raise V6Error(str(error)) from error


def validate_master_tools(config: dict[str, Any]) -> dict[str, Any]:
    try:
        return v5.validate_master_tools(config)
    except v5.V5Error as error:
        raise V6Error(str(error)) from error


def validate_v5_negative_evidence(config: dict[str, Any]) -> dict[str, Any]:
    path = repository_path(config["paths"]["v5NegativeAuditReceipt"], directory=False)
    negative = config["negativeEvidence"]
    validate_exact_file(
        path,
        byte_count=negative["v5AuditReceiptBytes"],
        digest=negative["v5AuditReceiptSHA256"],
        label="rejected V5 machine audit",
    )
    receipt = production.load_json(path)
    records = receipt.get("candidateRecords")
    if (
        receipt.get("status") != "CODEX_V5_MACHINE_AUDITED_NON_SHIPPING"
        or receipt.get("codexDiagnosticRecommendedVoiceID") is not None
        or receipt.get("shippingApproval") is not False
        or not isinstance(records, list)
        or [item.get("candidateID") for item in records] != EXPECTED_FINALISTS
        or any(item.get("passesCompleteV5MachineGate") is not False for item in records)
    ):
        raise V6Error("V5 negative evidence no longer proves two rejected candidates")
    collapse_records: list[dict[str, Any]] = []
    for candidate in records:
        failed = sorted(
            key for key, value in candidate.get("gates", {}).items() if value is False
        )
        if failed != sorted(negative["failedGates"]):
            raise V6Error("V5 candidate failure gates drifted")
        transcript_binding = candidate["inProcessWholeMasterASR"]["transcript"]
        transcript_path = Path(transcript_binding["path"])
        validate_exact_file(
            transcript_path,
            byte_count=transcript_binding["bytes"],
            digest=transcript_binding["sha256"],
            label=f"V5 transcript {candidate['candidateID']}",
        )
        document = production.load_json(transcript_path)
        words, _ = v5.timed_words_from_whisper(
            document,
            master_duration_ms=candidate["decodedDurationSeconds"] * 1000,
        )
        cue_failures: list[dict[str, Any]] = []
        for cue in candidate["cueAlignment"]["cueRecords"]:
            start_ms = cue["sampleRange"][0] * 1000 / config["master"]["nativeSampleRate"]
            end_ms = cue["sampleRange"][1] * 1000 / config["master"]["nativeSampleRate"]
            material = [
                word.text for word in words if start_ms <= word.start_ms < end_ms
            ]
            counts = Counter(
                tuple(material[index : index + 6])
                for index in range(max(0, len(material) - 5))
            )
            repeated = max(counts.items(), key=lambda item: item[1]) if counts else ((), 0)
            starts = [
                index
                for index in range(max(0, len(material) - 5))
                if tuple(material[index : index + 6]) == repeated[0]
            ]
            cue_failures.append(
                {
                    "segmentID": cue["segmentID"],
                    "recognizedWordCount": len(material),
                    "exactReferenceCoverage": cue["exactReferenceCoverage"],
                    "mostRepeatedSixGram": " ".join(repeated[0]),
                    "occurrences": repeated[1],
                    "secondOccurrenceWordOffset": starts[1] if len(starts) > 1 else None,
                }
            )
        collapse_records.append(
            {
                "candidateID": candidate["candidateID"],
                "wholeMasterWER": candidate["wholeMasterAlignment"][
                    "wordAlignmentErrorRate"
                ],
                "excessRepetitionFraction": candidate["repetition"][
                    "excessOccurrenceFraction"
                ],
                "cueFailures": cue_failures,
            }
        )
    return {
        "status": negative["status"],
        "receipt": file_binding(path),
        "role": "NEGATIVE_EVIDENCE_ONLY_NOT_ARTIFACT_PARENT",
        "passingCandidateCount": 0,
        "recommendedVoiceID": None,
        "collapseRecords": collapse_records,
    }


def validate_reference_tempo_method_evidence(
    config: dict[str, Any],
) -> dict[str, Any]:
    settings = config["referenceTempoConditioning"]
    lab_path = repository_path(settings["labReceiptPath"], directory=False)
    prior_path = repository_path(
        settings["priorRejectedLabReceiptPath"], directory=False
    )
    validate_exact_file(
        lab_path,
        byte_count=settings["labReceiptBytes"],
        digest=settings["labReceiptSHA256"],
        label="V6 qualifying reference-tempo lab",
    )
    validate_exact_file(
        prior_path,
        byte_count=settings["priorRejectedLabReceiptBytes"],
        digest=settings["priorRejectedLabReceiptSHA256"],
        label="V6 rejected reference-tempo lab",
    )
    lab = production.load_json(lab_path)
    prior = production.load_json(prior_path)
    if (
        prior.get("status")
        != "CODEX_V6_REFERENCE_TEMPO_LAB_COMPLETE_NON_SHIPPING"
        or prior.get("factors") != [1.0, 1.06, 1.1, 1.14]
        or prior.get("qualifyingFactors") != []
        or prior.get("lowestQualifyingFactor") is not None
        or prior.get("shippingApproval") is not False
        or lab.get("status")
        != "CODEX_V6_REFERENCE_TEMPO_LAB_COMPLETE_NON_SHIPPING"
        or lab.get("factors") != [1.18, 1.22, 1.26]
        or lab.get("qualifyingFactors") != settings["qualifyingFactors"]
        or lab.get("lowestQualifyingFactor") != settings["lowestQualifyingFactor"]
        or lab.get("shippingApproval") is not False
        or lab.get("networkUsed") is not False
        or lab.get("incrementalCostNOK") != 0
    ):
        raise V6Error("V6 reference-tempo lab evidence drifted")
    records = lab.get("factorRecords")
    selected = [
        item for item in records if item.get("factor") == settings["factor"]
    ] if isinstance(records, list) else []
    rejected_118 = [
        item for item in records if item.get("factor") == 1.18
    ] if isinstance(records, list) else []
    if (
        [item.get("candidateID") for item in selected] != EXPECTED_FINALISTS
        or any(item.get("passesLab") is not True for item in selected)
        or any(item.get("allClipGatesPass") is not True for item in selected)
        or len(rejected_118) != 2
        or not any(
            item.get("candidateID") == "voice-candidate-06"
            and item.get("estimatedDurationGate") is False
            and item.get("passesLab") is False
            for item in rejected_118
        )
    ):
        raise V6Error("V6 lowest qualifying reference-tempo factor is unproven")
    evidence_records = []
    for item in selected:
        candidate_id = item["candidateID"]
        expected = settings["expectedReferences"][candidate_id]
        conditioned = item["conditioning"]["conditioned"]
        decoded = item["conditionedReferenceDecoded"]
        if (
            item["conditioning"]["source"]["sha256"]
            != expected["originalSHA256"]
            or conditioned["bytes"] != expected["conditionedBytes"]
            or conditioned["sha256"] != expected["conditionedSHA256"]
            or decoded["decodedSampleCount"]
            != expected["decodedSampleCountAt24000Hz"]
            or decoded["decodedFloat32LESHA256"]
            != expected["decodedFloat32LESHA256"]
            or item["conditionedReferenceIdentityCosineToOriginal"]
            != expected["labIdentityCosineToOriginal"]
            or item["estimatedDurationGate"] is not True
        ):
            raise V6Error("V6 selected conditioned-reference evidence drifted")
        evidence_records.append(
            {
                "candidateID": candidate_id,
                "factor": item["factor"],
                "conditionedReferenceSHA256": conditioned["sha256"],
                "labIdentityCosineToOriginal": item[
                    "conditionedReferenceIdentityCosineToOriginal"
                ],
                "minimumLabClipIdentityCosine": item["minimumClipIdentityCosine"],
                "maximumLabClipWER": item["maximumClipWER"],
                "estimatedFullPretempoSeconds": item[
                    "estimatedFullPretempoSeconds"
                ],
                "estimatedRequiredMasterTempoFactor": item[
                    "estimatedRequiredMasterTempoFactor"
                ],
                "allClipGatesPass": True,
                "passesLab": True,
            }
        )
    return {
        "status": "V6_REFERENCE_TEMPO_1P22_PROVEN_LOWEST_QUALIFYING_FACTOR",
        "role": "METHOD_EVIDENCE_ONLY_NEVER_AN_AUDIO_PARENT",
        "qualifyingLabReceipt": file_binding(lab_path),
        "priorRejectedLabReceipt": file_binding(prior_path),
        "factor": settings["factor"],
        "pitchPreserving": True,
        "labAudioPermittedAsArtifactParent": False,
        "r2AudioPermittedAsArtifactParent": False,
        "records": evidence_records,
    }


def validate_adaptive_semantic_pacing_method_evidence(
    config: dict[str, Any],
) -> dict[str, Any]:
    settings = config["adaptiveSemanticPacing"]
    lab_path = repository_path(settings["recoveryLabReceiptPath"], directory=False)
    rejected_path = repository_path(
        settings["rejectedR3FailureReceiptPath"], directory=False
    )
    validate_exact_file(
        lab_path,
        byte_count=settings["recoveryLabReceiptBytes"],
        digest=settings["recoveryLabReceiptSHA256"],
        label="V6 adaptive semantic-pacing recovery lab",
    )
    validate_exact_file(
        rejected_path,
        byte_count=settings["rejectedR3FailureReceiptBytes"],
        digest=settings["rejectedR3FailureReceiptSHA256"],
        label="V6 rejected R3 batch finding",
    )
    lab = production.load_json(lab_path)
    rejected = production.load_json(rejected_path)
    expected_proposal = {
        "referenceTempoFactor": config["referenceTempoConditioning"]["factor"],
        "targetMaximumWordsPerMinute": settings[
            "targetMaximumWordsPerMinute"
        ],
        "unchangedHardGateMaximumWordsPerMinute": settings[
            "hardGateMaximumWordsPerMinute"
        ],
        "maximumAdditionalPauseMilliseconds": settings[
            "maximumAdditionalPauseMilliseconds"
        ],
        "zeroSignalAtAuthoredSemanticBoundaryOnly": True,
        "speechTimeStretchApplied": False,
    }
    if (
        lab.get("status")
        != "CODEX_V6_REFERENCE_TEMPO_FALLBACK_LAB_COMPLETE_NON_SHIPPING"
        or lab.get("trustDomain") != TRUST_DOMAIN
        or lab.get("factor") != config["referenceTempoConditioning"]["factor"]
        or lab.get("batchIndex") != 7
        or lab.get("attempt") != 2
        or lab.get("passesRecoveryLab") is not True
        or lab.get("proposedAdaptivePacing") != expected_proposal
        or lab.get("networkUsed") is not False
        or lab.get("incrementalCostNOK") != 0
        or lab.get("shippingApproval") is not False
        or rejected.get("status") != FAILURE_LOG_STATUS
        or rejected.get("discardedAudioRetained") is not False
    ):
        raise V6Error("V6 adaptive semantic-pacing lab evidence drifted")
    rejected_entries = rejected.get("entries")
    if (
        not isinstance(rejected_entries, list)
        or len(rejected_entries) != 3
        or [item.get("attempt") for item in rejected_entries] != [1, 2, 3]
        or any(item.get("candidateID") != "voice-candidate-05" for item in rejected_entries)
        or any(item.get("batchIndex") != 7 for item in rejected_entries)
        or any(
            item.get("failedUtterances", [{}])[0].get("utteranceID")
            != "utterance-059"
            for item in rejected_entries
        )
        or any(
            item["failedUtterances"][0].get("failedGates") != ["maximumTempo"]
            for item in rejected_entries
        )
    ):
        raise V6Error("V6 rejected R3 finding no longer proves the pacing failure")
    records = lab.get("records")
    if (
        not isinstance(records, list)
        or [item.get("candidateID") for item in records] != EXPECTED_FINALISTS
    ):
        raise V6Error("V6 adaptive semantic-pacing candidate evidence drifted")
    evidence_records = []
    expected_utterance_ids = [f"utterance-{index:03d}" for index in range(56, 64)]
    for record in records:
        clips = record.get("clips")
        if (
            record.get("allClipGatesPass") is not True
            or not isinstance(clips, list)
            or [item.get("utterance", {}).get("utteranceID") for item in clips]
            != expected_utterance_ids
            or any(item.get("gate", {}).get("passes") is not True for item in clips)
            or any(
                item.get("processing", {})
                .get("adaptiveSemanticPauseLab", {})
                .get("speechTimeStretchApplied")
                is not False
                for item in clips
            )
            or any(
                item.get("processing", {})
                .get("adaptiveSemanticPauseLab", {})
                .get("zeroSignalOnly")
                is not True
                for item in clips
            )
        ):
            raise V6Error("V6 adaptive semantic-pacing clip evidence drifted")
        changed = [
            item
            for item in clips
            if item["processing"]["adaptiveSemanticPauseLab"][
                "additionalPauseSamples"
            ]
            > 0
        ]
        if record["candidateID"] == "voice-candidate-05":
            if (
                len(changed) != 1
                or changed[0]["utterance"]["utteranceID"] != "utterance-059"
                or changed[0]["processing"]["adaptiveSemanticPauseLab"][
                    "additionalPauseSamples"
                ]
                != 12059
                or changed[0]["gate"]["wordsPerMinute"]
                > settings["targetMaximumWordsPerMinute"]
            ):
                raise V6Error("V6 candidate 05 pacing recovery is unproven")
        elif changed:
            raise V6Error("V6 candidate 06 pacing recovery unexpectedly changed audio")
        evidence_records.append(
            {
                "candidateID": record["candidateID"],
                "minimumClipIdentityCosine": record[
                    "minimumClipIdentityCosine"
                ],
                "maximumWordsPerMinute": record["maximumWordsPerMinute"],
                "changedUtterances": [
                    {
                        "utteranceID": item["utterance"]["utteranceID"],
                        "additionalPauseSamples": item["processing"][
                            "adaptiveSemanticPauseLab"
                        ]["additionalPauseSamples"],
                        "additionalPauseMilliseconds": item["processing"][
                            "adaptiveSemanticPauseLab"
                        ]["additionalPauseMilliseconds"],
                        "wordsPerMinuteAfterPause": item["gate"][
                            "wordsPerMinute"
                        ],
                    }
                    for item in changed
                ],
                "allClipGatesPass": True,
            }
        )
    return {
        "status": "V6_ADAPTIVE_SEMANTIC_PACING_PROVEN_ON_EXACT_R3_FAILURE_BATCH",
        "role": "METHOD_EVIDENCE_ONLY_NEVER_AN_AUDIO_PARENT",
        "recoveryLabReceipt": file_binding(lab_path),
        "rejectedR3FailureReceipt": file_binding(rejected_path),
        "targetMaximumWordsPerMinute": settings["targetMaximumWordsPerMinute"],
        "hardGateMaximumWordsPerMinute": settings[
            "hardGateMaximumWordsPerMinute"
        ],
        "maximumAdditionalPauseMilliseconds": settings[
            "maximumAdditionalPauseMilliseconds"
        ],
        "zeroSignalOnly": True,
        "speechTimeStretchApplied": False,
        "labOrRejectedAudioPermittedAsArtifactParent": False,
        "records": evidence_records,
    }


def validate_generation_method_evidence(config: dict[str, Any]) -> dict[str, Any]:
    return {
        "status": "V6_REFERENCE_TEMPO_AND_ADAPTIVE_SEMANTIC_PACING_PROVEN",
        "role": "METHOD_EVIDENCE_ONLY_NEVER_AN_AUDIO_PARENT",
        "referenceTempoConditioning": validate_reference_tempo_method_evidence(
            config
        ),
        "adaptiveSemanticPacing": validate_adaptive_semantic_pacing_method_evidence(
            config
        ),
    }


def _conditioned_reference_command(
    source: Path, destination: Path, config: dict[str, Any]
) -> list[str]:
    factor = config["referenceTempoConditioning"]["factor"]
    return [
        config["master"]["ffmpegPath"],
        "-nostdin",
        "-y",
        "-loglevel",
        "error",
        "-i",
        str(source),
        "-map_metadata",
        "-1",
        "-fflags",
        "+bitexact",
        "-flags:a",
        "+bitexact",
        "-af",
        f"atempo={factor:.12f}",
        "-ar",
        "48000",
        "-ac",
        "1",
        "-c:a",
        "pcm_s24le",
        str(destination),
    ]


def prepare_conditioned_references(
    *,
    output_root: Path,
    context: dict[str, Any],
    extractor: Any,
    original_units: dict[str, Any],
    config: dict[str, Any],
    method_evidence: dict[str, Any],
) -> tuple[dict[str, Path], dict[str, dict[str, Any]]]:
    directory = v5.confined_path(
        output_root / "conditioned-references",
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    paths: dict[str, Path] = {}
    records: dict[str, dict[str, Any]] = {}
    settings = config["referenceTempoConditioning"]
    for candidate_id in EXPECTED_FINALISTS:
        parent = context["parentRecords"][candidate_id]
        source = Path(parent["_verifiedReferencePath"])
        source = v5.confined_path(
            source,
            root=context["candidateRoot"],
            must_exist=True,
            expect_directory=False,
        )
        expected = settings["expectedReferences"][candidate_id]
        if file_binding(source)["sha256"] != expected["originalSHA256"]:
            raise V6Error("original selected reference drifted before conditioning")
        target = directory / f"{candidate_id}-tempo-1p22.wav"
        temporary = work_root(config, create=False) / (
            f".v6-reference-tempo-recompute-{candidate_id}.wav"
        )
        if temporary.exists():
            temporary.unlink()
        subprocess.run(
            _conditioned_reference_command(source, temporary, config),
            check=True,
            capture_output=True,
        )
        validate_exact_file(
            temporary,
            byte_count=expected["conditionedBytes"],
            digest=expected["conditionedSHA256"],
            label=f"rebuilt conditioned reference {candidate_id}",
        )
        if target.exists():
            validate_exact_file(
                target,
                byte_count=expected["conditionedBytes"],
                digest=expected["conditionedSHA256"],
                label=f"committed conditioned reference {candidate_id}",
            )
            temporary.unlink()
        else:
            os.replace(temporary, target)
            v5._fsync_directory(directory)
        decoded_audio, decoded = v5._load_reference_audio(
            target, config["master"]["nativeSampleRate"]
        )
        identity = _utterance_identity_cosine(
            decoded_audio, original_units[candidate_id], extractor
        )
        if (
            decoded["decodedSampleCount"]
            != expected["decodedSampleCountAt24000Hz"]
            or decoded["decodedFloat32LESHA256"]
            != expected["decodedFloat32LESHA256"]
            or identity
            < config["utteranceGate"]["minimumIdentityCosineToReference"]
        ):
            raise V6Error("rebuilt conditioned reference failed its frozen gate")
        paths[candidate_id] = target
        records[candidate_id] = {
            "candidateID": candidate_id,
            "factor": settings["factor"],
            "method": settings["method"],
            "originalReference": file_binding(source),
            "conditionedReference": file_binding(target),
            "decoded": decoded,
            "identityCosineToOriginalReference": identity,
            "identityGate": True,
            "methodEvidence": method_evidence,
            "labOrR2AudioUsed": False,
            "networkUsed": False,
            "incrementalCostNOK": 0,
        }
    if {item.name for item in directory.iterdir()} != {
        f"{candidate_id}-tempo-1p22.wav" for candidate_id in EXPECTED_FINALISTS
    }:
        raise V6Error("conditioned-reference inventory contains unexpected files")
    return paths, records


def stress_and_utterance_material(
    config: dict[str, Any],
) -> tuple[str, dict[str, Any], list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    v5_config = v5.load_config()
    text, source_record, cues = v5.stress_material(v5_config)
    stress = config["stressText"]
    if (
        source_record["source"]["bytes"] != stress["sourceBytes"]
        or source_record["source"]["sha256"] != stress["sourceSHA256"]
        or source_record["sourceStatus"] != stress["sourceStatus"]
        or source_record["textSHA256"] != stress["textSHA256"]
        or source_record["wordCount"] != stress["wordCount"]
        or source_record["normalizedWordCount"] != stress["normalizedWordCount"]
    ):
        raise V6Error("approved V6 stress text drifted")
    atoms: list[str] = []
    for match in re.finditer(r".*?(?:\n\n|\Z)", text, flags=re.S):
        block = match.group(0)
        if not block:
            continue
        paragraph_separator = "\n\n" if block.endswith("\n\n") else ""
        paragraph = block[:-2] if paragraph_separator else block
        date_heading = bool(
            re.match(r"^(?:c\.\s+)?(?:AD\s+\d+|\d+\s+BC)\.\s+\S", paragraph)
        )
        if date_heading:
            atoms.append(paragraph + paragraph_separator)
            continue
        start = 0
        boundaries = list(re.finditer(r"(?<=[.!?])(?=\s+\S)", paragraph))
        for index, boundary in enumerate([*boundaries, None]):
            end = boundary.start() if boundary is not None else len(paragraph)
            whitespace = re.match(r"\s+", paragraph[end:])
            separator = whitespace.group(0) if whitespace else ""
            if index == len(boundaries):
                separator += paragraph_separator
            atoms.append(paragraph[start:end] + separator)
            start = end + len(whitespace.group(0) if whitespace else "")
    if "".join(atoms) != text:
        raise V6Error("semantic atoms do not preserve every approved character")
    hard_boundaries = {
        cue["sourceCharacterEndExclusive"] + len(cue["separatorAfter"])
        for cue in cues
    }
    packed: list[tuple[int, str]] = []
    current = ""
    current_start = 0
    cursor = 0
    current_words = 0
    maximum_words = config["segmentation"]["maximumNormalizedWordsPerUtterance"]
    for atom in atoms:
        atom_words = len(v5.normalize_words(atom.rstrip()))
        if current and (cursor in hard_boundaries or current_words + atom_words > maximum_words):
            packed.append((current_start, current))
            current_start = cursor
            current = ""
            current_words = 0
        current += atom
        current_words += atom_words
        cursor += len(atom)
    if current:
        packed.append((current_start, current))
    utterances: list[dict[str, Any]] = []
    public_manifest: list[dict[str, Any]] = []
    for index, (start, chunk) in enumerate(packed):
        material = chunk.rstrip()
        separator = chunk[len(material) :]
        end = start + len(material)
        matching_cues = [
            cue
            for cue in cues
            if cue["sourceCharacterStartInclusive"] <= start
            and end <= cue["sourceCharacterEndExclusive"]
        ]
        if len(matching_cues) != 1:
            raise V6Error("utterance crossed a frozen cue boundary")
        cue = matching_cues[0]
        public = {
            "utteranceID": f"utterance-{index:03d}",
            "order": index + 1,
            "segmentID": cue["segmentID"],
            "sourceCharacterStartInclusive": start,
            "sourceCharacterEndExclusive": end,
            "separatorAfter": separator,
            "textSHA256": sha256_text(material),
            "wordCount": production.word_count(material),
            "normalizedWordCount": len(v5.normalize_words(material)),
        }
        public_manifest.append(public)
        utterances.append({**public, "text": material})
    segmentation = config["segmentation"]
    if (
        len(utterances) != segmentation["utteranceCount"]
        or min(item["normalizedWordCount"] for item in utterances)
        != segmentation["minimumNormalizedWordsPerUtterance"]
        or max(item["normalizedWordCount"] for item in utterances)
        != segmentation["maximumNormalizedWordsPerUtterance"]
        or sum(item["wordCount"] for item in utterances) != stress["wordCount"]
        or sum(item["normalizedWordCount"] for item in utterances)
        != stress["normalizedWordCount"]
        or sha256_text(canonical_json(public_manifest))
        != segmentation["utteranceManifestSHA256"]
        or "".join(item["text"] + item["separatorAfter"] for item in utterances)
        != text
    ):
        raise V6Error("frozen utterance manifest drifted")
    utterance_record = {
        "algorithmVersion": segmentation["algorithmVersion"],
        "utteranceCount": len(utterances),
        "manifestSHA256": segmentation["utteranceManifestSHA256"],
        "minimumNormalizedWords": min(
            item["normalizedWordCount"] for item in utterances
        ),
        "maximumNormalizedWords": max(
            item["normalizedWordCount"] for item in utterances
        ),
        "exactCharacterPartition": True,
        "crossCuePacking": False,
    }
    return text, source_record, cues, utterances, utterance_record


def batch_specs(
    utterances: list[dict[str, Any]], config: dict[str, Any]
) -> list[list[dict[str, Any]]]:
    size = config["generation"]["batchSize"]
    return [utterances[index : index + size] for index in range(0, len(utterances), size)]


def _activity_bounds(audio: Any, sample_rate: int, config: dict[str, Any]) -> tuple[int, int]:
    import numpy as np

    settings = config["join"]
    material = np.asarray(audio, dtype=np.float32).reshape(-1)
    frame = round(sample_rate * settings["activityFrameMilliseconds"] / 1000)
    hop = round(sample_rate * settings["activityHopMilliseconds"] / 1000)
    if material.size < frame:
        raise V6Error("utterance is too short for activity detection")
    squared = material.astype(np.float64) ** 2
    cumulative = np.concatenate(([0.0], np.cumsum(squared)))
    starts = np.arange(0, material.size - frame + 1, hop, dtype=np.int64)
    rms = np.sqrt((cumulative[starts + frame] - cumulative[starts]) / frame + 1e-15)
    active = np.flatnonzero(rms >= 10 ** (settings["activityThresholdDBFS"] / 20))
    if active.size == 0:
        raise V6Error("utterance contains no active speech")
    pre = round(sample_rate * settings["preSpeechMilliseconds"] / 1000)
    post = round(sample_rate * settings["postSpeechMilliseconds"] / 1000)
    start = max(0, int(starts[active[0]]) - pre)
    end = min(material.size, int(starts[active[-1]]) + frame + post)
    if end <= start:
        raise V6Error("activity crop is empty")
    return start, end


def process_utterance_audio(
    audio: Any,
    *,
    sample_rate: int,
    separator_after: str,
    config: dict[str, Any],
    normalized_word_count: int | None = None,
) -> tuple[Any, dict[str, Any]]:
    import numpy as np

    material = np.ascontiguousarray(np.asarray(audio, dtype=np.float32).reshape(-1))
    if (
        sample_rate != config["master"]["nativeSampleRate"]
        or material.size == 0
        or not np.all(np.isfinite(material))
    ):
        raise V6Error("raw utterance PCM is invalid")
    crop_start, crop_end = _activity_bounds(material, sample_rate, config)
    processed = np.array(material[crop_start:crop_end], dtype=np.float32, copy=True)
    fade_samples = round(
        sample_rate * config["join"]["edgeFadeMilliseconds"] / 1000
    )
    if processed.size <= fade_samples * 2 or fade_samples <= 1:
        raise V6Error("utterance is too short for the frozen edge fades")
    phase = np.linspace(0.0, math.pi / 2, fade_samples, dtype=np.float64)
    fade_in = np.sin(phase) ** 2
    fade_out = np.cos(phase) ** 2
    processed[:fade_samples] *= fade_in.astype(np.float32)
    processed[-fade_samples:] *= fade_out.astype(np.float32)
    processed[0] = 0.0
    processed[-1] = 0.0
    if separator_after == "\n\n":
        pause_ms = config["join"]["paragraphPauseMilliseconds"]
    elif separator_after == " ":
        pause_ms = config["join"]["intraParagraphPauseMilliseconds"]
    elif separator_after == "":
        pause_ms = config["join"]["finalPauseMilliseconds"]
    else:
        raise V6Error(f"unsupported authored utterance separator: {separator_after!r}")
    pause_samples = round(sample_rate * pause_ms / 1000)
    if pause_samples:
        processed = np.concatenate(
            [processed, np.zeros(pause_samples, dtype=np.float32)]
        )
    adaptive_record = None
    if normalized_word_count is not None:
        if type(normalized_word_count) is not int or normalized_word_count <= 0:
            raise V6Error("adaptive pacing requires a positive normalized word count")
        pacing = config["adaptiveSemanticPacing"]
        sample_count_before_adaptive = int(processed.size)
        required_target_samples = math.ceil(
            normalized_word_count
            / pacing["targetMaximumWordsPerMinute"]
            * 60
            * sample_rate
        )
        requested_additional = max(
            0, required_target_samples - sample_count_before_adaptive
        )
        maximum_additional = round(
            sample_rate
            * pacing["maximumAdditionalPauseMilliseconds"]
            / 1000
        )
        applied_additional = min(requested_additional, maximum_additional)
        if applied_additional:
            processed = np.concatenate(
                [processed, np.zeros(applied_additional, dtype=np.float32)]
            )
        target_reached = int(processed.size) >= required_target_samples
        adaptive_record = {
            "normalizedWordCount": normalized_word_count,
            "targetMaximumWordsPerMinute": pacing[
                "targetMaximumWordsPerMinute"
            ],
            "unchangedHardGateMaximumWordsPerMinute": pacing[
                "hardGateMaximumWordsPerMinute"
            ],
            "sampleCountBeforeAdaptivePause": sample_count_before_adaptive,
            "requiredSampleCountAtTargetMaximum": required_target_samples,
            "requestedAdditionalPauseSamples": requested_additional,
            "maximumAdditionalPauseMilliseconds": pacing[
                "maximumAdditionalPauseMilliseconds"
            ],
            "maximumAdditionalPauseSamples": maximum_additional,
            "additionalPauseSamples": applied_additional,
            "additionalPauseMilliseconds": applied_additional
            * 1000
            / sample_rate,
            "onlyAddedWhenRequired": applied_additional == 0
            or requested_additional > 0,
            "targetReachedBeforeCommitGate": target_reached,
            "zeroSignalOnly": True,
            "speechTimeStretchApplied": False,
        }
    processed = np.ascontiguousarray(processed, dtype=np.float32)
    if processed[0] != 0.0 or processed[-1] != 0.0:
        raise V6Error("processed utterance does not meet the zero-edge contract")
    record = {
        "rawSampleCount": int(material.size),
        "cropStartSampleInclusive": crop_start,
        "cropEndSampleExclusive": crop_end,
        "retainedSampleCountBeforePause": crop_end - crop_start,
        "edgeFadeSamples": fade_samples,
        "pauseMilliseconds": pause_ms,
        "pauseSamples": pause_samples,
        "processedSampleCount": int(processed.size),
        "firstSample": float(processed[0]),
        "lastSample": float(processed[-1]),
        "algorithm": "activity crop with retained pre/post roll, squared-sine zero-edge fades, and authored deterministic pause",
    }
    if adaptive_record is not None:
        record["adaptiveSemanticPacing"] = adaptive_record
        record["algorithm"] += (
            "; then bounded zero-signal semantic-boundary pacing without speech time stretch"
        )
    return processed, record


def maximum_false_run(values: Sequence[bool]) -> int:
    maximum = current = 0
    for value in values:
        if value:
            current = 0
        else:
            current += 1
            maximum = max(maximum, current)
    return maximum


def utterance_asr_gate(
    *,
    utterance: dict[str, Any],
    transcript: dict[str, Any],
    duration_seconds: float,
    token_count: int,
    token_cap: int,
    identity_cosine: float,
    config: dict[str, Any],
    adaptive_pacing_pass: bool = True,
) -> dict[str, Any]:
    reference = v5.normalize_words(utterance["text"])
    settings = config["utteranceGate"]
    words_per_minute = len(reference) / (duration_seconds / 60)
    try:
        timed_words, grouping = v5.timed_words_from_whisper(
            transcript, master_duration_ms=duration_seconds * 1000
        )
    except v5.V5Error as error:
        gates = {
            "adaptiveSemanticPacing": adaptive_pacing_pass,
            "tokenCeiling": token_count < token_cap,
            "identity": identity_cosine
            >= settings["minimumIdentityCosineToReference"],
            "minimumTempo": words_per_minute >= settings["minimumWordsPerMinute"],
            "maximumTempo": words_per_minute <= settings["maximumWordsPerMinute"],
            "minimumWordRatio": False,
            "maximumWordRatio": False,
            "editDistance": False,
            "referenceRun": False,
            "hypothesisRun": False,
            "repetition": False,
            "boundedTimestamps": False,
        }
        return {
            "referenceWordCount": len(reference),
            "hypothesisWordCount": None,
            "hypothesisToReferenceWordRatio": None,
            "durationSeconds": duration_seconds,
            "wordsPerMinute": words_per_minute,
            "tokenCount": token_count,
            "tokenCap": token_cap,
            "identityCosineToReference": identity_cosine,
            "maximumPermittedEditDistance": max(
                settings["maximumEditDistanceFloor"],
                math.ceil(
                    len(reference) * settings["maximumEditDistanceFraction"]
                ),
            ),
            "alignment": None,
            "maximumNonmatchingReferenceRunWords": None,
            "maximumNonmatchingHypothesisRunWords": None,
            "repetition": None,
            "timedWordGrouping": None,
            "transcriptStructuralError": str(error),
            "gates": gates,
            "passes": False,
        }
    hypothesis = [word.text for word in timed_words]
    steps, alignment = v5.monotone_global_alignment(reference, hypothesis)
    exact_reference = [False] * len(reference)
    exact_hypothesis = [False] * len(hypothesis)
    for step in steps:
        if step.operation == "equal":
            assert step.reference_index is not None
            assert step.hypothesis_index is not None
            exact_reference[step.reference_index] = True
            exact_hypothesis[step.hypothesis_index] = True
    repetition = v5.reference_aware_repetition(reference, hypothesis, config)
    maximum_edits = max(
        settings["maximumEditDistanceFloor"],
        math.ceil(len(reference) * settings["maximumEditDistanceFraction"]),
    )
    ratio = len(hypothesis) / len(reference)
    gates = {
        "adaptiveSemanticPacing": adaptive_pacing_pass,
        "tokenCeiling": token_count < token_cap,
        "identity": identity_cosine
        >= settings["minimumIdentityCosineToReference"],
        "minimumTempo": words_per_minute >= settings["minimumWordsPerMinute"],
        "maximumTempo": words_per_minute <= settings["maximumWordsPerMinute"],
        "minimumWordRatio": ratio
        >= settings["minimumHypothesisToReferenceWordRatio"],
        "maximumWordRatio": ratio
        <= settings["maximumHypothesisToReferenceWordRatio"],
        "editDistance": alignment["editDistance"] <= maximum_edits,
        "referenceRun": maximum_false_run(exact_reference)
        <= settings["maximumNonmatchingReferenceRunWords"],
        "hypothesisRun": maximum_false_run(exact_hypothesis)
        <= settings["maximumNonmatchingHypothesisRunWords"],
        "repetition": repetition["excessOccurrenceCount"]
        <= settings["maximumExcessRepeatedSixGramOccurrences"],
        "boundedTimestamps": grouping["boundedByDecodedMaster"] is True,
    }
    return {
        "referenceWordCount": len(reference),
        "hypothesisWordCount": len(hypothesis),
        "hypothesisToReferenceWordRatio": ratio,
        "durationSeconds": duration_seconds,
        "wordsPerMinute": words_per_minute,
        "tokenCount": token_count,
        "tokenCap": token_cap,
        "identityCosineToReference": identity_cosine,
        "maximumPermittedEditDistance": maximum_edits,
        "alignment": alignment,
        "maximumNonmatchingReferenceRunWords": maximum_false_run(exact_reference),
        "maximumNonmatchingHypothesisRunWords": maximum_false_run(exact_hypothesis),
        "repetition": repetition,
        "timedWordGrouping": grouping,
        "gates": gates,
        "passes": all(gates.values()),
    }


def work_root(config: dict[str, Any], *, create: bool) -> Path:
    root = REPOSITORY_ROOT / config["paths"]["workRoot"]
    if create and not root.exists():
        parent = v5.confined_path(
            root.parent,
            root=REPOSITORY_ROOT,
            must_exist=True,
            expect_directory=True,
        )
        root.mkdir()
        v5._fsync_directory(parent)
    return v5.confined_path(
        root,
        root=REPOSITORY_ROOT,
        must_exist=True,
        expect_directory=True,
    )


def prepare_generation_root(path: Path, config: dict[str, Any]) -> Path:
    root = work_root(config, create=True)
    target = v5.confined_path(
        path,
        root=root,
        must_exist=path.exists(),
        expect_directory=True if path.exists() else None,
    )
    if target == root or target.parent != root:
        raise V6Error("V6 generation output must be one direct child of its work root")
    if not target.exists():
        target.mkdir()
    for relative in ["batch-commits", "candidates", "conditioned-references"]:
        directory = target / relative
        if directory.exists():
            v5.confined_path(
                directory,
                root=target,
                must_exist=True,
                expect_directory=True,
            )
        else:
            directory.mkdir()
    staging = target / ".staging"
    if staging.exists():
        staging = v5.confined_path(
            staging,
            root=target,
            must_exist=True,
            expect_directory=True,
        )
        shutil.rmtree(staging)
    return target


def prepare_audit_root(path: Path, config: dict[str, Any]) -> Path:
    root = work_root(config, create=True)
    target = v5.confined_path(
        path,
        root=root,
        must_exist=path.exists(),
        expect_directory=True if path.exists() else None,
    )
    if target == root or target.parent != root:
        raise V6Error("V6 audit output must be one direct child of its work root")
    if target.exists() and any(target.iterdir()):
        raise V6Error("V6 audit output must be absent or empty")
    target.mkdir(parents=True, exist_ok=True)
    return target


def batch_relative(candidate_id: str, batch_index: int) -> Path:
    return Path("batch-commits") / candidate_id / f"batch-{batch_index:03d}"


def candidate_relative(candidate_id: str) -> Path:
    return Path("candidates") / candidate_id


def _destination_binding(path: Path, destination: Path) -> dict[str, Any]:
    binding = file_binding(path)
    binding["path"] = str(destination / path.name)
    return binding


def _transcript_document_is_pinned(
    document: dict[str, Any], config: dict[str, Any]
) -> bool:
    return (
        document.get("result", {}).get("language") == "en"
        and document.get("params", {}).get("language") == "en"
        and document.get("params", {}).get("translate") is False
        and document.get("params", {}).get("model")
        == config["offlineASR"]["modelPath"]
    )


def run_whisper_batch(
    *, audio_paths: list[Path], staging: Path, config: dict[str, Any]
) -> tuple[list[Path], dict[str, Any]]:
    if not audio_paths:
        raise V6Error("cannot audit an empty utterance batch")
    asr = config["offlineASR"]
    for path in audio_paths:
        v5.confined_path(
            path,
            root=staging,
            must_exist=True,
            expect_directory=False,
        )
        output = Path(str(path) + ".json")
        v5.validate_no_symlink_parent_chain(output, allow_missing_leaf=True)
        if os.path.lexists(output):
            raise V6Error("pre-existing per-utterance Whisper output")
    command = [
        asr["executablePath"],
        "--model",
        asr["modelPath"],
        *asr["arguments"],
        *[str(path) for path in audio_paths],
    ]
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    log_path = staging / "whisper.batch.log.txt"
    log_path.write_text(
        (completed.stdout or "") + (completed.stderr or ""), encoding="utf-8"
    )
    transcripts: list[Path] = []
    for path in audio_paths:
        generated = v5.confined_path(
            Path(str(path) + ".json"),
            root=staging,
            must_exist=True,
            expect_directory=False,
        )
        document = production.load_json(generated)
        if not _transcript_document_is_pinned(document, config):
            raise V6Error("per-utterance Whisper parameters drifted")
        transcripts.append(generated)
    return transcripts, {
        "tool": validate_asr_tools(config),
        "arguments": list(asr["arguments"]),
        "inputCount": len(audio_paths),
        "inputFiles": [file_binding(path) for path in audio_paths],
        "log": file_binding(log_path),
        "answerPromptUsed": False,
        "externalTranscriptReceiptUsed": False,
        "networkUsed": False,
    }


def _generation_settings(config: dict[str, Any]) -> dict[str, Any]:
    settings = config["generation"]
    return {
        "mode": settings["mode"],
        "batchSize": settings["batchSize"],
        "temperature": settings["temperature"],
        "topK": settings["topK"],
        "topP": settings["topP"],
        "repetitionPenaltyRequested": settings["repetitionPenaltyRequested"],
        "repetitionPenaltyAppliedByICLMinimum": settings[
            "repetitionPenaltyAppliedByICLMinimum"
        ],
        "maximumTokens": settings["maximumTokens"],
        "derivedTokenMultiplier": settings["derivedTokenMultiplier"],
        "minimumDerivedTokens": settings["minimumDerivedTokens"],
        "stream": False,
    }


def _derived_token_cap(model: Any, text: str, config: dict[str, Any]) -> tuple[int, int]:
    tokenizer_count = len(model.tokenizer.encode(text))
    settings = config["generation"]
    cap = min(
        settings["maximumTokens"],
        max(
            settings["minimumDerivedTokens"],
            tokenizer_count * settings["derivedTokenMultiplier"],
        ),
    )
    return tokenizer_count, cap


def _reference_unit_embedding(
    *, candidate_record: dict[str, Any], extractor: Any, config: dict[str, Any]
) -> tuple[Any, dict[str, Any]]:
    import numpy as np

    path = Path(candidate_record["_verifiedReferencePath"])
    audio, record = v5._load_reference_audio(
        path, config["master"]["nativeSampleRate"]
    )
    embedding = np.asarray(extractor(audio), dtype=np.float32).reshape(-1)
    norm = float(np.linalg.norm(embedding))
    if not math.isfinite(norm) or norm <= 0:
        raise V6Error("reference speaker embedding is invalid")
    return embedding / norm, record


def _utterance_identity_cosine(audio: Any, reference_unit: Any, extractor: Any) -> float:
    import numpy as np

    embedding = np.asarray(extractor(audio), dtype=np.float32).reshape(-1)
    norm = float(np.linalg.norm(embedding))
    if not math.isfinite(norm) or norm <= 0:
        raise V6Error("utterance speaker embedding is invalid")
    return float(np.dot(embedding / norm, reference_unit))


def _load_failure_log(
    output_root: Path,
    *,
    config: dict[str, Any],
    parent_chain: dict[str, Any],
) -> dict[str, Any]:
    path = output_root / "failed-attempts.v6.receipt.json"
    if not path.exists():
        return {
            "schemaVersion": 1,
            "status": FAILURE_LOG_STATUS,
            "trustDomain": TRUST_DOMAIN,
            "pipelineBinding": pipeline_binding(config),
            "parentChain": parent_chain,
            "entries": [],
            "discardedAudioRetained": False,
            "claimsExcluded": config["claimsExcluded"],
        }
    document = production.load_json(path)
    if (
        document.get("schemaVersion") != 1
        or document.get("status") != FAILURE_LOG_STATUS
        or document.get("trustDomain") != TRUST_DOMAIN
        or document.get("pipelineBinding") != pipeline_binding(config)
        or document.get("parentChain") != parent_chain
        or not isinstance(document.get("entries"), list)
        or document.get("discardedAudioRetained") is not False
        or document.get("claimsExcluded") != config["claimsExcluded"]
    ):
        raise V6Error("V6 failed-attempt log drifted")
    return document


def _write_failure_log(
    output_root: Path,
    document: dict[str, Any],
    *,
    config: dict[str, Any],
) -> None:
    v5.atomic_write_json(
        output_root / "failed-attempts.v6.receipt.json",
        document,
        work_root=work_root(config, create=False),
        confinement_root=output_root,
    )


def _attempts_for_batch(
    failure_log: dict[str, Any], candidate_id: str, batch_index: int
) -> list[dict[str, Any]]:
    entries = [
        item
        for item in failure_log["entries"]
        if item.get("candidateID") == candidate_id
        and item.get("batchIndex") == batch_index
    ]
    if [item.get("attempt") for item in entries] != list(range(1, len(entries) + 1)):
        raise V6Error("discarded V6 attempts are not a deterministic prefix")
    return entries


def _batch_seed(
    candidate: dict[str, Any], batch_index: int, attempt: int, config: dict[str, Any]
) -> int:
    settings = config["generation"]
    return (
        candidate["stressSeed"]
        + settings["batchSeedOffset"]
        + batch_index * settings["batchSeedStride"]
        + (attempt - 1) * settings["attemptSeedStride"]
    )


def _public_utterance(utterance: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in utterance.items() if key != "text"}


def commit_generated_batch(
    *,
    output_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    batch_index: int,
    utterances: list[dict[str, Any]],
    model: Any,
    extractor: Any,
    reference_unit: Any,
    reference_record: dict[str, Any],
    generation_reference_path: Path,
    conditioning_record: dict[str, Any],
    method_evidence: dict[str, Any],
    identity_text: str,
    model_receipt: dict[str, Any],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
    failure_log: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    import mlx.core as mx
    import numpy as np

    prior = _attempts_for_batch(failure_log, candidate_id, batch_index)
    first_attempt = len(prior) + 1
    maximum_attempts = config["generation"]["maximumBatchAttempts"]
    if first_attempt > maximum_attempts:
        raise V6Error(
            f"V6 batch exhausted all documented variants: {candidate_id}/batch-{batch_index:03d}"
        )
    reference_path = v5.confined_path(
        generation_reference_path,
        root=output_root,
        must_exist=True,
        expect_directory=False,
    )
    if file_binding(reference_path) != conditioning_record["conditionedReference"]:
        raise V6Error("V6 generation reference is not the rebuilt conditioned reference")
    for attempt in range(first_attempt, maximum_attempts + 1):
        staging = output_root / ".staging" / candidate_id / f"batch-{batch_index:03d}" / f"attempt-{attempt}"
        staging.parent.mkdir(parents=True, exist_ok=True)
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir()
        seed = _batch_seed(candidate, batch_index, attempt, config)
        production.set_generation_seed(seed)
        results = list(
            model.batch_generate(
                texts=[item["text"] for item in utterances],
                ref_audio=str(reference_path),
                ref_text=identity_text,
                lang_code=production.validate_config()["language"],
                temperature=config["generation"]["temperature"],
                top_k=config["generation"]["topK"],
                top_p=config["generation"]["topP"],
                repetition_penalty=config["generation"][
                    "repetitionPenaltyRequested"
                ],
                max_tokens=config["generation"]["maximumTokens"],
                stream=False,
                verbose=False,
            )
        )
        if (
            len(results) != len(utterances)
            or sorted(item.sequence_idx for item in results)
            != list(range(len(utterances)))
        ):
            raise V6Error("Qwen batch generation returned an incomplete sequence set")
        results_by_index = {item.sequence_idx: item for item in results}
        generated_records: list[dict[str, Any]] = []
        processed_paths: list[Path] = []
        processed_audio: list[Any] = []
        for local_index, utterance in enumerate(utterances):
            result = results_by_index[local_index]
            raw = np.ascontiguousarray(
                np.asarray(result.audio, dtype=np.float32).reshape(-1)
            )
            if (
                int(result.sample_rate) != config["master"]["nativeSampleRate"]
                or int(result.samples) != raw.size
                or raw.size == 0
                or not np.all(np.isfinite(raw))
            ):
                raise V6Error("Qwen batch returned invalid utterance PCM")
            processed, processing = process_utterance_audio(
                raw,
                sample_rate=int(result.sample_rate),
                separator_after=utterance["separatorAfter"],
                config=config,
                normalized_word_count=utterance["normalizedWordCount"],
            )
            raw_path = staging / f"{utterance['utteranceID']}.raw-f32.wav"
            audio_path = staging / f"{utterance['utteranceID']}.audio-f32.wav"
            production.write_float_wav(raw_path, int(result.sample_rate), raw)
            production.write_float_wav(audio_path, int(result.sample_rate), processed)
            raw_decoded, raw_info = v5.read_native_audio(raw_path, config)
            final_decoded, final_info = v5.read_native_audio(audio_path, config)
            if not np.array_equal(raw_decoded, raw) or not np.array_equal(
                final_decoded, processed
            ):
                raise V6Error("utterance WAV serialization changed PCM")
            tokenizer_count, token_cap = _derived_token_cap(
                model, utterance["text"], config
            )
            generated_records.append(
                {
                    "utterance": _public_utterance(utterance),
                    "sequenceIndex": local_index,
                    "tokenizerTokenCount": tokenizer_count,
                    "derivedTokenCap": token_cap,
                    "generatedTokenCount": int(result.token_count),
                    "rawAudio": raw_info,
                    "processedAudio": final_info,
                    "processing": processing,
                }
            )
            processed_paths.append(audio_path)
            processed_audio.append(processed)
        transcript_paths, asr_batch = run_whisper_batch(
            audio_paths=processed_paths, staging=staging, config=config
        )
        destination = output_root / batch_relative(candidate_id, batch_index)
        utterance_records: list[dict[str, Any]] = []
        failed: list[dict[str, Any]] = []
        for local_index, (utterance, generated, audio, generated_transcript) in enumerate(
            zip(
                utterances,
                generated_records,
                processed_audio,
                transcript_paths,
                strict=True,
            )
        ):
            transcript_path = staging / f"{utterance['utteranceID']}.transcript.json"
            os.replace(generated_transcript, transcript_path)
            transcript = production.load_json(transcript_path)
            identity_cosine = _utterance_identity_cosine(
                audio, reference_unit, extractor
            )
            gate = utterance_asr_gate(
                utterance=utterance,
                transcript=transcript,
                duration_seconds=generated["processedAudio"]["sampleCount"]
                / config["master"]["nativeSampleRate"],
                token_count=generated["generatedTokenCount"],
                token_cap=generated["derivedTokenCap"],
                identity_cosine=identity_cosine,
                config=config,
                adaptive_pacing_pass=generated["processing"][
                    "adaptiveSemanticPacing"
                ]["targetReachedBeforeCommitGate"],
            )
            raw_path = staging / f"{utterance['utteranceID']}.raw-f32.wav"
            audio_path = staging / f"{utterance['utteranceID']}.audio-f32.wav"
            record = {
                **generated,
                "rawAudio": {
                    **generated["rawAudio"],
                    "file": _destination_binding(raw_path, destination),
                    "relativePath": (
                        batch_relative(candidate_id, batch_index) / raw_path.name
                    ).as_posix(),
                },
                "processedAudio": {
                    **generated["processedAudio"],
                    "file": _destination_binding(audio_path, destination),
                    "relativePath": (
                        batch_relative(candidate_id, batch_index) / audio_path.name
                    ).as_posix(),
                },
                "transcript": {
                    "file": _destination_binding(transcript_path, destination),
                    "relativePath": (
                        batch_relative(candidate_id, batch_index)
                        / transcript_path.name
                    ).as_posix(),
                },
                "gate": gate,
            }
            utterance_records.append(record)
            if not gate["passes"]:
                failed.append(
                    {
                        "utteranceID": utterance["utteranceID"],
                        "failedGates": sorted(
                            key for key, passed in gate["gates"].items() if not passed
                        ),
                        "rawSHA256": record["rawAudio"]["file"]["sha256"],
                        "processedSHA256": record["processedAudio"]["file"]["sha256"],
                        "transcriptSHA256": record["transcript"]["file"]["sha256"],
                        "gate": gate,
                    }
                )
        asr_log_path = staging / "whisper.batch.log.txt"
        asr_batch["log"] = _destination_binding(asr_log_path, destination)
        asr_batch["inputFiles"] = [
            item["processedAudio"]["file"] for item in utterance_records
        ]
        if failed:
            failure_log["entries"].append(
                {
                    "candidateID": candidate_id,
                    "batchIndex": batch_index,
                    "attempt": attempt,
                    "generationSeed": seed,
                    "failedUtterances": failed,
                    "allAttemptFilesDiscarded": True,
                }
            )
            _write_failure_log(output_root, failure_log, config=config)
            shutil.rmtree(staging)
            mx.clear_cache()
            continue
        receipt = {
            "schemaVersion": 1,
            "status": BATCH_STATUS,
            "trustDomain": TRUST_DOMAIN,
            "createdAt": production.timestamp(),
            "pipelineBinding": pipeline_binding(config),
            "parentChain": parent_chain,
            "negativeEvidence": negative_evidence,
            "referenceTempoMethodEvidence": method_evidence,
            "voiceCloneModel": model_receipt,
            "candidateID": candidate_id,
            "candidateReference": reference_record,
            "generationReferenceConditioning": conditioning_record,
            "candidateReferenceSHA256": parent_candidate["reference"]["sha256"],
            "candidateInstructionSHA256": parent_candidate["instructionSHA256"],
            "batchIndex": batch_index,
            "attempt": attempt,
            "generationSeed": seed,
            "generationSettings": _generation_settings(config),
            "utteranceRecords": utterance_records,
            "inProcessASR": asr_batch,
            "allUtterancesPassedBeforeCommit": True,
            "claimsExcluded": config["claimsExcluded"],
        }
        write_json(staging / "batch.v6.receipt.json", receipt)
        v5.atomic_commit_directory(
            staging,
            destination,
            work_root=work_root(config, create=False),
            output_root=output_root,
        )
        stage_root = output_root / ".staging"
        if stage_root.exists():
            shutil.rmtree(stage_root)
        return (
            validate_batch_commit(
                output_root=output_root,
                candidate_id=candidate_id,
                candidate=candidate,
                parent_candidate=parent_candidate,
                batch_index=batch_index,
                utterances=utterances,
                model=model,
                extractor=extractor,
                reference_unit=reference_unit,
                reference_record=reference_record,
                conditioning_record=conditioning_record,
                method_evidence=method_evidence,
                model_receipt=model_receipt,
                config=config,
                parent_chain=parent_chain,
                negative_evidence=negative_evidence,
            ),
            failure_log,
        )
    raise V6Error(
        f"V6 batch failed every documented variant: {candidate_id}/batch-{batch_index:03d}"
    )


def validate_batch_commit(
    *,
    output_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    batch_index: int,
    utterances: list[dict[str, Any]],
    model: Any,
    extractor: Any,
    reference_unit: Any,
    reference_record: dict[str, Any],
    conditioning_record: dict[str, Any],
    method_evidence: dict[str, Any],
    model_receipt: dict[str, Any],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    root = v5.confined_path(
        output_root / batch_relative(candidate_id, batch_index),
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    expected_names = {"batch.v6.receipt.json", "whisper.batch.log.txt"}
    for utterance in utterances:
        expected_names.update(
            {
                f"{utterance['utteranceID']}.raw-f32.wav",
                f"{utterance['utteranceID']}.audio-f32.wav",
                f"{utterance['utteranceID']}.transcript.json",
            }
        )
    if {item.name for item in root.iterdir()} != expected_names:
        raise V6Error("V6 batch commit contains unexpected files")
    receipt_path = root / "batch.v6.receipt.json"
    receipt = production.load_json(receipt_path)
    attempt = receipt.get("attempt")
    if type(attempt) is not int or not 1 <= attempt <= config["generation"][
        "maximumBatchAttempts"
    ]:
        raise V6Error("V6 batch attempt is invalid")
    expected_seed = _batch_seed(candidate, batch_index, attempt, config)
    records = receipt.get("utteranceRecords")
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("status") != BATCH_STATUS
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("pipelineBinding") != pipeline_binding(config)
        or receipt.get("parentChain") != parent_chain
        or receipt.get("negativeEvidence") != negative_evidence
        or receipt.get("referenceTempoMethodEvidence") != method_evidence
        or receipt.get("voiceCloneModel") != model_receipt
        or receipt.get("candidateID") != candidate_id
        or receipt.get("candidateReference") != reference_record
        or receipt.get("generationReferenceConditioning") != conditioning_record
        or receipt.get("candidateReferenceSHA256")
        != parent_candidate["reference"]["sha256"]
        or receipt.get("candidateInstructionSHA256")
        != parent_candidate["instructionSHA256"]
        or receipt.get("batchIndex") != batch_index
        or receipt.get("generationSeed") != expected_seed
        or receipt.get("generationSettings") != _generation_settings(config)
        or receipt.get("allUtterancesPassedBeforeCommit") is not True
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
        or not isinstance(records, list)
        or len(records) != len(utterances)
    ):
        raise V6Error("V6 batch receipt provenance drifted")
    validated: list[dict[str, Any]] = []
    for local_index, (utterance, record) in enumerate(zip(utterances, records, strict=True)):
        if (
            record.get("utterance") != _public_utterance(utterance)
            or record.get("sequenceIndex") != local_index
        ):
            raise V6Error("V6 committed utterance order drifted")
        tokenizer_count, token_cap = _derived_token_cap(model, utterance["text"], config)
        if (
            record.get("tokenizerTokenCount") != tokenizer_count
            or record.get("derivedTokenCap") != token_cap
            or type(record.get("generatedTokenCount")) is not int
            or record["generatedTokenCount"] <= 0
        ):
            raise V6Error("V6 committed token metadata drifted")
        raw_path = root / f"{utterance['utteranceID']}.raw-f32.wav"
        audio_path = root / f"{utterance['utteranceID']}.audio-f32.wav"
        transcript_path = root / f"{utterance['utteranceID']}.transcript.json"
        for key, path in [
            ("rawAudio", raw_path),
            ("processedAudio", audio_path),
            ("transcript", transcript_path),
        ]:
            binding = record.get(key, {}).get("file")
            if binding != file_binding(path):
                raise V6Error("V6 committed utterance file binding drifted")
        raw, raw_info = v5.read_native_audio(raw_path, config)
        processed, processed_info = v5.read_native_audio(audio_path, config)
        recomputed, processing = process_utterance_audio(
            raw,
            sample_rate=config["master"]["nativeSampleRate"],
            separator_after=utterance["separatorAfter"],
            config=config,
            normalized_word_count=utterance["normalizedWordCount"],
        )
        if (
            record["rawAudio"].get("sampleCount") != raw_info["sampleCount"]
            or record["rawAudio"].get("float32LESHA256")
            != raw_info["float32LESHA256"]
            or record["processedAudio"].get("sampleCount")
            != processed_info["sampleCount"]
            or record["processedAudio"].get("float32LESHA256")
            != processed_info["float32LESHA256"]
            or record.get("processing") != processing
            or not np.array_equal(processed, recomputed)
        ):
            raise V6Error("V6 deterministic utterance processing drifted")
        transcript = production.load_json(transcript_path)
        if not _transcript_document_is_pinned(transcript, config):
            raise V6Error("V6 committed transcript parameters drifted")
        identity_cosine = _utterance_identity_cosine(
            processed, reference_unit, extractor
        )
        gate = utterance_asr_gate(
            utterance=utterance,
            transcript=transcript,
            duration_seconds=processed_info["sampleCount"]
            / config["master"]["nativeSampleRate"],
            token_count=record["generatedTokenCount"],
            token_cap=token_cap,
            identity_cosine=identity_cosine,
            config=config,
            adaptive_pacing_pass=processing[
                "adaptiveSemanticPacing"
            ]["targetReachedBeforeCommitGate"],
        )
        if record.get("gate") != gate or gate["passes"] is not True:
            raise V6Error("V6 committed utterance no longer passes its in-process gate")
        validated.append(
            {
                "utterance": utterance,
                "record": record,
                "rawPath": raw_path,
                "audioPath": audio_path,
                "audio": processed,
                "decoded": processed_info,
                "transcriptPath": transcript_path,
            }
        )
    asr = receipt.get("inProcessASR", {})
    log_path = root / "whisper.batch.log.txt"
    if (
        asr.get("tool") != validate_asr_tools(config)
        or asr.get("arguments") != config["offlineASR"]["arguments"]
        or asr.get("inputCount") != len(utterances)
        or asr.get("inputFiles")
        != [item["record"]["processedAudio"]["file"] for item in validated]
        or asr.get("log") != file_binding(log_path)
        or asr.get("answerPromptUsed") is not False
        or asr.get("externalTranscriptReceiptUsed") is not False
        or asr.get("networkUsed") is not False
    ):
        raise V6Error("V6 committed batch ASR receipt drifted")
    return {
        "receipt": receipt,
        "receiptPath": receipt_path,
        "receiptBinding": file_binding(receipt_path),
        "utterances": validated,
    }


def _render_tempo_corrected_native(
    source: Path,
    destination: Path,
    *,
    tempo_factor: float,
    config: dict[str, Any],
    confinement_root: Path,
) -> None:
    if not 1.0 <= tempo_factor <= config["durationCorrection"]["maximumTempoFactor"]:
        raise V6Error("tempo factor lies outside the frozen natural-prosody bound")
    source = v5.confined_path(
        source,
        root=confinement_root,
        must_exist=True,
        expect_directory=False,
    )
    destination = v5.confined_path(
        destination,
        root=confinement_root,
        must_exist=destination.exists(),
        expect_directory=False if destination.exists() else None,
    )
    if destination.exists():
        raise V6Error("tempo-corrected staging output already exists")
    factor = f"{tempo_factor:.12f}"
    command = [
        config["master"]["ffmpegPath"],
        "-nostdin",
        "-y",
        "-loglevel",
        "error",
        "-i",
        str(source),
        "-map_metadata",
        "-1",
        "-fflags",
        "+bitexact",
        "-flags:a",
        "+bitexact",
        "-af",
        f"atempo={factor}",
        "-ar",
        str(config["master"]["nativeSampleRate"]),
        "-ac",
        "1",
        "-c:a",
        "pcm_f32le",
        str(destination),
    ]
    subprocess.run(command, check=True, capture_output=True)


def _candidate_utterances(
    candidate_id: str,
    batches: list[dict[str, Any]],
    utterances: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    selected = [
        item
        for batch in batches
        if batch["receipt"]["candidateID"] == candidate_id
        for item in batch["utterances"]
    ]
    if [item["utterance"]["utteranceID"] for item in selected] != [
        item["utteranceID"] for item in utterances
    ]:
        raise V6Error(f"V6 candidate utterances are incomplete: {candidate_id}")
    return selected


def _assembly_ranges(
    selected: list[dict[str, Any]],
    cues: list[dict[str, Any]],
    *,
    final_sample_count: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    utterance_ranges: list[dict[str, Any]] = []
    cursor = 0
    for item in selected:
        end = cursor + item["decoded"]["sampleCount"]
        utterance_ranges.append(
            {
                "utteranceID": item["utterance"]["utteranceID"],
                "segmentID": item["utterance"]["segmentID"],
                "pretempoStartSampleInclusive": cursor,
                "pretempoEndSampleExclusive": end,
            }
        )
        cursor = end
    if cursor <= 0 or final_sample_count <= 0:
        raise V6Error("candidate assembly ranges are empty")
    previous = 0
    for index, record in enumerate(utterance_ranges):
        mapped_end = (
            final_sample_count
            if index == len(utterance_ranges) - 1
            else round(record["pretempoEndSampleExclusive"] / cursor * final_sample_count)
        )
        if mapped_end <= previous:
            raise V6Error("duration correction collapsed an utterance range")
        record["startSampleInclusive"] = previous
        record["endSampleExclusive"] = mapped_end
        previous = mapped_end
    cue_ranges: list[dict[str, Any]] = []
    cue_cursor = 0
    for cue in cues:
        own = [
            item for item in utterance_ranges if item["segmentID"] == cue["segmentID"]
        ]
        if not own:
            raise V6Error("cue has no V6 utterances")
        start = own[0]["startSampleInclusive"]
        end = own[-1]["endSampleExclusive"]
        if start != cue_cursor:
            raise V6Error("V6 cue assembly ranges are not contiguous")
        cue_ranges.append(
            {
                "segmentID": cue["segmentID"],
                "startSampleInclusive": start,
                "endSampleExclusive": end,
            }
        )
        cue_cursor = end
    if cue_cursor != final_sample_count:
        raise V6Error("V6 cue ranges do not cover the final assembly")
    return utterance_ranges, cue_ranges


def _seam_audit(audio: Any, selected: list[dict[str, Any]]) -> dict[str, Any]:
    import numpy as np

    material = np.asarray(audio, dtype=np.float32).reshape(-1)
    cursor = 0
    records: list[dict[str, Any]] = []
    for left, right in zip(selected, selected[1:]):
        cursor += left["decoded"]["sampleCount"]
        jump = abs(float(material[cursor]) - float(material[cursor - 1]))
        records.append(
            {
                "leftUtteranceID": left["utterance"]["utteranceID"],
                "rightUtteranceID": right["utterance"]["utteranceID"],
                "sample": cursor,
                "leftSample": float(material[cursor - 1]),
                "rightSample": float(material[cursor]),
                "absoluteDiscontinuity": jump,
                "passes": jump == 0.0,
            }
        )
    passes = bool(
        material.size
        and material[0] == 0.0
        and material[-1] == 0.0
        and all(item["passes"] for item in records)
    )
    return {
        "boundaryCount": len(records),
        "firstSample": float(material[0]),
        "lastSample": float(material[-1]),
        "maximumAbsoluteDiscontinuity": max(
            [item["absoluteDiscontinuity"] for item in records], default=0.0
        ),
        "boundaryRecords": records,
        "passes": passes,
    }


def commit_candidate(
    *,
    output_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    batches: list[dict[str, Any]],
    utterances: list[dict[str, Any]],
    cues: list[dict[str, Any]],
    conditioning_record: dict[str, Any],
    method_evidence: dict[str, Any],
    model_receipt: dict[str, Any],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    selected = _candidate_utterances(candidate_id, batches, utterances)
    pretempo = np.concatenate(
        [np.asarray(item["audio"], dtype=np.float32) for item in selected]
    )
    seam = _seam_audit(pretempo, selected)
    if not seam["passes"]:
        raise V6Error(f"V6 pretempo seams failed: {candidate_id}")
    root = work_root(config, create=False)
    staging = root / f".v6-candidate-stage-{candidate_id}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    committed = False
    try:
        pretempo_path = staging / "pretempo-f32.wav"
        production.write_float_wav(
            pretempo_path, config["master"]["nativeSampleRate"], pretempo
        )
        decoded_pretempo, pretempo_info = v5.read_native_audio(pretempo_path, config)
        if not np.array_equal(decoded_pretempo, pretempo):
            raise V6Error("V6 pretempo WAV changed utterance samples")
        pretempo_duration = (
            pretempo_info["sampleCount"] / config["master"]["nativeSampleRate"]
        )
        correction = config["durationCorrection"]
        if pretempo_duration > correction["hardMaximumUncorrectedSeconds"]:
            raise V6Error(
                f"V6 candidate exceeds bounded natural tempo correction: {candidate_id} "
                f"({pretempo_duration:.3f}s)"
            )
        tempo_factor = (
            pretempo_duration / correction["targetMaximumSeconds"]
            if pretempo_duration > correction["targetMaximumSeconds"]
            else 1.0
        )
        if tempo_factor > correction["maximumTempoFactor"]:
            raise V6Error("V6 candidate requires excessive tempo correction")
        if tempo_factor > 1.0:
            corrected_path = staging / "tempo-corrected-f32.wav"
            _render_tempo_corrected_native(
                pretempo_path,
                corrected_path,
                tempo_factor=tempo_factor,
                config=config,
                confinement_root=staging,
            )
            corrected, corrected_info = v5.read_native_audio(corrected_path, config)
        else:
            corrected = decoded_pretempo
            corrected_info = pretempo_info
        peak = float(np.max(np.abs(corrected)))
        if not math.isfinite(peak) or peak <= 0:
            raise V6Error("V6 corrected candidate audio is silent")
        target_peak = 10 ** (config["master"]["nativeAssemblyPeakDBFS"] / 20)
        common_gain = target_peak / peak
        assembly = np.ascontiguousarray(corrected * common_gain, dtype=np.float32)
        assembly_path = staging / "assembled-f32.wav"
        master_path = staging / "stress.wav"
        production.write_float_wav(
            assembly_path, config["master"]["nativeSampleRate"], assembly
        )
        assembly_audio, assembly_info = v5.read_native_audio(assembly_path, config)
        if not np.array_equal(assembly_audio, assembly):
            raise V6Error("V6 final native assembly changed PCM")
        v5.render_deterministic_master(
            assembly_path, master_path, config, confinement_root=staging
        )
        relation = v5.verify_native_master_relation(
            assembly_path,
            master_path,
            config,
            audit_root=staging,
            confinement_root=root,
        )
        duration_seconds = relation["master"]["durationSeconds"]
        if not v5.stress_duration_gate(duration_seconds, config):
            raise V6Error(
                f"V6 candidate duration is outside 18–22 minutes: {candidate_id} "
                f"({duration_seconds / 60:.3f} minutes)"
            )
        utterance_ranges, cue_ranges = _assembly_ranges(
            selected, cues, final_sample_count=assembly_info["sampleCount"]
        )
        destination = output_root / candidate_relative(candidate_id)
        record = {
            "candidateID": candidate_id,
            "referenceSHA256": parent_candidate["reference"]["sha256"],
            "instructionSHA256": parent_candidate["instructionSHA256"],
            "referenceTempoMethodEvidence": method_evidence,
            "generationReferenceConditioning": conditioning_record,
            "baseStressSeed": candidate["stressSeed"],
            "batchCommitReceipts": [
                batch["receiptBinding"]
                for batch in batches
                if batch["receipt"]["candidateID"] == candidate_id
            ],
            "utteranceCount": len(selected),
            "allUtterancesPassedBeforeAssembly": True,
            "utteranceRanges": utterance_ranges,
            "cueSampleRanges": cue_ranges,
            "pretempoAssembly": {
                "relativePath": (
                    candidate_relative(candidate_id) / "pretempo-f32.wav"
                ).as_posix(),
                "file": _destination_binding(pretempo_path, destination),
                "sampleRate": pretempo_info["sampleRate"],
                "sampleCount": pretempo_info["sampleCount"],
                "float32LESHA256": pretempo_info["float32LESHA256"],
                "decodedDurationSeconds": pretempo_duration,
                "seamAudit": seam,
            },
            "durationCorrection": {
                "applied": tempo_factor > 1.0,
                "tempoFactor": tempo_factor,
                "method": correction["method"],
                "correctedSampleCountBeforeGain": corrected_info["sampleCount"],
                "correctedFloat32LESHA256BeforeGain": corrected_info[
                    "float32LESHA256"
                ],
                "maximumTempoFactor": correction["maximumTempoFactor"],
            },
            "nativeAssembly": {
                "relativePath": (
                    candidate_relative(candidate_id) / "assembled-f32.wav"
                ).as_posix(),
                "file": _destination_binding(assembly_path, destination),
                "sampleRate": assembly_info["sampleRate"],
                "sampleCount": assembly_info["sampleCount"],
                "float32LESHA256": assembly_info["float32LESHA256"],
                "oneCommonNormalizationGain": common_gain,
            },
            "master": {
                "relativePath": (
                    candidate_relative(candidate_id) / "stress.wav"
                ).as_posix(),
                "file": _destination_binding(master_path, destination),
            },
            "masterRelationAtGeneration": {
                "nativeSampleCount": assembly_info["sampleCount"],
                "masterSampleCount": relation["master"]["sampleCount"],
                "decodedDurationDifferenceSamples": relation[
                    "decodedDurationDifferenceSamples"
                ],
                "deterministicRecomputeSHA256": relation[
                    "deterministicRecomputeSHA256"
                ],
                "deterministicByteEquality": relation["deterministicByteEquality"],
            },
            "decodedDurationSeconds": duration_seconds,
            "durationGate18To22Minutes": True,
        }
        receipt = {
            "schemaVersion": 1,
            "status": CANDIDATE_STATUS,
            "trustDomain": TRUST_DOMAIN,
            "createdAt": production.timestamp(),
            "pipelineBinding": pipeline_binding(config),
            "parentChain": parent_chain,
            "negativeEvidence": negative_evidence,
            "voiceCloneModel": model_receipt,
            "record": record,
            "claimsExcluded": config["claimsExcluded"],
        }
        write_json(staging / "candidate.v6.receipt.json", receipt)
        if (staging / "tempo-corrected-f32.wav").exists():
            (staging / "tempo-corrected-f32.wav").unlink()
        v5.atomic_commit_directory(
            staging,
            destination,
            work_root=root,
            output_root=output_root,
        )
        committed = True
    finally:
        if not committed and staging.exists():
            shutil.rmtree(staging)
    return validate_candidate_commit(
        output_root=output_root,
        candidate_id=candidate_id,
        candidate=candidate,
        parent_candidate=parent_candidate,
        batches=batches,
        utterances=utterances,
        cues=cues,
        conditioning_record=conditioning_record,
        method_evidence=method_evidence,
        model_receipt=model_receipt,
        config=config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
    )


def validate_candidate_commit(
    *,
    output_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    batches: list[dict[str, Any]],
    utterances: list[dict[str, Any]],
    cues: list[dict[str, Any]],
    conditioning_record: dict[str, Any],
    method_evidence: dict[str, Any],
    model_receipt: dict[str, Any],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    root = v5.confined_path(
        output_root / candidate_relative(candidate_id),
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    if {item.name for item in root.iterdir()} != {
        "pretempo-f32.wav",
        "assembled-f32.wav",
        "stress.wav",
        "candidate.v6.receipt.json",
    }:
        raise V6Error("V6 candidate commit contains unexpected files")
    receipt_path = root / "candidate.v6.receipt.json"
    receipt = production.load_json(receipt_path)
    record = receipt.get("record", {})
    selected = _candidate_utterances(candidate_id, batches, utterances)
    expected_pretempo = np.concatenate(
        [np.asarray(item["audio"], dtype=np.float32) for item in selected]
    )
    pretempo_path = root / "pretempo-f32.wav"
    assembly_path = root / "assembled-f32.wav"
    master_path = root / "stress.wav"
    pretempo, pretempo_info = v5.read_native_audio(pretempo_path, config)
    assembly, assembly_info = v5.read_native_audio(assembly_path, config)
    if not np.array_equal(pretempo, expected_pretempo):
        raise V6Error("V6 committed pretempo assembly changed utterance PCM")
    seam = _seam_audit(pretempo, selected)
    pretempo_duration = pretempo_info["sampleCount"] / config["master"][
        "nativeSampleRate"
    ]
    correction = config["durationCorrection"]
    tempo_factor = (
        pretempo_duration / correction["targetMaximumSeconds"]
        if pretempo_duration > correction["targetMaximumSeconds"]
        else 1.0
    )
    temporary = work_root(config, create=False) / f".v6-tempo-validate-{candidate_id}.wav"
    if temporary.exists():
        temporary.unlink()
    if tempo_factor > 1.0:
        _render_tempo_corrected_native(
            pretempo_path,
            temporary,
            tempo_factor=tempo_factor,
            config=config,
            confinement_root=work_root(config, create=False),
        )
        corrected, corrected_info = v5.read_native_audio(temporary, config)
        temporary.unlink()
    else:
        corrected, corrected_info = pretempo, pretempo_info
    peak = float(np.max(np.abs(corrected)))
    common_gain = 10 ** (config["master"]["nativeAssemblyPeakDBFS"] / 20) / peak
    expected_assembly = np.ascontiguousarray(corrected * common_gain, dtype=np.float32)
    if not np.array_equal(assembly, expected_assembly):
        raise V6Error("V6 committed native assembly is not deterministic")
    relation = v5.verify_native_master_relation(
        assembly_path,
        master_path,
        config,
        audit_root=work_root(config, create=False),
        confinement_root=work_root(config, create=False),
    )
    duration_seconds = relation["master"]["durationSeconds"]
    utterance_ranges, cue_ranges = _assembly_ranges(
        selected, cues, final_sample_count=assembly_info["sampleCount"]
    )
    expected_record = copy.deepcopy(record)
    expected_record.update(
        {
            "candidateID": candidate_id,
            "referenceSHA256": parent_candidate["reference"]["sha256"],
            "instructionSHA256": parent_candidate["instructionSHA256"],
            "referenceTempoMethodEvidence": method_evidence,
            "generationReferenceConditioning": conditioning_record,
            "baseStressSeed": candidate["stressSeed"],
            "batchCommitReceipts": [
                batch["receiptBinding"]
                for batch in batches
                if batch["receipt"]["candidateID"] == candidate_id
            ],
            "utteranceCount": len(selected),
            "allUtterancesPassedBeforeAssembly": True,
            "utteranceRanges": utterance_ranges,
            "cueSampleRanges": cue_ranges,
            "pretempoAssembly": {
                "relativePath": (
                    candidate_relative(candidate_id) / "pretempo-f32.wav"
                ).as_posix(),
                "file": file_binding(pretempo_path),
                "sampleRate": pretempo_info["sampleRate"],
                "sampleCount": pretempo_info["sampleCount"],
                "float32LESHA256": pretempo_info["float32LESHA256"],
                "decodedDurationSeconds": pretempo_duration,
                "seamAudit": seam,
            },
            "durationCorrection": {
                "applied": tempo_factor > 1.0,
                "tempoFactor": tempo_factor,
                "method": correction["method"],
                "correctedSampleCountBeforeGain": corrected_info["sampleCount"],
                "correctedFloat32LESHA256BeforeGain": corrected_info[
                    "float32LESHA256"
                ],
                "maximumTempoFactor": correction["maximumTempoFactor"],
            },
            "nativeAssembly": {
                "relativePath": (
                    candidate_relative(candidate_id) / "assembled-f32.wav"
                ).as_posix(),
                "file": file_binding(assembly_path),
                "sampleRate": assembly_info["sampleRate"],
                "sampleCount": assembly_info["sampleCount"],
                "float32LESHA256": assembly_info["float32LESHA256"],
                "oneCommonNormalizationGain": common_gain,
            },
            "master": {
                "relativePath": (
                    candidate_relative(candidate_id) / "stress.wav"
                ).as_posix(),
                "file": file_binding(master_path),
            },
            "masterRelationAtGeneration": {
                "nativeSampleCount": assembly_info["sampleCount"],
                "masterSampleCount": relation["master"]["sampleCount"],
                "decodedDurationDifferenceSamples": relation[
                    "decodedDurationDifferenceSamples"
                ],
                "deterministicRecomputeSHA256": relation[
                    "deterministicRecomputeSHA256"
                ],
                "deterministicByteEquality": relation["deterministicByteEquality"],
            },
            "decodedDurationSeconds": duration_seconds,
            "durationGate18To22Minutes": True,
        }
    )
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("status") != CANDIDATE_STATUS
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("pipelineBinding") != pipeline_binding(config)
        or receipt.get("parentChain") != parent_chain
        or receipt.get("negativeEvidence") != negative_evidence
        or receipt.get("voiceCloneModel") != model_receipt
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
        or set(record)
        != {
            "candidateID",
            "referenceSHA256",
            "instructionSHA256",
            "referenceTempoMethodEvidence",
            "generationReferenceConditioning",
            "baseStressSeed",
            "batchCommitReceipts",
            "utteranceCount",
            "allUtterancesPassedBeforeAssembly",
            "utteranceRanges",
            "cueSampleRanges",
            "pretempoAssembly",
            "durationCorrection",
            "nativeAssembly",
            "master",
            "masterRelationAtGeneration",
            "decodedDurationSeconds",
            "durationGate18To22Minutes",
        }
        or record != expected_record
        or not v5.stress_duration_gate(duration_seconds, config)
        or seam["passes"] is not True
    ):
        raise V6Error("V6 candidate commit validation failed")
    return {
        "receipt": receipt,
        "receiptPath": receipt_path,
        "receiptBinding": file_binding(receipt_path),
        "record": record,
        "pretempoPath": pretempo_path,
        "assemblyPath": assembly_path,
        "assemblyAudio": assembly,
        "masterPath": master_path,
        "masterRelation": relation,
        "cueSampleRanges": cue_ranges,
        "cueAudio": [
            (
                cue["segmentID"],
                np.asarray(
                    assembly[
                        cue["startSampleInclusive"] : cue["endSampleExclusive"]
                    ],
                    dtype=np.float32,
                ),
            )
            for cue in cue_ranges
        ],
    }


def validate_generation_inventory(
    output_root: Path,
    *,
    utterances: list[dict[str, Any]],
    config: dict[str, Any],
    require_complete: bool,
) -> None:
    """Reject every unrecognised path before trusting resumable state."""

    expected_root_names = {
        "batch-commits",
        "candidates",
        "conditioned-references",
    }
    optional_root_names = {
        "generation-progress.v6.receipt.json",
        "failed-attempts.v6.receipt.json",
        "stress-set.v6.receipt.json",
    }
    root_names = {item.name for item in output_root.iterdir()}
    if ".staging" in root_names or not root_names <= expected_root_names | optional_root_names:
        raise V6Error("V6 generation root contains staging or unexpected files")
    if not expected_root_names <= root_names:
        raise V6Error("V6 generation root is missing its fixed commit directories")

    batches = batch_specs(utterances, config)
    batch_root = v5.confined_path(
        output_root / "batch-commits",
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    candidate_root = v5.confined_path(
        output_root / "candidates",
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    conditioned_root = v5.confined_path(
        output_root / "conditioned-references",
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    conditioned_names = {item.name for item in conditioned_root.iterdir()}
    if not conditioned_names <= {
        f"{candidate_id}-tempo-1p22.wav" for candidate_id in EXPECTED_FINALISTS
    } or any(item.is_symlink() for item in conditioned_root.iterdir()):
        raise V6Error("V6 conditioned-reference inventory drifted")
    for top, label in [(batch_root, "batch"), (candidate_root, "candidate")]:
        names = {item.name for item in top.iterdir()}
        if not names <= set(EXPECTED_FINALISTS):
            raise V6Error(f"V6 {label} inventory contains an unknown candidate")
    for candidate_id in EXPECTED_FINALISTS:
        candidate_batches = batch_root / candidate_id
        if candidate_batches.exists():
            candidate_batches = v5.confined_path(
                candidate_batches,
                root=batch_root,
                must_exist=True,
                expect_directory=True,
            )
            names = {item.name for item in candidate_batches.iterdir()}
            allowed = {f"batch-{index:03d}" for index in range(len(batches))}
            if not names <= allowed:
                raise V6Error("V6 batch inventory contains an unknown batch")
            for item in candidate_batches.iterdir():
                if not item.is_dir() or item.is_symlink():
                    raise V6Error("V6 batch commit must be a real directory")
        committed_candidate = candidate_root / candidate_id
        if committed_candidate.exists() and (
            not committed_candidate.is_dir() or committed_candidate.is_symlink()
        ):
            raise V6Error("V6 candidate commit must be a real directory")
    if require_complete:
        if "stress-set.v6.receipt.json" not in root_names:
            raise V6Error("complete V6 generation is missing its stress-set receipt")
        for candidate_id in EXPECTED_FINALISTS:
            names = {
                item.name for item in (batch_root / candidate_id).iterdir()
            }
            if names != {f"batch-{index:03d}" for index in range(len(batches))}:
                raise V6Error("complete V6 generation is missing batch commits")
            if not (candidate_root / candidate_id).is_dir():
                raise V6Error("complete V6 generation is missing a candidate commit")
        if conditioned_names != {
            f"{candidate_id}-tempo-1p22.wav" for candidate_id in EXPECTED_FINALISTS
        }:
            raise V6Error("complete V6 generation is missing conditioned references")


def _validate_failure_log(
    output_root: Path,
    *,
    document: dict[str, Any],
    batch_commits: list[dict[str, Any]],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
) -> dict[str, Any]:
    loaded = _load_failure_log(
        output_root, config=config, parent_chain=parent_chain
    )
    if loaded != document:
        raise V6Error("V6 failed-attempt log changed during validation")
    entries = loaded["entries"]
    allowed_keys = {
        (candidate_id, index)
        for candidate_id in EXPECTED_FINALISTS
        for index in range(math.ceil(config["segmentation"]["utteranceCount"] / config["generation"]["batchSize"]))
    }
    for entry in entries:
        key = (entry.get("candidateID"), entry.get("batchIndex"))
        attempt = entry.get("attempt")
        if (
            key not in allowed_keys
            or type(attempt) is not int
            or not 1 <= attempt <= config["generation"]["maximumBatchAttempts"]
            or entry.get("generationSeed")
            != _batch_seed(
                {"stressSeed": production.candidate_by_id(production.validate_config(), key[0])["stressSeed"]},
                key[1],
                attempt,
                config,
            )
            or entry.get("allAttemptFilesDiscarded") is not True
            or not isinstance(entry.get("failedUtterances"), list)
            or not entry["failedUtterances"]
        ):
            raise V6Error("V6 discarded-attempt record is malformed")
        for failed in entry["failedUtterances"]:
            gates = failed.get("gate", {}).get("gates", {})
            failed_gates = sorted(key for key, value in gates.items() if value is False)
            if (
                failed.get("failedGates") != failed_gates
                or not failed_gates
                or failed.get("gate", {}).get("passes") is not False
                or any(
                    type(failed.get(field)) is not str
                    or not re.fullmatch(r"[0-9a-f]{64}", failed[field])
                    for field in ["rawSHA256", "processedSHA256", "transcriptSHA256"]
                )
            ):
                raise V6Error("V6 discarded utterance finding is malformed")
    committed_attempts = {
        (item["receipt"]["candidateID"], item["receipt"]["batchIndex"]): item["receipt"]["attempt"]
        for item in batch_commits
    }
    for key in allowed_keys:
        own = [item for item in entries if (item["candidateID"], item["batchIndex"]) == key]
        attempts = [item["attempt"] for item in own]
        committed_attempt = committed_attempts.get(key)
        expected = (
            list(range(1, committed_attempt))
            if committed_attempt is not None
            else list(range(1, len(attempts) + 1))
        )
        if attempts != expected:
            raise V6Error("V6 first-passing-attempt resume contract drifted")
    return loaded


def _progress_record(
    *,
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
    method_evidence: dict[str, Any],
    conditioning_records: dict[str, dict[str, Any]],
    stress_record: dict[str, Any],
    utterance_record: dict[str, Any],
    model_receipt: dict[str, Any],
    batch_commits: list[dict[str, Any]],
    candidate_commits: list[dict[str, Any]],
    failure_log: dict[str, Any],
    output_root: Path,
) -> dict[str, Any]:
    failure_path = output_root / "failed-attempts.v6.receipt.json"
    expected_batches = len(EXPECTED_FINALISTS) * math.ceil(
        config["segmentation"]["utteranceCount"] / config["generation"]["batchSize"]
    )
    return {
        "schemaVersion": 1,
        "status": PROGRESS_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "updatedAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "negativeEvidence": negative_evidence,
        "referenceTempoMethodEvidence": method_evidence,
        "generationReferenceConditioning": [
            conditioning_records[candidate_id]
            for candidate_id in EXPECTED_FINALISTS
        ],
        "stressText": stress_record,
        "utteranceManifest": utterance_record,
        "voiceCloneModel": model_receipt,
        "provisionalFinalistIDs": EXPECTED_FINALISTS,
        "expectedBatchCount": expected_batches,
        "completedBatchReceipts": [item["receiptBinding"] for item in batch_commits],
        "completedCandidateReceipts": [
            item["receiptBinding"] for item in candidate_commits
        ],
        "failedAttemptCount": len(failure_log["entries"]),
        "failedAttemptLog": file_binding(failure_path) if failure_path.exists() else None,
        "generationComplete": len(batch_commits) == expected_batches
        and len(candidate_commits) == len(EXPECTED_FINALISTS),
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "claimsExcluded": config["claimsExcluded"],
    }


def update_generation_progress(
    *,
    output_root: Path,
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
    method_evidence: dict[str, Any],
    conditioning_records: dict[str, dict[str, Any]],
    stress_record: dict[str, Any],
    utterance_record: dict[str, Any],
    model_receipt: dict[str, Any],
    batch_commits: list[dict[str, Any]],
    candidate_commits: list[dict[str, Any]],
    failure_log: dict[str, Any],
) -> dict[str, Any]:
    record = _progress_record(
        config=config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
        method_evidence=method_evidence,
        conditioning_records=conditioning_records,
        stress_record=stress_record,
        utterance_record=utterance_record,
        model_receipt=model_receipt,
        batch_commits=batch_commits,
        candidate_commits=candidate_commits,
        failure_log=failure_log,
        output_root=output_root,
    )
    v5.atomic_write_json(
        output_root / "generation-progress.v6.receipt.json",
        record,
        work_root=work_root(config, create=False),
        confinement_root=output_root,
    )
    return record


def _generation_context(config: dict[str, Any]) -> dict[str, Any]:
    base_config = production.validate_config()
    base_binding = production.pipeline_binding(base_config)
    candidate_root = repository_path(config["paths"]["candidateSetRoot"], directory=True)
    candidate_set = production.validate_candidate_set(
        candidate_root, base_config, base_binding
    )
    parent_records = {
        candidate_id: candidate_set["recordsByID"][candidate_id]
        for candidate_id in EXPECTED_FINALISTS
    }
    candidates = {
        candidate_id: production.candidate_by_id(base_config, candidate_id)
        for candidate_id in EXPECTED_FINALISTS
    }
    identity_path = repository_path(
        f"native/audio/narration/{base_config['texts']['identityReference']['path']}",
        directory=False,
    )
    identity_text = production.canonical_text(identity_path)
    if production.sha256_text(identity_text) != base_config["texts"]["identityReference"]["textSHA256"]:
        raise V6Error("identity reference text drifted before V6 generation")
    model_directory, model_files = production.verify_model_snapshot(
        base_config["models"]["voiceClone"], offline=True
    )
    return {
        "baseConfig": base_config,
        "candidateRoot": candidate_root,
        "parentRecords": parent_records,
        "candidates": candidates,
        "identityText": identity_text,
        "modelDirectory": model_directory,
        "modelReceipt": production.model_receipt(
            base_config["models"]["voiceClone"], model_files
        ),
    }


def scan_generation_commits(
    *,
    output_root: Path,
    utterances: list[dict[str, Any]],
    cues: list[dict[str, Any]],
    model: Any,
    extractor: Any,
    reference_units: dict[str, Any],
    reference_records: dict[str, Any],
    conditioning_records: dict[str, dict[str, Any]],
    method_evidence: dict[str, Any],
    context: dict[str, Any],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    validate_generation_inventory(
        output_root,
        utterances=utterances,
        config=config,
        require_complete=False,
    )
    specs = batch_specs(utterances, config)
    expected_order = [
        (candidate_id, index)
        for candidate_id in EXPECTED_FINALISTS
        for index in range(len(specs))
    ]
    existing = []
    for candidate_id, index in expected_order:
        if (output_root / batch_relative(candidate_id, index)).exists():
            existing.append((candidate_id, index))
    if existing != expected_order[: len(existing)]:
        raise V6Error("V6 resumable batch commits are not one deterministic prefix")
    batch_commits: list[dict[str, Any]] = []
    for candidate_id, index in existing:
        batch_commits.append(
            validate_batch_commit(
                output_root=output_root,
                candidate_id=candidate_id,
                candidate=context["candidates"][candidate_id],
                parent_candidate=context["parentRecords"][candidate_id],
                batch_index=index,
                utterances=specs[index],
                model=model,
                extractor=extractor,
                reference_unit=reference_units[candidate_id],
                reference_record=reference_records[candidate_id],
                conditioning_record=conditioning_records[candidate_id],
                method_evidence=method_evidence,
                model_receipt=context["modelReceipt"],
                config=config,
                parent_chain=parent_chain,
                negative_evidence=negative_evidence,
            )
        )
    failure_log = _load_failure_log(
        output_root, config=config, parent_chain=parent_chain
    )
    _validate_failure_log(
        output_root,
        document=failure_log,
        batch_commits=batch_commits,
        config=config,
        parent_chain=parent_chain,
    )
    candidate_commits: list[dict[str, Any]] = []
    for finalist_index, candidate_id in enumerate(EXPECTED_FINALISTS):
        path = output_root / candidate_relative(candidate_id)
        if not path.exists():
            continue
        own_batches = [
            item for item in batch_commits if item["receipt"]["candidateID"] == candidate_id
        ]
        if len(own_batches) != len(specs):
            raise V6Error("V6 candidate was committed before all utterance batches")
        if any(
            not (output_root / candidate_relative(prior)).exists()
            for prior in EXPECTED_FINALISTS[:finalist_index]
        ):
            raise V6Error("V6 candidate commits are not a deterministic prefix")
        candidate_commits.append(
            validate_candidate_commit(
                output_root=output_root,
                candidate_id=candidate_id,
                candidate=context["candidates"][candidate_id],
                parent_candidate=context["parentRecords"][candidate_id],
                batches=batch_commits,
                utterances=utterances,
                cues=cues,
                conditioning_record=conditioning_records[candidate_id],
                method_evidence=method_evidence,
                model_receipt=context["modelReceipt"],
                config=config,
                parent_chain=parent_chain,
                negative_evidence=negative_evidence,
            )
        )
    if [item["receipt"]["record"]["candidateID"] for item in candidate_commits] != EXPECTED_FINALISTS[: len(candidate_commits)]:
        raise V6Error("V6 candidate commits are not an ordered prefix")
    return batch_commits, candidate_commits, failure_log


def _load_runtime(context: dict[str, Any]) -> tuple[Any, Any]:
    from mlx_audio.tts.utils import load_model

    model = load_model(str(context["modelDirectory"]))
    if not hasattr(model, "batch_generate") or not hasattr(
        model, "extract_speaker_embedding"
    ):
        raise V6Error("pinned voice-clone model lacks the frozen V6 runtime methods")
    return model, v5.QwenSpeakerExtractor(model)


def _reference_material(
    *, context: dict[str, Any], extractor: Any, config: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    units: dict[str, Any] = {}
    records: dict[str, Any] = {}
    for candidate_id in EXPECTED_FINALISTS:
        unit, record = _reference_unit_embedding(
            candidate_record=context["parentRecords"][candidate_id],
            extractor=extractor,
            config=config,
        )
        units[candidate_id] = unit
        records[candidate_id] = record
    return units, records


def generate_v6(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V6Error("V6 generation requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    parent_chain = validate_parent_chain(config)
    negative_evidence = validate_v5_negative_evidence(config)
    method_evidence = validate_generation_method_evidence(config)
    validate_master_tools(config)
    validate_asr_tools(config)
    _, stress_record, cues, utterances, utterance_record = (
        stress_and_utterance_material(config)
    )
    output_root = prepare_generation_root(args.output, config)
    context = _generation_context(config)
    model, extractor = _load_runtime(context)
    reference_units, reference_records = _reference_material(
        context=context, extractor=extractor, config=config
    )
    conditioned_paths, conditioning_records = prepare_conditioned_references(
        output_root=output_root,
        context=context,
        extractor=extractor,
        original_units=reference_units,
        config=config,
        method_evidence=method_evidence,
    )
    final_path = output_root / "stress-set.v6.receipt.json"
    if final_path.exists():
        result = validate_stress_set(
            output_root,
            config=config,
            parent_chain=parent_chain,
            negative_evidence=negative_evidence,
            context=context,
            model=model,
            extractor=extractor,
            reference_units=reference_units,
            reference_records=reference_records,
            conditioned_paths=conditioned_paths,
            conditioning_records=conditioning_records,
            method_evidence=method_evidence,
        )
        return {
            "status": STRESS_STATUS,
            "resumedExistingCompleteSet": True,
            "receipt": result["receiptBinding"],
            "generationPerformedThisRun": False,
            "networkUsed": False,
            "incrementalCostNOK": 0,
        }

    batch_commits, candidate_commits, failure_log = scan_generation_commits(
        output_root=output_root,
        utterances=utterances,
        cues=cues,
        model=model,
        extractor=extractor,
        reference_units=reference_units,
        reference_records=reference_records,
        conditioning_records=conditioning_records,
        method_evidence=method_evidence,
        context=context,
        config=config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
    )
    update_generation_progress(
        output_root=output_root,
        config=config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
        method_evidence=method_evidence,
        conditioning_records=conditioning_records,
        stress_record=stress_record,
        utterance_record=utterance_record,
        model_receipt=context["modelReceipt"],
        batch_commits=batch_commits,
        candidate_commits=candidate_commits,
        failure_log=failure_log,
    )
    specs = batch_specs(utterances, config)
    completed_keys = {
        (item["receipt"]["candidateID"], item["receipt"]["batchIndex"])
        for item in batch_commits
    }
    performed = False
    for candidate_id in EXPECTED_FINALISTS:
        for batch_index, utterance_batch in enumerate(specs):
            key = (candidate_id, batch_index)
            if key in completed_keys:
                continue
            committed, failure_log = commit_generated_batch(
                output_root=output_root,
                candidate_id=candidate_id,
                candidate=context["candidates"][candidate_id],
                parent_candidate=context["parentRecords"][candidate_id],
                batch_index=batch_index,
                utterances=utterance_batch,
                model=model,
                extractor=extractor,
                reference_unit=reference_units[candidate_id],
                reference_record=reference_records[candidate_id],
                generation_reference_path=conditioned_paths[candidate_id],
                conditioning_record=conditioning_records[candidate_id],
                method_evidence=method_evidence,
                identity_text=context["identityText"],
                model_receipt=context["modelReceipt"],
                config=config,
                parent_chain=parent_chain,
                negative_evidence=negative_evidence,
                failure_log=failure_log,
            )
            batch_commits.append(committed)
            completed_keys.add(key)
            _validate_failure_log(
                output_root,
                document=failure_log,
                batch_commits=batch_commits,
                config=config,
                parent_chain=parent_chain,
            )
            update_generation_progress(
                output_root=output_root,
                config=config,
                parent_chain=parent_chain,
                negative_evidence=negative_evidence,
                method_evidence=method_evidence,
                conditioning_records=conditioning_records,
                stress_record=stress_record,
                utterance_record=utterance_record,
                model_receipt=context["modelReceipt"],
                batch_commits=batch_commits,
                candidate_commits=candidate_commits,
                failure_log=failure_log,
            )
            performed = True
            print(
                f"V6 committed {candidate_id} batch {batch_index + 1}/{len(specs)} "
                f"({len(batch_commits)}/{len(specs) * len(EXPECTED_FINALISTS)} total)",
                file=sys.stderr,
                flush=True,
            )
        if not any(
            item["receipt"]["record"]["candidateID"] == candidate_id
            for item in candidate_commits
        ):
            candidate_commit = commit_candidate(
                output_root=output_root,
                candidate_id=candidate_id,
                candidate=context["candidates"][candidate_id],
                parent_candidate=context["parentRecords"][candidate_id],
                batches=batch_commits,
                utterances=utterances,
                cues=cues,
                conditioning_record=conditioning_records[candidate_id],
                method_evidence=method_evidence,
                model_receipt=context["modelReceipt"],
                config=config,
                parent_chain=parent_chain,
                negative_evidence=negative_evidence,
            )
            candidate_commits.append(candidate_commit)
            update_generation_progress(
                output_root=output_root,
                config=config,
                parent_chain=parent_chain,
                negative_evidence=negative_evidence,
                method_evidence=method_evidence,
                conditioning_records=conditioning_records,
                stress_record=stress_record,
                utterance_record=utterance_record,
                model_receipt=context["modelReceipt"],
                batch_commits=batch_commits,
                candidate_commits=candidate_commits,
                failure_log=failure_log,
            )
            performed = True
            print(
                f"V6 committed complete candidate master {candidate_id}",
                file=sys.stderr,
                flush=True,
            )

    progress_path = output_root / "generation-progress.v6.receipt.json"
    failure_path = output_root / "failed-attempts.v6.receipt.json"
    receipt = {
        "schemaVersion": 1,
        "status": STRESS_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "negativeEvidence": negative_evidence,
        "referenceTempoMethodEvidence": method_evidence,
        "generationReferenceConditioning": [
            conditioning_records[candidate_id]
            for candidate_id in EXPECTED_FINALISTS
        ],
        "generationProgressReceipt": file_binding(progress_path),
        "failedAttemptLog": file_binding(failure_path) if failure_path.exists() else None,
        "voiceCloneModel": context["modelReceipt"],
        "provisionalFinalistIDs": EXPECTED_FINALISTS,
        "stressText": stress_record,
        "utteranceManifest": utterance_record,
        "assemblyPolicy": {
            "semanticUtteranceCountPerCandidate": len(utterances),
            "inProcessWhisperBeforeEveryUtteranceCommit": True,
            "firstPassingBatchAttemptWins": True,
            "failedAttemptAudioDiscarded": True,
            "activityCropAndZeroEdgeFadePerUtterance": True,
            "authoredPausePerUtterance": True,
            "maximumJoinDiscontinuity": 0.0,
            "oneBoundedWholeAssemblyTempoCorrection": True,
            "maximumTempoFactor": config["durationCorrection"]["maximumTempoFactor"],
            "oneCommonNativeAssemblyGain": True,
            "deterministicMaster": True,
        },
        "records": [
            {**item["record"], "candidateCommitReceipt": item["receiptBinding"]}
            for item in candidate_commits
        ],
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }
    v5.atomic_write_json(
        final_path,
        receipt,
        work_root=work_root(config, create=False),
        confinement_root=output_root,
    )
    validated = validate_stress_set(
        output_root,
        config=config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
        context=context,
        model=model,
        extractor=extractor,
        reference_units=reference_units,
        reference_records=reference_records,
        conditioned_paths=conditioned_paths,
        conditioning_records=conditioning_records,
        method_evidence=method_evidence,
    )
    return {
        "status": STRESS_STATUS,
        "resumedExistingCompleteSet": False,
        "receipt": validated["receiptBinding"],
        "generationPerformedThisRun": performed,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }


def validate_stress_set(
    root: Path,
    *,
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    negative_evidence: dict[str, Any],
    context: dict[str, Any] | None = None,
    model: Any | None = None,
    extractor: Any | None = None,
    reference_units: dict[str, Any] | None = None,
    reference_records: dict[str, Any] | None = None,
    conditioned_paths: dict[str, Path] | None = None,
    conditioning_records: dict[str, dict[str, Any]] | None = None,
    method_evidence: dict[str, Any] | None = None,
) -> dict[str, Any]:
    frozen_work_root = work_root(config, create=False)
    root = v5.confined_path(
        root,
        root=frozen_work_root,
        must_exist=True,
        expect_directory=True,
    )
    if root == frozen_work_root or root.parent != frozen_work_root:
        raise V6Error("V6 stress set must be one direct child of its frozen work root")
    text, stress_record, cues, utterances, utterance_record = (
        stress_and_utterance_material(config)
    )
    validate_generation_inventory(
        root, utterances=utterances, config=config, require_complete=True
    )
    receipt_path = root / "stress-set.v6.receipt.json"
    receipt = production.load_json(receipt_path)
    progress_path = root / "generation-progress.v6.receipt.json"
    progress = production.load_json(progress_path)
    context = context or _generation_context(config)
    if model is None or extractor is None:
        model, extractor = _load_runtime(context)
    if reference_units is None or reference_records is None:
        reference_units, reference_records = _reference_material(
            context=context, extractor=extractor, config=config
        )
    method_evidence = method_evidence or validate_generation_method_evidence(
        config
    )
    if conditioned_paths is None or conditioning_records is None:
        conditioned_paths, conditioning_records = prepare_conditioned_references(
            output_root=root,
            context=context,
            extractor=extractor,
            original_units=reference_units,
            config=config,
            method_evidence=method_evidence,
        )
    batch_commits, candidate_commits, failure_log = scan_generation_commits(
        output_root=root,
        utterances=utterances,
        cues=cues,
        model=model,
        extractor=extractor,
        reference_units=reference_units,
        reference_records=reference_records,
        conditioning_records=conditioning_records,
        method_evidence=method_evidence,
        context=context,
        config=config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
    )
    expected_batch_count = len(batch_specs(utterances, config)) * len(EXPECTED_FINALISTS)
    expected_progress_fields = {
        "schemaVersion": 1,
        "status": PROGRESS_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "negativeEvidence": negative_evidence,
        "referenceTempoMethodEvidence": method_evidence,
        "generationReferenceConditioning": [
            conditioning_records[candidate_id]
            for candidate_id in EXPECTED_FINALISTS
        ],
        "stressText": stress_record,
        "utteranceManifest": utterance_record,
        "voiceCloneModel": context["modelReceipt"],
        "provisionalFinalistIDs": EXPECTED_FINALISTS,
        "expectedBatchCount": expected_batch_count,
        "completedBatchReceipts": [item["receiptBinding"] for item in batch_commits],
        "completedCandidateReceipts": [item["receiptBinding"] for item in candidate_commits],
        "failedAttemptCount": len(failure_log["entries"]),
        "failedAttemptLog": file_binding(root / "failed-attempts.v6.receipt.json")
        if (root / "failed-attempts.v6.receipt.json").exists()
        else None,
        "generationComplete": True,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "claimsExcluded": config["claimsExcluded"],
    }
    if set(progress) != set(expected_progress_fields) | {"updatedAt"} or any(
        progress.get(key) != value for key, value in expected_progress_fields.items()
    ) or type(progress.get("updatedAt")) is not str:
        raise V6Error("V6 complete generation progress receipt drifted")
    failure_path = root / "failed-attempts.v6.receipt.json"
    assembly_policy = {
        "semanticUtteranceCountPerCandidate": len(utterances),
        "inProcessWhisperBeforeEveryUtteranceCommit": True,
        "firstPassingBatchAttemptWins": True,
        "failedAttemptAudioDiscarded": True,
        "activityCropAndZeroEdgeFadePerUtterance": True,
        "authoredPausePerUtterance": True,
        "maximumJoinDiscontinuity": 0.0,
        "oneBoundedWholeAssemblyTempoCorrection": True,
        "maximumTempoFactor": config["durationCorrection"]["maximumTempoFactor"],
        "oneCommonNativeAssemblyGain": True,
        "deterministicMaster": True,
    }
    expected_records = [
        {**item["record"], "candidateCommitReceipt": item["receiptBinding"]}
        for item in candidate_commits
    ]
    expected_receipt_fields = {
        "schemaVersion": 1,
        "status": STRESS_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "negativeEvidence": negative_evidence,
        "referenceTempoMethodEvidence": method_evidence,
        "generationReferenceConditioning": [
            conditioning_records[candidate_id]
            for candidate_id in EXPECTED_FINALISTS
        ],
        "generationProgressReceipt": file_binding(progress_path),
        "failedAttemptLog": file_binding(failure_path) if failure_path.exists() else None,
        "voiceCloneModel": context["modelReceipt"],
        "provisionalFinalistIDs": EXPECTED_FINALISTS,
        "stressText": stress_record,
        "utteranceManifest": utterance_record,
        "assemblyPolicy": assembly_policy,
        "records": expected_records,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }
    if set(receipt) != set(expected_receipt_fields) | {"createdAt"} or any(
        receipt.get(key) != value for key, value in expected_receipt_fields.items()
    ) or type(receipt.get("createdAt")) is not str:
        raise V6Error("V6 stress-set receipt contract or lineage drifted")
    rejected_hash = config["negativeEvidence"]["v5AuditReceiptSHA256"]
    if rejected_hash in canonical_json(parent_chain):
        raise V6Error("rejected V5 stress evidence became a V6 artifact parent")
    return {
        "receipt": receipt,
        "receiptPath": receipt_path,
        "receiptBinding": file_binding(receipt_path),
        "stressText": text,
        "stressTextRecord": stress_record,
        "utteranceManifest": utterance_record,
        "utterances": utterances,
        "cues": cues,
        "batchCommits": batch_commits,
        "candidateCommits": candidate_commits,
        "recordsByID": {
            item["record"]["candidateID"]: item for item in candidate_commits
        },
        "context": context,
        "model": model,
        "extractor": extractor,
        "referenceUnits": reference_units,
        "referenceRecords": reference_records,
        "conditionedPaths": conditioned_paths,
        "conditioningRecords": conditioning_records,
        "referenceTempoMethodEvidence": method_evidence,
    }


def _candidate_rank_key(record: dict[str, Any]) -> tuple[Any, ...]:
    alignment = record["cueAlignment"]["cueRecords"]
    identity = record["voiceIdentity"]
    return (
        0 if record["passesCompleteV6MachineGate"] else 1,
        -min(item["exactReferenceCoverage"] for item in alignment),
        record["wholeMasterAlignment"]["wordAlignmentErrorRate"],
        -min(
            item["minimumWindowToReferenceCosine"]
            for item in identity["cueRecords"]
        ),
        record["repetition"]["excessOccurrenceFraction"],
        record["candidateID"],
    )


def audit_v6(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V6Error("V6 audit requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    parent_chain = validate_parent_chain(config)
    negative_evidence = validate_v5_negative_evidence(config)
    master_tools = validate_master_tools(config)
    asr_tools = validate_asr_tools(config)
    audit_root = prepare_audit_root(args.output, config)
    transcript_root = audit_root / "transcripts"
    transcript_root.mkdir()
    stress_set = validate_stress_set(
        args.stress_set,
        config=config,
        parent_chain=parent_chain,
        negative_evidence=negative_evidence,
    )
    reference_words = v5.normalize_words(stress_set["stressText"])
    candidate_records: list[dict[str, Any]] = []
    for candidate_id in EXPECTED_FINALISTS:
        source = stress_set["recordsByID"][candidate_id]
        record = source["record"]
        master_relation = v5.verify_native_master_relation(
            source["assemblyPath"],
            source["masterPath"],
            config,
            audit_root=audit_root,
            confinement_root=work_root(config, create=False),
        )
        duration_seconds = master_relation["master"]["durationSeconds"]
        duration_gate = v5.stress_duration_gate(duration_seconds, config)
        parent = stress_set["context"]["parentRecords"][candidate_id]
        reference_audio, reference_record = v5._load_reference_audio(
            Path(parent["_verifiedReferencePath"]),
            config["master"]["nativeSampleRate"],
        )
        identity = v5.audit_voice_identity(
            reference_audio=reference_audio,
            cue_audio=source["cueAudio"],
            sample_rate=config["master"]["nativeSampleRate"],
            extractor=stress_set["extractor"],
            config=config,
        )
        transcript_path, asr_run = v5.run_pinned_whisper(
            master_path=source["masterPath"],
            output_prefix=transcript_root / candidate_id,
            config=config,
            confinement_root=work_root(config, create=False),
        )
        transcript = production.load_json(transcript_path)
        timed_words, grouping = v5.timed_words_from_whisper(
            transcript, master_duration_ms=duration_seconds * 1000
        )
        hypothesis_words = [item.text for item in timed_words]
        steps, whole_alignment = v5.monotone_global_alignment(
            reference_words, hypothesis_words
        )
        cue_alignment = v5.project_alignment_to_cues(
            reference_words=reference_words,
            hypothesis_words=timed_words,
            steps=steps,
            cues=stress_set["cues"],
            cue_sample_ranges=source["cueSampleRanges"],
            sample_rate=config["master"]["nativeSampleRate"],
            config=config,
        )
        repetition = v5.reference_aware_repetition(
            reference_words, hypothesis_words, config
        )
        tempo = v5.cue_tempo_audit(
            stress_set["cues"],
            source["cueSampleRanges"],
            config["master"]["nativeSampleRate"],
            config,
        )
        silence = v5.silence_audit(
            source["assemblyAudio"],
            sample_rate=config["master"]["nativeSampleRate"],
            cue_sample_ranges=source["cueSampleRanges"],
            config=config,
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
            <= config["durationCorrection"]["maximumTempoFactor"]
            and record["pretempoAssembly"]["decodedDurationSeconds"]
            <= config["durationCorrection"]["hardMaximumUncorrectedSeconds"]
        )
        seam = record["pretempoAssembly"]["seamAudit"]
        gates = {
            "allUtterancesPassedBeforeCommit": all_utterance_gates,
            "pretempoSeams": seam["passes"],
            "boundedWholeAssemblyTempoCorrection": bounded_correction,
            "decodedDuration18To22Minutes": duration_gate,
            "deterministicNativeToMaster": master_relation[
                "deterministicByteEquality"
            ],
            "voiceIdentity": identity["passes"],
            "cueAlignment": cue_alignment["allCuesPass"],
            "referenceAwareRepetition": repetition["passes"],
            "cueTempo": tempo["passes"],
            "silence": silence["passes"],
        }
        candidate_records.append(
            {
                "candidateID": candidate_id,
                "reference": reference_record,
                "nativeAssembly": file_binding(source["assemblyPath"]),
                "master": file_binding(source["masterPath"]),
                "masterRelation": master_relation,
                "decodedDurationSeconds": duration_seconds,
                "decodedDurationGate18To22Minutes": duration_gate,
                "utteranceGateSummary": {
                    "utteranceCount": len(stress_set["utterances"]),
                    "allPassedBeforeCommit": all_utterance_gates,
                    "batchCommitCount": len(
                        [
                            batch
                            for batch in stress_set["batchCommits"]
                            if batch["receipt"]["candidateID"] == candidate_id
                        ]
                    ),
                },
                "pretempoSeamAudit": seam,
                "durationCorrection": correction,
                "voiceIdentity": identity,
                "inProcessWholeMasterASR": asr_run,
                "timedWordGrouping": grouping,
                "wholeMasterAlignment": whole_alignment,
                "cueAlignment": cue_alignment,
                "repetition": repetition,
                "cueTempo": tempo,
                "silence": silence,
                "gates": gates,
                "passesCompleteV6MachineGate": all(gates.values()),
                "editorVoiceSelection": False,
                "artisticApproval": False,
                "shippingApproval": False,
            }
        )
        print(
            f"V6 audited complete master {candidate_id}: "
            f"{'PASS' if all(gates.values()) else 'FAIL'}",
            file=sys.stderr,
            flush=True,
        )
    ranking = sorted(candidate_records, key=_candidate_rank_key)
    passing = [
        item["candidateID"]
        for item in ranking
        if item["passesCompleteV6MachineGate"]
    ]
    receipt = {
        "schemaVersion": 1,
        "status": AUDIT_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "negativeEvidence": negative_evidence,
        "referenceTempoMethodEvidence": stress_set[
            "referenceTempoMethodEvidence"
        ],
        "generationReferenceConditioning": [
            stress_set["conditioningRecords"][candidate_id]
            for candidate_id in EXPECTED_FINALISTS
        ],
        "stressSetReceipt": stress_set["receiptBinding"],
        "stressText": stress_set["stressTextRecord"],
        "utteranceManifest": stress_set["utteranceManifest"],
        "masterTools": master_tools,
        "asrTools": asr_tools,
        "externalTranscriptReceiptUsed": False,
        "candidateRecords": candidate_records,
        "ranking": [
            {
                "rank": index,
                "candidateID": item["candidateID"],
                "passesCompleteV6MachineGate": item[
                    "passesCompleteV6MachineGate"
                ],
            }
            for index, item in enumerate(ranking, start=1)
        ],
        "passingCandidateIDs": passing,
        "machineLeadingPassingCandidateID": passing[0] if passing else None,
        "machineResultMeaning": (
            "A candidate appears here only after every frozen V6 machine gate passes. "
            "It is not an editor selection, artistic approval, or shipping approval."
        ),
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "claimsExcluded": config["claimsExcluded"],
    }
    receipt_path = audit_root / "audit.v6.receipt.json"
    write_json(receipt_path, receipt)
    return {**receipt, "receipt": file_binding(receipt_path)}


def validate_only(config: dict[str, Any], *, offline: bool) -> dict[str, Any]:
    if offline is not True:
        raise V6Error("V6 validation requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    parent_chain = validate_parent_chain(config)
    negative_evidence = validate_v5_negative_evidence(config)
    method_evidence = validate_generation_method_evidence(config)
    _, stress_record, cues, utterances, utterance_record = (
        stress_and_utterance_material(config)
    )
    context = _generation_context(config)
    return {
        "schemaVersion": 1,
        "status": METHOD_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "negativeEvidence": negative_evidence,
        "referenceTempoMethodEvidence": method_evidence,
        "stressText": stress_record,
        "cueCount": len(cues),
        "utteranceManifest": utterance_record,
        "batchCountPerCandidate": len(batch_specs(utterances, config)),
        "masterTools": validate_master_tools(config),
        "asrTools": validate_asr_tools(config),
        "voiceCloneModel": context["modelReceipt"],
        "voiceCloneModelDirectory": str(context["modelDirectory"]),
        "generationCommandAvailable": True,
        "generationExecuted": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Frozen offline non-shipping V6 narration stress method"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser(
        "validate", help="validate the frozen V6 method without generating audio"
    )
    validate.add_argument("--offline", action="store_true", required=True)
    generate = subparsers.add_parser(
        "generate", help="resume or create the two-candidate V6 utterance set"
    )
    generate.add_argument("--output", type=Path, required=True)
    generate.add_argument("--offline", action="store_true", required=True)
    audit = subparsers.add_parser(
        "audit", help="audit two complete V6 stress masters in-process"
    )
    audit.add_argument("--stress-set", type=Path, required=True)
    audit.add_argument("--output", type=Path, required=True)
    audit.add_argument("--offline", action="store_true", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        config = load_config()
        if args.command == "validate":
            result = validate_only(config, offline=args.offline)
        elif args.command == "generate":
            result = generate_v6(args, config)
        elif args.command == "audit":
            result = audit_v6(args, config)
        else:
            raise V6Error(f"unsupported V6 command: {args.command}")
    except (
        V6Error,
        v5.V5Error,
        production.PipelineError,
        subprocess.CalledProcessError,
        OSError,
        ValueError,
    ) as error:
        print(f"V6 narration method failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
