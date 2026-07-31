#!/usr/bin/env python3
"""Run the bounded VoxCPM2 comparison for Chapter 01 review narration."""

from __future__ import annotations

import argparse
import gc
import hashlib
import json
import math
import os
from pathlib import Path
import random
import socket
import subprocess
import sys
from typing import Any, Iterable

import first_farmers_review_narration as review


SCRIPT_PATH = Path(__file__).absolute()
PROBE_ROOT = review.REVIEW_ROOT / "probes"
PROBE_WORK_ROOT = review.WORK_ROOT / "voxcpm2-probes"
FULL_WORK_ROOT = review.WORK_ROOT / "voxcpm2-cues"
REVIEW_CACHE_ROOT = review.WORK_ROOT / "voxcpm2-cache"
NUMBA_CACHE_ROOT = REVIEW_CACHE_ROOT / "numba"
STATUS = review.STATUS
SHIPPING_STATE = review.SHIPPING_STATE
PROBE_SEGMENT_COUNT = 4
CONTROL_INSTRUCTION = (
    "(measured pace, calm authority, clear articulation, restrained expression)"
)


class VoxReviewError(RuntimeError):
    """Raised when the bounded VoxCPM2 review run escapes its contract."""


def _block_network() -> list[str]:
    attempts: list[str] = []

    def blocked(*args: Any, **kwargs: Any) -> Any:
        del args, kwargs
        attempts.append("socket")
        raise VoxReviewError("network access attempted during review synthesis")

    socket.socket.connect = blocked
    socket.socket.connect_ex = blocked
    socket.create_connection = blocked
    socket.getaddrinfo = blocked
    return attempts


def _v12_runtime() -> tuple[Any, dict[str, Any]]:
    import v12_voxcpm2_presynthesis as v12

    if os.environ.get("PYTHONDONTWRITEBYTECODE") != "1":
        raise VoxReviewError("review synthesis requires PYTHONDONTWRITEBYTECODE=1")
    receipt = v12.validate_receipt()
    if receipt.get("synthesisPermitted") is not False:
        raise VoxReviewError("V12 production boundary unexpectedly opened")
    expected_cache = NUMBA_CACHE_ROOT.absolute()
    actual_cache = Path(os.environ.get("NUMBA_CACHE_DIR", "")).absolute()
    if actual_cache != expected_cache:
        raise VoxReviewError(
            f"NUMBA_CACHE_DIR must be the separate review cache: {expected_cache}"
        )
    if actual_cache.is_relative_to(v12.RUNTIME_ROOT.absolute()):
        raise VoxReviewError("review Numba cache entered the V12 runtime tree")
    return v12, receipt


def _load_vox_model() -> tuple[Any, Any, list[str], dict[str, Any]]:
    v12, receipt = _v12_runtime()
    attempts = _block_network()
    import torch
    from voxcpm import VoxCPM
    from voxcpm.model.voxcpm2 import VoxCPM2Model

    if sys.version.split()[0] != "3.11.15" or torch.__version__ != "2.10.0":
        raise VoxReviewError("VoxCPM2 review runtime version drifted")
    if not torch.backends.mps.is_available():
        raise VoxReviewError("VoxCPM2 review requires the bound MPS runtime")
    lock = v12._load_lock()
    model_root = review.REPOSITORY_ROOT / lock["model"]["root"]
    protected_before = v12._protected_manifests(lock)
    model = VoxCPM(
        voxcpm_model_path=str(model_root),
        zipenhancer_model_path=None,
        enable_denoiser=False,
        optimize=False,
        device="mps",
        lora_config=None,
        lora_weights_path=None,
    )
    if not isinstance(model.tts_model, VoxCPM2Model):
        raise VoxReviewError("unexpected VoxCPM2 review architecture")
    if attempts:
        raise VoxReviewError("VoxCPM2 model load attempted network access")
    return model, v12, attempts, {
        "v12Validation": receipt,
        "protectedBefore": protected_before,
        "modelRoot": str(model_root.absolute()),
        "torchVersion": torch.__version__,
    }


def _generation_kwargs(reference_path: Path, transcript: str, text: str) -> dict[str, Any]:
    return {
        "text": CONTROL_INSTRUCTION + text,
        "prompt_wav_path": str(reference_path.absolute()),
        "prompt_text": transcript,
        "reference_wav_path": str(reference_path.absolute()),
        "cfg_value": 2.0,
        "inference_timesteps": 10,
        "min_len": 2,
        "max_len": 4096,
        "normalize": False,
        "denoise": False,
        "retry_badcase": False,
    }


