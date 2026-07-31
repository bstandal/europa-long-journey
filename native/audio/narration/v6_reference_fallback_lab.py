#!/usr/bin/env python3
"""Offline recovery lab for a bounded reference-tempo attempt schedule."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any, Sequence

import numpy as np

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V6_REFERENCE_TEMPO_FALLBACK_LAB_COMPLETE_NON_SHIPPING"
FACTOR = 1.22
BATCH_INDEX = 7
ATTEMPT = 2
ADAPTIVE_TARGET_WORDS_PER_MINUTE = 205
MAXIMUM_ADDITIONAL_PAUSE_MILLISECONDS = 1000
R3_FAILURE_RELATIVE = (
    "native/audio/narration/work/provisional-audit-v6/stress-v6-r3-2026-07-25/"
    "failed-attempts.v6.receipt.json"
)
R3_FAILURE_BYTES = 13_692
R3_FAILURE_SHA256 = (
    "8062c6718c28b2f7820fe5d196f608c1da3e95ee7da1c09b4161e9e2d1ba4920"
)


class FallbackLabError(RuntimeError):
    pass


def rejected_r3_evidence(config: dict[str, Any]) -> dict[str, Any]:
    path = v6.repository_path(R3_FAILURE_RELATIVE, directory=False)
    v6.validate_exact_file(
        path,
        byte_count=R3_FAILURE_BYTES,
        digest=R3_FAILURE_SHA256,
        label="R3 exhausted batch finding",
    )
    receipt = production.load_json(path)
    entries = receipt.get("entries")
    if (
        receipt.get("status") != v6.FAILURE_LOG_STATUS
        or not isinstance(entries, list)
        or len(entries) != 3
        or [item.get("attempt") for item in entries] != [1, 2, 3]
        or any(item.get("candidateID") != "voice-candidate-05" for item in entries)
        or any(item.get("batchIndex") != BATCH_INDEX for item in entries)
        or any(
            item.get("failedUtterances", [{}])[0].get("utteranceID")
            != "utterance-059"
            for item in entries
        )
        or any(
            item["failedUtterances"][0].get("failedGates") != ["maximumTempo"]
            for item in entries
        )
    ):
        raise FallbackLabError("R3 failure receipt no longer proves tempo overshoot")
    return {
        "role": "REJECTED_DIAGNOSTIC_ONLY_NOT_AUDIO_PARENT",
        "receipt": v6.file_binding(path),
        "candidateID": "voice-candidate-05",
        "batchIndex": BATCH_INDEX,
        "attemptsExhausted": 3,
        "failedUtteranceID": "utterance-059",
        "failedGate": "maximumTempo",
        "observedWordsPerMinute": [
            item["failedUtterances"][0]["gate"]["wordsPerMinute"]
            for item in entries
        ],
    }


def render_reference(
    *,
    source: Path,
    destination: Path,
    config: dict[str, Any],
    output_root: Path,
) -> dict[str, Any]:
    source = v5.confined_path(
        source,
        root=v6.repository_path(config["paths"]["candidateSetRoot"], directory=True),
        must_exist=True,
        expect_directory=False,
    )
    destination = v5.confined_path(destination, root=output_root, must_exist=False)
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
        f"atempo={FACTOR:.12f}",
        "-ar",
        "48000",
        "-ac",
        "1",
        "-c:a",
        "pcm_s24le",
        str(destination),
    ]
    subprocess.run(command, check=True, capture_output=True)
    return {
        "factor": FACTOR,
        "method": "one deterministic pitch-preserving ffmpeg atempo pass",
        "source": v6.file_binding(source),
        "derived": v6.file_binding(destination),
        "labOrR3AudioUsed": False,
    }


def apply_adaptive_semantic_pause(
    audio: Any,
    *,
    normalized_word_count: int,
    sample_rate: int,
) -> tuple[Any, dict[str, Any]]:
    material = np.ascontiguousarray(np.asarray(audio, dtype=np.float32).reshape(-1))
    required_samples = int(
        np.ceil(
            normalized_word_count
            / ADAPTIVE_TARGET_WORDS_PER_MINUTE
            * 60
            * sample_rate
        )
    )
    additional = max(0, required_samples - material.size)
    maximum = round(sample_rate * MAXIMUM_ADDITIONAL_PAUSE_MILLISECONDS / 1000)
    if additional > maximum:
        raise FallbackLabError("adaptive semantic pause exceeded its frozen maximum")
    if additional:
        material = np.concatenate(
            [material, np.zeros(additional, dtype=np.float32)]
        )
    return np.ascontiguousarray(material, dtype=np.float32), {
        "targetMaximumWordsPerMinute": ADAPTIVE_TARGET_WORDS_PER_MINUTE,
        "maximumAdditionalPauseMilliseconds": MAXIMUM_ADDITIONAL_PAUSE_MILLISECONDS,
        "additionalPauseSamples": additional,
        "additionalPauseMilliseconds": additional * 1000 / sample_rate,
        "speechTimeStretchApplied": False,
        "zeroSignalOnly": True,
    }


def run_lab(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise FallbackLabError("fallback lab requires --offline")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    config = v6.load_config()
    parent_chain = v6.validate_parent_chain(config)
    negative = v6.validate_v5_negative_evidence(config)
    tempo_evidence = v6.validate_reference_tempo_method_evidence(config)
    rejected = rejected_r3_evidence(config)
    _, stress_record, _, utterances, utterance_record = (
        v6.stress_and_utterance_material(config)
    )
    selected = v6.batch_specs(utterances, config)[BATCH_INDEX]
    if [item["utteranceID"] for item in selected] != [
        f"utterance-{index:03d}" for index in range(56, 64)
    ]:
        raise FallbackLabError("recovery batch text inventory drifted")
    output_root = v6.prepare_audit_root(args.output, config)
    (output_root / "references").mkdir()
    (output_root / "clips").mkdir()
    context = v6._generation_context(config)
    model, extractor = v6._load_runtime(context)
    original_units, _ = v6._reference_material(
        context=context, extractor=extractor, config=config
    )
    records = []
    all_audio_paths = []
    lookup: dict[str, dict[str, Any]] = {}
    for candidate_id in v6.EXPECTED_FINALISTS:
        candidate = context["candidates"][candidate_id]
        parent = context["parentRecords"][candidate_id]
        reference_path = output_root / "references" / f"{candidate_id}-tempo-1p22.wav"
        conditioning = render_reference(
            source=Path(parent["_verifiedReferencePath"]),
            destination=reference_path,
            config=config,
            output_root=output_root,
        )
        reference_audio, reference_decoded = v5._load_reference_audio(
            reference_path, config["master"]["nativeSampleRate"]
        )
        reference_identity = v6._utterance_identity_cosine(
            reference_audio, original_units[candidate_id], extractor
        )
        seed = v6._batch_seed(candidate, BATCH_INDEX, ATTEMPT, config)
        production.set_generation_seed(seed)
        generated = list(
            model.batch_generate(
                texts=[item["text"] for item in selected],
                ref_audio=str(reference_path),
                ref_text=context["identityText"],
                lang_code=context["baseConfig"]["language"],
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
        by_index = {item.sequence_idx: item for item in generated}
        if sorted(by_index) != list(range(len(selected))):
            raise FallbackLabError("fallback batch generation was incomplete")
        clip_keys = []
        for local_index, utterance in enumerate(selected):
            result = by_index[local_index]
            raw = np.ascontiguousarray(
                np.asarray(result.audio, dtype=np.float32).reshape(-1)
            )
            processed, processing = v6.process_utterance_audio(
                raw,
                sample_rate=int(result.sample_rate),
                separator_after=utterance["separatorAfter"],
                config=config,
            )
            processed, adaptive_pacing = apply_adaptive_semantic_pause(
                processed,
                normalized_word_count=utterance["normalizedWordCount"],
                sample_rate=int(result.sample_rate),
            )
            processing = {
                **processing,
                "adaptiveSemanticPauseLab": adaptive_pacing,
                "processedSampleCount": len(processed),
            }
            clip_dir = output_root / "clips" / candidate_id
            clip_dir.mkdir(parents=True, exist_ok=True)
            audio_path = clip_dir / f"{utterance['utteranceID']}.wav"
            production.write_float_wav(audio_path, int(result.sample_rate), processed)
            decoded_audio, decoded = v5.read_native_audio(audio_path, config)
            if not np.array_equal(decoded_audio, processed):
                raise FallbackLabError("fallback clip serialization changed PCM")
            tokenizer_count, token_cap = v6._derived_token_cap(
                model, utterance["text"], config
            )
            key = str(audio_path)
            lookup[key] = {
                "utterance": utterance,
                "audio": processed,
                "decoded": decoded,
                "processing": processing,
                "tokenizerTokenCount": tokenizer_count,
                "tokenCap": token_cap,
                "generatedTokenCount": int(result.token_count),
            }
            all_audio_paths.append(audio_path)
            clip_keys.append(key)
        records.append(
            {
                "candidateID": candidate_id,
                "generationSeed": seed,
                "conditioning": conditioning,
                "referenceDecoded": reference_decoded,
                "referenceIdentityCosineToOriginal": reference_identity,
                "clipKeys": clip_keys,
            }
        )
    transcript_paths, asr = v6.run_whisper_batch(
        audio_paths=all_audio_paths, staging=output_root, config=config
    )
    transcripts = {
        str(Path(str(path)[: -len(".json")])): path for path in transcript_paths
    }
    for record in records:
        clips = []
        for key in record.pop("clipKeys"):
            item = lookup[key]
            transcript_path = transcripts[key]
            identity = v6._utterance_identity_cosine(
                item["audio"],
                original_units[record["candidateID"]],
                extractor,
            )
            gate = v6.utterance_asr_gate(
                utterance=item["utterance"],
                transcript=production.load_json(transcript_path),
                duration_seconds=item["decoded"]["sampleCount"]
                / config["master"]["nativeSampleRate"],
                token_count=item["generatedTokenCount"],
                token_cap=item["tokenCap"],
                identity_cosine=identity,
                config=config,
            )
            clips.append(
                {
                    "utterance": v6._public_utterance(item["utterance"]),
                    "audio": v6.file_binding(Path(key)),
                    "transcript": v6.file_binding(transcript_path),
                    "processing": item["processing"],
                    "tokenizerTokenCount": item["tokenizerTokenCount"],
                    "derivedTokenCap": item["tokenCap"],
                    "generatedTokenCount": item["generatedTokenCount"],
                    "identityCosineToOriginal": identity,
                    "gate": gate,
                }
            )
        record["clips"] = clips
        record["allClipGatesPass"] = all(item["gate"]["passes"] for item in clips)
        record["minimumClipIdentityCosine"] = min(
            item["identityCosineToOriginal"] for item in clips
        )
        record["minimumWordsPerMinute"] = min(
            item["gate"]["wordsPerMinute"] for item in clips
        )
        record["maximumWordsPerMinute"] = max(
            item["gate"]["wordsPerMinute"] for item in clips
        )
    passes = all(
        item["allClipGatesPass"]
        and item["referenceIdentityCosineToOriginal"]
        >= config["utteranceGate"]["minimumIdentityCosineToReference"]
        for item in records
    )
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": v6.TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v6.file_binding(SCRIPT_PATH),
        "v6Method": v6.pipeline_binding(config),
        "parentChain": parent_chain,
        "v5NegativeEvidence": negative,
        "referenceTempoMethodEvidence": tempo_evidence,
        "rejectedR3Evidence": rejected,
        "stressText": stress_record,
        "utteranceManifest": utterance_record,
        "batchIndex": BATCH_INDEX,
        "attempt": ATTEMPT,
        "factor": FACTOR,
        "records": records,
        "asrRun": asr,
        "passesRecoveryLab": passes,
        "proposedAdaptivePacing": {
            "referenceTempoFactor": FACTOR,
            "targetMaximumWordsPerMinute": ADAPTIVE_TARGET_WORDS_PER_MINUTE,
            "unchangedHardGateMaximumWordsPerMinute": config["utteranceGate"][
                "maximumWordsPerMinute"
            ],
            "maximumAdditionalPauseMilliseconds": MAXIMUM_ADDITIONAL_PAUSE_MILLISECONDS,
            "zeroSignalAtAuthoredSemanticBoundaryOnly": True,
            "speechTimeStretchApplied": False,
        },
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }
    receipt_path = output_root / "reference-fallback-lab.v6.receipt.json"
    v6.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v6.file_binding(receipt_path)}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Frozen offline V6 reference-tempo fallback lab"
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--offline", action="store_true", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = run_lab(args)
    except (
        FallbackLabError,
        v6.V6Error,
        v5.V5Error,
        production.PipelineError,
        subprocess.CalledProcessError,
        OSError,
        ValueError,
    ) as error:
        print(f"V6 reference-fallback lab failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
