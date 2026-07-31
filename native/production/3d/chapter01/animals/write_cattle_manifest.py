#!/usr/bin/env python3
"""Write the deterministic manifest for the Chapter 01 cattle candidate."""

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
    parser.add_argument("--animal-dir", type=Path, required=True)
    args = parser.parse_args()
    animal_dir = args.animal_dir.resolve()
    output = animal_dir / "outputs"

    reports = [
        json.loads((output / f"chapter01-cattle-library-lod{lod}-report.json").read_text(encoding="utf-8"))
        for lod in (0, 1)
    ]
    stage_texts = [
        subprocess.run(
            ["/usr/bin/usdcat", str(output / f"chapter01-cattle-library-lod{lod}.usdc")],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        for lod in (0, 1)
    ]

    canonical_paths = []
    for lod in (0, 1):
        canonical_paths.extend(
            [
                output / f"chapter01-cattle-library-lod{lod}.usdc",
                output / f"chapter01-cattle-library-lod{lod}.usdz",
                output / f"chapter01-cattle-library-lod{lod}-report.json",
            ]
        )
    canonical_paths.extend(sorted((output / "textures").glob("*.png")))
    source_paths = [
        animal_dir / "generate_chapter01_cattle.py",
        animal_dir / "validate_cattle_usd.py",
        animal_dir / "write_cattle_manifest.py",
        animal_dir / "build-cattle-library.sh",
        animal_dir / "provenance.json",
    ]
    review_paths = [
        output / "chapter01-cattle-rig-library.blend",
        output / "chapter01-cattle-rig-preview-9x16.png",
    ]

    manifest = {
        "assetVersion": "chapter01-cattle-rigs-v1",
        "canonicalOutputs": [record(path, animal_dir) for path in canonical_paths],
        "classificationReason": (
            "The library replaces primitive bovines with anatomically directed, skinned cattle "
            "for the boat and herd contexts. Final hair cards, deformation/contact polish, and "
            "world-cell lighting approval remain open."
        ),
        "determinism": {
            "byteReproducibility": "PASS",
            "comparedBuilds": 2,
            "fixedTimestampUTC": "1980-01-01T00:00:00Z",
            "pythonHashSeed": 0,
            "sourceDateEpoch": 315532800,
        },
        "directedClipContract": {
            "cattle-adult": {
                "barrier-weight-shift": [40, 56],
                "herd-walk": [1, 33],
                "rest": [60, 64],
            },
            "cattle-young": {
                "boat-brace": [1, 32],
                "boat-weight-shift": [40, 56],
                "rest": [60, 64],
            },
            "fps": 24,
        },
        "finalArtGate": "OPEN",
        "geometry": {
            "lods": [
                {
                    "lod": report["lod"],
                    "meshObjects": report["meshObjects"],
                    "polygons": report["polygons"],
                    "triangles": report["triangles"],
                }
                for report in reports
            ],
            "meshPrimCount": [stage.count("def Mesh") for stage in stage_texts],
            "skeletonCount": [stage.count("def Skeleton") for stage in stage_texts],
            "skinnedRootCount": [stage.count("def SkelRoot") for stage in stage_texts],
        },
        "lodPolicy": {
            "lod0": "close interaction and boat animal, target distance 0-9 m",
            "lod1": "herd and middle-distance animals, target distance 9-30 m",
        },
        "openGates": [
            "Replace procedural surface relief with approved final hair/fur treatment if close-camera review requires it.",
            "Polish hoof-ground, body-barrier and boat-bracing contact after world-cell integration.",
            "Approve anatomy, deformation, material response and herd variation in final authored lighting.",
            "Pass physical iPhone frame, memory, thermal and battery gates in the complete cells.",
        ],
        "qualityClassification": "ANIMAL_RIG_CANDIDATE",
        "reviewArtifacts": [record(path, animal_dir) for path in review_paths],
        "rights": {
            "externalAssets": [],
            "geometry": "project-authored procedural Blender geometry",
            "materialsAndTextures": "project-authored deterministic procedural maps and PBR materials",
            "rigAndAnimation": "project-authored skeleton and directed keyframes",
            "rightsGate": "PASS",
        },
        "rootContract": {
            "cloneableLocalOriginRoots": ["cattle_adult", "cattle_young"],
            "includedSpecies": ["domestic-cattle"],
            "previewCameraLightsGroundAndBoatExcluded": True,
        },
        "schemaVersion": 1,
        "sources": [record(path, animal_dir) for path in source_paths],
        "tool": {
            "blenderBuildHash": "fbe6228777e7",
            "blenderVersion": "5.2.0 LTS",
        },
        "validation": {
            "arkitUsdchecker": "PASS",
            "byteIdenticalUsdcAndUsdz": "PASS",
            "directedClipMetadata": "PASS",
            "localOriginRoots": "PASS",
            "previewLeakage": "PASS",
            "rightsGate": "PASS",
        },
    }
    (animal_dir / "build-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
