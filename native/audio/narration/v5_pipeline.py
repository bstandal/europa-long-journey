#!/usr/bin/env python3
"""Fail-closed V5 narration method and in-process audit.

V5 is a non-shipping Codex trust domain.  It does not accept external ASR
receipts or self-reported audit metrics.  The audit recomputes the master,
speaker embeddings, timed words, monotone alignment and all acceptance gates
from byte-bound native cue files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Any, Callable, Iterable, Sequence

import pipeline as production


HERE = Path(__file__).resolve().parent
REPOSITORY_ROOT = HERE.parents[2]
CONFIG_PATH = HERE / "v5-audit-config.json"
SCRIPT_PATH = Path(__file__).resolve()
EXPECTED_CONFIG_BYTES = 9687
EXPECTED_CONFIG_SHA256 = "208ade8b925efffe0e81eae82d41cddd96a3495e8d4ec9dfd15137af6a1dd1d1"
FROZEN_COMPLETED_GENERATION_SCRIPT_BYTES = 148123
FROZEN_COMPLETED_GENERATION_SCRIPT_SHA256 = (
    "546a313f2299f2bd66a56acbdfd0f36a595d564f7d1fd4e808f1477d671cafd8"
)
TRUST_DOMAIN = "CODEX_V5_DIAGNOSTIC_NON_SHIPPING"
METHOD_STATUS = "CODEX_V5_METHOD_FROZEN_WITH_BOUND_GENERATOR"
GENERATION_PROGRESS_STATUS = "CODEX_V5_GENERATION_IN_PROGRESS_NON_SHIPPING"
CUE_COMMIT_STATUS = "CODEX_V5_CUE_COMMIT_NON_SHIPPING"
CANDIDATE_COMMIT_STATUS = "CODEX_V5_CANDIDATE_COMMIT_NON_SHIPPING"
STRESS_STATUS = "CODEX_V5_GENERATED_NON_SHIPPING_AWAITING_IN_PROCESS_AUDIT"
AUDIT_STATUS = "CODEX_V5_MACHINE_AUDITED_NON_SHIPPING"
EXPECTED_FINALISTS = ["voice-candidate-05", "voice-candidate-06"]
EXPECTED_ASR_ARGUMENTS = [
    "--language",
    "en",
    "--threads",
    "8",
    "--processors",
    "1",
    "--beam-size",
    "5",
    "--best-of",
    "5",
    "--split-on-word",
    "--output-json-full",
    "--no-prints",
]
WHISPER_TIMESTAMP_TAIL_TOLERANCE_MS = 500.0


class V5Error(RuntimeError):
    """A release-blocking V5 method or audit failure."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return production.sha256_file(path)


def file_binding(path: Path) -> dict[str, Any]:
    path = path.absolute()
    if not path.is_file():
        raise V5Error(f"missing bound file: {path}")
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def validate_exact_file(path: Path, *, byte_count: int, digest: str, label: str) -> None:
    if not path.is_file():
        raise V5Error(f"{label} is missing: {path}")
    if path.stat().st_size != byte_count or sha256_file(path) != digest:
        raise V5Error(f"{label} exact byte binding failed")


def _absolute_without_resolution(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path)))


def validate_no_symlink_parent_chain(path: Path, *, allow_missing_leaf: bool) -> None:
    target = _absolute_without_resolution(path)
    current = Path(target.anchor)
    parts = target.parts[1:] if target.anchor else target.parts
    missing_seen = False
    for index, part in enumerate(parts):
        current /= part
        exists = os.path.lexists(current)
        is_leaf = index == len(parts) - 1
        if not exists:
            if not allow_missing_leaf or (not is_leaf and not missing_seen):
                raise V5Error(f"missing path parent in chain: {current}")
            missing_seen = True
            continue
        if missing_seen:
            raise V5Error(f"path reappears after a missing parent: {current}")
        mode = os.lstat(current).st_mode
        if stat.S_ISLNK(mode):
            raise V5Error(f"symlink prohibited in path parent chain: {current}")
        if not is_leaf and not stat.S_ISDIR(mode):
            raise V5Error(f"non-directory path parent: {current}")


def confined_path(
    path: Path,
    *,
    root: Path,
    must_exist: bool,
    expect_directory: bool | None = None,
) -> Path:
    target = _absolute_without_resolution(path)
    boundary = _absolute_without_resolution(root)
    try:
        common = Path(os.path.commonpath([target, boundary]))
    except ValueError as error:
        raise V5Error("path confinement comparison failed") from error
    if common != boundary:
        raise V5Error(f"path escaped confined root: {target}")
    validate_no_symlink_parent_chain(
        target, allow_missing_leaf=not must_exist
    )
    if must_exist:
        if not target.exists():
            raise V5Error(f"confined path is missing: {target}")
        if expect_directory is True and not target.is_dir():
            raise V5Error(f"expected directory: {target}")
        if expect_directory is False and not target.is_file():
            raise V5Error(f"expected file: {target}")
    return target


def repository_path(relative: str, *, directory: bool | None = None) -> Path:
    value = Path(relative)
    if value.is_absolute() or ".." in value.parts:
        raise V5Error(f"repository path must be a clean relative path: {relative}")
    return confined_path(
        REPOSITORY_ROOT / value,
        root=REPOSITORY_ROOT,
        must_exist=True,
        expect_directory=directory,
    )


def prepare_output_root(path: Path, config: dict[str, Any]) -> Path:
    work_root = REPOSITORY_ROOT / config["paths"]["workRoot"]
    if not work_root.exists():
        confined_path(
            work_root.parent,
            root=REPOSITORY_ROOT,
            must_exist=True,
            expect_directory=True,
        )
        work_root.mkdir()
    work_root = confined_path(
        work_root,
        root=REPOSITORY_ROOT,
        must_exist=True,
        expect_directory=True,
    )
    target = confined_path(
        path,
        root=work_root,
        must_exist=path.exists(),
        expect_directory=True if path.exists() else None,
    )
    if target == _absolute_without_resolution(work_root):
        raise V5Error("audit output must be a child of the V5 work root")
    if target.parent != work_root:
        raise V5Error("audit output must be one direct child of the frozen V5 work root")
    if target.exists() and any(target.iterdir()):
        raise V5Error(f"audit output must be absent or empty: {target}")
    target.mkdir(parents=True, exist_ok=True)
    validate_no_symlink_parent_chain(target, allow_missing_leaf=False)
    return target


def _v5_work_root(config: dict[str, Any], *, create: bool) -> Path:
    work_root = REPOSITORY_ROOT / config["paths"]["workRoot"]
    if create and not work_root.exists():
        confined_path(
            work_root.parent,
            root=REPOSITORY_ROOT,
            must_exist=True,
            expect_directory=True,
        )
        work_root.mkdir()
    return confined_path(
        work_root,
        root=REPOSITORY_ROOT,
        must_exist=True,
        expect_directory=True,
    )


