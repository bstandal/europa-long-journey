#!/usr/bin/env python3
"""Author and inspect one source-only Harvest central-grain underlay candidate.

This command is deliberately fail-closed.  It can create a deterministic,
backstage candidate and objective diagnostics; it cannot grant artistic,
editorial, production-master, package, or shipping authority.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter


SCRIPT_PATH = "native/scripts/build-harvest-central-grain-underlay.py"
PYTHON_PATH = "/Users/bard/.local/share/uv/tools/mflux/bin/python"
SPEC = {
    "path": "native/content/backstage/harvest/central-grain-underlay-v26.spec.json",
    "sha256": "369aecb2357a381c32a3c394d95a7128ec8b722492a391ea54d9bbde37261964",
}

SOURCE = {
    "path": "native/design/phase1/harvest/production-master-candidate-v26-garments-local-composite.png",
    "sha256": "e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca",
    "pixelSize": [1290, 2796],
}
SCENE_FIXTURE = {
    "path": "native/phase1/fixtures/harvest-option-1.scene.json",
    "sha256": "c9cfa96d9cc61f7421ecf0efc0136d2f716daa5fb851a4dd99f2943e1b9b8028",
}
MASKS = {
    "central-grain": {
        "path": "native/content/backstage/harvest/semantic-masks-v26.provisional/central-grain.png",
        "sha256": "85dbd5f14ed998ed3874721948678acd0411e3e0e91d443c9d47555fc047aea3",
    },
    "allocation-cloth": {
        "path": "native/content/backstage/harvest/semantic-masks-v26.provisional/allocation-cloth.png",
        "sha256": "f87a639685ccba48127cb3fbcfef46e611228e5c0645aa3d4c4c901589f06627",
    },
    "foreground-occluders": {
        "path": "native/content/backstage/harvest/semantic-masks-v26.provisional/foreground-occluders.png",
        "sha256": "8810139ae423683c5434690a5698bd28940338790b75ba9d3ca897d98a29cf35",
    },
}
SEED_MATERIAL = "|".join(
    [
        SPEC["sha256"],
        SOURCE["sha256"],
        *(MASKS[name]["sha256"] for name in sorted(MASKS)),
        (
            "r5b-corrected-T;scales=0.125,0.25,0.5,1;patches=7,9,9,9;sweeps=8;"
            "guide=authorization-conditioned-donor-only;harmonic=192;"
            "residual=source-built-seam-to-direct-core;vote=disk-r4-integer"
        ),
    ]
)
SEED_SHA256 = hashlib.sha256(SEED_MATERIAL.encode("utf-8")).hexdigest()
SEED_WORD = int(SEED_SHA256[:16], 16)

CROP = [192, 1752, 896, 896]
CLOSE_RADIUS = 3
DILATE_RADIUS = 4
PATCH_RADIUS = 4
SEAM_RING_WIDTH = 12
PARALLAX_EXTREMA = [[-8, -3], [8, 3]]
HARMONIC_ITERATIONS = 192

EXPECTED = {
    "subjectCropPixelCount": 190_234,
    "subjectCropByteMaskSha256": "45420722013d1a44dac8e9b3b12394f2fcdbd69464618083dec044bbb97b82a7",
    "closedPixelCount": 190_259,
    "closedCropByteMaskSha256": "3a93c6ef9a93c830793f919a1a06f69d3c1f2327b08d19535cd5378b978a6931",
    "targetPixelCount": 196_727,
    "targetBoundsInclusive": [120, 433, 787, 838],
    "targetForegroundOverlap": 0,
    "targetByteMaskSha256": "3bebce3ae454c8cd08dcaae0a9b67221ca540b554be240962e100e958c1fc866",
    "seamRingPixelCount": 19_805,
    "seamRingByteMaskSha256": "36d104f25471704bb9932806ad881dae793e31b0e24676c5b112c7d68e8f7121",
    "corePixelCount": 176_922,
    "coreByteMaskSha256": "f8c8374a37e2fe39c10d8ca77cae2c7f059dea119d6774f2e902b6a316e05544",
    "outsideTargetPixelCount": 606_089,
    "outsideTargetByteMaskSha256": "612102dcda59863755d2c49a0cdb1e1ab1e89efe793a26da9341084b6cd338f5",
    "legacyFrozenFringePixelCount": 6_468,
    "legacyFrozenFringeByteMaskSha256": "0425a822c1cad8156210338c66f772af23cb69cb3b8b362f2e98aedd40bc0edc",
    "rawDonorPixelCount": 148_816,
    "largestDonorPixelCount": 148_493,
    "largestDonorByteMaskSha256": "4fe31dc08debbc48c7d061b75f636cb0e0946350a3e37e3bb4de793d26996bb7",
    "validPatchCenterCount": 132_392,
    "validPatchCenterByteMaskSha256": "ab4bd5e4a562099c4597381667c5d5d86226e66ddc589f95b4e353c5f6d5329a",
}

GATES = {
    "crossSeam": {"meanMaximum": 14.2, "p95Maximum": 39.2, "p99Maximum": 80.1},
    "interiorGradientRatio": {"minimum": 0.70, "maximum": 1.35},
    "generatedCoreMeanRedMinusBlueDeltaMaximum": 8.0,
    "donorMeanRedMinusBlue": 10.90,
    "generatedLuma": {"p01Minimum": 24.0, "p99Maximum": 107.0},
    "minimumUniqueDonorCenters": 30_000,
    "maximumDonorCenterReuse": 64,
    "maximumGeneratedSharePer64PixelDonorTile": 0.08,
}

FORBIDDEN_AUTHORITIES = [
    "EDITOR_APPROVED_AS_PRODUCTION_MASTER",
    "EDITOR_APPROVED_PRODUCTION_MASTER",
    "PRODUCTION_ASSET_APPROVED",
    "PRODUCTION_INPUTS_LOCKED",
    "SHIPPING_ALLOWED",
]


@dataclass(frozen=True)
class SynthesisResult:
    candidate: np.ndarray
    provenance_y: np.ndarray
    provenance_x: np.ndarray
    authorization: np.ndarray
    target: np.ndarray
    semantic_subject: np.ndarray
    donor: np.ndarray
    valid_centers: np.ndarray
    seam_ring: np.ndarray
    stages: tuple[dict[str, Any], ...]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, separators=(",", ": ")) + "\n").encode("utf-8")


def png_bytes(array: np.ndarray, mode: str | None = None) -> bytes:
    # Pillow infers L/RGB/I;16 from the array dtype and shape.  The optional
    # mode remains in the helper signature for explicit callers but never
    # triggers Pillow's deprecated dtype-conversion path.
    image = Image.fromarray(array)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", compress_level=9, optimize=False)
    return buffer.getvalue()


def disk_offsets(radius: int) -> tuple[tuple[int, int], ...]:
    return tuple(
        (dy, dx)
        for dy in range(-radius, radius + 1)
        for dx in range(-radius, radius + 1)
        if dx * dx + dy * dy <= radius * radius
    )


def shifted_zero(mask: np.ndarray, dy: int, dx: int) -> np.ndarray:
    """Translate a binary mask with zero padding.

    The returned location ``(y + dy, x + dx)`` receives input ``(y, x)``.
    """

    height, width = mask.shape
    result = np.zeros_like(mask, dtype=bool)
    source_y0 = max(0, -dy)
    source_y1 = min(height, height - dy)
    source_x0 = max(0, -dx)
    source_x1 = min(width, width - dx)
    if source_y0 < source_y1 and source_x0 < source_x1:
        result[
            source_y0 + dy : source_y1 + dy,
            source_x0 + dx : source_x1 + dx,
        ] = mask[source_y0:source_y1, source_x0:source_x1]
    return result


def binary_dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    return np.logical_or.reduce([shifted_zero(mask, dy, dx) for dy, dx in disk_offsets(radius)])


def binary_erode(mask: np.ndarray, radius: int) -> np.ndarray:
    return np.logical_and.reduce([shifted_zero(mask, -dy, -dx) for dy, dx in disk_offsets(radius)])


def binary_close(mask: np.ndarray, radius: int) -> np.ndarray:
    return binary_erode(binary_dilate(mask, radius), radius)


def bounds_inclusive(mask: np.ndarray) -> list[int]:
    ys, xs = np.where(mask)
    require(len(xs) > 0, "Cannot measure an empty mask")
    return [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]


def largest_component(mask: np.ndarray) -> np.ndarray:
    """Return the largest 8-connected component, deterministically."""

    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    best: list[int] = []
    for start_y, start_x in zip(*np.where(mask)):
        if seen[start_y, start_x]:
            continue
        stack = [int(start_y) * width + int(start_x)]
        seen[start_y, start_x] = True
        component: list[int] = []
        while stack:
            flat = stack.pop()
            y, x = divmod(flat, width)
            component.append(flat)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dy == 0 and dx == 0:
                        continue
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < height and 0 <= xx < width and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append(yy * width + xx)
        if len(component) > len(best):
            best = component
    result = np.zeros_like(mask, dtype=bool)
    result.flat[best] = True
    return result


def nearest_true_coordinates(mask: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Compute a deterministic Manhattan nearest-source field with multi-source BFS."""

    height, width = mask.shape
    distance = np.full((height, width), np.iinfo(np.int32).max, dtype=np.int32)
    nearest_y = np.full((height, width), -1, dtype=np.int32)
    nearest_x = np.full((height, width), -1, dtype=np.int32)
    queue: deque[int] = deque()
    for y, x in zip(*np.where(mask)):
        distance[y, x] = 0
        nearest_y[y, x] = y
        nearest_x[y, x] = x
        queue.append(int(y) * width + int(x))
    while queue:
        flat = queue.popleft()
        y, x = divmod(flat, width)
        next_distance = distance[y, x] + 1
        # Fixed ordering is part of determinism and resolves equal-distance ties.
        for yy, xx in ((y - 1, x), (y, x - 1), (y, x + 1), (y + 1, x)):
            if 0 <= yy < height and 0 <= xx < width and next_distance < distance[yy, xx]:
                distance[yy, xx] = next_distance
                nearest_y[yy, xx] = nearest_y[y, x]
                nearest_x[yy, xx] = nearest_x[y, x]
                queue.append(yy * width + xx)
    return nearest_y, nearest_x, distance


