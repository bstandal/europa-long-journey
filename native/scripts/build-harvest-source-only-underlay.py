#!/usr/bin/env python3
"""Build and replay-verify non-shipping, source-only Harvest underlays.

The recipe is the authority for every mask, crop, motion bound, objective QA
threshold and expected digest.  OpenCV inpainting is used only as a matching
guide: every generated RGB pixel is copied from an authorized source pixel.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import cv2
import numpy as np
from PIL import Image


SCHEMA_VERSION = 1
RECIPE_STATUS = "CODEX_NON_SHIPPING_SOURCE_ONLY_UNDERLAY_RECIPE"
RECEIPT_STATUS = "OBJECTIVE_TECHNICAL_QA_PASS"
BACKSTAGE_PREFIX = Path("native/content/backstage/harvest")
BUILD_PREFIX = Path("native/.build")


class RecipeError(RuntimeError):
    """A fail-closed recipe, input, QA or replay error."""


@dataclass(frozen=True)
class LoadedRecipe:
    root: Path
    path: Path
    relative_path: str
    raw_bytes: bytes
    data: dict[str, Any]
    source_path: Path
    source_rgb: np.ndarray
    mask_arrays: dict[str, np.ndarray]
    binding_digests: dict[str, str]
    crop: tuple[int, int, int, int]
    subject: np.ndarray
    authorization: np.ndarray
    donor: np.ndarray
    valid_donor_centers: np.ndarray
    seed_sha256: str
    measurements: dict[str, Any]
    output_directory: Path
    receipt_path: Path
    output_names: dict[str, str]


@dataclass(frozen=True)
class Analysis:
    loaded: LoadedRecipe
    candidate: np.ndarray
    provenance_y: np.ndarray
    provenance_x: np.ndarray
    candidate_sha256: str
    metrics: dict[str, Any]
    failed_gates: tuple[str, ...]
    expected_mismatches: tuple[str, ...]


def _canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json_without_duplicate_keys(raw: bytes, label: str) -> dict[str, Any]:
    def reject(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise RecipeError(f"{label}: duplicate key {key!r}")
            result[key] = value
        return result

    try:
        parsed = json.loads(raw.decode("utf-8"), object_pairs_hook=reject)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RecipeError(f"{label}: invalid UTF-8 JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise RecipeError(f"{label}: top level must be an object")
    return parsed


def _expect_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RecipeError(f"{label}: expected object")
    return value


def _expect_keys(
    value: dict[str, Any], label: str, required: Iterable[str], optional: Iterable[str] = ()
) -> None:
    required_set = set(required)
    allowed = required_set | set(optional)
    missing = sorted(required_set - set(value))
    extra = sorted(set(value) - allowed)
    if missing or extra:
        raise RecipeError(f"{label}: key mismatch; missing={missing}, extra={extra}")


def _expect_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise RecipeError(f"{label}: expected non-empty string")
    return value


def _expect_bool(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise RecipeError(f"{label}: expected boolean")
    return value


def _expect_int(value: Any, label: str, minimum: int | None = None, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise RecipeError(f"{label}: expected integer")
    if minimum is not None and value < minimum:
        raise RecipeError(f"{label}: must be >= {minimum}")
    if maximum is not None and value > maximum:
        raise RecipeError(f"{label}: must be <= {maximum}")
    return value


def _expect_number(value: Any, label: str, minimum: float | None = None, maximum: float | None = None) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise RecipeError(f"{label}: expected finite number")
    result = float(value)
    if minimum is not None and result < minimum:
        raise RecipeError(f"{label}: must be >= {minimum}")
    if maximum is not None and result > maximum:
        raise RecipeError(f"{label}: must be <= {maximum}")
    return result


def _expect_sha256(value: Any, label: str) -> str:
    result = _expect_string(value, label)
    if len(result) != 64 or any(char not in "0123456789abcdef" for char in result):
        raise RecipeError(f"{label}: expected lower-case SHA-256")
    return result


def _inside(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _repo_path(root: Path, raw: Any, label: str, must_exist: bool = True) -> Path:
    text = _expect_string(raw, label)
    candidate = Path(text)
    if candidate.is_absolute():
        raise RecipeError(f"{label}: absolute paths are forbidden")
    resolved = (root / candidate).resolve(strict=False)
    if not _inside(resolved, root):
        raise RecipeError(f"{label}: path escapes repository")
    if must_exist and not resolved.is_file():
        raise RecipeError(f"{label}: file does not exist: {text}")
    return resolved


def _size(value: Any, label: str) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise RecipeError(f"{label}: expected [width,height]")
    return (_expect_int(value[0], f"{label}[0]", 1), _expect_int(value[1], f"{label}[1]", 1))


def _disk_offsets(radius: int) -> tuple[tuple[int, int], ...]:
    return tuple(
        (dy, dx)
        for dy in range(-radius, radius + 1)
        for dx in range(-radius, radius + 1)
        if dx * dx + dy * dy <= radius * radius
    )


def _shift_zero(mask: np.ndarray, dy: int, dx: int) -> np.ndarray:
    height, width = mask.shape
    output = np.zeros_like(mask, dtype=bool)
    src_y0, src_y1 = max(0, -dy), min(height, height - dy)
    src_x0, src_x1 = max(0, -dx), min(width, width - dx)
    if src_y0 < src_y1 and src_x0 < src_x1:
        output[src_y0 + dy : src_y1 + dy, src_x0 + dx : src_x1 + dx] = mask[
            src_y0:src_y1, src_x0:src_x1
        ]
    return output


def _dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    if radius == 0:
        return mask.copy()
    output = np.zeros_like(mask, dtype=bool)
    for dy, dx in _disk_offsets(radius):
        output |= _shift_zero(mask, dy, dx)
    return output


def _erode(mask: np.ndarray, radius: int) -> np.ndarray:
    if radius == 0:
        return mask.copy()
    output = np.ones_like(mask, dtype=bool)
    for dy, dx in _disk_offsets(radius):
        output &= _shift_zero(mask, dy, dx)
    return output


def _largest_component(mask: np.ndarray) -> np.ndarray:
    source = mask.astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(source, connectivity=8)
    if count <= 1:
        return np.zeros_like(mask, dtype=bool)
    areas = stats[1:, cv2.CC_STAT_AREA]
    largest_label = 1 + int(np.argmax(areas))
    return labels == largest_label


def _eval_expression(
    expression: Any,
    masks: dict[str, np.ndarray],
    bindings: set[str],
    label: str,
    depth: int = 0,
) -> np.ndarray:
    if depth > 32:
        raise RecipeError(f"{label}: expression nesting exceeds 32")
    value = _expect_object(expression, label)
    if "mask" in value:
        _expect_keys(value, label, ["mask"])
        mask_id = _expect_string(value["mask"], f"{label}.mask")
        if mask_id not in masks:
            raise RecipeError(f"{label}: unknown mask {mask_id!r}")
        return masks[mask_id].copy()

    op = _expect_string(value.get("op"), f"{label}.op")
    if op in {"union", "intersect"}:
        _expect_keys(value, label, ["op", "inputs"])
        inputs = value["inputs"]
        if not isinstance(inputs, list) or len(inputs) < 2:
            raise RecipeError(f"{label}.inputs: expected at least two expressions")
        evaluated = [
            _eval_expression(item, masks, bindings, f"{label}.inputs[{index}]", depth + 1)
            for index, item in enumerate(inputs)
        ]
        output = evaluated[0]
        for item in evaluated[1:]:
            output = output | item if op == "union" else output & item
        return output

    if op == "subtract":
        _expect_keys(value, label, ["op", "input", "subtract"])
        subtract = value["subtract"]
        if not isinstance(subtract, list) or not subtract:
            raise RecipeError(f"{label}.subtract: expected one or more expressions")
        output = _eval_expression(value["input"], masks, bindings, f"{label}.input", depth + 1)
        for index, item in enumerate(subtract):
            output &= ~_eval_expression(item, masks, bindings, f"{label}.subtract[{index}]", depth + 1)
        return output

    if op in {"dilate", "erode", "close", "largestComponent"}:
        required = ["op", "input"] if op == "largestComponent" else ["op", "input", "radius"]
        _expect_keys(value, label, required)
        source = _eval_expression(value["input"], masks, bindings, f"{label}.input", depth + 1)
        if op == "largestComponent":
            return _largest_component(source)
        radius = _expect_int(value["radius"], f"{label}.radius", 0, 256)
        if op == "dilate":
            return _dilate(source, radius)
        if op == "erode":
            return _erode(source, radius)
        return _erode(_dilate(source, radius), radius)

    if op == "directionalReveal":
        _expect_keys(value, label, ["op", "input", "motion", "seamPixels"])
        source = _eval_expression(value["input"], masks, bindings, f"{label}.input", depth + 1)
        motion = _expect_object(value["motion"], f"{label}.motion")
        _expect_keys(motion, f"{label}.motion", ["minDx", "maxDx", "minDy", "maxDy", "authority"])
        min_dx = _expect_int(motion["minDx"], f"{label}.motion.minDx", -256, 256)
        max_dx = _expect_int(motion["maxDx"], f"{label}.motion.maxDx", -256, 256)
        min_dy = _expect_int(motion["minDy"], f"{label}.motion.minDy", -256, 256)
        max_dy = _expect_int(motion["maxDy"], f"{label}.motion.maxDy", -256, 256)
        if min_dx > max_dx or min_dy > max_dy:
            raise RecipeError(f"{label}.motion: minimum exceeds maximum")
        if min_dx == max_dx == min_dy == max_dy == 0:
            raise RecipeError(f"{label}.motion: at least one non-zero shift is required")
        shift_count = (max_dx - min_dx + 1) * (max_dy - min_dy + 1)
        if shift_count > 4096:
            raise RecipeError(f"{label}.motion: more than 4096 shifts")
        authority = _expect_string(motion["authority"], f"{label}.motion.authority")
        if authority not in bindings:
            raise RecipeError(f"{label}.motion.authority: unknown binding {authority!r}")
        reveal = np.zeros_like(source, dtype=bool)
        for dy in range(min_dy, max_dy + 1):
            for dx in range(min_dx, max_dx + 1):
                reveal |= source & ~_shift_zero(source, dy, dx)
        seam_pixels = _expect_int(value["seamPixels"], f"{label}.seamPixels", 0, 256)
        return _dilate(reveal, seam_pixels) & source

    raise RecipeError(f"{label}.op: unsupported operation {op!r}")


def _mask_measure(mask: np.ndarray) -> dict[str, Any]:
    coordinates = np.argwhere(mask)
    if coordinates.size == 0:
        bounds: list[int] | None = None
    else:
        y0, x0 = coordinates.min(axis=0)
        y1, x1 = coordinates.max(axis=0)
        bounds = [int(x0), int(y0), int(x1), int(y1)]
    return {
        "pixelCount": int(mask.sum()),
        "byteMaskSha256": _sha256_bytes(mask.astype(np.uint8).tobytes(order="C")),
        "boundsInclusive": bounds,
    }


def _validate_measure(value: Any, label: str) -> dict[str, Any]:
    result = _expect_object(value, label)
    _expect_keys(result, label, ["pixelCount", "byteMaskSha256", "boundsInclusive"])
    _expect_int(result["pixelCount"], f"{label}.pixelCount", 0)
    _expect_sha256(result["byteMaskSha256"], f"{label}.byteMaskSha256")
    bounds = result["boundsInclusive"]
    if bounds is not None:
        if not isinstance(bounds, list) or len(bounds) != 4:
            raise RecipeError(f"{label}.boundsInclusive: expected null or [x0,y0,x1,y1]")
        for index, item in enumerate(bounds):
            _expect_int(item, f"{label}.boundsInclusive[{index}]", 0)
        if bounds[0] > bounds[2] or bounds[1] > bounds[3]:
            raise RecipeError(f"{label}.boundsInclusive: inverted bounds")
    return result


def _load_rgb(path: Path, size: tuple[int, int], label: str) -> np.ndarray:
    try:
        with Image.open(path) as image:
            if image.mode != "RGB":
                raise RecipeError(f"{label}: source mode must be RGB, got {image.mode}")
            if image.size != size:
                raise RecipeError(f"{label}: expected size {size}, got {image.size}")
            return np.asarray(image, dtype=np.uint8).copy()
    except OSError as exc:
        raise RecipeError(f"{label}: cannot read image: {exc}") from exc


def _load_mask(path: Path, size: tuple[int, int], label: str) -> np.ndarray:
    try:
        with Image.open(path) as image:
            if image.size != size:
                raise RecipeError(f"{label}: expected size {size}, got {image.size}")
            array = np.asarray(image.convert("L"), dtype=np.uint8)
    except OSError as exc:
        raise RecipeError(f"{label}: cannot read mask: {exc}") from exc
    values = np.unique(array)
    if not set(int(item) for item in values).issubset({0, 255}):
        raise RecipeError(f"{label}: mask must contain only 0 and 255")
    return array == 255


def _validate_thresholds(value: Any) -> dict[str, Any]:
    thresholds = _expect_object(value, "thresholds")
    _expect_keys(
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
        ],
    )
    _expect_int(thresholds["minimumDonorPixels"], "thresholds.minimumDonorPixels", 1)
    _expect_int(thresholds["minimumValidDonorCenters"], "thresholds.minimumValidDonorCenters", 1)
    _expect_int(thresholds["minimumUniqueDonorCenters"], "thresholds.minimumUniqueDonorCenters", 1)
    _expect_int(thresholds["maximumDonorCenterReuse"], "thresholds.maximumDonorCenterReuse", 1)
    _expect_number(
        thresholds["maximumGeneratedSharePerTile"], "thresholds.maximumGeneratedSharePerTile", 0.0, 1.0
    )
    seam = _expect_object(thresholds["crossSeam"], "thresholds.crossSeam")
    _expect_keys(seam, "thresholds.crossSeam", ["meanMaximum", "p95Maximum", "p99Maximum"])
    for key in ("meanMaximum", "p95Maximum", "p99Maximum"):
        _expect_number(seam[key], f"thresholds.crossSeam.{key}", 0.0, 255.0)
    gradient = _expect_object(thresholds["interiorGradientRatio"], "thresholds.interiorGradientRatio")
    _expect_keys(gradient, "thresholds.interiorGradientRatio", ["minimum", "maximum"])
    gradient_min = _expect_number(gradient["minimum"], "thresholds.interiorGradientRatio.minimum", 0.0)
    gradient_max = _expect_number(gradient["maximum"], "thresholds.interiorGradientRatio.maximum", 0.0)
    if gradient_min > gradient_max:
        raise RecipeError("thresholds.interiorGradientRatio: minimum exceeds maximum")
    luma = _expect_object(thresholds["generatedLuma"], "thresholds.generatedLuma")
    _expect_keys(luma, "thresholds.generatedLuma", ["p01Minimum", "p99Maximum"])
    luma_min = _expect_number(luma["p01Minimum"], "thresholds.generatedLuma.p01Minimum", 0.0, 255.0)
    luma_max = _expect_number(luma["p99Maximum"], "thresholds.generatedLuma.p99Maximum", 0.0, 255.0)
    if luma_min > luma_max:
        raise RecipeError("thresholds.generatedLuma: minimum exceeds maximum")
    _expect_number(thresholds["maximumMeanColorDelta"], "thresholds.maximumMeanColorDelta", 0.0)
    changed = _expect_object(thresholds["changedTargetFraction"], "thresholds.changedTargetFraction")
    _expect_keys(changed, "thresholds.changedTargetFraction", ["minimum", "maximum"])
    changed_min = _expect_number(changed["minimum"], "thresholds.changedTargetFraction.minimum", 0.0, 1.0)
    changed_max = _expect_number(changed["maximum"], "thresholds.changedTargetFraction.maximum", 0.0, 1.0)
    if changed_min > changed_max:
        raise RecipeError("thresholds.changedTargetFraction: minimum exceeds maximum")
    return thresholds


def _validate_synthesis(value: Any) -> dict[str, Any]:
    synthesis = _expect_object(value, "synthesis")
    _expect_keys(
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
        ],
    )
    if synthesis["method"] != "deterministic-source-only-patchmatch-v1":
        raise RecipeError("synthesis.method: unsupported method")
    _expect_int(synthesis["patchRadius"], "synthesis.patchRadius", 1, 32)
    _expect_int(synthesis["initialCandidateCount"], "synthesis.initialCandidateCount", 1, 256)
    _expect_int(synthesis["sweeps"], "synthesis.sweeps", 0, 64)
    _expect_int(synthesis["randomCandidatesPerSweep"], "synthesis.randomCandidatesPerSweep", 0, 64)
    _expect_int(synthesis["tileSize"], "synthesis.tileSize", 1, 4096)
    guide = _expect_object(synthesis["guide"], "synthesis.guide")
    _expect_keys(guide, "synthesis.guide", ["algorithm", "radius", "blurSigma"])
    if guide["algorithm"] not in {"telea", "navier-stokes"}:
        raise RecipeError("synthesis.guide.algorithm: expected 'telea' or 'navier-stokes'")
    _expect_number(guide["radius"], "synthesis.guide.radius", 0.1, 128.0)
    _expect_number(guide["blurSigma"], "synthesis.guide.blurSigma", 0.0, 128.0)
    return synthesis


def _seed_material(data: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": data["schemaVersion"],
        "id": data["id"],
        "status": data["status"],
        "shippingAllowed": data["shippingAllowed"],
        "editorApprovalClaimed": data["editorApprovalClaimed"],
        "source": data["source"],
        "bindings": sorted(data["bindings"], key=lambda item: item["id"]),
        "masks": sorted(data["masks"], key=lambda item: item["id"]),
        "crop": data["crop"],
        "expressions": data["expressions"],
        "synthesis": data["synthesis"],
    }


def load_recipe(recipe_path: Path, root: Path, require_expected: bool) -> LoadedRecipe:
    root = root.resolve()
    path = recipe_path.resolve()
    backstage_root = (root / BACKSTAGE_PREFIX).resolve()
    if not _inside(path, backstage_root) or not path.is_file():
        raise RecipeError(f"recipe must be a file below {BACKSTAGE_PREFIX.as_posix()}")
    raw = path.read_bytes()
    data = _json_without_duplicate_keys(raw, "recipe")
    _expect_keys(
        data,
        "recipe",
        [
            "schemaVersion",
            "id",
            "status",
            "shippingAllowed",
            "editorApprovalClaimed",
            "source",
            "bindings",
            "masks",
            "crop",
            "expressions",
            "synthesis",
            "thresholds",
            "output",
        ],
        ["expected"],
    )
    if data["schemaVersion"] != SCHEMA_VERSION:
        raise RecipeError(f"schemaVersion: expected {SCHEMA_VERSION}")
    _expect_string(data["id"], "id")
    if data["status"] != RECIPE_STATUS:
        raise RecipeError(f"status: expected {RECIPE_STATUS}")
    if _expect_bool(data["shippingAllowed"], "shippingAllowed"):
        raise RecipeError("shippingAllowed must be false")
    if _expect_bool(data["editorApprovalClaimed"], "editorApprovalClaimed"):
        raise RecipeError("editorApprovalClaimed must be false")

    source = _expect_object(data["source"], "source")
    _expect_keys(source, "source", ["path", "sha256", "pixelSize"])
    source_path = _repo_path(root, source["path"], "source.path")
    source_digest = _expect_sha256(source["sha256"], "source.sha256")
    if _sha256_file(source_path) != source_digest:
        raise RecipeError("source.sha256: source digest mismatch")
    source_size = _size(source["pixelSize"], "source.pixelSize")
    source_rgb = _load_rgb(source_path, source_size, "source")

    bindings_raw = data["bindings"]
    if not isinstance(bindings_raw, list) or not bindings_raw:
        raise RecipeError("bindings: expected one or more binding objects")
    binding_digests: dict[str, str] = {}
    for index, item in enumerate(bindings_raw):
        label = f"bindings[{index}]"
        binding = _expect_object(item, label)
        _expect_keys(binding, label, ["id", "path", "sha256"])
        binding_id = _expect_string(binding["id"], f"{label}.id")
        if binding_id in binding_digests:
            raise RecipeError(f"{label}.id: duplicate {binding_id!r}")
        binding_path = _repo_path(root, binding["path"], f"{label}.path")
        binding_digest = _expect_sha256(binding["sha256"], f"{label}.sha256")
        if _sha256_file(binding_path) != binding_digest:
            raise RecipeError(f"{label}.sha256: binding digest mismatch")
        binding_digests[binding_id] = binding_digest

    masks_raw = data["masks"]
    if not isinstance(masks_raw, list) or not masks_raw:
        raise RecipeError("masks: expected one or more mask objects")
    mask_arrays: dict[str, np.ndarray] = {}
    for index, item in enumerate(masks_raw):
        label = f"masks[{index}]"
        mask_spec = _expect_object(item, label)
        _expect_keys(
            mask_spec,
            label,
            ["id", "path", "sha256", "pixelSize", "expectedPixelCount", "expectedByteMaskSha256"],
        )
        mask_id = _expect_string(mask_spec["id"], f"{label}.id")
        if mask_id in mask_arrays:
            raise RecipeError(f"{label}.id: duplicate {mask_id!r}")
        mask_path = _repo_path(root, mask_spec["path"], f"{label}.path")
        mask_digest = _expect_sha256(mask_spec["sha256"], f"{label}.sha256")
        if _sha256_file(mask_path) != mask_digest:
            raise RecipeError(f"{label}.sha256: mask file digest mismatch")
        mask_size = _size(mask_spec["pixelSize"], f"{label}.pixelSize")
        if mask_size != source_size:
            raise RecipeError(f"{label}.pixelSize: must match source.pixelSize")
        mask = _load_mask(mask_path, mask_size, label)
        expected_pixels = _expect_int(mask_spec["expectedPixelCount"], f"{label}.expectedPixelCount", 0)
        expected_mask_digest = _expect_sha256(
            mask_spec["expectedByteMaskSha256"], f"{label}.expectedByteMaskSha256"
        )
        if int(mask.sum()) != expected_pixels:
            raise RecipeError(f"{label}.expectedPixelCount: mask pixel count mismatch")
        if _sha256_bytes(mask.astype(np.uint8).tobytes(order="C")) != expected_mask_digest:
            raise RecipeError(f"{label}.expectedByteMaskSha256: byte-mask digest mismatch")
        mask_arrays[mask_id] = mask

    crop_value = _expect_object(data["crop"], "crop")
    _expect_keys(crop_value, "crop", ["x", "y", "width", "height"])
    crop_x = _expect_int(crop_value["x"], "crop.x", 0)
    crop_y = _expect_int(crop_value["y"], "crop.y", 0)
    crop_width = _expect_int(crop_value["width"], "crop.width", 1)
    crop_height = _expect_int(crop_value["height"], "crop.height", 1)
    if crop_x + crop_width > source_size[0] or crop_y + crop_height > source_size[1]:
        raise RecipeError("crop: rectangle exceeds source bounds")
    crop = (crop_x, crop_y, crop_width, crop_height)

    expressions = _expect_object(data["expressions"], "expressions")
    _expect_keys(expressions, "expressions", ["subject", "authorization", "donor"])
    binding_ids = set(binding_digests)
    full_subject = _eval_expression(expressions["subject"], mask_arrays, binding_ids, "expressions.subject")
    full_authorization = _eval_expression(
        expressions["authorization"], mask_arrays, binding_ids, "expressions.authorization"
    )
    full_donor = _eval_expression(expressions["donor"], mask_arrays, binding_ids, "expressions.donor")
    crop_slice = np.s_[crop_y : crop_y + crop_height, crop_x : crop_x + crop_width]
    subject = full_subject[crop_slice].copy()
    authorization = full_authorization[crop_slice].copy()
    donor = full_donor[crop_slice].copy() & ~authorization

    synthesis = _validate_synthesis(data["synthesis"])
    thresholds = _validate_thresholds(data["thresholds"])
    del thresholds
    patch_radius = int(synthesis["patchRadius"])
    valid_donor_centers = _erode(donor, patch_radius)
    if not subject.any():
        raise RecipeError("expressions.subject: crop result is empty")
    if not authorization.any():
        raise RecipeError("expressions.authorization: crop result is empty")
    if not donor.any():
        raise RecipeError("expressions.donor: crop result is empty after authorization subtraction")
    if not valid_donor_centers.any():
        raise RecipeError("expressions.donor: no valid donor centers remain after patch erosion")

    seed_sha256 = _sha256_bytes(_canonical_json(_seed_material(data)))
    measurements = {
        "subject": _mask_measure(subject),
        "authorization": _mask_measure(authorization),
        "donor": _mask_measure(donor),
        "validDonorCenters": _mask_measure(valid_donor_centers),
    }

    if require_expected and "expected" not in data:
        raise RecipeError("expected: required for build and verify")
    if "expected" in data:
        expected = _expect_object(data["expected"], "expected")
        _expect_keys(
            expected,
            "expected",
            ["seedSha256", "subject", "authorization", "donor", "validDonorCenters", "candidateSha256"],
        )
        _expect_sha256(expected["seedSha256"], "expected.seedSha256")
        for key in ("subject", "authorization", "donor", "validDonorCenters"):
            _validate_measure(expected[key], f"expected.{key}")
        _expect_sha256(expected["candidateSha256"], "expected.candidateSha256")

    output = _expect_object(data["output"], "output")
    _expect_keys(output, "output", ["directory", "receiptPath", "files"])
    output_directory = _repo_path(root, output["directory"], "output.directory", must_exist=False)
    if not _inside(output_directory, (root / BUILD_PREFIX).resolve()):
        raise RecipeError(f"output.directory must be below {BUILD_PREFIX.as_posix()}")
    receipt_path = _repo_path(root, output["receiptPath"], "output.receiptPath", must_exist=False)
    if not _inside(receipt_path, backstage_root):
        raise RecipeError(f"output.receiptPath must be below {BACKSTAGE_PREFIX.as_posix()}")
    files = _expect_object(output["files"], "output.files")
    required_files = [
        "candidate",
        "authorization",
        "subject",
        "donor",
        "validDonorCenters",
        "provenanceX",
        "provenanceY",
    ]
    _expect_keys(files, "output.files", required_files)
    output_names: dict[str, str] = {}
    for key in required_files:
        name = _expect_string(files[key], f"output.files.{key}")
        if Path(name).name != name or not name.lower().endswith(".png"):
            raise RecipeError(f"output.files.{key}: expected a .png basename")
        output_names[key] = name
    if len(set(output_names.values())) != len(output_names):
        raise RecipeError("output.files: filenames must be unique")

    return LoadedRecipe(
        root=root,
        path=path,
        relative_path=path.relative_to(root).as_posix(),
        raw_bytes=raw,
        data=data,
        source_path=source_path,
        source_rgb=source_rgb,
        mask_arrays=mask_arrays,
        binding_digests=binding_digests,
        crop=crop,
        subject=subject,
        authorization=authorization,
        donor=donor,
        valid_donor_centers=valid_donor_centers,
        seed_sha256=seed_sha256,
        measurements=measurements,
        output_directory=output_directory,
        receipt_path=receipt_path,
        output_names=output_names,
    )


def _hashed_indices(y: np.ndarray, x: np.ndarray, salt: int, seed: int, modulus: int) -> np.ndarray:
    values = y.astype(np.uint64) * np.uint64(0x9E3779B185EBCA87)
    values ^= x.astype(np.uint64) * np.uint64(0xC2B2AE3D27D4EB4F)
    salted_seed = (seed + salt * 0x165667B19E3779F9) & 0xFFFFFFFFFFFFFFFF
    values ^= np.uint64(salted_seed)
    values ^= values >> np.uint64(30)
    values *= np.uint64(0xBF58476D1CE4E5B9)
    values ^= values >> np.uint64(27)
    values *= np.uint64(0x94D049BB133111EB)
    values ^= values >> np.uint64(31)
    return (values % np.uint64(modulus)).astype(np.int64)


def _patch_cost(
    guide: np.ndarray,
    low_source: np.ndarray,
    target: np.ndarray,
    target_y: np.ndarray,
    target_x: np.ndarray,
    source_y: np.ndarray,
    source_x: np.ndarray,
    radius: int,
) -> np.ndarray:
    height, width = target.shape
    total = np.zeros(target_y.size, dtype=np.float64)
    total_weight = np.zeros(target_y.size, dtype=np.float64)
    for dy, dx in _disk_offsets(radius):
        ty = target_y + dy
        tx = target_x + dx
        valid = (ty >= 0) & (ty < height) & (tx >= 0) & (tx < width)
        if not valid.any():
            continue
        clipped_y = np.clip(ty, 0, height - 1)
        clipped_x = np.clip(tx, 0, width - 1)
        sy = source_y + dy
        sx = source_x + dx
        differences = guide[clipped_y, clipped_x].astype(np.int32) - low_source[sy, sx].astype(np.int32)
        squared = np.sum(differences.astype(np.int64) ** 2, axis=1)
        known_weight = np.where(target[clipped_y, clipped_x], 1.0, 4.0)
        weight = known_weight * valid.astype(np.float64)
        total += squared * weight
        total_weight += weight
    if np.any(total_weight == 0):
        raise RecipeError("synthesis: target patch has no in-bounds samples")
    return total / total_weight


def _source_only_patchmatch(loaded: LoadedRecipe) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    cv2.setNumThreads(1)
    cv2.setRNGSeed(0)
    x, y, width, height = loaded.crop
    source = loaded.source_rgb[y : y + height, x : x + width].copy()
    target = loaded.authorization
    synthesis = loaded.data["synthesis"]
    guide_spec = synthesis["guide"]
    algorithm = cv2.INPAINT_TELEA if guide_spec["algorithm"] == "telea" else cv2.INPAINT_NS
    guide = cv2.inpaint(source, target.astype(np.uint8) * 255, float(guide_spec["radius"]), algorithm)
    sigma = float(guide_spec["blurSigma"])
    if sigma > 0:
        guide = cv2.GaussianBlur(guide, (0, 0), sigmaX=sigma, sigmaY=sigma, borderType=cv2.BORDER_REFLECT_101)
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
        indices = _hashed_indices(target_y, target_x, salt, seed, donor_coordinates.shape[0])
        proposal_y = donor_coordinates[indices, 0].astype(np.int32)
        proposal_x = donor_coordinates[indices, 1].astype(np.int32)
        cost = _patch_cost(guide, low_source, target, target_y, target_x, proposal_y, proposal_x, radius)
        better = cost < best_cost
        best_cost[better] = cost[better]
        best_y[better] = proposal_y[better]
        best_x[better] = proposal_x[better]

    map_y = np.full((height, width), -1, dtype=np.int32)
    map_x = np.full((height, width), -1, dtype=np.int32)
    map_y[target_y, target_x] = best_y
    map_x[target_y, target_x] = best_x
    for sweep in range(int(synthesis["sweeps"])):
        offsets = ((0, -1), (-1, 0)) if sweep % 2 == 0 else ((0, 1), (1, 0))
        snapshot_y = map_y.copy()
        snapshot_x = map_x.copy()
        for neighbor_dy, neighbor_dx in offsets:
            neighbor_y = target_y + neighbor_dy
            neighbor_x = target_x + neighbor_dx
            valid_neighbor = (
                (neighbor_y >= 0)
                & (neighbor_y < height)
                & (neighbor_x >= 0)
                & (neighbor_x < width)
            )
            clipped_y = np.clip(neighbor_y, 0, height - 1)
            clipped_x = np.clip(neighbor_x, 0, width - 1)
            proposal_y = snapshot_y[clipped_y, clipped_x] - neighbor_dy
            proposal_x = snapshot_x[clipped_y, clipped_x] - neighbor_dx
            valid_proposal = valid_neighbor & (proposal_y >= 0) & (proposal_x >= 0)
            safe_y = np.clip(proposal_y, 0, height - 1)
            safe_x = np.clip(proposal_x, 0, width - 1)
            valid_proposal &= loaded.valid_donor_centers[safe_y, safe_x]
            selected = np.flatnonzero(valid_proposal)
            if selected.size:
                cost = _patch_cost(
                    guide,
                    low_source,
                    target,
                    target_y[selected],
                    target_x[selected],
                    proposal_y[selected],
                    proposal_x[selected],
                    radius,
                )
                better_local = cost < best_cost[selected]
                better_indices = selected[better_local]
                best_cost[better_indices] = cost[better_local]
                best_y[better_indices] = proposal_y[better_indices]
                best_x[better_indices] = proposal_x[better_indices]
        for random_index in range(int(synthesis["randomCandidatesPerSweep"])):
            salt = 1_000_000 + sweep * 10_000 + random_index
            indices = _hashed_indices(target_y, target_x, salt, seed, donor_coordinates.shape[0])
            proposal_y = donor_coordinates[indices, 0].astype(np.int32)
            proposal_x = donor_coordinates[indices, 1].astype(np.int32)
            cost = _patch_cost(guide, low_source, target, target_y, target_x, proposal_y, proposal_x, radius)
            better = cost < best_cost
            best_cost[better] = cost[better]
            best_y[better] = proposal_y[better]
            best_x[better] = proposal_x[better]
        map_y[target_y, target_x] = best_y
        map_x[target_y, target_x] = best_x

    if np.any(~loaded.valid_donor_centers[best_y, best_x]):
        raise RecipeError("synthesis: provenance escaped valid donor centers")
    candidate = source.copy()
    candidate[target_y, target_x] = source[best_y, best_x]
    if np.any(candidate[~target] != source[~target]):
        raise RecipeError("synthesis: pixels outside authorization changed")
    return candidate, map_y, map_x


def _cross_seam_values(candidate: np.ndarray, target: np.ndarray) -> np.ndarray:
    values: list[np.ndarray] = []
    for dy, dx in ((0, 1), (1, 0)):
        y0a, y1a = (0, target.shape[0] - dy)
        x0a, x1a = (0, target.shape[1] - dx)
        first_mask = target[y0a:y1a, x0a:x1a]
        second_mask = target[y0a + dy : y1a + dy, x0a + dx : x1a + dx]
        crossing = first_mask != second_mask
        if crossing.any():
            first = candidate[y0a:y1a, x0a:x1a][crossing].astype(np.int16)
            second = candidate[y0a + dy : y1a + dy, x0a + dx : x1a + dx][crossing].astype(np.int16)
            values.append(np.mean(np.abs(first - second), axis=1))
    if not values:
        return np.empty(0, dtype=np.float64)
    return np.concatenate(values).astype(np.float64)


def _gradient_magnitude(rgb: np.ndarray) -> np.ndarray:
    gray = (77.0 * rgb[:, :, 0] + 150.0 * rgb[:, :, 1] + 29.0 * rgb[:, :, 2]) / 256.0
    gx = cv2.Sobel(gray.astype(np.float32), cv2.CV_32F, 1, 0, ksize=3, borderType=cv2.BORDER_REFLECT_101)
    gy = cv2.Sobel(gray.astype(np.float32), cv2.CV_32F, 0, 1, ksize=3, borderType=cv2.BORDER_REFLECT_101)
    return np.sqrt(gx * gx + gy * gy)


def _round(value: float) -> float:
    return round(float(value), 6)


def _measure_quality(
    loaded: LoadedRecipe, candidate: np.ndarray, provenance_y: np.ndarray, provenance_x: np.ndarray
) -> tuple[dict[str, Any], tuple[str, ...]]:
    x, y, width, height = loaded.crop
    source = loaded.source_rgb[y : y + height, x : x + width]
    target = loaded.authorization
    thresholds = loaded.data["thresholds"]
    target_count = int(target.sum())
    changed = np.any(candidate[target] != source[target], axis=1)
    changed_fraction = float(changed.mean())
    donor_pairs = np.stack([provenance_y[target], provenance_x[target]], axis=1)
    unique_pairs, reuse_counts = np.unique(donor_pairs, axis=0, return_counts=True)
    seam = _cross_seam_values(candidate, target)
    target_gradient = _gradient_magnitude(candidate)[target]
    donor_gradient = _gradient_magnitude(source)[loaded.donor]
    gradient_denominator = float(np.median(donor_gradient))
    gradient_ratio = float(np.median(target_gradient) / gradient_denominator) if gradient_denominator > 0 else math.inf
    generated_pixels = candidate[target]
    luma = (
        77 * generated_pixels[:, 0].astype(np.uint16)
        + 150 * generated_pixels[:, 1].astype(np.uint16)
        + 29 * generated_pixels[:, 2].astype(np.uint16)
    ) / 256.0
    mean_color_delta = float(
        np.linalg.norm(candidate[target].mean(axis=0, dtype=np.float64) - source[loaded.donor].mean(axis=0, dtype=np.float64))
    )
    tile_size = int(loaded.data["synthesis"]["tileSize"])
    tile_columns = math.ceil(width / tile_size)
    donor_tile_ids = (donor_pairs[:, 0] // tile_size) * tile_columns + donor_pairs[:, 1] // tile_size
    _, donor_tile_counts = np.unique(donor_tile_ids, return_counts=True)
    max_tile_share = float(donor_tile_counts.max() / target_count)

    metrics = {
        "authorizationPixelCount": target_count,
        "donorPixelCount": int(loaded.donor.sum()),
        "validDonorCenterCount": int(loaded.valid_donor_centers.sum()),
        "uniqueDonorCenterCount": int(unique_pairs.shape[0]),
        "maximumDonorCenterReuse": int(reuse_counts.max()),
        "maximumGeneratedSharePerTile": _round(max_tile_share),
        "crossSeam": {
            "sampleCount": int(seam.size),
            "mean": _round(float(np.mean(seam))) if seam.size else None,
            "p95": _round(float(np.percentile(seam, 95))) if seam.size else None,
            "p99": _round(float(np.percentile(seam, 99))) if seam.size else None,
        },
        "interiorGradientRatio": _round(gradient_ratio) if math.isfinite(gradient_ratio) else None,
        "generatedLuma": {"p01": _round(float(np.percentile(luma, 1))), "p99": _round(float(np.percentile(luma, 99)))},
        "meanColorDelta": _round(mean_color_delta),
        "changedTargetFraction": _round(changed_fraction),
        "outsideAuthorizationChangedPixelCount": int(
            np.any(candidate[~target] != source[~target], axis=1).sum()
        ),
        "provenanceComplete": bool(np.all((provenance_y[target] >= 0) & (provenance_x[target] >= 0))),
        "provenanceAuthorized": bool(np.all(loaded.valid_donor_centers[provenance_y[target], provenance_x[target]])),
    }

    failures: list[str] = []
    if metrics["donorPixelCount"] < thresholds["minimumDonorPixels"]:
        failures.append("DONOR_PIXELS_BELOW_MINIMUM")
    if metrics["validDonorCenterCount"] < thresholds["minimumValidDonorCenters"]:
        failures.append("VALID_DONOR_CENTERS_BELOW_MINIMUM")
    if metrics["uniqueDonorCenterCount"] < thresholds["minimumUniqueDonorCenters"]:
        failures.append("UNIQUE_DONOR_CENTERS_BELOW_MINIMUM")
    if metrics["maximumDonorCenterReuse"] > thresholds["maximumDonorCenterReuse"]:
        failures.append("DONOR_CENTER_REUSE_ABOVE_MAXIMUM")
    if metrics["maximumGeneratedSharePerTile"] > thresholds["maximumGeneratedSharePerTile"]:
        failures.append("GENERATED_SHARE_PER_TILE_ABOVE_MAXIMUM")
    if seam.size == 0:
        failures.append("CROSS_SEAM_HAS_NO_SAMPLES")
    else:
        if metrics["crossSeam"]["mean"] > thresholds["crossSeam"]["meanMaximum"]:
            failures.append("CROSS_SEAM_MEAN_ABOVE_MAXIMUM")
        if metrics["crossSeam"]["p95"] > thresholds["crossSeam"]["p95Maximum"]:
            failures.append("CROSS_SEAM_P95_ABOVE_MAXIMUM")
        if metrics["crossSeam"]["p99"] > thresholds["crossSeam"]["p99Maximum"]:
            failures.append("CROSS_SEAM_P99_ABOVE_MAXIMUM")
    if metrics["interiorGradientRatio"] is None:
        failures.append("INTERIOR_GRADIENT_RATIO_UNDEFINED")
    elif metrics["interiorGradientRatio"] < thresholds["interiorGradientRatio"]["minimum"]:
        failures.append("INTERIOR_GRADIENT_RATIO_BELOW_MINIMUM")
    elif metrics["interiorGradientRatio"] > thresholds["interiorGradientRatio"]["maximum"]:
        failures.append("INTERIOR_GRADIENT_RATIO_ABOVE_MAXIMUM")
    if metrics["generatedLuma"]["p01"] < thresholds["generatedLuma"]["p01Minimum"]:
        failures.append("GENERATED_LUMA_P01_BELOW_MINIMUM")
    if metrics["generatedLuma"]["p99"] > thresholds["generatedLuma"]["p99Maximum"]:
        failures.append("GENERATED_LUMA_P99_ABOVE_MAXIMUM")
    if metrics["meanColorDelta"] > thresholds["maximumMeanColorDelta"]:
        failures.append("MEAN_COLOR_DELTA_ABOVE_MAXIMUM")
    changed_threshold = thresholds["changedTargetFraction"]
    if metrics["changedTargetFraction"] < changed_threshold["minimum"]:
        failures.append("CHANGED_TARGET_FRACTION_BELOW_MINIMUM")
    if metrics["changedTargetFraction"] > changed_threshold["maximum"]:
        failures.append("CHANGED_TARGET_FRACTION_ABOVE_MAXIMUM")
    if metrics["outsideAuthorizationChangedPixelCount"] != 0:
        failures.append("PIXELS_CHANGED_OUTSIDE_AUTHORIZATION")
    if not metrics["provenanceComplete"]:
        failures.append("PROVENANCE_INCOMPLETE")
    if not metrics["provenanceAuthorized"]:
        failures.append("PROVENANCE_OUTSIDE_VALID_DONOR_CENTERS")
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
        raise RecipeError("expected forensic mismatch: " + ", ".join(sorted(mismatches)))

    first = _source_only_patchmatch(loaded)
    second = _source_only_patchmatch(loaded)
    if not all(np.array_equal(left, right) for left, right in zip(first, second)):
        raise RecipeError("determinism: two in-process synthesis runs differ")
    candidate, provenance_y, provenance_x = first
    candidate_sha = _sha256_bytes(candidate.tobytes(order="C"))
    metrics, failures = _measure_quality(loaded, candidate, provenance_y, provenance_x)
    if expected is not None:
        if expected["candidateSha256"] != candidate_sha:
            mismatches.append("EXPECTED_CANDIDATE_SHA256_MISMATCH")
    if require_expected and mismatches:
        raise RecipeError("expected forensic mismatch: " + ", ".join(sorted(mismatches)))
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


def _png_bytes(array: np.ndarray, mode: str | None = None) -> bytes:
    buffer = io.BytesIO()
    image = Image.fromarray(array)
    if mode is not None and image.mode != mode:
        raise RecipeError(f"output: expected Pillow mode {mode}, got {image.mode}")
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def _artifact_bytes(analysis: Analysis) -> dict[str, bytes]:
    target = analysis.loaded.authorization
    provenance_x = np.zeros_like(analysis.provenance_x, dtype=np.uint16)
    provenance_y = np.zeros_like(analysis.provenance_y, dtype=np.uint16)
    if analysis.loaded.crop[2] > 65534 or analysis.loaded.crop[3] > 65534:
        raise RecipeError("output: crop dimensions exceed 16-bit provenance encoding")
    provenance_x[target] = analysis.provenance_x[target].astype(np.uint16) + 1
    provenance_y[target] = analysis.provenance_y[target].astype(np.uint16) + 1
    mask = lambda value: _png_bytes(value.astype(np.uint8) * 255, "L")
    return {
        "candidate": _png_bytes(analysis.candidate, "RGB"),
        "authorization": mask(analysis.loaded.authorization),
        "subject": mask(analysis.loaded.subject),
        "donor": mask(analysis.loaded.donor),
        "validDonorCenters": mask(analysis.loaded.valid_donor_centers),
        "provenanceX": _png_bytes(provenance_x, "I;16"),
        "provenanceY": _png_bytes(provenance_y, "I;16"),
    }


def _runtime_record() -> dict[str, str]:
    return {
        "python": sys.version.split()[0],
        "numpy": np.__version__,
        "pillow": Image.__version__,
        "opencv": cv2.__version__,
    }


def _receipt(analysis: Analysis, artifacts: dict[str, bytes]) -> dict[str, Any]:
    loaded = analysis.loaded
    outputs: dict[str, Any] = {}
    for key in sorted(artifacts):
        path = loaded.output_directory / loaded.output_names[key]
        outputs[key] = {
            "path": path.relative_to(loaded.root).as_posix(),
            "sha256": _sha256_bytes(artifacts[key]),
            "byteCount": len(artifacts[key]),
        }
    script_path = Path(__file__).resolve()
    return {
        "schemaVersion": SCHEMA_VERSION,
        "status": RECEIPT_STATUS,
        "scope": "NON_SHIPPING_BACKSTAGE_ONLY",
        "authority": {
            "editorApprovalClaimed": False,
            "productionApprovalClaimed": False,
            "shippingAllowed": False,
        },
        "recipe": {
            "path": loaded.relative_path,
            "sha256": _sha256_bytes(loaded.raw_bytes),
            "id": loaded.data["id"],
        },
        "seedSha256": loaded.seed_sha256,
        "crop": loaded.data["crop"],
        "expressions": loaded.data["expressions"],
        "measurements": loaded.measurements,
        "candidatePixelSha256": analysis.candidate_sha256,
        "metrics": analysis.metrics,
        "thresholds": loaded.data["thresholds"],
        "failedGates": [],
        "determinism": {"inProcessReplayCount": 2, "byteIdentical": True},
        "outputs": outputs,
        "tool": {
            "path": script_path.relative_to(loaded.root).as_posix() if _inside(script_path, loaded.root) else script_path.name,
            "sha256": _sha256_file(script_path),
            "runtime": _runtime_record(),
        },
    }


def _write_build(analysis: Analysis, artifacts: dict[str, bytes], receipt_bytes: bytes) -> None:
    loaded = analysis.loaded
    output = loaded.output_directory
    receipt = loaded.receipt_path
    sidecar = receipt.with_name(receipt.name + ".sha256")
    if output.exists():
        raise RecipeError(f"build refuses existing output directory: {output.relative_to(loaded.root)}")
    if receipt.exists() or sidecar.exists():
        raise RecipeError("build refuses existing receipt or receipt sidecar")
    output.parent.mkdir(parents=True, exist_ok=True)
    if not receipt.parent.is_dir():
        raise RecipeError("output.receiptPath parent directory does not exist")
    temporary = Path(tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=output.parent))
    created_output = False
    created_receipt = False
    try:
        for key, payload in artifacts.items():
            (temporary / loaded.output_names[key]).write_bytes(payload)
        os.replace(temporary, output)
        created_output = True
        with receipt.open("xb") as handle:
            handle.write(receipt_bytes)
        created_receipt = True
        receipt_digest = _sha256_bytes(receipt_bytes)
        with sidecar.open("xb") as handle:
            handle.write(f"{receipt_digest}  {receipt.name}\n".encode("ascii"))
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary)
        if sidecar.exists():
            sidecar.unlink()
        if created_receipt and receipt.exists():
            receipt.unlink()
        if created_output and output.exists():
            shutil.rmtree(output)
        raise


def _verify_existing(analysis: Analysis, artifacts: dict[str, bytes], receipt_bytes: bytes) -> None:
    loaded = analysis.loaded
    receipt_path = loaded.receipt_path
    sidecar = receipt_path.with_name(receipt_path.name + ".sha256")
    if not receipt_path.is_file() or not sidecar.is_file() or receipt_path.is_symlink() or sidecar.is_symlink():
        raise RecipeError("verify: receipt or receipt sidecar is missing")
    actual_receipt = receipt_path.read_bytes()
    if actual_receipt != receipt_bytes:
        raise RecipeError("verify: receipt bytes do not match replay")
    expected_sidecar = f"{_sha256_bytes(actual_receipt)}  {receipt_path.name}\n".encode("ascii")
    if sidecar.read_bytes() != expected_sidecar:
        raise RecipeError("verify: receipt sidecar mismatch")
    output_directory = loaded.output_directory
    if not output_directory.is_dir() or output_directory.is_symlink():
        raise RecipeError("verify: output directory is missing or is a symlink")
    expected_names = set(loaded.output_names.values())
    actual_names = {path.name for path in output_directory.iterdir()}
    if actual_names != expected_names:
        raise RecipeError("verify: output directory membership differs from recipe")
    for key, expected_bytes in artifacts.items():
        path = loaded.output_directory / loaded.output_names[key]
        if not path.is_file() or path.is_symlink():
            raise RecipeError(f"verify: missing output {key}")
        if path.read_bytes() != expected_bytes:
            raise RecipeError(f"verify: output bytes differ for {key}")


def run(mode: str, recipe_path: Path, root: Path) -> dict[str, Any]:
    if mode not in {"inspect", "build", "verify"}:
        raise RecipeError(f"unsupported mode: {mode}")
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
        raise RecipeError("objective QA failed: " + ", ".join(analysis.failed_gates))
    artifacts = _artifact_bytes(analysis)
    receipt_bytes = _canonical_json(_receipt(analysis, artifacts))
    if mode == "build":
        _write_build(analysis, artifacts, receipt_bytes)
    else:
        _verify_existing(analysis, artifacts, receipt_bytes)
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("inspect", "build", "verify"))
    parser.add_argument("--recipe", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        summary = run(arguments.mode, arguments.recipe, Path.cwd())
    except RecipeError as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2
    print(_canonical_json(summary).decode("utf-8"), end="")
    return 0 if summary["objectiveGate"] == "PASS" and not summary["expectedMismatches"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
