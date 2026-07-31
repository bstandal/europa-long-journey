#!/usr/bin/env python3
"""Fail-closed inventory of already-local alternative narration methods.

This block is deliberately a pre-synthesis gate.  It may inspect installed
executables, cached model snapshots, local licence text and pinned source
code.  It must not download a model, call a hosted service or render speech.
The unchanged V8 fourteen-utterance by two-reference comparison opens only
when one genuinely different method clears every inventory prerequisite.
"""

from __future__ import annotations

import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any

import pipeline as production
import v8_chatterbox_comparison as chatterbox
import v8_pipeline as v8


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V9_LOCAL_ALTERNATIVE_SYNTHESIS_INVENTORY_BLOCKED"
TRUST_DOMAIN = v8.TRUST_DOMAIN
RECEIPT_NAME = "local-synthesis-inventory.v9.receipt.json"

NARRATION_ROOT = SCRIPT_PATH.parent
MLX_AUDIO_ROOT = NARRATION_ROOT / ".venv/lib/python3.14/site-packages"
MLX_MODELS_ROOT = MLX_AUDIO_ROOT / "mlx_audio/tts/models"
MLX_DIST_ROOT = MLX_AUDIO_ROOT / "mlx_audio-0.4.5.dist-info"
HF_CACHE_ROOT = Path.home() / ".cache/huggingface/hub"

APPLE_SAY = Path("/usr/bin/say")
APPLE_SAY_MANPAGE = Path("/usr/share/man/man1/say.1")
APPLE_SLA = Path(
    "/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/"
    "en.lproj/OSXSoftwareLicense.html"
)
APPLE_EXACT_BINDINGS = {
    "binary": {
        "bytes": 197824,
        "sha256": "480d4f1678034fa65a023502b4bc0330430dcd48cd7f584e746772635113b353",
    },
    "manpage": {
        "bytes": 10552,
        "sha256": "3ca47b61cb9db7df543732ce64d8acced6f846dae2c9c1852e74332bc8518140",
    },
    "licence": {
        "bytes": 97187,
        "sha256": "968f97210d609dbd8087f8da9e33a80f6f1b99e888a1cea2edc0b33a043bddcb",
    },
}

EXECUTABLE_NAMES = (
    "say",
    "piper",
    "espeak",
    "espeak-ng",
    "mimic3",
    "festival",
    "flite",
    "kokoro-tts",
    "edge-tts",
)

BASELINE_RECEIPTS = {
    "qwenTechnicalProbe": (
        "native/audio/narration/probes/technical-2026-07-24/"
        "technical-probe.receipt.json"
    ),
    "chatterboxPreflight": (
        "native/audio/narration/work/provisional-audit-v8/"
        "chatterbox-comparison-preflight-r1-2026-07-25/"
        "chatterbox-comparison-preflight.v8.receipt.json"
    ),
    "chatterboxComparison": (
        "native/audio/narration/work/provisional-audit-v8/"
        "chatterbox-comparison-r1-2026-07-25/"
        "chatterbox-comparison.v8.receipt.json"
    ),
}

