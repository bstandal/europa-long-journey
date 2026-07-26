#!/usr/bin/env python3
"""Frozen one-take VoxCPM2 representative method; no synthesis entry point.

This module binds the only V11 call shape that may enter the unchanged V8
14-by-2 gate. Importing or validating it never loads a model or creates audio.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import v8_chatterbox_comparison as v8_comparison
import v8_pipeline as v8
import v11_narration_candidate_preflight as candidate_gate


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
STATUS = "CODEX_V11_VOXCPM2_ONE_TAKE_METHOD_BOUND"
EXPECTED_FINALISTS = ("voice-candidate-05", "voice-candidate-06")
CONTROL_INSTRUCTION = (
    "(measured pace, calm authority, clear articulation, restrained expression)"
)
MODEL_INITIALISATION = {
    "constructor": "VoxCPM",
    "modelPath": "exact local snapshot/model",
    "zipenhancerModelPath": None,
    "enableDenoiser": False,
    "optimize": False,
    "device": "mps",
    "loraConfig": None,
    "loraWeightsPath": None,
    "runtimeDtype": "float32",
}
GENERATION_SETTINGS = {
    "cfgValue": 2.0,
    "inferenceTimesteps": 10,
    "minLen": 2,
    "maxLen": 4096,
    "normalize": False,
    "denoise": False,
    "retryBadcase": False,
    "streaming": False,
    "sameReferencePassedAsPromptAndIsolatedReference": True,
    "exactTranscriptPassedAsPromptText": True,
    "oneModelGenerateCallPerUtterance": True,
    "alternativeTakesPermitted": False,
    "retryPermitted": False,
    "thresholdChangePermitted": False,
    "speechTimeStretchPermitted": False,
    "internalSilenceTrimPermitted": False,
    "seedBase": 11_000_000,
    "seedCandidateStride": 100_000,
    "seedUtteranceStride": 10,
}


class MethodError(RuntimeError):
    """Raised when the frozen V11 one-take method drifts."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _binding(path: Path) -> dict[str, Any]:
    return {
        "path": str(path.absolute()),
        "bytes": path.stat().st_size,
        "sha256": _sha256(path),
    }


def generation_seed(candidate_index: int, utterance_index: int) -> int:
    if candidate_index not in (0, 1) or utterance_index not in range(14):
        raise MethodError("V11 seed request escaped the exact 14-by-2 grid")
    return (
        GENERATION_SETTINGS["seedBase"]
        + candidate_index * GENERATION_SETTINGS["seedCandidateStride"]
        + utterance_index * GENERATION_SETTINGS["seedUtteranceStride"]
    )


def generation_kwargs(reference_path: Path, transcript: str, text: str) -> dict[str, Any]:
    return {
        "text": CONTROL_INSTRUCTION + text,
        "prompt_wav_path": str(reference_path.absolute()),
        "prompt_text": transcript,
        "reference_wav_path": str(reference_path.absolute()),
        "cfg_value": GENERATION_SETTINGS["cfgValue"],
        "inference_timesteps": GENERATION_SETTINGS["inferenceTimesteps"],
        "min_len": GENERATION_SETTINGS["minLen"],
        "max_len": GENERATION_SETTINGS["maxLen"],
        "normalize": GENERATION_SETTINGS["normalize"],
        "denoise": GENERATION_SETTINGS["denoise"],
        "retry_badcase": GENERATION_SETTINGS["retryBadcase"],
    }


def validate() -> dict[str, Any]:
    candidate_gate.validate()
    gate = json.loads(candidate_gate.GATE_PATH.read_text(encoding="utf-8"))
    transcript_record = gate["frozenInputs"]["referenceTranscript"]
    transcript_path = REPOSITORY_ROOT / transcript_record["path"]
    if (
        not transcript_path.is_file()
        or _binding(transcript_path)["bytes"] != transcript_record["bytes"]
        or _binding(transcript_path)["sha256"] != transcript_record["sha256"]
    ):
        raise MethodError("V11 exact reference transcript drifted")
    transcript = transcript_path.read_text(encoding="utf-8")

    selected, representative = v8_comparison._selected_material(v8.load_config())
    if len(selected) != 14 or representative["utteranceCount"] != 14:
        raise MethodError("V11 representative set escaped the frozen V8 fourteen")
    references = gate["frozenInputs"]["references"]
    if [item["candidateID"] for item in references] != list(EXPECTED_FINALISTS):
        raise MethodError("V11 finalist order drifted")

    calls = []
    seeds = set()
    for candidate_index, reference in enumerate(references):
        reference_path = REPOSITORY_ROOT / reference["path"]
        binding = _binding(reference_path)
        if (
            binding["bytes"] != reference["bytes"]
            or binding["sha256"] != reference["sha256"]
        ):
            raise MethodError(f"V11 reference drifted: {reference['candidateID']}")
        for utterance_index, utterance in enumerate(selected):
            seed = generation_seed(candidate_index, utterance_index)
            if seed in seeds:
                raise MethodError("V11 generation seed was reused")
            seeds.add(seed)
            kwargs = generation_kwargs(reference_path, transcript, utterance["text"])
            if (
                kwargs["prompt_wav_path"] != kwargs["reference_wav_path"]
                or kwargs["prompt_text"] != transcript
                or kwargs["retry_badcase"] is not False
                or kwargs["normalize"] is not False
                or kwargs["denoise"] is not False
            ):
                raise MethodError("V11 reference, transcript or one-take call drifted")
            calls.append(
                {
                    "candidateID": reference["candidateID"],
                    "utteranceID": utterance["utteranceID"],
                    "seed": seed,
                    "reference": binding,
                    "targetTextSHA256": hashlib.sha256(
                        kwargs["text"].encode("utf-8")
                    ).hexdigest(),
                }
            )
    if len(calls) != 28 or len(seeds) != 28:
        raise MethodError("V11 call inventory is not exactly fourteen by two")
    return {
        "status": STATUS,
        "trustDomain": candidate_gate.TRUST_DOMAIN,
        "modelInitialisation": MODEL_INITIALISATION,
        "generationSettings": GENERATION_SETTINGS,
        "controlInstruction": CONTROL_INSTRUCTION,
        "transcript": _binding(transcript_path),
        "representativeSet": representative,
        "callCount": len(calls),
        "uniqueSeedCount": len(seeds),
        "calls": calls,
        "unchangedV8Thresholds": gate["frozenInputs"]["thresholds"],
        "generatedAudio": False,
        "comparisonSynthesisPermittedOnlyAfterRuntimeAndModelLoadGate": True,
        "fullGenerationPermitted": False,
    }


if __name__ == "__main__":
    print(json.dumps(validate(), sort_keys=True))