def _generate_one(
    model: Any,
    *,
    text: str,
    reference_path: Path,
    transcript: str,
    seed: int,
) -> tuple[Any, dict[str, Any]]:
    import numpy as np
    import torch

    random.seed(seed)
    np.random.seed(seed % (2**32))
    torch.manual_seed(seed)
    generated = model.generate(
        **_generation_kwargs(reference_path, transcript, text)
    )
    torch.mps.synchronize()
    raw = np.ascontiguousarray(np.asarray(generated, dtype=np.float32).reshape(-1))
    if raw.size == 0 or not np.all(np.isfinite(raw)):
        raise VoxReviewError("VoxCPM2 returned empty or non-finite PCM")
    processed = review._trim_fade_and_pause(raw, review.EXPECTED_SAMPLE_RATE)
    return processed, {
        "seed": seed,
        "rawSampleCount": int(raw.size),
        "processedSampleCount": int(processed.size),
        "sampleRate": review.EXPECTED_SAMPLE_RATE,
        "rawFloat32LESHA256": hashlib.sha256(raw.astype("<f4").tobytes()).hexdigest(),
        "processedFloat32LESHA256": hashlib.sha256(
            processed.astype("<f4").tobytes()
        ).hexdigest(),
        "oneModelGenerateCall": True,
        "retryUsed": False,
    }


def _write_float_wav(path: Path, audio: Any) -> None:
    from scipy.io import wavfile
    import numpy as np

    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise VoxReviewError(f"refusing to overwrite generated WAV: {path}")
    wavfile.write(
        path,
        review.EXPECTED_SAMPLE_RATE,
        np.ascontiguousarray(audio, dtype=np.float32),
    )


def _finish_model(model: Any, v12: Any, model_record: dict[str, Any]) -> dict[str, Any]:
    import torch

    torch.mps.synchronize()
    protected_after = v12._protected_manifests(v12._load_lock())
    if protected_after != model_record["protectedBefore"]:
        raise VoxReviewError("review synthesis mutated V12 protected bytes")
    del model
    gc.collect()
    torch.mps.empty_cache()
    return protected_after


def generate_probes() -> dict[str, Any]:
    review.validate_authorization()
    if review.PROBE_MANIFEST_PATH.exists():
        raise VoxReviewError("VoxCPM2 probe manifest already exists")
    NUMBA_CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    _, segments = review.manuscript_segments()
    probe_segments = segments[:PROBE_SEGMENT_COUNT]
    transcript = review.IDENTITY_TEXT_PATH.read_text(encoding="utf-8").strip()
    model, v12, attempts, model_record = _load_vox_model()
    import numpy as np

    PROBE_ROOT.mkdir(parents=True, exist_ok=True)
    PROBE_WORK_ROOT.mkdir(parents=True, exist_ok=True)
    candidate_records = []
    for candidate_index, candidate_id in enumerate(review.CANDIDATE_REFERENCE_PATHS):
        reference_path = review.CANDIDATE_REFERENCE_PATHS[candidate_id]
        parts = []
        jobs = []
        for segment_index, segment in enumerate(probe_segments):
            seed = 27_020_000 + candidate_index * 100_000 + segment_index * 101
            audio, job = _generate_one(
                model,
                text=segment["text"],
                reference_path=reference_path,
                transcript=transcript,
                seed=seed,
            )
            parts.append(audio)
            jobs.append(
                {
                    **job,
                    "manuscriptSegmentID": segment["manuscriptSegmentID"],
                    "manuscriptSegmentSHA256": segment[
                        "manuscriptSegmentSHA256"
                    ],
                }
            )
            print(
                f"VoxCPM2 probe {candidate_id} {segment_index + 1}/{PROBE_SEGMENT_COUNT}",
                flush=True,
            )
        combined = np.ascontiguousarray(np.concatenate(parts), dtype=np.float32)
        native_path = PROBE_WORK_ROOT / f"{candidate_id}.wav"
        _write_float_wav(native_path, combined)
        destination = PROBE_ROOT / f"{candidate_id}.m4a"
        encoded = review.encode_m4a_deterministically(native_path, destination)
        candidate_records.append(
            {
                "candidateID": candidate_id,
                "reference": review.binding(reference_path, repository_relative=True),
                "generationCallCount": len(jobs),
                "jobs": jobs,
                "audio": encoded,
                "durationSeconds": encoded["durationSamples"]
                / review.EXPECTED_SAMPLE_RATE,
            }
        )
    protected_after = _finish_model(model, v12, model_record)
    if attempts:
        raise VoxReviewError("VoxCPM2 review generation attempted network access")
    manifest = {
        "schemaVersion": 1,
        "status": STATUS,
        "shippingState": SHIPPING_STATE,
        "chapterID": "first-farmers",
        "engine": review.VOX_ENGINE,
        "probeCount": 2,
        "sharedText": [
            {
                "manuscriptSegmentID": item["manuscriptSegmentID"],
                "manuscriptSegmentSHA256": item["manuscriptSegmentSHA256"],
            }
            for item in probe_segments
        ],
        "sharedTextSHA256": review.sha256_bytes(
            " ".join(item["text"] for item in probe_segments).encode("utf-8")
        ),
        "authorization": review.binding(
            review.AUTHORIZATION_PATH, repository_relative=True
        ),
        "closedV12Authority": review.binding(
            review.REPOSITORY_ROOT
            / review.load_json(review.AUTHORIZATION_PATH)[
                "v12PresynthesisAuthority"
            ]["path"],
            repository_relative=True,
        ),
        "synthesisScript": review.binding(SCRIPT_PATH, repository_relative=True),
        "runtime": {
            "python": sys.version.split()[0],
            "torch": model_record["torchVersion"],
            "device": "mps",
            "dtype": "float32",
            "separateReviewNumbaCache": str(NUMBA_CACHE_ROOT.absolute()),
        },
        "candidateRecords": candidate_records,
        "modelGenerateCallCount": sum(
            item["generationCallCount"] for item in candidate_records
        ),
        "networkAttemptCount": len(attempts),
        "v12ProtectedBytesUnchanged": protected_after
        == model_record["protectedBefore"],
        "oneTakePerSegment": True,
        "retryUsed": False,
        "runtimeGenerationPermitted": False,
        "shippingUsePermitted": False,
    }
    review.write_json(review.PROBE_MANIFEST_PATH, manifest)
    return validate_probes()


