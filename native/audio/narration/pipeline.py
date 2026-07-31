#!/usr/bin/env python3
"""Pinned, local narration casting and stress-test production.

The module keeps MLX and model imports lazy so its contracts can be validated
without downloading weights or allocating the synthesis models.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


HERE = Path(__file__).resolve().parent
REPOSITORY_ROOT = HERE.parents[2]
DEFAULT_CONFIG = HERE / "pipeline-config.json"
UV_LOCK_PATH = HERE / "uv.lock"
PIPELINE_PATH = Path(__file__).resolve()
EDITOR_SELECTION_ROOT = HERE / "editor-selections"
REGISTRY_PATH = REPOSITORY_ROOT / "native/tooling/registries/cost-license.json"
HEX_40 = re.compile(r"^[0-9a-f]{40}$")
HEX_64 = re.compile(r"^[0-9a-f]{64}$")
CANDIDATE_ID = re.compile(r"^voice-candidate-(0[1-6])$")
EXPECTED_CANDIDATE_IDS = [f"voice-candidate-{index:02d}" for index in range(1, 7)]
EDITOR_SELECTION_STATUS = "APPROVED_BY_EDITOR_IN_CHIEF"


class PipelineError(RuntimeError):
    """A fail-closed production or contract error."""


def sha256_file(file_path: Path) -> str:
    digest = hashlib.sha256()
    with file_path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_json(value: Any) -> str:
    material = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    return sha256_text(material)


def canonical_text(file_path: Path) -> str:
    value = file_path.read_text(encoding="utf-8")
    if "\r" in value:
        raise PipelineError(f"{file_path}: CR line endings are prohibited")
    if not value.endswith("\n"):
        raise PipelineError(f"{file_path}: text must end with one newline")
    return value.strip()


def word_count(value: str) -> int:
    return len(re.findall(r"\S+", value))


def load_json(file_path: Path) -> dict[str, Any]:
    try:
        return json.loads(file_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PipelineError(f"cannot read {file_path}: {error}") from error


def confined_path(root: Path, relative: str) -> Path:
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError as error:
        raise PipelineError(f"path escapes {root}: {relative}") from error
    return candidate


def validate_model_record(label: str, record: dict[str, Any]) -> None:
    required = {
        "repository",
        "revision",
        "upstreamRepository",
        "upstreamRevision",
        "license",
        "controlFileCount",
        "controlManifestSHA256",
        "files",
    }
    if set(record) != required:
        raise PipelineError(f"models.{label}: fields drifted")
    if not HEX_40.fullmatch(record["revision"]):
        raise PipelineError(f"models.{label}.revision: expected a pinned commit")
    if not HEX_40.fullmatch(record["upstreamRevision"]):
        raise PipelineError(
            f"models.{label}.upstreamRevision: expected a pinned commit"
        )
    if record["license"] != "Apache-2.0":
        raise PipelineError(f"models.{label}: commercial license gate failed")
    if record["controlFileCount"] <= 0 or not HEX_64.fullmatch(
        record["controlManifestSHA256"]
    ):
        raise PipelineError(f"models.{label}: invalid control-file manifest")
    if not isinstance(record["files"], list) or len(record["files"]) != 2:
        raise PipelineError(f"models.{label}: exact two-weight inventory required")
    seen: set[str] = set()
    for item in record["files"]:
        if set(item) != {"path", "bytes", "sha256"}:
            raise PipelineError(f"models.{label}.files: fields drifted")
        if item["path"] in seen or item["path"].startswith("/") or ".." in Path(
            item["path"]
        ).parts:
            raise PipelineError(f"models.{label}.files: unsafe or duplicate path")
        seen.add(item["path"])
        if not isinstance(item["bytes"], int) or item["bytes"] <= 0:
            raise PipelineError(f"models.{label}.{item['path']}: invalid byte count")
        if not HEX_64.fullmatch(item["sha256"]):
            raise PipelineError(f"models.{label}.{item['path']}: invalid SHA-256")


def validate_registry(config: dict[str, Any]) -> None:
    registry = load_json(REGISTRY_PATH)
    entries = {entry["id"]: entry for entry in registry.get("entries", [])}
    expected = {
        "uv-local-narration": config["toolchain"]["uvVersion"],
        "python-local-narration": config["toolchain"]["pythonVersion"],
        "mlx-audio-local": config["toolchain"]["mlxAudioVersion"],
        "qwen3-tts-voice-design-mlx-bf16": config["models"]["voiceDesign"][
            "revision"
        ],
        "qwen3-tts-base-mlx-bf16": config["models"]["voiceClone"]["revision"],
    }
    for entry_id, version in expected.items():
        if entry_id not in entries:
            raise PipelineError(f"cost registry is missing {entry_id}")
        entry = entries[entry_id]
        if entry["version"] != version:
            raise PipelineError(f"cost registry version drifted for {entry_id}")
        if entry["incrementalCostNOK"] != 0 or entry[
            "billingCredentialRequired"
        ]:
            raise PipelineError(f"zero-cost gate failed for {entry_id}")
        if entry["commercialUse"] != "allowed":
            raise PipelineError(f"commercial-use gate failed for {entry_id}")

    for model_key, entry_id in [
        ("voiceDesign", "qwen3-tts-voice-design-mlx-bf16"),
        ("voiceClone", "qwen3-tts-base-mlx-bf16"),
    ]:
        source = entries[entry_id]["source"]
        record = config["models"][model_key]
        required_fragments = [
            record["repository"],
            record["upstreamRepository"],
            *(item["sha256"] for item in record["files"]),
        ]
        if any(fragment not in source for fragment in required_fragments):
            raise PipelineError(f"cost registry weight lineage drifted for {entry_id}")


def validate_config(config_path: Path = DEFAULT_CONFIG) -> dict[str, Any]:
    config_path = config_path.resolve()
    if config_path.parent != HERE:
        raise PipelineError("the production config must remain in the narration tree")
    config = load_json(config_path)
    if config.get("schemaVersion") != 1:
        raise PipelineError("unsupported pipeline schema")
    if config.get("status") != "NON_SHIPPING_UNTIL_EDITOR_VOICE_SELECTION":
        raise PipelineError("pipeline cannot claim shipping or voice approval")
    if config.get("language") != "English" or config.get("locale") != "en-GB":
        raise PipelineError("casting language or locale drifted")

    if set(config.get("models", {})) != {"voiceDesign", "voiceClone"}:
        raise PipelineError("voice-design and voice-clone models are both required")
    for label, record in config["models"].items():
        validate_model_record(label, record)

    text_records = config.get("texts", {})
    if set(text_records) != {"identityReference", "casting"}:
        raise PipelineError("identity and casting text records are required")
    loaded_texts: dict[str, str] = {}
    for label, record in text_records.items():
        file_path = confined_path(HERE, record["path"])
        text = canonical_text(file_path)
        if sha256_file(file_path) != record["sha256"]:
            raise PipelineError(f"texts.{label}: locked bytes changed")
        if sha256_text(text) != record["textSHA256"]:
            raise PipelineError(f"texts.{label}: synthesis text changed")
        if word_count(text) != record["wordCount"]:
            raise PipelineError(f"texts.{label}: word count drifted")
        loaded_texts[label] = text

    identity_record = text_records["identityReference"]
    identity_source = confined_path(REPOSITORY_ROOT, identity_record["source"])
    if (
        sha256_text(loaded_texts["identityReference"])
        != identity_record["sourceSegmentSHA256"]
        or loaded_texts["identityReference"]
        not in identity_source.read_text(encoding="utf-8")
    ):
        raise PipelineError("identity reference is no longer exact approved source text")

    casting_record = text_records["casting"]
    segments = loaded_texts["casting"].split("\n\n")
    sources = casting_record.get("sourceSegments", [])
    if len(segments) != len(sources) or len(sources) != 12:
        raise PipelineError("casting source-segment inventory drifted")
    for index, (segment, source) in enumerate(zip(segments, sources, strict=True)):
        if sha256_text(segment) != source["sha256"]:
            raise PipelineError(f"casting segment {index + 1}: hash drifted")
        source_path = confined_path(REPOSITORY_ROOT, source["source"])
        if segment not in source_path.read_text(encoding="utf-8"):
            raise PipelineError(
                f"casting segment {index + 1}: no longer exact approved source text"
            )
    coverage = casting_record.get("nameCoverage")
    if not isinstance(coverage, list) or [
        item.get("tradition") for item in coverage
    ] != ["Greek", "Latin", "Germanic", "Slavic"]:
        raise PipelineError("casting name coverage must remain Greek, Latin, Germanic and Slavic")
    for item in coverage:
        if set(item) != {"tradition", "segmentIndexes", "requiredTerms"}:
            raise PipelineError(f"{item.get('tradition')}: name-coverage fields drifted")
        indexes = item["segmentIndexes"]
        terms = item["requiredTerms"]
        if (
            not isinstance(indexes, list)
            or not indexes
            or any(
                not isinstance(index, int) or not 1 <= index <= len(segments)
                for index in indexes
            )
            or not isinstance(terms, list)
            or len(terms) < 4
            or any(not isinstance(term, str) or not term.strip() for term in terms)
        ):
            raise PipelineError(f"{item['tradition']}: invalid name-coverage contract")
        covered_text = "\n\n".join(segments[index - 1] for index in indexes)
        missing = [term for term in terms if term not in covered_text]
        if missing:
            raise PipelineError(
                f"{item['tradition']}: casting passage lost required terms: {', '.join(missing)}"
            )

    candidates = config.get("candidates")
    if not isinstance(candidates, list) or len(candidates) != 6:
        raise PipelineError("exactly six anonymous candidates are required")
    candidate_ids = [candidate.get("id") for candidate in candidates]
    if candidate_ids != EXPECTED_CANDIDATE_IDS or any(
        not isinstance(value, str) or not CANDIDATE_ID.fullmatch(value)
        for value in candidate_ids
    ):
        raise PipelineError("candidate IDs must remain ordered anonymous 01 through 06")
    for candidate in candidates:
        if set(candidate) != {
            "id",
            "referenceSeed",
            "castingSeed",
            "stressSeed",
            "instruction",
        }:
            raise PipelineError(f"{candidate.get('id')}: candidate fields drifted")
        seeds = [
            candidate["referenceSeed"],
            candidate["castingSeed"],
            candidate["stressSeed"],
        ]
        if any(not isinstance(seed, int) or seed <= 0 for seed in seeds):
            raise PipelineError(f"{candidate['id']}: invalid deterministic seed")
        if not isinstance(candidate["instruction"], str) or not candidate[
            "instruction"
        ].strip():
            raise PipelineError(f"{candidate['id']}: missing voice instruction")
        lowered = candidate["instruction"].lower()
        if any(term in lowered for term in ["voice of", "sound like", "imitate"]):
            raise PipelineError(f"{candidate['id']}: identity imitation is prohibited")

    generation = config.get("generation", {})
    if not (0 < generation.get("temperature", 0) <= 1):
        raise PipelineError("generation temperature is invalid")
    if generation.get("maxTokens") != 8192:
        raise PipelineError("generation token ceiling drifted")
    if generation.get("candidatePeakDBFS") != -3.0:
        raise PipelineError("candidate comparison gain drifted")
    if config.get("masterFormat") != {
        "sampleRate": 48000,
        "bitDepth": 24,
        "channels": 1,
        "codec": "pcm_s24le",
    }:
        raise PipelineError("narration master format drifted")
    stress = config.get("stressTest", {})
    if stress != {
        "targetMinutes": 20,
        "minimumMinutes": 18,
        "maximumMinutes": 22,
        "estimatedWordsPerMinute": 145,
        "maxTokens": 20000,
        "singleGenerationRequired": True,
    }:
        raise PipelineError("twenty-minute stress gate drifted")

    validate_registry(config)
    config["_validatedConfigPath"] = str(config_path)
    return config


def executable_binding(executable: str, version_arguments: list[str]) -> dict[str, Any]:
    located = shutil.which(executable)
    if not located:
        raise PipelineError(f"{executable} is required")
    path = Path(located).resolve()
    first_line = subprocess.run(
        [str(path), *version_arguments],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()[0]
    return {
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        "versionFirstLine": first_line,
    }


def verify_runtime(config: dict[str, Any]) -> dict[str, Any]:
    expected_python = config["toolchain"]["pythonVersion"]
    if platform.python_version() != expected_python:
        raise PipelineError(
            f"Python {expected_python} required; found {platform.python_version()}"
        )
    try:
        package_version = importlib.metadata.version("mlx-audio")
    except importlib.metadata.PackageNotFoundError as error:
        raise PipelineError("mlx-audio is not installed in this environment") from error
    if package_version != config["toolchain"]["mlxAudioVersion"]:
        raise PipelineError(
            f"mlx-audio {config['toolchain']['mlxAudioVersion']} required; "
            f"found {package_version}"
        )
    uv = executable_binding("uv", ["--version"])
    expected_uv = f"uv {config['toolchain']['uvVersion']}"
    if not uv["versionFirstLine"].startswith(expected_uv):
        raise PipelineError(
            f"{expected_uv} required; found {uv['versionFirstLine']}"
        )
    ffmpeg = executable_binding("ffmpeg", ["-version"])
    ffprobe = executable_binding("ffprobe", ["-version"])
    expected_ffmpeg = f"ffmpeg version {config['toolchain']['ffmpegVersion']}"
    if not ffmpeg["versionFirstLine"].startswith(expected_ffmpeg):
        raise PipelineError(
            f"{expected_ffmpeg} required; found {ffmpeg['versionFirstLine']}"
        )
    expected_ffprobe = f"ffprobe version {config['toolchain']['ffmpegVersion']}"
    if not ffprobe["versionFirstLine"].startswith(expected_ffprobe):
        raise PipelineError(
            f"{expected_ffprobe} required; found {ffprobe['versionFirstLine']}"
        )
    return {
        "pythonVersion": platform.python_version(),
        "mlxAudioVersion": package_version,
        "uv": uv,
        "ffmpeg": ffmpeg,
        "ffprobe": ffprobe,
    }


def file_binding(file_path: Path) -> dict[str, Any]:
    if not file_path.is_file():
        raise PipelineError(f"pipeline artifact is missing: {file_path}")
    return {
        "bytes": file_path.stat().st_size,
        "sha256": sha256_file(file_path),
    }


def pipeline_binding(
    config: dict[str, Any], runtime: dict[str, Any] | None = None
) -> dict[str, Any]:
    config_path = Path(config.get("_validatedConfigPath", DEFAULT_CONFIG)).resolve()
    if config_path.parent != HERE:
        raise PipelineError("validated config path escaped narration tree")
    runtime = runtime or verify_runtime(config)
    return {
        "schemaVersion": 1,
        "pipelinePy": file_binding(PIPELINE_PATH),
        "pipelineConfig": file_binding(config_path),
        "uvLock": file_binding(UV_LOCK_PATH),
        "runtime": runtime,
    }


def candidate_contract(config: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "candidateID": candidate["id"],
            "referenceSeed": candidate["referenceSeed"],
            "castingSeed": candidate["castingSeed"],
            "stressSeed": candidate["stressSeed"],
            "instructionSHA256": sha256_text(candidate["instruction"]),
        }
        for candidate in config["candidates"]
    ]


def verify_model_snapshot(
    record: dict[str, Any], *, offline: bool
) -> tuple[Path, list[dict[str, Any]]]:
    from huggingface_hub import snapshot_download

    try:
        local_dir = Path(
            snapshot_download(
                repo_id=record["repository"],
                revision=record["revision"],
                local_files_only=offline,
            )
        ).resolve()
    except Exception as error:
        mode = "offline cache" if offline else "pinned download"
        raise PipelineError(
            f"{record['repository']} unavailable from {mode}: {error}"
        ) from error

    receipts: list[dict[str, Any]] = []
    weight_paths = {item["path"] for item in record["files"]}
    cache_repository_root = local_dir.parent.parent.resolve()
    for expected in record["files"]:
        relative_path = Path(expected["path"])
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise PipelineError(f"unsafe model path: {expected['path']}")
        file_path = local_dir / relative_path
        resolved_file = file_path.resolve()
        try:
            resolved_file.relative_to(cache_repository_root)
        except ValueError as error:
            raise PipelineError(
                f"model file resolves outside its repository cache: {expected['path']}"
            ) from error
        if not file_path.is_file():
            raise PipelineError(f"model file missing: {expected['path']}")
        actual_bytes = file_path.stat().st_size
        actual_hash = sha256_file(file_path)
        if actual_bytes != expected["bytes"] or actual_hash != expected["sha256"]:
            raise PipelineError(
                f"model integrity failed: {record['repository']}/{expected['path']}"
            )
        receipts.append(
            {
                "path": expected["path"],
                "bytes": actual_bytes,
                "sha256": actual_hash,
            }
        )
    control_records: list[tuple[str, int, str]] = []
    for candidate_path in sorted(local_dir.rglob("*")):
        if not candidate_path.is_file():
            continue
        relative = candidate_path.relative_to(local_dir).as_posix()
        if relative in weight_paths:
            continue
        resolved_control = candidate_path.resolve()
        try:
            resolved_control.relative_to(cache_repository_root)
        except ValueError as error:
            raise PipelineError(
                f"model control file resolves outside its repository cache: {relative}"
            ) from error
        control_records.append(
            (relative, candidate_path.stat().st_size, sha256_file(candidate_path))
        )
    control_material = "".join(
        f"{relative}\t{byte_count}\t{digest}\n"
        for relative, byte_count, digest in control_records
    )
    if (
        len(control_records) != record["controlFileCount"]
        or sha256_text(control_material) != record["controlManifestSHA256"]
    ):
        raise PipelineError(f"model control-file integrity failed: {record['repository']}")
    return local_dir, receipts


def generation_kwargs(
    config: dict[str, Any], *, max_tokens: int | None = None
) -> dict[str, Any]:
    settings = config["generation"]
    return {
        "temperature": settings["temperature"],
        "max_tokens": max_tokens or settings["maxTokens"],
        "top_k": settings["topK"],
        "top_p": settings["topP"],
        "repetition_penalty": settings["repetitionPenalty"],
        "verbose": False,
        "stream": False,
    }


def set_generation_seed(seed: int) -> None:
    import mlx.core as mx
    import numpy as np

    mx.random.seed(seed)
    np.random.seed(seed % (2**32))


def one_generation_audio(results: Iterable[Any]) -> tuple[Any, int]:
    import numpy as np

    materialized = list(results)
    if len(materialized) != 1:
        raise PipelineError(f"expected one non-streaming result; got {len(materialized)}")
    result = materialized[0]
    audio = np.asarray(result.audio, dtype=np.float32).reshape(-1)
    if audio.size == 0 or not np.all(np.isfinite(audio)):
        raise PipelineError("synthesis returned empty or non-finite audio")
    peak = float(np.max(np.abs(audio)))
    if peak < 1e-5:
        raise PipelineError("synthesis returned silence")
    return audio, int(result.sample_rate)


def normalize_candidate(audio: Any, target_dbfs: float) -> tuple[Any, float]:
    import numpy as np

    peak = float(np.max(np.abs(audio)))
    target = 10 ** (target_dbfs / 20)
    gain = target / peak
    normalized = np.asarray(audio * gain, dtype=np.float32)
    if float(np.max(np.abs(normalized))) > 1.0:
        raise PipelineError("candidate normalization would clip")
    return normalized, gain


def write_float_wav(file_path: Path, sample_rate: int, audio: Any) -> None:
    from scipy.io import wavfile

    wavfile.write(file_path, sample_rate, audio)


def convert_to_master(
    source_path: Path, destination_path: Path, config: dict[str, Any]
) -> dict[str, Any]:
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    ffprobe = shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise PipelineError("ffmpeg and ffprobe are required")
    master = config["masterFormat"]
    subprocess.run(
        [
            ffmpeg,
            "-nostdin",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(source_path),
            "-af",
            f"aresample={master['sampleRate']}:dither_method=triangular_hp",
            "-ar",
            str(master["sampleRate"]),
            "-ac",
            str(master["channels"]),
            "-c:a",
            master["codec"],
            str(destination_path),
        ],
        check=True,
    )
    probe = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "stream=codec_name,sample_rate,channels,bits_per_raw_sample,duration",
            "-of",
            "json",
            str(destination_path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    streams = json.loads(probe.stdout).get("streams", [])
    if len(streams) != 1:
        raise PipelineError(f"{destination_path}: expected one audio stream")
    stream = streams[0]
    if (
        stream.get("codec_name") != master["codec"]
        or int(stream.get("sample_rate", 0)) != master["sampleRate"]
        or int(stream.get("channels", 0)) != master["channels"]
        or int(stream.get("bits_per_raw_sample", 0)) != master["bitDepth"]
    ):
        raise PipelineError(f"{destination_path}: master format verification failed")
    return {
        "path": str(destination_path),
        "sha256": sha256_file(destination_path),
        "bytes": destination_path.stat().st_size,
        "durationSeconds": round(float(stream["duration"]), 6),
        "sampleRate": master["sampleRate"],
        "bitDepth": master["bitDepth"],
        "channels": master["channels"],
        "codec": master["codec"],
    }


def prepare_output_root(output_root: Path) -> Path:
    output_root = output_root.resolve()
    if output_root == REPOSITORY_ROOT or output_root == Path.home().resolve():
        raise PipelineError("refusing a broad output root")
    if output_root.exists() and any(output_root.iterdir()):
        raise PipelineError(f"output directory must be absent or empty: {output_root}")
    output_root.mkdir(parents=True, exist_ok=True)
    return output_root


def candidate_by_id(config: dict[str, Any], candidate_id: str) -> dict[str, Any]:
    match = next(
        (candidate for candidate in config["candidates"] if candidate["id"] == candidate_id),
        None,
    )
    if match is None:
        raise PipelineError(f"unknown candidate: {candidate_id}")
    return match


def model_receipt(record: dict[str, Any], files: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "repository": record["repository"],
        "revision": record["revision"],
        "upstreamRepository": record["upstreamRepository"],
        "upstreamRevision": record["upstreamRevision"],
        "license": record["license"],
        "controlFileCount": record["controlFileCount"],
        "controlManifestSHA256": record["controlManifestSHA256"],
        "verifiedFiles": files,
    }


def timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def write_receipt(file_path: Path, value: dict[str, Any]) -> None:
    file_path.write_text(
        json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def load_synthesis_models(config: dict[str, Any], *, offline: bool):
    from mlx_audio.tts.utils import load_model

    design_dir, design_files = verify_model_snapshot(
        config["models"]["voiceDesign"], offline=offline
    )
    clone_dir, clone_files = verify_model_snapshot(
        config["models"]["voiceClone"], offline=offline
    )
    design_model = load_model(str(design_dir))
    clone_model = load_model(str(clone_dir))
    receipt = {
        "voiceDesign": model_receipt(
            config["models"]["voiceDesign"], design_files
        ),
        "voiceClone": model_receipt(config["models"]["voiceClone"], clone_files),
    }
    return design_model, clone_model, receipt


def run_preflight(config: dict[str, Any], *, offline: bool) -> dict[str, Any]:
    runtime = verify_runtime(config)
    models: dict[str, Any] = {}
    for label in ["voiceDesign", "voiceClone"]:
        _, files = verify_model_snapshot(config["models"][label], offline=offline)
        models[label] = model_receipt(config["models"][label], files)
    contract = candidate_contract(config)
    return {
        "schemaVersion": 1,
        "status": "PREFLIGHT_VALID_NO_SYNTHESIS",
        "offline": offline,
        "candidateCount": 6,
        "candidateContract": contract,
        "candidateContractSHA256": sha256_json(contract),
        "pipelineBinding": pipeline_binding(config, runtime),
        "models": models,
        "claimsExcluded": [
            "candidate generation",
            "editor voice selection",
            "artistic approval",
            "shipping approval",
        ],
    }


def synthesize_reference(
    design_model: Any,
    candidate: dict[str, Any],
    identity_text: str,
    config: dict[str, Any],
) -> tuple[Any, int]:
    set_generation_seed(candidate["referenceSeed"])
    return one_generation_audio(
        design_model.generate_voice_design(
            text=identity_text,
            instruct=candidate["instruction"],
            language=config["language"],
            **generation_kwargs(config),
        )
    )


def synthesize_clone(
    clone_model: Any,
    *,
    text: str,
    reference_path: Path,
    reference_text: str,
    seed: int,
    config: dict[str, Any],
    max_tokens: int | None = None,
) -> tuple[Any, int]:
    set_generation_seed(seed)
    return one_generation_audio(
        clone_model.generate(
            text=text,
            ref_audio=str(reference_path),
            ref_text=reference_text,
            lang_code=config["language"],
            **generation_kwargs(config, max_tokens=max_tokens),
        )
    )


def run_probe(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    runtime = verify_runtime(config)
    binding = pipeline_binding(config, runtime)
    output_root = prepare_output_root(args.output)
    candidate = candidate_by_id(config, args.candidate)
    identity_text = canonical_text(
        confined_path(HERE, config["texts"]["identityReference"]["path"])
    )
    probe_text = canonical_text(
        confined_path(HERE, config["texts"]["casting"]["path"])
    ).split(". ", 2)[0] + "."
    design_model, clone_model, models = load_synthesis_models(
        config, offline=args.offline
    )
    with tempfile.TemporaryDirectory(prefix="long-west-narration-probe-") as temporary:
        temporary_root = Path(temporary)
        reference_audio, reference_rate = synthesize_reference(
            design_model, candidate, identity_text, config
        )
        reference_audio, reference_gain = normalize_candidate(
            reference_audio, config["generation"]["candidatePeakDBFS"]
        )
        reference_raw = temporary_root / "reference-f32.wav"
        write_float_wav(reference_raw, reference_rate, reference_audio)
        reference_path = output_root / "technical-reference.wav"
        reference_receipt = convert_to_master(reference_raw, reference_path, config)

        clone_audio, clone_rate = synthesize_clone(
            clone_model,
            text=probe_text,
            reference_path=reference_path,
            reference_text=identity_text,
            seed=candidate["castingSeed"],
            config=config,
        )
        clone_audio, clone_gain = normalize_candidate(
            clone_audio, config["generation"]["candidatePeakDBFS"]
        )
        clone_raw = temporary_root / "clone-f32.wav"
        write_float_wav(clone_raw, clone_rate, clone_audio)
        clone_path = output_root / "technical-clone.wav"
        clone_receipt = convert_to_master(clone_raw, clone_path, config)

    receipt = {
        "schemaVersion": 2,
        "status": "TECHNICAL_ONLY_NOT_ARTISTICALLY_APPROVED",
        "createdAt": timestamp(),
        "candidateID": candidate["id"],
        "instructionSHA256": sha256_text(candidate["instruction"]),
        "pipelineBinding": binding,
        "identityTextSHA256": sha256_text(identity_text),
        "probeText": probe_text,
        "probeTextSHA256": sha256_text(probe_text),
        "models": models,
        "generation": config["generation"],
        "referencePeakGain": reference_gain,
        "clonePeakGain": clone_gain,
        "reference": reference_receipt,
        "clone": clone_receipt,
        "claimsExcluded": [
            "editor voice selection",
            "word-accuracy approval",
            "pronunciation approval",
            "artistic approval",
            "shipping approval"
        ],
    }
    write_receipt(output_root / "technical-probe.receipt.json", receipt)
    return receipt


def run_cast(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    runtime = verify_runtime(config)
    binding = pipeline_binding(config, runtime)
    output_root = prepare_output_root(args.output)
    candidates = config["candidates"]
    if [candidate["id"] for candidate in candidates] != EXPECTED_CANDIDATE_IDS:
        raise PipelineError("production cast requires the exact complete six-candidate set")
    identity_text = canonical_text(
        confined_path(HERE, config["texts"]["identityReference"]["path"])
    )
    casting_text = canonical_text(
        confined_path(HERE, config["texts"]["casting"]["path"])
    )
    design_model, clone_model, models = load_synthesis_models(
        config, offline=args.offline
    )
    records: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="long-west-narration-cast-") as temporary:
        temporary_root = Path(temporary)
        for candidate in candidates:
            reference_audio, reference_rate = synthesize_reference(
                design_model, candidate, identity_text, config
            )
            reference_audio, reference_gain = normalize_candidate(
                reference_audio, config["generation"]["candidatePeakDBFS"]
            )
            reference_raw = temporary_root / f"{candidate['id']}-reference-f32.wav"
            write_float_wav(reference_raw, reference_rate, reference_audio)
            reference_path = (
                output_root / "references" / f"{candidate['id']}-reference.wav"
            )
            reference_receipt = convert_to_master(reference_raw, reference_path, config)

            casting_audio, casting_rate = synthesize_clone(
                clone_model,
                text=casting_text,
                reference_path=reference_path,
                reference_text=identity_text,
                seed=candidate["castingSeed"],
                config=config,
            )
            casting_audio, casting_gain = normalize_candidate(
                casting_audio, config["generation"]["candidatePeakDBFS"]
            )
            casting_raw = temporary_root / f"{candidate['id']}-casting-f32.wav"
            write_float_wav(casting_raw, casting_rate, casting_audio)
            casting_path = output_root / "candidates" / f"{candidate['id']}.wav"
            casting_receipt = convert_to_master(casting_raw, casting_path, config)
            records.append(
                {
                    "candidateID": candidate["id"],
                    "instructionSHA256": sha256_text(candidate["instruction"]),
                    "referenceSeed": candidate["referenceSeed"],
                    "castingSeed": candidate["castingSeed"],
                    "referencePeakGain": reference_gain,
                    "castingPeakGain": casting_gain,
                    "reference": reference_receipt,
                    "casting": casting_receipt,
                }
            )

    receipt = {
        "schemaVersion": 2,
        "status": "AWAITING_EDITOR_SELECTION_AND_ARTISTIC_AUDIT",
        "createdAt": timestamp(),
        "language": config["language"],
        "locale": config["locale"],
        "identityTextSHA256": sha256_text(identity_text),
        "castingTextSHA256": sha256_text(casting_text),
        "castingWordCount": word_count(casting_text),
        "completeCandidateSet": True,
        "candidateCount": 6,
        "candidateIDs": EXPECTED_CANDIDATE_IDS,
        "candidateContract": candidate_contract(config),
        "candidateContractSHA256": sha256_json(candidate_contract(config)),
        "pipelineBinding": binding,
        "models": models,
        "generation": config["generation"],
        "masterFormat": config["masterFormat"],
        "candidateRecords": records,
        "claimsExcluded": [
            "editor voice selection",
            "word-accuracy approval",
            "pronunciation approval",
            "artistic approval",
            "shipping approval"
        ],
    }
    write_receipt(output_root / "candidate-set.receipt.json", receipt)
    return receipt


def validate_stress_text(text: str, config: dict[str, Any]) -> dict[str, Any]:
    stress = config["stressTest"]
    words = word_count(text)
    estimated_minutes = words / stress["estimatedWordsPerMinute"]
    if not stress["minimumMinutes"] <= estimated_minutes <= stress["maximumMinutes"]:
        raise PipelineError(
            f"stress text estimates to {estimated_minutes:.2f} minutes; "
            f"required range is {stress['minimumMinutes']}–{stress['maximumMinutes']}"
        )
    return {
        "sha256": sha256_text(text),
        "wordCount": words,
        "estimatedMinutes": round(estimated_minutes, 3),
        "singleGenerationRequired": True,
        "maxTokens": stress["maxTokens"],
    }


def model_binding_matches_config(
    receipt: dict[str, Any], record: dict[str, Any]
) -> bool:
    verified_files = receipt.get("verifiedFiles", [])
    return (
        receipt.get("repository") == record["repository"]
        and receipt.get("revision") == record["revision"]
        and receipt.get("upstreamRepository") == record["upstreamRepository"]
        and receipt.get("upstreamRevision") == record["upstreamRevision"]
        and receipt.get("license") == record["license"]
        and receipt.get("controlFileCount") == record["controlFileCount"]
        and receipt.get("controlManifestSHA256")
        == record["controlManifestSHA256"]
        and verified_files == record["files"]
    )


def validate_candidate_set(
    candidate_set: Path,
    config: dict[str, Any],
    binding: dict[str, Any] | None = None,
) -> dict[str, Any]:
    candidate_set = candidate_set.resolve()
    if not candidate_set.is_dir():
        raise PipelineError("candidate set directory is missing")
    receipt_path = (candidate_set / "candidate-set.receipt.json").resolve()
    try:
        receipt_path.relative_to(candidate_set)
    except ValueError as error:
        raise PipelineError("candidate-set receipt escaped its directory") from error
    receipt = load_json(receipt_path)
    if (
        receipt.get("schemaVersion") != 2
        or receipt.get("status")
        != "AWAITING_EDITOR_SELECTION_AND_ARTISTIC_AUDIT"
    ):
        raise PipelineError("candidate-set receipt status is invalid")
    expected_contract = candidate_contract(config)
    expected_binding = binding or pipeline_binding(config)
    records = receipt.get("candidateRecords")
    record_ids = (
        [record.get("candidateID") for record in records]
        if isinstance(records, list)
        else []
    )
    if (
        receipt.get("completeCandidateSet") is not True
        or receipt.get("candidateCount") != 6
        or receipt.get("candidateIDs") != EXPECTED_CANDIDATE_IDS
        or record_ids != EXPECTED_CANDIDATE_IDS
        or receipt.get("language") != config["language"]
        or receipt.get("locale") != config["locale"]
        or receipt.get("candidateContract") != expected_contract
        or receipt.get("candidateContractSHA256") != sha256_json(expected_contract)
        or receipt.get("pipelineBinding") != expected_binding
        or receipt.get("identityTextSHA256")
        != sha256_text(
            canonical_text(
                confined_path(
                    HERE, config["texts"]["identityReference"]["path"]
                )
            )
        )
        or receipt.get("castingTextSHA256")
        != config["texts"]["casting"]["textSHA256"]
        or receipt.get("castingWordCount")
        != config["texts"]["casting"]["wordCount"]
        or receipt.get("generation") != config["generation"]
        or receipt.get("masterFormat") != config["masterFormat"]
        or not all(
            model_binding_matches_config(
                receipt.get("models", {}).get(label, {}), config["models"][label]
            )
            for label in ["voiceDesign", "voiceClone"]
        )
    ):
        raise PipelineError("candidate set no longer matches the frozen pipeline")
    records_by_id: dict[str, dict[str, Any]] = {}
    for expected, record in zip(config["candidates"], records, strict=True):
        candidate_id = expected["id"]
        if (
            record.get("instructionSHA256")
            != sha256_text(expected["instruction"])
            or record.get("referenceSeed") != expected["referenceSeed"]
            or record.get("castingSeed") != expected["castingSeed"]
        ):
            raise PipelineError(f"candidate contract drifted: {candidate_id}")
        for label in ["reference", "casting"]:
            file_record = record.get(label)
            if not isinstance(file_record, dict):
                raise PipelineError(f"candidate {label} receipt missing: {candidate_id}")
            try:
                audio_path = Path(file_record["path"]).resolve()
                expected_hash = file_record["sha256"]
                expected_bytes = file_record["bytes"]
            except (KeyError, TypeError) as error:
                raise PipelineError(
                    f"candidate {label} receipt malformed: {candidate_id}"
                ) from error
            try:
                audio_path.relative_to(candidate_set)
            except ValueError as error:
                raise PipelineError(
                    f"candidate {label} escaped its set: {candidate_id}"
                ) from error
            if (
                not audio_path.is_file()
                or audio_path.stat().st_size != expected_bytes
                or sha256_file(audio_path) != expected_hash
            ):
                raise PipelineError(
                    f"candidate {label} integrity failed: {candidate_id}"
                )
            if label == "reference":
                record["_verifiedReferencePath"] = str(audio_path)
        records_by_id[candidate_id] = record
    return {
        "root": candidate_set,
        "receipt": receipt,
        "receiptPath": receipt_path,
        "receiptSHA256": sha256_file(receipt_path),
        "receiptBytes": receipt_path.stat().st_size,
        "recordsByID": records_by_id,
    }


def validate_editor_selection_record(
    selection_path: Path,
    candidate_set: dict[str, Any],
) -> dict[str, Any]:
    selection_path = selection_path.resolve()
    try:
        selection_path.relative_to(EDITOR_SELECTION_ROOT.resolve())
    except ValueError as error:
        raise PipelineError(
            "editor-selection record must remain in the versioned editor-selections directory"
        ) from error
    record = load_json(selection_path)
    required_fields = {
        "schemaVersion",
        "status",
        "decisionType",
        "approvedBy",
        "decidedAt",
        "decisionReference",
        "candidateSetReceiptSHA256",
        "candidateSetReceiptBytes",
        "selectedCandidateIDs",
    }
    if set(record) != required_fields:
        raise PipelineError("editor-selection record fields drifted")
    if record.get("status") != EDITOR_SELECTION_STATUS:
        raise PipelineError("editor-selection record has no editor approval")
    if (
        record.get("schemaVersion") != 1
        or record.get("decisionType") != "NARRATION_STRESS_FINALISTS"
        or record.get("approvedBy") != "editor-in-chief"
        or record.get("candidateSetReceiptSHA256")
        != candidate_set["receiptSHA256"]
        or record.get("candidateSetReceiptBytes")
        != candidate_set["receiptBytes"]
    ):
        raise PipelineError("editor-selection record does not bind this candidate set")
    selected = record.get("selectedCandidateIDs")
    if (
        not isinstance(selected, list)
        or len(selected) != 2
        or len(set(selected)) != 2
        or any(candidate_id not in EXPECTED_CANDIDATE_IDS for candidate_id in selected)
    ):
        raise PipelineError("editor selection must contain exactly two candidates")
    if not isinstance(record.get("decisionReference"), str) or not record[
        "decisionReference"
    ].strip():
        raise PipelineError("editor decision reference is required")
    try:
        decided_at = datetime.fromisoformat(record["decidedAt"].replace("Z", "+00:00"))
    except (AttributeError, ValueError) as error:
        raise PipelineError("editor decision timestamp is invalid") from error
    if decided_at.tzinfo is None:
        raise PipelineError("editor decision timestamp must include a timezone")
    return {
        "record": record,
        "path": selection_path,
        "sha256": sha256_file(selection_path),
        "bytes": selection_path.stat().st_size,
        "selectedCandidateIDs": selected,
    }


def require_stress_duration(duration_seconds: float, config: dict[str, Any]) -> None:
    minimum = config["stressTest"]["minimumMinutes"] * 60
    maximum = config["stressTest"]["maximumMinutes"] * 60
    if not minimum <= duration_seconds <= maximum:
        raise PipelineError(
            f"uninterrupted stress output is {duration_seconds / 60:.2f} minutes; "
            f"required range is {minimum / 60:.0f}–{maximum / 60:.0f}"
        )


def run_stress(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    runtime = verify_runtime(config)
    binding = pipeline_binding(config, runtime)
    candidate_set = validate_candidate_set(
        args.candidate_set.resolve(), config, binding
    )
    selection = validate_editor_selection_record(
        args.selection_record, candidate_set
    )
    stress_path = args.text.resolve()
    stress_text = canonical_text(stress_path)
    stress_plan = validate_stress_text(stress_text, config)
    identity_text = canonical_text(
        confined_path(HERE, config["texts"]["identityReference"]["path"])
    )
    if stress_path in {
        confined_path(HERE, config["texts"]["identityReference"]["path"]),
        confined_path(HERE, config["texts"]["casting"]["path"]),
    }:
        raise PipelineError("casting text cannot masquerade as the long stress script")

    from mlx_audio.tts.utils import load_model
    import mlx.core as mx

    clone_dir, clone_files = verify_model_snapshot(
        config["models"]["voiceClone"], offline=args.offline
    )
    clone_model = load_model(str(clone_dir))
    output_root = prepare_output_root(args.output)
    records: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="long-west-narration-stress-") as temporary:
        temporary_root = Path(temporary)
        for candidate_id in selection["selectedCandidateIDs"]:
            candidate = candidate_by_id(config, candidate_id)
            candidate_record = candidate_set["recordsByID"][candidate_id]
            reference_path = Path(
                candidate_record["_verifiedReferencePath"]
            ).resolve()
            audio, sample_rate = synthesize_clone(
                clone_model,
                text=stress_text,
                reference_path=reference_path,
                reference_text=identity_text,
                seed=candidate["stressSeed"],
                config=config,
                max_tokens=config["stressTest"]["maxTokens"],
            )
            native_duration = len(audio) / sample_rate
            require_stress_duration(native_duration, config)
            audio, gain = normalize_candidate(
                audio, config["generation"]["candidatePeakDBFS"]
            )
            raw_path = temporary_root / f"{candidate_id}-stress-f32.wav"
            write_float_wav(raw_path, sample_rate, audio)
            master_path = output_root / f"{candidate_id}-stress.wav"
            master_receipt = convert_to_master(raw_path, master_path, config)
            require_stress_duration(master_receipt["durationSeconds"], config)
            records.append(
                {
                    "candidateID": candidate_id,
                    "instructionSHA256": candidate_record["instructionSHA256"],
                    "referenceSHA256": candidate_record["reference"]["sha256"],
                    "stressSeed": candidate["stressSeed"],
                    "generationCount": 1,
                    "editCount": 0,
                    "uninterruptedSingleGeneration": True,
                    "nativeDurationSeconds": round(native_duration, 6),
                    "peakGain": gain,
                    "master": master_receipt,
                }
            )
            mx.clear_cache()

    receipt = {
        "schemaVersion": 2,
        "status": "AWAITING_WORD_PRONUNCIATION_CADENCE_AND_ARTISTIC_AUDIT",
        "createdAt": timestamp(),
        "language": config["language"],
        "pipelineBinding": binding,
        "candidateSetReceipt": {
            "sha256": candidate_set["receiptSHA256"],
            "bytes": candidate_set["receiptBytes"],
            "completeCandidateCount": 6,
        },
        "editorSelectionRecord": {
            "sha256": selection["sha256"],
            "bytes": selection["bytes"],
            "selectedCandidateIDs": selection["selectedCandidateIDs"],
        },
        "stressTextPath": str(stress_path),
        "stressTextFileSHA256": sha256_file(stress_path),
        "stressTextSHA256": stress_plan["sha256"],
        "stressWordCount": stress_plan["wordCount"],
        "estimatedMinutes": stress_plan["estimatedMinutes"],
        "singleGenerationPerFinalist": True,
        "stressMaxTokens": config["stressTest"]["maxTokens"],
        "voiceCloneModel": model_receipt(
            config["models"]["voiceClone"], clone_files
        ),
        "records": records,
        "claimsExcluded": [
            "final editor voice selection",
            "word-accuracy approval",
            "pronunciation approval",
            "artistic approval",
            "shipping approval"
        ],
    }
    write_receipt(output_root / "stress-set.receipt.json", receipt)
    return receipt


def plan(config: dict[str, Any], mode: str) -> dict[str, Any]:
    base = {
        "schemaVersion": 1,
        "mode": mode,
        "status": "PLAN_ONLY_NO_SYNTHESIS",
        "language": config["language"],
        "models": {
            label: {
                "repository": record["repository"],
                "revision": record["revision"],
                "weightSHA256": [item["sha256"] for item in record["files"]],
            }
            for label, record in config["models"].items()
        },
        "masterFormat": config["masterFormat"],
    }
    if mode == "cast":
        base.update(
            {
                "candidateIDs": [item["id"] for item in config["candidates"]],
                "sharedCastingTextSHA256": config["texts"]["casting"]["sha256"],
                "synthesisTextSHA256": config["texts"]["casting"]["textSHA256"],
                "sharedCastingWordCount": config["texts"]["casting"]["wordCount"],
                "selfGeneratedReferenceOnly": True,
            }
        )
    else:
        base.update(
            {
                "requiredCompleteCandidateSetCount": 6,
                "requiredEditorSelectedFinalistCount": 2,
                "minimumMinutes": config["stressTest"]["minimumMinutes"],
                "maximumMinutes": config["stressTest"]["maximumMinutes"],
                "sameLockedTextRequired": True,
                "singleUninterruptedGenerationPerFinalist": True,
                "stressMaxTokens": config["stressTest"]["maxTokens"],
            }
        )
    return base


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Produce pinned local narration candidates and stress tests."
    )
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("validate", help="validate contracts without model loading")
    preflight_parser = subparsers.add_parser(
        "preflight", help="verify pinned runtime and cached models without synthesis"
    )
    preflight_parser.add_argument("--offline", action="store_true")
    plan_parser = subparsers.add_parser("plan", help="print a no-synthesis plan")
    plan_parser.add_argument("mode", choices=["cast", "stress"])

    probe_parser = subparsers.add_parser(
        "probe", help="run one short VoiceDesign-to-Base technical probe"
    )
    probe_parser.add_argument("--candidate", default="voice-candidate-01")
    probe_parser.add_argument("--output", type=Path, required=True)
    probe_parser.add_argument("--offline", action="store_true")

    cast_parser = subparsers.add_parser(
        "cast", help="produce six anonymous candidates from one locked passage"
    )
    cast_parser.add_argument("--output", type=Path, required=True)
    cast_parser.add_argument("--offline", action="store_true")

    stress_parser = subparsers.add_parser(
        "stress", help="produce two long tests using selected candidate references"
    )
    stress_parser.add_argument("--candidate-set", type=Path, required=True)
    stress_parser.add_argument("--selection-record", type=Path, required=True)
    stress_parser.add_argument("--text", type=Path, required=True)
    stress_parser.add_argument("--output", type=Path, required=True)
    stress_parser.add_argument("--offline", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        config = validate_config(args.config)
        if args.command == "validate":
            result = {
                "status": "VALID",
                "candidateCount": len(config["candidates"]),
                "castingTextSHA256": config["texts"]["casting"]["sha256"],
                "castingNameTraditions": [
                    item["tradition"]
                    for item in config["texts"]["casting"]["nameCoverage"]
                ],
            }
        elif args.command == "preflight":
            result = run_preflight(config, offline=args.offline)
        elif args.command == "plan":
            result = plan(config, args.mode)
        elif args.command == "probe":
            result = run_probe(args, config)
        elif args.command == "cast":
            result = run_cast(args, config)
        elif args.command == "stress":
            result = run_stress(args, config)
        else:
            raise PipelineError(f"unsupported command: {args.command}")
    except (PipelineError, subprocess.CalledProcessError) as error:
        print(f"narration pipeline failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
