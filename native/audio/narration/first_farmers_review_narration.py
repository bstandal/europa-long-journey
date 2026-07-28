#!/usr/bin/env python3
"""Build and verify the non-shipping Chapter 01 narration cue set.

The production narration trust domain remains closed.  This module accepts
only the editor-authorised ``NON_SHIPPING_REVIEW`` scope and emits exactly one
offline 48 kHz M4A cue for each frozen manuscript segment.
"""

from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any, Iterable


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
REVIEW_ROOT = NARRATION_ROOT / "review/chapter-01"
AUTHORIZATION_PATH = REVIEW_ROOT / "review-authorization.json"
PROBE_MANIFEST_PATH = REVIEW_ROOT / "probes/manifest.json"
PROBE_SELECTION_PATH = REVIEW_ROOT / "probe-selection.json"
MANIFEST_PATH = REVIEW_ROOT / "manifest.json"
CUES_ROOT = REVIEW_ROOT / "cues"
WORK_ROOT = NARRATION_ROOT / "work/chapter-01-review-v1"
DRAFT_PATH = (
    REPOSITORY_ROOT
    / "native/phase2/editor-review/first-farmers/first-farmers-native-draft-v1.json"
)
TEXT_FREEZE_PATH = (
    REPOSITORY_ROOT
    / "native/content/backstage/first-farmers/chapter-01-review-text-freeze-v1.json"
)
V6_CONFIG_PATH = NARRATION_ROOT / "v6-audit-config.json"
PIPELINE_CONFIG_PATH = NARRATION_ROOT / "pipeline-config.json"
IDENTITY_TEXT_PATH = NARRATION_ROOT / "identity-reference-v1.txt"
CANDIDATE_REFERENCE_PATHS = {
    "voice-candidate-05": NARRATION_ROOT
    / "work/cast-v1-2026-07-24/references/voice-candidate-05-reference.wav",
    "voice-candidate-06": NARRATION_ROOT
    / "work/cast-v1-2026-07-24/references/voice-candidate-06-reference.wav",
}
STATUS = "NON_SHIPPING_REVIEW"
SHIPPING_STATE = "PROHIBITED"
EXPECTED_CUE_COUNT = 37
EXPECTED_SAMPLE_RATE = 48_000
QWEN_ENGINE = "Qwen3-TTS Base"
VOX_ENGINE = "VoxCPM2 V12"