def validate_probes() -> dict[str, Any]:
    review.validate_authorization()
    document = review.load_json(review.PROBE_MANIFEST_PATH)
    if (
        document.get("schemaVersion") != 1
        or document.get("status") != STATUS
        or document.get("shippingState") != SHIPPING_STATE
        or document.get("chapterID") != "first-farmers"
        or document.get("engine") != review.VOX_ENGINE
        or document.get("probeCount") != 2
        or document.get("modelGenerateCallCount") != 8
        or document.get("networkAttemptCount") != 0
        or document.get("v12ProtectedBytesUnchanged") is not True
        or document.get("oneTakePerSegment") is not True
        or document.get("retryUsed") is not False
        or document.get("runtimeGenerationPermitted") is not False
        or document.get("shippingUsePermitted") is not False
    ):
        raise VoxReviewError("VoxCPM2 probe manifest drifted")
    _, segments = review.manuscript_segments()
    expected_text = [
        {
            "manuscriptSegmentID": item["manuscriptSegmentID"],
            "manuscriptSegmentSHA256": item["manuscriptSegmentSHA256"],
        }
        for item in segments[:PROBE_SEGMENT_COUNT]
    ]
    if document.get("sharedText") != expected_text:
        raise VoxReviewError("VoxCPM2 probe manuscript binding drifted")
    records = document.get("candidateRecords")
    if (
        not isinstance(records, list)
        or [item.get("candidateID") for item in records]
        != ["voice-candidate-05", "voice-candidate-06"]
    ):
        raise VoxReviewError("VoxCPM2 probe candidate inventory drifted")
    durations = {}
    for record in records:
        candidate_id = record["candidateID"]
        path = PROBE_ROOT / f"{candidate_id}.m4a"
        actual = review.audio_record(path)
        if (
            record.get("audio") != actual
            or record.get("generationCallCount") != PROBE_SEGMENT_COUNT
            or len(record.get("jobs", [])) != PROBE_SEGMENT_COUNT
        ):
            raise VoxReviewError(f"VoxCPM2 probe bytes drifted: {candidate_id}")
        durations[candidate_id] = actual["durationSamples"] / review.EXPECTED_SAMPLE_RATE
    return {
        "status": STATUS,
        "probeCount": 2,
        "durations": durations,
        "manifest": review.binding(
            review.PROBE_MANIFEST_PATH, repository_relative=True
        ),
    }


