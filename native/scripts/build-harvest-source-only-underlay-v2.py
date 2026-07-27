#!/usr/bin/env python3
"""Build deterministic v2 Harvest underlays with in-place PatchMatch propagation.

The v1 builder remains a byte-frozen replay dependency.  This entry point only
accepts the explicit v2 method and adds fail-closed provenance-coherence gates.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np


V1_BUILDER = Path(__file__).with_name("build-harvest-source-only-underlay.py")
V1_BUILDER_SHA256 = "0272ba485e7dd46370956d02194a1cde7b0c165982737ba19ba3aca2d1f7031f"
V2_METHOD = "deterministic-source-only-patchmatch-v2-inplace"


def _load_v1_module() -> Any:
    digest = hashlib.sha256(V1_BUILDER.read_bytes()).hexdigest()
    if digest != V1_BUILDER_SHA256:
        raise RuntimeError(
            "v1 replay dependency changed; expected "
            f"{V1_BUILDER_SHA256}, got {digest}"
        )
    spec = importlib.util.spec_from_file_location("harvest_source_only_underlay_v1_frozen", V1_BUILDER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load frozen v1 builder: {V1_BUILDER}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


V1 = _load_v1_module()
_V1_VALIDATE_SYNTHESIS = V1._validate_synthesis
_V1_VALIDATE_THRESHOLDS = V1._validate_thresholds


@dataclass(frozen=True)
class Analysis:
    loaded: Any
    candidate: np.ndarray
    provenance_y: np.ndarray
    provenance_x: np.ndarray
    candidate_sha256: str
    metrics: dict[str, Any]
    failed_gates: tuple[str, ...]
    expected_mismatches: tuple[str, ...]


def _validate_v2_synthesis(value: Any) -> dict[str, Any]:
    synthesis = V1._expect_object(value, "synthesis")
    if synthesis.get("method") != V2_METHOD:
        raise V1.RecipeError(f"synthesis.method: expected {V2_METHOD!r}")
    V1._expect_keys(
        synthesis,
        "synthesis",
        [
            "method",
            "patchRadius",
            "guide",
            "initialCandidateCount",
            "sweeps",
            "randomCandidatesPerSweep",
            "tileSize",
            "propagationCostToleranceFraction",
        ],
    )
    compatibility_copy = {
        key: item for key, item in synthesis.items() if key != "propagationCostToleranceFraction"
    }
    compatibility_copy["method"] = "deterministic-source-only-patchmatch-v1"
    _V1_VALIDATE_SYNTHESIS(compatibility_copy)
    V1._expect_number(
        synthesis["propagationCostToleranceFraction"],
        "synthesis.propagationCostToleranceFraction",
        0.0,
        10.0,
    )
    return synthesis


def _validate_v2_thresholds(value: Any) -> dict[str, Any]:
    thresholds = V1._expect_object(value, "thresholds")
    V1._expect_keys(
        thresholds,
        "thresholds",
        [
            "minimumDonorPixels",
            "minimumValidDonorCenters",
            "minimumUniqueDonorCenters",
            "maximumDonorCenterReuse",
            "maximumGeneratedSharePerTile",
            "crossSeam",
            "interiorGradientRatio",
            "generatedLuma",
            "maximumMeanColorDelta",
            "changedTargetFraction",
            "provenanceCoherence",
        ],
    )
    v1_copy = {key: item for key, item in thresholds.items() if key != "provenanceCoherence"}
    _V1_VALIDATE_THRESHOLDS(v1_copy)
    coherence = V1._expect_object(thresholds["provenanceCoherence"], "thresholds.provenanceCoherence")
    V1._expect_keys(
        coherence,
        "thresholds.provenanceCoherence",
        [
            "minimumExactTranslationAdjacencyFraction",
            "maximumDisplacementJumpP95",
            "maximumDisplacementJumpP99",
        ],
    )
    V1._expect_number(
        coherence["minimumExactTranslationAdjacencyFraction"],
        "thresholds.provenanceCoherence.minimumExactTranslationAdjacencyFraction",
        0.0,
        1.0,
    )
    p95 = V1._expect_number(
        coherence["maximumDisplacementJumpP95"],
        "thresholds.provenanceCoherence.maximumDisplacementJumpP95",
        0.0,
    )
    p99 = V1._expect_number(
        coherence["maximumDisplacementJumpP99"],
        "thresholds.provenanceCoherence.maximumDisplacementJumpP99",
        0.0,
    )
    if p95 > p99:
        raise V1.RecipeError("thresholds.provenanceCoherence: p95 maximum exceeds p99 maximum")
    return thresholds


def load_recipe(recipe_path: Path, root: Path, require_expected: bool) -> Any:
    original_synthesis = V1._validate_synthesis
    original_thresholds = V1._validate_thresholds
    V1._validate_synthesis = _validate_v2_synthesis
    V1._validate_thresholds = _validate_v2_thresholds
    try:
        return V1.load_recipe(recipe_path, root, require_expected=require_expected)
    finally:
        V1._validate_synthesis = original_synthesis
        V1._validate_thresholds = original_thresholds


def _initial_mapping(loaded: Any) -> tuple[np.ndarray, ...]:
    cv2.setNumThreads(1)
    cv2.setRNGSeed(0)
    crop_x, crop_y, width, height = loaded.crop
    source = loaded.source_rgb[crop_y : crop_y + height, crop_x : crop_x + width].copy()
    target = loaded.authorization
    synthesis = loaded.data["synthesis"]
    guide_spec = synthesis["guide"]
    algorithm = cv2.INPAINT_TELEA if guide_spec["algorithm"] == "telea" else cv2.INPAINT_NS
    guide = cv2.inpaint(source, target.astype(np.uint8) * 255, float(guide_spec["radius"]), algorithm)
    sigma = float(guide_spec["blurSigma"])
    if sigma > 0:
        guide = cv2.GaussianBlur(
            guide, (0, 0), sigmaX=sigma, sigmaY=sigma, borderType=cv2.BORDER_REFLECT_101
        )
        low_source = cv2.GaussianBlur(
            source, (0, 0), sigmaX=sigma, sigmaY=sigma, borderType=cv2.BORDER_REFLECT_101
        )
    else:
        low_source = source

    target_coordinates = np.argwhere(target)
    donor_coordinates = np.argwhere(loaded.valid_donor_centers)
    target_y = target_coordinates[:, 0].astype(np.int32)
    target_x = target_coordinates[:, 1].astype(np.int32)
    radius = int(synthesis["patchRadius"])
    seed = int(loaded.seed_sha256[:16], 16)
    best_y = np.empty(target_y.size, dtype=np.int32)
    best_x = np.empty(target_y.size, dtype=np.int32)
    best_cost = np.full(target_y.size, np.inf, dtype=np.float64)
    for salt in range(int(synthesis["initialCandidateCount"])):
        indices = V1._hashed_indices(target_y, target_x, salt, seed, donor_coordinates.shape[0])
        proposal_y = donor_coordinates[indices, 0].astype(np.int32)
        proposal_x = donor_coordinates[indices, 1].astype(np.int32)
        cost = V1._patch_cost(guide, low_source, target, target_y, target_x, proposal_y, proposal_x, radius)
        better = cost < best_cost
        best_cost[better] = cost[better]
        best_y[better] = proposal_y[better]
        best_x[better] = proposal_x[better]
    return source, guide, low_source, target_y, target_x, best_y, best_x, best_cost, donor_coordinates


def _propagate_in_place(
    loaded: Any,
    guide: np.ndarray,
    low_source: np.ndarray,
    target_y: np.ndarray,
    target_x: np.ndarray,
    best_y: np.ndarray,
    best_x: np.ndarray,
    best_cost: np.ndarray,
    forward: bool,
) -> None:
    height, width = loaded.authorization.shape
    radius = int(loaded.data["synthesis"]["patchRadius"])
    tolerance = float(loaded.data["synthesis"]["propagationCostToleranceFraction"])
    map_y = np.full((height, width), -1, dtype=np.int32)
    map_x = np.full((height, width), -1, dtype=np.int32)
    map_index = np.full((height, width), -1, dtype=np.int32)
    map_y[target_y, target_x] = best_y
    map_x[target_y, target_x] = best_x
    map_index[target_y, target_x] = np.arange(target_y.size, dtype=np.int32)
    diagonals = range(height + width - 1) if forward else range(height + width - 2, -1, -1)
    offsets = ((0, -1), (-1, 0)) if forward else ((0, 1), (1, 0))

    for diagonal in diagonals:
        y_min = max(0, diagonal - (width - 1))
        y_max = min(height - 1, diagonal)
        diagonal_y = np.arange(y_min, y_max + 1, dtype=np.int32)
        diagonal_x = diagonal - diagonal_y
        indices = map_index[diagonal_y, diagonal_x]
        indices = indices[indices >= 0]
        if indices.size == 0:
            continue
        current_y = target_y[indices]
        current_x = target_x[indices]
        for neighbor_dy, neighbor_dx in offsets:
            neighbor_y = current_y + neighbor_dy
            neighbor_x = current_x + neighbor_dx
            inside = (
                (neighbor_y >= 0)
                & (neighbor_y < height)
                & (neighbor_x >= 0)
                & (neighbor_x < width)
            )
            clipped_y = np.clip(neighbor_y, 0, height - 1)
            clipped_x = np.clip(neighbor_x, 0, width - 1)
            proposal_y = map_y[clipped_y, clipped_x] - neighbor_dy
            proposal_x = map_x[clipped_y, clipped_x] - neighbor_dx
            valid = inside & (proposal_y >= 0) & (proposal_x >= 0)
            safe_y = np.clip(proposal_y, 0, height - 1)
            safe_x = np.clip(proposal_x, 0, width - 1)
            valid &= loaded.valid_donor_centers[safe_y, safe_x]
            selected = np.flatnonzero(valid)
            if selected.size == 0:
                continue
            selected_indices = indices[selected]
            cost = V1._patch_cost(
                guide,
                low_source,
                loaded.authorization,
                target_y[selected_indices],
                target_x[selected_indices],
                proposal_y[selected],
                proposal_x[selected],
                radius,
            )
            if tolerance == 0:
                better = cost < best_cost[selected_indices]
            else:
                better = cost <= best_cost[selected_indices] * (1.0 + tolerance)
            changed = selected_indices[better]
            if changed.size:
                best_cost[changed] = cost[better]
                best_y[changed] = proposal_y[selected][better]
                best_x[changed] = proposal_x[selected][better]
                map_y[target_y[changed], target_x[changed]] = best_y[changed]
                map_x[target_y[changed], target_x[changed]] = best_x[changed]


def _source_only_patchmatch_v2(loaded: Any) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    (
        source,
        guide,
        low_source,
        target_y,
        target_x,
        best_y,
        best_x,
        best_cost,
        donor_coordinates,
    ) = _initial_mapping(loaded)
    synthesis = loaded.data["synthesis"]
    seed = int(loaded.seed_sha256[:16], 16)
    radius = int(synthesis["patchRadius"])

    for sweep in range(int(synthesis["sweeps"])):
        for random_index in range(int(synthesis["randomCandidatesPerSweep"])):
            salt = 1_000_000 + sweep * 10_000 + random_index
            indices = V1._hashed_indices(target_y, target_x, salt, seed, donor_coordinates.shape[0])
            proposal_y = donor_coordinates[indices, 0].astype(np.int32)
            proposal_x = donor_coordinates[indices, 1].astype(np.int32)
            cost = V1._patch_cost(
                guide,
                low_source,
                loaded.authorization,
                target_y,
                target_x,
                proposal_y,
                proposal_x,
                radius,
            )
            better = cost < best_cost
            best_cost[better] = cost[better]
            best_y[better] = proposal_y[better]
            best_x[better] = proposal_x[better]
        _propagate_in_place(
            loaded,
            guide,
            low_source,
            target_y,
            target_x,
            best_y,
            best_x,
            best_cost,
            forward=sweep % 2 == 0,
        )

    if np.any(~loaded.valid_donor_centers[best_y, best_x]):
        raise V1.RecipeError("synthesis: provenance escaped valid donor centers")
    height, width = loaded.authorization.shape
    map_y = np.full((height, width), -1, dtype=np.int32)
    map_x = np.full((height, width), -1, dtype=np.int32)
    map_y[target_y, target_x] = best_y
    map_x[target_y, target_x] = best_x
    candidate = source.copy()
    candidate[target_y, target_x] = source[best_y, best_x]
    if np.any(candidate[~loaded.authorization] != source[~loaded.authorization]):
        raise V1.RecipeError("synthesis: pixels outside authorization changed")
    return candidate, map_y, map_x


def _coherence_metrics(target: np.ndarray, provenance_y: np.ndarray, provenance_x: np.ndarray) -> dict[str, Any]:
    exact_parts: list[np.ndarray] = []
    jump_parts: list[np.ndarray] = []
    for dy, dx in ((0, 1), (1, 0)):
        first = target[: target.shape[0] - dy, : target.shape[1] - dx]
        second = target[dy:, dx:]
        both = first & second
        if not both.any():
            continue
        source_y_delta = (
            provenance_y[dy:, dx:][both]
            - provenance_y[: provenance_y.shape[0] - dy, : provenance_y.shape[1] - dx][both]
        )
        source_x_delta = (
            provenance_x[dy:, dx:][both]
            - provenance_x[: provenance_x.shape[0] - dy, : provenance_x.shape[1] - dx][both]
        )
        displacement_y_jump = source_y_delta - dy
        displacement_x_jump = source_x_delta - dx
        exact_parts.append((displacement_y_jump == 0) & (displacement_x_jump == 0))
        jump_parts.append(
            np.hypot(displacement_y_jump.astype(np.float64), displacement_x_jump.astype(np.float64))
        )
    if not exact_parts:
        return {
            "internalAdjacencyPairCount": 0,
            "exactTranslationAdjacencyFraction": None,
            "displacementJump": {"median": None, "p95": None, "p99": None, "maximum": None},
        }
    exact = np.concatenate(exact_parts)
    jumps = np.concatenate(jump_parts)
    return {
        "internalAdjacencyPairCount": int(exact.size),
        "exactTranslationAdjacencyFraction": V1._round(float(exact.mean())),
        "displacementJump": {
            "median": V1._round(float(np.median(jumps))),
            "p95": V1._round(float(np.percentile(jumps, 95))),
            "p99": V1._round(float(np.percentile(jumps, 99))),
            "maximum": V1._round(float(np.max(jumps))),
        },
    }


def _measure_quality_v2(
    loaded: Any, candidate: np.ndarray, provenance_y: np.ndarray, provenance_x: np.ndarray
) -> tuple[dict[str, Any], tuple[str, ...]]:
    metrics, v1_failures = V1._measure_quality(loaded, candidate, provenance_y, provenance_x)
    coherence = _coherence_metrics(loaded.authorization, provenance_y, provenance_x)
    metrics["provenanceCoherence"] = coherence
    thresholds = loaded.data["thresholds"]["provenanceCoherence"]
    failures = list(v1_failures)
    exact = coherence["exactTranslationAdjacencyFraction"]
    if exact is None:
        failures.append("PROVENANCE_COHERENCE_HAS_NO_ADJACENCY_PAIRS")
    else:
        if exact < thresholds["minimumExactTranslationAdjacencyFraction"]:
            failures.append("EXACT_TRANSLATION_ADJACENCY_FRACTION_BELOW_MINIMUM")
        if coherence["displacementJump"]["p95"] > thresholds["maximumDisplacementJumpP95"]:
            failures.append("DISPLACEMENT_JUMP_P95_ABOVE_MAXIMUM")
        if coherence["displacementJump"]["p99"] > thresholds["maximumDisplacementJumpP99"]:
            failures.append("DISPLACEMENT_JUMP_P99_ABOVE_MAXIMUM")
    return metrics, tuple(sorted(failures))


def analyze(recipe_path: Path, root: Path, require_expected: bool) -> Analysis:
    loaded = load_recipe(recipe_path, root, require_expected=require_expected)
    mismatches: list[str] = []
    expected = loaded.data.get("expected")
    if expected is not None:
        if expected["seedSha256"] != loaded.seed_sha256:
            mismatches.append("EXPECTED_SEED_SHA256_MISMATCH")
        for key, measured in loaded.measurements.items():
            if expected[key] != measured:
                mismatches.append(f"EXPECTED_{key.upper()}_MISMATCH")
    if require_expected and mismatches:
        raise V1.RecipeError("expected forensic mismatch: " + ", ".join(sorted(mismatches)))
    first = _source_only_patchmatch_v2(loaded)
    second = _source_only_patchmatch_v2(loaded)
    if not all(np.array_equal(left, right) for left, right in zip(first, second)):
        raise V1.RecipeError("determinism: two in-process v2 synthesis runs differ")
    candidate, provenance_y, provenance_x = first
    candidate_sha = V1._sha256_bytes(candidate.tobytes(order="C"))
    metrics, failures = _measure_quality_v2(loaded, candidate, provenance_y, provenance_x)
    if expected is not None and expected["candidateSha256"] != candidate_sha:
        mismatches.append("EXPECTED_CANDIDATE_SHA256_MISMATCH")
    if require_expected and mismatches:
        raise V1.RecipeError("expected forensic mismatch: " + ", ".join(sorted(mismatches)))
    return Analysis(
        loaded=loaded,
        candidate=candidate,
        provenance_y=provenance_y,
        provenance_x=provenance_x,
        candidate_sha256=candidate_sha,
        metrics=metrics,
        failed_gates=failures,
        expected_mismatches=tuple(sorted(mismatches)),
    )


def _receipt(analysis: Analysis, artifacts: dict[str, bytes]) -> dict[str, Any]:
    receipt = V1._receipt(analysis, artifacts)
    script_path = Path(__file__).resolve()
    script_label = (
        script_path.relative_to(analysis.loaded.root).as_posix()
        if V1._inside(script_path, analysis.loaded.root)
        else script_path.name
    )
    dependency_label = (
        V1_BUILDER.relative_to(analysis.loaded.root).as_posix()
        if V1._inside(V1_BUILDER, analysis.loaded.root)
        else V1_BUILDER.name
    )
    receipt["tool"] = {
        "path": script_label,
        "sha256": V1._sha256_file(script_path),
        "runtime": V1._runtime_record(),
        "frozenReplayDependency": {
            "path": dependency_label,
            "sha256": V1_BUILDER_SHA256,
        },
    }
    receipt["synthesisMethod"] = V2_METHOD
    return receipt


def run(mode: str, recipe_path: Path, root: Path) -> dict[str, Any]:
    if mode not in {"inspect", "build", "verify"}:
        raise V1.RecipeError(f"unsupported mode: {mode}")
    analysis = analyze(recipe_path, root, require_expected=mode in {"build", "verify"})
    locking_values = {
        "seedSha256": analysis.loaded.seed_sha256,
        **analysis.loaded.measurements,
        "candidateSha256": analysis.candidate_sha256,
    }
    summary = {
        "mode": mode,
        "recipe": analysis.loaded.relative_path,
        "objectiveGate": "PASS" if not analysis.failed_gates else "FAIL",
        "failedGates": list(analysis.failed_gates),
        "expectedMismatches": list(analysis.expected_mismatches),
        "lockingValues": locking_values,
        "metrics": analysis.metrics,
    }
    if mode == "inspect":
        return summary
    if analysis.failed_gates:
        raise V1.RecipeError("objective QA failed: " + ", ".join(analysis.failed_gates))
    artifacts = V1._artifact_bytes(analysis)
    receipt_bytes = V1._canonical_json(_receipt(analysis, artifacts))
    if mode == "build":
        V1._write_build(analysis, artifacts, receipt_bytes)
    else:
        V1._verify_existing(analysis, artifacts, receipt_bytes)
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("inspect", "build", "verify"))
    parser.add_argument("--recipe", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        summary = run(arguments.mode, arguments.recipe, Path.cwd())
    except (V1.RecipeError, RuntimeError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2
    print(V1._canonical_json(summary).decode("utf-8"), end="")
    return 0 if summary["objectiveGate"] == "PASS" and not summary["expectedMismatches"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