class ReviewNarrationError(RuntimeError):
    """Raised when review narration escapes its exact bounded contract."""


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def binding(path: Path, *, repository_relative: bool = False) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ReviewNarrationError(f"required regular file is unavailable: {path}")
    resolved = path.absolute()
    rendered_path = str(resolved)
    if repository_relative:
        try:
            rendered_path = resolved.relative_to(REPOSITORY_ROOT).as_posix()
        except ValueError as error:
            raise ReviewNarrationError(f"file lies outside repository: {path}") from error
    return {
        "path": rendered_path,
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReviewNarrationError(f"invalid or missing JSON: {path}") from error
    if not isinstance(value, dict):
        raise ReviewNarrationError(f"JSON root must be an object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    temporary = path.with_suffix(path.suffix + ".partial")
    if temporary.exists():
        raise ReviewNarrationError(f"stale partial JSON exists: {temporary}")
    temporary.write_text(payload, encoding="utf-8")
    if temporary.read_text(encoding="utf-8") != payload:
        raise ReviewNarrationError(f"JSON reread failed: {temporary}")
    os.replace(temporary, path)


def validate_authorization() -> dict[str, Any]:
    document = load_json(AUTHORIZATION_PATH)
    required = {
        "schemaVersion": 1,
        "status": "NON_SHIPPING_REVIEW_AUTHORIZED",
        "shippingState": SHIPPING_STATE,
        "milestone": "CHAPTER_01_REVIEW_READY",
        "chapterID": "first-farmers",
        "configuration": STATUS,
        "approvedBy": "editor-in-chief",
    }
    for key, expected in required.items():
        if document.get(key) != expected:
            raise ReviewNarrationError(f"review authorization drifted at {key}")
    scope = document.get("scope", {})
    vox = scope.get("voxcpm2V12", {})
    fallback = scope.get("fallback", {})
    cue_set = scope.get("chapterCueSet", {})
    if (
        vox.get("permitted") is not True
        or vox.get("candidateIDs")
        != ["voice-candidate-05", "voice-candidate-06"]
        or vox.get("technicalProbeCount") != 2
        or vox.get("minimumProbeSeconds") != 60
        or vox.get("maximumProbeSeconds") != 90
        or vox.get("productionVoicePromotionPermitted") is not False
        or vox.get("shippingUsePermitted") is not False
        or fallback.get("engine") != QWEN_ENGINE
        or fallback.get("candidateID") != "voice-candidate-05"
        or fallback.get("wholeChapterOnly") is not True
        or fallback.get("shippingUsePermitted") is not False
        or cue_set.get("cueCount") != EXPECTED_CUE_COUNT
        or cue_set.get("locale") != "en"
        or cue_set.get("runtimeGenerationPermitted") is not False
        or cue_set.get("shippingUsePermitted") is not False
    ):
        raise ReviewNarrationError("review narration scope drifted")
    authority = document.get("v12PresynthesisAuthority", {})
    authority_path = REPOSITORY_ROOT / str(authority.get("path", ""))
    actual = binding(authority_path, repository_relative=True)
    if (
        actual != {
            "path": authority.get("path"),
            "bytes": authority.get("bytes"),
            "sha256": authority.get("sha256"),
        }
        or authority.get("remainsClosedForProduction") is not True
        or authority.get("modifiedByThisDecision") is not False
    ):
        raise ReviewNarrationError("V12 pre-synthesis authority binding drifted")
    closed = load_json(authority_path)
    if (
        closed.get("synthesisPermitted") is not False
        or closed.get("requiresEditorDecision") is not True
        or closed.get("v11IsTerminal") is not True
        or closed.get("v11TerminalAuthorityModified") is not False
    ):
        raise ReviewNarrationError("V12 production boundary is no longer closed")
    return document


def manuscript_segments() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    draft = load_json(DRAFT_PATH)
    arcs = draft.get("arcs")
    if not isinstance(arcs, list) or len(arcs) != 3:
        raise ReviewNarrationError("Chapter 01 must contain exactly three arcs")
    segments: list[dict[str, Any]] = []
    beat_count = 0
    for arc_index, arc in enumerate(arcs):
        beats = arc.get("beats")
        if not isinstance(beats, list):
            raise ReviewNarrationError("Chapter 01 arc has no beat list")
        for beat_index, beat in enumerate(beats):
            beat_count += 1
            narrative = beat.get("narrative", {})
            for segment_index, segment in enumerate(narrative.get("segments", [])):
                segment_id = segment.get("id")
                text = segment.get("text")
                if (
                    not isinstance(segment_id, str)
                    or not re.fullmatch(r"ff-[a-z0-9-]+", segment_id)
                    or not isinstance(text, str)
                    or not text.strip()
                    or text != text.strip()
                ):
                    raise ReviewNarrationError("invalid manuscript segment identity or text")
                segments.append(
                    {
                        "order": len(segments) + 1,
                        "arcID": arc.get("arcID"),
                        "arcIndex": arc_index,
                        "beatID": beat.get("beatID"),
                        "beatIndex": beat_index,
                        "segmentIndex": segment_index,
                        "manuscriptSegmentID": segment_id,
                        "manuscriptSegmentSHA256": sha256_bytes(text.encode("utf-8")),
                        "text": text,
                        "cueID": f"narration-{segment_id}",
                    }
                )
    if beat_count != 17 or len(segments) != EXPECTED_CUE_COUNT:
        raise ReviewNarrationError(
            f"Chapter 01 structure drifted: {beat_count} beats/{len(segments)} segments"
        )
    if len({item["manuscriptSegmentID"] for item in segments}) != len(segments):
        raise ReviewNarrationError("manuscript segment IDs are not unique")
    if len({item["cueID"] for item in segments}) != len(segments):
        raise ReviewNarrationError("narration cue IDs are not unique")
    return draft, segments


def manuscript_binding(segments: list[dict[str, Any]]) -> dict[str, Any]:
    freeze = review_text_freeze(segments)
    public = [
        {
            "order": item["order"],
            "arcID": item["arcID"],
            "beatID": item["beatID"],
            "manuscriptSegmentID": item["manuscriptSegmentID"],
            "manuscriptSegmentSHA256": item["manuscriptSegmentSHA256"],
            "cueID": item["cueID"],
        }
        for item in segments
    ]
    return {
        "draft": binding(DRAFT_PATH, repository_relative=True),
        "reviewTextFreeze": binding(TEXT_FREEZE_PATH, repository_relative=True),
        "segmentCount": len(public),
        "segmentManifestSHA256": sha256_bytes(canonical_json(public)),
        "combinedBindingSHA256": freeze["combinedBindingSha256"],
    }


def review_text_freeze(segments: list[dict[str, Any]]) -> dict[str, Any]:
    freeze = load_json(TEXT_FREEZE_PATH)
    draft_sha = sha256_file(DRAFT_PATH)
    if (
        freeze.get("schemaVersion") != 1
        or freeze.get("freezeID") != "first-farmers-chapter-01-review-text-v1"
        or freeze.get("milestone") != "CHAPTER_01_REVIEW_READY"
        or freeze.get("status") != "CHAPTER_01_REVIEW_TEXT_FROZEN"
        or freeze.get("shippingBoundary") != "BACKSTAGE_ONLY_DO_NOT_PACKAGE"
        or freeze.get("chapterID") != "first-farmers"
        or freeze.get("locale") != "en"
        or freeze.get("authority") != "EDITOR_IN_CHIEF_APPROVED_REVIEW_TEXT"
        or freeze.get("segmentCount") != EXPECTED_CUE_COUNT
        or freeze.get("sourceDraft")
        != {
            "path": DRAFT_PATH.relative_to(REPOSITORY_ROOT).as_posix(),
            "sha256": draft_sha,
        }
        or not re.fullmatch(r"[0-9a-f]{64}", str(freeze.get("combinedBindingSha256", "")))
    ):
        raise ReviewNarrationError("Chapter 01 review-text freeze drifted")
    expected = [
        (item["order"], item["manuscriptSegmentID"], item["manuscriptSegmentSHA256"])
        for item in segments
    ]
    actual = [
        (item.get("ordinal"), item.get("segmentID"), item.get("textSha256"))
        for item in freeze.get("segments", [])
    ]
    if actual != expected:
        raise ReviewNarrationError("review-text freeze segment binding drifted")
    return freeze


def selected_review_voice() -> dict[str, Any]:
    selection = load_json(PROBE_SELECTION_PATH)
    if (
        selection.get("schemaVersion") != 1
        or selection.get("status") != STATUS
        or selection.get("shippingState") != SHIPPING_STATE
        or selection.get("chapterID") != "first-farmers"
        or selection.get("probeCount") != 2
        or selection.get("shippingUsePermitted") is not False
    ):
        raise ReviewNarrationError("probe selection record is invalid")
    engine = selection.get("selectedEngine")
    candidate = selection.get("selectedCandidateID")
    if engine == QWEN_ENGINE and candidate != "voice-candidate-05":
        raise ReviewNarrationError("Qwen fallback escaped candidate 05")
    if engine == VOX_ENGINE and candidate not in CANDIDATE_REFERENCE_PATHS:
        raise ReviewNarrationError("VoxCPM2 selection escaped the two candidates")
    if engine not in {QWEN_ENGINE, VOX_ENGINE}:
        raise ReviewNarrationError("unknown review narration engine")
    return selection


def _ffmpeg_path() -> Path:
    config = load_json(V6_CONFIG_PATH)
    path = Path(config["master"]["ffmpegPath"])
    expected_bytes = config["master"]["ffmpegBytes"]
    expected_sha = config["master"]["ffmpegSHA256"]
    if binding(path) != {
        "path": str(path.absolute()),
        "bytes": expected_bytes,
        "sha256": expected_sha,
    }:
        raise ReviewNarrationError("pinned FFmpeg binding drifted")
    return path


def _ffprobe_path() -> Path:
    config = load_json(V6_CONFIG_PATH)
    path = Path(config["master"]["ffprobePath"])
    expected_bytes = config["master"]["ffprobeBytes"]
    expected_sha = config["master"]["ffprobeSHA256"]
    if binding(path) != {
        "path": str(path.absolute()),
        "bytes": expected_bytes,
        "sha256": expected_sha,
    }:
        raise ReviewNarrationError("pinned FFprobe binding drifted")
    return path


def _encode_command(source: Path, destination: Path) -> list[str]:
    return [
        str(_ffmpeg_path()),
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
        "-ar",
        str(EXPECTED_SAMPLE_RATE),
        "-ac",
        "1",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-movflags",
        "+faststart",
        str(destination),
    ]


def encode_m4a_deterministically(source: Path, destination: Path) -> dict[str, Any]:
    if not source.is_file() or source.is_symlink():
        raise ReviewNarrationError(f"source WAV is unavailable: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise ReviewNarrationError(f"refusing to overwrite review cue: {destination}")
    first = destination.with_suffix(".first.m4a")
    second = destination.with_suffix(".second.m4a")
    if first.exists() or second.exists():
        raise ReviewNarrationError(f"stale encode comparison exists for {destination}")
    subprocess.run(_encode_command(source, first), check=True)
    subprocess.run(_encode_command(source, second), check=True)
    if first.read_bytes() != second.read_bytes():
        raise ReviewNarrationError(f"AAC encoding is not byte-identical: {destination}")
    os.replace(first, destination)
    second.unlink()
    return audio_record(destination)


def decoded_float32(path: Path, *, sample_rate: int = EXPECTED_SAMPLE_RATE) -> array:
    completed = subprocess.run(
        [
            str(_ffmpeg_path()),
            "-nostdin",
            "-v",
            "error",
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-ar",
            str(sample_rate),
            "-ac",
            "1",
            "-f",
            "f32le",
            "-acodec",
            "pcm_f32le",
            "pipe:1",
        ],
        check=True,
        capture_output=True,
    )
    samples = array("f")
    samples.frombytes(completed.stdout)
    if sys.byteorder != "little":
        samples.byteswap()
    if not samples or any(not math.isfinite(value) for value in samples):
        raise ReviewNarrationError(f"decoded audio is empty or non-finite: {path}")
    return samples


def audio_record(path: Path) -> dict[str, Any]:
    probe = subprocess.run(
        [
            str(_ffprobe_path()),
            "-v",
            "error",
            "-show_entries",
            "stream=codec_name,sample_rate,channels",
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
        raise ReviewNarrationError(f"review cue has invalid stream inventory: {path}")
    stream = streams[0]
    if (
        stream.get("codec_name") != "aac"
        or int(stream.get("sample_rate", 0)) != EXPECTED_SAMPLE_RATE
        or int(stream.get("channels", 0)) != 1
    ):
        raise ReviewNarrationError(f"review cue format drifted: {path}")
    decoded = decoded_float32(path)
    return {
        "repositoryPath": path.absolute().relative_to(REPOSITORY_ROOT).as_posix(),
        "sampleRate": EXPECTED_SAMPLE_RATE,
        "durationSamples": len(decoded),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def runtime_audio_record(path: Path) -> dict[str, Any]:
    """Bind a cue to the valid frames AVAudioFile exposes at runtime.

    The decoded probe used by the voice audit includes the AAC encoder's final
    remainder. AVAudioFile excludes that remainder from ``length``. Runtime
    timelines must therefore use the container stream's valid-frame duration,
    or their final event can request frames that the installed file cannot
    supply.
    """

    decoded = audio_record(path)
    probe = subprocess.run(
        [
            str(_ffprobe_path()),
            "-v",
            "error",
            "-select_streams",
            "a:0",
            "-show_entries",
            "stream=duration_ts,time_base",
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
        raise ReviewNarrationError(f"review cue has no runtime duration: {path}")
    stream = streams[0]
    if stream.get("time_base") != f"1/{EXPECTED_SAMPLE_RATE}":
        raise ReviewNarrationError(f"review cue runtime time base drifted: {path}")
    try:
        valid_frames = int(stream["duration_ts"])
    except (KeyError, TypeError, ValueError) as error:
        raise ReviewNarrationError(
            f"review cue runtime duration is invalid: {path}"
        ) from error
    decoder_remainder = decoded["durationSamples"] - valid_frames
    if valid_frames <= 0 or not 0 <= decoder_remainder < 1_024:
        raise ReviewNarrationError(
            f"review cue runtime/decoder duration diverged: {path}"
        )
    return decoded | {"durationSamples": valid_frames}


def _trim_fade_and_pause(audio: Any, sample_rate: int) -> Any:
    import numpy as np

    material = np.ascontiguousarray(np.asarray(audio, dtype=np.float32).reshape(-1))
    if material.size == 0 or not np.all(np.isfinite(material)):
        raise ReviewNarrationError("synthesizer returned empty or non-finite PCM")
    threshold = 10 ** (-52 / 20)
    active = np.flatnonzero(np.abs(material) >= threshold)
    if active.size == 0:
        raise ReviewNarrationError("synthesizer returned silence")
    pre = round(sample_rate * 0.06)
    post = round(sample_rate * 0.10)
    start = max(0, int(active[0]) - pre)
    end = min(material.size, int(active[-1]) + post + 1)
    material = np.ascontiguousarray(material[start:end], dtype=np.float32)
    fade = min(round(sample_rate * 0.012), material.size // 2)
    if fade:
        ramp = np.sin(np.linspace(0, math.pi / 2, fade, endpoint=True)) ** 2
        material[:fade] *= ramp.astype(np.float32)
        material[-fade:] *= ramp[::-1].astype(np.float32)
    peak = float(np.max(np.abs(material)))
    target = 10 ** (-3 / 20)
    if peak <= 0 or not math.isfinite(peak):
        raise ReviewNarrationError("review cue has invalid peak")
    material *= np.float32(target / peak)
    leading = np.zeros(round(sample_rate * 0.04), dtype=np.float32)
    trailing = np.zeros(round(sample_rate * 0.14), dtype=np.float32)
    return np.ascontiguousarray(
        np.concatenate((leading, material, trailing)), dtype=np.float32
    )


def build_manifest(
    *, engine: str, candidate_id: str, cue_records: list[dict[str, Any]]
) -> dict[str, Any]:
    validate_authorization()
    selection = selected_review_voice()
    _, segments = manuscript_segments()
    if (
        selection.get("selectedEngine") != engine
        or selection.get("selectedCandidateID") != candidate_id
    ):
        raise ReviewNarrationError("cue engine does not match technical selection")
    if len(cue_records) != EXPECTED_CUE_COUNT:
        raise ReviewNarrationError("cue record count is not exactly 37")
    by_id = {item["cueID"]: item for item in cue_records}
    ordered = []
    for segment in segments:
        record = by_id.get(segment["cueID"])
        if record is None:
            raise ReviewNarrationError(f"missing cue: {segment['cueID']}")
        expected_path = (
            CUES_ROOT / f"{segment['cueID']}.m4a"
        ).absolute().relative_to(REPOSITORY_ROOT).as_posix()
        if (
            record.get("repositoryPath") != expected_path
            or record.get("sampleRate") != EXPECTED_SAMPLE_RATE
            or type(record.get("durationSamples")) is not int
            or record["durationSamples"] <= 0
        ):
            raise ReviewNarrationError(f"cue record drifted: {segment['cueID']}")
        ordered.append(
            {
                "cueID": segment["cueID"],
                "manuscriptSegmentID": segment["manuscriptSegmentID"],
                "manuscriptSegmentSHA256": segment["manuscriptSegmentSHA256"],
                "repositoryPath": record["repositoryPath"],
                "sampleRate": record["sampleRate"],
                "durationSamples": record["durationSamples"],
                "bytes": record["bytes"],
                "sha256": record["sha256"],
            }
        )
    freeze = review_text_freeze(segments)
    return {
        "schemaVersion": 1,
        "manifestID": "chapter-01-review-narration-v1",
        "status": STATUS,
        "shippingState": SHIPPING_STATE,
        "chapterID": "first-farmers",
        "sampleRate": EXPECTED_SAMPLE_RATE,
        "manuscriptDraftSHA256": freeze["sourceDraft"]["sha256"],
        "combinedBindingSHA256": freeze["combinedBindingSha256"],
        "milestone": "CHAPTER_01_REVIEW_READY",
        "locale": "en",
        "cueCount": EXPECTED_CUE_COUNT,
        "engine": engine,
        "candidateID": candidate_id,
        "technicalSelection": binding(
            PROBE_SELECTION_PATH, repository_relative=True
        ),
        "authorization": binding(AUTHORIZATION_PATH, repository_relative=True),
        "manuscript": manuscript_binding(segments),
        "durationSource": "encoded AAC valid frames at 48 kHz",
        "runtimeGenerationPermitted": False,
        "shippingUsePermitted": False,
        "cues": ordered,
    }


def _qwen_model_and_reference() -> tuple[Any, Path, str, dict[str, Any]]:
    os.environ.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_HUB_DISABLE_TELEMETRY": "1",
            "DO_NOT_TRACK": "1",
            "NO_PROXY": "*",
        }
    )
    import pipeline as production
    from mlx_audio.tts.utils import load_model

    config = production.validate_config(PIPELINE_CONFIG_PATH)
    model_path, model_files = production.verify_model_snapshot(
        config["models"]["voiceClone"], offline=True
    )
    model = load_model(str(model_path))
    reference = CANDIDATE_REFERENCE_PATHS["voice-candidate-05"]
    if binding(reference, repository_relative=True) != {
        "path": reference.absolute().relative_to(REPOSITORY_ROOT).as_posix(),
        "bytes": 2_119_782,
        "sha256": "a832c5fd5ac65d5b7392f69a93f14ed0b1dfbb3ba88bb7b2d34328b215acab04",
    }:
        raise ReviewNarrationError("Qwen fallback reference drifted")
    identity_text = production.canonical_text(IDENTITY_TEXT_PATH)
    return model, reference, identity_text, {
        "config": config,
        "modelPath": str(model_path),
        "verifiedModelFiles": model_files,
    }


def render_qwen() -> dict[str, Any]:
    validate_authorization()
    selection = selected_review_voice()
    if (
        selection.get("selectedEngine") != QWEN_ENGINE
        or selection.get("selectedCandidateID") != "voice-candidate-05"
        or selection.get("voxcpm2TechnicalPassCount") != 0
    ):
        raise ReviewNarrationError("Qwen fallback has not been selected")
    if MANIFEST_PATH.exists():
        raise ReviewNarrationError("review narration manifest already exists")
    _, segments = manuscript_segments()
    CUES_ROOT.mkdir(parents=True, exist_ok=True)
    work = WORK_ROOT / "qwen-candidate-05"
    records_root = work / "records"
    native_root = work / "native"
    records_root.mkdir(parents=True, exist_ok=True)
    native_root.mkdir(parents=True, exist_ok=True)
    model, reference, identity_text, model_record = _qwen_model_and_reference()
    import pipeline as production

    cue_records = []
    for index, segment in enumerate(segments):
        cue_id = segment["cueID"]
        destination = CUES_ROOT / f"{cue_id}.m4a"
        record_path = records_root / f"{cue_id}.json"
        if destination.exists() or record_path.exists():
            if not destination.is_file() or not record_path.is_file():
                raise ReviewNarrationError(f"partial Qwen cue exists: {cue_id}")
            existing = load_json(record_path)
            actual = audio_record(destination)
            if (
                existing.get("cueID") != cue_id
                or existing.get("manuscriptSegmentSHA256")
                != segment["manuscriptSegmentSHA256"]
                or existing.get("audio") != actual
            ):
                raise ReviewNarrationError(f"resumed Qwen cue drifted: {cue_id}")
            cue_records.append(runtime_audio_record(destination) | {"cueID": cue_id})
            continue
        audio, sample_rate = production.synthesize_clone(
            model,
            text=segment["text"],
            reference_path=reference,
            reference_text=identity_text,
            seed=27_010_000 + index * 101,
            config=model_record["config"],
            max_tokens=384,
        )
        processed = _trim_fade_and_pause(audio, sample_rate)
        native_path = native_root / f"{cue_id}.wav"
        production.write_float_wav(native_path, sample_rate, processed)
        encoded = encode_m4a_deterministically(native_path, destination)
        record = {
            "schemaVersion": 1,
            "status": STATUS,
            "shippingState": SHIPPING_STATE,
            "cueID": cue_id,
            "manuscriptSegmentSHA256": segment["manuscriptSegmentSHA256"],
            "engine": QWEN_ENGINE,
            "candidateID": "voice-candidate-05",
            "seed": 27_010_000 + index * 101,
            "audio": encoded,
        }
        write_json(record_path, record)
        cue_records.append(runtime_audio_record(destination) | {"cueID": cue_id})
        print(f"Qwen review cue {index + 1}/{EXPECTED_CUE_COUNT}: {cue_id}", flush=True)
    manifest = build_manifest(
        engine=QWEN_ENGINE,
        candidate_id="voice-candidate-05",
        cue_records=cue_records,
    )
    manifest["generation"] = {
        "offline": True,
        "oneWholeChapterCandidate": True,
        "reference": binding(reference, repository_relative=True),
        "model": {
            "repository": model_record["config"]["models"]["voiceClone"]["repository"],
            "revision": model_record["config"]["models"]["voiceClone"]["revision"],
            "verifiedWeightFiles": model_record["verifiedModelFiles"],
        },
    }
    write_json(MANIFEST_PATH, manifest)
    return validate_manifest()


def validate_manifest() -> dict[str, Any]:
    validate_authorization()
    selection = selected_review_voice()
    document = load_json(MANIFEST_PATH)
    exact = {
        "schemaVersion": 1,
        "manifestID": "chapter-01-review-narration-v1",
        "status": STATUS,
        "shippingState": SHIPPING_STATE,
        "milestone": "CHAPTER_01_REVIEW_READY",
        "chapterID": "first-farmers",
        "sampleRate": EXPECTED_SAMPLE_RATE,
        "locale": "en",
        "cueCount": EXPECTED_CUE_COUNT,
        "runtimeGenerationPermitted": False,
        "shippingUsePermitted": False,
    }
    for key, expected in exact.items():
        if document.get(key) != expected:
            raise ReviewNarrationError(f"review narration manifest drifted at {key}")
    if document.get("durationSource") != "encoded AAC valid frames at 48 kHz":
        raise ReviewNarrationError("review narration runtime duration authority drifted")
    if (
        document.get("engine") != selection.get("selectedEngine")
        or document.get("candidateID") != selection.get("selectedCandidateID")
        or document.get("authorization")
        != binding(AUTHORIZATION_PATH, repository_relative=True)
        or document.get("technicalSelection")
        != binding(PROBE_SELECTION_PATH, repository_relative=True)
    ):
        raise ReviewNarrationError("review narration authority or voice drifted")
    _, segments = manuscript_segments()
    freeze = review_text_freeze(segments)
    if (
        document.get("manuscriptDraftSHA256") != freeze["sourceDraft"]["sha256"]
        or document.get("combinedBindingSHA256")
        != freeze["combinedBindingSha256"]
    ):
        raise ReviewNarrationError("review narration text-freeze binding drifted")
    if document.get("manuscript") != manuscript_binding(segments):
        raise ReviewNarrationError("review narration manuscript binding drifted")
    cues = document.get("cues")
    if not isinstance(cues, list) or len(cues) != EXPECTED_CUE_COUNT:
        raise ReviewNarrationError("review narration does not contain exactly 37 cues")
    expected_names = {f"{item['cueID']}.m4a" for item in segments}
    actual_names = {
        path.name for path in CUES_ROOT.iterdir() if path.is_file() and not path.is_symlink()
    }
    if actual_names != expected_names:
        raise ReviewNarrationError("review cue directory inventory drifted")
    total_samples = 0
    for cue, segment in zip(cues, segments, strict=True):
        expected_keys = {
            "cueID",
            "manuscriptSegmentID",
            "manuscriptSegmentSHA256",
            "repositoryPath",
            "sampleRate",
            "durationSamples",
            "bytes",
            "sha256",
        }
        if set(cue) != expected_keys:
            raise ReviewNarrationError(f"cue manifest fields drifted: {segment['cueID']}")
        path = REPOSITORY_ROOT / cue["repositoryPath"]
        actual = runtime_audio_record(path)
        if (
            cue["cueID"] != segment["cueID"]
            or cue["manuscriptSegmentID"] != segment["manuscriptSegmentID"]
            or cue["manuscriptSegmentSHA256"]
            != segment["manuscriptSegmentSHA256"]
            or {key: cue[key] for key in actual} != actual
            or not cue["repositoryPath"].startswith(
                "native/audio/narration/review/chapter-01/cues/"
            )
        ):
            raise ReviewNarrationError(f"review cue binding drifted: {segment['cueID']}")
        total_samples += cue["durationSamples"]
    return {
        "status": STATUS,
        "shippingState": SHIPPING_STATE,
        "engine": document["engine"],
        "candidateID": document["candidateID"],
        "cueCount": len(cues),
        "sampleRate": EXPECTED_SAMPLE_RATE,
        "totalDurationSamples": total_samples,
        "totalDurationSeconds": total_samples / EXPECTED_SAMPLE_RATE,
        "manifest": binding(MANIFEST_PATH, repository_relative=True),
    }


def refresh_manifest_runtime_durations() -> dict[str, Any]:
    """Rebind an existing review cue set without synthesising new audio."""

    validate_authorization()
    selection = selected_review_voice()
    existing = load_json(MANIFEST_PATH)
    engine = selection.get("selectedEngine")
    candidate_id = selection.get("selectedCandidateID")
    if (
        existing.get("engine") != engine
        or existing.get("candidateID") != candidate_id
        or not isinstance(existing.get("generation"), dict)
    ):
        raise ReviewNarrationError("existing review narration authority drifted")
    _, segments = manuscript_segments()
    expected_names = {f"{item['cueID']}.m4a" for item in segments}
    actual_names = {
        path.name
        for path in CUES_ROOT.iterdir()
        if path.is_file() and not path.is_symlink()
    }
    if actual_names != expected_names:
        raise ReviewNarrationError("review cue directory inventory drifted")
    cue_records = [
        runtime_audio_record(CUES_ROOT / f"{segment['cueID']}.m4a")
        | {"cueID": segment["cueID"]}
        for segment in segments
    ]
    refreshed = build_manifest(
        engine=engine,
        candidate_id=candidate_id,
        cue_records=cue_records,
    )
    refreshed["generation"] = existing["generation"]
    write_json(MANIFEST_PATH, refreshed)
    return validate_manifest()


def plan() -> dict[str, Any]:
    authorization = validate_authorization()
    _, segments = manuscript_segments()
    return {
        "status": STATUS,
        "chapterID": "first-farmers",
        "cueCount": len(segments),
        "manuscript": manuscript_binding(segments),
        "authorization": binding(AUTHORIZATION_PATH, repository_relative=True),
        "authorizedCandidates": authorization["scope"]["voxcpm2V12"][
            "candidateIDs"
        ],
        "outputManifest": MANIFEST_PATH.relative_to(REPOSITORY_ROOT).as_posix(),
    }


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=("plan", "render-qwen", "refresh-runtime-durations", "validate"),
    )
    args = parser.parse_args(list(argv) if argv is not None else None)
    try:
        if args.command == "plan":
            result = plan()
        elif args.command == "render-qwen":
            result = render_qwen()
        elif args.command == "refresh-runtime-durations":
            result = refresh_manifest_runtime_durations()
        else:
            result = validate_manifest()
    except Exception as error:
        print(f"Chapter 01 review narration failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