def _maximum_false_run(values: list[bool]) -> int:
    maximum = current = 0
    for value in values:
        if value:
            current = 0
        else:
            current += 1
            maximum = max(maximum, current)
    return maximum


def _silence_fraction(audio: Any, sample_rate: int) -> float:
    import numpy as np

    material = np.asarray(audio, dtype=np.float32).reshape(-1)
    frame = round(sample_rate * 0.02)
    usable = material[: material.size - (material.size % frame)]
    if usable.size == 0:
        raise VoxReviewError("probe is too short for silence analysis")
    frames = usable.reshape(-1, frame)
    rms = np.sqrt(np.mean(frames.astype(np.float64) ** 2, axis=1) + 1e-15)
    return float(np.mean(rms < 10 ** (-50 / 20)))


def _unit(value: Any) -> Any:
    import numpy as np

    material = np.asarray(value, dtype=np.float32).reshape(-1)
    norm = float(np.linalg.norm(material))
    if not math.isfinite(norm) or norm <= 0:
        raise VoxReviewError("speaker embedding is invalid")
    return material / norm


def _identity_stability(
    *, audio: Any, reference: Any, extractor: Any, sample_rate: int
) -> dict[str, Any]:
    import numpy as np

    reference_unit = _unit(extractor(reference))
    material = np.asarray(audio, dtype=np.float32).reshape(-1)
    window = round(sample_rate * 8)
    hop = round(sample_rate * 8)
    cosines = []
    for start in range(0, max(1, material.size - window + 1), hop):
        part = material[start : start + window]
        if part.size < window:
            break
        if float(np.sqrt(np.mean(part.astype(np.float64) ** 2) + 1e-15)) < 0.003:
            continue
        cosines.append(float(np.dot(_unit(extractor(part)), reference_unit)))
    if not cosines:
        raise VoxReviewError("probe has no voiced identity window")
    return {
        "windowSeconds": 8,
        "windowCount": len(cosines),
        "cosinesToReference": cosines,
        "minimumCosineToReference": min(cosines),
        "meanCosineToReference": sum(cosines) / len(cosines),
    }


def _whisper_derivative(source: Path, destination: Path) -> dict[str, Any]:
    """Decode the reviewed AAC bytes to whisper.cpp's required PCM WAV input."""
    if destination.exists():
        raise VoxReviewError(f"Whisper audit derivative already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(review._ffmpeg_path()),
        "-nostdin",
        "-v",
        "error",
        "-i",
        str(source),
        "-map",
        "0:a:0",
        "-map_metadata",
        "-1",
        "-ar",
        "16000",
        "-ac",
        "1",
        "-c:a",
        "pcm_s16le",
        str(destination),
    ]
    subprocess.run(command, check=True)
    if not destination.is_file() or destination.stat().st_size <= 44:
        raise VoxReviewError(f"Whisper audit derivative is empty: {destination}")
    return {
        "source": review.binding(source, repository_relative=True),
        "derivative": review.binding(destination),
        "sampleRate": 16_000,
        "channels": 1,
        "codec": "pcm_s16le",
        "contentTransform": "decode-and-resample-only",
    }