SOURCE_CANDIDATES = (
    {
        "candidateID": "mlx-kokoro-code-only",
        "rank": 2,
        "relativeSource": "kokoro/kokoro.py",
        "requiredEvidence": (
            "duration = mx.sigmoid(duration).sum(axis=-1) / speed",
            "speed: float = 1.0",
        ),
        "referenceConditioning": False,
        "nativeRateControl": True,
        "nativeAuthoredPauseControl": False,
        "reason": (
            "The installed runtime exposes native duration scaling, but no "
            "Kokoro weights or voices are cached and it cannot condition on "
            "the two frozen finalist references."
        ),
    },
    {
        "candidateID": "mlx-melotts-code-only",
        "rank": 3,
        "relativeSource": "melotts/melotts.py",
        "requiredEvidence": (
            "w = mx.exp(logw) * x_mask * (1.0 / speed)",
            "speed: float = 1.0",
        ),
        "referenceConditioning": False,
        "nativeRateControl": True,
        "nativeAuthoredPauseControl": False,
        "reason": (
            "The installed runtime exposes native duration scaling, but no "
            "MeloTTS model is cached, no model-weight licence is locally "
            "bound and the runtime does not clone the frozen references."
        ),
    },
    {
        "candidateID": "mlx-indextts-code-only",
        "rank": 4,
        "relativeSource": "indextts/indextts.py",
        "requiredEvidence": (
            "ref_audio: Optional[Union[str, mx.array]]",
            "Must provide one of ref_audio or ref_mel",
        ),
        "referenceConditioning": True,
        "nativeRateControl": False,
        "nativeAuthoredPauseControl": False,
        "reason": (
            "The installed code accepts reference audio, but no IndexTTS "
            "weights or model licence are cached and this runtime exposes no "
            "model-native rate or authored-pause control."
        ),
    },
    {
        "candidateID": "mlx-dia-code-only",
        "rank": 5,
        "relativeSource": "dia/dia.py",
        "requiredEvidence": (
            "ref_audio: Optional[Union[str, mx.array]] = None",
            "audio_prompt_codebook",
        ),
        "referenceConditioning": True,
        "nativeRateControl": False,
        "nativeAuthoredPauseControl": False,
        "reason": (
            "The installed code accepts an audio prompt, but no Dia weights "
            "or model licence are cached and this runtime exposes no "
            "model-native rate or authored-pause control."
        ),
    },
    {
        "candidateID": "mlx-voxcpm2-code-only",
        "rank": 6,
        "relativeSource": "voxcpm2/voxcpm2.py",
        "requiredEvidence": (
            "Generate audio from text with optional voice cloning.",
            "Reference cloning: ref_audio + text",
        ),
        "referenceConditioning": True,
        "nativeRateControl": False,
        "nativeAuthoredPauseControl": False,
        "reason": (
            "The installed code supports reference cloning, but no VoxCPM2 "
            "weights or model licence are cached and this runtime exposes no "
            "model-native rate or authored-pause control."
        ),
    },
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _binding(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise v8.V8Error(f"required local evidence is unavailable: {path}")
    return {
        "path": str(path.absolute()),
        "bytes": path.stat().st_size,
        "sha256": _sha256(path),
    }


def _validate_exact(path: Path, expected: dict[str, Any], label: str) -> dict[str, Any]:
    binding = _binding(path)
    if (
        binding["bytes"] != expected["bytes"]
        or binding["sha256"] != expected["sha256"]
    ):
        raise v8.V8Error(f"{label} bytes drifted")
    return binding


class _ParagraphParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._inside = False
        self._parts: list[str] = []
        self.paragraphs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        del attrs
        if tag == "p":
            self._inside = True
            self._parts = []

    def handle_data(self, data: str) -> None:
        if self._inside:
            self._parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "p" and self._inside:
            text = re.sub(r"\s+", " ", "".join(self._parts)).strip()
            self.paragraphs.append(text)
            self._inside = False
            self._parts = []


def apple_voice_licence() -> dict[str, Any]:
    binding = _validate_exact(
        APPLE_SLA, APPLE_EXACT_BINDINGS["licence"], "local macOS licence"
    )
    parser = _ParagraphParser()
    parser.feed(APPLE_SLA.read_text(encoding="utf-8"))
    sections = [
        item for item in parser.paragraphs if item.startswith("F. Voices; Live Captions")
    ]
    if len(sections) != 1:
        raise v8.V8Error("cannot isolate macOS section 2.F voice licence")
    section = sections[0]
    required = {
        "systemVoicesDefined": "System Voices" in section,
        "personalNonCommercialOnly": "personal, non-commercial use" in section,
        "otherUseNotPermitted": (
            "No other creation or use of the System Voices" in section
            and "is permitted by this License" in section
        ),
        "commercialContextExplicitlyIncluded": "commercial context" in section,
        "recordingPublishingRedistributionExplicitlyIncluded": all(
            word in section for word in ("recording", "publishing", "redistribution")
        ),
    }
    if not all(required.values()):
        raise v8.V8Error("macOS voice restriction evidence drifted")
    return {
        "document": binding,
        "documentTitle": "Apple Software License Agreement for macOS Tahoe 26",
        "section": "2.F Voices; Live Captions",
        "sectionTextSHA256": production.sha256_text(section),
        "restrictionMatches": required,
        "commercialProductionPermitted": False,
        "diagnosticProjectAudioPermitted": False,
        "finding": (
            "The locally installed System Voices may not be recorded, "
            "published or redistributed for this commercial product."
        ),
    }


def _source_evidence(relative: str, needles: tuple[str, ...]) -> dict[str, Any]:
    path = MLX_MODELS_ROOT / relative
    binding = _binding(path)
    lines = path.read_text(encoding="utf-8").splitlines()
    matches: list[dict[str, Any]] = []
    for needle in needles:
        found = [index + 1 for index, line in enumerate(lines) if needle in line]
        if not found:
            raise v8.V8Error(f"runtime-control evidence drifted: {path}: {needle}")
        line = lines[found[0] - 1].strip()
        matches.append(
            {
                "needleSHA256": production.sha256_text(needle),
                "lineNumber": found[0],
                "lineSHA256": production.sha256_text(line),
            }
        )
    return {"file": binding, "evidence": matches}


def apple_say_runtime(licence: dict[str, Any]) -> dict[str, Any]:
    binary = _validate_exact(
        APPLE_SAY, APPLE_EXACT_BINDINGS["binary"], "Apple say executable"
    )
    manpage = _validate_exact(
        APPLE_SAY_MANPAGE,
        APPLE_EXACT_BINDINGS["manpage"],
        "Apple say manpage",
    )
    manual = APPLE_SAY_MANPAGE.read_text(encoding="utf-8")
    control_matches = {
        "nativeRateWordsPerMinute": (
            "Speech rate to be used, in words per minute." in manual
            and "\\-r rate" in manual
        ),
        "nativeInlineSilenceMilliseconds": "[[slnc 200]]" in manual,
    }
    if not all(control_matches.values()):
        raise v8.V8Error("Apple say native-control documentation drifted")
    completed = subprocess.run(
        [str(APPLE_SAY), "-v", "?"],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, "LC_ALL": "C.UTF-8"},
    )
    voices: list[dict[str, str]] = []
    for line in completed.stdout.splitlines():
        match = re.match(r"^(.*?)\s+([a-z]{2}_[A-Z]{2})\s+#", line)
        if match and match.group(2).startswith("en_"):
            voices.append({"voice": match.group(1).strip(), "locale": match.group(2)})
    if not voices:
        raise v8.V8Error("no installed English Apple System Voice was enumerated")
    return {
        "candidateID": "apple-speech-synthesis",
        "rank": 1,
        "binary": binary,
        "manpage": manpage,
        "installedEnglishVoiceCount": len(voices),
        "installedEnglishVoices": voices,
        "voiceInventorySHA256": production.sha256_text(
            v8.canonical_json(voices)
        ),
        "genuinelyDifferentFromQwenAndChatterbox": True,
        "installedRuntimeAndWeights": True,
        "offlineCapable": True,
        "nativeRateControl": control_matches["nativeRateWordsPerMinute"],
        "nativeAuthoredPauseControl": control_matches[
            "nativeInlineSilenceMilliseconds"
        ],
        "conditionsOnBothFrozenReferences": False,
        "commerciallyPermissiveExactBytes": licence[
            "commercialProductionPermitted"
        ],
        "licence": licence,
        "eligible": False,
        "hardBlocks": [
            "The bound macOS 26 section 2.F prohibits commercial recording, publishing and redistribution of System Voices.",
            "Apple System Voices cannot condition on the two exact frozen finalist references, so the unchanged identity gate cannot be run.",
        ],
        "synthesisExecuted": False,
    }


def _snapshot_manifest(snapshot: Path) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    for path in sorted(item for item in snapshot.rglob("*") if item.is_file()):
        resolved = path.resolve()
        records.append(
            {
                "path": path.relative_to(snapshot).as_posix(),
                "bytes": path.stat().st_size,
                "blobID": resolved.name if path.is_symlink() else _sha256(path),
                "symlink": path.is_symlink(),
            }
        )
    joined = "\n".join(
        f"{item['path']}\0{item['bytes']}\0{item['blobID']}\0{item['symlink']}"
        for item in records
    )
    return {
        "revision": snapshot.name,
        "fileCount": len(records),
        "totalLogicalBytes": sum(item["bytes"] for item in records),
        "fileManifestSHA256": production.sha256_text(joined),
        "allSnapshotFilesResolve": True,
    }


def hf_cache_inventory(root: Path = HF_CACHE_ROOT) -> dict[str, Any]:
    if not root.is_dir():
        raise v8.V8Error(f"Hugging Face cache is unavailable: {root}")
    models: list[dict[str, Any]] = []
    for model_root in sorted(root.glob("models--*")):
        if not model_root.is_dir():
            continue
        encoded = model_root.name.removeprefix("models--")
        model_id = encoded.replace("--", "/", 1)
        snapshots_root = model_root / "snapshots"
        snapshots = (
            [_snapshot_manifest(item) for item in sorted(snapshots_root.iterdir()) if item.is_dir()]
            if snapshots_root.is_dir()
            else []
        )
        models.append(
            {
                "modelID": model_id,
                "cachePath": str(model_root),
                "snapshotCount": len(snapshots),
                "snapshots": snapshots,
            }
        )
    tts_ids = {
        "ResembleAI/chatterbox-turbo",
        "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
        "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
        "mlx-community/chatterbox-turbo-fp16",
    }
    codec_ids = {"mlx-community/S3TokenizerV2"}
    return {
        "root": str(root),
        "modelRootCount": len(models),
        "models": models,
        "cachedSynthesisModelIDs": [
            item["modelID"] for item in models if item["modelID"] in tts_ids
        ],
        "cachedCodecModelIDs": [
            item["modelID"] for item in models if item["modelID"] in codec_ids
        ],
        "cachedAlternativeSynthesisModelIDs": [],
        "finding": (
            "Every locally cached speech-synthesis snapshot belongs to the "
            "already-tested Qwen or Chatterbox families."
        ),
    }


def executable_inventory() -> dict[str, Any]:
    records = []
    for name in EXECUTABLE_NAMES:
        located = shutil.which(name)
        records.append(
            {
                "name": name,
                "installed": located is not None,
                "path": located,
            }
        )
    return {
        "commands": records,
        "installedAlternativeSpeechCommands": [
            item["name"] for item in records if item["installed"]
        ],
    }


def code_only_candidates() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for candidate in SOURCE_CANDIDATES:
        evidence = _source_evidence(
            candidate["relativeSource"], candidate["requiredEvidence"]
        )
        record = {
            "candidateID": candidate["candidateID"],
            "rank": candidate["rank"],
            "genuinelyDifferentFromQwenAndChatterbox": True,
            "installedRuntimeCode": True,
            "installedRuntimeAndWeights": False,
            "cachedModelSnapshotIDs": [],
            "modelWeightLicenceBound": False,
            "commerciallyPermissiveExactBytes": False,
            "offlineCapable": False,
            "nativeRateControl": candidate["nativeRateControl"],
            "nativeAuthoredPauseControl": candidate[
                "nativeAuthoredPauseControl"
            ],
            "conditionsOnBothFrozenReferences": candidate[
                "referenceConditioning"
            ],
            "sourceEvidence": evidence,
            "eligible": False,
            "hardBlocks": [candidate["reason"]],
            "synthesisExecuted": False,
        }
        records.append(record)
    return records


def _baseline_evidence() -> dict[str, Any]:
    bindings: dict[str, Any] = {}
    for label, relative in BASELINE_RECEIPTS.items():
        bindings[label] = _binding(v8.repository_path(relative, directory=False))
    probe = production.load_json(Path(bindings["qwenTechnicalProbe"]["path"]))
    chatterbox_preflight = production.load_json(
        Path(bindings["chatterboxPreflight"]["path"])
    )
    chatterbox_result = production.load_json(
        Path(bindings["chatterboxComparison"]["path"])
    )
    if (
        set(probe.get("models", {})) != {"voiceDesign", "voiceClone"}
        or chatterbox_preflight.get("passesPreflight") is not True
        or chatterbox_result.get("passesRepresentativeComparison") is not False
    ):
        raise v8.V8Error("baseline narration evidence drifted")
    return {
        "bindings": bindings,
        "excludedFamilies": ["Qwen3-TTS", "Chatterbox-Turbo"],
        "qwenAlreadyTested": True,
        "chatterboxAlreadyTested": True,
        "chatterboxRepresentativeComparisonPassed": False,
        "purpose": (
            "These receipts bind installed baseline bytes and prior results; "
            "neither family can satisfy the requirement for a genuinely "
            "different next method."
        ),
    }


def frozen_comparison_contract(config: dict[str, Any]) -> dict[str, Any]:
    selected, representative = chatterbox._selected_material(config)
    references, _ = chatterbox._reference_bindings()
    if len(selected) != 14 or set(references) != set(v8.EXPECTED_FINALISTS):
        raise v8.V8Error("frozen fourteen-by-two comparison contract drifted")
    return {
        "utteranceCountPerReference": 14,
        "referenceCount": 2,
        "requiredSynthesisCount": 28,
        "representativeSet": representative,
        "utterances": [
            {
                "utteranceID": item["utteranceID"],
                "segmentID": item["segmentID"],
                "textSHA256": item["textSHA256"],
                "normalizedWordCount": item["normalizedWordCount"],
            }
            for item in selected
        ],
        "references": references,
        "unchangedQualityGates": config["pauseDensityLab"],
        "sameGateForBothReferences": True,
        "candidateMustClearInventoryBeforeSynthesis": True,
    }


def _candidate_gate(candidates: list[dict[str, Any]]) -> dict[str, Any]:
    eligibility_fields = (
        "genuinelyDifferentFromQwenAndChatterbox",
        "installedRuntimeAndWeights",
        "commerciallyPermissiveExactBytes",
        "offlineCapable",
        "nativeRateControl",
        "nativeAuthoredPauseControl",
        "conditionsOnBothFrozenReferences",
    )
    eligible = [
        item["candidateID"]
        for item in candidates
        if all(item.get(field) is True for field in eligibility_fields)
    ]
    if eligible:
        raise v8.V8Error(
            "inventory found an eligible candidate; this blocked receipt must be replaced by an explicit synthesis method"
        )
    ranked = sorted(candidates, key=lambda item: item["rank"])
    return {
        "eligibilityFields": list(eligibility_fields),
        "assessedCandidateIDsByProbability": [
            item["candidateID"] for item in ranked
        ],
        "highestProbabilityAssessedCandidateID": ranked[0]["candidateID"],
        "highestProbabilityCandidateWasSelected": False,
        "highestProbabilityHardBlocks": ranked[0]["hardBlocks"],
        "eligibleCandidateIDs": eligible,
        "selectedCandidateID": None,
        "passesInventoryGate": False,
    }


def inventory(args: argparse.Namespace) -> dict[str, Any]:
    if args.offline is not True:
        raise v8.V8Error("local synthesis inventory requires --offline")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["DO_NOT_TRACK"] = "1"

    config = v8.load_config()
    output = v8.prepare_output(args.output, config)
    licence = apple_voice_licence()
    apple = apple_say_runtime(licence)
    cache = hf_cache_inventory()
    commands = executable_inventory()
    code_candidates = code_only_candidates()
    candidates = [apple, *code_candidates]
    candidate_gate = _candidate_gate(candidates)
    comparison = frozen_comparison_contract(config)
    baseline = _baseline_evidence()
    dependencies = v8.validate_dependencies(config)

    if cache["cachedAlternativeSynthesisModelIDs"] or commands[
        "installedAlternativeSpeechCommands"
    ] != ["say"]:
        raise v8.V8Error("local alternative synthesis inventory drifted")

    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "v8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "v8Config": v8.file_binding(v8.CONFIG_PATH),
        "v8ValidatedDependencies": dependencies,
        "baselineEvidence": baseline,
        "frozenFourteenByTwoComparison": comparison,
        "huggingFaceCache": cache,
        "executableInventory": commands,
        "mlxAudioDistribution": {
            "package": "mlx-audio",
            "version": "0.4.5",
            "codeLicence": "MIT",
            "metadata": _binding(MLX_DIST_ROOT / "METADATA"),
            "licence": _binding(MLX_DIST_ROOT / "licenses/LICENSE"),
            "modelWeightsIncludedInPackage": False,
        },
        "candidates": candidates,
        "candidateGate": candidate_gate,
        "inventoryScope": {
            "newNetworkDownloadsPermitted": False,
            "newNetworkDownloadsMade": False,
            "hostedAPIsPermitted": False,
            "paidAPIUsed": False,
            "incrementalCostNOK": 0,
            "licenceAmbiguityFailsClosed": True,
            "missingWeightsFailClosed": True,
            "postSynthesisRateRepairPermitted": False,
            "postSynthesisPauseRepairPermitted": False,
        },
        "synthesisExecuted": False,
        "audioFilesCreated": 0,
        "representativeGateRun": False,
        "representativeComparisonPermitted": False,
        "fullGenerationPermitted": False,
        "completeMasterCount": 0,
        "candidatePromoted": False,
        "editorVoiceSelection": False,
        "finalPronunciationApproval": False,
        "artisticApproval": False,
        "shippingApproval": False,
        "blockingFinding": (
            "No already-local method is simultaneously commercially "
            "permissive, genuinely different, reference-conditioned and "
            "equipped with model-native rate and authored-pause control. "
            "The unchanged 14 x 2 audio gate therefore cannot lawfully or "
            "technically begin without adding new locally licensed model bytes."
        ),
    }
    receipt_path = output / RECEIPT_NAME
    v8.write_json(receipt_path, receipt)
    audio_extensions = {".wav", ".aif", ".aiff", ".caf", ".m4a", ".mp3"}
    if any(path.suffix.lower() in audio_extensions for path in output.rglob("*")):
        raise v8.V8Error("inventory unexpectedly created audio")
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--offline", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        receipt = inventory(parse_args(sys.argv[1:] if argv is None else argv))
    except (OSError, subprocess.SubprocessError, v8.V8Error) as error:
        print(f"v9 local synthesis inventory failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
