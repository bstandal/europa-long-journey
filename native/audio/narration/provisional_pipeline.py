#!/usr/bin/env python3
"""Offline, non-shipping narration audit and stress-production trust domain.

This module can rank machine-audited candidates and create provisional stress
tests.  Its records are deliberately incompatible with the editor-selection
record accepted by ``pipeline.py``.  Nothing produced here is an editor,
artistic, word-accuracy, pronunciation or shipping approval.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

import pipeline as production


HERE = Path(__file__).resolve().parent
REPOSITORY_ROOT = HERE.parents[2]
CONFIG_PATH = HERE / "provisional-audit-config.json"
SCRIPT_PATH = Path(__file__).resolve()
TRUST_DOMAIN = "CODEX_PROVISIONAL_NON_SHIPPING"
EXPECTED_IDS = production.EXPECTED_CANDIDATE_IDS


class ProvisionalError(RuntimeError):
    """A fail-closed provisional-audit error."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def file_binding(path: Path) -> dict[str, Any]:
    path = path.resolve()
    if not path.is_file():
        raise ProvisionalError(f"missing file: {path}")
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": production.sha256_file(path),
    }


def native_float32_bytes(audio: Any) -> bytes:
    import numpy as np

    material = np.ascontiguousarray(np.asarray(audio).reshape(-1), dtype="<f4")
    if material.size == 0 or not np.all(np.isfinite(material)):
        raise ProvisionalError("native audio must be finite, non-empty float32")
    return material.tobytes(order="C")


def native_float32_sha256(audio: Any) -> str:
    return hashlib.sha256(native_float32_bytes(audio)).hexdigest()


def assemble_native_segments(
    segments: list[Any], target_dbfs: float
) -> tuple[Any, dict[str, Any]]:
    import numpy as np

    if not segments:
        raise ProvisionalError("cannot assemble an empty cue sequence")
    material = [
        np.ascontiguousarray(np.asarray(segment).reshape(-1), dtype=np.float32)
        for segment in segments
    ]
    if any(segment.size == 0 or not np.all(np.isfinite(segment)) for segment in material):
        raise ProvisionalError("cue generation returned invalid native samples")
    boundaries: list[dict[str, int]] = []
    cursor = 0
    raw_digest = hashlib.sha256()
    for order, segment in enumerate(material, start=1):
        start = cursor
        cursor += int(segment.size)
        raw_digest.update(native_float32_bytes(segment))
        boundaries.append(
            {
                "order": order,
                "startSampleInclusive": start,
                "endSampleExclusive": cursor,
                "sampleCount": int(segment.size),
            }
        )
    concatenated = np.concatenate(material).astype(np.float32, copy=False)
    if raw_digest.hexdigest() != native_float32_sha256(concatenated):
        raise ProvisionalError("sample-for-sample cue concatenation failed")
    normalized, gain = production.normalize_candidate(concatenated, target_dbfs)
    return normalized, {
        "rawConcatenatedSampleCount": int(concatenated.size),
        "rawConcatenatedFloat32LESHA256": native_float32_sha256(concatenated),
        "normalizedFloat32LESHA256": native_float32_sha256(normalized),
        "oneCommonNormalizationGain": gain,
        "boundaries": boundaries,
        "sampleCuts": 0,
        "insertedSilenceSamples": 0,
        "crossfades": 0,
        "fades": 0,
        "timeStretchApplied": False,
        "perSegmentGainChanges": 0,
    }


def speaker_embedding(model: Any, audio: Any) -> tuple[dict[str, Any], Any]:
    import mlx.core as mx
    import numpy as np

    material = np.ascontiguousarray(np.asarray(audio).reshape(-1), dtype=np.float32)
    embedding = np.asarray(
        model.extract_speaker_embedding(mx.array(material)), dtype=np.float32
    ).reshape(-1)
    norm = float(np.linalg.norm(embedding))
    if embedding.size == 0 or not np.all(np.isfinite(embedding)) or norm <= 0:
        raise ProvisionalError("speaker encoder returned an invalid embedding")
    unit = embedding / norm
    return {
        "dimension": int(embedding.size),
        "float32LESHA256": native_float32_sha256(embedding),
        "l2Norm": round(norm, 9),
    }, unit


