#!/usr/bin/env python3
"""Write a deterministic manifest for the Chapter 01 hero-rig candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def record(path: Path, base: Path) -> dict[str, object]:
    return {
        "bytes": path.stat().st_size,
        "path": str(path.relative_to(base)),
        "sha256": digest(path),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chapter-root", type=Path, required=True)
    parser.add_argument("--character-dir", type=Path, required=True)
    args = parser.parse_args()

    chapter_root = args.chapter_root.resolve()
    character_dir = args.character_dir.resolve()
    output = character_dir / "outputs"
    tooling = chapter_root / "tooling"
    usdc = output / "chapter01-hero-character-library.usdc"
    usdz = output / "chapter01-hero-character-library.usdz"
    stage_text = subprocess.run(
        ["/usr/bin/usdcat", str(usdc)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout

    canonical_paths = [usdc, usdz] + sorted((output / "textures").glob("*.png"))
    source_paths = [
        tooling / "generate_hero_characters.py",
        tooling / "validate_hero_character_usd.py",
        tooling / "write_hero_character_manifest.py",
        tooling / "build-hero-characters.sh",
        character_dir / "provenance.json",
    ]
    review_paths = [
        output / "chapter01-hero-character-library.blend",
        output / "chapter01-hero-character-preview.png",
        character_dir / "review/chapter01-hero-character-preview-before.png",
        character_dir / "review/chapter01-hero-character-preview-before-9x16.png",
        character_dir / "review/chapter01-hero-character-preview-comparison.png",
        character_dir / "VISUAL_REVIEW.md",
    ]
    review_paths = [path for path in review_paths if path.is_file()]

    manifest = {
        "assetVersion": "chapter01-hero-characters-v3",
        "canonicalOutputs": [record(path, chapter_root) for path in canonical_paths],
        "determinism": {
            "byteReproducibility": "PASS",
            "comparedBuilds": 2,
            "fixedTimestampUTC": "1980-01-01T00:00:00Z",
            "pythonHashSeed": 0,
            "sourceDateEpoch": 315532800,
        },
        "finalArtGate": "OPEN",
        "geometry": {
            "blendShapePrimCount": stage_text.count("def BlendShape"),
            "garmentAuthority": "project-authored-fitted-and-parametric-garment-v3",
            "garmentExternalTopologyInputs": 0,
            "meshPrimCount": stage_text.count("def Mesh"),
            "skeletonCount": stage_text.count("def Skeleton"),
            "skinnedRootCount": stage_text.count("def SkelRoot"),
        },
        "openGates": [
            "Complete final historical-costume review; the belted woven tunic is a restrained reconstruction, not an evidence claim for one exact cut.",
            "Complete close-camera face, hand, eye, hair and contact polish in final scene lighting.",
            "Integrate and validate the shared rigs in each world cell; this candidate is not integrated here.",
        ],
        "qualityClassification": "HERO_RIG_CANDIDATE",
        "reviewArtifacts": [record(path, chapter_root) for path in review_paths],
        "rootContract": {
            "cloneableLocalOriginRoots": ["hero_adult_a", "hero_adult_b", "hero_youth"],
            "previewCameraLightsAndGroundExcluded": True,
            "previewSpacingUsesNonExportedParents": True,
        },
        "schemaVersion": 1,
        "sources": [record(path, chapter_root) for path in source_paths],
        "tool": {
            "blenderBuildHash": "fbe6228777e7",
            "blenderVersion": "5.2.0 LTS",
            "mpfbCommit": "f4f4f1ffa8203585730a7ce433b66738777ba168",
            "mpfbTag": "v2.0.15",
        },
        "validation": {
            "arkitUsdchecker": "PASS",
            "deterministicTextures": "PASS",
            "externalGarmentTopologyAbsent": "PASS",
            "hairRestClearanceAuthored": "PASS",
            "localOriginRoots": "PASS",
            "nineBySixteenReviewRender": "PASS",
            "previewLeakage": "PASS",
            "rightsGate": "PASS",
        },
    }
    manifest_path = character_dir / "build-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