def audit_probes() -> dict[str, Any]:
    validate_probes()
    if review.PROBE_SELECTION_PATH.exists():
        raise VoxReviewError("probe selection record already exists")
    import pipeline as production
    import v5_pipeline as v5
    import v6_pipeline as v6
    from mlx_audio.tts.utils import load_model
    from mlx_audio.utils import load_audio
    import numpy as np

    v6_config = v6.load_config()
    production_config = production.validate_config(review.PIPELINE_CONFIG_PATH)
    model_path, _ = production.verify_model_snapshot(
        production_config["models"]["voiceClone"], offline=True
    )
    speaker_model = load_model(str(model_path))
    extractor = v5.QwenSpeakerExtractor(speaker_model)
    _, segments = review.manuscript_segments()
    probe_segments = segments[:PROBE_SEGMENT_COUNT]
    expected_text = " ".join(item["text"] for item in probe_segments)
    reference_words = v5.normalize_words(expected_text)
    audit_root = PROBE_WORK_ROOT / "audit"
    audit_root.mkdir(parents=True, exist_ok=True)
    records = []
    for candidate_id, reference_path in review.CANDIDATE_REFERENCE_PATHS.items():
        audio_path = PROBE_ROOT / f"{candidate_id}.m4a"
        whisper_input = audit_root / f"{candidate_id}-asr-input.wav"
        asr_derivative = _whisper_derivative(audio_path, whisper_input)
        output_prefix = audit_root / candidate_id
        transcript_path, asr = v5.run_pinned_whisper(
            master_path=whisper_input,
            output_prefix=output_prefix,
            config=v6_config,
            confinement_root=review.REPOSITORY_ROOT,
        )
        transcript = review.load_json(transcript_path)
        duration = review.audio_record(audio_path)["durationSamples"] / review.EXPECTED_SAMPLE_RATE
        timed_words, grouping = v5.timed_words_from_whisper(
            transcript, master_duration_ms=duration * 1000
        )
        hypothesis = [item.text for item in timed_words]
        steps, alignment = v5.monotone_global_alignment(reference_words, hypothesis)
        exact_reference = [False] * len(reference_words)
        exact_hypothesis = [False] * len(hypothesis)
        for step in steps:
            if step.operation == "equal":
                if step.reference_index is not None:
                    exact_reference[step.reference_index] = True
                if step.hypothesis_index is not None:
                    exact_hypothesis[step.hypothesis_index] = True
        audio = np.asarray(load_audio(str(audio_path), sample_rate=24_000), dtype=np.float32)
        reference = np.asarray(
            load_audio(str(reference_path), sample_rate=24_000), dtype=np.float32
        )
        identity = _identity_stability(
            audio=audio,
            reference=reference,
            extractor=extractor,
            sample_rate=24_000,
        )
        silence = _silence_fraction(audio, 24_000)
        accuracy = 1 - alignment["editDistance"] / len(reference_words)
        ratio = len(hypothesis) / len(reference_words)
        maximum_reference_run = _maximum_false_run(exact_reference)
        maximum_hypothesis_run = _maximum_false_run(exact_hypothesis)
        repetition = v5.reference_aware_repetition(
            reference_words, hypothesis, v6_config
        )
        gates = {
            "duration60To90Seconds": 60 <= duration <= 90,
            "wordAccuracy": accuracy >= 0.88,
            "identityStability": identity["minimumCosineToReference"] >= 0.90,
            "retainedSilence": silence <= 0.20,
            "decoderCollapseAbsent": (
                0.8 <= ratio <= 1.2
                and maximum_reference_run <= 4
                and maximum_hypothesis_run <= 4
                and repetition["excessOccurrenceCount"] == 0
            ),
        }
        records.append(
            {
                "candidateID": candidate_id,
                "audio": review.audio_record(audio_path),
                "durationSeconds": duration,
                "wordAccuracy": accuracy,
                "wordErrorRate": 1 - accuracy,
                "hypothesisToReferenceWordRatio": ratio,
                "maximumNonmatchingReferenceRunWords": maximum_reference_run,
                "maximumNonmatchingHypothesisRunWords": maximum_hypothesis_run,
                "identity": identity,
                "retainedSilenceFraction": silence,
                "repetition": repetition,
                "timedWordGrouping": grouping,
                "asrDerivative": asr_derivative,
                "asr": asr,
                "transcript": review.binding(transcript_path),
                "gates": gates,
                "technicalPass": all(gates.values()),
            }
        )
    passing = [item for item in records if item["technicalPass"]]
    if passing:
        passing.sort(
            key=lambda item: (
                -item["wordAccuracy"],
                -item["identity"]["minimumCosineToReference"],
                item["retainedSilenceFraction"],
                item["candidateID"],
            )
        )
        selected_engine = review.VOX_ENGINE
        selected_candidate = passing[0]["candidateID"]
        fallback_used = False
    else:
        selected_engine = review.QWEN_ENGINE
        selected_candidate = "voice-candidate-05"
        fallback_used = True
    selection = {
        "schemaVersion": 1,
        "status": STATUS,
        "shippingState": SHIPPING_STATE,
        "chapterID": "first-farmers",
        "probeCount": 2,
        "probeManifest": review.binding(
            review.PROBE_MANIFEST_PATH, repository_relative=True
        ),
        "selectionCriteria": [
            "word-accuracy",
            "identity-stability",
            "retained-silence-fraction",
            "decoder-collapse-absence",
        ],
        "candidateRecords": records,
        "voxcpm2TechnicalPassCount": len(passing),
        "selectedEngine": selected_engine,
        "selectedCandidateID": selected_candidate,
        "fallbackUsed": fallback_used,
        "wholeChapterUsesOneEngineAndVoice": True,
        "productionVoicePromoted": False,
        "shippingUsePermitted": False,
    }
    review.write_json(review.PROBE_SELECTION_PATH, selection)
    return {
        "status": STATUS,
        "voxcpm2TechnicalPassCount": len(passing),
        "selectedEngine": selected_engine,
        "selectedCandidateID": selected_candidate,
        "fallbackUsed": fallback_used,
        "selection": review.binding(
            review.PROBE_SELECTION_PATH, repository_relative=True
        ),
    }