def voice_consistency_record(
    *,
    reference_embedding: tuple[dict[str, Any], Any],
    segment_embeddings: list[tuple[dict[str, Any], Any]],
    segment_ids: list[str],
    config: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    if len(segment_embeddings) != len(segment_ids) or len(segment_ids) < 2:
        raise ProvisionalError("voice-consistency inventory is invalid")
    reference_record, reference_unit = reference_embedding
    segment_records: list[dict[str, Any]] = []
    reference_cosines: list[float] = []
    for segment_id, (record, unit) in zip(
        segment_ids, segment_embeddings, strict=True
    ):
        cosine = float(np.dot(reference_unit, unit))
        reference_cosines.append(cosine)
        segment_records.append(
            {
                "segmentID": segment_id,
                "embedding": record,
                "cosineToFrozenReference": round(cosine, 9),
            }
        )
    pairwise: list[dict[str, Any]] = []
    for left in range(len(segment_embeddings)):
        for right in range(left + 1, len(segment_embeddings)):
            cosine = float(
                np.dot(segment_embeddings[left][1], segment_embeddings[right][1])
            )
            pairwise.append(
                {
                    "leftSegmentID": segment_ids[left],
                    "rightSegmentID": segment_ids[right],
                    "cosine": round(cosine, 9),
                }
            )
    limits = config["voiceConsistency"]
    minimum_reference = min(reference_cosines)
    minimum_pairwise = min(item["cosine"] for item in pairwise)
    gates = {
        "segmentToReference": minimum_reference
        >= limits["minimumSegmentToReferenceCosine"],
        "pairwiseSegments": minimum_pairwise
        >= limits["minimumPairwiseSegmentCosine"],
    }
    return {
        "method": limits["method"],
        "referenceEmbedding": reference_record,
        "segmentEmbeddings": segment_records,
        "pairwiseSegmentCosines": pairwise,
        "minimumSegmentToReferenceCosine": round(minimum_reference, 9),
        "requiredMinimumSegmentToReferenceCosine": limits[
            "minimumSegmentToReferenceCosine"
        ],
        "minimumPairwiseSegmentCosine": round(minimum_pairwise, 9),
        "requiredMinimumPairwiseSegmentCosine": limits[
            "minimumPairwiseSegmentCosine"
        ],
        "gates": gates,
        "passesFrozenIdentityDriftScreen": all(gates.values()),
        "methodLimit": limits["methodLimit"],
    }


def load_provisional_config(path: Path = CONFIG_PATH) -> dict[str, Any]:
    path = path.resolve()
    if path.parent != HERE or path.name != CONFIG_PATH.name:
        raise ProvisionalError("provisional config must remain in the narration tree")
    config = production.load_json(path)
    if config.get("schemaVersion") != 2:
        raise ProvisionalError("unsupported provisional-audit schema")
    if config.get("status") != TRUST_DOMAIN or config.get("trustDomain") != TRUST_DOMAIN:
        raise ProvisionalError("provisional trust domain drifted")
    if config.get("language") != "English" or config.get("locale") != "en-GB":
        raise ProvisionalError("language or locale drifted")
    excluded = config.get("claimsExcluded")
    required_exclusions = {
        "editor voice selection",
        "final word-accuracy approval",
        "final pronunciation approval",
        "artistic approval",
        "shipping approval",
    }
    if not isinstance(excluded, list) or set(excluded) != required_exclusions:
        raise ProvisionalError("approval exclusions drifted")
    candidate_set = config.get("candidateSet", {})
    if (
        candidate_set.get("candidateCount") != 6
        or not production.HEX_64.fullmatch(candidate_set.get("receiptSHA256", ""))
        or not isinstance(candidate_set.get("receiptBytes"), int)
        or candidate_set["receiptBytes"] <= 0
    ):
        raise ProvisionalError("candidate-set binding is invalid")
    asr = config.get("offlineASR", {})
    if (
        asr.get("engine") != "whisper.cpp"
        or asr.get("version") != "1.9.1"
        or asr.get("model") != "Whisper large-v3"
        or asr.get("answerPromptProhibited") is not True
        or not production.HEX_64.fullmatch(asr.get("executableSHA256", ""))
        or not production.HEX_64.fullmatch(asr.get("modelSHA256", ""))
    ):
        raise ProvisionalError("offline ASR contract drifted")
    rubric = config.get("auditRubric", {})
    weights = rubric.get("scoreWeights", {})
    if set(weights) != {
        "wordAlignment",
        "referenceCoverage",
        "repetition",
        "pronunciationRecognition",
        "technicalIntegrity",
        "cadenceSignals",
    } or sum(weights.values()) != 100:
        raise ProvisionalError("audit score weights must remain an exact 100 points")
    if rubric.get("stressMaster") != {
        "maximumWordAlignmentErrorRate": 0.05,
        "minimumReferenceExactMatchCoverage": 0.96,
        "maximumNonmatchingReferenceRunWords": 12,
        "maximumNonmatchingHypothesisRunWords": 24,
        "maximumRepeatedTokenCoverage": 0.02,
        "maximumRepeatedNgramOccurrences": 3,
    }:
        raise ProvisionalError("whole-master ASR gates drifted")
    terms = config.get("pronunciationTerms")
    if not isinstance(terms, list) or len(terms) < 40 or len(set(terms)) != len(terms):
        raise ProvisionalError("pronunciation-recognition inventory drifted")
    stress = config.get("stressText", {})
    expected_segment_groups = [
        ["contract-01", "contract-02", "contract-03"],
        ["contract-04", "contract-05", "contract-06"],
        ["contract-07", "contract-08", "contract-09"],
        ["contract-10", "contract-11", "contract-12"],
        ["contract-13", "contract-14"],
        ["contract-15", "contract-16"],
    ]
    segment_specs = stress.get("segments")
    if (
        stress.get("assemblyMode") != "CUE_SEGMENTED_CONTINUOUS_MASTER"
        or stress.get("uninterruptedAuditionMasterRequired") is not True
        or stress.get("singleModelCallRequired") is not False
        or stress.get("nativeSampleRate") != 24000
        or stress.get("minimumActualMinutes") != 18
        or stress.get("maximumActualMinutes") != 22
        or stress.get("wordCount") != 3400
        or stress.get("completeContractIDs")
        != [f"contract-{index:02d}" for index in range(1, 17)]
        or not isinstance(segment_specs, list)
        or [item.get("segmentID") for item in segment_specs]
        != [f"cue-{index:02d}" for index in range(1, 7)]
        or [item.get("contractIDs") for item in segment_specs]
        != expected_segment_groups
        or [item.get("wordCount") for item in segment_specs]
        != [483, 579, 655, 652, 523, 508]
        or [item.get("seedOffset") for item in segment_specs]
        != [100, 200, 300, 400, 500, 600]
        or [item.get("maxTokens") for item in segment_specs]
        != [3140, 3764, 4258, 4238, 3400, 3302]
        or any(
            not production.HEX_64.fullmatch(item.get("textSHA256", ""))
            for item in segment_specs
        )
        or stress.get("prohibitedAssemblyOperations")
        != [
            "sample cuts",
            "inserted silence",
            "crossfades",
            "fades",
            "time stretching",
            "per-segment gain changes",
        ]
    ):
        raise ProvisionalError("stress contract drifted")
    consistency = config.get("voiceConsistency", {})
    if (
        consistency.get("minimumSegmentToReferenceCosine") != 0.96
        or consistency.get("minimumPairwiseSegmentCosine") != 0.985
        or set(consistency.get("referenceCalibration", {}))
        != {"voice-candidate-05", "voice-candidate-06"}
    ):
        raise ProvisionalError("voice-consistency gate drifted")
    calibration = config.get("calibrationEvidence", {})
    if (
        calibration.get("status") != "REJECTED_OVERLONG_NON_SHIPPING_CALIBRATION"
        or calibration.get("sharedTextWordCount") != 3400
        or calibration.get("stressSetReceiptBytes") != 7478
        or not production.HEX_64.fullmatch(
            calibration.get("stressSetReceiptSHA256", "")
        )
        or [item.get("candidateID") for item in calibration.get("records", [])]
        != ["voice-candidate-05", "voice-candidate-06"]
        or any(
            item.get("durationSeconds") != 1600.0
            or not production.HEX_64.fullmatch(item.get("audioSHA256", ""))
            for item in calibration.get("records", [])
        )
    ):
        raise ProvisionalError("rejected calibration evidence drifted")
    rejected = config.get("rejectedSingleCallEvidence", {})
    if (
        rejected.get("status")
        != "REJECTED_TOKEN_LIMIT_REPETITION_NON_SHIPPING"
        or rejected.get("sharedTextWordCount") != 2620
        or rejected.get("stressSetReceiptBytes") != 8225
        or rejected.get("transcriptRunReceiptBytes") != 3509
        or rejected.get("stressAuditReceiptBytes") != 169042
        or any(
            not production.HEX_64.fullmatch(rejected.get(key, ""))
            for key in [
                "stressSetReceiptSHA256",
                "transcriptRunReceiptSHA256",
                "stressAuditReceiptSHA256",
            ]
        )
        or [item.get("candidateID") for item in rejected.get("records", [])]
        != ["voice-candidate-05", "voice-candidate-06"]
        or [item.get("firstIncorrectAudioMilliseconds") for item in rejected["records"]]
        != [52460, 233640]
        or any(
            item.get("maximumRepeatedSixGramOccurrences", 0) < 600
            or not production.HEX_64.fullmatch(item.get("audioSHA256", ""))
            or not production.HEX_64.fullmatch(item.get("transcriptSHA256", ""))
            for item in rejected["records"]
        )
    ):
        raise ProvisionalError("rejected single-call evidence drifted")
    config["_path"] = str(path)
    return config


def validate_exact_file(path: Path, *, byte_count: int, digest: str, label: str) -> None:
    if not path.is_file():
        raise ProvisionalError(f"{label} is missing: {path}")
    if path.stat().st_size != byte_count or production.sha256_file(path) != digest:
        raise ProvisionalError(f"{label} byte binding failed")


def validate_asr_tools(
    config: dict[str, Any], executable: Path, model: Path
) -> dict[str, Any]:
    executable = executable.resolve()
    model = model.resolve()
    asr = config["offlineASR"]
    validate_exact_file(
        executable,
        byte_count=asr["executableBytes"],
        digest=asr["executableSHA256"],
        label="whisper.cpp executable",
    )
    validate_exact_file(
        model,
        byte_count=asr["modelBytes"],
        digest=asr["modelSHA256"],
        label="Whisper model",
    )
    version_run = subprocess.run(
        [str(executable), "--version"], check=True, capture_output=True, text=True
    )
    version_material = version_run.stdout + "\n" + version_run.stderr
    expected_line = f"whisper.cpp version: {asr['version']}"
    if expected_line not in version_material:
        raise ProvisionalError(f"expected {expected_line}")
    return {
        "engine": asr["engine"],
        "version": asr["version"],
        "executable": file_binding(executable),
        "modelName": asr["model"],
        "model": file_binding(model),
        "arguments": asr["arguments"],
        "answerPromptUsed": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }


def provisional_binding(config: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 2,
        "trustDomain": TRUST_DOMAIN,
        "provisionalPipeline": file_binding(SCRIPT_PATH),
        "provisionalConfig": file_binding(Path(config["_path"])),
    }


def validate_candidate_set(
    candidate_root: Path, config: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    base_config = production.validate_config()
    base_binding = production.pipeline_binding(base_config)
    candidate_set = production.validate_candidate_set(
        candidate_root.resolve(), base_config, base_binding
    )
    expected = config["candidateSet"]
    if (
        candidate_set["receiptSHA256"] != expected["receiptSHA256"]
        or candidate_set["receiptBytes"] != expected["receiptBytes"]
        or candidate_set["receipt"].get("candidateCount") != expected["candidateCount"]
    ):
        raise ProvisionalError("candidate set is not the frozen six-candidate object")
    return base_config, candidate_set


def _stress_material(
    config: dict[str, Any],
) -> tuple[str, dict[str, Any], list[dict[str, Any]]]:
    contract = config["stressText"]
    source = (REPOSITORY_ROOT / contract["sourcePath"]).resolve()
    try:
        source.relative_to(REPOSITORY_ROOT)
    except ValueError as error:
        raise ProvisionalError("stress source escaped the repository") from error
    validate_exact_file(
        source,
        byte_count=contract["sourceBytes"],
        digest=contract["sourceSHA256"],
        label="approved chapter-contract source",
    )
    document = production.load_json(source)
    if document.get("status") != contract["sourceStatus"]:
        raise ProvisionalError("stress source is no longer editor-approved")
    by_id = {item.get("contractID"): item for item in document.get("contracts", [])}
    paragraphs: list[str] = []
    contract_text_by_id: dict[str, str] = {}
    source_segments: list[dict[str, Any]] = []
    for contract_id in contract["completeContractIDs"]:
        chapter = by_id.get(contract_id)
        if not chapter or chapter.get("editorApproval") != "APPROVED":
            raise ProvisionalError(f"stress source chapter is not approved: {contract_id}")
        locked = set(chapter.get("lockedOnApproval", []))
        required_locked = {
            "thesis",
            "causalSpine",
            "governingJudgement",
            "ending",
            "handoff",
        }
        if not required_locked.issubset(locked):
            raise ProvisionalError(f"stress source fields are not locked: {contract_id}")
        values = [
            chapter["thesis"],
            *chapter["causalSpine"],
            chapter["governingJudgement"],
            f"{chapter['ending']['period']}. {chapter['ending']['title']}",
            chapter["ending"]["consequence"],
            chapter["handoff"],
        ]
        chapter_paragraphs: list[str] = []
        for value in values:
            if not isinstance(value, str) or not value.strip():
                raise ProvisionalError(f"empty stress segment in {contract_id}")
            material = value.strip()
            paragraphs.append(material)
            chapter_paragraphs.append(material)
            source_segments.append(
                {
                    "contractID": contract_id,
                    "sha256": production.sha256_text(material),
                    "wordCount": production.word_count(material),
                }
            )
        contract_text_by_id[contract_id] = "\n\n".join(chapter_paragraphs)
    text = "\n\n".join(paragraphs)
    if production.word_count(text) != contract["wordCount"]:
        raise ProvisionalError("stress text word count drifted")
    cue_segments: list[dict[str, Any]] = []
    cue_manifest: list[dict[str, Any]] = []
    for order, specification in enumerate(contract["segments"], start=1):
        cue_text = "\n\n".join(
            contract_text_by_id[contract_id]
            for contract_id in specification["contractIDs"]
        )
        cue_record = {
            "segmentID": specification["segmentID"],
            "order": order,
            "contractIDs": specification["contractIDs"],
            "textSHA256": production.sha256_text(cue_text),
            "wordCount": production.word_count(cue_text),
            "seedOffset": specification["seedOffset"],
            "maxTokens": specification["maxTokens"],
        }
        if (
            cue_record["textSHA256"] != specification["textSHA256"]
            or cue_record["wordCount"] != specification["wordCount"]
        ):
            raise ProvisionalError(
                f"stress cue binding drifted: {specification['segmentID']}"
            )
        cue_manifest.append(cue_record)
        cue_segments.append({**cue_record, "text": cue_text})
    if "\n\n".join(item["text"] for item in cue_segments) != text:
        raise ProvisionalError("stress cue assembly does not reproduce the shared text")
    record = {
        "source": file_binding(source),
        "sourceStatus": document["status"],
        "textSHA256": production.sha256_text(text),
        "wordCount": production.word_count(text),
        "sourceFieldSegmentCount": len(source_segments),
        "sourceSegmentManifestSHA256": production.sha256_text(
            canonical_json(source_segments)
        ),
        "completeContractIDs": contract["completeContractIDs"],
        "fieldsInOrder": contract["fieldsInOrder"],
        "assemblyMode": contract["assemblyMode"],
        "cueCount": len(cue_manifest),
        "cueManifest": cue_manifest,
        "cueManifestSHA256": production.sha256_text(canonical_json(cue_manifest)),
    }
    return text, record, cue_segments


def stress_text(config: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    text, record, _ = _stress_material(config)
    return text, record


def stress_cue_segments(config: dict[str, Any]) -> list[dict[str, Any]]:
    _, _, segments = _stress_material(config)
    return segments


def prepare_empty_directory(path: Path) -> Path:
    path = path.resolve()
    if path in {REPOSITORY_ROOT, Path.home().resolve()}:
        raise ProvisionalError("refusing broad output directory")
    if path.exists() and any(path.iterdir()):
        raise ProvisionalError(f"output directory must be absent or empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path


def run_whisper(
    *,
    executable: Path,
    model: Path,
    arguments: list[str],
    input_path: Path,
    output_prefix: Path,
) -> Path:
    command = [
        str(executable.resolve()),
        "--model",
        str(model.resolve()),
        *arguments,
        "--output-file",
        str(output_prefix.resolve()),
        str(input_path.resolve()),
    ]
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    output_path = output_prefix.with_suffix(".json")
    if not output_path.is_file():
        raise ProvisionalError(f"Whisper did not create {output_path}")
    transcript = production.load_json(output_path)
    if transcript.get("result", {}).get("language") != "en":
        raise ProvisionalError(f"unexpected transcript language: {output_path}")
    if transcript.get("params", {}).get("translate") is not False:
        raise ProvisionalError(f"translation was unexpectedly enabled: {output_path}")
    if transcript.get("params", {}).get("model") != str(model.resolve()):
        raise ProvisionalError(f"transcript model binding drifted: {output_path}")
    log_path = output_prefix.with_suffix(".whisper.log.txt")
    log_path.write_text(completed.stdout + completed.stderr, encoding="utf-8")
    return output_path


def transcribe_candidates(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    _, candidate_set = validate_candidate_set(args.candidate_set, config)
    tools = validate_asr_tools(config, args.whisper, args.model)
    output = prepare_empty_directory(args.output)
    records: list[dict[str, Any]] = []
    for candidate_id in EXPECTED_IDS:
        audio_record = candidate_set["recordsByID"][candidate_id]["casting"]
        audio_path = Path(audio_record["path"]).resolve()
        transcript_path = run_whisper(
            executable=args.whisper,
            model=args.model,
            arguments=config["offlineASR"]["arguments"],
            input_path=audio_path,
            output_prefix=output / candidate_id,
        )
        records.append(
            {
                "candidateID": candidate_id,
                "audio": file_binding(audio_path),
                "transcript": file_binding(transcript_path),
                "log": file_binding(output / f"{candidate_id}.whisper.log.txt"),
            }
        )
    receipt = {
        "schemaVersion": 1,
        "status": TRUST_DOMAIN,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "purpose": "UNPROMPTED_OFFLINE_MACHINE_TRANSCRIPTION_OF_SIX_CASTING_READINGS",
        "candidateSetReceipt": {
            "sha256": candidate_set["receiptSHA256"],
            "bytes": candidate_set["receiptBytes"],
        },
        "tools": tools,
        "records": records,
        "claimsExcluded": config["claimsExcluded"],
    }
    write_json(output / "transcript-run.receipt.json", receipt)
    return receipt


NORMALIZATION_REPLACEMENTS = {
    "centre": "center",
    "centres": "centers",
    "defence": "defense",
    "travelled": "traveled",
    "tenth": "10th",
    "kiev": "kyiv",
}


def normalize_words(value: str) -> list[str]:
    value = value.lower().replace("’", "'").replace("‘", "'")
    value = re.sub(r"(?<=\d),(?=\d)", "", value)
    value = re.sub(r"[^a-z0-9']+", " ", value)
    result: list[str] = []
    for token in value.split():
        if token.endswith("'s"):
            token = token[:-2]
        elif token.endswith("s'"):
            token = token[:-1]
        token = NORMALIZATION_REPLACEMENTS.get(token, token)
        result.append(token)
    return result


def edit_alignment(reference: list[str], hypothesis: list[str]) -> dict[str, Any]:
    matcher = difflib.SequenceMatcher(None, reference, hypothesis, autojunk=False)
    substitutions = deletions = insertions = equal = 0
    events: list[dict[str, Any]] = []
    maximum_reference_run = maximum_hypothesis_run = 0
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        reference_count = i2 - i1
        hypothesis_count = j2 - j1
        if tag == "equal":
            equal += reference_count
            continue
        if tag == "replace":
            common = min(reference_count, hypothesis_count)
            substitutions += common
            deletions += reference_count - common
            insertions += hypothesis_count - common
        elif tag == "delete":
            deletions += reference_count
        elif tag == "insert":
            insertions += hypothesis_count
        maximum_reference_run = max(maximum_reference_run, reference_count)
        maximum_hypothesis_run = max(maximum_hypothesis_run, hypothesis_count)
        if len(events) < 80:
            events.append(
                {
                    "operation": tag,
                    "referenceWordOffset": i1,
                    "hypothesisWordOffset": j1,
                    "reference": " ".join(reference[i1:i2]),
                    "hypothesis": " ".join(hypothesis[j1:j2]),
                }
            )
    errors = substitutions + deletions + insertions
    return {
        "referenceWords": len(reference),
        "recognizedWords": len(hypothesis),
        "equalWords": equal,
        "substitutions": substitutions,
        "deletions": deletions,
        "insertions": insertions,
        "wordAlignmentErrorRate": round(errors / max(1, len(reference)), 6),
        "referenceExactMatchCoverage": round(equal / max(1, len(reference)), 6),
        "maximumNonmatchingReferenceRunWords": maximum_reference_run,
        "maximumNonmatchingHypothesisRunWords": maximum_hypothesis_run,
        "alignmentMethod": "Python difflib.SequenceMatcher(autojunk=False), frozen normalization v1",
        "events": events,
    }


def repeated_ngram_metrics(words: list[str], size: int, minimum: int) -> dict[str, Any]:
    locations: dict[tuple[str, ...], list[int]] = {}
    for index in range(max(0, len(words) - size + 1)):
        key = tuple(words[index : index + size])
        locations.setdefault(key, []).append(index)
    repeated = [(key, starts) for key, starts in locations.items() if len(starts) >= minimum]
    covered: set[int] = set()
    for _, starts in repeated:
        for start in starts:
            covered.update(range(start, min(len(words), start + size)))
    repeated.sort(key=lambda item: (-len(item[1]), item[0]))
    return {
        "ngramSize": size,
        "minimumOccurrences": minimum,
        "repeatedTokenCoverage": round(len(covered) / max(1, len(words)), 6),
        "maximumOccurrences": max((len(starts) for _, starts in repeated), default=1),
        "topRepeatedNgrams": [
            {"text": " ".join(key), "occurrences": len(starts), "starts": starts[:20]}
            for key, starts in repeated[:12]
        ],
    }


def character_distance(left: str, right: str) -> int:
    if len(left) < len(right):
        left, right = right, left
    previous = list(range(len(right) + 1))
    for left_index, left_char in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_char in enumerate(right, start=1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[right_index] + 1,
                    previous[right_index - 1] + (left_char != right_char),
                )
            )
        previous = current
    return previous[-1]


def pronunciation_recognition(terms: list[str], hypothesis: list[str]) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    for term in terms:
        expected = normalize_words(term)
        expected_joined = "".join(expected)
        best_ratio = 1.0
        best_material = ""
        minimum_window = max(1, len(expected) - 1)
        maximum_window = len(expected) + 1
        for window_size in range(minimum_window, maximum_window + 1):
            for start in range(max(0, len(hypothesis) - window_size + 1)):
                material_words = hypothesis[start : start + window_size]
                material = "".join(material_words)
                ratio = character_distance(expected_joined, material) / max(
                    len(expected_joined), len(material), 1
                )
                if ratio < best_ratio:
                    best_ratio = ratio
                    best_material = " ".join(material_words)
        recognized = best_ratio <= 0.38
        records.append(
            {
                "term": term,
                "recognized": recognized,
                "closestTranscriptMaterial": best_material,
                "normalizedCharacterDistance": round(best_ratio, 6),
            }
        )
    recognized_count = sum(item["recognized"] for item in records)
    return {
        "termCount": len(records),
        "recognizedCount": recognized_count,
        "recognitionRecall": round(recognized_count / max(1, len(records)), 6),
        "methodLimit": "Orthographic ASR recognition is a pronunciation-risk screen, not phonetic or editor approval.",
        "terms": records,
    }


def pronunciation_terms_present(terms: list[str], reference_text: str) -> list[str]:
    reference = normalize_words(reference_text)
    present: list[str] = []
    for term in terms:
        expected = normalize_words(term)
        if any(
            reference[start : start + len(expected)] == expected
            for start in range(max(0, len(reference) - len(expected) + 1))
        ):
            present.append(term)
    if not present:
        raise ProvisionalError("stress text contains no pronunciation-screen terms")
    return present


def contiguous_regions(mask: Any, hop_seconds: float, minimum_seconds: float) -> list[tuple[int, int, float]]:
    import numpy as np

    padded = np.concatenate(([False], mask.astype(bool), [False]))
    changes = np.diff(padded.astype(np.int8))
    starts = np.flatnonzero(changes == 1)
    ends = np.flatnonzero(changes == -1)
    regions: list[tuple[int, int, float]] = []
    for start, end in zip(starts, ends, strict=True):
        duration = (end - start) * hop_seconds
        if duration >= minimum_seconds:
            regions.append((int(start), int(end), float(duration)))
    return regions


def coefficient_of_variation(values: Iterable[float]) -> float:
    material = list(values)
    if not material:
        return 0.0
    mean = sum(material) / len(material)
    if mean == 0:
        return 0.0
    variance = sum((value - mean) ** 2 for value in material) / len(material)
    return math.sqrt(variance) / mean


def pitch_track(audio: Any, sample_rate: int) -> tuple[Any, Any]:
    import numpy as np

    frame_length = int(round(sample_rate * 0.04))
    hop = int(round(sample_rate * 0.05))
    starts = np.arange(0, max(0, len(audio) - frame_length + 1), hop, dtype=np.int64)
    f0 = np.full(len(starts), np.nan, dtype=np.float32)
    confidence = np.zeros(len(starts), dtype=np.float32)
    minimum_lag = max(1, int(sample_rate / 400))
    maximum_lag = min(frame_length - 2, int(sample_rate / 65))
    window = np.hanning(frame_length).astype(np.float32)
    batch_size = 2000
    for offset in range(0, len(starts), batch_size):
        batch_starts = starts[offset : offset + batch_size]
        frames = np.stack([audio[start : start + frame_length] for start in batch_starts])
        rms = np.sqrt(np.mean(frames * frames, axis=1) + 1e-12)
        frames = (frames - frames.mean(axis=1, keepdims=True)) * window
        spectrum = np.fft.rfft(frames, n=1024, axis=1)
        autocorrelation = np.fft.irfft(spectrum * np.conj(spectrum), n=1024, axis=1)
        baseline = np.maximum(autocorrelation[:, 0], 1e-12)
        search = autocorrelation[:, minimum_lag : maximum_lag + 1]
        local = np.argmax(search, axis=1)
        peaks = search[np.arange(len(search)), local] / baseline
        lags = local + minimum_lag
        voiced = (rms >= 10 ** (-42 / 20)) & (peaks >= 0.30)
        target = slice(offset, offset + len(batch_starts))
        f0[target][voiced] = sample_rate / lags[voiced]
        confidence[target] = peaks
    return f0, confidence


def terminal_contour_duplicate_rate(f0: Any, pause_regions: list[tuple[int, int, float]]) -> dict[str, Any]:
    import numpy as np

    contours: list[Any] = []
    for pause_start, _, duration in pause_regions:
        if duration < 0.25:
            continue
        material = f0[max(0, pause_start - 20) : pause_start]
        material = material[np.isfinite(material)]
        if len(material) < 6:
            continue
        source_x = np.linspace(0, 1, len(material))
        contour = np.interp(np.linspace(0, 1, 12), source_x, 12 * np.log2(material))
        contour -= contour.mean()
        contours.append(contour)
    pair_count = 0
    duplicate_count = 0
    for left in range(len(contours)):
        for right in range(left + 1, len(contours)):
            pair_count += 1
            rmse = float(np.sqrt(np.mean((contours[left] - contours[right]) ** 2)))
            if rmse <= 0.35:
                duplicate_count += 1
    return {
        "contourCount": len(contours),
        "pairCount": pair_count,
        "nearDuplicatePairCount": duplicate_count,
        "nearDuplicatePairRate": round(duplicate_count / max(1, pair_count), 6),
        "screeningThresholdSemitonesRMSE": 0.35,
    }


def analyze_audio(path: Path) -> dict[str, Any]:
    import numpy as np
    from scipy import signal
    from scipy.io import wavfile

    path = path.resolve()
    decode = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-i", str(path), "-f", "null", "-"],
        capture_output=True,
        text=True,
    )
    if decode.returncode != 0:
        raise ProvisionalError(f"FFmpeg decode failed for {path}: {decode.stderr}")
    sample_rate, raw = wavfile.read(path)
    if raw.ndim != 1 or raw.dtype != np.int32 or sample_rate != 48000:
        raise ProvisionalError(f"unexpected WAV sample representation: {path}")
    audio = raw.astype(np.float32) / float(2**31)
    duration = len(audio) / sample_rate
    peak = float(np.max(np.abs(audio)))
    dc_offset = float(np.mean(audio, dtype=np.float64))
    clipping = int(np.count_nonzero(np.abs(audio) >= 0.999))
    discontinuity_count = 0
    maximum_difference = 0.0
    block = 2_000_000
    previous: float | None = None
    for offset in range(0, len(audio), block):
        material = audio[offset : offset + block]
        if previous is not None and len(material):
            boundary = abs(float(material[0]) - previous)
            maximum_difference = max(maximum_difference, boundary)
            discontinuity_count += int(boundary >= 0.35)
        if len(material) > 1:
            differences = np.abs(np.diff(material))
            maximum_difference = max(maximum_difference, float(np.max(differences)))
            discontinuity_count += int(np.count_nonzero(differences >= 0.35))
        if len(material):
            previous = float(material[-1])
    downsampled = signal.resample_poly(audio, 1, 6).astype(np.float32)
    analysis_rate = sample_rate // 6
    rms_frame = int(round(analysis_rate * 0.02))
    rms_hop = int(round(analysis_rate * 0.01))
    squared = downsampled.astype(np.float64) ** 2
    cumulative = np.concatenate(([0.0], np.cumsum(squared)))
    rms_starts = np.arange(0, max(0, len(downsampled) - rms_frame + 1), rms_hop)
    rms = np.sqrt(
        (cumulative[rms_starts + rms_frame] - cumulative[rms_starts]) / rms_frame + 1e-15
    )
    silence_regions_rms = contiguous_regions(rms < 10 ** (-45 / 20), 0.01, 0.12)
    f0, f0_confidence = pitch_track(downsampled, analysis_rate)
    voiced = f0[np.isfinite(f0)]
    pause_durations = [item[2] for item in silence_regions_rms]
    contours = terminal_contour_duplicate_rate(f0, silence_regions_rms)
    if len(voiced):
        p05, median, p95 = [float(value) for value in np.percentile(voiced, [5, 50, 95])]
        pitch_span = 12 * math.log2(p95 / p05) if p05 > 0 else 0.0
    else:
        p05 = median = p95 = pitch_span = 0.0
    pause_cv = coefficient_of_variation(pause_durations)
    cadence_score = 0.0
    cadence_score += 0.4 * min(1.0, pitch_span / 8.0)
    cadence_score += 0.3 * min(1.0, pause_cv / 0.8)
    cadence_score += 0.3 * (1.0 - contours["nearDuplicatePairRate"])
    return {
        "file": file_binding(path),
        "decodeErrors": 0,
        "sampleRate": sample_rate,
        "channels": 1,
        "sampleRepresentation": "signed-int32-container-with-24-valid-PCM-bits",
        "durationSeconds": round(duration, 6),
        "peakDBFS": round(20 * math.log10(max(peak, 1e-12)), 3),
        "absoluteDCOffset": round(abs(dc_offset), 9),
        "clippingSampleCount": clipping,
        "largeSampleDiscontinuityCount": discontinuity_count,
        "maximumAdjacentSampleDifference": round(maximum_difference, 6),
        "silence": {
            "thresholdDBFS": -45,
            "minimumRegionSeconds": 0.12,
            "regionCount": len(pause_durations),
            "totalSeconds": round(sum(pause_durations), 6),
            "medianSeconds": round(float(np.median(pause_durations)), 6)
            if pause_durations
            else 0.0,
            "p95Seconds": round(float(np.percentile(pause_durations, 95)), 6)
            if pause_durations
            else 0.0,
            "maximumSeconds": round(max(pause_durations), 6) if pause_durations else 0.0,
            "durationCoefficientOfVariation": round(pause_cv, 6),
        },
        "pitch": {
            "method": "8-kHz 40-ms autocorrelation frames at 50-ms hop",
            "voicedFrameCount": int(len(voiced)),
            "medianAutocorrelationConfidence": round(
                float(np.median(f0_confidence[f0_confidence >= 0.30])), 6
            )
            if np.any(f0_confidence >= 0.30)
            else 0.0,
            "p05Hz": round(p05, 3),
            "medianHz": round(median, 3),
            "p95Hz": round(p95, 3),
            "p05ToP95SemitoneSpan": round(pitch_span, 6),
        },
        "terminalCadence": contours,
        "cadenceSignalScore01": round(cadence_score, 6),
        "methodLimits": [
            "Waveform screens can detect clipping, discontinuities, silence and repeated contours; they cannot certify naturalness or exclude every metallic timbre.",
            "Pitch and cadence values are comparative machine signals, not an artistic judgment.",
        ],
    }


def transcript_text(path: Path) -> tuple[str, dict[str, Any]]:
    document = production.load_json(path)
    if document.get("result", {}).get("language") != "en":
        raise ProvisionalError(f"non-English transcript: {path}")
    segments = document.get("transcription")
    if not isinstance(segments, list) or not segments:
        raise ProvisionalError(f"empty transcript: {path}")
    text = " ".join(item.get("text", "") for item in segments).strip()
    probabilities: list[float] = []
    zero_duration_segments = 0
    for segment in segments:
        offsets = segment.get("offsets", {})
        if offsets.get("to", 0) <= offsets.get("from", 0):
            zero_duration_segments += 1
        for token in segment.get("tokens", []):
            material = token.get("text", "")
            if material.startswith("[_"):
                continue
            probability = token.get("p")
            if isinstance(probability, (int, float)):
                probabilities.append(float(probability))
    probabilities.sort()
    return text, {
        "segmentCount": len(segments),
        "zeroDurationSegmentCount": zero_duration_segments,
        "meanTokenProbability": round(sum(probabilities) / max(1, len(probabilities)), 6),
        "p05TokenProbability": round(
            probabilities[max(0, int(len(probabilities) * 0.05) - 1)], 6
        )
        if probabilities
        else 0.0,
    }


def validate_transcript_receipt(
    root: Path,
    *,
    expected_audio: dict[str, Path],
    config: dict[str, Any],
    purpose: str,
) -> dict[str, Any]:
    root = root.resolve()
    receipt_path = root / "transcript-run.receipt.json"
    receipt = production.load_json(receipt_path)
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("status") != TRUST_DOMAIN
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("purpose") != purpose
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
    ):
        raise ProvisionalError("transcript receipt trust or purpose drifted")
    tools = receipt.get("tools", {})
    asr = config["offlineASR"]
    if (
        tools.get("engine") != asr["engine"]
        or tools.get("version") != asr["version"]
        or tools.get("arguments") != asr["arguments"]
        or tools.get("answerPromptUsed") is not False
        or tools.get("networkUsed") is not False
        or tools.get("incrementalCostNOK") != 0
        or tools.get("executable", {}).get("sha256") != asr["executableSHA256"]
        or tools.get("model", {}).get("sha256") != asr["modelSHA256"]
    ):
        raise ProvisionalError("transcript tool binding drifted")
    records = receipt.get("records")
    if not isinstance(records, list) or [item.get("candidateID") for item in records] != list(expected_audio):
        raise ProvisionalError("transcript candidate inventory drifted")
    result: dict[str, Any] = {}
    for record in records:
        candidate_id = record["candidateID"]
        audio = expected_audio[candidate_id].resolve()
        transcript = root / f"{candidate_id}.json"
        log = root / f"{candidate_id}.whisper.log.txt"
        for label, path in [("audio", audio), ("transcript", transcript), ("log", log)]:
            expected = record.get(label, {})
            if (
                not path.is_file()
                or path.stat().st_size != expected.get("bytes")
                or production.sha256_file(path) != expected.get("sha256")
            ):
                raise ProvisionalError(f"transcript {label} binding failed: {candidate_id}")
        result[candidate_id] = {
            "transcript": transcript,
            "transcriptBinding": file_binding(transcript),
            "logBinding": file_binding(log),
        }
    return {
        "receipt": receipt,
        "receiptBinding": file_binding(receipt_path),
        "records": result,
    }


def candidate_score(
    metrics: dict[str, Any], config: dict[str, Any]
) -> tuple[float, dict[str, float]]:
    weights = config["auditRubric"]["scoreWeights"]
    alignment = metrics["wordAccuracy"]
    repetition = metrics["repetition"]
    pronunciation = metrics["pronunciationRecognition"]
    signal = metrics["signal"]
    components = {
        "wordAlignment": weights["wordAlignment"]
        * max(0.0, 1.0 - alignment["wordAlignmentErrorRate"] / 0.30),
        "referenceCoverage": weights["referenceCoverage"]
        * alignment["referenceExactMatchCoverage"],
        "repetition": weights["repetition"]
        * max(0.0, 1.0 - repetition["repeatedTokenCoverage"]),
        "pronunciationRecognition": weights["pronunciationRecognition"]
        * pronunciation["recognitionRecall"],
        "technicalIntegrity": weights["technicalIntegrity"]
        * float(
            signal["decodeErrors"] == 0
            and signal["clippingSampleCount"] == 0
            and signal["largeSampleDiscontinuityCount"] == 0
        ),
        "cadenceSignals": weights["cadenceSignals"] * signal["cadenceSignalScore01"],
    }
    return round(sum(components.values()), 6), {
        key: round(value, 6) for key, value in components.items()
    }


def analyze_record(
    *,
    audio_path: Path,
    transcript_path: Path,
    reference_text: str,
    config: dict[str, Any],
    pronunciation_terms: list[str] | None = None,
) -> dict[str, Any]:
    recognized_text, asr_quality = transcript_text(transcript_path)
    reference_words = normalize_words(reference_text)
    recognized_words = normalize_words(recognized_text)
    alignment = edit_alignment(reference_words, recognized_words)
    rubric = config["auditRubric"]
    repetition = repeated_ngram_metrics(
        recognized_words,
        rubric["repeatedNgramSize"],
        rubric["repeatedNgramMinimumOccurrences"],
    )
    pronunciation = pronunciation_recognition(
        pronunciation_terms or config["pronunciationTerms"], recognized_words
    )
    signal = analyze_audio(audio_path)
    metrics = {
        "wordAccuracy": alignment,
        "repetition": repetition,
        "pronunciationRecognition": pronunciation,
        "asrQuality": asr_quality,
        "signal": signal,
    }
    gates = {
        "wordAlignment": alignment["wordAlignmentErrorRate"]
        <= rubric["maximumWordAlignmentErrorRateForStress"],
        "repetition": repetition["repeatedTokenCoverage"]
        <= rubric["maximumRepeatedTokenCoverageForStress"],
        "silence": signal["silence"]["maximumSeconds"]
        <= rubric["maximumSingleSilenceSecondsForStress"],
        "dcOffset": signal["absoluteDCOffset"] <= rubric["maximumAbsoluteDCOffset"],
        "pronunciationRecognition": pronunciation["recognitionRecall"]
        >= rubric["minimumPronunciationRecognitionRecallForStress"],
        "decode": signal["decodeErrors"] == 0,
        "clipping": signal["clippingSampleCount"] == 0,
        "sampleDiscontinuity": signal["largeSampleDiscontinuityCount"] == 0,
    }
    score, components = candidate_score(metrics, config)
    return {
        "metrics": metrics,
        "stressEligibilityGates": gates,
        "eligibleForProvisionalStress": all(gates.values()),
        "machineScore100": score,
        "scoreComponents": components,
        "editorOrShippingEligibility": False,
    }


def audit_candidates(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    _, candidate_set = validate_candidate_set(args.candidate_set, config)
    expected_audio = {
        candidate_id: Path(candidate_set["recordsByID"][candidate_id]["casting"]["path"])
        for candidate_id in EXPECTED_IDS
    }
    transcript_set = validate_transcript_receipt(
        args.transcripts,
        expected_audio=expected_audio,
        config=config,
        purpose="UNPROMPTED_OFFLINE_MACHINE_TRANSCRIPTION_OF_SIX_CASTING_READINGS",
    )
    reference_text = production.canonical_text(HERE / "casting-passage-v1.txt")
    records: list[dict[str, Any]] = []
    for candidate_id in EXPECTED_IDS:
        result = analyze_record(
            audio_path=expected_audio[candidate_id],
            transcript_path=transcript_set["records"][candidate_id]["transcript"],
            reference_text=reference_text,
            config=config,
        )
        result.update(
            {
                "candidateID": candidate_id,
                "audio": file_binding(expected_audio[candidate_id]),
                "transcript": transcript_set["records"][candidate_id]["transcriptBinding"],
            }
        )
        records.append(result)
    ranking = sorted(records, key=lambda item: (-item["machineScore100"], item["candidateID"]))
    eligible = [item for item in ranking if item["eligibleForProvisionalStress"]]
    if len(eligible) < 2:
        raise ProvisionalError(
            "fewer than two candidates passed the frozen machine gates; no provisional finalists"
        )
    finalists = [item["candidateID"] for item in eligible[:2]]
    output = args.output.resolve()
    if output.exists():
        raise ProvisionalError(f"audit receipt already exists: {output}")
    receipt = {
        "schemaVersion": 1,
        "status": TRUST_DOMAIN,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "candidateSetReceipt": {
            "sha256": candidate_set["receiptSHA256"],
            "bytes": candidate_set["receiptBytes"],
            "candidateCount": 6,
        },
        "pipelineBinding": provisional_binding(config),
        "transcriptRunReceipt": transcript_set["receiptBinding"],
        "referenceText": {
            "path": str(HERE / "casting-passage-v1.txt"),
            "sha256": production.sha256_text(reference_text),
            "wordCount": production.word_count(reference_text),
        },
        "rubric": config["auditRubric"],
        "pronunciationTermInventorySHA256": production.sha256_text(
            canonical_json(config["pronunciationTerms"])
        ),
        "candidateRecords": records,
        "ranking": [
            {
                "rank": index,
                "candidateID": item["candidateID"],
                "machineScore100": item["machineScore100"],
                "eligibleForProvisionalStress": item["eligibleForProvisionalStress"],
            }
            for index, item in enumerate(ranking, start=1)
        ],
        "provisionalFinalistIDs": finalists,
        "selectionAuthority": "Frozen local machine rubric only",
        "selectionMeaning": "Strongest two candidates permitted to enter non-shipping stress production; not an editor or artistic choice.",
        "knownLimits": [
            "Whisper transcription can mistake a correctly spoken word or normalize a wrongly spoken word.",
            "Orthographic name recognition is a pronunciation-risk screen, not a phonetic approval.",
            "Waveform and cadence metrics cannot certify artistic presence, naturalness or absence of every synthetic artifact.",
        ],
        "claimsExcluded": config["claimsExcluded"],
    }
    write_json(output, receipt)
    return receipt


def validate_audit_receipt(
    path: Path, candidate_set: dict[str, Any], config: dict[str, Any]
) -> dict[str, Any]:
    path = path.resolve()
    receipt = production.load_json(path)
    expected_binding = provisional_binding(config)
    finalists = receipt.get("provisionalFinalistIDs")
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("status") != TRUST_DOMAIN
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("pipelineBinding") != expected_binding
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
        or receipt.get("candidateSetReceipt", {}).get("sha256")
        != candidate_set["receiptSHA256"]
        or receipt.get("candidateSetReceipt", {}).get("bytes")
        != candidate_set["receiptBytes"]
        or not isinstance(finalists, list)
        or len(finalists) != 2
        or len(set(finalists)) != 2
        or any(candidate_id not in EXPECTED_IDS for candidate_id in finalists)
    ):
        raise ProvisionalError("provisional audit receipt validation failed")
    records = {item.get("candidateID"): item for item in receipt.get("candidateRecords", [])}
    if any(
        candidate_id not in records
        or records[candidate_id].get("eligibleForProvisionalStress") is not True
        for candidate_id in finalists
    ):
        raise ProvisionalError("provisional finalist did not pass frozen stress gates")
    return {
        "record": receipt,
        "path": path,
        "binding": file_binding(path),
        "finalists": finalists,
    }


def generate_stress(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    base_config, candidate_set = validate_candidate_set(args.candidate_set, config)
    audit = validate_audit_receipt(args.audit_receipt, candidate_set, config)
    text, text_record, cue_segments = _stress_material(config)
    output = prepare_empty_directory(args.output)
    stress_text_path = output / "stress-passage-v4.txt"
    stress_text_path.write_text(text + "\n", encoding="utf-8")
    runtime = production.verify_runtime(base_config)
    clone_dir, clone_files = production.verify_model_snapshot(
        base_config["models"]["voiceClone"], offline=args.offline
    )
    from mlx_audio.tts.utils import load_model
    from mlx_audio.utils import load_audio
    import mlx.core as mx
    import numpy as np

    clone_model = load_model(str(clone_dir))
    records: list[dict[str, Any]] = []
    segments_root = output / "segments"
    native_root = output / "native-assembly"
    segments_root.mkdir()
    native_root.mkdir()
    identity_text = production.canonical_text(HERE / "identity-reference-v1.txt")
    for candidate_id in audit["finalists"]:
        candidate = production.candidate_by_id(base_config, candidate_id)
        candidate_record = candidate_set["recordsByID"][candidate_id]
        reference_path = Path(candidate_record["_verifiedReferencePath"]).resolve()
        reference_audio = np.asarray(
            load_audio(str(reference_path), sample_rate=config["stressText"]["nativeSampleRate"]),
            dtype=np.float32,
        ).reshape(-1)
        reference_embedding = speaker_embedding(clone_model, reference_audio)
        candidate_segment_root = segments_root / candidate_id
        candidate_segment_root.mkdir()
        generated_audio: list[Any] = []
        generated_embeddings: list[tuple[dict[str, Any], Any]] = []
        cue_records: list[dict[str, Any]] = []
        for cue in cue_segments:
            generation_seed = candidate["stressSeed"] + cue["seedOffset"]
            audio, sample_rate = production.synthesize_clone(
                clone_model,
                text=cue["text"],
                reference_path=reference_path,
                reference_text=identity_text,
                seed=generation_seed,
                config=base_config,
                max_tokens=cue["maxTokens"],
            )
            if sample_rate != config["stressText"]["nativeSampleRate"]:
                raise ProvisionalError(
                    f"unexpected native rate for {candidate_id}/{cue['segmentID']}"
                )
            audio = np.ascontiguousarray(audio, dtype=np.float32)
            cue_path = candidate_segment_root / f"{cue['segmentID']}-f32.wav"
            production.write_float_wav(cue_path, sample_rate, audio)
            embedding = speaker_embedding(clone_model, audio)
            generated_audio.append(audio)
            generated_embeddings.append(embedding)
            cue_records.append(
                {
                    "segmentID": cue["segmentID"],
                    "order": cue["order"],
                    "contractIDs": cue["contractIDs"],
                    "textSHA256": cue["textSHA256"],
                    "wordCount": cue["wordCount"],
                    "generationSeed": generation_seed,
                    "seedOffset": cue["seedOffset"],
                    "maxTokens": cue["maxTokens"],
                    "generationCount": 1,
                    "wholeUntouchedNonStreamingGeneration": True,
                    "sampleRate": sample_rate,
                    "sampleCount": int(audio.size),
                    "durationSeconds": round(audio.size / sample_rate, 6),
                    "nativeFloat32LESHA256": native_float32_sha256(audio),
                    "nativeFile": file_binding(cue_path),
                }
            )
            write_json(
                output / "stress-generation-progress.receipt.json",
                {
                    "schemaVersion": 2,
                    "status": TRUST_DOMAIN,
                    "trustDomain": TRUST_DOMAIN,
                    "currentCandidateID": candidate_id,
                    "completedCandidateRecords": records,
                    "completedCueRecordsForCurrentCandidate": cue_records,
                    "claimsExcluded": config["claimsExcluded"],
                },
            )
            mx.clear_cache()
        assembled, assembly = assemble_native_segments(
            generated_audio, base_config["generation"]["candidatePeakDBFS"]
        )
        for cue_record, boundary in zip(
            cue_records, assembly["boundaries"], strict=True
        ):
            if cue_record["order"] != boundary["order"]:
                raise ProvisionalError("cue boundary order drifted")
            cue_record.update(
                {
                    "startSampleInclusive": boundary["startSampleInclusive"],
                    "endSampleExclusive": boundary["endSampleExclusive"],
                }
            )
        assembly.pop("boundaries")
        voice_consistency = voice_consistency_record(
            reference_embedding=reference_embedding,
            segment_embeddings=generated_embeddings,
            segment_ids=[cue["segmentID"] for cue in cue_segments],
            config=config,
        )
        native_assembly = native_root / f"{candidate_id}-assembled-normalized-f32.wav"
        production.write_float_wav(
            native_assembly, config["stressText"]["nativeSampleRate"], assembled
        )
        assembly.update(
            {
                "assemblyMode": config["stressText"]["assemblyMode"],
                "nativeSampleRate": config["stressText"]["nativeSampleRate"],
                "nativeDurationSeconds": round(
                    assembled.size / config["stressText"]["nativeSampleRate"], 6
                ),
                "nativeAssemblyFile": file_binding(native_assembly),
                "losslessCueConcatenation": True,
                "uninterruptedAuditionMaster": True,
                "singleModelCall": False,
            }
        )
        master = output / f"{candidate_id}-stress.wav"
        master_receipt = production.convert_to_master(
            native_assembly, master, base_config
        )
        actual_minutes = master_receipt["durationSeconds"] / 60
        duration_pass = (
            config["stressText"]["minimumActualMinutes"]
            <= actual_minutes
            <= config["stressText"]["maximumActualMinutes"]
        )
        record = {
            "candidateID": candidate_id,
            "baseStressSeed": candidate["stressSeed"],
            "instructionSHA256": candidate_record["instructionSHA256"],
            "referenceSHA256": candidate_record["reference"]["sha256"],
            "generationCount": len(cue_records),
            "cueGenerationCount": len(cue_records),
            "auditionMasterCount": 1,
            "cueRecords": cue_records,
            "masterAssembly": assembly,
            "voiceIdentityConsistency": voice_consistency,
            "actualDurationMinutes": round(actual_minutes, 6),
            "durationGate18To22Minutes": duration_pass,
            "master": master_receipt,
        }
        records.append(record)
        write_json(
            output / "stress-generation-progress.receipt.json",
            {
                "schemaVersion": 2,
                "status": TRUST_DOMAIN,
                "trustDomain": TRUST_DOMAIN,
                "completedCandidateRecords": records,
                "completedCueRecordsForCurrentCandidate": [],
                "claimsExcluded": config["claimsExcluded"],
            },
        )
        mx.clear_cache()
    receipt = {
        "schemaVersion": 2,
        "status": TRUST_DOMAIN,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": provisional_binding(config),
        "productionPipelineBinding": production.pipeline_binding(base_config, runtime),
        "candidateSetReceipt": {
            "sha256": candidate_set["receiptSHA256"],
            "bytes": candidate_set["receiptBytes"],
        },
        "provisionalAuditReceipt": audit["binding"],
        "provisionalFinalistIDs": audit["finalists"],
        "stressText": {
            **text_record,
            "materializedFile": file_binding(stress_text_path),
            "calibrationRule": config["stressText"]["calibrationRule"],
        },
        "voiceCloneModel": production.model_receipt(
            base_config["models"]["voiceClone"], clone_files
        ),
        "generationSettings": {
            "base": base_config["generation"],
            "perCueMaxTokens": [cue["maxTokens"] for cue in cue_segments],
            "perCueSeedRule": "candidate baseStressSeed plus frozen cue seedOffset",
            "nonStreamingWholeCueGeneration": True,
        },
        "assemblyPolicy": {
            "mode": config["stressText"]["assemblyMode"],
            "cueCountPerFinalist": len(cue_segments),
            "uninterruptedAuditionMasterRequired": True,
            "singleModelCallRequired": False,
            "prohibitedOperations": config["stressText"][
                "prohibitedAssemblyOperations"
            ],
            "oneCommonMasterNormalization": True,
        },
        "actualDurationGate": {
            "minimumMinutes": config["stressText"]["minimumActualMinutes"],
            "maximumMinutes": config["stressText"]["maximumActualMinutes"],
            "allRecordsPass": all(item["durationGate18To22Minutes"] for item in records),
        },
        "rejectedCalibrationEvidence": config["calibrationEvidence"],
        "rejectedSingleCallEvidence": config["rejectedSingleCallEvidence"],
        "records": records,
        "nextRequiredGate": "OFFLINE_WORD_PRONUNCIATION_ARTIFACT_AND_CADENCE_AUDIT_OF_BOTH_STRESS_FILES",
        "claimsExcluded": config["claimsExcluded"],
    }
    write_json(output / "stress-set.provisional.receipt.json", receipt)
    return receipt


def validate_stress_set(
    root: Path, config: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Path]]:
    import numpy as np
    from scipy.io import wavfile

    root = root.resolve()
    receipt_path = root / "stress-set.provisional.receipt.json"
    receipt = production.load_json(receipt_path)
    if (
        receipt.get("schemaVersion") != 2
        or receipt.get("status") != TRUST_DOMAIN
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("pipelineBinding") != provisional_binding(config)
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
        or receipt.get("assemblyPolicy")
        != {
            "mode": config["stressText"]["assemblyMode"],
            "cueCountPerFinalist": 6,
            "uninterruptedAuditionMasterRequired": True,
            "singleModelCallRequired": False,
            "prohibitedOperations": config["stressText"][
                "prohibitedAssemblyOperations"
            ],
            "oneCommonMasterNormalization": True,
        }
        or receipt.get("rejectedCalibrationEvidence")
        != config["calibrationEvidence"]
        or receipt.get("rejectedSingleCallEvidence")
        != config["rejectedSingleCallEvidence"]
    ):
        raise ProvisionalError("stress-set trust domain or binding drifted")
    finalists = receipt.get("provisionalFinalistIDs")
    records = receipt.get("records")
    if (
        not isinstance(finalists, list)
        or len(finalists) != 2
        or not isinstance(records, list)
        or [item.get("candidateID") for item in records] != finalists
    ):
        raise ProvisionalError("stress-set finalist inventory drifted")
    _, text_record, cue_segments = _stress_material(config)
    cue_by_id = {item["segmentID"]: item for item in cue_segments}
    base_config = production.validate_config()
    audio: dict[str, Path] = {}
    for record in records:
        candidate_id = record["candidateID"]
        candidate = production.candidate_by_id(base_config, candidate_id)
        cue_records = record.get("cueRecords")
        assembly = record.get("masterAssembly", {})
        consistency = record.get("voiceIdentityConsistency", {})
        if (
            record.get("baseStressSeed") != candidate["stressSeed"]
            or record.get("generationCount") != 6
            or record.get("cueGenerationCount") != 6
            or record.get("auditionMasterCount") != 1
            or not isinstance(cue_records, list)
            or [item.get("segmentID") for item in cue_records]
            != [f"cue-{index:02d}" for index in range(1, 7)]
            or assembly.get("assemblyMode")
            != config["stressText"]["assemblyMode"]
            or assembly.get("nativeSampleRate")
            != config["stressText"]["nativeSampleRate"]
            or assembly.get("losslessCueConcatenation") is not True
            or assembly.get("uninterruptedAuditionMaster") is not True
            or assembly.get("singleModelCall") is not False
            or assembly.get("sampleCuts") != 0
            or assembly.get("insertedSilenceSamples") != 0
            or assembly.get("crossfades") != 0
            or assembly.get("fades") != 0
            or assembly.get("timeStretchApplied") is not False
            or assembly.get("perSegmentGainChanges") != 0
        ):
            raise ProvisionalError(f"stress assembly contract failed: {candidate_id}")
        native_path = (
            root
            / "native-assembly"
            / f"{candidate_id}-assembled-normalized-f32.wav"
        )
        expected_native = assembly.get("nativeAssemblyFile", {})
        if (
            not native_path.is_file()
            or native_path.stat().st_size != expected_native.get("bytes")
            or production.sha256_file(native_path) != expected_native.get("sha256")
        ):
            raise ProvisionalError(f"native assembly binding failed: {candidate_id}")
        native_rate, native_audio = wavfile.read(native_path)
        if (
            native_rate != config["stressText"]["nativeSampleRate"]
            or native_audio.ndim != 1
            or native_audio.dtype != np.float32
            or native_audio.size != assembly.get("rawConcatenatedSampleCount")
            or native_float32_sha256(native_audio)
            != assembly.get("normalizedFloat32LESHA256")
        ):
            raise ProvisionalError(f"native assembly samples failed: {candidate_id}")
        raw_digest = hashlib.sha256()
        cursor = 0
        maximum_peak = 0.0
        for cue_record in cue_records:
            cue = cue_by_id.get(cue_record["segmentID"])
            if (
                cue is None
                or cue_record.get("order") != cue["order"]
                or cue_record.get("contractIDs") != cue["contractIDs"]
                or cue_record.get("textSHA256") != cue["textSHA256"]
                or cue_record.get("wordCount") != cue["wordCount"]
                or cue_record.get("seedOffset") != cue["seedOffset"]
                or cue_record.get("generationSeed")
                != candidate["stressSeed"] + cue["seedOffset"]
                or cue_record.get("maxTokens") != cue["maxTokens"]
                or cue_record.get("generationCount") != 1
                or cue_record.get("wholeUntouchedNonStreamingGeneration") is not True
                or cue_record.get("sampleRate")
                != config["stressText"]["nativeSampleRate"]
                or cue_record.get("startSampleInclusive") != cursor
            ):
                raise ProvisionalError(
                    f"stress cue contract failed: {candidate_id}/{cue_record.get('segmentID')}"
                )
            cue_path = (
                root
                / "segments"
                / candidate_id
                / f"{cue_record['segmentID']}-f32.wav"
            )
            expected_cue_file = cue_record.get("nativeFile", {})
            if (
                not cue_path.is_file()
                or cue_path.stat().st_size != expected_cue_file.get("bytes")
                or production.sha256_file(cue_path)
                != expected_cue_file.get("sha256")
            ):
                raise ProvisionalError(
                    f"stress cue file binding failed: {candidate_id}/{cue_record['segmentID']}"
                )
            cue_rate, cue_audio = wavfile.read(cue_path)
            cue_audio = np.asarray(cue_audio)
            expected_end = cursor + int(cue_audio.size)
            if (
                cue_rate != config["stressText"]["nativeSampleRate"]
                or cue_audio.ndim != 1
                or cue_audio.dtype != np.float32
                or cue_audio.size != cue_record.get("sampleCount")
                or cue_record.get("endSampleExclusive") != expected_end
                or native_float32_sha256(cue_audio)
                != cue_record.get("nativeFloat32LESHA256")
            ):
                raise ProvisionalError(
                    f"stress cue samples failed: {candidate_id}/{cue_record['segmentID']}"
                )
            maximum_peak = max(maximum_peak, float(np.max(np.abs(cue_audio))))
            raw_digest.update(native_float32_bytes(cue_audio))
            cursor = expected_end
        if (
            cursor != native_audio.size
            or raw_digest.hexdigest()
            != assembly.get("rawConcatenatedFloat32LESHA256")
        ):
            raise ProvisionalError(f"lossless cue order failed: {candidate_id}")
        expected_gain = (
            10 ** (base_config["generation"]["candidatePeakDBFS"] / 20)
        ) / maximum_peak
        gain = assembly.get("oneCommonNormalizationGain")
        if not isinstance(gain, (int, float)) or not math.isclose(
            gain, expected_gain, rel_tol=1e-12, abs_tol=1e-12
        ):
            raise ProvisionalError(f"common master gain drifted: {candidate_id}")
        for cue_record in cue_records:
            cue_path = (
                root
                / "segments"
                / candidate_id
                / f"{cue_record['segmentID']}-f32.wav"
            )
            _, cue_audio = wavfile.read(cue_path)
            normalized_slice = np.asarray(cue_audio * gain, dtype=np.float32)
            start = cue_record["startSampleInclusive"]
            end = cue_record["endSampleExclusive"]
            if not np.array_equal(native_audio[start:end], normalized_slice):
                raise ProvisionalError(
                    f"assembled master changed cue samples: {candidate_id}/{cue_record['segmentID']}"
                )
        consistency_ids = [
            item.get("segmentID") for item in consistency.get("segmentEmbeddings", [])
        ]
        consistency_gates = {
            "segmentToReference": consistency.get(
                "minimumSegmentToReferenceCosine", -1
            )
            >= config["voiceConsistency"]["minimumSegmentToReferenceCosine"],
            "pairwiseSegments": consistency.get("minimumPairwiseSegmentCosine", -1)
            >= config["voiceConsistency"]["minimumPairwiseSegmentCosine"],
        }
        if (
            consistency_ids != [item["segmentID"] for item in cue_segments]
            or consistency.get("requiredMinimumSegmentToReferenceCosine")
            != config["voiceConsistency"]["minimumSegmentToReferenceCosine"]
            or consistency.get("requiredMinimumPairwiseSegmentCosine")
            != config["voiceConsistency"]["minimumPairwiseSegmentCosine"]
            or consistency.get("gates") != consistency_gates
            or consistency.get("passesFrozenIdentityDriftScreen")
            is not all(consistency_gates.values())
        ):
            raise ProvisionalError(f"voice identity record failed: {candidate_id}")
        path = root / f"{candidate_id}-stress.wav"
        expected = record.get("master", {})
        if (
            not path.is_file()
            or path.stat().st_size != expected.get("bytes")
            or production.sha256_file(path) != expected.get("sha256")
        ):
            raise ProvisionalError(f"stress master binding failed: {candidate_id}")
        audio[candidate_id] = path
    if receipt.get("stressText", {}).get("textSHA256") != text_record["textSHA256"]:
        raise ProvisionalError("stress text binding drifted")
    materialized = root / "stress-passage-v4.txt"
    expected_text_file = receipt.get("stressText", {}).get("materializedFile", {})
    if (
        not materialized.is_file()
        or materialized.stat().st_size != expected_text_file.get("bytes")
        or production.sha256_file(materialized) != expected_text_file.get("sha256")
    ):
        raise ProvisionalError("materialized stress text binding failed")
    return receipt, audio


def transcribe_stress(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    stress_receipt, audio = validate_stress_set(args.stress_set, config)
    tools = validate_asr_tools(config, args.whisper, args.model)
    output = prepare_empty_directory(args.output)
    records: list[dict[str, Any]] = []
    for candidate_id, audio_path in audio.items():
        transcript_path = run_whisper(
            executable=args.whisper,
            model=args.model,
            arguments=config["offlineASR"]["arguments"],
            input_path=audio_path,
            output_prefix=output / candidate_id,
        )
        records.append(
            {
                "candidateID": candidate_id,
                "audio": file_binding(audio_path),
                "transcript": file_binding(transcript_path),
                "log": file_binding(output / f"{candidate_id}.whisper.log.txt"),
            }
        )
    receipt = {
        "schemaVersion": 1,
        "status": TRUST_DOMAIN,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "purpose": "UNPROMPTED_OFFLINE_MACHINE_TRANSCRIPTION_OF_TWO_PROVISIONAL_STRESS_READINGS",
        "stressSetReceipt": file_binding(
            args.stress_set.resolve() / "stress-set.provisional.receipt.json"
        ),
        "provisionalFinalistIDs": stress_receipt["provisionalFinalistIDs"],
        "tools": tools,
        "records": records,
        "claimsExcluded": config["claimsExcluded"],
    }
    write_json(output / "transcript-run.receipt.json", receipt)
    return receipt


def audit_stress(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    stress_receipt, audio = validate_stress_set(args.stress_set, config)
    transcript_set = validate_transcript_receipt(
        args.transcripts,
        expected_audio=audio,
        config=config,
        purpose="UNPROMPTED_OFFLINE_MACHINE_TRANSCRIPTION_OF_TWO_PROVISIONAL_STRESS_READINGS",
    )
    text, text_record = stress_text(config)
    stress_pronunciation_terms = pronunciation_terms_present(
        config["pronunciationTerms"], text
    )
    master_limits = config["auditRubric"]["stressMaster"]
    records: list[dict[str, Any]] = []
    for candidate_id, audio_path in audio.items():
        result = analyze_record(
            audio_path=audio_path,
            transcript_path=transcript_set["records"][candidate_id]["transcript"],
            reference_text=text,
            config=config,
            pronunciation_terms=stress_pronunciation_terms,
        )
        duration_record = next(
            item for item in stress_receipt["records"] if item["candidateID"] == candidate_id
        )
        result.update(
            {
                "candidateID": candidate_id,
                "durationGate18To22Minutes": duration_record["durationGate18To22Minutes"],
                "audio": file_binding(audio_path),
                "transcript": transcript_set["records"][candidate_id]["transcriptBinding"],
            }
        )
        accuracy = result["metrics"]["wordAccuracy"]
        repetition = result["metrics"]["repetition"]
        whole_master_gates = {
            "wordAlignmentErrorRate": accuracy["wordAlignmentErrorRate"]
            <= master_limits["maximumWordAlignmentErrorRate"],
            "referenceExactMatchCoverage": accuracy["referenceExactMatchCoverage"]
            >= master_limits["minimumReferenceExactMatchCoverage"],
            "maximumNonmatchingReferenceRun": accuracy[
                "maximumNonmatchingReferenceRunWords"
            ]
            <= master_limits["maximumNonmatchingReferenceRunWords"],
            "maximumNonmatchingHypothesisRun": accuracy[
                "maximumNonmatchingHypothesisRunWords"
            ]
            <= master_limits["maximumNonmatchingHypothesisRunWords"],
            "repeatedTokenCoverage": repetition["repeatedTokenCoverage"]
            <= master_limits["maximumRepeatedTokenCoverage"],
            "repeatedNgramOccurrences": repetition["maximumOccurrences"]
            <= master_limits["maximumRepeatedNgramOccurrences"],
            "pronunciationRecognition": result["stressEligibilityGates"][
                "pronunciationRecognition"
            ],
            "decode": result["stressEligibilityGates"]["decode"],
            "clipping": result["stressEligibilityGates"]["clipping"],
            "sampleDiscontinuity": result["stressEligibilityGates"][
                "sampleDiscontinuity"
            ],
            "silence": result["stressEligibilityGates"]["silence"],
            "dcOffset": result["stressEligibilityGates"]["dcOffset"],
            "duration18To22Minutes": result["durationGate18To22Minutes"],
            "speakerIdentityConsistency": duration_record[
                "voiceIdentityConsistency"
            ]["passesFrozenIdentityDriftScreen"],
            "losslessCueAssembly": duration_record["masterAssembly"][
                "losslessCueConcatenation"
            ],
        }
        result["wholeMasterGates"] = whole_master_gates
        result["passesCompleteMachineStressGate"] = all(
            whole_master_gates.values()
        )
        records.append(result)
    ranking = sorted(records, key=lambda item: (-item["machineScore100"], item["candidateID"]))
    passing = [item for item in ranking if item["passesCompleteMachineStressGate"]]
    recommendation = passing[0]["candidateID"] if passing else None
    output = args.output.resolve()
    if output.exists():
        raise ProvisionalError(f"stress audit receipt already exists: {output}")
    receipt = {
        "schemaVersion": 1,
        "status": TRUST_DOMAIN,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": provisional_binding(config),
        "stressSetReceipt": file_binding(
            args.stress_set.resolve() / "stress-set.provisional.receipt.json"
        ),
        "transcriptRunReceipt": transcript_set["receiptBinding"],
        "stressText": text_record,
        "rubric": config["auditRubric"],
        "stressPronunciationTerms": stress_pronunciation_terms,
        "stressPronunciationInventorySHA256": production.sha256_text(
            canonical_json(stress_pronunciation_terms)
        ),
        "candidateRecords": records,
        "ranking": [
            {
                "rank": index,
                "candidateID": item["candidateID"],
                "machineScore100": item["machineScore100"],
                "passesCompleteMachineStressGate": item["passesCompleteMachineStressGate"],
            }
            for index, item in enumerate(ranking, start=1)
        ],
        "codexProvisionalRecommendedVoiceID": recommendation,
        "recommendationMeaning": "Local integration recommendation only; null when neither finalist passes every frozen machine stress gate.",
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }
    write_json(output, receipt)
    return receipt


def validate_only(config: dict[str, Any]) -> dict[str, Any]:
    base = production.validate_config()
    text, text_record = stress_text(config)
    if production.word_count(text) != config["stressText"]["wordCount"]:
        raise ProvisionalError("stress text validation failed")
    return {
        "status": "VALID",
        "trustDomain": TRUST_DOMAIN,
        "productionEditorTrustDomain": production.EDITOR_SELECTION_STATUS,
        "trustDomainsAreDistinct": TRUST_DOMAIN != production.EDITOR_SELECTION_STATUS,
        "candidateCount": len(base["candidates"]),
        "stressTextSHA256": text_record["textSHA256"],
        "stressWordCount": text_record["wordCount"],
        "stressAssemblyMode": text_record["assemblyMode"],
        "stressCueCount": text_record["cueCount"],
        "claimsExcluded": config["claimsExcluded"],
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")

    transcribe = sub.add_parser("transcribe-candidates")
    transcribe.add_argument("--candidate-set", type=Path, required=True)
    transcribe.add_argument("--whisper", type=Path, required=True)
    transcribe.add_argument("--model", type=Path, required=True)
    transcribe.add_argument("--output", type=Path, required=True)

    audit = sub.add_parser("audit-candidates")
    audit.add_argument("--candidate-set", type=Path, required=True)
    audit.add_argument("--transcripts", type=Path, required=True)
    audit.add_argument("--output", type=Path, required=True)

    stress = sub.add_parser("generate-stress")
    stress.add_argument("--candidate-set", type=Path, required=True)
    stress.add_argument("--audit-receipt", type=Path, required=True)
    stress.add_argument("--output", type=Path, required=True)
    stress.add_argument("--offline", action="store_true")

    transcribe_long = sub.add_parser("transcribe-stress")
    transcribe_long.add_argument("--stress-set", type=Path, required=True)
    transcribe_long.add_argument("--whisper", type=Path, required=True)
    transcribe_long.add_argument("--model", type=Path, required=True)
    transcribe_long.add_argument("--output", type=Path, required=True)

    audit_long = sub.add_parser("audit-stress")
    audit_long.add_argument("--stress-set", type=Path, required=True)
    audit_long.add_argument("--transcripts", type=Path, required=True)
    audit_long.add_argument("--output", type=Path, required=True)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        config = load_provisional_config()
        if args.command == "validate":
            result = validate_only(config)
        elif args.command == "transcribe-candidates":
            result = transcribe_candidates(args, config)
        elif args.command == "audit-candidates":
            result = audit_candidates(args, config)
        elif args.command == "generate-stress":
            result = generate_stress(args, config)
        elif args.command == "transcribe-stress":
            result = transcribe_stress(args, config)
        elif args.command == "audit-stress":
            result = audit_stress(args, config)
        else:
            raise ProvisionalError(f"unsupported command: {args.command}")
    except (ProvisionalError, production.PipelineError, subprocess.CalledProcessError) as error:
        print(f"provisional narration pipeline failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
