#!/usr/bin/env python3
"""Deterministic offline reference-tempo conditioning lab for V6 R3.

The lab never approves a voice and never becomes an audio parent.  It changes
only the duration of each already selected clone reference with ffmpeg atempo,
then tests identical text, seeds and gates for both finalists.
"""

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
STATUS = "CODEX_V6_REFERENCE_TEMPO_LAB_COMPLETE_NON_SHIPPING"
TRUST_DOMAIN = v6.TRUST_DOMAIN
FACTORS = [1.18, 1.22, 1.26]
UTTERANCE_INDICES = [0, 17, 35, 52, 70, 87, 105, 122]
LAB_SEED_OFFSET = 7_000_000
R2_ROOT_RELATIVE = (
    "native/audio/narration/work/provisional-audit-v6/"
    "stress-v6-2026-07-25-r2"
)
PRIOR_LAB_RELATIVE = (
    "native/audio/narration/work/provisional-audit-v6/reference-tempo-lab-r1/"
    "reference-tempo-lab.v6.receipt.json"
)
PRIOR_LAB_BYTES = 367_988
PRIOR_LAB_SHA256 = (
    "753cc1e9771fc2f1a6ed94c2f1e4b16232d4d8d4e76f622249d12d905739d728"
)


class TempoLabError(RuntimeError):
    pass


def factor_label(factor: float) -> str:
    return f"tempo-{factor:.2f}".replace(".", "p")


