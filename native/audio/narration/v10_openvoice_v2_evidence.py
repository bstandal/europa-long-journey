#!/usr/bin/env python3
"""Validate the durable compact V10 negative-evidence record."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
EVIDENCE_PATH = NARRATION_ROOT / "v10-openvoice-negative-evidence.json"
COST_REGISTRY = REPOSITORY_ROOT / "native/tooling/registries/cost-license.json"


class EvidenceError(RuntimeError):
    """Raised when the frozen V10 record or one of its live bindings drifts."""


EXPECTED_RECEIPTS = [
    (
        "primarySource",
        "CODEX_V10_OPENVOICE_V2_PRIMARY_SOURCE_GATE_PASSED",
        "native/audio/narration/work/provisional-audit-v8/openvoice-v2-primary-source-gate-r1-2026-07-25/openvoice-v2-primary-source-gate.v10.receipt.json",
        130799,
        "c68515bcb328040585c9fa6e43a51580986979092fdc56086d471211c40e5924",
    ),
    (
        "exactSnapshot",
        "CODEX_V10_OPENVOICE_V2_EXACT_SNAPSHOT_VERIFIED",
        "native/audio/narration/work/provisional-audit-v8/openvoice-v2-exact-snapshot-r1-2026-07-25/openvoice-v2-exact-snapshot.v10.receipt.json",
        15463,
        "4d46640d7b653305a686cbf64b040807a95843d4fba13b0a6bd5766eeb26c765",
    ),
    (
        "runtime",
        "CODEX_V10_OPENVOICE_V2_CPU_RUNTIME_AND_LICENCES_VERIFIED",
        "native/audio/narration/work/provisional-audit-v8/openvoice-v2-runtime-r1-2026-07-25/openvoice-v2-runtime-audit.v10.receipt.json",
        141772,
        "4d643d6c4494d0e599e290ac4099a431aae2e49527bd1a3c3601fa4a1407a8cc",
    ),
    (
        "pronunciation",
        "CODEX_V10_OPENVOICE_PRONUNCIATION_GATE_PASSED",
        "native/audio/narration/work/provisional-audit-v8/openvoice-v2-pronunciation-gate-r1-2026-07-25/openvoice-v2-pronunciation-gate.v10.receipt.json",
        115760,
        "985a15b5660bc92bf69df34beb223fd59635e30479379e7caf7568bf207ae828",
    ),
    (
        "modelLoad",
        "CODEX_V10_OPENVOICE_EXACT_CPU_MODEL_LOAD_PASSED",
        "native/audio/narration/work/provisional-audit-v8/openvoice-v2-model-load-r1-2026-07-25/openvoice-v2-model-load.v10.receipt.json",
        8031,
        "cece9edc56cffc49ba95d842561143a54708c48263f4a6653d9ce296e57be97c",
    ),
    (
        "generation",
        "CODEX_V10_OPENVOICE_FROZEN_14_BY_2_SYNTHESISED_NON_SHIPPING",
        "native/audio/narration/work/provisional-audit-v8/openvoice-v2-comparison-generation-r1-2026-07-25/openvoice-v2-generation.v10.receipt.json",
        415917,
        "a82ef6a4da63f741fb2c371fbd5b8f3d16d7d96548f8b1820d0a1702977941c5",
    ),
    (
        "audit",
        "CODEX_V10_OPENVOICE_UNCHANGED_14_BY_2_GATE_BLOCKED",
        "native/audio/narration/work/provisional-audit-v8/openvoice-v2-comparison-audit-r1-2026-07-25/openvoice-v2-comparison-audit.v10.receipt.json",
        229314,
        "91e92cc683bacc4c6d3c83db2161b6d9ad261b308358ae5f4764563f8fe01418",
    ),
]

EXPECTED_SOURCE_BINDINGS = {
    "native/audio/narration/v10_openvoice_v2_preflight.py": (28992, "30f2fdba8cc3316f9af160aff96e25ce28fc77f9c73f786392dea382f433ce55"),
    "native/audio/narration/v10_openvoice_v2_snapshot.py": (7695, "05e5ca1d42096808120a1041adb2c7ed34e3fee83795c2b5eeb3335c34964edd"),
    "native/audio/narration/v10-openvoice-runtime-requirements.in": (369, "2c98a17f4bc7e4c1040a563959d02e4cea2a97ebfd1a344e1c3cf99d28170de5"),
    "native/audio/narration/v10-openvoice-runtime-requirements.lock": (81934, "9551473de973eca87b0c05503199dbf0db42cf957eefa1c1279ec289905f761e"),
    "native/audio/narration/v10-openvoice-runtime-macos-arm64.lock": (4235, "a85d007aa0bb8ef5aa636b18d09955caac452610445559e03f6064528f08e2e3"),
    "native/audio/narration/v10_openvoice_v2_runtime_audit.py": (17840, "d54fff9b4fbcb3951c036daa6fc9431b3e1ddfa59b01713408a64a4d63c49af3"),
    "native/audio/narration/v10-openvoice-pronunciations.json": (3152, "4902f69058c79b5274b3ee9cb879d6ff5f9d8d8b09413e19052cea3e32762cc6"),
    "native/audio/narration/v10_openvoice_v2_pronunciation_gate.py": (14434, "35e5f70aac3e700ddd27be7acf749b35889215c2cd2a88056f38824369680d32"),
    "native/audio/narration/v10_openvoice_v2_model_load_probe.py": (13705, "ef7976c9a3b38fb24a756aefa75b2c81d1cb40d3a39e4388fee9d09c2b5f563a"),
    "native/audio/narration/v10-openvoice-method-config.json": (2142, "0dde10f3a0474f19ed7df87a1b832f68545cfaaeb3bb153b5c52a85b00635679"),
    "native/audio/narration/v10_openvoice_v2_adapter.py": (13122, "1bfaac4965c5a155a0e971257e53d7a7b64c69bdcd02d4eaf5cea67e06bdcedb"),
    "native/audio/narration/v10_openvoice_v2_generate_comparison.py": (12296, "ff202dfb7eab0ae4e4fb8db30f414978b0d3103e60a628cc5ba103b8cce40079"),
    "native/audio/narration/v10_openvoice_v2_audit_comparison.py": (11903, "c75df3bfb58b9d294a068c647e1d9506d5230019fe7a18be27e49d8ad4afc9ed"),
    "native/audio/narration/v8_chatterbox_comparison.py": (33424, "a96c8ce1576c17d1ca944ee221bba4dcd1d0090e5ad4db7852a1e3db583341f6"),
    "native/audio/narration/v8-method-config.json": (7879, "43c436765f5d82ed8a9175e57c1c41bc66e0b6d5c51bb4e90ee4a2661997d4fc"),
    "native/audio/narration/v6_pipeline.py": (150416, "293f1a77cc1ef007b2257500a3d4672b6230c4add4d3fa2284f98c9c86e0dc32"),
    "native/audio/narration/v6-audit-config.json": (11951, "c7eeb28602fc46fb2538aee770d31302955bacefc7888f85cbf58ee2038bcc13"),
}

EXPECTED_THRESHOLDS = {
    "minimumUtteranceIdentityCosine": 0.98,
    "maximumAggregateWordErrorRate": 0.03,
    "maximumModelRetainedSilenceFraction": 0.1,
    "maximumRepresentativeMontageSilenceFraction": 0.115,
    "minimumProjectedFullDurationSeconds": 1080,
    "maximumProjectedFullDurationSeconds": 1320,
}

EXPECTED_RESULTS = [
    {
        "candidateID": "voice-candidate-05",
        "passes": False,
        "allUtteranceGates": True,
        "minimumUtteranceIdentityCosine": 0.9802075624465942,
        "aggregateWordErrorRate": 0.05627705627705628,
        "missingCriticalWords": ["habsburg", "polis", "roman"],
        "modelRetainedSilenceFraction": 0.1596847781003733,
        "representativeMontageSilenceFraction": 0.17179356157383752,
        "projectedFullDurationSeconds": 1449.0737525252525,
        "failedGates": [
            "maximumAggregateWordErrorRate",
            "criticalPronunciationWords",
            "maximumModelRetainedSilenceFraction",
            "maximumRepresentativeMontageSilenceFraction",
            "maximumProjectedFullDuration",
        ],
    },
    {
        "candidateID": "voice-candidate-06",
        "passes": False,
        "allUtteranceGates": False,
        "minimumUtteranceIdentityCosine": 0.9783645868301392,
        "aggregateWordErrorRate": 0.030303030303030304,
        "missingCriticalWords": ["roman"],
        "modelRetainedSilenceFraction": 0.16654560547888347,
        "representativeMontageSilenceFraction": 0.17856412354264675,
        "projectedFullDurationSeconds": 1448.0429552669555,
        "failedGates": [
            "allUtteranceGates",
            "minimumUtteranceIdentity",
            "maximumAggregateWordErrorRate",
            "criticalPronunciationWords",
            "maximumModelRetainedSilenceFraction",
            "maximumRepresentativeMontageSilenceFraction",
            "maximumProjectedFullDuration",
        ],
    },
]

EXPECTED_COST_ENTRIES = {
    "openvoice-v2-narration": ("model", "MIT"),
    "melotts-english-narration": ("model", "MIT"),
    "bert-base-uncased-narration": ("model", "Apache License 2.0"),
    "openvoice-v2-offline-runtime": (
        "tool",
        "PSF-2.0 CPython; MPL-2.0 python-build-standalone distribution; permissive package licences recorded in the exact runtime receipt; no unavoidable copyleft dependency",
    ),
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvidenceError(f"cannot load V10 evidence input: {path}") from error


def _expected_receipt_records() -> list[dict[str, Any]]:
    return [
        {
            "stage": stage,
            "status": status,
            "path": path,
            "bytes": size,
            "sha256": sha256,
        }
        for stage, status, path, size, sha256 in EXPECTED_RECEIPTS
    ]


def _validate_cost_registry() -> None:
    registry = _load(COST_REGISTRY)
    entries = {item.get("id"): item for item in registry.get("entries", [])}
    for identifier, (category, licence) in EXPECTED_COST_ENTRIES.items():
        item = entries.get(identifier)
        if (
            item is None
            or item.get("category") != category
            or item.get("license") != licence
            or item.get("incrementalCostNOK") != 0
            or item.get("billingCredentialRequired") is not False
            or item.get("commercialUse") != "allowed"
        ):
            raise EvidenceError(f"V10 cost/licence registry entry drifted: {identifier}")
    unresolved = {
        item.get("id"): item for item in registry.get("unresolvedCapabilities", [])
    }
    narration = unresolved.get("final-narration-synthesis")
    if (
        narration is None
        or narration.get("status")
        != "BLOCKED_UNTIL_ZERO_COST_COMMERCIAL_TOOL_PASSES"
        or narration.get("incrementalCostNOKMaximum") != 0
        or narration.get("billingCredentialPermitted") is not False
    ):
        raise EvidenceError("final narration cost gate is no longer closed")


def validate(path: Path = EVIDENCE_PATH) -> dict[str, Any]:
    evidence = _load(path)
    if path.absolute() == EVIDENCE_PATH and "work" in path.relative_to(NARRATION_ROOT).parts:
        raise EvidenceError("durable V10 evidence escaped into the ignored work tree")
    if (
        evidence.get("schemaVersion") != 1
        or evidence.get("status")
        != "CODEX_V10_OPENVOICE_NEGATIVE_EVIDENCE_FROZEN"
        or evidence.get("trustDomain") != "CODEX_V8_DIAGNOSTIC_NON_SHIPPING"
        or evidence.get("recordedAt") != "2026-07-25"
        or evidence.get("candidateID")
        != "openvoice-v2-melotts-english-en-br"
    ):
        raise EvidenceError("V10 evidence identity drifted")
    expected_decision = {
        "passesFrozenRepresentativeGate": False,
        "full203By2GenerationPermitted": False,
        "parameterTuningPermitted": False,
        "retryPermitted": False,
        "candidatePromoted": False,
        "masterParentPermitted": False,
        "shippingPermitted": False,
    }
    if evidence.get("decision") != expected_decision:
        raise EvidenceError("V10 stopped decision drifted")
    if evidence.get("receiptChain") != _expected_receipt_records():
        raise EvidenceError("V10 seven-receipt chain drifted")

    source_records = evidence.get("sourceBindings")
    if not isinstance(source_records, list) or len(source_records) != len(
        EXPECTED_SOURCE_BINDINGS
    ):
        raise EvidenceError("V10 source-binding inventory drifted")
    source_by_path = {item.get("path"): item for item in source_records}
    if set(source_by_path) != set(EXPECTED_SOURCE_BINDINGS):
        raise EvidenceError("V10 source-binding paths drifted")
    for relative, (size, sha256) in EXPECTED_SOURCE_BINDINGS.items():
        record = source_by_path[relative]
        if record != {"path": relative, "bytes": size, "sha256": sha256}:
            raise EvidenceError(f"V10 recorded source binding drifted: {relative}")
        current = REPOSITORY_ROOT / relative
        if (
            not current.is_file()
            or current.stat().st_size != size
            or _sha256(current) != sha256
        ):
            raise EvidenceError(f"V10 live source binding drifted: {relative}")

    optional_receipt_count = 0
    for record in evidence["receiptChain"]:
        current = REPOSITORY_ROOT / record["path"]
        if current.exists():
            optional_receipt_count += 1
            if (
                not current.is_file()
                or current.stat().st_size != record["bytes"]
                or _sha256(current) != record["sha256"]
            ):
                raise EvidenceError(f"local ignored V10 receipt drifted: {record['stage']}")

    if evidence.get("snapshot") != {
        "fileCount": 16,
        "totalBytes": 789435291,
        "allFilesSHA256VerifiedBeforeLoad": True,
        "mutableRevisionAliasUsed": False,
    }:
        raise EvidenceError("V10 snapshot result drifted")
    if evidence.get("runtime") != {
        "pythonVersion": "3.9.25",
        "packageCount": 44,
        "oneSelectedMacOSArm64WheelHashPerPackage": True,
        "allDependencyLicencesPermitInternalCommercialProduction": True,
        "unavoidableCopyleftDependencyCount": 0,
        "offlineImportPassed": True,
        "allRequiredWeightsLoadedOnCPU": True,
        "bothExactReferencesExtractedDirectly": True,
    }:
        raise EvidenceError("V10 runtime result drifted")
    if evidence.get("pronunciation") != {
        "representativeUtteranceCount": 14,
        "exactTextManifestSHA256": "822786bfaa942aec932686929d2ece3a7122d5215db654862cad3e28d9a8cb62",
        "normalizedTokenOccurrenceCount": 280,
        "uniqueNormalizedTokenCount": 185,
        "unknownTokenCount": 0,
        "criticalWordCount": 15,
        "g2pEnImported": False,
        "nltkImported": False,
        "networkFallbackUsed": False,
    }:
        raise EvidenceError("V10 pronunciation result drifted")
    if evidence.get("generation") != {
        "referenceCount": 2,
        "utteranceCountPerReference": 14,
        "synthesisCount": 28,
        "audioFileCount": 84,
        "attemptsPerUtterance": 1,
        "speed": 1.0,
        "adaptiveParameterChoiceUsed": False,
        "rawConverterOutputsRetainedUnmodified": True,
        "auditDerivativesAreNonShipping": True,
        "postConversionRepairUsed": False,
        "full203By2GenerationCount": 0,
    }:
        raise EvidenceError("V10 generation result drifted")
    gate = evidence.get("unchangedGate", {})
    if (
        gate.get("thresholds") != EXPECTED_THRESHOLDS
        or gate.get("candidateResults") != EXPECTED_RESULTS
        or gate.get("sameThresholdsAppliedToBothReferences") is not True
        or gate.get("thresholdOrGateModificationApplied") is not False
        or gate.get("bothReferencesPassEveryGate") is not False
    ):
        raise EvidenceError("V10 unchanged gate result drifted")
    if evidence.get("licenceAndCost") != {
        "openVoiceCodeAndWeights": "MIT",
        "meloTTSCodeAndWeights": "MIT",
        "bertBaseUncased": "Apache-2.0",
        "cpython": "PSF-2.0",
        "pythonBuildStandaloneDistribution": "MPL-2.0",
        "publishedCommercialUsePermitted": True,
        "completeTrainingCorpusAndBaseSpeakerIdentityDisclosed": False,
        "externalHumanReferenceSpeakerAdded": False,
        "hostedSynthesisUsed": False,
        "billingCredentialUsed": False,
        "incrementalCostNOK": 0,
    }:
        raise EvidenceError("V10 licence or cost finding drifted")
    _validate_cost_registry()
    return {
        "status": evidence["status"],
        "receiptCount": len(evidence["receiptChain"]),
        "sourceBindingCount": len(source_records),
        "locallyPresentReceiptCount": optional_receipt_count,
        "candidateCount": len(EXPECTED_RESULTS),
        "bothReferencesPass": False,
        "fullGenerationPermitted": False,
        "incrementalCostNOK": 0,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate",))
    parser.add_argument("--evidence", type=Path, default=EVIDENCE_PATH)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = validate(args.evidence.absolute())
    except EvidenceError as error:
        print(f"V10 evidence validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