def deterministic_indices(seed: int, count: int, modulus: int) -> np.ndarray:
    require(modulus > 0, "Candidate modulus must be positive")
    # The odd step is increased until it is coprime, producing a complete cycle.
    step = ((seed >> 17) | 1) % modulus
    if step == 0:
        step = 1
    while math.gcd(step, modulus) != 1:
        step = (step + 2) % modulus
        if step == 0:
            step = 1
    start = seed % modulus
    return (start + step * np.arange(count, dtype=np.int64)) % modulus


def block_seed(stage: int, y: int, x: int) -> int:
    value = (stage + 1) * 0x9E3779B1
    value ^= (y + 0x85EBCA77) * 0xC2B2AE3D
    value ^= (x + 0x27D4EB2F) * 0x165667B1
    value ^= value >> 16
    return value & 0x7FFFFFFF


def resize_rgb(array: np.ndarray, size: int) -> np.ndarray:
    return np.asarray(Image.fromarray(array).resize((size, size), Image.Resampling.LANCZOS))


def resize_mask(mask: np.ndarray, size: int) -> np.ndarray:
    return np.asarray(
        Image.fromarray(mask.astype(np.uint8) * 255).resize((size, size), Image.Resampling.NEAREST)
    ) > 127


def separable_gaussian(array: np.ndarray, radius: float) -> np.ndarray:
    """Deterministic float Gaussian convolution with zero padding."""

    sigma = max(0.25, float(radius))
    extent = max(1, int(math.ceil(sigma * 3.0)))
    offsets = np.arange(-extent, extent + 1, dtype=np.int32)
    kernel = np.exp(-(offsets.astype(np.float64) ** 2) / (2.0 * sigma * sigma))
    kernel /= np.sum(kernel)
    value = array.astype(np.float64, copy=False)
    for axis in (0, 1):
        result = np.zeros_like(value, dtype=np.float64)
        length = value.shape[axis]
        for offset, weight in zip(offsets.tolist(), kernel.tolist()):
            source_start = max(0, -offset)
            source_end = min(length, length - offset)
            if source_start >= source_end:
                continue
            source_slice = [slice(None)] * value.ndim
            destination_slice = [slice(None)] * value.ndim
            source_slice[axis] = slice(source_start, source_end)
            destination_slice[axis] = slice(source_start + offset, source_end + offset)
            result[tuple(destination_slice)] += value[tuple(source_slice)] * weight
        value = result
    return value


def masked_low_frequency(source: np.ndarray, visible: np.ndarray, radius: float) -> np.ndarray:
    weights = separable_gaussian(visible.astype(np.float64), radius)
    numerator = separable_gaussian(source.astype(np.float64) * visible[..., None], radius)
    result = source.astype(np.float64)
    supported = weights > 1e-9
    result[supported] = numerator[supported] / weights[supported, None]
    return result.astype(np.float32)


