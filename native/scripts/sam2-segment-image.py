#!/usr/bin/env python3
"""Offline, prompt-driven SAM2 mask authoring for backstage visual production.

The script deliberately stops at frozen masks and review previews. It does not
declare a scene, layer set, or production master approved.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import sys
from pathlib import Path
from typing import Any

# Fail closed if a library attempts to resolve anything over the network.
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import numpy as np
import torch
from PIL import Image
from transformers import Sam2Model, Sam2Processor


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validated_point(point: Any, width: int, height: int, label: str) -> list[float]:
    require(isinstance(point, list) and len(point) == 2, f"{label} must be [x, y]")
    x, y = (float(point[0]), float(point[1]))
    require(0 <= x < width and 0 <= y < height, f"{label} lies outside the source image")
    return [x, y]


def validated_box(box: Any, width: int, height: int, label: str) -> list[float]:
    require(isinstance(box, list) and len(box) == 4, f"{label} must be [x0, y0, x1, y1]")
    x0, y0, x1, y1 = (float(value) for value in box)
    require(0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height, f"{label} is invalid")
    return [x0, y0, x1, y1]


def mask_metrics(mask: np.ndarray) -> dict[str, Any]:
    ys, xs = np.where(mask > 0)
    if len(xs) == 0:
        return {"pixelCount": 0, "coverage": 0.0, "boundingBox": None}
    return {
        "pixelCount": int(len(xs)),
        "coverage": round(float(len(xs) / mask.size), 8),
        "boundingBox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
    }


def review_overlay(image: np.ndarray, mask: np.ndarray) -> Image.Image:
    overlay = image.astype(np.float32).copy()
    outside = mask == 0
    inside = ~outside
    overlay[outside] *= 0.2
    overlay[inside] = overlay[inside] * 0.55 + np.array([110.0, 0.0, 120.0])
    return Image.fromarray(np.clip(overlay, 0, 255).astype(np.uint8), "RGB")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--device", choices=("auto", "cpu", "mps"), default="auto")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    spec_path = args.spec.resolve()
    output = args.output.resolve()
    require(spec_path.is_file(), f"Missing prompt specification: {spec_path}")
    require(not output.exists() or not any(output.iterdir()), f"Output directory must be absent or empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    candidate_dir = output / "candidates"
    selected_dir = output / "selected"
    preview_dir = output / "review"
    candidate_dir.mkdir()
    selected_dir.mkdir()
    preview_dir.mkdir()

    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    require(spec.get("schemaVersion") == 1, "Unsupported prompt specification")
    source_spec = spec["source"]
    model_spec = spec["model"]
    source_path = (Path.cwd() / source_spec["path"]).resolve()
    model_path = (Path.cwd() / model_spec["path"]).resolve()
    require(source_path.is_file(), f"Missing source image: {source_path}")
    require(model_path.is_dir(), f"Missing model snapshot: {model_path}")
    require(sha256(source_path) == source_spec["sha256"], "Source image hash mismatch")

    verified_model_files: dict[str, str] = {}
    for relative_path, expected_hash in sorted(model_spec["requiredFiles"].items()):
        path = model_path / relative_path
        require(path.is_file(), f"Missing model file: {relative_path}")
        actual_hash = sha256(path)
        require(actual_hash == expected_hash, f"Model file hash mismatch: {relative_path}")
        verified_model_files[relative_path] = actual_hash

    image = Image.open(source_path).convert("RGB")
    width, height = image.size
    require([width, height] == source_spec["pixelSize"], "Source image dimensions mismatch")
    image_array = np.asarray(image)

    device = args.device
    if device == "auto":
        device = "mps" if torch.backends.mps.is_available() else "cpu"
    if device == "mps":
        require(torch.backends.mps.is_available(), "MPS requested but unavailable")

    torch.manual_seed(0)
    model = Sam2Model.from_pretrained(str(model_path), local_files_only=True).to(device)
    processor = Sam2Processor.from_pretrained(str(model_path), local_files_only=True)
    model.eval()

    object_receipts: list[dict[str, Any]] = []
    selected_masks: dict[str, np.ndarray] = {}
    image_embeddings = None
    original_sizes = None

    for index, object_spec in enumerate(spec["objects"]):
        object_id = object_spec["id"]
        require(object_id not in selected_masks, f"Duplicate object id: {object_id}")
        require(object_id.replace("-", "").replace("_", "").isalnum(), f"Unsafe object id: {object_id}")
        box = validated_box(object_spec["box"], width, height, f"{object_id}.box")
        positives = [
            validated_point(point, width, height, f"{object_id}.positivePoints")
            for point in object_spec.get("positivePoints", [])
        ]
        negatives = [
            validated_point(point, width, height, f"{object_id}.negativePoints")
            for point in object_spec.get("negativePoints", [])
        ]
        require(positives, f"{object_id} needs at least one positive point")
        points = positives + negatives
        labels = [1] * len(positives) + [0] * len(negatives)

        processor_args: dict[str, Any] = {
            "input_boxes": [[box]],
            "input_points": [[points]],
            "input_labels": [[labels]],
            "return_tensors": "pt",
        }
        if index == 0:
            processor_args["images"] = image
        else:
            processor_args["original_sizes"] = original_sizes
        inputs = processor(**processor_args).to(device)
        with torch.no_grad():
            if index == 0:
                outputs = model(**inputs)
                image_embeddings = outputs.image_embeddings
                original_sizes = inputs["original_sizes"]
            else:
                outputs = model(**inputs, image_embeddings=image_embeddings)

        masks = processor.post_process_masks(outputs.pred_masks.cpu(), original_sizes.cpu())[0][0]
        scores = outputs.iou_scores.detach().cpu()[0][0]
        require(masks.shape[0] == 3, f"{object_id} did not produce three candidate masks")
        selected_candidate = int(object_spec["selectedCandidate"])
        require(0 <= selected_candidate < 3, f"{object_id}.selectedCandidate must be 0, 1, or 2")

        candidates: list[dict[str, Any]] = []
        for candidate_index, candidate in enumerate(masks):
            mask = (candidate.numpy() > 0).astype(np.uint8) * 255
            mask_path = candidate_dir / f"{object_id}--{candidate_index}.png"
            preview_path = preview_dir / f"{object_id}--{candidate_index}.jpg"
            Image.fromarray(mask, "L").save(mask_path, format="PNG", compress_level=9, optimize=False)
            review_overlay(image_array, mask).save(preview_path, format="JPEG", quality=90, optimize=False)
            candidates.append(
                {
                    "candidate": candidate_index,
                    "predictedIoU": round(float(scores[candidate_index]), 8),
                    "mask": str(mask_path.relative_to(output)),
                    "maskSha256": sha256(mask_path),
                    "metrics": mask_metrics(mask),
                    "reviewPreview": str(preview_path.relative_to(output)),
                    "reviewPreviewSha256": sha256(preview_path),
                }
            )

        selected = (masks[selected_candidate].numpy() > 0).astype(np.uint8) * 255
        selected_path = selected_dir / f"{object_id}.png"
        Image.fromarray(selected, "L").save(selected_path, format="PNG", compress_level=9, optimize=False)
        selected_masks[object_id] = selected
        object_receipts.append(
            {
                "id": object_id,
                "box": box,
                "positivePoints": positives,
                "negativePoints": negatives,
                "selectedCandidate": selected_candidate,
                "selectedMask": str(selected_path.relative_to(output)),
                "selectedMaskSha256": sha256(selected_path),
                "selectedMetrics": mask_metrics(selected),
                "candidates": candidates,
            }
        )

    union_receipts: list[dict[str, Any]] = []
    for union_spec in spec.get("unions", []):
        union_id = union_spec["id"]
        members = union_spec["members"]
        require(members, f"Union {union_id} has no members")
        unknown = [member for member in members if member not in selected_masks]
        require(not unknown, f"Union {union_id} has unknown members: {unknown}")
        mask = np.maximum.reduce([selected_masks[member] for member in members])
        mask_path = selected_dir / f"{union_id}.png"
        preview_path = preview_dir / f"{union_id}.jpg"
        Image.fromarray(mask, "L").save(mask_path, format="PNG", compress_level=9, optimize=False)
        review_overlay(image_array, mask).save(preview_path, format="JPEG", quality=90, optimize=False)
        selected_masks[union_id] = mask
        union_receipts.append(
            {
                "id": union_id,
                "members": members,
                "mask": str(mask_path.relative_to(output)),
                "maskSha256": sha256(mask_path),
                "metrics": mask_metrics(mask),
                "reviewPreview": str(preview_path.relative_to(output)),
                "reviewPreviewSha256": sha256(preview_path),
            }
        )

    receipt = {
        "schemaVersion": 1,
        "status": "BACKSTAGE_MASK_AUTHORING_OUTPUT_REQUIRES_VISUAL_REVIEW",
        "shippingState": "PROHIBITED",
        "source": {
            "path": source_spec["path"],
            "sha256": sha256(source_path),
            "pixelSize": [width, height],
        },
        "promptSpecification": {
            "path": str(spec_path),
            "sha256": sha256(spec_path),
        },
        "model": {
            "repository": model_spec["repository"],
            "revision": model_spec["revision"],
            "path": model_spec["path"],
            "verifiedFiles": verified_model_files,
        },
        "runtime": {
            "device": device,
            "offlineEnvironment": True,
            "python": platform.python_version(),
            "torch": torch.__version__,
            "transformers": __import__("transformers").__version__,
            "pillow": __import__("PIL").__version__,
            "numpy": np.__version__,
        },
        "objects": object_receipts,
        "unions": union_receipts,
        "limitations": [
            "Predicted IoU is a model estimate, not a visual approval.",
            "Every selected mask requires source-alignment inspection at full resolution.",
            "This output cannot approve clean plates, parallax, alpha edges, state variants, or a production master.",
        ],
    }
    receipt_path = output / "receipt.json"
    receipt_path.write_bytes(canonical_json(receipt))
    print(json.dumps({"receipt": str(receipt_path), "sha256": sha256(receipt_path)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, TypeError, ValueError) as error:
        print(f"sam2-segment-image: {error}", file=sys.stderr)
        raise SystemExit(2)
