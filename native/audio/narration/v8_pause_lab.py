#!/usr/bin/env python3
"""Frozen V8 offline pause-density lab for both narration finalists.

Lab audio is diagnostic and can never become a master parent.  The lab changes
only semantic segmentation and the tempo of the reference presented to Qwen;
it never trims internal silence, pads duration, or time-stretches output speech.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any

import numpy as np

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6
import v7_pipeline as v7
import v8_pipeline as v8


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V8_TWO_VOICE_PAUSE_DENSITY_LAB_NON_SHIPPING"


def _factor_slug(factor: float) -> str:
    return f"{factor:.2f}".replace(".", "p")


def _silence_fraction(audio: np.ndarray, *, sample_rate: int) -> dict[str, Any]:
    settings = v8.load_config()["finalAudit"]
    frame = round(sample_rate * 20 / 1000)
    hop = round(sample_rate * 10 / 1000)
    material = np.asarray(audio, dtype=np.float32).reshape(-1)
    if material.size < frame:
        raise v8.V8Error("pause-lab audio is too short for silence analysis")
    squared = material.astype(np.float64) ** 2
    cumulative = np.concatenate(([0.0], np.cumsum(squared)))
    starts = np.arange(0, material.size - frame + 1, hop, dtype=np.int64)
    rms = np.sqrt(
        (cumulative[starts + frame] - cumulative[starts]) / frame + 1e-15
    )
    count = int(np.count_nonzero(rms < 10 ** (-45 / 20)))
    return {
        "thresholdDBFS": -45,
        "frameMilliseconds": 20,
        "hopMilliseconds": 10,
        "analysisFrameCount": len(starts),
        "silentFrameCount": count,
        "silenceFraction": count / len(starts),
        "maximumFinalMasterSilenceFraction": settings[
            "maximumTotalSilenceFraction"
        ],
    }


def _condition_reference(
    *,
    source: Path,
    destination: Path,
    factor: float,
    v6_config: dict[str, Any],
) -> None:
    command = [
        v6_config["master"]["ffmpegPath"],
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
    subprocess.run(command, check=True, capture_output=True)


def _generation_seed(
    *, candidate_index: int, factor_index: int, batch_index: int, attempt: int
) -> int:
    return (
        8_000_000
        + candidate_index * 1_000_000
        + factor_index * 100_000
        + batch_index * 1_000
        + attempt
    )


def _generate_attempt(
    *,
    directory: Path,
    candidate_id: str,
    candidate_index: int,
    factor_index: int,
    factor: float,
    batch_index: int,
    attempt: int,
    utterances: list[dict[str, Any]],
    model: Any,
    extractor: Any,
    reference_unit: Any,
    conditioned_reference: Path,
    identity_text: str,
    v6_config: dict[str, Any],
) -> dict[str, Any]:
    import mlx.core as mx

    if directory.exists():
        raise v8.V8Error("pause-lab attempt directory already exists")
    directory.mkdir(parents=True)
    seed = _generation_seed(
        candidate_index=candidate_index,
        factor_index=factor_index,
        batch_index=batch_index,
        attempt=attempt,
    )
    production.set_generation_seed(seed)
    results = list(
        model.batch_generate(
            texts=[item["text"] for item in utterances],
            ref_audio=str(conditioned_reference),
            ref_text=identity_text,
            lang_code=production.validate_config()["language"],
            temperature=v6_config["generation"]["temperature"],
            top_k=v6_config["generation"]["topK"],
            top_p=v6_config["generation"]["topP"],
            repetition_penalty=v6_config["generation"][
                "repetitionPenaltyRequested"
            ],
            max_tokens=v6_config["generation"]["maximumTokens"],
            stream=False,
            verbose=False,
        )
    )
    if (
        len(results) != len(utterances)
        or sorted(item.sequence_idx for item in results)
        != list(range(len(utterances)))
    ):
        raise v8.V8Error("pause-lab Qwen batch returned an incomplete sequence")
    results_by_index = {item.sequence_idx: item for item in results}
    audio_paths: list[Path] = []
    generated: list[dict[str, Any]] = []
    processed_audio: list[np.ndarray] = []
    retained_audio: list[np.ndarray] = []
    for local_index, utterance in enumerate(utterances):
        result = results_by_index[local_index]
        raw = np.ascontiguousarray(
            np.asarray(result.audio, dtype=np.float32).reshape(-1)
        )
        if (
            int(result.sample_rate) != v6_config["master"]["nativeSampleRate"]
            or int(result.samples) != raw.size
            or raw.size == 0
            or not np.all(np.isfinite(raw))
        ):
            raise v8.V8Error("pause-lab Qwen output PCM is invalid")
        processed, processing = v6.process_utterance_audio(
            raw,
            sample_rate=int(result.sample_rate),
            separator_after=utterance["separatorAfter"],
            config=v6_config,
            normalized_word_count=None,
        )
        if "adaptiveSemanticPacing" in processing:
            raise v8.V8Error("pause lab added forbidden adaptive zero padding")
        raw_path = directory / f"{utterance['utteranceID']}.raw-f32.wav"
        audio_path = directory / f"{utterance['utteranceID']}.audio-f32.wav"
        production.write_float_wav(raw_path, int(result.sample_rate), raw)
        production.write_float_wav(audio_path, int(result.sample_rate), processed)
        tokenizer_count, token_cap = v6._derived_token_cap(
            model, utterance["text"], v6_config
        )
        generated.append(
            {
                "utterance": {
                    key: value for key, value in utterance.items() if key != "text"
                },
                "tokenizerTokenCount": tokenizer_count,
                "derivedTokenCap": token_cap,
                "generatedTokenCount": int(result.token_count),
                "rawAudio": v8.file_binding(raw_path),
                "processedAudio": v8.file_binding(audio_path),
                "processing": processing,
            }
        )
        audio_paths.append(audio_path)
        processed_audio.append(processed)
        retained_audio.append(
            processed[: processing["retainedSampleCountBeforePause"]]
        )
    transcript_paths, asr_run = v6.run_whisper_batch(
        audio_paths=audio_paths, staging=directory, config=v6_config
    )
    utterance_records: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    reference_words: list[str] = []
    hypothesis_words: list[str] = []
    for utterance, record, audio, transcript_path in zip(
        utterances, generated, processed_audio, transcript_paths, strict=True
    ):
        transcript = production.load_json(transcript_path)
        identity = v6._utterance_identity_cosine(audio, reference_unit, extractor)
        gate = v6.utterance_asr_gate(
            utterance=utterance,
            transcript=transcript,
            duration_seconds=len(audio)
            / v6_config["master"]["nativeSampleRate"],
            token_count=record["generatedTokenCount"],
            token_cap=record["derivedTokenCap"],
            identity_cosine=identity,
            config=v6_config,
            adaptive_pacing_pass=True,
        )
        timed_words, grouping = v5.timed_words_from_whisper(
            transcript,
            master_duration_ms=len(audio)
            * 1000
            / v6_config["master"]["nativeSampleRate"],
        )
        reference_words.extend(v5.normalize_words(utterance["text"]))
        hypothesis_words.extend(item.text for item in timed_words)
        complete = {
            **record,
            "transcript": v8.file_binding(transcript_path),
            "identityCosineToOriginalReference": identity,
            "timedWordGrouping": grouping,
            "gate": gate,
        }
        utterance_records.append(complete)
        if not gate["passes"]:
            failed.append(
                {
                    "utteranceID": utterance["utteranceID"],
                    "failedGates": [
                        key for key, passed in gate["gates"].items() if not passed
                    ],
                    "gate": gate,
                }
            )
    steps, alignment = v5.monotone_global_alignment(
        reference_words, hypothesis_words
    )
    del steps
    montage = np.concatenate(processed_audio)
    retained_montage = np.concatenate(retained_audio)
    montage_silence = _silence_fraction(
        montage, sample_rate=v6_config["master"]["nativeSampleRate"]
    )
    retained_silence = _silence_fraction(
        retained_montage, sample_rate=v6_config["master"]["nativeSampleRate"]
    )
    mx.clear_cache()
    return {
        "candidateID": candidate_id,
        "factor": factor,
        "batchIndex": batch_index,
        "attempt": attempt,
        "generationSeed": seed,
        "utteranceRecords": utterance_records,
        "asrRun": asr_run,
        "aggregateAlignment": alignment,
        "montageSilence": montage_silence,
        "modelRetainedSilence": retained_silence,
        "processedSampleCount": int(len(montage)),
        "retainedSampleCount": int(len(retained_montage)),
        "normalizedReferenceWordCount": len(reference_words),
        "failedUtterances": failed,
        "allUtteranceGatesPass": not failed,
    }


def _candidate_factor(
    *,
    root: Path,
    candidate_id: str,
    candidate_index: int,
    factor: float,
    factor_index: int,
    selected: list[dict[str, Any]],
    full_utterances: list[dict[str, Any]],
    model: Any,
    extractor: Any,
    reference_unit: Any,
    reference_source: Path,
    identity_text: str,
    v6_config: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    factor_root = root / f"factor-{_factor_slug(factor)}" / candidate_id
    factor_root.mkdir(parents=True)
    conditioned = factor_root / "conditioned-reference.wav"
    _condition_reference(
        source=reference_source,
        destination=conditioned,
        factor=factor,
        v6_config=v6_config,
    )
    conditioned_audio, conditioned_record = v5._load_reference_audio(
        conditioned, v6_config["master"]["nativeSampleRate"]
    )
    reference_identity = v6._utterance_identity_cosine(
        conditioned_audio, reference_unit, extractor
    )
    maximum_attempts = config["generation"]["maximumBatchAttempts"]
    batch_size = config["generation"]["batchSize"]
    accepted: list[dict[str, Any]] = []
    all_attempts: list[dict[str, Any]] = []
    exhausted = False
    for batch_index, start in enumerate(range(0, len(selected), batch_size)):
        batch = selected[start : start + batch_size]
        chosen: dict[str, Any] | None = None
        for attempt in range(1, maximum_attempts + 1):
            attempt_record = _generate_attempt(
                directory=factor_root
                / f"batch-{batch_index:03d}"
                / f"attempt-{attempt}",
                candidate_id=candidate_id,
                candidate_index=candidate_index,
                factor_index=factor_index,
                factor=factor,
                batch_index=batch_index,
                attempt=attempt,
                utterances=batch,
                model=model,
                extractor=extractor,
                reference_unit=reference_unit,
                conditioned_reference=conditioned,
                identity_text=identity_text,
                v6_config=v6_config,
            )
            all_attempts.append(attempt_record)
            if attempt_record["allUtteranceGatesPass"]:
                chosen = attempt_record
                break
        if chosen is None:
            exhausted = True
            break
        accepted.append(chosen)

    lab = config["pauseDensityLab"]
    expected_batch_count = math.ceil(len(selected) / batch_size)
    if exhausted or len(accepted) != expected_batch_count:
        return {
            "candidateID": candidate_id,
            "factor": factor,
            "conditionedReference": conditioned_record,
            "conditionedReferenceFile": v8.file_binding(conditioned),
            "referenceIdentityCosine": reference_identity,
            "attempts": all_attempts,
            "acceptedBatchCount": len(accepted),
            "expectedBatchCount": expected_batch_count,
            "gates": {
                "referenceIdentity": reference_identity
                >= lab["minimumReferenceIdentityCosine"],
                "allBatchesPassed": False,
            },
            "passes": False,
        }

    utterance_records = [
        item for batch in accepted for item in batch["utteranceRecords"]
    ]
    references = [
        word
        for utterance in selected
        for word in v5.normalize_words(utterance["text"])
    ]
    hypotheses: list[str] = []
    processed_audio: list[np.ndarray] = []
    retained_audio: list[np.ndarray] = []
    total_retained_samples = 0
    for record in utterance_records:
        transcript = production.load_json(Path(record["transcript"]["path"]))
        timed, _ = v5.timed_words_from_whisper(
            transcript,
            master_duration_ms=record["gate"]["durationSeconds"] * 1000,
        )
        hypotheses.extend(item.text for item in timed)
        audio, _ = v5.read_native_audio(
            Path(record["processedAudio"]["path"]), v6_config
        )
        retained = record["processing"]["retainedSampleCountBeforePause"]
        processed_audio.append(audio)
        retained_audio.append(audio[:retained])
        total_retained_samples += retained
    _, aggregate = v5.monotone_global_alignment(references, hypotheses)
    montage_silence = _silence_fraction(
        np.concatenate(processed_audio),
        sample_rate=v6_config["master"]["nativeSampleRate"],
    )
    retained_silence = _silence_fraction(
        np.concatenate(retained_audio),
        sample_rate=v6_config["master"]["nativeSampleRate"],
    )
    full_authored_pause_samples = sum(
        round(
            v6_config["master"]["nativeSampleRate"]
            * (
                v6_config["join"]["paragraphPauseMilliseconds"]
                if item["separatorAfter"] == "\n\n"
                else v6_config["join"]["intraParagraphPauseMilliseconds"]
                if item["separatorAfter"] == " "
                else v6_config["join"]["finalPauseMilliseconds"]
            )
            / 1000
        )
        for item in full_utterances
    )
    projected = (
        total_retained_samples
        / v6_config["master"]["nativeSampleRate"]
        / len(references)
        * 3422
        + full_authored_pause_samples
        / v6_config["master"]["nativeSampleRate"]
    )
    gates = {
        "referenceIdentity": reference_identity
        >= lab["minimumReferenceIdentityCosine"],
        "allBatchesPassed": True,
        "allUtteranceGates": all(
            item["gate"]["passes"] for item in utterance_records
        ),
        "minimumUtteranceIdentity": min(
            item["identityCosineToOriginalReference"] for item in utterance_records
        )
        >= lab["minimumUtteranceIdentityCosine"],
        "maximumAggregateWordErrorRate": aggregate["wordAlignmentErrorRate"]
        <= lab["maximumAggregateWordErrorRate"],
        "maximumModelRetainedSilenceFraction": retained_silence[
            "silenceFraction"
        ]
        <= lab["maximumModelRetainedSilenceFraction"],
        "maximumRepresentativeMontageSilenceFraction": montage_silence[
            "silenceFraction"
        ]
        <= lab["maximumRepresentativeMontageSilenceFraction"],
        "minimumProjectedFullDuration": projected
        >= lab["minimumProjectedFullDurationSeconds"],
        "maximumProjectedFullDuration": projected
        <= lab["maximumProjectedFullDurationSeconds"],
    }
    return {
        "candidateID": candidate_id,
        "factor": factor,
        "conditionedReference": conditioned_record,
        "conditionedReferenceFile": v8.file_binding(conditioned),
        "referenceIdentityCosine": reference_identity,
        "attempts": all_attempts,
        "acceptedBatches": [
            {
                "batchIndex": item["batchIndex"],
                "attempt": item["attempt"],
                "generationSeed": item["generationSeed"],
            }
            for item in accepted
        ],
        "utteranceRecords": utterance_records,
        "aggregateAlignment": aggregate,
        "modelRetainedSilence": retained_silence,
        "representativeMontageSilence": montage_silence,
        "projectedFullDurationSeconds": projected,
        "fullAuthoredPauseSeconds": full_authored_pause_samples
        / v6_config["master"]["nativeSampleRate"],
        "gates": gates,
        "passes": all(gates.values()),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("V8 pause lab requires the explicit --offline flag")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    config = v8.load_config()
    output = v8.prepare_output(args.output, config)
    dependencies = v8.validate_dependencies(config)
    v6_config = v6.load_config()
    _, stress_record, cues, utterances, segmentation = v8.segmentation_material()
    selected_ids = set(
        config["pauseDensityLab"]["representativeUtteranceIDs"]
    )
    selected = [
        item for item in utterances if item["utteranceID"] in selected_ids
    ]
    if len(selected) != len(selected_ids) or {
        item["segmentID"] for item in selected
    } != {item["segmentID"] for item in cues}:
        raise v8.V8Error("V8 pause-lab representative set is incomplete")
    context = v6._generation_context(v6_config)
    model, extractor = v6._load_runtime(context)
    reference_units, reference_records = v6._reference_material(
        context=context, extractor=extractor, config=v6_config
    )
    records: list[dict[str, Any]] = []
    factors = config["pauseDensityLab"]["referenceTempoFactors"]
    for factor_index, factor in enumerate(factors):
        for candidate_index, candidate_id in enumerate(v8.EXPECTED_FINALISTS):
            source = Path(
                context["parentRecords"][candidate_id]["_verifiedReferencePath"]
            )
            record = _candidate_factor(
                root=output,
                candidate_id=candidate_id,
                candidate_index=candidate_index,
                factor=factor,
                factor_index=factor_index,
                selected=selected,
                full_utterances=utterances,
                model=model,
                extractor=extractor,
                reference_unit=reference_units[candidate_id],
                reference_source=source,
                identity_text=context["identityText"],
                v6_config=v6_config,
                config=config,
            )
            record["originalReference"] = reference_records[candidate_id]
            records.append(record)
            print(
                f"V8 pause lab {candidate_id} factor {factor:.2f}: "
                f"{'PASS' if record['passes'] else 'FAIL'}",
                file=sys.stderr,
                flush=True,
            )
    qualifying = [
        factor
        for factor in factors
        if all(
            item["passes"]
            for item in records
            if item["factor"] == factor
        )
        and len([item for item in records if item["factor"] == factor]) == 2
    ]
    selected_factor = min(qualifying) if qualifying else None
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v8.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "v8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "v8Config": v8.file_binding(v8.CONFIG_PATH),
        "dependencyBindings": dependencies,
        "stressText": stress_record,
        "segmentation": segmentation,
        "representativeUtterances": [
            {key: value for key, value in item.items() if key != "text"}
            for item in selected
        ],
        "factors": factors,
        "factorCandidateRecords": records,
        "qualifyingFactors": qualifying,
        "selectedFactor": selected_factor,
        "selectionRule": config["pauseDensityLab"]["selectionRule"],
        "passesPauseDensityLab": selected_factor is not None,
        "technicalBlock": None
        if selected_factor is not None
        else (
            "No frozen reference-tempo factor passed every word, identity, "
            "model-retained silence, montage silence and projected-duration "
            "gate for both voices. Full V8 master generation is prohibited."
        ),
        "labAudioPermittedAsMasterParent": False,
        "fullGenerationMustResynthesiseAllUtterancesWithNewSeeds": True,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "shippingApproval": False,
        "networkUsed": False,
        "incrementalCostNOK": 0,
    }
    receipt_path = output / "pause-density-lab.v8.receipt.json"
    v8.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Frozen offline V8 pause-density lab")
    result.add_argument("--output", required=True, type=Path)
    result.add_argument("--offline", action="store_true")
    return result


def main() -> int:
    try:
        print(json.dumps(run(parser().parse_args()), ensure_ascii=False, indent=2))
        return 0
    except (
        v8.V8Error,
        v7.V7Error,
        v6.V6Error,
        v5.V5Error,
        production.PipelineError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"V8 pause lab error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