def prepare_generation_root(path: Path, config: dict[str, Any]) -> Path:
    work_root = _v5_work_root(config, create=True)
    target = confined_path(
        path,
        root=work_root,
        must_exist=path.exists(),
        expect_directory=True if path.exists() else None,
    )
    if target == work_root or target.parent != work_root:
        raise V5Error("generation output must be one direct child of the V5 work root")
    if not target.exists():
        target.mkdir()
    validate_no_symlink_parent_chain(target, allow_missing_leaf=False)
    for relative in ["cue-commits", "candidates"]:
        directory = target / relative
        if directory.exists():
            confined_path(
                directory,
                root=target,
                must_exist=True,
                expect_directory=True,
            )
        else:
            directory.mkdir()
    return target


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write_json(
    path: Path, value: Any, *, work_root: Path, confinement_root: Path
) -> None:
    path = confined_path(
        path,
        root=confinement_root,
        must_exist=path.exists(),
        expect_directory=False if path.exists() else None,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=work_root, prefix=".v5-json-stage-", suffix=".json"
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_commit_directory(
    staging: Path, destination: Path, *, work_root: Path, output_root: Path
) -> None:
    staging = confined_path(
        staging,
        root=work_root,
        must_exist=True,
        expect_directory=True,
    )
    destination = _absolute_without_resolution(destination)
    destination_parent = confined_path(
        destination.parent,
        root=output_root,
        must_exist=destination.parent.exists(),
        expect_directory=True if destination.parent.exists() else None,
    )
    if not destination_parent.exists():
        destination_parent.mkdir()
        _fsync_directory(destination_parent.parent)
    destination = confined_path(
        destination,
        root=output_root,
        must_exist=destination.exists(),
        expect_directory=True if destination.exists() else None,
    )
    if destination.exists():
        raise V5Error(f"atomic V5 commit destination already exists: {destination}")
    for file_path in staging.rglob("*"):
        if file_path.is_file():
            with file_path.open("rb") as handle:
                os.fsync(handle.fileno())
    _fsync_directory(staging)
    os.replace(staging, destination)
    _fsync_directory(destination.parent)


def validate_config_document(config: dict[str, Any]) -> None:
    if (
        config.get("schemaVersion") != 1
        or config.get("status") != METHOD_STATUS
        or config.get("trustDomain") != TRUST_DOMAIN
        or config.get("language") != "English"
        or config.get("locale") != "en-GB"
    ):
        raise V5Error("V5 config identity drifted")
    if config.get("offlineASR", {}).get("arguments") != EXPECTED_ASR_ARGUMENTS:
        raise V5Error("pinned ASR arguments drifted")
    asr = config["offlineASR"]
    if (
        asr.get("engine") != "whisper.cpp"
        or asr.get("version") != "1.9.1"
        or asr.get("answerPromptProhibited") is not True
        or asr.get("externalTranscriptReceiptProhibited") is not True
    ):
        raise V5Error("pinned ASR contract drifted")
    stress = config.get("stressText", {})
    if (
        stress.get("wordCount") != 3400
        or stress.get("textSHA256")
        != "b375fe2c3ea7658c4cab28f68812dc58a50b0bcb026466e0f777118de2eb8a28"
        or stress.get("minimumActualMinutes") != 18
        or stress.get("maximumActualMinutes") != 22
        or stress.get("completeContractIDs")
        != [f"contract-{index:02d}" for index in range(1, 17)]
        or stress.get("tokenCeilingFailsAtOrAboveMaxTokens") is not True
    ):
        raise V5Error("V5 stress contract drifted")
    segments = stress.get("segments")
    if (
        not isinstance(segments, list)
        or [item.get("segmentID") for item in segments]
        != [f"cue-{index:02d}" for index in range(1, 7)]
        or [item.get("wordCount") for item in segments]
        != [483, 579, 670, 637, 523, 508]
        or [item.get("maxTokens") for item in segments]
        != [3140, 3764, 4355, 4141, 3400, 3302]
        or [item.get("contractIDs") for item in segments]
        != [
            ["contract-01", "contract-02", "contract-03"],
            ["contract-04", "contract-05", "contract-06"],
            ["contract-07", "contract-08", "contract-09", "contract-10"],
            ["contract-10", "contract-11", "contract-12"],
            ["contract-13", "contract-14"],
            ["contract-15", "contract-16"],
        ]
        or [item.get("sourceCharacterStartInclusive") for item in segments]
        != [0, 3274, 7248, 12019, 16358, 20002]
        or [item.get("sourceCharacterEndExclusive") for item in segments]
        != [3272, 7246, 12018, 16356, 20000, 23622]
        or [item.get("separatorAfter") for item in segments]
        != ["\n\n", "\n\n", " ", "\n\n", "\n\n", ""]
        or [item.get("boundaryAfter") for item in segments]
        != [
            "AUTHORED_PARAGRAPH",
            "AUTHORED_PARAGRAPH",
            "AUTHORED_SENTENCE",
            "AUTHORED_PARAGRAPH",
            "AUTHORED_PARAGRAPH",
            "END_OF_TEXT",
        ]
    ):
        raise V5Error("V5 cue inventory drifted")
    master = config.get("master", {})
    if (
        master.get("nativeSampleRate") != 24000
        or master.get("nativeChannels") != 1
        or master.get("nativeRepresentation") != "float32"
        or master.get("nativeAssemblyPeakDBFS") != -3.0
        or master.get("masterSampleRate") != 48000
        or master.get("masterChannels") != 1
        or master.get("masterBitDepth") != 24
        or master.get("masterCodec") != "pcm_s24le"
        or master.get("deterministicByteEqualityRequired") is not True
        or master.get("decodedDurationToleranceSamples") != 0
    ):
        raise V5Error("V5 deterministic master contract drifted")
    identity = config.get("identity", {})
    if identity != {
        "method": "Qwen3-TTS Base ECAPA-TDNN speaker encoder from the pinned voice-clone snapshot",
        "windowSeconds": 20,
        "hopSeconds": 10,
        "minimumWholeCueToReferenceCosine": 0.97,
        "minimumWindowToReferenceCosine": 0.96,
        "minimumWindowToWholeCueCosine": 0.985,
        "minimumAdjacentWindowCosine": 0.995,
        "minimumPairwiseWholeCueCosine": 0.98,
        "minimumAllWindowPairCosine": 0.975,
    }:
        raise V5Error("V5 identity gates drifted")
    if config.get("alignment") != {
        "normalizationVersion": 1,
        "algorithm": "Hirschberg global Levenshtein with deterministic monotone backtrace",
        "anchorWords": 8,
        "minimumExactReferenceCoveragePerCue": 0.98,
        "minimumExactHypothesisCoveragePerCue": 0.98,
        "maximumNonmatchingReferenceRunWordsPerCue": 6,
        "maximumNonmatchingHypothesisRunWordsPerCue": 12,
        "boundaryToleranceMilliseconds": 750,
        "ambiguousAnchorFails": True,
    }:
        raise V5Error("V5 alignment gates drifted")
    if config.get("repetition") != {
        "ngramSize": 6,
        "minimumHypothesisOccurrences": 2,
        "maximumExcessOccurrenceFraction": 0.005,
        "referenceMultisetSubtracted": True,
    }:
        raise V5Error("V5 repetition gate drifted")
    if config.get("tempo") != {
        "minimumWordsPerMinute": 110,
        "maximumWordsPerMinute": 210,
        "maximumRelativeDeviationFromCueMedian": 0.25,
    }:
        raise V5Error("V5 tempo gate drifted")
    if config.get("silence") != {
        "thresholdDBFS": -45,
        "frameMilliseconds": 20,
        "hopMilliseconds": 10,
        "maximumTotalSilenceFraction": 0.12,
        "maximumCueBoundarySilenceMilliseconds": 1250,
        "maximumLeadingOrTrailingCueSilenceMilliseconds": 750,
    }:
        raise V5Error("V5 silence gate drifted")
    exclusions = {
        "editor voice selection",
        "final word-accuracy approval",
        "final pronunciation approval",
        "artistic approval",
        "shipping approval",
    }
    if set(config.get("claimsExcluded", [])) != exclusions:
        raise V5Error("V5 approval exclusions drifted")


def load_config(path: Path = CONFIG_PATH) -> dict[str, Any]:
    path = _absolute_without_resolution(path)
    if path != _absolute_without_resolution(CONFIG_PATH):
        raise V5Error("V5 config path is frozen")
    validate_no_symlink_parent_chain(path, allow_missing_leaf=False)
    validate_exact_file(
        path,
        byte_count=EXPECTED_CONFIG_BYTES,
        digest=EXPECTED_CONFIG_SHA256,
        label="V5 config",
    )
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise V5Error(f"cannot load V5 config: {error}") from error
    validate_config_document(config)
    config["_path"] = str(path)
    return config


NORMALIZATION_REPLACEMENTS = {
    "centre": "center",
    "centres": "centers",
    "defence": "defense",
    "travelled": "traveled",
    "labour": "labor",
    "organised": "organized",
    "civilisation": "civilization",
    "recognisable": "recognizable",
    "kiev": "kyiv",
}


def normalize_words(value: str) -> list[str]:
    value = value.lower().replace("’", "'").replace("‘", "'")
    value = re.sub(r"(?<=\d),(?=\d)", "", value)
    value = re.sub(
        r"\b(?:[a-z]\.){2,}", lambda match: match.group(0).replace(".", ""), value
    )
    value = value.replace("-", " ")
    value = re.sub(r"[^a-z0-9']+", " ", value)
    words: list[str] = []
    for token in value.split():
        if token.endswith("'s"):
            token = token[:-2]
        elif token.endswith("s'"):
            token = token[:-1]
        words.append(NORMALIZATION_REPLACEMENTS.get(token, token))
    return words


def _subsequence_starts(words: Sequence[str], target: Sequence[str]) -> list[int]:
    if not target or len(target) > len(words):
        return []
    return [
        index
        for index in range(len(words) - len(target) + 1)
        if list(words[index : index + len(target)]) == list(target)
    ]


def stress_material(config: dict[str, Any]) -> tuple[str, dict[str, Any], list[dict[str, Any]]]:
    specification = config["stressText"]
    source = repository_path(specification["sourcePath"], directory=False)
    validate_exact_file(
        source,
        byte_count=specification["sourceBytes"],
        digest=specification["sourceSHA256"],
        label="approved chapter contracts",
    )
    document = production.load_json(source)
    if document.get("status") != specification["sourceStatus"]:
        raise V5Error("chapter-contract approval status drifted")
    by_id = {item.get("contractID"): item for item in document.get("contracts", [])}
    contract_text: dict[str, str] = {}
    all_paragraphs: list[str] = []
    for contract_id in specification["completeContractIDs"]:
        chapter = by_id.get(contract_id)
        if not chapter or chapter.get("editorApproval") != "APPROVED":
            raise V5Error(f"stress contract is not approved: {contract_id}")
        if not {
            "thesis",
            "causalSpine",
            "governingJudgement",
            "ending",
            "handoff",
        }.issubset(set(chapter.get("lockedOnApproval", []))):
            raise V5Error(f"stress contract fields are not locked: {contract_id}")
        values = [
            chapter["thesis"],
            *chapter["causalSpine"],
            chapter["governingJudgement"],
            f"{chapter['ending']['period']}. {chapter['ending']['title']}",
            chapter["ending"]["consequence"],
            chapter["handoff"],
        ]
        if any(not isinstance(value, str) or not value.strip() for value in values):
            raise V5Error(f"empty approved stress field: {contract_id}")
        material = [value.strip() for value in values]
        contract_text[contract_id] = "\n\n".join(material)
        all_paragraphs.extend(material)
    text = "\n\n".join(all_paragraphs)
    if (
        production.word_count(text) != specification["wordCount"]
        or production.sha256_text(text) != specification["textSHA256"]
    ):
        raise V5Error("shared V5 stress text drifted")
    contract_character_ranges: dict[str, tuple[int, int]] = {}
    character_cursor = 0
    for contract_id in specification["completeContractIDs"]:
        material = contract_text[contract_id]
        contract_character_ranges[contract_id] = (
            character_cursor,
            character_cursor + len(material),
        )
        character_cursor += len(material)
        if contract_id != specification["completeContractIDs"][-1]:
            character_cursor += 2
    if character_cursor != len(text):
        raise V5Error("contract character ranges do not cover the stress text")
    cues: list[dict[str, Any]] = []
    normalized_cursor = 0
    for order, cue_spec in enumerate(specification["segments"], start=1):
        character_start = cue_spec["sourceCharacterStartInclusive"]
        character_end = cue_spec["sourceCharacterEndExclusive"]
        separator = cue_spec["separatorAfter"]
        if (
            not isinstance(character_start, int)
            or not isinstance(character_end, int)
            or character_start < 0
            or character_end <= character_start
            or character_end > len(text)
        ):
            raise V5Error(f"invalid V5 cue character range: {cue_spec['segmentID']}")
        cue_text = text[character_start:character_end]
        next_start = character_end + len(separator)
        if text[character_end:next_start] != separator:
            raise V5Error(f"V5 cue separator drifted: {cue_spec['segmentID']}")
        expected_next_start = (
            specification["segments"][order].get("sourceCharacterStartInclusive")
            if order < len(specification["segments"])
            else len(text)
        )
        if next_start != expected_next_start:
            raise V5Error(f"V5 cue character ranges have a gap or overlap: {cue_spec['segmentID']}")
        boundary = cue_spec["boundaryAfter"]
        if boundary == "AUTHORED_SENTENCE":
            if separator != " " or cue_text[-1] not in ".!?":
                raise V5Error("authored sentence boundary no longer ends a sentence")
            if next_start >= len(text) or not text[next_start].isalnum():
                raise V5Error("authored sentence boundary has no following sentence")
        elif boundary == "AUTHORED_PARAGRAPH":
            if separator != "\n\n" or cue_text[-1] not in ".!?":
                raise V5Error("authored paragraph boundary drifted")
        elif boundary == "END_OF_TEXT":
            if separator or character_end != len(text):
                raise V5Error("last V5 cue does not end with the shared text")
        else:
            raise V5Error(f"unknown authored boundary: {boundary}")
        intersecting_contracts = [
            contract_id
            for contract_id in specification["completeContractIDs"]
            if character_start < contract_character_ranges[contract_id][1]
            and character_end > contract_character_ranges[contract_id][0]
        ]
        if cue_spec["contractIDs"] != intersecting_contracts:
            raise V5Error(
                f"V5 cue contract overlap drifted: {cue_spec['segmentID']}"
            )
        if (
            production.word_count(cue_text) != cue_spec["wordCount"]
            or production.sha256_text(cue_text) != cue_spec["textSHA256"]
            or cue_spec["maxTokens"] != math.ceil(cue_spec["wordCount"] * 6.5)
        ):
            raise V5Error(f"V5 cue text drifted: {cue_spec['segmentID']}")
        words = normalize_words(cue_text)
        cue = {
            **cue_spec,
            "order": order,
            "text": cue_text,
            "words": words,
            "normalizedReferenceStart": normalized_cursor,
            "normalizedReferenceEndExclusive": normalized_cursor + len(words),
            "firstAnchor": words[: config["alignment"]["anchorWords"]],
            "lastAnchor": words[-config["alignment"]["anchorWords"] :],
        }
        normalized_cursor += len(words)
        cues.append(cue)
    if "".join(
        item["text"] + item["separatorAfter"] for item in cues
    ) != text:
        raise V5Error("V5 cue sequence does not reproduce the shared text")
    full_words = normalize_words(text)
    if normalized_cursor != len(full_words):
        raise V5Error("normalized cue ranges do not cover the shared text")
    for cue in cues:
        for label in ["firstAnchor", "lastAnchor"]:
            occurrences = _subsequence_starts(full_words, cue[label])
            if len(occurrences) != 1:
                raise V5Error(
                    f"approved {cue['segmentID']} {label} is not unique: {occurrences}"
                )
    public_cues = [
        {
            key: value
            for key, value in cue.items()
            if key not in {"text", "words"}
        }
        for cue in cues
    ]
    record = {
        "source": file_binding(source),
        "sourceStatus": document["status"],
        "textSHA256": production.sha256_text(text),
        "wordCount": production.word_count(text),
        "normalizedWordCount": len(full_words),
        "cueManifest": public_cues,
        "cueManifestSHA256": production.sha256_text(canonical_json(public_cues)),
    }
    return text, record, cues


def pipeline_binding(config: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "trustDomain": TRUST_DOMAIN,
        "script": file_binding(SCRIPT_PATH),
        "config": file_binding(Path(config["_path"])),
    }


def frozen_completed_generation_pipeline_binding(
    config: dict[str, Any],
) -> dict[str, Any]:
    """Return the exact method binding that produced the completed V5 set.

    The generated cue and master bytes predate audit-only timestamp-tail
    normalization. Keeping their original script binding avoids falsely
    claiming that the revised audit code generated those immutable artifacts.
    """
    return {
        "schemaVersion": 1,
        "trustDomain": TRUST_DOMAIN,
        "script": {
            "path": str(SCRIPT_PATH.absolute()),
            "bytes": FROZEN_COMPLETED_GENERATION_SCRIPT_BYTES,
            "sha256": FROZEN_COMPLETED_GENERATION_SCRIPT_SHA256,
        },
        "config": file_binding(Path(config["_path"])),
    }


def validated_generation_pipeline_binding(
    value: Any, config: dict[str, Any]
) -> dict[str, Any]:
    current = pipeline_binding(config)
    frozen = frozen_completed_generation_pipeline_binding(config)
    if value != current and value != frozen:
        raise V5Error("V5 generation pipeline binding is not an accepted exact method")
    return value


def _binding_matches(path: Path, expected: dict[str, Any]) -> bool:
    return (
        path.is_file()
        and path.stat().st_size == expected.get("bytes")
        and sha256_file(path) == expected.get("sha256")
    )


def validate_parent_chain(config: dict[str, Any]) -> dict[str, Any]:
    parent = config["parentChain"]
    production_pipeline = repository_path(
        "native/audio/narration/pipeline.py", directory=False
    )
    production_config_path = repository_path(
        "native/audio/narration/pipeline-config.json", directory=False
    )
    uv_lock = repository_path("native/audio/narration/uv.lock", directory=False)
    v4_pipeline = repository_path(
        "native/audio/narration/provisional_pipeline.py", directory=False
    )
    v4_config_path = repository_path(
        "native/audio/narration/provisional-audit-config.json", directory=False
    )
    for path, byte_key, hash_key, label in [
        (
            production_pipeline,
            "productionPipelineBytes",
            "productionPipelineSHA256",
            "production pipeline",
        ),
        (
            production_config_path,
            "productionConfigBytes",
            "productionConfigSHA256",
            "production config",
        ),
        (uv_lock, "uvLockBytes", "uvLockSHA256", "uv lock"),
        (v4_pipeline, "v4PipelineBytes", "v4PipelineSHA256", "V4 pipeline"),
        (v4_config_path, "v4ConfigBytes", "v4ConfigSHA256", "V4 config"),
    ]:
        validate_exact_file(
            path, byte_count=parent[byte_key], digest=parent[hash_key], label=label
        )
    base_config = production.validate_config(production_config_path)
    base_binding = production.pipeline_binding(base_config)
    candidate_root = repository_path(
        config["paths"]["candidateSetRoot"], directory=True
    )
    candidate_receipt_path = repository_path(
        config["paths"]["candidateSetReceipt"], directory=False
    )
    validate_exact_file(
        candidate_receipt_path,
        byte_count=parent["candidateSetReceiptBytes"],
        digest=parent["candidateSetReceiptSHA256"],
        label="candidate-set receipt",
    )
    candidate_set = production.validate_candidate_set(
        candidate_root, base_config, base_binding
    )
    if (
        candidate_set["receiptSHA256"] != parent["candidateSetReceiptSHA256"]
        or candidate_set["receiptBytes"] != parent["candidateSetReceiptBytes"]
    ):
        raise V5Error("candidate-set validator returned a different parent")
    transcript_receipt_path = repository_path(
        config["paths"]["v4CandidateTranscriptReceipt"], directory=False
    )
    validate_exact_file(
        transcript_receipt_path,
        byte_count=parent["v4CandidateTranscriptReceiptBytes"],
        digest=parent["v4CandidateTranscriptReceiptSHA256"],
        label="V4 candidate transcript receipt",
    )
    transcript_receipt = production.load_json(transcript_receipt_path)
    transcript_root = transcript_receipt_path.parent
    if (
        transcript_receipt.get("schemaVersion") != 1
        or transcript_receipt.get("status") != "CODEX_PROVISIONAL_NON_SHIPPING"
        or transcript_receipt.get("purpose")
        != "UNPROMPTED_OFFLINE_MACHINE_TRANSCRIPTION_OF_SIX_CASTING_READINGS"
        or [item.get("candidateID") for item in transcript_receipt.get("records", [])]
        != production.EXPECTED_CANDIDATE_IDS
    ):
        raise V5Error("V4 transcript parent contract drifted")
    for transcript_record in transcript_receipt["records"]:
        candidate_id = transcript_record["candidateID"]
        expected_audio = Path(
            candidate_set["recordsByID"][candidate_id]["casting"]["path"]
        )
        transcript_path = transcript_root / f"{candidate_id}.json"
        log_path = transcript_root / f"{candidate_id}.whisper.log.txt"
        for label, path, key in [
            ("audio", expected_audio, "audio"),
            ("transcript", transcript_path, "transcript"),
            ("log", log_path, "log"),
        ]:
            confined_path(
                path,
                root=REPOSITORY_ROOT,
                must_exist=True,
                expect_directory=False,
            )
            if not _binding_matches(path, transcript_record.get(key, {})):
                raise V5Error(f"V4 transcript {label} chain broke: {candidate_id}")
    audit_path = repository_path(
        config["paths"]["v4CandidateAuditReceipt"], directory=False
    )
    validate_exact_file(
        audit_path,
        byte_count=parent["v4CandidateAuditReceiptBytes"],
        digest=parent["v4CandidateAuditReceiptSHA256"],
        label="V4 candidate audit receipt",
    )
    audit = production.load_json(audit_path)
    expected_v4_binding = {
        "schemaVersion": 2,
        "trustDomain": "CODEX_PROVISIONAL_NON_SHIPPING",
        "provisionalPipeline": file_binding(v4_pipeline),
        "provisionalConfig": file_binding(v4_config_path),
    }
    if (
        audit.get("schemaVersion") != 1
        or audit.get("status") != "CODEX_PROVISIONAL_NON_SHIPPING"
        or audit.get("trustDomain") != "CODEX_PROVISIONAL_NON_SHIPPING"
        or audit.get("pipelineBinding") != expected_v4_binding
        or audit.get("candidateSetReceipt")
        != {
            "sha256": parent["candidateSetReceiptSHA256"],
            "bytes": parent["candidateSetReceiptBytes"],
            "candidateCount": 6,
        }
        or audit.get("transcriptRunReceipt") != file_binding(transcript_receipt_path)
        or audit.get("provisionalFinalistIDs") != EXPECTED_FINALISTS
    ):
        raise V5Error("V4 candidate-audit parent chain broke")
    audit_records = {
        item.get("candidateID"): item for item in audit.get("candidateRecords", [])
    }
    for candidate_id in production.EXPECTED_CANDIDATE_IDS:
        record = audit_records.get(candidate_id)
        if record is None:
            raise V5Error(f"candidate missing from V4 audit: {candidate_id}")
        expected_audio = Path(
            candidate_set["recordsByID"][candidate_id]["casting"]["path"]
        )
        expected_transcript = transcript_root / f"{candidate_id}.json"
        if (
            record.get("audio") != file_binding(expected_audio)
            or record.get("transcript") != file_binding(expected_transcript)
        ):
            raise V5Error(f"candidate V4 audit leaf binding broke: {candidate_id}")
    return {
        "schemaVersion": 1,
        "productionPipeline": file_binding(production_pipeline),
        "productionConfig": file_binding(production_config_path),
        "uvLock": file_binding(uv_lock),
        "candidateSetReceipt": file_binding(candidate_receipt_path),
        "candidateAuditReceipt": file_binding(audit_path),
        "candidateTranscriptReceipt": file_binding(transcript_receipt_path),
        "provisionalFinalistIDs": EXPECTED_FINALISTS,
        "v4StressEvidencePermittedAsParent": False,
    }


def validate_v4_diagnostic_evidence(config: dict[str, Any], *, deep: bool) -> dict[str, Any]:
    evidence = config["v4DiagnosticEvidence"]
    root = repository_path(
        "native/audio/narration/work/provisional-audit-v4", directory=True
    )
    paths = {
        "stressSet": root / "stress-set" / "stress-set.provisional.receipt.json",
        "transcript": root / "stress-transcripts" / "transcript-run.receipt.json",
        "audit": root / "stress-audit.provisional.receipt.json",
    }
    for label, path, bytes_key, hash_key in [
        (
            "V4 stress-set receipt",
            paths["stressSet"],
            "stressSetReceiptBytes",
            "stressSetReceiptSHA256",
        ),
        (
            "V4 transcript receipt",
            paths["transcript"],
            "transcriptReceiptBytes",
            "transcriptReceiptSHA256",
        ),
        (
            "V4 audit receipt",
            paths["audit"],
            "auditReceiptBytes",
            "auditReceiptSHA256",
        ),
    ]:
        confined_path(
            path,
            root=REPOSITORY_ROOT,
            must_exist=True,
            expect_directory=False,
        )
        validate_exact_file(
            path, byte_count=evidence[bytes_key], digest=evidence[hash_key], label=label
        )
    audit = production.load_json(paths["audit"])
    passing = [
        item
        for item in audit.get("candidateRecords", [])
        if item.get("passesCompleteMachineStressGate") is True
    ]
    if (
        evidence.get("status") != "REJECTED_DIAGNOSTIC_ONLY_NEVER_A_V5_PARENT"
        or audit.get("codexProvisionalRecommendedVoiceID") is not None
        or passing
        or evidence.get("recommendedVoiceID") is not None
        or evidence.get("passingCandidateCount") != 0
    ):
        raise V5Error("V4 diagnostic evidence was promoted or reclassified")
    if deep:
        import provisional_pipeline as v4

        v4_config = v4.load_provisional_config()
        stress_receipt, stress_audio = v4.validate_stress_set(root / "stress-set", v4_config)
        transcript = v4.validate_transcript_receipt(
            root / "stress-transcripts",
            expected_audio=stress_audio,
            config=v4_config,
            purpose="UNPROMPTED_OFFLINE_MACHINE_TRANSCRIPTION_OF_TWO_PROVISIONAL_STRESS_READINGS",
        )
        if (
            file_binding(root / "stress-set" / "stress-set.provisional.receipt.json")
            != file_binding(paths["stressSet"])
            or transcript["receiptBinding"] != file_binding(paths["transcript"])
            or stress_receipt.get("provisionalFinalistIDs") != EXPECTED_FINALISTS
        ):
            raise V5Error("deep V4 diagnostic byte validation failed")
    return {
        "status": evidence["status"],
        "stressSetReceipt": file_binding(paths["stressSet"]),
        "transcriptReceipt": file_binding(paths["transcript"]),
        "auditReceipt": file_binding(paths["audit"]),
        "passingCandidateCount": 0,
        "recommendedVoiceID": None,
        "deepByteValidation": deep,
    }


def materialize_generation_result(
    results: Iterable[Any], *, max_tokens: int
) -> tuple[Any, int, dict[str, Any]]:
    import numpy as np

    materialized = list(results)
    if len(materialized) != 1:
        raise V5Error(f"expected one non-streaming generation result; got {len(materialized)}")
    result = materialized[0]
    if getattr(result, "is_streaming_chunk", False):
        raise V5Error("streaming generation chunks are prohibited")
    token_count = getattr(result, "token_count", None)
    if type(token_count) is not int or token_count <= 0:
        raise V5Error("generation result did not retain a positive tokenCount")
    if token_count >= max_tokens:
        raise V5Error(
            f"generation reached token ceiling: tokenCount={token_count}, maxTokens={max_tokens}"
        )
    sample_rate = getattr(result, "sample_rate", None)
    if type(sample_rate) is not int or sample_rate <= 0:
        raise V5Error("generation result sample rate is invalid")
    audio = np.ascontiguousarray(
        np.asarray(getattr(result, "audio", None), dtype=np.float32).reshape(-1)
    )
    if audio.size == 0 or not np.all(np.isfinite(audio)):
        raise V5Error("generation returned empty or non-finite audio")
    reported_samples = getattr(result, "samples", None)
    if type(reported_samples) is not int or reported_samples != int(audio.size):
        raise V5Error("generation sample count does not match decoded audio")
    return audio, sample_rate, {
        "tokenCount": token_count,
        "maxTokens": max_tokens,
        "tokenCeilingReached": False,
        "sampleCount": int(audio.size),
        "sampleRate": sample_rate,
        "nonStreamingResultCount": 1,
    }


def synthesize_v5_cue(
    clone_model: Any,
    *,
    text: str,
    reference_path: Path,
    reference_text: str,
    seed: int,
    max_tokens: int,
    base_config: dict[str, Any],
) -> tuple[Any, int, dict[str, Any]]:
    import numpy as np

    production.set_generation_seed(seed)
    results = clone_model.generate(
        text=text,
        ref_audio=str(reference_path),
        ref_text=reference_text,
        lang_code=base_config["language"],
        **production.generation_kwargs(base_config, max_tokens=max_tokens),
    )
    audio, sample_rate, generation = materialize_generation_result(
        results, max_tokens=max_tokens
    )
    peak = float(np.max(np.abs(audio)))
    if not math.isfinite(peak) or peak < 1e-5:
        raise V5Error("V5 cue generation returned silence")
    generation["peakAbsolute"] = peak
    return audio, sample_rate, generation


def native_float32_bytes(audio: Any) -> bytes:
    import numpy as np

    material = np.ascontiguousarray(np.asarray(audio).reshape(-1), dtype="<f4")
    if material.size == 0 or not np.all(np.isfinite(material)):
        raise V5Error("native PCM must be finite non-empty float32")
    return material.tobytes(order="C")


def native_float32_sha256(audio: Any) -> str:
    return sha256_bytes(native_float32_bytes(audio))


def read_native_audio(path: Path, config: dict[str, Any]) -> tuple[Any, dict[str, Any]]:
    import numpy as np
    from scipy.io import wavfile

    sample_rate, audio = wavfile.read(path)
    if (
        sample_rate != config["master"]["nativeSampleRate"]
        or audio.ndim != 1
        or audio.dtype != np.float32
        or audio.size == 0
        or not np.all(np.isfinite(audio))
    ):
        raise V5Error(f"invalid native cue or assembly WAV: {path}")
    return audio, {
        "file": file_binding(path),
        "sampleRate": sample_rate,
        "channels": 1,
        "sampleRepresentation": "float32",
        "sampleCount": int(audio.size),
        "durationSeconds": audio.size / sample_rate,
        "float32LESHA256": native_float32_sha256(audio),
    }


def validate_master_tools(config: dict[str, Any]) -> dict[str, Any]:
    master = config["master"]
    ffmpeg = Path(master["ffmpegPath"])
    ffprobe = Path(master["ffprobePath"])
    for label, path, bytes_key, hash_key, expected_version in [
        (
            "ffmpeg",
            ffmpeg,
            "ffmpegBytes",
            "ffmpegSHA256",
            "ffmpeg version 8.1.2",
        ),
        (
            "ffprobe",
            ffprobe,
            "ffprobeBytes",
            "ffprobeSHA256",
            "ffprobe version 8.1.2",
        ),
    ]:
        validate_no_symlink_parent_chain(path, allow_missing_leaf=False)
        validate_exact_file(
            path, byte_count=master[bytes_key], digest=master[hash_key], label=label
        )
        version = subprocess.run(
            [str(path), "-version"], check=True, capture_output=True, text=True
        ).stdout.splitlines()[0]
        if not version.startswith(expected_version):
            raise V5Error(f"{label} version drifted: {version}")
    return {"ffmpeg": file_binding(ffmpeg), "ffprobe": file_binding(ffprobe)}


def deterministic_master_command(
    native_path: Path, master_path: Path, config: dict[str, Any]
) -> list[str]:
    arguments: list[str] = []
    for argument in config["master"]["conversionArguments"]:
        arguments.append(
            argument.replace("{native}", str(native_path)).replace(
                "{master}", str(master_path)
            )
        )
    return [config["master"]["ffmpegPath"], *arguments]


def render_deterministic_master(
    native_path: Path,
    master_path: Path,
    config: dict[str, Any],
    *,
    confinement_root: Path,
) -> dict[str, Any]:
    native_path = confined_path(
        native_path,
        root=confinement_root,
        must_exist=True,
        expect_directory=False,
    )
    master_path = confined_path(
        master_path,
        root=confinement_root,
        must_exist=master_path.exists(),
        expect_directory=False if master_path.exists() else None,
    )
    master_path.parent.mkdir(parents=True, exist_ok=True)
    command = deterministic_master_command(native_path, master_path, config)
    subprocess.run(command, check=True, capture_output=True, text=True)
    return {
        "command": command,
        "commandSHA256": production.sha256_text(canonical_json(command)),
        "file": file_binding(master_path),
    }


def decode_master(path: Path, config: dict[str, Any]) -> tuple[Any, dict[str, Any]]:
    import numpy as np
    from scipy.io import wavfile

    master = config["master"]
    probe = subprocess.run(
        [
            master["ffprobePath"],
            "-v",
            "error",
            "-show_entries",
            "stream=codec_name,sample_rate,channels,bits_per_raw_sample,duration",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    streams = json.loads(probe.stdout).get("streams", [])
    if len(streams) != 1:
        raise V5Error("master must contain exactly one audio stream")
    stream = streams[0]
    sample_rate, raw = wavfile.read(path)
    if (
        stream.get("codec_name") != master["masterCodec"]
        or int(stream.get("sample_rate", 0)) != master["masterSampleRate"]
        or int(stream.get("channels", 0)) != master["masterChannels"]
        or int(stream.get("bits_per_raw_sample", 0)) != master["masterBitDepth"]
        or sample_rate != master["masterSampleRate"]
        or raw.ndim != 1
        or raw.dtype != np.int32
        or raw.size == 0
    ):
        raise V5Error("decoded master format drifted")
    if np.any(np.bitwise_and(raw, np.int32(0xFF)) != 0):
        raise V5Error("master does not contain exactly 24 valid left-justified PCM bits")
    duration = raw.size / sample_rate
    if not math.isclose(
        duration, float(stream["duration"]), rel_tol=0.0, abs_tol=1 / sample_rate
    ):
        raise V5Error("ffprobe and decoded master duration disagree")
    return raw, {
        "file": file_binding(path),
        "sampleRate": sample_rate,
        "channels": 1,
        "sampleRepresentation": "signed-int32-container-with-24-valid-PCM-bits",
        "bitDepth": 24,
        "codec": master["masterCodec"],
        "sampleCount": int(raw.size),
        "durationSeconds": duration,
    }


def verify_native_master_relation(
    native_path: Path,
    master_path: Path,
    config: dict[str, Any],
    *,
    audit_root: Path,
    confinement_root: Path,
) -> dict[str, Any]:
    native, native_record = read_native_audio(native_path, config)
    master_audio, master_record = decode_master(master_path, config)
    expected_master_samples = (
        native.size
        * config["master"]["masterSampleRate"]
        // config["master"]["nativeSampleRate"]
    )
    if master_audio.size != expected_master_samples:
        raise V5Error("decoded master duration does not match native sample duration")
    with tempfile.TemporaryDirectory(dir=audit_root, prefix="v5-master-recompute-") as temp:
        recomputed = Path(temp) / "recomputed.wav"
        render = render_deterministic_master(
            native_path,
            recomputed,
            config,
            confinement_root=confinement_root,
        )
        if (
            recomputed.stat().st_size != master_path.stat().st_size
            or sha256_file(recomputed) != sha256_file(master_path)
        ):
            raise V5Error("master is not the deterministic conversion of native assembly")
        recomputed_binding = file_binding(recomputed)
    return {
        "native": native_record,
        "master": master_record,
        "expectedMasterSampleCount": expected_master_samples,
        "decodedDurationDifferenceSamples": int(master_audio.size - expected_master_samples),
        "deterministicRecomputeSHA256": recomputed_binding["sha256"],
        "deterministicRecomputeBytes": recomputed_binding["bytes"],
        "deterministicByteEquality": True,
    }


def stress_duration_gate(duration_seconds: float, config: dict[str, Any]) -> bool:
    return (
        math.isfinite(duration_seconds)
        and config["stressText"]["minimumActualMinutes"] * 60
        <= duration_seconds
        <= config["stressText"]["maximumActualMinutes"] * 60
    )


def _unit_embedding(value: Any) -> tuple[Any, dict[str, Any]]:
    import numpy as np

    embedding = np.ascontiguousarray(np.asarray(value).reshape(-1), dtype=np.float32)
    norm = float(np.linalg.norm(embedding))
    if embedding.size == 0 or not np.all(np.isfinite(embedding)) or norm <= 0:
        raise V5Error("speaker embedding is empty, non-finite or zero")
    return embedding / norm, {
        "dimension": int(embedding.size),
        "float32LESHA256": native_float32_sha256(embedding),
        "l2Norm": norm,
    }


def identity_window_ranges(
    sample_count: int, sample_rate: int, *, window_seconds: int, hop_seconds: int
) -> list[tuple[int, int]]:
    window = window_seconds * sample_rate
    hop = hop_seconds * sample_rate
    if sample_count < window:
        raise V5Error("cue is shorter than the frozen identity window")
    starts = list(range(0, sample_count - window + 1, hop))
    final_start = sample_count - window
    if starts[-1] != final_start:
        starts.append(final_start)
    return [(start, start + window) for start in starts]


def audit_voice_identity(
    *,
    reference_audio: Any,
    cue_audio: list[tuple[str, Any]],
    sample_rate: int,
    extractor: Callable[[Any], Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    limits = config["identity"]
    reference_unit, reference_record = _unit_embedding(extractor(reference_audio))
    cue_records: list[dict[str, Any]] = []
    whole_units: list[Any] = []
    all_window_units: list[tuple[str, int, Any]] = []
    for cue_id, audio in cue_audio:
        whole_unit, whole_record = _unit_embedding(extractor(audio))
        whole_units.append(whole_unit)
        ranges = identity_window_ranges(
            len(audio),
            sample_rate,
            window_seconds=limits["windowSeconds"],
            hop_seconds=limits["hopSeconds"],
        )
        windows: list[dict[str, Any]] = []
        window_units: list[Any] = []
        for index, (start, end) in enumerate(ranges):
            unit, embedding_record = _unit_embedding(extractor(audio[start:end]))
            window_units.append(unit)
            all_window_units.append((cue_id, index, unit))
            windows.append(
                {
                    "index": index,
                    "startSampleInclusive": start,
                    "endSampleExclusive": end,
                    "startMilliseconds": start * 1000 / sample_rate,
                    "endMilliseconds": end * 1000 / sample_rate,
                    "embedding": embedding_record,
                    "cosineToReference": float(np.dot(unit, reference_unit)),
                    "cosineToWholeCue": float(np.dot(unit, whole_unit)),
                }
            )
        adjacent = [
            float(np.dot(window_units[index], window_units[index + 1]))
            for index in range(len(window_units) - 1)
        ]
        all_pairs = [
            float(np.dot(window_units[left], window_units[right]))
            for left in range(len(window_units))
            for right in range(left + 1, len(window_units))
        ]
        minimum_reference = min(item["cosineToReference"] for item in windows)
        minimum_whole = min(item["cosineToWholeCue"] for item in windows)
        minimum_adjacent = min(adjacent) if adjacent else 1.0
        minimum_all_pairs = min(all_pairs) if all_pairs else 1.0
        cue_gates = {
            "wholeCueToReference": float(np.dot(whole_unit, reference_unit))
            >= limits["minimumWholeCueToReferenceCosine"],
            "allWindowsToReference": minimum_reference
            >= limits["minimumWindowToReferenceCosine"],
            "allWindowsToWholeCue": minimum_whole
            >= limits["minimumWindowToWholeCueCosine"],
            "adjacentWindows": minimum_adjacent
            >= limits["minimumAdjacentWindowCosine"],
            "allWindowPairsWithinCue": minimum_all_pairs
            >= limits["minimumAllWindowPairCosine"],
        }
        cue_records.append(
            {
                "segmentID": cue_id,
                "wholeCueEmbedding": whole_record,
                "wholeCueCosineToReference": float(np.dot(whole_unit, reference_unit)),
                "windows": windows,
                "minimumWindowToReferenceCosine": minimum_reference,
                "minimumWindowToWholeCueCosine": minimum_whole,
                "minimumAdjacentWindowCosine": minimum_adjacent,
                "minimumAllWindowPairCosine": minimum_all_pairs,
                "gates": cue_gates,
                "passes": all(cue_gates.values()),
            }
        )
    pairwise_whole = [
        {
            "leftSegmentID": cue_audio[left][0],
            "rightSegmentID": cue_audio[right][0],
            "cosine": float(np.dot(whole_units[left], whole_units[right])),
        }
        for left in range(len(whole_units))
        for right in range(left + 1, len(whole_units))
    ]
    minimum_pairwise_whole = min(item["cosine"] for item in pairwise_whole)
    cross_cue_window_pairs = [
        float(np.dot(left[2], right[2]))
        for index, left in enumerate(all_window_units)
        for right in all_window_units[index + 1 :]
        if left[0] != right[0]
    ]
    minimum_cross_window = min(cross_cue_window_pairs)
    global_gates = {
        "allCueScreens": all(item["passes"] for item in cue_records),
        "pairwiseWholeCues": minimum_pairwise_whole
        >= limits["minimumPairwiseWholeCueCosine"],
        "allWindowsAcrossCues": minimum_cross_window
        >= limits["minimumAllWindowPairCosine"],
    }
    return {
        "method": limits["method"],
        "windowSeconds": limits["windowSeconds"],
        "hopSeconds": limits["hopSeconds"],
        "referenceEmbedding": reference_record,
        "cueRecords": cue_records,
        "pairwiseWholeCueCosines": pairwise_whole,
        "minimumPairwiseWholeCueCosine": minimum_pairwise_whole,
        "minimumCrossCueWindowCosine": minimum_cross_window,
        "gates": global_gates,
        "passes": all(global_gates.values()),
    }


class QwenSpeakerExtractor:
    def __init__(self, model: Any):
        self.model = model

    def __call__(self, audio: Any) -> Any:
        import mlx.core as mx
        import numpy as np

        return np.asarray(
            self.model.extract_speaker_embedding(
                mx.array(np.ascontiguousarray(audio, dtype=np.float32))
            ),
            dtype=np.float32,
        ).reshape(-1)


def validate_asr_tools(config: dict[str, Any]) -> dict[str, Any]:
    asr = config["offlineASR"]
    if asr["arguments"] != EXPECTED_ASR_ARGUMENTS:
        raise V5Error("ASR arguments changed after config validation")
    executable = Path(asr["executablePath"])
    model = Path(asr["modelPath"])
    for label, path, byte_key, hash_key in [
        ("whisper executable", executable, "executableBytes", "executableSHA256"),
        ("Whisper model", model, "modelBytes", "modelSHA256"),
    ]:
        validate_no_symlink_parent_chain(path, allow_missing_leaf=False)
        validate_exact_file(
            path, byte_count=asr[byte_key], digest=asr[hash_key], label=label
        )
    version = subprocess.run(
        [str(executable), "--version"], check=True, capture_output=True, text=True
    )
    version_text = version.stdout + "\n" + version.stderr
    if f"whisper.cpp version: {asr['version']}" not in version_text:
        raise V5Error("Whisper executable version drifted")
    return {
        "engine": asr["engine"],
        "version": asr["version"],
        "executable": file_binding(executable),
        "modelName": asr["modelName"],
        "model": file_binding(model),
        "arguments": list(asr["arguments"]),
        "answerPromptUsed": False,
        "externalTranscriptReceiptUsed": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }


def pinned_whisper_command(
    master_path: Path, output_prefix: Path, config: dict[str, Any]
) -> list[str]:
    asr = config["offlineASR"]
    if asr["arguments"] != EXPECTED_ASR_ARGUMENTS:
        raise V5Error("cannot build a command from drifted ASR arguments")
    return [
        asr["executablePath"],
        "--model",
        asr["modelPath"],
        *EXPECTED_ASR_ARGUMENTS,
        "--output-file",
        str(output_prefix),
        str(master_path),
    ]


def run_pinned_whisper(
    *,
    master_path: Path,
    output_prefix: Path,
    config: dict[str, Any],
    confinement_root: Path,
    runner: Callable[..., Any] = subprocess.run,
) -> tuple[Path, dict[str, Any]]:
    master_path = confined_path(
        master_path,
        root=confinement_root,
        must_exist=True,
        expect_directory=False,
    )
    output_prefix = confined_path(
        output_prefix,
        root=confinement_root,
        must_exist=output_prefix.exists(),
        expect_directory=False if output_prefix.exists() else None,
    )
    if output_prefix.exists():
        raise V5Error(f"in-process ASR prefix already exists: {output_prefix}")
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    transcript_path = output_prefix.with_suffix(".json")
    validate_no_symlink_parent_chain(transcript_path, allow_missing_leaf=True)
    if os.path.lexists(transcript_path):
        raise V5Error(f"in-process ASR output already exists: {transcript_path}")
    command = pinned_whisper_command(master_path, output_prefix, config)
    completed = runner(command, check=True, capture_output=True, text=True)
    transcript_path = confined_path(
        transcript_path,
        root=confinement_root,
        must_exist=True,
        expect_directory=False,
    )
    document = production.load_json(transcript_path)
    if (
        document.get("result", {}).get("language") != "en"
        or document.get("params", {}).get("language") != "en"
        or document.get("params", {}).get("translate") is not False
        or document.get("params", {}).get("model") != config["offlineASR"]["modelPath"]
    ):
        raise V5Error("in-process Whisper output parameters drifted")
    log_path = output_prefix.with_suffix(".whisper.log.txt")
    log_path = confined_path(
        log_path,
        root=confinement_root,
        must_exist=False,
    )
    stdout = getattr(completed, "stdout", "") or ""
    stderr = getattr(completed, "stderr", "") or ""
    log_path.write_text(stdout + stderr, encoding="utf-8")
    return transcript_path, {
        "command": command,
        "commandSHA256": production.sha256_text(canonical_json(command)),
        "master": file_binding(master_path),
        "transcript": file_binding(transcript_path),
        "log": file_binding(log_path),
        "answerPromptUsed": False,
        "externalReceiptUsed": False,
    }


@dataclass(frozen=True)
class TimedWord:
    text: str
    start_ms: float
    end_ms: float
    source_token_start: int
    source_token_end_exclusive: int


def timed_words_from_whisper(
    document: dict[str, Any], *, master_duration_ms: float
) -> tuple[list[TimedWord], dict[str, Any]]:
    if (
        not isinstance(master_duration_ms, (int, float))
        or not math.isfinite(master_duration_ms)
        or master_duration_ms <= 0
    ):
        raise V5Error("timed-word grouping requires a finite positive master duration")
    if document.get("result", {}).get("language") != "en":
        raise V5Error("timed-word grouping requires an English Whisper result")
    segments = document.get("transcription")
    if not isinstance(segments, list) or not segments:
        raise V5Error("Whisper transcript contains no segments")
    raw_groups: list[tuple[str, float, float, int, int]] = []
    pieces: list[str] = []
    group_start = group_end = 0.0
    group_token_start = 0
    token_index = 0
    previous_token_start = -1.0
    previous_token_end = -1.0
    clipped_token_count = 0
    clipped_lexical_token_count = 0
    clipped_nonlexical_token_count = 0
    dropped_token_count = 0
    dropped_lexical_token_count = 0
    dropped_nonlexical_token_count = 0
    maximum_timestamp_overrun_ms = 0.0

    def finish_group() -> None:
        nonlocal pieces
        if pieces:
            raw_groups.append(
                (
                    "".join(pieces),
                    group_start,
                    group_end,
                    group_token_start,
                    token_index,
                )
            )
            pieces = []

    for segment in segments:
        tokens = segment.get("tokens")
        if not isinstance(tokens, list):
            raise V5Error("Whisper segment has no token inventory")
        for token in tokens:
            text = token.get("text")
            offsets = token.get("offsets", {})
            start = offsets.get("from")
            end = offsets.get("to")
            if (
                not isinstance(text, str)
                or type(start) is not int
                or type(end) is not int
            ):
                raise V5Error("Whisper token lacks exact text or millisecond offsets")
            if start < 0 or end < start:
                raise V5Error("Whisper token lies outside the decoded master")
            if (
                start < previous_token_start
                or end < previous_token_end
                or start < previous_token_end
            ):
                raise V5Error("Whisper token offsets are not monotone")
            previous_token_start = float(start)
            previous_token_end = float(end)
            special = text.startswith("[_") and text.endswith("]")
            lexical = not special and bool(normalize_words(text))
            bounded_start = float(start)
            bounded_end = float(end)
            if end > master_duration_ms:
                overrun = float(end) - master_duration_ms
                if overrun > WHISPER_TIMESTAMP_TAIL_TOLERANCE_MS:
                    raise V5Error("Whisper token lies outside the decoded master")
                maximum_timestamp_overrun_ms = max(
                    maximum_timestamp_overrun_ms, overrun
                )
                if start >= master_duration_ms:
                    finish_group()
                    dropped_token_count += 1
                    if lexical:
                        dropped_lexical_token_count += 1
                    else:
                        dropped_nonlexical_token_count += 1
                    token_index += 1
                    continue
                bounded_start = min(bounded_start, master_duration_ms)
                bounded_end = master_duration_ms
                clipped_token_count += 1
                if lexical:
                    clipped_lexical_token_count += 1
                else:
                    clipped_nonlexical_token_count += 1
            if special:
                finish_group()
                token_index += 1
                continue
            begins_word = bool(text[:1].isspace())
            if begins_word and pieces:
                finish_group()
            if not pieces:
                group_start = bounded_start
                group_end = bounded_end
                group_token_start = token_index
            else:
                group_end = bounded_end
            pieces.append(text)
            token_index += 1
        finish_group()
    finish_group()
    words: list[TimedWord] = []
    split_group_count = 0
    for raw, start, end, token_start, token_end in raw_groups:
        normalized = normalize_words(raw)
        if not normalized:
            continue
        if len(normalized) > 1:
            split_group_count += 1
        duration = max(0.0, end - start)
        for index, word in enumerate(normalized):
            word_start = start + duration * index / len(normalized)
            word_end = start + duration * (index + 1) / len(normalized)
            if words and (
                word_start < words[-1].end_ms or word_end < words[-1].end_ms
            ):
                raise V5Error("token-to-word grouping produced non-monotone word time")
            words.append(
                TimedWord(
                    text=word,
                    start_ms=word_start,
                    end_ms=word_end,
                    source_token_start=token_start,
                    source_token_end_exclusive=token_end,
                )
            )
    if not words:
        raise V5Error("token-to-word grouping produced no lexical words")
    return words, {
        "algorithm": (
            "Whisper BPE leading-space grouping with deterministic intra-token "
            "time partition, clipped overlap, and bounded decoder-tail removal"
        ),
        "sourceTokenCount": token_index,
        "rawLexicalGroupCount": len(raw_groups),
        "splitLexicalGroupCount": split_group_count,
        "timedWordCount": len(words),
        "firstWordStartMilliseconds": words[0].start_ms,
        "lastWordEndMilliseconds": words[-1].end_ms,
        "timestampTailToleranceMilliseconds": WHISPER_TIMESTAMP_TAIL_TOLERANCE_MS,
        "clippedSourceTokenCount": clipped_token_count,
        "clippedLexicalTokenCount": clipped_lexical_token_count,
        "clippedNonLexicalTokenCount": clipped_nonlexical_token_count,
        "droppedSourceTokenCount": dropped_token_count,
        "droppedLexicalTokenCount": dropped_lexical_token_count,
        "droppedNonLexicalTokenCount": dropped_nonlexical_token_count,
        "maximumTimestampOverrunMilliseconds": maximum_timestamp_overrun_ms,
        "monotone": True,
        "boundedByDecodedMaster": True,
    }


@dataclass(frozen=True)
class AlignmentStep:
    operation: str
    reference_index: int | None
    hypothesis_index: int | None


def _levenshtein_score_row(left: Sequence[str], right: Sequence[str]) -> list[int]:
    previous = list(range(len(right) + 1))
    for left_index, left_word in enumerate(left, start=1):
        current = [left_index] + [0] * len(right)
        for right_index, right_word in enumerate(right, start=1):
            substitution = previous[right_index - 1] + (left_word != right_word)
            deletion = previous[right_index] + 1
            insertion = current[right_index - 1] + 1
            current[right_index] = min(substitution, deletion, insertion)
        previous = current
    return previous


def _small_global_alignment(
    reference: Sequence[str],
    hypothesis: Sequence[str],
    reference_offset: int,
    hypothesis_offset: int,
) -> list[AlignmentStep]:
    rows = len(reference) + 1
    columns = len(hypothesis) + 1
    matrix = [[0] * columns for _ in range(rows)]
    for index in range(rows):
        matrix[index][0] = index
    for index in range(columns):
        matrix[0][index] = index
    for row in range(1, rows):
        for column in range(1, columns):
            matrix[row][column] = min(
                matrix[row - 1][column - 1]
                + (reference[row - 1] != hypothesis[column - 1]),
                matrix[row - 1][column] + 1,
                matrix[row][column - 1] + 1,
            )
    row = len(reference)
    column = len(hypothesis)
    reverse: list[AlignmentStep] = []
    while row or column:
        if row and column:
            cost = reference[row - 1] != hypothesis[column - 1]
            if matrix[row][column] == matrix[row - 1][column - 1] + cost:
                reverse.append(
                    AlignmentStep(
                        "equal" if cost == 0 else "substitute",
                        reference_offset + row - 1,
                        hypothesis_offset + column - 1,
                    )
                )
                row -= 1
                column -= 1
                continue
        if row and matrix[row][column] == matrix[row - 1][column] + 1:
            reverse.append(
                AlignmentStep("delete", reference_offset + row - 1, None)
            )
            row -= 1
            continue
        if column and matrix[row][column] == matrix[row][column - 1] + 1:
            reverse.append(
                AlignmentStep("insert", None, hypothesis_offset + column - 1)
            )
            column -= 1
            continue
        raise V5Error("small Levenshtein backtrace reached an impossible cell")
    return list(reversed(reverse))


def monotone_global_alignment(
    reference: Sequence[str], hypothesis: Sequence[str]
) -> tuple[list[AlignmentStep], dict[str, Any]]:
    def recurse(
        left: Sequence[str],
        right: Sequence[str],
        left_offset: int,
        right_offset: int,
    ) -> list[AlignmentStep]:
        if not left:
            return [
                AlignmentStep("insert", None, right_offset + index)
                for index in range(len(right))
            ]
        if not right:
            return [
                AlignmentStep("delete", left_offset + index, None)
                for index in range(len(left))
            ]
        if len(left) <= 2 or len(right) <= 2:
            return _small_global_alignment(left, right, left_offset, right_offset)
        middle = len(left) // 2
        forward = _levenshtein_score_row(left[:middle], right)
        backward = _levenshtein_score_row(left[middle:][::-1], right[::-1])
        split = min(
            range(len(right) + 1),
            key=lambda index: (forward[index] + backward[len(right) - index], index),
        )
        return recurse(left[:middle], right[:split], left_offset, right_offset) + recurse(
            left[middle:],
            right[split:],
            left_offset + middle,
            right_offset + split,
        )

    steps = recurse(reference, hypothesis, 0, 0)
    expected_reference = 0
    expected_hypothesis = 0
    counts = Counter(step.operation for step in steps)
    for step in steps:
        if step.reference_index is not None:
            if step.reference_index != expected_reference:
                raise V5Error("alignment reference projection is not monotone and complete")
            expected_reference += 1
        if step.hypothesis_index is not None:
            if step.hypothesis_index != expected_hypothesis:
                raise V5Error("alignment hypothesis projection is not monotone and complete")
            expected_hypothesis += 1
    if expected_reference != len(reference) or expected_hypothesis != len(hypothesis):
        raise V5Error("alignment did not consume both complete word sequences")
    distance = counts["substitute"] + counts["delete"] + counts["insert"]
    return steps, {
        "algorithm": "Hirschberg global Levenshtein with deterministic monotone backtrace",
        "referenceWordCount": len(reference),
        "hypothesisWordCount": len(hypothesis),
        "editDistance": distance,
        "wordAlignmentErrorRate": distance / max(1, len(reference)),
        "equal": counts["equal"],
        "substitute": counts["substitute"],
        "delete": counts["delete"],
        "insert": counts["insert"],
        "monotone": True,
        "complete": True,
        "alignmentSHA256": production.sha256_text(
            canonical_json(
                [
                    [step.operation, step.reference_index, step.hypothesis_index]
                    for step in steps
                ]
            )
        ),
    }


def _maximum_false_run(values: Sequence[bool]) -> int:
    maximum = current = 0
    for value in values:
        if value:
            current = 0
        else:
            current += 1
            maximum = max(maximum, current)
    return maximum


def project_alignment_to_cues(
    *,
    reference_words: list[str],
    hypothesis_words: list[TimedWord],
    steps: list[AlignmentStep],
    cues: list[dict[str, Any]],
    cue_sample_ranges: list[dict[str, Any]],
    sample_rate: int,
    config: dict[str, Any],
) -> dict[str, Any]:
    if [item.get("segmentID") for item in cue_sample_ranges] != [
        cue["segmentID"] for cue in cues
    ]:
        raise V5Error("cue sample ranges do not match the frozen cue sequence")
    exact_ref_to_hyp: dict[int, int] = {}
    exact_hyp_to_ref: dict[int, int] = {}
    for step in steps:
        if step.operation == "equal":
            assert step.reference_index is not None and step.hypothesis_index is not None
            exact_ref_to_hyp[step.reference_index] = step.hypothesis_index
            exact_hyp_to_ref[step.hypothesis_index] = step.reference_index
    hypothesis_text = [word.text for word in hypothesis_words]
    limits = config["alignment"]
    anchor_positions: list[dict[str, Any]] = []
    for cue in cues:
        first_occurrences = _subsequence_starts(hypothesis_text, cue["firstAnchor"])
        last_occurrences = _subsequence_starts(hypothesis_text, cue["lastAnchor"])
        anchor_positions.append(
            {
                "firstOccurrences": first_occurrences,
                "lastOccurrences": last_occurrences,
                "first": first_occurrences[0] if len(first_occurrences) == 1 else None,
                "last": last_occurrences[0] if len(last_occurrences) == 1 else None,
            }
        )
    cue_records: list[dict[str, Any]] = []
    for cue_index, (cue, sample_range) in enumerate(
        zip(cues, cue_sample_ranges, strict=True)
    ):
        reference_start = cue["normalizedReferenceStart"]
        reference_end = cue["normalizedReferenceEndExclusive"]
        expected_start_ms = sample_range["startSampleInclusive"] * 1000 / sample_rate
        expected_end_ms = sample_range["endSampleExclusive"] * 1000 / sample_rate
        anchor_position = anchor_positions[cue_index]
        first_occurrences = anchor_position["firstOccurrences"]
        last_occurrences = anchor_position["lastOccurrences"]
        first_unique = len(first_occurrences) == 1
        last_unique = len(last_occurrences) == 1
        first_hypothesis = anchor_position["first"]
        last_hypothesis = anchor_position["last"]
        first_alignment_exact = bool(
            first_unique
            and all(
                exact_ref_to_hyp.get(reference_start + offset)
                == first_hypothesis + offset
                for offset in range(limits["anchorWords"])
            )
        )
        last_reference_start = reference_end - limits["anchorWords"]
        last_alignment_exact = bool(
            last_unique
            and all(
                exact_ref_to_hyp.get(last_reference_start + offset)
                == last_hypothesis + offset
                for offset in range(limits["anchorWords"])
            )
        )
        if first_unique:
            actual_start_ms = hypothesis_words[first_hypothesis].start_ms
            start_error = actual_start_ms - expected_start_ms
        else:
            actual_start_ms = None
            start_error = math.inf
        if last_unique:
            last_index = last_hypothesis + limits["anchorWords"] - 1
            actual_end_ms = hypothesis_words[last_index].end_ms
            end_error = actual_end_ms - expected_end_ms
        else:
            actual_end_ms = None
            end_error = math.inf
        reference_exact = [
            reference_index in exact_ref_to_hyp
            for reference_index in range(reference_start, reference_end)
        ]
        coverage = sum(reference_exact) / len(reference_exact)
        maximum_reference_run = _maximum_false_run(reference_exact)
        next_first = (
            anchor_positions[cue_index + 1]["first"]
            if cue_index + 1 < len(anchor_positions)
            else len(hypothesis_words)
        )
        partition_start = 0 if cue_index == 0 else first_hypothesis
        partition_end = next_first
        if (
            first_unique
            and last_unique
            and partition_start is not None
            and partition_end is not None
            and partition_start <= first_hypothesis <= last_hypothesis
            and last_hypothesis + limits["anchorWords"] <= partition_end
        ):
            hypothesis_exact = [
                hypothesis_index in exact_hyp_to_ref
                and reference_start
                <= exact_hyp_to_ref[hypothesis_index]
                < reference_end
                for hypothesis_index in range(partition_start, partition_end)
            ]
            maximum_hypothesis_run = _maximum_false_run(hypothesis_exact)
            hypothesis_coverage = sum(hypothesis_exact) / max(1, len(hypothesis_exact))
            projected_hypothesis_range = [partition_start, partition_end]
        else:
            maximum_hypothesis_run = len(hypothesis_words)
            hypothesis_coverage = 0.0
            projected_hypothesis_range = None
        gates = {
            "firstAnchorUnique": first_unique,
            "lastAnchorUnique": last_unique,
            "firstAnchorAlignedExact": first_alignment_exact,
            "lastAnchorAlignedExact": last_alignment_exact,
            "minimumExactReferenceCoverage": coverage
            >= limits["minimumExactReferenceCoveragePerCue"],
            "minimumExactHypothesisCoverage": hypothesis_coverage
            >= limits["minimumExactHypothesisCoveragePerCue"],
            "maximumNonmatchingReferenceRun": maximum_reference_run
            <= limits["maximumNonmatchingReferenceRunWordsPerCue"],
            "maximumNonmatchingHypothesisRun": maximum_hypothesis_run
            <= limits["maximumNonmatchingHypothesisRunWordsPerCue"],
            "startBoundaryTolerance": abs(start_error)
            <= limits["boundaryToleranceMilliseconds"],
            "endBoundaryTolerance": abs(end_error)
            <= limits["boundaryToleranceMilliseconds"],
        }
        cue_records.append(
            {
                "segmentID": cue["segmentID"],
                "referenceRange": [reference_start, reference_end],
                "sampleRange": [
                    sample_range["startSampleInclusive"],
                    sample_range["endSampleExclusive"],
                ],
                "expectedStartMilliseconds": expected_start_ms,
                "expectedEndMilliseconds": expected_end_ms,
                "firstAnchor": cue["firstAnchor"],
                "lastAnchor": cue["lastAnchor"],
                "firstAnchorHypothesisOccurrences": first_occurrences,
                "lastAnchorHypothesisOccurrences": last_occurrences,
                "projectedHypothesisRange": projected_hypothesis_range,
                "actualStartMilliseconds": actual_start_ms,
                "actualEndMilliseconds": actual_end_ms,
                "startBoundaryErrorMilliseconds": start_error,
                "endBoundaryErrorMilliseconds": end_error,
                "exactReferenceCoverage": coverage,
                "exactHypothesisCoverage": hypothesis_coverage,
                "maximumNonmatchingReferenceRunWords": maximum_reference_run,
                "maximumNonmatchingHypothesisRunWords": maximum_hypothesis_run,
                "gates": gates,
                "passes": all(gates.values()),
            }
        )
    return {
        "cueRecords": cue_records,
        "allCuesPass": all(item["passes"] for item in cue_records),
        "anchorWords": limits["anchorWords"],
        "boundaryToleranceMilliseconds": limits["boundaryToleranceMilliseconds"],
        "ambiguousAnchorFails": limits["ambiguousAnchorFails"],
    }


def reference_aware_repetition(
    reference: Sequence[str], hypothesis: Sequence[str], config: dict[str, Any]
) -> dict[str, Any]:
    settings = config["repetition"]
    size = settings["ngramSize"]
    reference_counts = Counter(
        tuple(reference[index : index + size])
        for index in range(max(0, len(reference) - size + 1))
    )
    hypothesis_counts = Counter(
        tuple(hypothesis[index : index + size])
        for index in range(max(0, len(hypothesis) - size + 1))
    )
    excess: list[tuple[tuple[str, ...], int, int, int]] = []
    for ngram, hypothesis_count in hypothesis_counts.items():
        if hypothesis_count < settings["minimumHypothesisOccurrences"]:
            continue
        reference_count = reference_counts.get(ngram, 0)
        excess_count = max(0, hypothesis_count - reference_count)
        if excess_count:
            excess.append((ngram, reference_count, hypothesis_count, excess_count))
    total_hypothesis_ngrams = max(0, len(hypothesis) - size + 1)
    total_excess = sum(item[3] for item in excess)
    fraction = total_excess / max(1, total_hypothesis_ngrams)
    excess.sort(key=lambda item: (-item[3], item[0]))
    return {
        "ngramSize": size,
        "minimumHypothesisOccurrences": settings["minimumHypothesisOccurrences"],
        "referenceNgramCount": sum(reference_counts.values()),
        "hypothesisNgramCount": total_hypothesis_ngrams,
        "excessOccurrenceCount": total_excess,
        "excessOccurrenceFraction": fraction,
        "maximumAllowedExcessOccurrenceFraction": settings[
            "maximumExcessOccurrenceFraction"
        ],
        "topExcessNgrams": [
            {
                "text": " ".join(ngram),
                "referenceOccurrences": reference_count,
                "hypothesisOccurrences": hypothesis_count,
                "excessOccurrences": excess_count,
            }
            for ngram, reference_count, hypothesis_count, excess_count in excess[:20]
        ],
        "passes": fraction <= settings["maximumExcessOccurrenceFraction"],
    }


def cue_tempo_audit(
    cues: list[dict[str, Any]],
    cue_sample_ranges: list[dict[str, Any]],
    sample_rate: int,
    config: dict[str, Any],
) -> dict[str, Any]:
    settings = config["tempo"]
    records: list[dict[str, Any]] = []
    tempos: list[float] = []
    for cue, sample_range in zip(cues, cue_sample_ranges, strict=True):
        samples = (
            sample_range["endSampleExclusive"]
            - sample_range["startSampleInclusive"]
        )
        if samples <= 0:
            raise V5Error("cue sample range is empty or reversed")
        minutes = samples / sample_rate / 60
        words_per_minute = cue["wordCount"] / minutes
        tempos.append(words_per_minute)
        records.append(
            {
                "segmentID": cue["segmentID"],
                "wordCount": cue["wordCount"],
                "durationSeconds": samples / sample_rate,
                "wordsPerMinute": words_per_minute,
            }
        )
    median_tempo = median(tempos)
    for record in records:
        deviation = abs(record["wordsPerMinute"] / median_tempo - 1)
        gates = {
            "absoluteMinimum": record["wordsPerMinute"]
            >= settings["minimumWordsPerMinute"],
            "absoluteMaximum": record["wordsPerMinute"]
            <= settings["maximumWordsPerMinute"],
            "medianRelativeDeviation": deviation
            <= settings["maximumRelativeDeviationFromCueMedian"],
        }
        record["relativeDeviationFromMedian"] = deviation
        record["gates"] = gates
        record["passes"] = all(gates.values())
    return {
        "medianWordsPerMinute": median_tempo,
        "cueRecords": records,
        "passes": all(record["passes"] for record in records),
    }


def silence_audit(
    audio: Any,
    *,
    sample_rate: int,
    cue_sample_ranges: list[dict[str, Any]],
    config: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    settings = config["silence"]
    material = np.asarray(audio, dtype=np.float32).reshape(-1)
    frame = round(sample_rate * settings["frameMilliseconds"] / 1000)
    hop = round(sample_rate * settings["hopMilliseconds"] / 1000)
    if material.size < frame or frame <= 0 or hop <= 0:
        raise V5Error("audio is too short for the frozen silence analysis")
    squared = material.astype(np.float64) ** 2
    cumulative = np.concatenate(([0.0], np.cumsum(squared)))
    starts = np.arange(0, material.size - frame + 1, hop, dtype=np.int64)
    rms = np.sqrt((cumulative[starts + frame] - cumulative[starts]) / frame + 1e-15)
    silent = rms < 10 ** (settings["thresholdDBFS"] / 20)
    total_fraction = float(np.mean(silent))

    silence_threshold = 10 ** (settings["thresholdDBFS"] / 20)

    def window_is_silent(start_sample: int) -> bool:
        mean_square = (
            cumulative[start_sample + frame] - cumulative[start_sample]
        ) / frame
        return math.sqrt(mean_square + 1e-15) < silence_threshold

    def cue_edge_silence_samples(
        start_sample: int, end_sample: int, *, leading: bool
    ) -> int:
        if (
            start_sample < 0
            or end_sample > material.size
            or end_sample - start_sample < frame
        ):
            raise V5Error("cue range is outside audio or too short for silence analysis")
        if leading:
            frame_starts = range(start_sample, end_sample - frame + 1, hop)
        else:
            frame_starts = range(end_sample - frame, start_sample - 1, -hop)
        silent_frames = 0
        for frame_start in frame_starts:
            if not window_is_silent(frame_start):
                break
            silent_frames += 1
        return (silent_frames - 1) * hop + frame if silent_frames else 0

    cue_records: list[dict[str, Any]] = []
    previous_end: int | None = None
    for cue in cue_sample_ranges:
        start_sample = cue["startSampleInclusive"]
        end_sample = cue["endSampleExclusive"]
        if previous_end is None:
            if start_sample != 0:
                raise V5Error("first cue range must begin at the first native sample")
        elif start_sample != previous_end:
            raise V5Error("cue sample ranges are not contiguous")
        leading_samples = cue_edge_silence_samples(
            start_sample, end_sample, leading=True
        )
        trailing_samples = cue_edge_silence_samples(
            start_sample, end_sample, leading=False
        )
        leading_ms = leading_samples * 1000 / sample_rate
        trailing_ms = trailing_samples * 1000 / sample_rate
        gates = {
            "leadingSilence": leading_ms
            <= settings["maximumLeadingOrTrailingCueSilenceMilliseconds"],
            "trailingSilence": trailing_ms
            <= settings["maximumLeadingOrTrailingCueSilenceMilliseconds"],
        }
        cue_records.append(
            {
                "segmentID": cue["segmentID"],
                "leadingSilenceMilliseconds": leading_ms,
                "trailingSilenceMilliseconds": trailing_ms,
                "gates": gates,
                "passes": all(gates.values()),
            }
        )
        previous_end = end_sample
    if previous_end != material.size:
        raise V5Error("final cue range must end at the final native sample")
    boundary_records: list[dict[str, Any]] = []
    for index, (left, right) in enumerate(
        zip(cue_sample_ranges, cue_sample_ranges[1:])
    ):
        if left["endSampleExclusive"] != right["startSampleInclusive"]:
            raise V5Error("cue sample ranges are not contiguous at a boundary")
        left_ms = cue_records[index]["trailingSilenceMilliseconds"]
        right_ms = cue_records[index + 1]["leadingSilenceMilliseconds"]
        duration_ms = left_ms + right_ms
        boundary_records.append(
            {
                "leftSegmentID": left["segmentID"],
                "rightSegmentID": right["segmentID"],
                "sample": left["endSampleExclusive"],
                "leftTrailingSilenceMilliseconds": left_ms,
                "rightLeadingSilenceMilliseconds": right_ms,
                "silenceMilliseconds": duration_ms,
                "passes": duration_ms
                <= settings["maximumCueBoundarySilenceMilliseconds"],
            }
        )
    gates = {
        "totalSilence": total_fraction <= settings["maximumTotalSilenceFraction"],
        "allCueEdges": all(item["passes"] for item in cue_records),
        "allCueBoundaries": all(item["passes"] for item in boundary_records),
    }
    return {
        "thresholdDBFS": settings["thresholdDBFS"],
        "frameMilliseconds": settings["frameMilliseconds"],
        "hopMilliseconds": settings["hopMilliseconds"],
        "totalSilenceFraction": total_fraction,
        "maximumTotalSilenceFraction": settings["maximumTotalSilenceFraction"],
        "cueRecords": cue_records,
        "boundaryRecords": boundary_records,
        "gates": gates,
        "passes": all(gates.values()),
    }


def _cue_commit_relative(candidate_id: str, segment_id: str) -> Path:
    return Path("cue-commits") / candidate_id / segment_id


def _candidate_commit_relative(candidate_id: str) -> Path:
    return Path("candidates") / candidate_id


def _expected_generation_settings(
    base_config: dict[str, Any], *, max_tokens: int
) -> dict[str, Any]:
    return {
        "language": base_config["language"],
        **production.generation_kwargs(base_config, max_tokens=max_tokens),
    }


def validate_generation_inventory(
    output_root: Path, config: dict[str, Any], cues: list[dict[str, Any]]
) -> None:
    output_root = confined_path(
        output_root,
        root=_v5_work_root(config, create=False),
        must_exist=True,
        expect_directory=True,
    )
    allowed_directories = {Path("."), Path("cue-commits"), Path("candidates")}
    allowed_files = {
        Path("generation-progress.v5.receipt.json"),
        Path("stress-set.v5.receipt.json"),
    }
    for candidate_id in EXPECTED_FINALISTS:
        candidate_cues = Path("cue-commits") / candidate_id
        allowed_directories.add(candidate_cues)
        for cue in cues:
            commit = candidate_cues / cue["segmentID"]
            allowed_directories.add(commit)
            allowed_files.add(commit / "audio-f32.wav")
            allowed_files.add(commit / "cue.v5.receipt.json")
        candidate = Path("candidates") / candidate_id
        allowed_directories.add(candidate)
        allowed_files.add(candidate / "assembled-f32.wav")
        allowed_files.add(candidate / "stress.wav")
        allowed_files.add(candidate / "candidate.v5.receipt.json")
    for path in output_root.rglob("*"):
        validate_no_symlink_parent_chain(path, allow_missing_leaf=False)
        relative = path.relative_to(output_root)
        if path.is_dir():
            if relative not in allowed_directories:
                raise V5Error(f"unexpected V5 generation directory: {relative}")
        elif path.is_file():
            if relative not in allowed_files:
                raise V5Error(f"unexpected V5 generation file: {relative}")
        else:
            raise V5Error(f"unsupported V5 generation filesystem object: {relative}")


def _cue_public_spec(cue: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in cue.items() if key not in {"text", "words"}}


def validate_cue_commit(
    *,
    output_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    cue: dict[str, Any],
    config: dict[str, Any],
    base_config: dict[str, Any],
    parent_chain: dict[str, Any],
    model_receipt: dict[str, Any],
    identity_text_sha256: str,
    expected_pipeline_binding: dict[str, Any] | None = None,
) -> dict[str, Any]:
    import numpy as np

    commit = output_root / _cue_commit_relative(candidate_id, cue["segmentID"])
    commit = confined_path(
        commit,
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    audio_path = confined_path(
        commit / "audio-f32.wav",
        root=commit,
        must_exist=True,
        expect_directory=False,
    )
    receipt_path = confined_path(
        commit / "cue.v5.receipt.json",
        root=commit,
        must_exist=True,
        expect_directory=False,
    )
    if {item.name for item in commit.iterdir()} != {
        "audio-f32.wav",
        "cue.v5.receipt.json",
    }:
        raise V5Error(f"cue commit contains unexpected files: {candidate_id}/{cue['segmentID']}")
    receipt = production.load_json(receipt_path)
    audio, decoded = read_native_audio(audio_path, config)
    expected_seed = candidate["stressSeed"] + cue["seedOffset"]
    generation = receipt.get("generation", {})
    generation_binding = expected_pipeline_binding or pipeline_binding(config)
    token_count = generation.get("tokenCount")
    relative_audio = (
        _cue_commit_relative(candidate_id, cue["segmentID"]) / "audio-f32.wav"
    ).as_posix()
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("status") != CUE_COMMIT_STATUS
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("pipelineBinding") != generation_binding
        or receipt.get("parentChain") != parent_chain
        or receipt.get("voiceCloneModel") != model_receipt
        or receipt.get("candidateID") != candidate_id
        or receipt.get("reference")
        != {
            "sha256": parent_candidate["reference"]["sha256"],
            "bytes": parent_candidate["reference"]["bytes"],
        }
        or receipt.get("instructionSHA256") != parent_candidate["instructionSHA256"]
        or receipt.get("baseStressSeed") != candidate["stressSeed"]
        or receipt.get("identityReferenceTextSHA256") != identity_text_sha256
        or receipt.get("cueSpec") != _cue_public_spec(cue)
        or receipt.get("generationSeed") != expected_seed
        or receipt.get("generationSettings")
        != _expected_generation_settings(base_config, max_tokens=cue["maxTokens"])
        or type(token_count) is not int
        or token_count <= 0
        or token_count >= cue["maxTokens"]
        or generation.get("maxTokens") != cue["maxTokens"]
        or generation.get("tokenCeilingReached") is not False
        or generation.get("sampleCount") != decoded["sampleCount"]
        or generation.get("sampleRate") != decoded["sampleRate"]
        or generation.get("nonStreamingResultCount") != 1
        or not isinstance(generation.get("peakAbsolute"), (int, float))
        or generation.get("peakAbsolute") < 1e-5
        or receipt.get("wholeUntouchedNonStreamingGeneration") is not True
        or receipt.get("audio", {}).get("relativePath") != relative_audio
        or receipt.get("audio", {}).get("file") != file_binding(audio_path)
        or receipt.get("audio", {}).get("float32LESHA256")
        != decoded["float32LESHA256"]
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
    ):
        raise V5Error(f"V5 cue commit failed: {candidate_id}/{cue['segmentID']}")
    if not math.isclose(
        float(generation["peakAbsolute"]),
        float(np.max(np.abs(audio))),
        rel_tol=1e-12,
        abs_tol=1e-12,
    ):
        raise V5Error(f"V5 cue peak receipt drifted: {candidate_id}/{cue['segmentID']}")
    return {
        "receipt": receipt,
        "receiptPath": receipt_path,
        "receiptBinding": file_binding(receipt_path),
        "audioPath": audio_path,
        "audio": audio,
        "decoded": decoded,
    }


def commit_v5_cue(
    *,
    output_root: Path,
    work_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    cue: dict[str, Any],
    audio: Any,
    sample_rate: int,
    generation: dict[str, Any],
    config: dict[str, Any],
    base_config: dict[str, Any],
    parent_chain: dict[str, Any],
    model_receipt: dict[str, Any],
    identity_text_sha256: str,
) -> dict[str, Any]:
    if sample_rate != config["master"]["nativeSampleRate"]:
        raise V5Error(f"V5 cue native rate drifted: {candidate_id}/{cue['segmentID']}")
    staging = Path(
        tempfile.mkdtemp(dir=work_root, prefix=f".v5-cue-stage-{candidate_id}-")
    )
    committed = False
    try:
        audio_path = staging / "audio-f32.wav"
        production.write_float_wav(audio_path, sample_rate, audio)
        _, decoded = read_native_audio(audio_path, config)
        if (
            decoded["sampleCount"] != generation["sampleCount"]
            or decoded["sampleRate"] != generation["sampleRate"]
            or decoded["float32LESHA256"] != native_float32_sha256(audio)
        ):
            raise V5Error(
                f"V5 cue WAV changed native PCM: {candidate_id}/{cue['segmentID']}"
            )
        expected_seed = candidate["stressSeed"] + cue["seedOffset"]
        relative_audio = (
            _cue_commit_relative(candidate_id, cue["segmentID"]) / "audio-f32.wav"
        ).as_posix()
        destination = output_root / _cue_commit_relative(
            candidate_id, cue["segmentID"]
        )
        committed_audio_binding = file_binding(audio_path)
        committed_audio_binding["path"] = str(destination / "audio-f32.wav")
        receipt = {
            "schemaVersion": 1,
            "status": CUE_COMMIT_STATUS,
            "trustDomain": TRUST_DOMAIN,
            "createdAt": production.timestamp(),
            "pipelineBinding": pipeline_binding(config),
            "parentChain": parent_chain,
            "voiceCloneModel": model_receipt,
            "candidateID": candidate_id,
            "reference": {
                "sha256": parent_candidate["reference"]["sha256"],
                "bytes": parent_candidate["reference"]["bytes"],
            },
            "instructionSHA256": parent_candidate["instructionSHA256"],
            "baseStressSeed": candidate["stressSeed"],
            "identityReferenceTextSHA256": identity_text_sha256,
            "cueSpec": _cue_public_spec(cue),
            "generationSeed": expected_seed,
            "generationSettings": _expected_generation_settings(
                base_config, max_tokens=cue["maxTokens"]
            ),
            "generation": generation,
            "wholeUntouchedNonStreamingGeneration": True,
            "audio": {
                "relativePath": relative_audio,
                "file": committed_audio_binding,
                "float32LESHA256": decoded["float32LESHA256"],
            },
            "claimsExcluded": config["claimsExcluded"],
        }
        write_json(staging / "cue.v5.receipt.json", receipt)
        atomic_commit_directory(
            staging, destination, work_root=work_root, output_root=output_root
        )
        committed = True
    finally:
        if not committed and staging.exists():
            shutil.rmtree(staging)
    return validate_cue_commit(
        output_root=output_root,
        candidate_id=candidate_id,
        candidate=candidate,
        parent_candidate=parent_candidate,
        cue=cue,
        config=config,
        base_config=base_config,
        parent_chain=parent_chain,
        model_receipt=model_receipt,
        identity_text_sha256=identity_text_sha256,
    )


def _progress_record(
    *,
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    stress_record: dict[str, Any],
    model_receipt: dict[str, Any],
    cue_commits: list[dict[str, Any]],
    candidate_commits: list[dict[str, Any]],
    expected_pipeline_binding: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "status": GENERATION_PROGRESS_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "updatedAt": production.timestamp(),
        "pipelineBinding": expected_pipeline_binding or pipeline_binding(config),
        "parentChain": parent_chain,
        "stressText": stress_record,
        "voiceCloneModel": model_receipt,
        "provisionalFinalistIDs": EXPECTED_FINALISTS,
        "completedCueCommits": [
            {
                "candidateID": item["receipt"]["candidateID"],
                "segmentID": item["receipt"]["cueSpec"]["segmentID"],
                "receipt": item["receiptBinding"],
            }
            for item in cue_commits
        ],
        "completedCandidateCommits": [
            {
                "candidateID": item["record"]["candidateID"],
                "receipt": item["receiptBinding"],
            }
            for item in candidate_commits
        ],
        "generationComplete": len(candidate_commits) == len(EXPECTED_FINALISTS),
        "claimsExcluded": config["claimsExcluded"],
    }


def update_generation_progress(
    *,
    output_root: Path,
    work_root: Path,
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    stress_record: dict[str, Any],
    model_receipt: dict[str, Any],
    cue_commits: list[dict[str, Any]],
    candidate_commits: list[dict[str, Any]],
) -> dict[str, Any]:
    expected = _progress_record(
        config=config,
        parent_chain=parent_chain,
        stress_record=stress_record,
        model_receipt=model_receipt,
        cue_commits=cue_commits,
        candidate_commits=candidate_commits,
    )
    path = output_root / "generation-progress.v5.receipt.json"
    if path.exists():
        previous = production.load_json(path)
        stable_keys = [
            "schemaVersion",
            "status",
            "trustDomain",
            "pipelineBinding",
            "parentChain",
            "stressText",
            "voiceCloneModel",
            "provisionalFinalistIDs",
            "claimsExcluded",
        ]
        if any(previous.get(key) != expected.get(key) for key in stable_keys):
            raise V5Error("V5 generation progress provenance drifted")
        previous_cues = previous.get("completedCueCommits", [])
        previous_candidates = previous.get("completedCandidateCommits", [])
        if (
            previous_cues != expected["completedCueCommits"][: len(previous_cues)]
            or previous_candidates
            != expected["completedCandidateCommits"][: len(previous_candidates)]
        ):
            raise V5Error("V5 generation progress is not a committed prefix")
    atomic_write_json(path, expected, work_root=work_root, confinement_root=output_root)
    return {**expected, "receiptBinding": file_binding(path)}


def _cue_records_for_candidate(
    candidate_id: str,
    cues: list[dict[str, Any]],
    cue_commits: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    selected = [
        item for item in cue_commits if item["receipt"]["candidateID"] == candidate_id
    ]
    if [item["receipt"]["cueSpec"]["segmentID"] for item in selected] != [
        cue["segmentID"] for cue in cues
    ]:
        raise V5Error(f"candidate cue commits are incomplete or out of order: {candidate_id}")
    records: list[dict[str, Any]] = []
    ranges: list[dict[str, Any]] = []
    cursor = 0
    for cue, commit in zip(cues, selected, strict=True):
        decoded = commit["decoded"]
        end = cursor + decoded["sampleCount"]
        receipt = commit["receipt"]
        records.append(
            {
                "segmentID": cue["segmentID"],
                "order": cue["order"],
                "contractIDs": cue["contractIDs"],
                "textSHA256": cue["textSHA256"],
                "wordCount": cue["wordCount"],
                "generationSeed": receipt["generationSeed"],
                "seedOffset": cue["seedOffset"],
                "maxTokens": cue["maxTokens"],
                "tokenCount": receipt["generation"]["tokenCount"],
                "tokenCeilingReached": False,
                "sampleRate": decoded["sampleRate"],
                "sampleCount": decoded["sampleCount"],
                "float32LESHA256": decoded["float32LESHA256"],
                "startSampleInclusive": cursor,
                "endSampleExclusive": end,
                "relativePath": receipt["audio"]["relativePath"],
                "file": receipt["audio"]["file"],
                "cueCommitReceipt": commit["receiptBinding"],
            }
        )
        ranges.append(
            {
                "segmentID": cue["segmentID"],
                "startSampleInclusive": cursor,
                "endSampleExclusive": end,
            }
        )
        cursor = end
    return records, ranges


def commit_v5_candidate(
    *,
    output_root: Path,
    work_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    cues: list[dict[str, Any]],
    cue_commits: list[dict[str, Any]],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    model_receipt: dict[str, Any],
) -> dict[str, Any]:
    import numpy as np

    cue_records, cue_ranges = _cue_records_for_candidate(
        candidate_id, cues, cue_commits
    )
    selected = [
        item for item in cue_commits if item["receipt"]["candidateID"] == candidate_id
    ]
    maximum_peak = max(float(np.max(np.abs(item["audio"]))) for item in selected)
    if not math.isfinite(maximum_peak) or maximum_peak <= 0:
        raise V5Error(f"candidate cues are silent: {candidate_id}")
    target_peak = 10 ** (config["master"]["nativeAssemblyPeakDBFS"] / 20)
    common_gain = target_peak / maximum_peak
    assembly = np.concatenate(
        [np.asarray(item["audio"] * common_gain, dtype=np.float32) for item in selected]
    )
    staging = Path(
        tempfile.mkdtemp(dir=work_root, prefix=f".v5-candidate-stage-{candidate_id}-")
    )
    committed = False
    try:
        assembly_path = staging / "assembled-f32.wav"
        master_path = staging / "stress.wav"
        production.write_float_wav(
            assembly_path, config["master"]["nativeSampleRate"], assembly
        )
        assembly_audio, assembly_decoded = read_native_audio(assembly_path, config)
        if not np.array_equal(assembly_audio, assembly):
            raise V5Error(f"candidate assembly WAV changed samples: {candidate_id}")
        render_deterministic_master(
            assembly_path, master_path, config, confinement_root=work_root
        )
        relation = verify_native_master_relation(
            assembly_path,
            master_path,
            config,
            audit_root=staging,
            confinement_root=work_root,
        )
        duration_seconds = relation["master"]["durationSeconds"]
        if not stress_duration_gate(duration_seconds, config):
            raise V5Error(
                f"V5 candidate duration is outside 18–22 minutes: {candidate_id} "
                f"({duration_seconds / 60:.3f} minutes)"
            )
        destination = output_root / _candidate_commit_relative(candidate_id)
        committed_assembly_binding = file_binding(assembly_path)
        committed_assembly_binding["path"] = str(destination / "assembled-f32.wav")
        committed_master_binding = file_binding(master_path)
        committed_master_binding["path"] = str(destination / "stress.wav")
        relation_summary = {
            "nativeFloat32LESHA256": assembly_decoded["float32LESHA256"],
            "nativeSampleCount": assembly_decoded["sampleCount"],
            "masterSHA256": committed_master_binding["sha256"],
            "masterBytes": committed_master_binding["bytes"],
            "masterSampleCount": relation["master"]["sampleCount"],
            "decodedDurationDifferenceSamples": relation[
                "decodedDurationDifferenceSamples"
            ],
            "deterministicRecomputeSHA256": relation[
                "deterministicRecomputeSHA256"
            ],
            "deterministicByteEquality": relation["deterministicByteEquality"],
        }
        record = {
            "candidateID": candidate_id,
            "referenceSHA256": parent_candidate["reference"]["sha256"],
            "instructionSHA256": parent_candidate["instructionSHA256"],
            "baseStressSeed": candidate["stressSeed"],
            "generationCount": len(cues),
            "cueRecords": cue_records,
            "nativeAssembly": {
                "relativePath": (
                    _candidate_commit_relative(candidate_id) / "assembled-f32.wav"
                ).as_posix(),
                "file": committed_assembly_binding,
                "sampleRate": assembly_decoded["sampleRate"],
                "sampleCount": assembly_decoded["sampleCount"],
                "float32LESHA256": assembly_decoded["float32LESHA256"],
                "oneCommonNormalizationGain": common_gain,
                "sampleCuts": 0,
                "insertedSilenceSamples": 0,
                "crossfades": 0,
                "fades": 0,
                "timeStretchApplied": False,
                "perSegmentGainChanges": 0,
            },
            "master": {
                "relativePath": (
                    _candidate_commit_relative(candidate_id) / "stress.wav"
                ).as_posix(),
                "file": committed_master_binding,
            },
            "masterRelationAtGeneration": relation_summary,
            "decodedDurationSeconds": duration_seconds,
            "durationGate18To22Minutes": True,
        }
        receipt = {
            "schemaVersion": 1,
            "status": CANDIDATE_COMMIT_STATUS,
            "trustDomain": TRUST_DOMAIN,
            "createdAt": production.timestamp(),
            "pipelineBinding": pipeline_binding(config),
            "parentChain": parent_chain,
            "voiceCloneModel": model_receipt,
            "record": record,
            "claimsExcluded": config["claimsExcluded"],
        }
        write_json(staging / "candidate.v5.receipt.json", receipt)
        atomic_commit_directory(
            staging, destination, work_root=work_root, output_root=output_root
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
        cues=cues,
        cue_commits=cue_commits,
        config=config,
        parent_chain=parent_chain,
        model_receipt=model_receipt,
    )


def validate_candidate_commit(
    *,
    output_root: Path,
    candidate_id: str,
    candidate: dict[str, Any],
    parent_candidate: dict[str, Any],
    cues: list[dict[str, Any]],
    cue_commits: list[dict[str, Any]],
    config: dict[str, Any],
    parent_chain: dict[str, Any],
    model_receipt: dict[str, Any],
    expected_pipeline_binding: dict[str, Any] | None = None,
) -> dict[str, Any]:
    import numpy as np

    commit = confined_path(
        output_root / _candidate_commit_relative(candidate_id),
        root=output_root,
        must_exist=True,
        expect_directory=True,
    )
    if {item.name for item in commit.iterdir()} != {
        "assembled-f32.wav",
        "stress.wav",
        "candidate.v5.receipt.json",
    }:
        raise V5Error(f"candidate commit contains unexpected files: {candidate_id}")
    assembly_path = confined_path(
        commit / "assembled-f32.wav",
        root=commit,
        must_exist=True,
        expect_directory=False,
    )
    master_path = confined_path(
        commit / "stress.wav",
        root=commit,
        must_exist=True,
        expect_directory=False,
    )
    receipt_path = confined_path(
        commit / "candidate.v5.receipt.json",
        root=commit,
        must_exist=True,
        expect_directory=False,
    )
    receipt = production.load_json(receipt_path)
    record = receipt.get("record", {})
    cue_records, _ = _cue_records_for_candidate(candidate_id, cues, cue_commits)
    selected = [
        item for item in cue_commits if item["receipt"]["candidateID"] == candidate_id
    ]
    maximum_peak = max(float(np.max(np.abs(item["audio"]))) for item in selected)
    target_peak = 10 ** (config["master"]["nativeAssemblyPeakDBFS"] / 20)
    common_gain = target_peak / maximum_peak
    assembly_audio, assembly_decoded = read_native_audio(assembly_path, config)
    if assembly_decoded["sampleCount"] != sum(
        item["decoded"]["sampleCount"] for item in selected
    ):
        raise V5Error(f"candidate assembly sample count drifted: {candidate_id}")
    cursor = 0
    for cue, item in zip(cues, selected, strict=True):
        end = cursor + item["decoded"]["sampleCount"]
        expected = np.asarray(item["audio"] * common_gain, dtype=np.float32)
        if not np.array_equal(assembly_audio[cursor:end], expected):
            raise V5Error(
                f"candidate assembly changed cue PCM: {candidate_id}/{cue['segmentID']}"
            )
        cursor = end
    relation = verify_native_master_relation(
        assembly_path,
        master_path,
        config,
        audit_root=commit,
        confinement_root=_v5_work_root(config, create=False),
    )
    duration_seconds = relation["master"]["durationSeconds"]
    relation_summary = {
        "nativeFloat32LESHA256": assembly_decoded["float32LESHA256"],
        "nativeSampleCount": assembly_decoded["sampleCount"],
        "masterSHA256": sha256_file(master_path),
        "masterBytes": master_path.stat().st_size,
        "masterSampleCount": relation["master"]["sampleCount"],
        "decodedDurationDifferenceSamples": relation[
            "decodedDurationDifferenceSamples"
        ],
        "deterministicRecomputeSHA256": relation[
            "deterministicRecomputeSHA256"
        ],
        "deterministicByteEquality": relation["deterministicByteEquality"],
    }
    assembly_record = record.get("nativeAssembly", {})
    master_record = record.get("master", {})
    generation_binding = expected_pipeline_binding or pipeline_binding(config)
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("status") != CANDIDATE_COMMIT_STATUS
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("pipelineBinding") != generation_binding
        or receipt.get("parentChain") != parent_chain
        or receipt.get("voiceCloneModel") != model_receipt
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
        or record.get("candidateID") != candidate_id
        or record.get("referenceSHA256") != parent_candidate["reference"]["sha256"]
        or record.get("instructionSHA256") != parent_candidate["instructionSHA256"]
        or record.get("baseStressSeed") != candidate["stressSeed"]
        or record.get("generationCount") != len(cues)
        or record.get("cueRecords") != cue_records
        or assembly_record.get("relativePath")
        != (_candidate_commit_relative(candidate_id) / "assembled-f32.wav").as_posix()
        or assembly_record.get("file") != file_binding(assembly_path)
        or assembly_record.get("sampleRate") != assembly_decoded["sampleRate"]
        or assembly_record.get("sampleCount") != assembly_decoded["sampleCount"]
        or assembly_record.get("float32LESHA256")
        != assembly_decoded["float32LESHA256"]
        or not math.isclose(
            assembly_record.get("oneCommonNormalizationGain", math.nan),
            common_gain,
            rel_tol=1e-12,
            abs_tol=1e-12,
        )
        or assembly_record.get("sampleCuts") != 0
        or assembly_record.get("insertedSilenceSamples") != 0
        or assembly_record.get("crossfades") != 0
        or assembly_record.get("fades") != 0
        or assembly_record.get("timeStretchApplied") is not False
        or assembly_record.get("perSegmentGainChanges") != 0
        or master_record.get("relativePath")
        != (_candidate_commit_relative(candidate_id) / "stress.wav").as_posix()
        or master_record.get("file") != file_binding(master_path)
        or record.get("masterRelationAtGeneration") != relation_summary
        or not math.isclose(
            record.get("decodedDurationSeconds", math.nan),
            duration_seconds,
            rel_tol=0.0,
            abs_tol=0.0,
        )
        or record.get("durationGate18To22Minutes") is not True
        or not stress_duration_gate(duration_seconds, config)
    ):
        raise V5Error(f"V5 candidate commit failed: {candidate_id}")
    return {
        "record": record,
        "receipt": receipt,
        "receiptPath": receipt_path,
        "receiptBinding": file_binding(receipt_path),
        "assemblyPath": assembly_path,
        "assemblyAudio": assembly_audio,
        "masterPath": master_path,
        "masterRelation": relation,
    }


def scan_generation_commits(
    *,
    output_root: Path,
    candidates_by_id: dict[str, dict[str, Any]],
    parent_records_by_id: dict[str, dict[str, Any]],
    cues: list[dict[str, Any]],
    config: dict[str, Any],
    base_config: dict[str, Any],
    parent_chain: dict[str, Any],
    model_receipt: dict[str, Any],
    identity_text_sha256: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    validate_generation_inventory(output_root, config, cues)
    cue_commits: list[dict[str, Any]] = []
    missing_cue_seen = False
    for candidate_id in EXPECTED_FINALISTS:
        for cue in cues:
            path = output_root / _cue_commit_relative(
                candidate_id, cue["segmentID"]
            )
            if path.exists():
                if missing_cue_seen:
                    raise V5Error("V5 cue commits are not one resumable prefix")
                cue_commits.append(
                    validate_cue_commit(
                        output_root=output_root,
                        candidate_id=candidate_id,
                        candidate=candidates_by_id[candidate_id],
                        parent_candidate=parent_records_by_id[candidate_id],
                        cue=cue,
                        config=config,
                        base_config=base_config,
                        parent_chain=parent_chain,
                        model_receipt=model_receipt,
                        identity_text_sha256=identity_text_sha256,
                    )
                )
            else:
                missing_cue_seen = True
    candidate_commits: list[dict[str, Any]] = []
    missing_candidate_seen = False
    for candidate_id in EXPECTED_FINALISTS:
        path = output_root / _candidate_commit_relative(candidate_id)
        own_cue_count = sum(
            item["receipt"]["candidateID"] == candidate_id for item in cue_commits
        )
        if path.exists():
            if missing_candidate_seen or own_cue_count != len(cues):
                raise V5Error("V5 candidate commits are not one complete resumable prefix")
            candidate_commits.append(
                validate_candidate_commit(
                    output_root=output_root,
                    candidate_id=candidate_id,
                    candidate=candidates_by_id[candidate_id],
                    parent_candidate=parent_records_by_id[candidate_id],
                    cues=cues,
                    cue_commits=cue_commits,
                    config=config,
                    parent_chain=parent_chain,
                    model_receipt=model_receipt,
                )
            )
        else:
            missing_candidate_seen = True
    return cue_commits, candidate_commits


def generate_v5(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V5Error("V5 generation requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    parent_chain = validate_parent_chain(config)
    rejected_v4 = validate_v4_diagnostic_evidence(config, deep=False)
    validate_master_tools(config)
    stress_text, stress_record, cues = stress_material(config)
    work_root = _v5_work_root(config, create=True)
    output_root = prepare_generation_root(args.output, config)
    base_config = production.validate_config()
    base_binding = production.pipeline_binding(base_config)
    candidate_root = repository_path(
        config["paths"]["candidateSetRoot"], directory=True
    )
    candidate_set = production.validate_candidate_set(
        candidate_root, base_config, base_binding
    )
    parent_records_by_id = {
        candidate_id: candidate_set["recordsByID"][candidate_id]
        for candidate_id in EXPECTED_FINALISTS
    }
    candidates_by_id = {
        candidate_id: production.candidate_by_id(base_config, candidate_id)
        for candidate_id in EXPECTED_FINALISTS
    }
    identity_path = repository_path(
        f"native/audio/narration/{base_config['texts']['identityReference']['path']}",
        directory=False,
    )
    identity_text = production.canonical_text(identity_path)
    identity_text_sha256 = production.sha256_text(identity_text)
    if identity_text_sha256 != base_config["texts"]["identityReference"]["textSHA256"]:
        raise V5Error("identity reference text drifted before V5 generation")
    clone_directory, clone_files = production.verify_model_snapshot(
        base_config["models"]["voiceClone"], offline=True
    )
    model_receipt = production.model_receipt(
        base_config["models"]["voiceClone"], clone_files
    )
    final_path = output_root / "stress-set.v5.receipt.json"
    if final_path.exists():
        result = validate_stress_set(output_root, config, parent_chain)
        return {
            "status": STRESS_STATUS,
            "resumedExistingCompleteSet": True,
            "receipt": result["receiptBinding"],
            "generationPerformedThisRun": False,
        }
    cue_commits, candidate_commits = scan_generation_commits(
        output_root=output_root,
        candidates_by_id=candidates_by_id,
        parent_records_by_id=parent_records_by_id,
        cues=cues,
        config=config,
        base_config=base_config,
        parent_chain=parent_chain,
        model_receipt=model_receipt,
        identity_text_sha256=identity_text_sha256,
    )
    update_generation_progress(
        output_root=output_root,
        work_root=work_root,
        config=config,
        parent_chain=parent_chain,
        stress_record=stress_record,
        model_receipt=model_receipt,
        cue_commits=cue_commits,
        candidate_commits=candidate_commits,
    )

    if len(cue_commits) < len(EXPECTED_FINALISTS) * len(cues):
        from mlx_audio.tts.utils import load_model
        import mlx.core as mx

        clone_model = load_model(str(clone_directory))
        completed_keys = {
            (
                item["receipt"]["candidateID"],
                item["receipt"]["cueSpec"]["segmentID"],
            )
            for item in cue_commits
        }
        for candidate_id in EXPECTED_FINALISTS:
            candidate = candidates_by_id[candidate_id]
            parent_candidate = parent_records_by_id[candidate_id]
            reference_path = confined_path(
                Path(parent_candidate["_verifiedReferencePath"]),
                root=candidate_root,
                must_exist=True,
                expect_directory=False,
            )
            for cue in cues:
                key = (candidate_id, cue["segmentID"])
                if key in completed_keys:
                    continue
                generation_seed = candidate["stressSeed"] + cue["seedOffset"]
                audio, sample_rate, generation = synthesize_v5_cue(
                    clone_model,
                    text=cue["text"],
                    reference_path=reference_path,
                    reference_text=identity_text,
                    seed=generation_seed,
                    max_tokens=cue["maxTokens"],
                    base_config=base_config,
                )
                committed = commit_v5_cue(
                    output_root=output_root,
                    work_root=work_root,
                    candidate_id=candidate_id,
                    candidate=candidate,
                    parent_candidate=parent_candidate,
                    cue=cue,
                    audio=audio,
                    sample_rate=sample_rate,
                    generation=generation,
                    config=config,
                    base_config=base_config,
                    parent_chain=parent_chain,
                    model_receipt=model_receipt,
                    identity_text_sha256=identity_text_sha256,
                )
                cue_commits.append(committed)
                completed_keys.add(key)
                update_generation_progress(
                    output_root=output_root,
                    work_root=work_root,
                    config=config,
                    parent_chain=parent_chain,
                    stress_record=stress_record,
                    model_receipt=model_receipt,
                    cue_commits=cue_commits,
                    candidate_commits=candidate_commits,
                )
                mx.clear_cache()

    for candidate_id in EXPECTED_FINALISTS:
        if any(item["record"]["candidateID"] == candidate_id for item in candidate_commits):
            continue
        committed = commit_v5_candidate(
            output_root=output_root,
            work_root=work_root,
            candidate_id=candidate_id,
            candidate=candidates_by_id[candidate_id],
            parent_candidate=parent_records_by_id[candidate_id],
            cues=cues,
            cue_commits=cue_commits,
            config=config,
            parent_chain=parent_chain,
            model_receipt=model_receipt,
        )
        candidate_commits.append(committed)
        update_generation_progress(
            output_root=output_root,
            work_root=work_root,
            config=config,
            parent_chain=parent_chain,
            stress_record=stress_record,
            model_receipt=model_receipt,
            cue_commits=cue_commits,
            candidate_commits=candidate_commits,
        )

    progress_path = output_root / "generation-progress.v5.receipt.json"
    receipt = {
        "schemaVersion": 1,
        "status": STRESS_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "rejectedV4DiagnosticEvidence": rejected_v4,
        "generationProgressReceipt": file_binding(progress_path),
        "voiceCloneModel": model_receipt,
        "provisionalFinalistIDs": EXPECTED_FINALISTS,
        "stressText": stress_record,
        "assemblyPolicy": {
            "cueCountPerCandidate": len(cues),
            "oneUntouchedNonStreamingGenerationPerCue": True,
            "oneCommonNativeAssemblyGain": True,
            "sampleCuts": 0,
            "insertedSilenceSamples": 0,
            "crossfades": 0,
            "fades": 0,
            "timeStretchApplied": False,
            "perSegmentGainChanges": 0,
            "deterministicMaster": True,
        },
        "records": [
            {**item["record"], "candidateCommitReceipt": item["receiptBinding"]}
            for item in candidate_commits
        ],
        "claimsExcluded": config["claimsExcluded"],
    }
    atomic_write_json(
        final_path, receipt, work_root=work_root, confinement_root=output_root
    )
    validated = validate_stress_set(output_root, config, parent_chain)
    return {
        "status": STRESS_STATUS,
        "resumedExistingCompleteSet": False,
        "receipt": validated["receiptBinding"],
        "generationPerformedThisRun": True,
    }


def _relative_bound_file(
    root: Path,
    relative: str,
    expected: dict[str, Any],
    *,
    exact_relative: str,
) -> Path:
    relative_path = Path(relative)
    if (
        relative != exact_relative
        or relative_path.is_absolute()
        or ".." in relative_path.parts
    ):
        raise V5Error(f"receipt path drifted or escaped: {relative}")
    path = confined_path(
        root / relative_path,
        root=root,
        must_exist=True,
        expect_directory=False,
    )
    if (
        path.stat().st_size != expected.get("bytes")
        or sha256_file(path) != expected.get("sha256")
    ):
        raise V5Error(f"receipt leaf binding failed: {relative}")
    return path


def validate_stress_set(
    root: Path, config: dict[str, Any], parent_chain: dict[str, Any]
) -> dict[str, Any]:
    import numpy as np

    work_root = REPOSITORY_ROOT / config["paths"]["workRoot"]
    root = confined_path(
        root,
        root=work_root,
        must_exist=True,
        expect_directory=True,
    )
    if root == _absolute_without_resolution(work_root) or root.parent != _absolute_without_resolution(
        work_root
    ):
        raise V5Error("V5 stress set must be one direct child of the frozen work root")
    receipt_path = confined_path(
        root / "stress-set.v5.receipt.json",
        root=root,
        must_exist=True,
        expect_directory=False,
    )
    receipt = production.load_json(receipt_path)
    generation_binding = validated_generation_pipeline_binding(
        receipt.get("pipelineBinding"), config
    )
    _, stress_record, cues = stress_material(config)
    validate_generation_inventory(root, config, cues)
    expected_v4_diagnostic = validate_v4_diagnostic_evidence(config, deep=False)
    progress_path = root / "generation-progress.v5.receipt.json"
    progress = production.load_json(
        confined_path(
            progress_path,
            root=root,
            must_exist=True,
            expect_directory=False,
        )
    )
    expected_assembly_policy = {
        "cueCountPerCandidate": len(cues),
        "oneUntouchedNonStreamingGenerationPerCue": True,
        "oneCommonNativeAssemblyGain": True,
        "sampleCuts": 0,
        "insertedSilenceSamples": 0,
        "crossfades": 0,
        "fades": 0,
        "timeStretchApplied": False,
        "perSegmentGainChanges": 0,
        "deterministicMaster": True,
    }
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("status") != STRESS_STATUS
        or receipt.get("trustDomain") != TRUST_DOMAIN
        or receipt.get("pipelineBinding") != generation_binding
        or receipt.get("parentChain") != parent_chain
        or receipt.get("provisionalFinalistIDs") != EXPECTED_FINALISTS
        or receipt.get("stressText") != stress_record
        or receipt.get("rejectedV4DiagnosticEvidence") != expected_v4_diagnostic
        or receipt.get("generationProgressReceipt") != file_binding(progress_path)
        or receipt.get("assemblyPolicy") != expected_assembly_policy
        or receipt.get("claimsExcluded") != config["claimsExcluded"]
    ):
        raise V5Error("V5 stress-set receipt contract or parent chain drifted")
    if (
        progress.get("schemaVersion") != 1
        or progress.get("status") != GENERATION_PROGRESS_STATUS
        or progress.get("trustDomain") != TRUST_DOMAIN
        or progress.get("pipelineBinding") != generation_binding
        or progress.get("parentChain") != parent_chain
        or progress.get("stressText") != stress_record
        or progress.get("provisionalFinalistIDs") != EXPECTED_FINALISTS
        or progress.get("generationComplete") is not True
        or progress.get("claimsExcluded") != config["claimsExcluded"]
    ):
        raise V5Error("V5 generation progress receipt is not complete and bound")
    rejected_stress_hash = config["v4DiagnosticEvidence"]["stressSetReceiptSHA256"]
    for label, lineage in [
        ("stress-set", receipt.get("parentChain")),
        ("generation-progress", progress.get("parentChain")),
    ]:
        if rejected_stress_hash in canonical_json(lineage):
            raise V5Error(
                f"rejected V4 stress evidence cannot become a {label} parent"
            )
    base_config = production.validate_config()
    clone_dir, clone_files = production.verify_model_snapshot(
        base_config["models"]["voiceClone"], offline=True
    )
    expected_model = production.model_receipt(
        base_config["models"]["voiceClone"], clone_files
    )
    if (
        receipt.get("voiceCloneModel") != expected_model
        or progress.get("voiceCloneModel") != expected_model
    ):
        raise V5Error("V5 stress generation model lineage drifted")
    records = receipt.get("records")
    if (
        not isinstance(records, list)
        or [item.get("candidateID") for item in records] != EXPECTED_FINALISTS
    ):
        raise V5Error("V5 stress candidate inventory drifted")
    candidate_root = repository_path(
        config["paths"]["candidateSetRoot"], directory=True
    )
    candidate_set = production.validate_candidate_set(
        candidate_root, base_config, production.pipeline_binding(base_config)
    )
    identity_path = repository_path(
        f"native/audio/narration/{base_config['texts']['identityReference']['path']}",
        directory=False,
    )
    identity_text_sha256 = production.sha256_text(
        production.canonical_text(identity_path)
    )
    records_by_id: dict[str, Any] = {}
    all_cue_commits: list[dict[str, Any]] = []
    all_candidate_commits: list[dict[str, Any]] = []
    for record in records:
        candidate_id = record["candidateID"]
        candidate = production.candidate_by_id(base_config, candidate_id)
        parent_candidate = candidate_set["recordsByID"][candidate_id]
        reference_path = Path(parent_candidate["_verifiedReferencePath"])
        reference_path = confined_path(
            reference_path,
            root=candidate_root,
            must_exist=True,
            expect_directory=False,
        )
        if (
            record.get("referenceSHA256") != parent_candidate["reference"]["sha256"]
            or record.get("instructionSHA256")
            != parent_candidate["instructionSHA256"]
            or record.get("baseStressSeed") != candidate["stressSeed"]
        ):
            raise V5Error(f"candidate identity parent drifted: {candidate_id}")
        cue_records = record.get("cueRecords")
        if (
            not isinstance(cue_records, list)
            or [item.get("segmentID") for item in cue_records]
            != [cue["segmentID"] for cue in cues]
        ):
            raise V5Error(f"cue generation inventory drifted: {candidate_id}")
        cursor = 0
        maximum_peak = 0.0
        cue_audio: list[tuple[str, Any]] = []
        cue_sample_ranges: list[dict[str, Any]] = []
        for cue, cue_record in zip(cues, cue_records, strict=True):
            committed = validate_cue_commit(
                output_root=root,
                candidate_id=candidate_id,
                candidate=candidate,
                parent_candidate=parent_candidate,
                cue=cue,
                config=config,
                base_config=base_config,
                parent_chain=parent_chain,
                model_receipt=expected_model,
                identity_text_sha256=identity_text_sha256,
                expected_pipeline_binding=generation_binding,
            )
            all_cue_commits.append(committed)
            expected_relative = (
                _cue_commit_relative(candidate_id, cue["segmentID"])
                / "audio-f32.wav"
            ).as_posix()
            cue_path = _relative_bound_file(
                root,
                cue_record.get("relativePath", ""),
                cue_record.get("file", {}),
                exact_relative=expected_relative,
            )
            audio, decoded = read_native_audio(cue_path, config)
            expected_seed = candidate["stressSeed"] + cue["seedOffset"]
            token_count = cue_record.get("tokenCount")
            if (
                cue_record.get("order") != cue["order"]
                or cue_record.get("contractIDs") != cue["contractIDs"]
                or cue_record.get("textSHA256") != cue["textSHA256"]
                or cue_record.get("wordCount") != cue["wordCount"]
                or cue_record.get("generationSeed") != expected_seed
                or cue_record.get("maxTokens") != cue["maxTokens"]
                or type(token_count) is not int
                or token_count <= 0
                or token_count >= cue["maxTokens"]
                or cue_record.get("tokenCeilingReached") is not False
                or cue_record.get("sampleCount") != decoded["sampleCount"]
                or cue_record.get("sampleRate") != decoded["sampleRate"]
                or cue_record.get("float32LESHA256")
                != decoded["float32LESHA256"]
                or cue_record.get("startSampleInclusive") != cursor
                or cue_record.get("cueCommitReceipt")
                != committed["receiptBinding"]
            ):
                raise V5Error(
                    f"retained generation metadata failed: {candidate_id}/{cue['segmentID']}"
                )
            end = cursor + decoded["sampleCount"]
            if cue_record.get("endSampleExclusive") != end:
                raise V5Error(
                    f"cue sample boundary failed: {candidate_id}/{cue['segmentID']}"
                )
            maximum_peak = max(maximum_peak, float(np.max(np.abs(audio))))
            cue_audio.append((cue["segmentID"], audio))
            cue_sample_ranges.append(
                {
                    "segmentID": cue["segmentID"],
                    "startSampleInclusive": cursor,
                    "endSampleExclusive": end,
                }
            )
            cursor = end
        if not math.isfinite(maximum_peak) or maximum_peak <= 0:
            raise V5Error(f"all V5 cue audio is silent: {candidate_id}")
        assembly_record = record.get("nativeAssembly", {})
        assembly_path = _relative_bound_file(
            root,
            assembly_record.get("relativePath", ""),
            assembly_record.get("file", {}),
            exact_relative=(
                _candidate_commit_relative(candidate_id) / "assembled-f32.wav"
            ).as_posix(),
        )
        assembly_audio, assembly_decoded = read_native_audio(assembly_path, config)
        target_peak = 10 ** (config["master"]["nativeAssemblyPeakDBFS"] / 20)
        expected_gain = target_peak / maximum_peak
        common_gain = assembly_record.get("oneCommonNormalizationGain")
        if (
            not isinstance(common_gain, (int, float))
            or not math.isclose(common_gain, expected_gain, rel_tol=1e-12, abs_tol=1e-12)
            or assembly_decoded["sampleCount"] != cursor
            or assembly_record.get("sampleCount") != cursor
            or assembly_record.get("float32LESHA256")
            != assembly_decoded["float32LESHA256"]
            or assembly_record.get("sampleCuts") != 0
            or assembly_record.get("insertedSilenceSamples") != 0
            or assembly_record.get("crossfades") != 0
            or assembly_record.get("fades") != 0
            or assembly_record.get("timeStretchApplied") is not False
            or assembly_record.get("perSegmentGainChanges") != 0
        ):
            raise V5Error(f"native assembly contract failed: {candidate_id}")
        for cue_range, (_, audio) in zip(cue_sample_ranges, cue_audio, strict=True):
            expected_slice = np.asarray(audio * common_gain, dtype=np.float32)
            start = cue_range["startSampleInclusive"]
            end = cue_range["endSampleExclusive"]
            if not np.array_equal(assembly_audio[start:end], expected_slice):
                raise V5Error(
                    f"assembly changed cue samples: {candidate_id}/{cue_range['segmentID']}"
                )
        master_record = record.get("master", {})
        master_path = _relative_bound_file(
            root,
            master_record.get("relativePath", ""),
            master_record.get("file", {}),
            exact_relative=(
                _candidate_commit_relative(candidate_id) / "stress.wav"
            ).as_posix(),
        )
        candidate_commit = validate_candidate_commit(
            output_root=root,
            candidate_id=candidate_id,
            candidate=candidate,
            parent_candidate=parent_candidate,
            cues=cues,
            cue_commits=all_cue_commits,
            config=config,
            parent_chain=parent_chain,
            model_receipt=expected_model,
            expected_pipeline_binding=generation_binding,
        )
        final_record_without_commit = {
            key: value for key, value in record.items() if key != "candidateCommitReceipt"
        }
        if (
            record.get("candidateCommitReceipt")
            != candidate_commit["receiptBinding"]
            or final_record_without_commit != candidate_commit["record"]
        ):
            raise V5Error(f"V5 candidate commit binding drifted: {candidate_id}")
        all_candidate_commits.append(candidate_commit)
        records_by_id[candidate_id] = {
            "receiptRecord": record,
            "referencePath": reference_path,
            "cueAudio": cue_audio,
            "cueSampleRanges": cue_sample_ranges,
            "assemblyPath": assembly_path,
            "assemblyAudio": assembly_audio,
            "masterPath": master_path,
        }
    expected_progress = _progress_record(
        config=config,
        parent_chain=parent_chain,
        stress_record=stress_record,
        model_receipt=expected_model,
        cue_commits=all_cue_commits,
        candidate_commits=all_candidate_commits,
        expected_pipeline_binding=generation_binding,
    )
    if any(
        progress.get(key) != value
        for key, value in expected_progress.items()
        if key != "updatedAt"
    ):
        raise V5Error("complete V5 progress inventory does not match committed artifacts")
    return {
        "root": root,
        "receipt": receipt,
        "receiptPath": receipt_path,
        "receiptBinding": file_binding(receipt_path),
        "modelDirectory": clone_dir,
        "recordsByID": records_by_id,
        "cues": cues,
        "stressTextRecord": stress_record,
    }


def _load_reference_audio(path: Path, sample_rate: int) -> tuple[Any, dict[str, Any]]:
    import numpy as np
    from mlx_audio.utils import load_audio

    material = np.ascontiguousarray(
        np.asarray(load_audio(str(path), sample_rate=sample_rate), dtype=np.float32).reshape(
            -1
        )
    )
    if material.size == 0 or not np.all(np.isfinite(material)):
        raise V5Error(f"decoded speaker reference is empty or non-finite: {path}")
    return material, {
        "file": file_binding(path),
        "decodedSampleRate": sample_rate,
        "decodedSampleCount": int(material.size),
        "decodedFloat32LESHA256": native_float32_sha256(material),
    }


def _load_identity_extractor(model_directory: Path) -> QwenSpeakerExtractor:
    from mlx_audio.tts.utils import load_model

    model = load_model(str(model_directory))
    if not hasattr(model, "extract_speaker_embedding"):
        raise V5Error("pinned voice-clone model has no speaker encoder")
    return QwenSpeakerExtractor(model)


def _candidate_rank_key(record: dict[str, Any]) -> tuple[Any, ...]:
    alignment = record["cueAlignment"]["cueRecords"]
    identity = record["voiceIdentity"]
    return (
        0 if record["passesCompleteV5MachineGate"] else 1,
        -min(item["exactReferenceCoverage"] for item in alignment),
        record["wholeMasterAlignment"]["wordAlignmentErrorRate"],
        -min(
            item["minimumWindowToReferenceCosine"]
            for item in identity["cueRecords"]
        ),
        record["repetition"]["excessOccurrenceFraction"],
        record["candidateID"],
    )


def audit_v5(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    if args.offline is not True:
        raise V5Error("V5 audit requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"

    parent_chain = validate_parent_chain(config)
    diagnostic = validate_v4_diagnostic_evidence(config, deep=False)
    master_tools = validate_master_tools(config)
    asr_tools = validate_asr_tools(config)
    audit_root = prepare_output_root(args.output, config)
    transcript_root = audit_root / "transcripts"
    transcript_root.mkdir()
    work_root = confined_path(
        REPOSITORY_ROOT / config["paths"]["workRoot"],
        root=REPOSITORY_ROOT,
        must_exist=True,
        expect_directory=True,
    )
    stress_set = validate_stress_set(args.stress_set, config, parent_chain)
    stress_text, stress_record, cues = stress_material(config)
    if stress_record != stress_set["stressTextRecord"]:
        raise V5Error("stress text changed between validation and audit")
    reference_words = normalize_words(stress_text)
    extractor = _load_identity_extractor(stress_set["modelDirectory"])

    candidate_records: list[dict[str, Any]] = []
    for candidate_id in EXPECTED_FINALISTS:
        source = stress_set["recordsByID"][candidate_id]
        master_relation = verify_native_master_relation(
            source["assemblyPath"],
            source["masterPath"],
            config,
            audit_root=audit_root,
            confinement_root=work_root,
        )
        duration_seconds = master_relation["master"]["durationSeconds"]
        duration_gate = stress_duration_gate(duration_seconds, config)

        reference_audio, reference_record = _load_reference_audio(
            source["referencePath"], config["master"]["nativeSampleRate"]
        )
        identity = audit_voice_identity(
            reference_audio=reference_audio,
            cue_audio=source["cueAudio"],
            sample_rate=config["master"]["nativeSampleRate"],
            extractor=extractor,
            config=config,
        )

        transcript_path, asr_run = run_pinned_whisper(
            master_path=source["masterPath"],
            output_prefix=transcript_root / candidate_id,
            config=config,
            confinement_root=work_root,
        )
        transcript = production.load_json(transcript_path)
        timed_words, grouping = timed_words_from_whisper(
            transcript, master_duration_ms=duration_seconds * 1000
        )
        hypothesis_words = [item.text for item in timed_words]
        steps, whole_alignment = monotone_global_alignment(
            reference_words, hypothesis_words
        )
        cue_alignment = project_alignment_to_cues(
            reference_words=reference_words,
            hypothesis_words=timed_words,
            steps=steps,
            cues=cues,
            cue_sample_ranges=source["cueSampleRanges"],
            sample_rate=config["master"]["nativeSampleRate"],
            config=config,
        )
        repetition = reference_aware_repetition(
            reference_words, hypothesis_words, config
        )
        tempo = cue_tempo_audit(
            cues,
            source["cueSampleRanges"],
            config["master"]["nativeSampleRate"],
            config,
        )
        silence = silence_audit(
            source["assemblyAudio"],
            sample_rate=config["master"]["nativeSampleRate"],
            cue_sample_ranges=source["cueSampleRanges"],
            config=config,
        )
        gates = {
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
                "voiceIdentity": identity,
                "inProcessWholeMasterASR": asr_run,
                "timedWordGrouping": grouping,
                "wholeMasterAlignment": whole_alignment,
                "cueAlignment": cue_alignment,
                "repetition": repetition,
                "cueTempo": tempo,
                "silence": silence,
                "gates": gates,
                "passesCompleteV5MachineGate": all(gates.values()),
            }
        )

    ranking = sorted(candidate_records, key=_candidate_rank_key)
    passing = [
        item["candidateID"]
        for item in ranking
        if item["passesCompleteV5MachineGate"]
    ]
    recommendation = passing[0] if passing else None
    receipt = {
        "schemaVersion": 1,
        "status": AUDIT_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "rejectedV4DiagnosticEvidence": diagnostic,
        "stressSetReceipt": stress_set["receiptBinding"],
        "stressText": stress_record,
        "masterTools": master_tools,
        "asrTools": asr_tools,
        "externalTranscriptReceiptUsed": False,
        "candidateRecords": candidate_records,
        "ranking": [
            {
                "rank": index,
                "candidateID": item["candidateID"],
                "passesCompleteV5MachineGate": item[
                    "passesCompleteV5MachineGate"
                ],
            }
            for index, item in enumerate(ranking, start=1)
        ],
        "codexDiagnosticRecommendedVoiceID": recommendation,
        "recommendationMeaning": (
            "The first candidate in the frozen machine ranking only when it passes "
            "every V5 gate; this is not an editor selection or shipping approval."
        ),
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }
    receipt_path = audit_root / "audit.v5.receipt.json"
    write_json(receipt_path, receipt)
    return {**receipt, "receipt": file_binding(receipt_path)}


def validate_only(
    config: dict[str, Any], *, deep_v4: bool, offline: bool
) -> dict[str, Any]:
    if offline is not True:
        raise V5Error("V5 validation requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    parent_chain = validate_parent_chain(config)
    diagnostic = validate_v4_diagnostic_evidence(config, deep=deep_v4)
    _, stress_record, cues = stress_material(config)
    master_tools = validate_master_tools(config)
    asr_tools = validate_asr_tools(config)
    base_config = production.validate_config()
    model_directory, model_files = production.verify_model_snapshot(
        base_config["models"]["voiceClone"], offline=True
    )
    return {
        "schemaVersion": 1,
        "status": METHOD_STATUS,
        "trustDomain": TRUST_DOMAIN,
        "pipelineBinding": pipeline_binding(config),
        "parentChain": parent_chain,
        "rejectedV4DiagnosticEvidence": diagnostic,
        "stressText": stress_record,
        "cueCount": len(cues),
        "masterTools": master_tools,
        "asrTools": asr_tools,
        "voiceCloneModel": production.model_receipt(
            base_config["models"]["voiceClone"], model_files
        ),
        "voiceCloneModelDirectory": str(model_directory),
        "generationCommandAvailable": True,
        "generationExecuted": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "claimsExcluded": config["claimsExcluded"],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Frozen non-shipping V5 narration audit method"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser(
        "validate", help="validate the frozen method without generating audio"
    )
    validate.add_argument("--offline", action="store_true", required=True)
    validate.add_argument("--deep-v4", action="store_true")
    generate = subparsers.add_parser(
        "generate", help="resume or create the frozen two-candidate V5 cue set"
    )
    generate.add_argument("--output", type=Path, required=True)
    generate.add_argument("--offline", action="store_true", required=True)
    audit = subparsers.add_parser(
        "audit", help="run one in-process audit of an existing V5 stress set"
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
            result = validate_only(
                config, deep_v4=args.deep_v4, offline=args.offline
            )
        elif args.command == "generate":
            result = generate_v5(args, config)
        elif args.command == "audit":
            result = audit_v5(args, config)
        else:
            raise V5Error(f"unsupported V5 command: {args.command}")
    except (
        V5Error,
        production.PipelineError,
        subprocess.CalledProcessError,
        OSError,
        ValueError,
    ) as error:
        print(f"V5 narration method failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
