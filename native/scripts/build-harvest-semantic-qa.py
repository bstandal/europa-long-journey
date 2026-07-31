#!/usr/bin/env python3
"""Build a deterministic, non-shipping parallax/halo stress test for Harvest v26."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def resolved(root: Path, value: str) -> Path:
    return (root / value).resolve()


def load_verified(root: Path, entry: dict[str, Any]) -> Path:
    path = resolved(root, entry["path"])
    require(path.is_file(), f"Missing input: {path}")
    require(sha256(path) == entry["sha256"], f"Hash mismatch: {path}")
    return path


def union_masks(masks: dict[str, Image.Image], names: list[str]) -> Image.Image:
    require(names, "A mask union cannot be empty")
    result = masks[names[0]].copy()
    for name in names[1:]:
        result = ImageChops.lighter(result, masks[name])
    return result


def dilated_feather(mask: Image.Image, dilation: int, feather: float) -> Image.Image:
    result = mask
    full_steps, remainder = divmod(dilation, 10)
    for _ in range(full_steps):
        result = result.filter(ImageFilter.MaxFilter(21))
    if remainder:
        result = result.filter(ImageFilter.MaxFilter(remainder * 2 + 1))
    if feather:
        result = result.filter(ImageFilter.GaussianBlur(feather))
    return result


def layer_alpha(mask: Image.Image, erode: int, feather: float) -> Image.Image:
    result = mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    if erode:
        result = result.filter(ImageFilter.MinFilter(erode * 2 + 1))
    if feather:
        result = result.filter(ImageFilter.GaussianBlur(feather))
    return result


def translate(image: Image.Image, dx: int, dy: int, fill: int | tuple[int, ...]) -> Image.Image:
    shifted = Image.new(image.mode, image.size, fill)
    source_x = max(0, -dx)
    source_y = max(0, -dy)
    target_x = max(0, dx)
    target_y = max(0, dy)
    width = image.width - abs(dx)
    height = image.height - abs(dy)
    if width > 0 and height > 0:
        region = image.crop((source_x, source_y, source_x + width, source_y + height))
        shifted.paste(region, (target_x, target_y))
    return shifted


def source_over(base: Image.Image, source: Image.Image, alpha: Image.Image) -> Image.Image:
    return Image.composite(source, base, alpha)


def crop_and_resize(image: Image.Image, rect: list[int], size: list[int]) -> Image.Image:
    x, y, width, height = rect
    return image.crop((x, y, x + width, y + height)).resize(tuple(size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    image.save(path, format="PNG", compress_level=9, optimize=False)


def difference_metrics(first: Image.Image, second: Image.Image) -> dict[str, Any]:
    left = np.asarray(first.convert("RGB"), dtype=np.int16)
    right = np.asarray(second.convert("RGB"), dtype=np.int16)
    delta = np.abs(left - right)
    changed = np.any(delta != 0, axis=2)
    mse = float(np.mean((left.astype(np.float64) - right.astype(np.float64)) ** 2))
    return {
        "changedPixelCount": int(np.count_nonzero(changed)),
        "changedPixelFraction": round(float(np.mean(changed)), 10),
        "maximumChannelDifference": int(delta.max()),
        "meanAbsoluteChannelDifference": round(float(delta.mean()), 8),
        "psnrDecibels": None if mse == 0 else round(10 * math.log10((255 * 255) / mse), 8),
    }


def contact_sheet(images: list[tuple[str, Image.Image]], cell_size: tuple[int, int]) -> Image.Image:
    cell_width, cell_height = cell_size
    label_height = 34
    sheet = Image.new("RGB", (cell_width * len(images), cell_height + label_height), (13, 14, 16))
    draw = ImageDraw.Draw(sheet)
    for index, (label, image) in enumerate(images):
        fitted = image.resize((cell_width, cell_height), Image.Resampling.LANCZOS)
        x = index * cell_width
        sheet.paste(fitted, (x, label_height))
        draw.text((x + 10, 10), label, fill=(236, 231, 214))
    return sheet


def fitted_panel(image: Image.Image, rect: list[int], size: tuple[int, int]) -> Image.Image:
    x, y, width, height = rect
    crop = image.crop((x, y, x + width, y + height))
    crop.thumbnail(size, Image.Resampling.LANCZOS)
    panel = Image.new("RGB", size, (8, 8, 10))
    panel.paste(crop, ((size[0] - crop.width) // 2, (size[1] - crop.height) // 2))
    return panel


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path.cwd().resolve()
    spec_path = args.spec.resolve()
    output = args.output.resolve()
    require(spec_path.is_file(), f"Missing QA specification: {spec_path}")
    require(not output.exists() or (output.is_dir() and not any(output.iterdir())), "Output must be absent or empty")
    output.mkdir(parents=True, exist_ok=True)
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    require(spec.get("schemaVersion") == 1, "Unsupported QA specification")

    source_path = load_verified(root, spec["source"])
    source = Image.open(source_path).convert("RGB")
    require(list(source.size) == spec["source"]["pixelSize"], "Source dimensions do not match")

    segmentation = spec["segmentationAuthority"]
    for path_key, hash_key in (("preflightPath", "preflightSha256"), ("receiptPath", "receiptSha256")):
        path = resolved(root, segmentation[path_key])
        require(path.is_file() and sha256(path) == segmentation[hash_key], f"Segmentation authority mismatch: {path}")

    masks: dict[str, Image.Image] = {}
    mask_hashes: dict[str, str] = {}
    mask_root = root / "native/content/backstage/harvest/semantic-masks-v26.provisional"
    for name, expected_hash in sorted(spec["masks"].items()):
        path = mask_root / f"{name}.png"
        require(path.is_file(), f"Missing semantic mask: {path}")
        actual_hash = sha256(path)
        require(actual_hash == expected_hash, f"Semantic mask hash mismatch: {name}")
        mask = Image.open(path).convert("L")
        require(mask.size == source.size, f"Semantic mask size mismatch: {name}")
        masks[name] = mask
        mask_hashes[name] = actual_hash

    clean = spec["cleanPlateDiagnostics"]
    provenance_path = resolved(root, clean["provenancePath"])
    require(provenance_path.is_file() and sha256(provenance_path) == clean["provenanceSha256"], "Clean diagnostic provenance mismatch")
    settlement_path = load_verified(root, clean["settlement"])
    settlement = Image.open(settlement_path).convert("RGB").resize(source.size, Image.Resampling.LANCZOS)

    clean_config = spec["cleanPlateConstruction"]
    object_config = clean_config["objectRemoval"]
    object_union = union_masks(masks, object_config["masks"])
    object_replacement = dilated_feather(
        object_union,
        int(object_config["dilationPixels"]),
        float(object_config["featherPixels"]),
    )
    clean_base = Image.composite(settlement, source, object_replacement)
    save_png(clean_base, output / "diagnostic-clean-base.png")
    save_png(object_replacement, output / "diagnostic-object-replacement-mask.png")

    alpha_config = spec["alphaConstruction"]
    prepared_layers: list[dict[str, Any]] = []
    for layer in spec["layersBackToFront"]:
        hard_mask = union_masks(masks, layer["masks"])
        alpha = layer_alpha(hard_mask, int(alpha_config["erodePixels"]), float(alpha_config["featherPixels"]))
        alpha_path = output / f"alpha-{layer['id']}.png"
        save_png(alpha, alpha_path)
        prepared_layers.append({**layer, "alpha": alpha, "alphaPath": alpha_path})

    extrema: dict[str, Image.Image] = {}
    for extreme in spec["extrema"]:
        multiplier = int(extreme["multiplier"])
        frame = clean_base.copy()
        for layer in prepared_layers:
            dx = int(layer["maximumShiftPixels"][0]) * multiplier
            dy = int(layer["maximumShiftPixels"][1]) * -multiplier
            shifted_source = translate(source, dx, dy, (0, 0, 0))
            shifted_alpha = translate(layer["alpha"], dx, dy, 0)
            frame = source_over(frame, shifted_source, shifted_alpha)
        extrema[extreme["id"]] = frame
        save_png(frame, output / f"parallax-{extreme['id']}-full.png")

    crop = spec["comparisonCrop"]
    reference_crop = crop_and_resize(source, crop["sourcePixelRect"], crop["outputPixelSize"])
    reduce_motion_crop = reference_crop.copy()
    negative_crop = crop_and_resize(extrema["negative"], crop["sourcePixelRect"], crop["outputPixelSize"])
    positive_crop = crop_and_resize(extrema["positive"], crop["sourcePixelRect"], crop["outputPixelSize"])
    outputs = {
        "v26-reference-crop.png": reference_crop,
        "reduce-motion-static-crop.png": reduce_motion_crop,
        "parallax-negative-crop.png": negative_crop,
        "parallax-positive-crop.png": positive_crop,
    }
    for name, image in outputs.items():
        save_png(image, output / name)

    reduce_difference = ImageChops.difference(reference_crop, reduce_motion_crop)
    extrema_difference = ImageChops.difference(negative_crop, positive_crop).point(lambda value: min(255, value * 4))
    save_png(reduce_difference, output / "reduce-motion-difference.png")
    save_png(extrema_difference, output / "parallax-extrema-difference-x4.png")

    comparison = contact_sheet(
        [
            ("v26 reference", reference_crop),
            ("parallax -1", negative_crop),
            ("parallax +1", positive_crop),
            ("Reduce Motion", reduce_motion_crop),
        ],
        (393, 852),
    )
    save_png(comparison, output / "combined-comparison.png")

    regions = spec["haloInspectionRegions"]
    panel_size = (640, 430)
    label_height = 32
    halo_sheet = Image.new("RGB", (panel_size[0] * 2, (panel_size[1] + label_height) * len(regions)), (10, 10, 12))
    draw = ImageDraw.Draw(halo_sheet)
    for row, region in enumerate(regions):
        y = row * (panel_size[1] + label_height)
        left = fitted_panel(extrema["negative"], region["pixelRect"], panel_size)
        right = fitted_panel(extrema["positive"], region["pixelRect"], panel_size)
        halo_sheet.paste(left, (0, y + label_height))
        halo_sheet.paste(right, (panel_size[0], y + label_height))
        draw.text((10, y + 8), f"{region['id']} / parallax -1", fill=(236, 231, 214))
        draw.text((panel_size[0] + 10, y + 8), f"{region['id']} / parallax +1", fill=(236, 231, 214))
    save_png(halo_sheet, output / "halo-edge-inspection.png")

    output_hashes: dict[str, str] = {}
    for path in sorted(output.glob("*.png")):
        output_hashes[path.name] = sha256(path)
    receipt = {
        "schemaVersion": 1,
        "status": "BACKSTAGE_COMBINED_VISUAL_QA_REQUIRES_CODEX_REVIEW",
        "shippingState": "PROHIBITED",
        "specification": {"path": str(spec_path), "sha256": sha256(spec_path)},
        "builder": {"path": "native/scripts/build-harvest-semantic-qa.py", "sha256": sha256(Path(__file__).resolve())},
        "source": spec["source"],
        "segmentationAuthority": segmentation,
        "semanticMasks": mask_hashes,
        "cleanPlateDiagnostics": {
            "authority": clean["authority"],
            "provenancePath": clean["provenancePath"],
            "provenanceSha256": clean["provenanceSha256"],
            "replacementInput": "settlement",
            "settlementSha256": clean["settlement"]["sha256"],
        },
        "construction": {
            "cleanPlateConstruction": spec["cleanPlateConstruction"],
            "layersBackToFront": spec["layersBackToFront"],
            "testScope": spec["testScope"],
            "alphaConstruction": spec["alphaConstruction"],
            "comparisonCrop": crop,
        },
        "metrics": {
            "reduceMotionAgainstV26": difference_metrics(reference_crop, reduce_motion_crop),
            "positiveAgainstNegativeParallax": difference_metrics(negative_crop, positive_crop),
        },
        "outputs": output_hashes,
        "authorityLimits": spec["limits"],
        "unresolvedByThisReceipt": [
            "The resized settlement clean diagnostic source is globally redrawn, below-resolution, and non-reproducible as a production input.",
            "The world diagnostic source is provenance-verified but is not composited in this restricted proof.",
            "Visual review must reject any remaining subject ghost, seam, halo, geometric edge, or registration break.",
            "No state variant, full clean plate, runtime layer set, or camera-rail performance is approved.",
        ],
    }
    receipt_path = output / "receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt_hash = sha256(receipt_path)
    (output / "receipt.sha256").write_text(f"{receipt_hash}  receipt.json\n", encoding="utf-8")
    print(json.dumps({"receipt": str(receipt_path), "sha256": receipt_hash}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, TypeError, ValueError) as error:
        print(f"build-harvest-semantic-qa: {error}", file=sys.stderr)
        raise SystemExit(2)