def render_vox_cues() -> dict[str, Any]:
    selection = review.selected_review_voice()
    if selection.get("selectedEngine") != review.VOX_ENGINE:
        raise VoxReviewError("VoxCPM2 was not selected for the whole review chapter")
    candidate_id = selection["selectedCandidateID"]
    if review.MANIFEST_PATH.exists():
        raise VoxReviewError("review narration manifest already exists")
    NUMBA_CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    _, segments = review.manuscript_segments()
    transcript = review.IDENTITY_TEXT_PATH.read_text(encoding="utf-8").strip()
    reference_path = review.CANDIDATE_REFERENCE_PATHS[candidate_id]
    review.CUES_ROOT.mkdir(parents=True, exist_ok=True)
    records_root = FULL_WORK_ROOT / "records"
    native_root = FULL_WORK_ROOT / "native"
    records_root.mkdir(parents=True, exist_ok=True)
    native_root.mkdir(parents=True, exist_ok=True)
    model, v12, attempts, model_record = _load_vox_model()
    cue_records = []
    for index, segment in enumerate(segments):
        cue_id = segment["cueID"]
        destination = review.CUES_ROOT / f"{cue_id}.m4a"
        record_path = records_root / f"{cue_id}.json"
        if destination.exists() or record_path.exists():
            if not destination.is_file() or not record_path.is_file():
                raise VoxReviewError(f"partial VoxCPM2 cue exists: {cue_id}")
            existing = review.load_json(record_path)
            actual = review.audio_record(destination)
            if (
                existing.get("cueID") != cue_id
                or existing.get("manuscriptSegmentSHA256")
                != segment["manuscriptSegmentSHA256"]
                or existing.get("audio") != actual
            ):
                raise VoxReviewError(f"resumed VoxCPM2 cue drifted: {cue_id}")
            cue_records.append(
                review.runtime_audio_record(destination) | {"cueID": cue_id}
            )
            continue
        seed = 27_030_000 + index * 101
        audio, generation = _generate_one(
            model,
            text=segment["text"],
            reference_path=reference_path,
            transcript=transcript,
            seed=seed,
        )
        native_path = native_root / f"{cue_id}.wav"
        _write_float_wav(native_path, audio)
        encoded = review.encode_m4a_deterministically(native_path, destination)
        review.write_json(
            record_path,
            {
                "schemaVersion": 1,
                "status": STATUS,
                "shippingState": SHIPPING_STATE,
                "cueID": cue_id,
                "manuscriptSegmentSHA256": segment[
                    "manuscriptSegmentSHA256"
                ],
                "engine": review.VOX_ENGINE,
                "candidateID": candidate_id,
                "generation": generation,
                "audio": encoded,
            },
        )
        cue_records.append(
            review.runtime_audio_record(destination) | {"cueID": cue_id}
        )
        print(f"VoxCPM2 review cue {index + 1}/37: {cue_id}", flush=True)
    _finish_model(model, v12, model_record)
    if attempts:
        raise VoxReviewError("VoxCPM2 cue generation attempted network access")
    manifest = review.build_manifest(
        engine=review.VOX_ENGINE,
        candidate_id=candidate_id,
        cue_records=cue_records,
    )
    manifest["generation"] = {
        "offline": True,
        "oneWholeChapterCandidate": True,
        "reference": review.binding(reference_path, repository_relative=True),
        "v12ProductionAuthorityModified": False,
        "reviewNumbaCacheOutsideRuntime": True,
    }
    review.write_json(review.MANIFEST_PATH, manifest)
    return review.validate_manifest()


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=("probe", "validate-probes", "audit", "render", "validate"),
    )
    args = parser.parse_args(list(argv) if argv is not None else None)
    try:
        if args.command == "probe":
            result = generate_probes()
        elif args.command == "validate-probes":
            result = validate_probes()
        elif args.command == "audit":
            result = audit_probes()
        elif args.command == "render":
            result = render_vox_cues()
        else:
            result = review.validate_manifest()
    except Exception as error:
        print(f"Chapter 01 VoxCPM2 review failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
