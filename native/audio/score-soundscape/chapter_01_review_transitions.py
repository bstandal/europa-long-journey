#!/usr/bin/env python3
"""Build three deterministic, review-only Chapter 01 transition renders."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


SCRIPT_PATH = Path(__file__).absolute()
REPOSITORY_ROOT = SCRIPT_PATH.parents[3]
AUDIO_ROOT = SCRIPT_PATH.parent
CACHE_ROOT = AUDIO_ROOT / "cache"
OUTPUT_ROOT = AUDIO_ROOT / "chapter-01-review-transitions-v1"
ASSET_ROOT = OUTPUT_ROOT / "audio"
WORK_ROOT = CACHE_ROOT / "chapter-01-review-transitions-v1"
MANIFEST_PATH = OUTPUT_ROOT / "manifest.json"
AUTHORIZATION_PATH = (
    REPOSITORY_ROOT
    / "native/audio/narration/review/chapter-01/review-authorization.json"
)
TOOLCHAIN_PATH = AUDIO_ROOT / "toolchain.json"
FFMPEG_PATH = Path("/opt/homebrew/bin/ffmpeg").resolve(strict=True)

STATUS = "NON_SHIPPING_REVIEW"
SHIPPING_STATE = "PROHIBITED"
SAMPLE_RATE = 48_000
CHANNEL_COUNT = 2
SOURCE_FRAMES = 192_000
CROSSFADE_FRAMES = 96_000
NOMINAL_OUTPUT_FRAMES = SOURCE_FRAMES * 2 - CROSSFADE_FRAMES

PROGRAMS = {
    "household-crosses": {
        "directory": "household-crosses-responsive-v1",
        "receipt": "render-receipt.json",
    },
    "harvest": {
        "directory": "harvest-responsive-v1",
        "receipt": "render-receipt.json",
    },
    "three-records": {
        "directory": "three-records-responsive-v1",
        "receipt": "render-receipt.json",
    },
    "continent-remade": {
        "directory": "continent-remade-responsive-v1",
        "receipt": "render-receipt.json",
    },
}

TRANSITIONS = [
    {
        "transitionID": "transition-aegean-thessaly-v1",
        "fromWorld": "aegean-crossing",
        "toWorld": "thessaly-first-field",
        "sourceA": ("household-crosses", "consequence/program-preview.wav"),
        "sourceB": ("harvest", "approach/program-preview.wav"),
    },
    {
        "transitionID": "transition-store-iron-gates-v1",
        "fromWorld": "harvest-store",
        "toWorld": "iron-gates-danube",
        "sourceA": ("harvest", "consequence/program-preview.wav"),
        "sourceB": ("three-records", "approach/program-preview.wav"),
    },
    {
        "transitionID": "transition-farming-belt-steppe-v1",
        "fromWorld": "european-farming-belt",
        "toWorld": "steppe-transition",
        "sourceA": ("continent-remade", "approach/program-preview.wav"),
        "sourceB": ("continent-remade", "consequence/program-preview.wav"),
    },
]


class TransitionError(RuntimeError):
    """Raised when a transition escapes the non-shipping derivation contract."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise TransitionError(f"cannot read JSON: {path}") from error
    if not isinstance(value, dict):
        raise TransitionError(f"JSON root must be an object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def binding(path: Path, *, repository_relative: bool = True) -> dict[str, Any]:
    path = path.absolute()
    if not path.is_file() or path.is_symlink():
        raise TransitionError(f"bound file is missing or linked: {path}")
    rendered_path = (
        path.relative_to(REPOSITORY_ROOT).as_posix()
        if repository_relative
        else str(path)
    )
    return {
        "path": rendered_path,
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def validate_authorization() -> dict[str, Any]:
    authorization = load_json(AUTHORIZATION_PATH)
    if (
        authorization.get("schemaVersion") != 1
        or authorization.get("status") != "NON_SHIPPING_REVIEW_AUTHORIZED"
        or authorization.get("shippingState") != SHIPPING_STATE
        or authorization.get("milestone") != "CHAPTER_01_REVIEW_READY"
        or authorization.get("chapterID") != "first-farmers"
        or authorization.get("configuration") != "NON_SHIPPING_REVIEW"
    ):
        raise TransitionError("Chapter 01 review authorization drifted")
    return authorization


def validate_ffmpeg() -> dict[str, Any]:
    toolchain = load_json(TOOLCHAIN_PATH)
    expected = toolchain.get("ffmpeg", {}).get("installedBinarySHA256")
    actual = binding(FFMPEG_PATH, repository_relative=False)
    if expected != actual["sha256"]:
        raise TransitionError("pinned FFmpeg bytes drifted")
    return {
        "version": toolchain["ffmpeg"]["version"],
        "executable": actual,
    }


def source_record(program_key: str, relative_output: str) -> dict[str, Any]:
    program = PROGRAMS[program_key]
    program_root = AUDIO_ROOT / program["directory"]
    receipt_path = program_root / program["receipt"]
    receipt = load_json(receipt_path)
    if (
        receipt.get("shippingState") != SHIPPING_STATE
        or receipt.get("reproducibility") != "PASS_SECOND_COMPLETE_OFFLINE_RENDER"
        or not isinstance(receipt.get("outputs"), list)
    ):
        raise TransitionError(f"responsive receipt is not reusable: {receipt_path}")
    matches = [item for item in receipt["outputs"] if item.get("path") == relative_output]
    if len(matches) != 1:
        raise TransitionError(
            f"responsive output is not uniquely receipt-bound: {relative_output}"
        )
    output = matches[0]
    source_path = CACHE_ROOT / program["directory"] / relative_output
    actual = binding(source_path)
    if actual["bytes"] != output.get("bytes") or actual["sha256"] != output.get(
        "sha256"
    ):
        raise TransitionError(f"responsive cache bytes drifted: {source_path}")
    return {
        "programKey": program_key,
        "receipt": binding(receipt_path),
        "receiptOutputPath": relative_output,
        "audio": actual,
    }


def encode_command(source_a: Path, source_b: Path, destination: Path) -> list[str]:
    filters = (
        f"[0:a]areverse,atrim=end_sample={SOURCE_FRAMES},areverse,"
        "asetpts=N/SR/TB[a];"
        f"[1:a]atrim=end_sample={SOURCE_FRAMES},asetpts=N/SR/TB[b];"
        f"[a][b]acrossfade=ns={CROSSFADE_FRAMES}:c1=qsin:c2=qsin[out]"
    )
    return [
        str(FFMPEG_PATH),
        "-nostdin",
        "-y",
        "-v",
        "error",
        "-i",
        str(source_a),
        "-i",
        str(source_b),
        "-filter_complex_threads",
        "1",
        "-filter_complex",
        filters,
        "-map",
        "[out]",
        "-map_metadata",
        "-1",
        "-fflags",
        "+bitexact",
        "-flags:a",
        "+bitexact",
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        str(CHANNEL_COUNT),
        "-c:a",
        "aac",
        "-b:a",
        "256k",
        "-movflags",
        "+faststart",
        "-threads",
        "1",
        str(destination),
    ]


def audio_record(path: Path) -> dict[str, Any]:
    completed = subprocess.run(
        [
            str(FFMPEG_PATH),
            "-nostdin",
            "-v",
            "error",
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            str(CHANNEL_COUNT),
            "-f",
            "f32le",
            "-acodec",
            "pcm_f32le",
            "pipe:1",
        ],
        check=True,
        capture_output=True,
    )
    bytes_per_frame = 4 * CHANNEL_COUNT
    if not completed.stdout or len(completed.stdout) % bytes_per_frame:
        raise TransitionError(f"transition decode is invalid: {path}")
    duration_frames = len(completed.stdout) // bytes_per_frame
    if not NOMINAL_OUTPUT_FRAMES <= duration_frames <= NOMINAL_OUTPUT_FRAMES + 1024:
        raise TransitionError(f"transition duration drifted: {path}")
    result = binding(path)
    result.update(
        {
            "sampleRate": SAMPLE_RATE,
            "channelCount": CHANNEL_COUNT,
            "durationFrames": duration_frames,
        }
    )
    return result


def encode_twice(source_a: Path, source_b: Path, destination: Path) -> dict[str, Any]:
    if destination.exists():
        raise TransitionError(f"refusing to overwrite transition: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    WORK_ROOT.mkdir(parents=True, exist_ok=True)
    first = WORK_ROOT / f"{destination.stem}.first.m4a"
    second = WORK_ROOT / f"{destination.stem}.second.m4a"
    if first.exists() or second.exists():
        raise TransitionError(f"stale transition comparison exists: {destination.stem}")
    subprocess.run(encode_command(source_a, source_b, first), check=True)
    subprocess.run(encode_command(source_a, source_b, second), check=True)
    if first.read_bytes() != second.read_bytes():
        raise TransitionError(f"transition render is not byte-identical: {destination.stem}")
    os.replace(first, destination)
    second.unlink()
    return audio_record(destination)


def render() -> dict[str, Any]:
    validate_authorization()
    toolchain = validate_ffmpeg()
    if MANIFEST_PATH.exists():
        raise TransitionError("review transition manifest already exists")
    records = []
    for transition in TRANSITIONS:
        source_a = source_record(*transition["sourceA"])
        source_b = source_record(*transition["sourceB"])
        path_a = REPOSITORY_ROOT / source_a["audio"]["path"]
        path_b = REPOSITORY_ROOT / source_b["audio"]["path"]
        destination = ASSET_ROOT / f"{transition['transitionID']}.m4a"
        audio = encode_twice(path_a, path_b, destination)
        records.append(
            {
                "transitionID": transition["transitionID"],
                "fromWorld": transition["fromWorld"],
                "toWorld": transition["toWorld"],
                "sourceA": source_a,
                "sourceB": source_b,
                "derivation": {
                    "sourceTailFrames": SOURCE_FRAMES,
                    "destinationHeadFrames": SOURCE_FRAMES,
                    "crossfadeFrames": CROSSFADE_FRAMES,
                    "crossfadeCurve": "qsin",
                    "nominalOutputFrames": NOMINAL_OUTPUT_FRAMES,
                    "newCompositionAdded": False,
                },
                "audio": audio,
            }
        )
        print(f"Rendered review transition: {transition['transitionID']}", flush=True)
    manifest = {
        "schemaVersion": 1,
        "manifestID": "chapter-01-review-transitions-v1",
        "status": STATUS,
        "shippingState": SHIPPING_STATE,
        "milestone": "CHAPTER_01_REVIEW_READY",
        "chapterID": "first-farmers",
        "sampleRate": SAMPLE_RATE,
        "channelCount": CHANNEL_COUNT,
        "transitionCount": 3,
        "derivedWithoutNewComposition": True,
        "runtimeGenerationPermitted": False,
        "shippingUsePermitted": False,
        "authorization": binding(AUTHORIZATION_PATH),
        "generator": binding(SCRIPT_PATH),
        "toolchain": toolchain,
        "transitions": records,
    }
    write_json(MANIFEST_PATH, manifest)
    return validate()


def validate() -> dict[str, Any]:
    validate_authorization()
    toolchain = validate_ffmpeg()
    manifest = load_json(MANIFEST_PATH)
    exact = {
        "schemaVersion": 1,
        "manifestID": "chapter-01-review-transitions-v1",
        "status": STATUS,
        "shippingState": SHIPPING_STATE,
        "milestone": "CHAPTER_01_REVIEW_READY",
        "chapterID": "first-farmers",
        "sampleRate": SAMPLE_RATE,
        "channelCount": CHANNEL_COUNT,
        "transitionCount": 3,
        "derivedWithoutNewComposition": True,
        "runtimeGenerationPermitted": False,
        "shippingUsePermitted": False,
    }
    for key, expected in exact.items():
        if manifest.get(key) != expected:
            raise TransitionError(f"transition manifest drifted at {key}")
    if (
        manifest.get("authorization") != binding(AUTHORIZATION_PATH)
        or manifest.get("generator") != binding(SCRIPT_PATH)
        or manifest.get("toolchain") != toolchain
    ):
        raise TransitionError("transition authority or toolchain binding drifted")
    records = manifest.get("transitions")
    if not isinstance(records, list) or len(records) != len(TRANSITIONS):
        raise TransitionError("transition inventory drifted")
    expected_names = {f"{item['transitionID']}.m4a" for item in TRANSITIONS}
    actual_names = {item.name for item in ASSET_ROOT.glob("*.m4a")}
    if actual_names != expected_names:
        raise TransitionError("transition asset inventory drifted")
    for expected, record in zip(TRANSITIONS, records, strict=True):
        if (
            record.get("transitionID") != expected["transitionID"]
            or record.get("fromWorld") != expected["fromWorld"]
            or record.get("toWorld") != expected["toWorld"]
            or record.get("sourceA") != source_record(*expected["sourceA"])
            or record.get("sourceB") != source_record(*expected["sourceB"])
            or record.get("derivation")
            != {
                "sourceTailFrames": SOURCE_FRAMES,
                "destinationHeadFrames": SOURCE_FRAMES,
                "crossfadeFrames": CROSSFADE_FRAMES,
                "crossfadeCurve": "qsin",
                "nominalOutputFrames": NOMINAL_OUTPUT_FRAMES,
                "newCompositionAdded": False,
            }
        ):
            raise TransitionError(
                f"transition derivation drifted: {expected['transitionID']}"
            )
        path = ASSET_ROOT / f"{expected['transitionID']}.m4a"
        if record.get("audio") != audio_record(path):
            raise TransitionError(f"transition bytes drifted: {path}")
    return {
        "status": STATUS,
        "transitionCount": len(records),
        "manifest": binding(MANIFEST_PATH),
        "durationFrames": [item["audio"]["durationFrames"] for item in records],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("render", "validate"))
    args = parser.parse_args()
    try:
        result = render() if args.command == "render" else validate()
    except (TransitionError, subprocess.CalledProcessError) as error:
        print(f"Chapter 01 review transitions failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