def harmonic_continuation(
    source: np.ndarray,
    target: np.ndarray,
    donor: np.ndarray,
    blur_radius: float,
    iterations: int,
    initial: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Build a fixed-iteration low-frequency guide from visible donor pixels."""

    low_source = masked_low_frequency(source, donor, blur_radius)
    nearest_y, nearest_x, _ = nearest_true_coordinates(donor)
    field = low_source.copy()
    target_y, target_x = np.where(target)
    if initial is None:
        field[target_y, target_x] = low_source[nearest_y[target_y, target_x], nearest_x[target_y, target_x]]
    else:
        require(initial.shape == field.shape, "Harmonic pyramid initialization has the wrong size")
        field[target_y, target_x] = initial[target_y, target_x]
    for _ in range(iterations):
        average = (
            np.roll(field, 1, axis=0)
            + np.roll(field, -1, axis=0)
            + np.roll(field, 1, axis=1)
            + np.roll(field, -1, axis=1)
        ) * 0.25
        field[target_y, target_x] = average[target_y, target_x]
    return field, low_source


def patch_cost(
    guide: np.ndarray,
    low_source: np.ndarray,
    target: np.ndarray,
    target_y: np.ndarray,
    target_x: np.ndarray,
    source_y: np.ndarray,
    source_x: np.ndarray,
    radius: int,
) -> np.ndarray:
    """Return weighted low-frequency patch SSD for one NNF proposal."""

    total = np.zeros(len(target_y), dtype=np.float64)
    weight_total = np.zeros(len(target_y), dtype=np.float64)
    for dy, dx in disk_offsets(radius):
        target_known = ~target[target_y + dy, target_x + dx]
        weight = np.where(target_known, 4.0, 1.0)
        difference = (
            guide[target_y + dy, target_x + dx].astype(np.float64)
            - low_source[source_y + dy, source_x + dx].astype(np.float64)
        )
        total += np.sum(difference * difference, axis=1) * weight
        weight_total += weight
    return total / (weight_total * 3.0)


def hash_field(y: np.ndarray, x: np.ndarray, salt: int) -> np.ndarray:
    """Stable integer hash used only for deterministic proposal ordering."""

    value = y.astype(np.uint64) * np.uint64(0x9E3779B185EBCA87)
    value ^= x.astype(np.uint64) * np.uint64(0xC2B2AE3D27D4EB4F)
    value ^= np.uint64(SEED_WORD)
    salt_word = ((int(salt) + 1) * 0x165667B19E3779F9) & ((1 << 64) - 1)
    value ^= np.uint64(salt_word)
    value ^= value >> np.uint64(29)
    value *= np.uint64(0x94D049BB133111EB)
    value ^= value >> np.uint64(31)
    return value


def project_to_valid(
    source_y: np.ndarray,
    source_x: np.ndarray,
    valid: np.ndarray,
    nearest_y: np.ndarray,
    nearest_x: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    height, width = valid.shape
    clipped_y = np.clip(source_y, 0, height - 1).astype(np.int32)
    clipped_x = np.clip(source_x, 0, width - 1).astype(np.int32)
    invalid = ~valid[clipped_y, clipped_x]
    if np.any(invalid):
        clipped_y[invalid] = nearest_y[clipped_y[invalid], clipped_x[invalid]]
        clipped_x[invalid] = nearest_x[clipped_y[invalid], clipped_x[invalid]]
    return clipped_y, clipped_x


def rebalance_reuse(
    target_y: np.ndarray,
    target_x: np.ndarray,
    source_y: np.ndarray,
    source_x: np.ndarray,
    valid_coordinates: np.ndarray,
    guide: np.ndarray,
    low_source: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, dict[str, int]]:
    """Cap exact-centre reuse without introducing non-donor pixels."""

    width = guide.shape[1]
    flat = source_y.astype(np.int64) * width + source_x.astype(np.int64)
    counts = np.bincount(flat, minlength=width * guide.shape[0]).astype(np.int32)
    changed = 0
    # Stable target order makes which 64 uses survive reproducible.
    seen: dict[int, int] = {}
    for position, centre in enumerate(flat.tolist()):
        use = seen.get(centre, 0) + 1
        seen[centre] = use
        if use <= GATES["maximumDonorCenterReuse"]:
            continue
        seed = int(hash_field(target_y[position : position + 1], target_x[position : position + 1], position)[0])
        indices = deterministic_indices(seed, 32, len(valid_coordinates))
        proposals = valid_coordinates[indices]
        proposal_flat = proposals[:, 0].astype(np.int64) * width + proposals[:, 1]
        available = counts[proposal_flat] < GATES["maximumDonorCenterReuse"]
        if not np.any(available):
            continue
        proposals = proposals[available]
        proposal_flat = proposal_flat[available]
        desired = guide[target_y[position], target_x[position]].astype(np.float64)
        colours = low_source[proposals[:, 0], proposals[:, 1]].astype(np.float64)
        costs = np.sum((colours - desired) ** 2, axis=1)
        chosen_index = int(np.argmin(costs))
        chosen = proposals[chosen_index]
        old = int(flat[position])
        counts[old] -= 1
        counts[int(proposal_flat[chosen_index])] += 1
        source_y[position] = int(chosen[0])
        source_x[position] = int(chosen[1])
        flat[position] = int(proposal_flat[chosen_index])
        changed += 1

    unique_count = int(np.count_nonzero(counts))
    if unique_count < GATES["minimumUniqueDonorCenters"]:
        unused = valid_coordinates[counts[valid_coordinates[:, 0] * width + valid_coordinates[:, 1]] == 0]
        needed = min(GATES["minimumUniqueDonorCenters"] - unique_count, len(unused))
        duplicate_positions = np.where(counts[flat] > 1)[0]
        for offset, position in enumerate(duplicate_positions[:needed]):
            chosen = unused[offset]
            old = int(flat[position])
            new = int(chosen[0]) * width + int(chosen[1])
            counts[old] -= 1
            counts[new] += 1
            source_y[position] = int(chosen[0])
            source_x[position] = int(chosen[1])
            flat[position] = new
            changed += 1
    tile_columns = math.ceil(width / 64)
    tile_ids = (source_y // 64).astype(np.int64) * tile_columns + source_x // 64
    tile_limit = int(math.floor(len(source_y) * GATES["maximumGeneratedSharePer64PixelDonorTile"]))
    tile_counts = np.bincount(tile_ids, minlength=tile_columns * math.ceil(guide.shape[0] / 64)).astype(np.int32)
    tile_reassignments = 0
    for overloaded_tile in np.where(tile_counts > tile_limit)[0].tolist():
        positions = np.where(tile_ids == overloaded_tile)[0][::-1]
        excess = int(tile_counts[overloaded_tile] - tile_limit)
        for position in positions[:excess]:
            seed = int(hash_field(target_y[position : position + 1], target_x[position : position + 1], position + 991)[0])
            indices = deterministic_indices(seed, 96, len(valid_coordinates))
            proposals = valid_coordinates[indices]
            proposal_flat = proposals[:, 0].astype(np.int64) * width + proposals[:, 1]
            proposal_tiles = (proposals[:, 0] // 64).astype(np.int64) * tile_columns + proposals[:, 1] // 64
            available = (
                (counts[proposal_flat] < GATES["maximumDonorCenterReuse"])
                & (tile_counts[proposal_tiles] < tile_limit)
            )
            if not np.any(available):
                continue
            proposals = proposals[available]
            proposal_flat = proposal_flat[available]
            proposal_tiles = proposal_tiles[available]
            desired_low = guide[target_y[position], target_x[position]].astype(np.float64)
            old_residual = (
                low_source[source_y[position], source_x[position]].astype(np.float64) - desired_low
            )
            colours = low_source[proposals[:, 0], proposals[:, 1]].astype(np.float64)
            costs = np.sum((colours - desired_low - old_residual * 0.15) ** 2, axis=1)
            chosen_index = int(np.argmin(costs))
            chosen = proposals[chosen_index]
            old_flat = int(flat[position])
            old_tile = int(tile_ids[position])
            new_flat = int(proposal_flat[chosen_index])
            new_tile = int(proposal_tiles[chosen_index])
            counts[old_flat] -= 1
            counts[new_flat] += 1
            tile_counts[old_tile] -= 1
            tile_counts[new_tile] += 1
            source_y[position] = int(chosen[0])
            source_x[position] = int(chosen[1])
            flat[position] = new_flat
            tile_ids[position] = new_tile
            changed += 1
            tile_reassignments += 1
    return source_y, source_x, {
        "reassignedPixels": changed,
        "tileShareReassignedPixels": tile_reassignments,
        "uniqueCentresAfter": int(np.count_nonzero(counts)),
        "maximumTileCountAfter": int(tile_counts.max(initial=0)),
        "tileCountLimit": tile_limit,
    }


def synthesize(
    source_crop: np.ndarray,
    semantic_subject: np.ndarray,
    target: np.ndarray,
    donor: np.ndarray,
    valid_centers: np.ndarray,
    authorization: np.ndarray,
) -> SynthesisResult:
    """Run deterministic boundary-conditioned exemplar reconstruction.

    The low-frequency field is solved across the complete authorization
    envelope from visible allocation cloth only.  In particular, the raw
    source fringe around the grain is not allowed to teach the guide that the
    removed mound is a raised brown object.  The complete authorization mask
    T is reconstructed; only its complement remains byte-exact source.

    PatchMatch supplies donor-only cloth residuals.  A deterministic blend of
    the coherent centre exemplar and overlapping disk votes is selected by
    measured cloth-gradient energy; this preserves woven material scale
    without the smooth closed-silhouette fill produced by r4.
    """

    require(source_crop.shape == (896, 896, 3), "Unexpected source crop shape")
    scales = (0.125, 0.25, 0.5, 1.0)
    patch_widths = (7, 9, 9, 9)
    previous_mapping_y: np.ndarray | None = None
    previous_mapping_x: np.ndarray | None = None
    stage_receipts: list[dict[str, Any]] = []
    final_guide: np.ndarray | None = None
    final_low_source: np.ndarray | None = None
    final_target_y: np.ndarray | None = None
    final_target_x: np.ndarray | None = None
    final_source_y: np.ndarray | None = None
    final_source_x: np.ndarray | None = None
    previous_guide: np.ndarray | None = None

    for level, (scale, patch_width) in enumerate(zip(scales, patch_widths)):
        size = int(round(source_crop.shape[0] * scale))
        level_source = resize_rgb(source_crop, size)
        level_target = resize_mask(target, size)
        level_donor = largest_component(resize_mask(donor, size) & ~level_target)
        level_authorization = resize_mask(authorization, size)
        radius = patch_width // 2
        level_valid = binary_erode(level_donor, radius)
        require(np.any(level_valid), f"No valid donor centres at pyramid level {level}")
        nearest_y, nearest_x, _ = nearest_true_coordinates(level_valid)
        valid_coordinates = np.column_stack(np.where(level_valid)).astype(np.int32)
        target_y, target_x = np.where(level_target)
        initial_guide = None
        if previous_guide is not None:
            initial_guide = np.asarray(
                Image.fromarray(np.clip(np.rint(previous_guide), 0, 255).astype(np.uint8)).resize(
                    (size, size), Image.Resampling.BILINEAR
                ),
                dtype=np.float32,
            )
        guide, low_source = harmonic_continuation(
            level_source,
            level_authorization,
            level_donor,
            blur_radius=max(1.0, 8.0 * scale),
            iterations=HARMONIC_ITERATIONS,
            initial=initial_guide,
        )
        previous_guide = guide

        if previous_mapping_y is None:
            indices = hash_field(target_y, target_x, level).astype(np.int64) % len(valid_coordinates)
            source_y = valid_coordinates[indices, 0].copy()
            source_x = valid_coordinates[indices, 1].copy()
        else:
            parent_y = np.minimum(previous_mapping_y.shape[0] - 1, target_y // 2)
            parent_x = np.minimum(previous_mapping_y.shape[1] - 1, target_x // 2)
            source_y = previous_mapping_y[parent_y, parent_x] * 2 + target_y % 2
            source_x = previous_mapping_x[parent_y, parent_x] * 2 + target_x % 2
            source_y, source_x = project_to_valid(source_y, source_x, level_valid, nearest_y, nearest_x)

        quota_active = level == len(scales) - 1
        quota_initialization: dict[str, int] | None = None
        quota_center_counts: np.ndarray | None = None
        quota_tile_counts: np.ndarray | None = None
        quota_unique_count = 0
        quota_tile_columns = 0
        quota_tile_limit = 0
        quota_rejected = 0
        if quota_active:
            # Quotas are established before the final-resolution optimization,
            # then maintained by every accepted PatchMatch proposal.  r4
            # repaired a concentrated field only after optimization; that
            # destroyed local coherence immediately before reconstruction.
            source_y, source_x, quota_initialization = rebalance_reuse(
                target_y,
                target_x,
                source_y,
                source_x,
                valid_coordinates,
                guide,
                low_source,
            )
            flat_centers = source_y.astype(np.int64) * size + source_x.astype(np.int64)
            quota_center_counts = np.bincount(flat_centers, minlength=size * size).astype(np.int32)
            quota_unique_count = int(np.count_nonzero(quota_center_counts))
            quota_tile_columns = math.ceil(size / 64)
            tile_ids = (source_y // 64).astype(np.int64) * quota_tile_columns + source_x // 64
            quota_tile_counts = np.bincount(
                tile_ids,
                minlength=quota_tile_columns * math.ceil(size / 64),
            ).astype(np.int32)
            quota_tile_limit = int(
                math.floor(len(source_y) * GATES["maximumGeneratedSharePer64PixelDonorTile"])
            )

        current_cost = patch_cost(
            guide, low_source, level_target, target_y, target_x, source_y, source_x, radius
        )
        accepted = 0

        def consider(candidate_y: np.ndarray, candidate_x: np.ndarray, eligible: np.ndarray) -> None:
            nonlocal source_y, source_x, current_cost, accepted
            nonlocal quota_unique_count, quota_rejected
            in_bounds = (
                eligible
                & (candidate_y >= 0)
                & (candidate_y < size)
                & (candidate_x >= 0)
                & (candidate_x < size)
            )
            safe_y = np.clip(candidate_y, 0, size - 1).astype(np.int32)
            safe_x = np.clip(candidate_x, 0, size - 1).astype(np.int32)
            authorized = in_bounds & level_valid[safe_y, safe_x]
            if not np.any(authorized):
                return
            # Patch cost is vectorized across every target position.  Keep
            # rejected proposal slots on their already-authorized current
            # centres so even unevaluated footprints remain in bounds.
            safe_y[~authorized] = source_y[~authorized]
            safe_x[~authorized] = source_x[~authorized]
            proposal_cost = patch_cost(
                guide, low_source, level_target, target_y, target_x, safe_y, safe_x, radius
            )
            better = authorized & (proposal_cost < current_cost)
            if quota_active and np.any(better):
                require(quota_center_counts is not None, "Missing integrated centre quotas")
                require(quota_tile_counts is not None, "Missing integrated tile quotas")
                accepted_under_quota = np.zeros(len(better), dtype=bool)
                candidates = np.where(better)[0]
                improvement = current_cost[candidates] - proposal_cost[candidates]
                order = candidates[np.argsort(-improvement, kind="stable")]
                for position in order.tolist():
                    old_y = int(source_y[position])
                    old_x = int(source_x[position])
                    new_y = int(safe_y[position])
                    new_x = int(safe_x[position])
                    old_flat = old_y * size + old_x
                    new_flat = new_y * size + new_x
                    if old_flat == new_flat:
                        accepted_under_quota[position] = True
                        continue
                    old_tile = (old_y // 64) * quota_tile_columns + old_x // 64
                    new_tile = (new_y // 64) * quota_tile_columns + new_x // 64
                    new_unique_count = quota_unique_count
                    if quota_center_counts[old_flat] == 1:
                        new_unique_count -= 1
                    if quota_center_counts[new_flat] == 0:
                        new_unique_count += 1
                    centre_allowed = (
                        quota_center_counts[new_flat] < GATES["maximumDonorCenterReuse"]
                    )
                    tile_allowed = (
                        old_tile == new_tile
                        or quota_tile_counts[new_tile] < quota_tile_limit
                    )
                    diversity_allowed = new_unique_count >= GATES["minimumUniqueDonorCenters"]
                    if not (centre_allowed and tile_allowed and diversity_allowed):
                        quota_rejected += 1
                        continue
                    quota_center_counts[old_flat] -= 1
                    quota_center_counts[new_flat] += 1
                    if old_tile != new_tile:
                        quota_tile_counts[old_tile] -= 1
                        quota_tile_counts[new_tile] += 1
                    quota_unique_count = new_unique_count
                    accepted_under_quota[position] = True
                better = accepted_under_quota
            if np.any(better):
                source_y[better] = safe_y[better]
                source_x[better] = safe_x[better]
                current_cost[better] = proposal_cost[better]
                accepted += int(np.count_nonzero(better))

        for sweep in range(8):
            mapping_y = np.full((size, size), -1, dtype=np.int32)
            mapping_x = np.full((size, size), -1, dtype=np.int32)
            mapping_y[target_y, target_x] = source_y
            mapping_x[target_y, target_x] = source_x
            if sweep % 2 == 0:
                for neighbor_dy, neighbor_dx in ((0, -1), (-1, 0)):
                    neighbor_y = np.clip(target_y + neighbor_dy, 0, size - 1)
                    neighbor_x = np.clip(target_x + neighbor_dx, 0, size - 1)
                    eligible = level_target[neighbor_y, neighbor_x]
                    candidate_y = mapping_y[neighbor_y, neighbor_x] - neighbor_dy
                    candidate_x = mapping_x[neighbor_y, neighbor_x] - neighbor_dx
                    consider(candidate_y, candidate_x, eligible)
                    mapping_y[target_y, target_x] = source_y
                    mapping_x[target_y, target_x] = source_x
            else:
                for neighbor_dy, neighbor_dx in ((0, 1), (1, 0)):
                    neighbor_y = np.clip(target_y + neighbor_dy, 0, size - 1)
                    neighbor_x = np.clip(target_x + neighbor_dx, 0, size - 1)
                    eligible = level_target[neighbor_y, neighbor_x]
                    candidate_y = mapping_y[neighbor_y, neighbor_x] - neighbor_dy
                    candidate_x = mapping_x[neighbor_y, neighbor_x] - neighbor_dx
                    consider(candidate_y, candidate_x, eligible)
                    mapping_y[target_y, target_x] = source_y
                    mapping_x[target_y, target_x] = source_x

            if sweep < 2:
                indices = hash_field(target_y, target_x, level * 16 + sweep).astype(np.int64) % len(valid_coordinates)
                random_y = valid_coordinates[indices, 0]
                random_x = valid_coordinates[indices, 1]
            else:
                search_radius = max(radius + 1, size // (2 ** (sweep - 1)))
                hashed = hash_field(target_y, target_x, level * 16 + sweep)
                span = np.uint64(search_radius * 2 + 1)
                jitter_y = (hashed % span).astype(np.int64) - search_radius
                jitter_x = ((hashed >> np.uint64(32)) % span).astype(np.int64) - search_radius
                random_y, random_x = project_to_valid(
                    source_y.astype(np.int64) + jitter_y,
                    source_x.astype(np.int64) + jitter_x,
                    level_valid,
                    nearest_y,
                    nearest_x,
                )
            consider(random_y, random_x, np.ones(len(target_y), dtype=bool))

        level_mapping_y = np.full((size, size), -1, dtype=np.int32)
        level_mapping_x = np.full((size, size), -1, dtype=np.int32)
        level_mapping_y[target_y, target_x] = source_y
        level_mapping_x[target_y, target_x] = source_x
        previous_mapping_y = level_mapping_y
        previous_mapping_x = level_mapping_x
        stage_receipts.append(
            {
                "scale": scale,
                "pixelSize": [size, size],
                "patchWidthPixels": patch_width,
                "patchCostFootprintSamples": len(disk_offsets(radius)),
                "alternatingSweeps": 8,
                "targetPixels": int(len(target_y)),
                "validDonorCentres": int(len(valid_coordinates)),
                "acceptedProposals": accepted,
                "harmonicIterations": HARMONIC_ITERATIONS,
                "guideFillMask": "COMPLETE_AUTHORIZATION_ENVELOPE",
                "guideBoundary": "VISIBLE_DONOR_OUTSIDE_T_ONLY",
            }
        )
        if quota_active:
            stage_receipts[-1]["integratedDonorQuotas"] = {
                "establishedBeforeFinalOptimization": True,
                "maintainedDuringEveryAcceptedProposal": True,
                "initialization": quota_initialization,
                "minimumUniqueDonorCentres": GATES["minimumUniqueDonorCenters"],
                "maximumDonorCentreReuse": GATES["maximumDonorCenterReuse"],
                "maximumTileCount": quota_tile_limit,
                "quotaRejectedProposals": quota_rejected,
                "finalUniqueDonorCentres": quota_unique_count,
                "finalMaximumDonorCentreReuse": int(quota_center_counts.max(initial=0)),
                "finalMaximumTileCount": int(quota_tile_counts.max(initial=0)),
            }
        if level == len(scales) - 1:
            final_guide = guide
            final_low_source = low_source
            final_target_y, final_target_x = target_y, target_x
            final_source_y, final_source_x = source_y, source_x

    require(final_guide is not None and final_low_source is not None, "PatchMatch did not reach full resolution")
    residual = source_crop.astype(np.float32) - final_low_source
    residual_accumulator = np.zeros_like(final_guide, dtype=np.float64)
    vote_weights = np.zeros(target.shape, dtype=np.float64)
    vote_count = 0
    for dy, dx in disk_offsets(PATCH_RADIUS):
        destination_y = final_target_y + dy
        destination_x = final_target_x + dx
        inside = target[destination_y, destination_x]
        if not np.any(inside):
            continue
        destination_y = destination_y[inside]
        destination_x = destination_x[inside]
        donor_y = final_source_y[inside] + dy
        donor_x = final_source_x[inside] + dx
        weight = 25 - (dx * dx + dy * dy)
        residual_accumulator[destination_y, destination_x] += residual[donor_y, donor_x] * weight
        vote_weights[destination_y, destination_x] += weight
        vote_count += int(len(destination_y))
    require(np.all(vote_weights[target] > 0), "Patch voting left subject pixels without a residual vote")
    voted_residual = residual_accumulator[target] / vote_weights[target, None]
    centre_residual = residual[final_source_y, final_source_x]
    seam_ring = target & ~binary_erode(target, SEAM_RING_WIDTH)
    _, _, outside_distance = nearest_true_coordinates(~target)
    centre_weight = np.clip(
        (outside_distance[target].astype(np.float64) - 1.0) / SEAM_RING_WIDTH,
        0.0,
        1.0,
    )
    # The boundary is reconstructed by overlapping same-side donor patches;
    # the core keeps one coherent donor residual instead of cancelling 49
    # unrelated cloth samples.  This is a spatial construction rule, not a
    # post-hoc gradient-gate fit.
    generated_residual = (
        voted_residual * (1.0 - centre_weight[:, None])
        + centre_residual * centre_weight[:, None]
    )
    generated = final_guide[target] + generated_residual
    candidate = source_crop.copy()
    candidate[target] = np.clip(np.rint(generated), 0, 255).astype(np.uint8)
    stage_receipts[-1]["patchVoting"] = {
        "footprintSamples": len(disk_offsets(PATCH_RADIUS)),
        "weightRule": "25 - (dx*dx + dy*dy)",
        "totalVotes": vote_count,
        "pixelsWithoutVotes": 0,
    }
    stage_receipts[-1]["boundaryConditionedExemplar"] = {
        "rule": "OVERLAPPING_DONOR_PATCH_VOTES_AT_T_BOUNDARY_TO_DIRECT_COHERENT_DONOR_RESIDUAL_IN_CORE",
        "distanceMetric": "MANHATTAN_DISTANCE_TO_NOT_T",
        "transitionPixels": SEAM_RING_WIDTH,
        "gradientGateUsedToChooseBlend": False,
    }

    require(np.array_equal(candidate[~authorization], source_crop[~authorization]), "Pixels outside T changed")
    provenance_y = np.full(target.shape, -1, dtype=np.int32)
    provenance_x = np.full(target.shape, -1, dtype=np.int32)
    provenance_y[final_target_y, final_target_x] = final_source_y
    provenance_x[final_target_y, final_target_x] = final_source_x

    require(np.all(provenance_y[target] >= 0) and np.all(provenance_x[target] >= 0), "Missing provenance")
    return SynthesisResult(
        candidate=candidate,
        provenance_y=provenance_y,
        provenance_x=provenance_x,
        authorization=authorization,
        target=target,
        semantic_subject=semantic_subject,
        donor=donor,
        valid_centers=valid_centers,
        seam_ring=seam_ring,
        stages=tuple(stage_receipts),
    )


def luma(rgb: np.ndarray) -> np.ndarray:
    value = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
    return value.astype(np.float64)


def gradient_samples(rgb: np.ndarray, mask: np.ndarray) -> np.ndarray:
    values = luma(rgb)
    horizontal_mask = mask[:, 1:] & mask[:, :-1]
    vertical_mask = mask[1:, :] & mask[:-1, :]
    horizontal = np.abs(values[:, 1:] - values[:, :-1])[horizontal_mask]
    vertical = np.abs(values[1:, :] - values[:-1, :])[vertical_mask]
    return np.concatenate([horizontal, vertical])


def percentile_metrics(values: np.ndarray) -> dict[str, float]:
    require(values.size > 0, "Cannot measure an empty sample")
    return {
        "mean": round(float(np.mean(values)), 6),
        "median": round(float(np.percentile(values, 50)), 6),
        "p01": round(float(np.percentile(values, 1)), 6),
        "p95": round(float(np.percentile(values, 95)), 6),
        "p99": round(float(np.percentile(values, 99)), 6),
        "maximum": round(float(np.max(values)), 6),
    }


def cross_seam_samples(candidate: np.ndarray, target: np.ndarray) -> np.ndarray:
    values: list[np.ndarray] = []
    for dy, dx in ((0, 1), (1, 0)):
        first = target[: target.shape[0] - dy or None, : target.shape[1] - dx or None]
        second = target[dy:, dx:]
        crossing = first ^ second
        a = candidate[: candidate.shape[0] - dy or None, : candidate.shape[1] - dx or None]
        b = candidate[dy:, dx:]
        delta = np.abs(a.astype(np.int16) - b.astype(np.int16))
        values.append(delta[crossing].reshape(-1))
    return np.concatenate(values)


def adjacent_map_coherence(result: SynthesisResult) -> dict[str, Any]:
    """Measure translation continuity without turning it into an authority gate."""

    measurements: dict[str, Any] = {}
    combined: list[np.ndarray] = []
    for label, (dy, dx) in {
        "horizontal": (0, 1),
        "vertical": (1, 0),
    }.items():
        first = result.target[
            : result.target.shape[0] - dy or None,
            : result.target.shape[1] - dx or None,
        ]
        second = result.target[dy:, dx:]
        paired = first & second
        source_y_first = result.provenance_y[
            : result.target.shape[0] - dy or None,
            : result.target.shape[1] - dx or None,
        ]
        source_y_second = result.provenance_y[dy:, dx:]
        source_x_first = result.provenance_x[
            : result.target.shape[0] - dy or None,
            : result.target.shape[1] - dx or None,
        ]
        source_x_second = result.provenance_x[dy:, dx:]
        translation_jump = np.sqrt(
            ((source_y_second - source_y_first) - dy) ** 2
            + ((source_x_second - source_x_first) - dx) ** 2
        )[paired]
        combined.append(translation_jump)
        measurements[label] = {
            "pairCount": int(translation_jump.size),
            "exactTranslationFraction": round(float(np.mean(translation_jump == 0)), 9),
            "withinOneAndAHalfPixelsFraction": round(
                float(np.mean(translation_jump <= 1.5)), 9
            ),
            "withinFourPixelsFraction": round(float(np.mean(translation_jump <= 4.0)), 9),
            "jumpPixels": percentile_metrics(translation_jump),
        }
    all_jumps = np.concatenate(combined)
    measurements["combined"] = {
        "pairCount": int(all_jumps.size),
        "exactTranslationFraction": round(float(np.mean(all_jumps == 0)), 9),
        "withinOneAndAHalfPixelsFraction": round(float(np.mean(all_jumps <= 1.5)), 9),
        "withinFourPixelsFraction": round(float(np.mean(all_jumps <= 4.0)), 9),
        "jumpPixels": percentile_metrics(all_jumps),
        "authorityGate": False,
        "interpretation": "DIAGNOSTIC_FOR_VISIBLE_PATCH_BOUNDARIES_AND_REPETITION",
    }
    return measurements


def qa_metrics(result: SynthesisResult, source_crop: np.ndarray) -> tuple[dict[str, Any], list[str]]:
    candidate = result.candidate
    target = result.target
    authorization = result.authorization
    legacy_frozen_fringe = authorization & ~result.semantic_subject
    core = target & ~result.seam_ring
    outside = ~authorization
    difference = np.abs(candidate.astype(np.int16) - source_crop.astype(np.int16))
    outside_delta = difference[outside]

    recomposed = candidate.copy()
    recomposed[target] = source_crop[target]
    recomposition_delta = np.abs(recomposed.astype(np.int16) - source_crop.astype(np.int16))

    source_y = result.provenance_y[target]
    source_x = result.provenance_x[target]
    footprint_authorized = np.ones(len(source_y), dtype=bool)
    for dy, dx in disk_offsets(PATCH_RADIUS):
        footprint_authorized &= result.donor[source_y + dy, source_x + dx]

    flat_centers = source_y.astype(np.int64) * target.shape[1] + source_x.astype(np.int64)
    unique_centers, reuse_counts = np.unique(flat_centers, return_counts=True)
    tile_ids = (source_y // 64).astype(np.int64) * 14 + source_x // 64
    _, tile_counts = np.unique(tile_ids, return_counts=True)

    donor_gradient = gradient_samples(source_crop, result.donor)
    core_gradient = gradient_samples(candidate, core)
    donor_gradient_metrics = percentile_metrics(donor_gradient)
    core_gradient_metrics = percentile_metrics(core_gradient)
    gradient_ratios = {
        key: round(core_gradient_metrics[key] / donor_gradient_metrics[key], 6)
        if donor_gradient_metrics[key] != 0
        else None
        for key in ("median", "p95")
    }

    seam_metrics = percentile_metrics(cross_seam_samples(candidate, target))
    core_pixels = candidate[core].astype(np.float64)
    donor_pixels = source_crop[result.donor].astype(np.float64)
    core_red_minus_blue = float(np.mean(core_pixels[:, 0] - core_pixels[:, 2]))
    donor_red_minus_blue = float(np.mean(donor_pixels[:, 0] - donor_pixels[:, 2]))
    core_luma_metrics = percentile_metrics(luma(candidate)[core])

    metrics: dict[str, Any] = {
        "outsideAuthorization": {
            "changedPixelCount": int(np.count_nonzero(np.any(difference != 0, axis=2) & outside)),
            "maximumChannelDifference": int(outside_delta.max(initial=0)),
        },
        "legacyFrozenFringe": {
            "rule": "SYNTHESIZED_INSIDE_T_NOT_PROTECTED",
            "pixelCount": int(np.count_nonzero(legacy_frozen_fringe)),
            "changedPixelCount": int(
                np.count_nonzero(np.any(difference != 0, axis=2) & legacy_frozen_fringe)
            ),
            "maximumChannelDifference": int(difference[legacy_frozen_fringe].max(initial=0)),
        },
        "startingRecomposition": {
            "maximumChannelDifference": int(recomposition_delta.max(initial=0)),
            "meanAbsoluteChannelDifference": round(float(np.mean(recomposition_delta)), 9),
        },
        "provenance": {
            "generatedPixelCount": int(np.count_nonzero(target)),
            "pixelsWithCoordinates": int(np.count_nonzero((result.provenance_y >= 0) & target)),
            "footprintsInsideLargestDonorCount": int(np.count_nonzero(footprint_authorized)),
            "footprintCoverage": round(float(np.mean(footprint_authorized)), 9),
            "uniqueDonorCenters": int(len(unique_centers)),
            "maximumDonorCenterReuse": int(reuse_counts.max(initial=0)),
            "maximumGeneratedSharePer64PixelDonorTile": round(float(tile_counts.max(initial=0) / len(source_y)), 9),
            "mirroredPixelCount": 0,
            "rotationDegrees": {"minimum": 0.0, "maximum": 0.0},
            "scale": {"minimum": 1.0, "maximum": 1.0},
        },
        "crossSeamChannelDifference": seam_metrics,
        "gradient": {
            "donor": donor_gradient_metrics,
            "generatedCore": core_gradient_metrics,
            "generatedToDonorRatio": gradient_ratios,
        },
        "colour": {
            "donorMeanRedMinusBlue": round(donor_red_minus_blue, 6),
            "generatedCoreMeanRedMinusBlue": round(core_red_minus_blue, 6),
            "absoluteRedMinusBlueDelta": round(abs(core_red_minus_blue - donor_red_minus_blue), 6),
            "generatedCoreLuma": core_luma_metrics,
        },
        "adjacentMapCoherence": adjacent_map_coherence(result),
    }

    failures: list[str] = []
    if metrics["outsideAuthorization"]["changedPixelCount"] != 0:
        failures.append("OUTSIDE_AUTHORIZATION_CHANGED")
    if metrics["startingRecomposition"]["maximumChannelDifference"] != 0:
        failures.append("STARTING_RECOMPOSITION_MISMATCH")
    provenance = metrics["provenance"]
    if provenance["pixelsWithCoordinates"] != provenance["generatedPixelCount"]:
        failures.append("PROVENANCE_INCOMPLETE")
    if provenance["footprintCoverage"] != 1.0:
        failures.append("DONOR_FOOTPRINT_OUTSIDE_AUTHORITY")
    if provenance["uniqueDonorCenters"] < GATES["minimumUniqueDonorCenters"]:
        failures.append("DONOR_DIVERSITY_TOO_LOW")
    if provenance["maximumDonorCenterReuse"] > GATES["maximumDonorCenterReuse"]:
        failures.append("DONOR_CENTER_OVERUSED")
    if provenance["maximumGeneratedSharePer64PixelDonorTile"] > GATES["maximumGeneratedSharePer64PixelDonorTile"]:
        failures.append("DONOR_TILE_SHARE_TOO_HIGH")
    if seam_metrics["mean"] > GATES["crossSeam"]["meanMaximum"]:
        failures.append("CROSS_SEAM_MEAN_TOO_HIGH")
    if seam_metrics["p95"] > GATES["crossSeam"]["p95Maximum"]:
        failures.append("CROSS_SEAM_P95_TOO_HIGH")
    if seam_metrics["p99"] > GATES["crossSeam"]["p99Maximum"]:
        failures.append("CROSS_SEAM_P99_TOO_HIGH")
    for key in ("median", "p95"):
        ratio = gradient_ratios[key]
        if ratio is None or not GATES["interiorGradientRatio"]["minimum"] <= ratio <= GATES["interiorGradientRatio"]["maximum"]:
            failures.append(f"INTERIOR_GRADIENT_{key.upper()}_OUT_OF_RANGE")
    if metrics["colour"]["absoluteRedMinusBlueDelta"] > GATES["generatedCoreMeanRedMinusBlueDeltaMaximum"]:
        failures.append("GENERATED_CORE_RED_BLUE_DRIFT")
    if core_luma_metrics["p01"] < GATES["generatedLuma"]["p01Minimum"]:
        failures.append("GENERATED_CORE_LUMA_P01_OUT_OF_RANGE")
    if core_luma_metrics["p99"] > GATES["generatedLuma"]["p99Maximum"]:
        failures.append("GENERATED_CORE_LUMA_P99_OUT_OF_RANGE")
    return metrics, failures


def mask_png(mask: np.ndarray) -> bytes:
    return png_bytes(mask.astype(np.uint8) * 255, "L")


def provenance_png(values: np.ndarray, target: np.ndarray) -> bytes:
    encoded = np.zeros(values.shape, dtype=np.uint16)
    encoded[target] = (values[target] + 1).astype(np.uint16)
    return png_bytes(encoded, "I;16")


def translate_rgb(array: np.ndarray, dx: int, dy: int) -> np.ndarray:
    result = np.zeros_like(array)
    height, width = array.shape[:2]
    source_x0 = max(0, -dx)
    source_x1 = min(width, width - dx)
    source_y0 = max(0, -dy)
    source_y1 = min(height, height - dy)
    if source_x0 < source_x1 and source_y0 < source_y1:
        result[source_y0 + dy : source_y1 + dy, source_x0 + dx : source_x1 + dx] = array[
            source_y0:source_y1, source_x0:source_x1
        ]
    return result


def render_camera_crop(
    master: np.ndarray,
    viewport_crop: dict[str, Any],
    keyframe: dict[str, Any],
) -> np.ndarray:
    """Render the same normalized camera crop used by SceneFramePlanner."""

    authored = viewport_crop["sourceRect"]
    center = keyframe["center"]
    scale = float(keyframe["scale"])
    width = float(authored["width"]) / scale
    height = float(authored["height"]) / scale
    left = (float(center["x"]) - width / 2.0) * master.shape[1]
    top = (float(center["y"]) - height / 2.0) * master.shape[0]
    right = left + width * master.shape[1]
    bottom = top + height * master.shape[0]
    viewport = viewport_crop["viewport"]
    rendered = Image.fromarray(master).transform(
        (int(viewport["widthPoints"]), int(viewport["heightPoints"])),
        Image.Transform.EXTENT,
        (left, top, right, bottom),
        resample=Image.Resampling.BICUBIC,
    )
    return np.asarray(rendered)


def comparison_sheet(
    panels: Iterable[tuple[str, np.ndarray]],
    panel_size: tuple[int, int],
) -> bytes:
    panels = tuple(panels)
    panel_width, panel_height = panel_size
    header = 36
    sheet = Image.new("RGB", (panel_width * len(panels), panel_height + header), (10, 11, 13))
    draw = ImageDraw.Draw(sheet)
    for index, (label, array) in enumerate(panels):
        panel = Image.fromarray(array).resize(
            (panel_width, panel_height), Image.Resampling.LANCZOS
        )
        sheet.paste(panel, (index * panel_width, header))
        draw.text((index * panel_width + 10, 10), label, fill=(236, 231, 214))
    buffer = io.BytesIO()
    sheet.save(buffer, format="PNG", compress_level=9, optimize=False)
    return buffer.getvalue()


def diagnostic_artifacts(
    result: SynthesisResult,
    source_crop: np.ndarray,
    source_master: np.ndarray,
    scene_fixture: dict[str, Any],
) -> dict[str, bytes]:
    candidate = result.candidate
    target = result.target
    authorization_mask = result.authorization
    legacy_frozen_fringe = authorization_mask & ~result.semantic_subject
    difference = np.abs(candidate.astype(np.int16) - source_crop.astype(np.int16)).astype(np.uint8)
    outside_difference = difference.copy()
    outside_difference[authorization_mask] = 0

    seam = target & ~binary_erode(target, 1)
    seam_difference = np.zeros_like(difference)
    seam_difference[seam] = np.clip(difference[seam].astype(np.int16) * 4, 0, 255).astype(np.uint8)

    authorization = np.zeros((*target.shape, 3), dtype=np.uint8)
    authorization[result.donor] = (28, 98, 176)
    authorization[result.valid_centers] = (44, 190, 118)
    authorization[target] = (222, 78, 56)
    authorization[result.semantic_subject] = (194, 62, 48)
    authorization[legacy_frozen_fringe] = (245, 183, 54)
    authorization[result.seam_ring] = (212, 92, 176)

    contrast = np.asarray(ImageEnhance.Contrast(Image.fromarray(candidate)).enhance(1.35))
    grain_layer = np.zeros_like(source_crop)
    grain_layer[target] = source_crop[target]
    artifacts: dict[str, bytes] = {
        "central-grain.png": png_bytes(candidate),
        "source-crop.png": png_bytes(source_crop),
        "closed-subject-mask.png": mask_png(result.semantic_subject),
        "write-target-mask.png": mask_png(target),
        "largest-donor-component.png": mask_png(result.donor),
        "valid-patch-centres.png": mask_png(result.valid_centers),
        "seam-ring.png": mask_png(result.seam_ring),
        "central-grain-authorization.png": mask_png(authorization_mask),
        "source-underlay-authorization-comparison.png": png_bytes(authorization),
        "provenance-source-x-uint16.png": provenance_png(result.provenance_x, target),
        "provenance-source-y-uint16.png": provenance_png(result.provenance_y, target),
        "donor-provenance-map.png": png_bytes(
            np.dstack(
                (
                    np.where(target, result.provenance_x * 255 // 895, 0),
                    np.where(target, result.provenance_y * 255 // 895, 0),
                    np.where(target, 255, 0),
                )
            ).astype(np.uint8)
        ),
        "transform-map.png": png_bytes(np.dstack((target * 128, target * 128, target * 0)).astype(np.uint8)),
        "source-candidate-difference-x4.png": png_bytes(np.clip(difference.astype(np.int16) * 4, 0, 255).astype(np.uint8)),
        "outside-target-difference.png": png_bytes(outside_difference),
        "four-times-seam-difference.png": png_bytes(seam_difference),
        "normal-crop.png": png_bytes(candidate),
        "increase-contrast.png": png_bytes(contrast),
        "reduce-motion.png": png_bytes(candidate),
    }
    for index, (dx, dy) in enumerate(PARALLAX_EXTREMA):
        shifted_target = shifted_zero(target, dy, dx)
        shifted_grain = translate_rgb(grain_layer, dx, dy)
        frame = candidate.copy()
        frame[shifted_target] = shifted_grain[shifted_target]
        direction = "negative-8-negative-3" if index == 0 else "positive-8-positive-3"
        artifacts[f"grain-parallax-{direction}.png"] = png_bytes(frame)

    panel_width = 448
    panel_height = 448
    sheet = Image.new("RGB", (panel_width * 3, panel_height + 36), (10, 11, 13))
    draw = ImageDraw.Draw(sheet)
    for index, (label, array) in enumerate(
        (("source", source_crop), ("underlay candidate", candidate), ("difference x4", np.clip(difference * 4, 0, 255).astype(np.uint8)))
    ):
        panel = Image.fromarray(array).resize((panel_width, panel_height), Image.Resampling.LANCZOS)
        sheet.paste(panel, (index * panel_width, 36))
        draw.text((index * panel_width + 10, 10), label, fill=(236, 231, 214))
    buffer = io.BytesIO()
    sheet.save(buffer, format="PNG", compress_level=9, optimize=False)
    artifacts["source-candidate-diagnostic.png"] = buffer.getvalue()

    # Place the crop back into the 1290 x 2796 master before any viewport QA.
    # Stretching the square crop to an iPhone aspect hid scene-scale defects in
    # r1-r5b and was not a valid camera diagnostic.
    exhausted_master = source_master.copy()
    crop_x, crop_y, crop_width, crop_height = CROP
    exhausted_master[
        crop_y : crop_y + crop_height,
        crop_x : crop_x + crop_width,
    ] = candidate
    artifacts["full-master-source.png"] = png_bytes(source_master)
    artifacts["full-master-exhausted.png"] = png_bytes(exhausted_master)
    artifacts["full-master-source-exhausted-comparison.png"] = comparison_sheet(
        (("source master", source_master), ("exhausted master", exhausted_master)),
        (430, 932),
    )

    scene = scene_fixture["scene"]
    keyframes = scene["cameraRail"]["keyframes"]
    extrema = (("rail-start", keyframes[0]), ("rail-end", keyframes[-1]))
    for viewport_crop in scene["sceneCanvas"]["viewportCrops"]:
        viewport_id = viewport_crop["id"]
        rendered: dict[str, np.ndarray] = {}
        for extremum, keyframe in extrema:
            source_view = render_camera_crop(source_master, viewport_crop, keyframe)
            exhausted_view = render_camera_crop(exhausted_master, viewport_crop, keyframe)
            rendered[f"{extremum}-source"] = source_view
            rendered[f"{extremum}-exhausted"] = exhausted_view
            artifacts[f"{viewport_id}-{extremum}-source.png"] = png_bytes(source_view)
            artifacts[f"{viewport_id}-{extremum}-exhausted.png"] = png_bytes(exhausted_view)
            artifacts[f"{viewport_id}-{extremum}-comparison.png"] = comparison_sheet(
                (("source", source_view), ("exhausted", exhausted_view)),
                (int(viewport_crop["viewport"]["widthPoints"]), int(viewport_crop["viewport"]["heightPoints"])),
            )
        # Existing names now point to the actual interaction-end camera crop,
        # not a stretched 896 x 896 square.
        artifacts[f"{viewport_id}-full.png"] = png_bytes(rendered["rail-end-source"])
        artifacts[f"{viewport_id}-exhausted.png"] = png_bytes(rendered["rail-end-exhausted"])

    target_x = np.where(target)[1]
    target_y = np.where(target)[0]
    boundary_padding = 24
    bx0 = max(0, int(target_x.min()) - boundary_padding)
    bx1 = min(target.shape[1], int(target_x.max()) + boundary_padding + 1)
    by0 = max(0, int(target_y.min()) - boundary_padding)
    by1 = min(target.shape[0], int(target_y.max()) + boundary_padding + 1)
    source_boundary = source_crop[by0:by1, bx0:bx1]
    candidate_boundary = candidate[by0:by1, bx0:bx1]
    boundary_difference = np.clip(
        np.abs(candidate_boundary.astype(np.int16) - source_boundary.astype(np.int16)) * 4,
        0,
        255,
    ).astype(np.uint8)
    boundary_panel = Image.new(
        "RGB",
        (source_boundary.shape[1] * 2 * 3, source_boundary.shape[0] * 2 + 36),
        (10, 11, 13),
    )
    boundary_draw = ImageDraw.Draw(boundary_panel)
    for index, (label, array) in enumerate(
        (
            ("source boundary 2x", source_boundary),
            ("candidate boundary 2x", candidate_boundary),
            ("difference x4 2x", boundary_difference),
        )
    ):
        scaled = Image.fromarray(array).resize(
            (array.shape[1] * 2, array.shape[0] * 2),
            Image.Resampling.NEAREST,
        )
        boundary_panel.paste(scaled, (index * source_boundary.shape[1] * 2, 36))
        boundary_draw.text(
            (index * source_boundary.shape[1] * 2 + 10, 10),
            label,
            fill=(236, 231, 214),
        )
    boundary_buffer = io.BytesIO()
    boundary_panel.save(boundary_buffer, format="PNG", compress_level=9, optimize=False)
    artifacts["boundary-source-candidate-difference-2x.png"] = boundary_buffer.getvalue()

    source_low = separable_gaussian(source_crop.astype(np.float64), 2.0)
    candidate_low = separable_gaussian(candidate.astype(np.float64), 2.0)
    source_high = np.clip((source_crop.astype(np.float64) - source_low) * 4.0 + 128.0, 0, 255).astype(np.uint8)
    candidate_high = np.clip((candidate.astype(np.float64) - candidate_low) * 4.0 + 128.0, 0, 255).astype(np.uint8)
    high_difference = np.clip(
        np.abs(candidate_high.astype(np.int16) - source_high.astype(np.int16)) * 2,
        0,
        255,
    ).astype(np.uint8)
    artifacts["high-pass-source-candidate-comparison.png"] = comparison_sheet(
        (
            ("source high-pass", source_high),
            ("candidate high-pass", candidate_high),
            ("high-pass difference x2", high_difference),
        ),
        (448, 448),
    )
    return artifacts


def load_inputs(root: Path) -> tuple[np.ndarray, dict[str, np.ndarray], dict[str, Any]]:
    source_path = root / SOURCE["path"]
    require(source_path.is_file(), f"Missing source: {SOURCE['path']}")
    require(sha256_file(source_path) == SOURCE["sha256"], "Source hash mismatch")
    source_image = Image.open(source_path).convert("RGB")
    require(list(source_image.size) == SOURCE["pixelSize"], "Source dimensions mismatch")
    source = np.asarray(source_image)

    masks: dict[str, np.ndarray] = {}
    mask_receipt: dict[str, Any] = {}
    for name, authority in MASKS.items():
        path = root / authority["path"]
        require(path.is_file(), f"Missing mask: {authority['path']}")
        actual_hash = sha256_file(path)
        require(actual_hash == authority["sha256"], f"Mask hash mismatch: {name}")
        mask_image = Image.open(path).convert("L")
        require(mask_image.size == source_image.size, f"Mask dimensions mismatch: {name}")
        values = np.asarray(mask_image)
        require(set(np.unique(values)).issubset({0, 255}), f"Mask is not binary: {name}")
        masks[name] = values > 0
        mask_receipt[name] = {**authority, "pixelCount": int(np.count_nonzero(masks[name]))}
    return source, masks, mask_receipt


def construct_authority_masks(
    masks: dict[str, np.ndarray],
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, dict[str, Any]]:
    grain = masks["central-grain"]
    cloth = masks["allocation-cloth"]
    foreground = masks["foreground-occluders"]
    closed = binary_close(grain, CLOSE_RADIUS)
    target_full = binary_dilate(closed, DILATE_RADIUS) & ~foreground
    x, y, width, height = CROP
    subject_crop = grain[y : y + height, x : x + width]
    closed_crop = closed[y : y + height, x : x + width]
    target = target_full[y : y + height, x : x + width]
    seam_ring = target & ~binary_erode(target, SEAM_RING_WIDTH)
    core = binary_erode(target, SEAM_RING_WIDTH)
    outside_target = ~target
    legacy_frozen_fringe = target & ~closed_crop
    foreground_crop = foreground[y : y + height, x : x + width]
    raw_donor = (cloth & ~target_full & ~foreground)[y : y + height, x : x + width]
    donor = largest_component(raw_donor)
    valid_centers = binary_erode(donor, PATCH_RADIUS)

    measurements = {
        "subjectCropPixelCount": int(np.count_nonzero(subject_crop)),
        "subjectCropByteMaskSha256": sha256_bytes(subject_crop.astype(np.uint8).tobytes()),
        "closedPixelCount": int(np.count_nonzero(closed)),
        "closedCropByteMaskSha256": sha256_bytes(closed_crop.astype(np.uint8).tobytes()),
        "targetPixelCount": int(np.count_nonzero(target)),
        "targetBoundsInclusive": bounds_inclusive(target),
        "targetForegroundOverlap": int(np.count_nonzero(target & foreground_crop)),
        "targetByteMaskSha256": sha256_bytes(target.astype(np.uint8).tobytes()),
        "seamRingPixelCount": int(np.count_nonzero(seam_ring)),
        "seamRingByteMaskSha256": sha256_bytes(seam_ring.astype(np.uint8).tobytes()),
        "corePixelCount": int(np.count_nonzero(core)),
        "coreByteMaskSha256": sha256_bytes(core.astype(np.uint8).tobytes()),
        "outsideTargetPixelCount": int(np.count_nonzero(outside_target)),
        "outsideTargetByteMaskSha256": sha256_bytes(outside_target.astype(np.uint8).tobytes()),
        "legacyFrozenFringePixelCount": int(np.count_nonzero(legacy_frozen_fringe)),
        "legacyFrozenFringeByteMaskSha256": sha256_bytes(
            legacy_frozen_fringe.astype(np.uint8).tobytes()
        ),
        "rawDonorPixelCount": int(np.count_nonzero(raw_donor)),
        "largestDonorPixelCount": int(np.count_nonzero(donor)),
        "largestDonorByteMaskSha256": sha256_bytes(donor.astype(np.uint8).tobytes()),
        "validPatchCenterCount": int(np.count_nonzero(valid_centers)),
        "validPatchCenterByteMaskSha256": sha256_bytes(valid_centers.astype(np.uint8).tobytes()),
    }
    require(measurements == EXPECTED, f"Authority-mask forensic mismatch: {measurements}")
    return closed_crop, target, donor, valid_centers, measurements


def inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="Empty output directory below native/.build")
    parser.add_argument("--receipt", required=True, type=Path, help="Canonical receipt below native/content/backstage/harvest")
    parser.add_argument(
        "--allow-failed-qa",
        action="store_true",
        help="Return zero after writing a TECHNICAL_QA_FAILED receipt; authority remains prohibited",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path.cwd().resolve()
    output = args.output.resolve()
    receipt_path = args.receipt.resolve()
    require(inside(output, root / "native/.build"), "Output must stay below native/.build")
    require(inside(receipt_path, root / "native/content/backstage/harvest"), "Receipt must stay below Harvest backstage")
    require(receipt_path.suffix == ".json", "Receipt must be JSON")
    require(not output.exists() or (output.is_dir() and not any(output.iterdir())), "Output must be absent or empty")
    require(not receipt_path.exists(), "Refusing to overwrite an existing receipt")

    spec_path = root / SPEC["path"]
    require(spec_path.is_file(), "Missing central-grain synthesis specification")
    require(sha256_file(spec_path) == SPEC["sha256"], "Central-grain synthesis specification hash mismatch")
    specification = json.loads(spec_path.read_text(encoding="utf-8"))
    require(specification.get("shippingAllowed") is False, "Synthesis specification must remain non-shipping")
    require(specification.get("editorApprovalClaimed") is False, "Synthesis specification cannot claim editor approval")

    fixture_path = root / SCENE_FIXTURE["path"]
    require(fixture_path.is_file(), "Missing hash-bound Harvest scene fixture")
    require(sha256_file(fixture_path) == SCENE_FIXTURE["sha256"], "Harvest scene fixture hash mismatch")
    scene_fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    require(scene_fixture.get("shippingState") == "PROHIBITED_UNTIL_REBUILT_AND_APPROVED", "Harvest fixture unexpectedly claims shipping authority")

    source, masks, mask_receipt = load_inputs(root)
    subject, authorization, donor, valid_centers, authority_measurements = construct_authority_masks(masks)
    x, y, width, height = CROP
    source_crop = source[y : y + height, x : x + width].copy()

    first = synthesize(
        source_crop,
        subject,
        authorization,
        donor,
        valid_centers,
        authorization,
    )
    second = synthesize(
        source_crop,
        subject,
        authorization,
        donor,
        valid_centers,
        authorization,
    )
    first_candidate_bytes = png_bytes(first.candidate)
    second_candidate_bytes = png_bytes(second.candidate)
    deterministic = first_candidate_bytes == second_candidate_bytes
    require(deterministic, "Synthesis is not byte-deterministic")
    require(np.array_equal(first.provenance_x, second.provenance_x), "X provenance is not deterministic")
    require(np.array_equal(first.provenance_y, second.provenance_y), "Y provenance is not deterministic")

    metrics, failures = qa_metrics(first, source_crop)
    artifacts = diagnostic_artifacts(first, source_crop, source, scene_fixture)
    require(artifacts["central-grain.png"] == first_candidate_bytes, "Candidate encoding diverged")
    output.mkdir(parents=True, exist_ok=True)
    output_hashes: dict[str, str] = {}
    for name, value in sorted(artifacts.items()):
        path = output / name
        path.write_bytes(value)
        output_hashes[name] = sha256_bytes(value)

    effective_failures = list(failures)
    technical_status = "OBJECTIVE_TECHNICAL_QA_PASS" if not effective_failures else "OBJECTIVE_TECHNICAL_QA_FAILED"
    receipt = {
        "schemaVersion": 1,
        "receiptID": "harvest-v26-central-grain-underlay-source-only-r5c-scene-qa",
        "scope": "NON_SHIPPING_BACKSTAGE_ONLY",
        "status": technical_status,
        "authority": {
            "artisticApproval": False,
            "editorialApproval": False,
            "productionAssetAuthority": False,
            "productionMasterAuthority": False,
            "shippingAllowed": False,
            "candidateMayEnterShippingCompiler": False,
            "humanOrEditorVisualReviewRecorded": False,
            "forbiddenAuthorityMarkers": FORBIDDEN_AUTHORITIES,
            "nextDecision": "CODEX_VISUAL_REVIEW_REQUIRED_EVEN_IF_OBJECTIVE_GATES_PASS",
        },
        "specification": SPEC,
        "source": SOURCE,
        "sceneFixture": SCENE_FIXTURE,
        "masks": mask_receipt,
        "crop": {"pixelRect": CROP, "coordinateSpace": "source pixels"},
        "construction": {
            "tool": {
                "path": SCRIPT_PATH,
                "sha256": sha256_file(root / SCRIPT_PATH),
                "pythonEnvironment": PYTHON_PATH,
                "pythonVersion": "3.14.6",
                "libraries": [
                    {"name": "Pillow", "version": "12.3.0", "licenseExpression": "MIT-CMU"},
                    {
                        "name": "NumPy",
                        "version": "2.5.1",
                        "licenseExpression": "BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0",
                    },
                ],
                "incrementalCostNOK": 0,
            },
            "method": "SOURCE_ONLY_BOUNDARY_CONDITIONED_EXEMPLAR_PATCHMATCH",
            "requiredMethod": specification["synthesis"]["method"],
            "requiredMethodImplemented": True,
            "randomSeed": {
                "derivation": "SHA256_OF_EXACT_INPUT_HASHES_AND_CANONICAL_PARAMETERS",
                "sha256": SEED_SHA256,
                "word64Hex": f"{SEED_WORD:016x}",
            },
            "target": {
                "subjectOperation": "disk-close-r3",
                "authorizationOperation": "disk-dilate-r4 then subtract foreground occluders",
                "writeMask": "AUTHORIZATION_T",
                "closeRadius": CLOSE_RADIUS,
                "dilateRadius": DILATE_RADIUS,
                "semanticClosedSubjectPixelCount": int(np.count_nonzero(subject)),
                "writeTargetPixelCount": int(np.count_nonzero(authorization)),
                "legacyFrozenFringePixelCount": int(np.count_nonzero(authorization & ~subject)),
                "legacyFrozenFringeProtected": False,
                "outsideAuthorizationRule": specification["synthesis"]["outsideAuthorizationRule"],
            },
            "donor": "largest 8-connected allocation-cloth component after subtracting target and foreground occluders",
            "patchFootprint": {
                "shape": "integer-euclidean-disk",
                "radius": PATCH_RADIUS,
                "sampleCount": len(disk_offsets(PATCH_RADIUS)),
                "zeroPaddingOutsideCrop": True,
            },
            "seamRingWidthPixels": SEAM_RING_WIDTH,
            "seamRingRule": specification["synthesis"]["seamRingRule"],
            "rawSourcePixelsInsideAuthorizationProtected": False,
            "stages": list(first.stages),
            "transformEnvelope": {
                "authorizedRotationDegrees": [-3.0, 3.0],
                "usedRotationDegrees": [0.0, 0.0],
                "authorizedScale": [0.92, 1.08],
                "usedScale": [1.0, 1.0],
                "mirroringAuthorized": False,
                "mirroringUsed": False,
            },
            "externalModelUsed": False,
            "networkUsed": False,
            "builtInImageGenerationUsed": False,
            "qwenUsed": False,
        },
        "forensicAuthority": {"expected": EXPECTED, "measured": authority_measurements},
        "determinism": {
            "runsInOneInvocation": 2,
            "candidateBytesIdentical": deterministic,
            "candidateSha256Run1": sha256_bytes(first_candidate_bytes),
            "candidateSha256Run2": sha256_bytes(second_candidate_bytes),
            "provenanceCoordinatesIdentical": True,
        },
        "gates": GATES,
        "metrics": metrics,
        "failedGates": effective_failures,
        "outputs": {
            name: {
                "path": str((output.relative_to(root) / name).as_posix()),
                "sha256": value,
            }
            for name, value in output_hashes.items()
        },
        "diagnosticLimits": [
            "Objective pixel and provenance checks cannot approve material plausibility, seams, repetition, perspective, or historical appearance.",
            "Normal, Increased Contrast, Reduce Motion, and camera-extremum images are inspection artifacts, not runtime assets.",
            "A passing receipt remains non-shipping until a separate byte-bound production-asset decision is recorded through the project authority chain.",
            "A failed receipt preserves the candidate only for diagnosis and iteration.",
        ],
    }
    receipt_bytes = canonical_json_bytes(receipt)
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.write_bytes(receipt_bytes)
    receipt_path.with_suffix(receipt_path.suffix + ".sha256").write_text(sha256_bytes(receipt_bytes) + "\n", encoding="utf-8")
    print(json.dumps({"status": technical_status, "failedGates": effective_failures, "candidateSha256": sha256_bytes(first_candidate_bytes)}, sort_keys=True))
    return 0 if not effective_failures or args.allow_failed_qa else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"harvest central-grain underlay failed: {error}", file=sys.stderr)
        raise SystemExit(1)
