#!/usr/bin/env python3
"""Validate the rights-cleared Chapter 01 hero-rig candidate contract."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import zipfile
from pathlib import Path


ROOTS = ("hero_adult_a", "hero_adult_b", "hero_youth")
PREVIEW_TOKENS = (
    "preview_only",
    "preview_ground",
    "preview_camera",
    "preview_warm_key",
    "preview_cool_fill",
)
FORBIDDEN_GARMENT_SOURCE_TOKENS = (
    "suits02",
    "rehmanpolanski",
    "viking_tunic",
    "viking_pants",
    "tunicviking",
    "pantsviking",
)
GARMENT_PRIMS = tuple(
    f"hero_{character_id}_{garment}"
    for character_id in ("adult_a", "adult_b", "youth")
    for garment in ("woven_garment", "woven_belt")
)


def prim_block(stage_text: str, prim_name: str) -> str:
    marker = f'def Xform "{prim_name}"'
    start = stage_text.find(marker)
    if start < 0:
        raise AssertionError(f"Missing root prim: {prim_name}")
    brace = stage_text.find("{", start)
    depth = 0
    for index in range(brace, len(stage_text)):
        if stage_text[index] == "{":
            depth += 1
        elif stage_text[index] == "}":
            depth -= 1
            if depth == 0:
                return stage_text[start : index + 1]
    raise AssertionError(f"Unclosed root prim: {prim_name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--usdc", type=Path, required=True)
    parser.add_argument("--usdz", type=Path, required=True)
    args = parser.parse_args()

    stage_text = subprocess.run(
        ["/usr/bin/usdcat", str(args.usdc)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout

    lowered = stage_text.lower()
    for token in PREVIEW_TOKENS:
        if token in lowered:
            raise AssertionError(f"Preview-only token leaked into runtime USD: {token}")
    for token in FORBIDDEN_GARMENT_SOURCE_TOKENS:
        if token in lowered:
            raise AssertionError(f"Removed garment source leaked into runtime USD: {token}")
    if 'def Camera ' in stage_text or 'def RectLight ' in stage_text or 'def SphereLight ' in stage_text:
        raise AssertionError("Preview camera or light leaked into runtime USD")

    for garment_prim in GARMENT_PRIMS:
        if f'def Xform "{garment_prim}"' not in stage_text:
            raise AssertionError(f"Missing project-authored garment prim: {garment_prim}")

    if "project-authored-fitted-and-parametric-garment-v3" not in stage_text:
        raise AssertionError("Missing profiled-garment authority marker")
    if "fitted-bodice-fixed-drape-belted-tunic" not in stage_text:
        raise AssertionError("Missing deterministic silhouette authority marker")
    if "pinned-cc0-hair-with-project-clearance-v1" not in stage_text:
        raise AssertionError("Missing deterministic hair-clearance marker")

    for root in ROOTS:
        block = prim_block(stage_text, root)
        header = block[: block.find("def SkelRoot") if "def SkelRoot" in block else len(block)]
        authored_transform = re.search(
            r"^\s*(?:double|float|half|matrix|quat|token).*\bxformOp(?:Order|:).*\=",
            header,
            re.MULTILINE,
        )
        if authored_transform:
            raise AssertionError(f"Root is not local-origin cloneable: {root}")

    if stage_text.count("def SkelRoot") != 3:
        raise AssertionError("Expected exactly three skinned character roots")
    if stage_text.count("def Skeleton") != 3:
        raise AssertionError("Expected exactly three skeletons")

    with zipfile.ZipFile(args.usdz) as archive:
        members = archive.namelist()
    if not members or members[0] != args.usdc.name:
        raise AssertionError("USDZ root layer is not the first package member")
    if any(token in member.lower() for member in members for token in PREVIEW_TOKENS):
        raise AssertionError("Preview-only file leaked into USDZ")
    if any(
        token in member.lower()
        for member in members
        for token in FORBIDDEN_GARMENT_SOURCE_TOKENS
    ):
        raise AssertionError("Removed garment source leaked into USDZ")
    required_textures = {
        f"textures/skin-{character_id.replace('_', '-')}-basecolor.png"
        for character_id in ("adult-a", "adult-b", "youth")
    }
    if not required_textures.issubset(set(members)):
        missing = sorted(required_textures - set(members))
        raise AssertionError(f"Missing packaged skin textures: {missing}")

    print(
        json.dumps(
            {
                "classification": "HERO_RIG_CANDIDATE",
                "finalArtGate": "OPEN",
                "garmentAuthority": "project-authored-fitted-and-parametric-garment-v3",
                "garmentRightsGate": "PASS",
                "localOriginRoots": list(ROOTS),
                "previewLeakage": "PASS",
                "skeletonCount": 3,
                "usdzMemberCount": len(members),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
