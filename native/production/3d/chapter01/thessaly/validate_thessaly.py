"""Headless structural validation for the Thessaly USD family."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from pxr import Sdf, Usd, UsdGeom, UsdShade


REQUIRED_LOGICAL_NAMES = {
    "thessalian-household-store",
    "worked-field",
    "harvest-grain-source",
    "food-grain",
    "reserve-grain",
    "seed-grain",
    "raised-store",
    "household-hearth-flame",
    "winter-rain",
    "state-harvest",
    "state-winter",
    "state-spring",
    "person-grinding-grain",
    "person-carrying-seed",
    "action-grain-source",
    "action-food",
    "action-reserve",
    "action-seed",
    "action-store-seal",
    "action-store-repair",
    "action-spring-sow",
    "camera-harvest-overview",
    "camera-allocation-close",
    "camera-winter-loss",
    "camera-repair",
    "camera-spring-sowing",
    "transition-aegean-in",
    "transition-iron-gates-out",
    "carrier-dry-seed-entry",
    "carrier-sown-seed-exit",
}

ACTION_NAMES = {
    "action-grain-source",
    "action-food",
    "action-reserve",
    "action-seed",
    "action-store-seal",
    "action-store-repair",
    "action-spring-sow",
}


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", type=Path, required=True)
    parser.add_argument("--lod1", type=Path, required=True)
    parser.add_argument("--lod2", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--bindings", type=Path, required=True)
    return parser.parse_args(raw)


def open_stage(path: Path) -> Usd.Stage:
    if not path.is_file() or path.stat().st_size == 0:
        raise AssertionError(f"Missing or empty asset: {path}")
    stage = Usd.Stage.Open(str(path))
    if stage is None:
        raise AssertionError(f"USD failed to open: {path}")
    return stage


def logical_map(stage: Usd.Stage) -> dict[str, Usd.Prim]:
    result: dict[str, Usd.Prim] = {}
    for prim in stage.TraverseAll():
        attribute = prim.GetAttribute("userProperties:runtimeName")
        if not attribute:
            continue
        value = attribute.Get()
        if isinstance(value, str) and value:
            if value in result:
                raise AssertionError(f"Duplicate runtimeName in stage: {value}")
            result[value] = prim
            if prim.GetDisplayName() != value:
                raise AssertionError(f"displayName mismatch for {value}: {prim.GetDisplayName()}")
    return result


def mesh_counts(stage: Usd.Stage) -> tuple[int, int, int]:
    meshes = 0
    vertices = 0
    triangles = 0
    for prim in stage.TraverseAll():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        meshes += 1
        mesh = UsdGeom.Mesh(prim)
        points = mesh.GetPointsAttr().Get() or []
        counts = mesh.GetFaceVertexCountsAttr().Get() or []
        vertices += len(points)
        triangles += sum(max(0, int(count) - 2) for count in counts)
    return meshes, vertices, triangles


def contains_mesh(prim: Usd.Prim) -> bool:
    if prim.IsA(UsdGeom.Mesh):
        return True
    return any(descendant.IsA(UsdGeom.Mesh) for descendant in Usd.PrimRange(prim))


def validate_primary(stage: Usd.Stage, bindings_path: Path) -> dict[str, int]:
    if UsdGeom.GetStageUpAxis(stage) != UsdGeom.Tokens.y:
        raise AssertionError(f"Expected Y-up, got {UsdGeom.GetStageUpAxis(stage)}")
    meters = UsdGeom.GetStageMetersPerUnit(stage)
    if abs(meters - 1.0) > 1e-8:
        raise AssertionError(f"Expected metersPerUnit 1.0, got {meters}")

    mapping = logical_map(stage)
    missing = sorted(REQUIRED_LOGICAL_NAMES - set(mapping))
    if missing:
        raise AssertionError(f"Missing required logical entities: {missing}")
    default = stage.GetDefaultPrim()
    if not default or default.GetDisplayName() != "thessalian-household-store":
        raise AssertionError("Default prim is not thessalian-household-store")

    declared = json.loads(bindings_path.read_text(encoding="utf-8"))
    if declared.get("schemaVersion") != 1:
        raise AssertionError("Unsupported entity-bindings schema")
    for binding in declared["bindings"]:
        logical = binding["logicalName"]
        path = Sdf.Path(binding["primPath"])
        if logical not in mapping:
            raise AssertionError(f"Declared binding missing from USD: {logical}")
        if mapping[logical].GetPath() != path:
            raise AssertionError(
                f"Binding path mismatch for {logical}: expected {path}, got {mapping[logical].GetPath()}"
            )

    for name in ACTION_NAMES:
        prim = mapping[name]
        if not contains_mesh(prim):
            raise AssertionError(f"Action entity has no collision-source mesh: {name}")
        collision = prim.GetAttribute("userProperties:collisionEnabled")
        shape = prim.GetAttribute("userProperties:collisionShape")
        if not collision or collision.Get() is not True or not shape or shape.Get() != "box":
            raise AssertionError(f"Action entity lacks collision metadata: {name}")

    materials = sum(1 for prim in stage.TraverseAll() if prim.IsA(UsdShade.Material))
    cameras = sum(1 for prim in stage.TraverseAll() if prim.IsA(UsdGeom.Camera))
    meshes, vertices, triangles = mesh_counts(stage)
    if materials < 18:
        raise AssertionError(f"Expected materially rich scene; only {materials} USD materials")
    if cameras < 5:
        raise AssertionError(f"Expected five camera anchors; only {cameras} cameras")
    if meshes < 80 or vertices < 6000 or triangles < 8000:
        raise AssertionError(
            f"Scene is below authored-detail floor: meshes={meshes}, vertices={vertices}, triangles={triangles}"
        )
    return {
        "materials": materials,
        "cameras": cameras,
        "meshes": meshes,
        "vertices": vertices,
        "triangles": triangles,
    }


def validate_lods(full: Usd.Stage, lod1: Usd.Stage, lod2: Usd.Stage) -> dict[str, int]:
    full_counts = mesh_counts(full)
    lod1_counts = mesh_counts(lod1)
    lod2_counts = mesh_counts(lod2)
    if not (full_counts[2] > lod1_counts[2] > lod2_counts[2]):
        raise AssertionError(
            f"LOD triangle counts are not strictly descending: {full_counts[2]}, {lod1_counts[2]}, {lod2_counts[2]}"
        )
    if lod1_counts[2] > full_counts[2] * 0.82:
        raise AssertionError("LOD1 does not remove at least 18% of full-detail triangles")
    if lod2_counts[2] > full_counts[2] * 0.60:
        raise AssertionError("LOD2 does not remove at least 40% of full-detail triangles")
    for stage, label in ((lod1, "LOD1"), (lod2, "LOD2")):
        mapping = logical_map(stage)
        essential = {
            "thessalian-household-store",
            "worked-field",
            "food-grain",
            "reserve-grain",
            "seed-grain",
            "raised-store",
            "state-harvest",
            "state-winter",
            "state-spring",
            "action-grain-source",
            "action-food",
            "action-reserve",
            "action-seed",
            "transition-aegean-in",
            "transition-iron-gates-out",
        }
        missing = sorted(essential - set(mapping))
        if missing:
            raise AssertionError(f"{label} dropped essential bindings: {missing}")
    return {
        "lod0Triangles": full_counts[2],
        "lod1Triangles": lod1_counts[2],
        "lod2Triangles": lod2_counts[2],
    }


def validate_package(path: Path) -> None:
    package_stage = open_stage(path)
    if package_stage.GetDefaultPrim().GetDisplayName() != "thessalian-household-store":
        raise AssertionError("USDZ default prim contract changed")
    command = ["/usr/bin/usdchecker", "--arkit", str(path)]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise AssertionError(
            f"RealityKit USDZ compliance failed\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )


def main() -> None:
    args = parse_args()
    full = open_stage(args.asset)
    lod1 = open_stage(args.lod1)
    lod2 = open_stage(args.lod2)
    metrics = validate_primary(full, args.bindings)
    metrics.update(validate_lods(full, lod1, lod2))
    validate_package(args.package)
    print(json.dumps({"status": "PASS", **metrics}, sort_keys=True))


if __name__ == "__main__":
    main()