def render_conditioned_reference(
    source: Path,
    destination: Path,
    *,
    factor: float,
    config: dict[str, Any],
    output_root: Path,
) -> dict[str, Any]:
    source = v5.confined_path(
        source,
        root=v6.repository_path(config["paths"]["candidateSetRoot"], directory=True),
        must_exist=True,
        expect_directory=False,
    )
    destination = v5.confined_path(
        destination,
        root=output_root,
        must_exist=False,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
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
    return {
        "factor": factor,
        "method": "one deterministic pitch-preserving ffmpeg atempo pass",
        "source": v6.file_binding(source),
        "conditioned": v6.file_binding(destination),
        "commandSHA256": production.sha256_text(v6.canonical_json(command)),
    }


def r2_baseline(config: dict[str, Any]) -> dict[str, Any]:
    root = v5.confined_path(
        v6.REPOSITORY_ROOT / R2_ROOT_RELATIVE,
        root=v6.work_root(config, create=False),
        must_exist=True,
        expect_directory=True,
    )
    candidate_id = v6.EXPECTED_FINALISTS[0]
    receipts = sorted(
        (root / "batch-commits" / candidate_id).glob("batch-*/batch.v6.receipt.json")
    )
    if len(receipts) != 16:
        raise TempoLabError("R2 diagnostic does not contain all 16 candidate-05 batches")
    sample_count = 0
    receipt_bindings = []
    utterance_count = 0
    for receipt_path in receipts:
        document = production.load_json(receipt_path)
        if (
            document.get("status") != v6.BATCH_STATUS
            or document.get("candidateID") != candidate_id
            or document.get("allUtterancesPassedBeforeCommit") is not True
        ):
            raise TempoLabError("R2 diagnostic batch identity drifted")
        for item in document["utteranceRecords"]:
            audio_path = Path(item["processedAudio"]["file"]["path"])
            if v6.file_binding(audio_path) != item["processedAudio"]["file"]:
                raise TempoLabError("R2 diagnostic utterance binding drifted")
            _, decoded = v5.read_native_audio(audio_path, config)
            if (
                decoded["sampleCount"] != item["processedAudio"]["sampleCount"]
                or decoded["float32LESHA256"]
                != item["processedAudio"]["float32LESHA256"]
                or item["gate"]["passes"] is not True
            ):
                raise TempoLabError("R2 diagnostic utterance no longer passes")
            sample_count += decoded["sampleCount"]
            utterance_count += 1
        receipt_bindings.append(v6.file_binding(receipt_path))
    duration = sample_count / config["master"]["nativeSampleRate"]
    if (
        utterance_count != config["segmentation"]["utteranceCount"]
        or sample_count != 35_063_281
    ):
        raise TempoLabError("R2 diagnostic full-duration finding drifted")
    return {
        "role": "REJECTED_DIAGNOSTIC_ONLY_NOT_R3_PARENT",
        "candidateID": candidate_id,
        "batchReceipts": receipt_bindings,
        "utteranceCount": utterance_count,
        "pretempoSampleCount": sample_count,
        "pretempoDurationSeconds": duration,
        "failedHardMaximumSeconds": config["durationCorrection"][
            "hardMaximumUncorrectedSeconds"
        ],
        "passesDurationCorrectionBound": False,
    }


def prior_lab_rejection(config: dict[str, Any]) -> dict[str, Any]:
    path = v5.confined_path(
        v6.REPOSITORY_ROOT / PRIOR_LAB_RELATIVE,
        root=v6.work_root(config, create=False),
        must_exist=True,
        expect_directory=False,
    )
    v6.validate_exact_file(
        path,
        byte_count=PRIOR_LAB_BYTES,
        digest=PRIOR_LAB_SHA256,
        label="V6 reference-tempo lab R1",
    )
    receipt = production.load_json(path)
    if (
        receipt.get("status") != STATUS
        or receipt.get("factors") != [1.0, 1.06, 1.1, 1.14]
        or receipt.get("qualifyingFactors") != []
        or receipt.get("lowestQualifyingFactor") is not None
        or any(item.get("passesLab") is not False for item in receipt["factorRecords"])
    ):
        raise TempoLabError("prior reference-tempo lab no longer proves rejection")
    return {
        "role": "REJECTED_DIAGNOSTIC_ONLY_NOT_R3_PARENT",
        "receipt": v6.file_binding(path),
        "rejectedFactors": receipt["factors"],
        "qualifyingFactors": [],
    }


def run_lab(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise TempoLabError("reference-tempo lab requires --offline")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    config = v6.load_config()
    parent_chain = v6.validate_parent_chain(config)
    negative = v6.validate_v5_negative_evidence(config)
    v6.validate_master_tools(config)
    v6.validate_asr_tools(config)
    _, stress_record, cues, utterances, utterance_record = (
        v6.stress_and_utterance_material(config)
    )
    selected = [utterances[index] for index in UTTERANCE_INDICES]
    if {item["segmentID"] for item in selected} != {
        cue["segmentID"] for cue in cues
    }:
        raise TempoLabError("tempo lab no longer covers every frozen cue")
    output_root = v6.prepare_audit_root(args.output, config)
    (output_root / "references").mkdir()
    (output_root / "clips").mkdir()
    context = v6._generation_context(config)
    model, extractor = v6._load_runtime(context)
    original_units, original_records = v6._reference_material(
        context=context, extractor=extractor, config=config
    )
    generation_records: list[dict[str, Any]] = []
    audio_paths: list[Path] = []
    audio_lookup: dict[str, dict[str, Any]] = {}
    for candidate_id in v6.EXPECTED_FINALISTS:
        candidate = context["candidates"][candidate_id]
        parent = context["parentRecords"][candidate_id]
        for factor_index, factor in enumerate(FACTORS):
            label = factor_label(factor)
            reference_path = output_root / "references" / f"{candidate_id}-{label}.wav"
            conditioning = render_conditioned_reference(
                Path(parent["_verifiedReferencePath"]),
                reference_path,
                factor=factor,
                config=config,
                output_root=output_root,
            )
            conditioned_audio, conditioned_record = v5._load_reference_audio(
                reference_path, config["master"]["nativeSampleRate"]
            )
            conditioned_identity = v6._utterance_identity_cosine(
                conditioned_audio, original_units[candidate_id], extractor
            )
            seed = candidate["stressSeed"] + LAB_SEED_OFFSET
            production.set_generation_seed(seed)
            results = list(
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
            by_index = {item.sequence_idx: item for item in results}
            if sorted(by_index) != list(range(len(selected))):
                raise TempoLabError("tempo lab generation returned incomplete batch")
            clip_records = []
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
                clip_dir = output_root / "clips" / candidate_id / label
                clip_dir.mkdir(parents=True, exist_ok=True)
                audio_path = clip_dir / f"{utterance['utteranceID']}.wav"
                production.write_float_wav(audio_path, int(result.sample_rate), processed)
                decoded_audio, decoded = v5.read_native_audio(audio_path, config)
                if not np.array_equal(decoded_audio, processed):
                    raise TempoLabError("tempo lab clip serialization changed PCM")
                tokenizer_count, token_cap = v6._derived_token_cap(
                    model, utterance["text"], config
                )
                key = str(audio_path)
                audio_lookup[key] = {
                    "candidateID": candidate_id,
                    "factor": factor,
                    "factorLabel": label,
                    "utterance": utterance,
                    "audio": processed,
                    "decoded": decoded,
                    "processing": processing,
                    "tokenizerTokenCount": tokenizer_count,
                    "tokenCap": token_cap,
                    "generatedTokenCount": int(result.token_count),
                }
                audio_paths.append(audio_path)
                clip_records.append(key)
            generation_records.append(
                {
                    "candidateID": candidate_id,
                    "factor": factor,
                    "factorLabel": label,
                    "generationSeed": seed,
                    "conditioning": conditioning,
                    "conditionedReferenceDecoded": conditioned_record,
                    "conditionedReferenceIdentityCosineToOriginal": conditioned_identity,
                    "clipKeys": clip_records,
                }
            )
    transcript_paths, asr_run = v6.run_whisper_batch(
        audio_paths=audio_paths, staging=output_root, config=config
    )
    transcript_by_audio = {
        str(Path(str(path)[: -len(".json")])): path for path in transcript_paths
    }
    factor_records: list[dict[str, Any]] = []
    for generation in generation_records:
        clips = []
        for key in generation.pop("clipKeys"):
            item = audio_lookup[key]
            transcript_path = transcript_by_audio[key]
            transcript = production.load_json(transcript_path)
            identity = v6._utterance_identity_cosine(
                item["audio"], original_units[item["candidateID"]], extractor
            )
            gate = v6.utterance_asr_gate(
                utterance=item["utterance"],
                transcript=transcript,
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
                    "identityCosineToOriginalReference": identity,
                    "gate": gate,
                }
            )
        duration = sum(item["gate"]["durationSeconds"] for item in clips)
        generation["clips"] = clips
        generation["selectedWordCount"] = sum(
            item["utterance"]["wordCount"] for item in clips
        )
        generation["selectedDurationSeconds"] = duration
        generation["selectedWordsPerMinute"] = (
            generation["selectedWordCount"] / duration * 60
        )
        generation["minimumClipIdentityCosine"] = min(
            item["identityCosineToOriginalReference"] for item in clips
        )
        measured_wers = [
            item["gate"]["alignment"]["wordAlignmentErrorRate"]
            for item in clips
            if item["gate"]["alignment"] is not None
        ]
        generation["maximumClipWER"] = max(measured_wers, default=None)
        generation["allClipGatesPass"] = all(
            item["gate"]["passes"] for item in clips
        )
        factor_records.append(generation)
    r2 = r2_baseline(config)
    prior_lab = prior_lab_rejection(config)
    prior_document = production.load_json(Path(prior_lab["receipt"]["path"]))
    baseline_05 = next(
        item
        for item in prior_document["factorRecords"]
        if item["candidateID"] == "voice-candidate-05" and item["factor"] == 1.0
    )
    for item in factor_records:
        if item["candidateID"] == "voice-candidate-05":
            estimate = r2["pretempoDurationSeconds"] * (
                item["selectedDurationSeconds"]
                / baseline_05["selectedDurationSeconds"]
            )
        else:
            estimate = r2["pretempoDurationSeconds"] * (
                item["selectedDurationSeconds"]
                / baseline_05["selectedDurationSeconds"]
            )
        correction = (
            estimate / config["durationCorrection"]["targetMaximumSeconds"]
            if estimate > config["durationCorrection"]["targetMaximumSeconds"]
            else 1.0
        )
        item["estimatedFullPretempoSeconds"] = estimate
        item["estimatedRequiredMasterTempoFactor"] = correction
        item["estimatedCorrectedFullSeconds"] = estimate / correction
        item["estimatedDurationGate"] = (
            estimate >= config["stressText"]["minimumActualMinutes"] * 60
            and estimate <= config["durationCorrection"]["hardMaximumUncorrectedSeconds"]
            and correction <= config["durationCorrection"]["maximumTempoFactor"]
            and item["estimatedCorrectedFullSeconds"]
            <= config["stressText"]["maximumActualMinutes"] * 60
        )
        item["passesLab"] = item["allClipGatesPass"] and item[
            "conditionedReferenceIdentityCosineToOriginal"
        ] >= config["utteranceGate"]["minimumIdentityCosineToReference"] and item[
            "estimatedDurationGate"
        ]
    qualifying = []
    for factor in FACTORS:
        own = [item for item in factor_records if item["factor"] == factor]
        if len(own) == 2 and all(item["passesLab"] for item in own):
            qualifying.append(factor)
    selected_factor = min(qualifying) if qualifying else None
    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v6.file_binding(SCRIPT_PATH),
        "v6Method": v6.pipeline_binding(config),
        "parentChain": parent_chain,
        "v5NegativeEvidence": negative,
        "r2RejectedDurationEvidence": r2,
        "priorRejectedReferenceTempoLab": prior_lab,
        "stressText": stress_record,
        "utteranceManifest": utterance_record,
        "representativeSet": {
            "indices": UTTERANCE_INDICES,
            "utteranceIDs": [item["utteranceID"] for item in selected],
            "cueIDs": [item["segmentID"] for item in selected],
            "sameTextsForEveryCandidateAndFactor": True,
            "sameSeedWithinEachCandidate": True,
        },
        "factors": FACTORS,
        "factorRecords": factor_records,
        "asrRun": asr_run,
        "qualifyingFactors": qualifying,
        "lowestQualifyingFactor": selected_factor,
        "selectionRule": (
            "lowest factor passing both candidates without weakening any V6 utterance "
            "gate and with estimated 18–22 minute fullmaster under the frozen 3% cap"
        ),
        "networkUsed": False,
        "incrementalCostNOK": 0,
        "editorDecisionStillRequired": True,
        "artisticApprovalStillRequired": True,
        "shippingApproval": False,
        "claimsExcluded": config["claimsExcluded"],
    }
    receipt_path = output_root / "reference-tempo-lab.v6.receipt.json"
    v6.write_json(receipt_path, receipt)
    return {**receipt, "receipt": v6.file_binding(receipt_path)}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Frozen offline V6 reference-tempo conditioning lab"
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--offline", action="store_true", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = run_lab(args)
    except (
        TempoLabError,
        v6.V6Error,
        v5.V5Error,
        production.PipelineError,
        subprocess.CalledProcessError,
        OSError,
        ValueError,
    ) as error:
        print(f"V6 reference-tempo lab failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
