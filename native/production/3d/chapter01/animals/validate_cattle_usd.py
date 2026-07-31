#!/usr/bin/env python3
"""Validate the local-origin, animated Chapter 01 cattle contract."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import zipfile
from pathlib import Path


ROOTS = ("cattle_adult", "cattle_young")
PREVIEW_TOKENS = (
    "preview_only",
    "preview_ground",
    "preview_camera",
    "preview_warm",
    "preview_cool",
)
REQUIRED_CLIPS = ("herd-walk", "barrier-weight-shift", "boat-brace", "boat-weight-shift")


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


def triangle_count(stage_text: str) -> int:
    count = 0
    for match in re.finditer(r"int\[\] faceVertexCounts\s*=\s*\[([^\]]*)\]", stage_text, re.DOTALL):
        values = [int(value) for value in re.findall(r"\d+", match.group(1))]
        count += sum(max(1, value - 2) for value in values)
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lod", type=int, choices=(0, 1), required=True)
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
    if 'def Camera ' in stage_text or 'def RectLight ' in stage_text or 'def SphereLight ' in stage_text:
        raise AssertionError("Preview camera or light leaked into runtime USD")

    for root in ROOTS:
        block = prim_block(stage_text, root)
        header_end = block.find("def SkelRoot") if "def SkelRoot" in block else len(block)
        header = block[:header_end]
        authored_transform = re.search(
            r"^\s*(?:double|float|half|matrix|quat|token).*\bxformOp(?:Order|:).*\=",
            header,
            re.MULTILINE,
        )
        if authored_transform:
            raise AssertionError(f"Root is not local-origin cloneable: {root}")

    if stage_text.count("def SkelRoot") != 2:
        raise AssertionError("Expected exactly two skinned cattle roots")
    if stage_text.count("def Skeleton") != 2:
        raise AssertionError("Expected exactly two cattle skeletons")
    if stage_text.count("def SkelAnimation") < 2:
        raise AssertionError("Directed skeletal animation did not export")
    for clip in REQUIRED_CLIPS:
        if clip not in stage_text:
            raise AssertionError(f"Missing directed clip metadata: {clip}")

    triangles = triangle_count(stage_text)
    limits = {0: (8_000, 100_000), 1: (3_000, 45_000)}
    minimum, maximum = limits[args.lod]
    if not minimum <= triangles <= maximum:
        raise AssertionError(
            f"LOD{args.lod} triangle count {triangles} outside [{minimum}, {maximum}]"
        )

    with zipfile.ZipFile(args.usdz) as archive:
        members = archive.namelist()
    if not members or members[0] != args.usdc.name:
        raise AssertionError("USDZ root layer is not the first package member")
    if any(token in member.lower() for member in members for token in PREVIEW_TOKENS):
        raise AssertionError("Preview-only file leaked into USDZ")
    required_textures = {
        "textures/cattle-adult-hide-basecolor.png",
        "textures/cattle-young-hide-basecolor.png",
        "textures/cattle-hide-normal.png",
    }
    missing = sorted(required_textures - set(members))
    if missing:
        raise AssertionError(f"Missing packaged project-authored textures: {missing}")

    print(
        json.dumps(
            {
                "classification": "ANIMAL_RIG_CANDIDATE",
                "directedClips": list(REQUIRED_CLIPS),
                "finalArtGate": "OPEN",
                "localOriginRoots": list(ROOTS),
                "lod": args.lod,
                "previewLeakage": "PASS",
                "skeletonCount": 2,
                "triangles": triangles,
                "usdzMemberCount": len(members),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
