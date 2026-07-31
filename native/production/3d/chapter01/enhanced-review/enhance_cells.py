#!/usr/bin/env python3
"""Build non-shipping Chapter 01 cells with shared skinned hero candidates.

Run this module through Blender so its bundled USD Python bindings are used.
The source cells and hero library are never modified. Each output root layer
sublayers an exact copied source cell and adds reversible visibility and hero
reference opinions at the existing person placeholders.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import traceback
import zipfile

import bpy
from mathutils import Vector
from pxr import Gf, Sdf, Usd, UsdGeom, UsdSkel


FIXED_MTIME = 1_700_000_000
CLASSIFICATION = "GREYBOX_CONTINUITY_CANDIDATE"
FINAL_ART_GATE = "OPEN"
SHIPPING_STATUS = "BLOCKED"
HERO_ROOTS = ("hero_adult_a", "hero_adult_b", "hero_youth")
HERO_MATERIALS = {
    "hero_adult_a": (
        "cloth_adult_a",
        "cloth_dark_adult_a",
        "hair_adult_a",
        "skin_adult_a",
    ),
    "hero_adult_b": (
        "cloth_adult_b",
        "cloth_dark_adult_b",
        "hair_adult_b",
        "skin_adult_b",
    ),
    "hero_youth": (
        "cloth_youth",
        "cloth_dark_youth",
        "hair_youth",
        "skin_youth",
    ),
}
ANIMAL_VARIANTS = {
    "cattle_adult": {
        "sourceKey": "sourceLOD1",
        "root": "cattle_adult",
        "filename": "cattle_adult-lod1.usdc",
    },
    "cattle_young": {
        "sourceKey": "sourceLOD0",
        "root": "cattle_young",
        "filename": "cattle_young-lod0.usdc",
    },
}
ANIMAL_MATERIALS = (
    "cattle_adult_hide",
    "cattle_cloven_hoof",
    "cattle_eye",
    "cattle_horn",
    "cattle_inner_ear",
    "cattle_muzzle",
    "cattle_nostril",
    "cattle_tail_tuft",
    "cattle_young_hide",
)


def parse_args() -> argparse.Namespace:
    argv = []
    if "--" in os.sys.argv:
        argv = os.sys.argv[os.sys.argv.index("--") + 1 :]
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--render-previews", action="store_true")
    parser.add_argument("--verify-reproducible", action="store_true")
    return parser.parse_args(argv)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pin_timestamp(path: Path) -> None:
    os.utime(path, (FIXED_MTIME, FIXED_MTIME))


def normalize_zip(path: Path) -> None:
    """Fix ZIP timestamps in place without breaking USDZ byte alignment."""

    payload = bytearray(path.read_bytes())
    end_offset = payload.rfind(b"PK\x05\x06")
    if end_offset < 0:
        raise RuntimeError(f"USDZ end-of-central-directory record missing: {path}")
    entry_count = struct.unpack_from("<H", payload, end_offset + 10)[0]
    central_offset = struct.unpack_from("<I", payload, end_offset + 16)[0]
    cursor = central_offset
    fixed_time = 0
    fixed_date = 0x0021
    for _ in range(entry_count):
        if payload[cursor : cursor + 4] != b"PK\x01\x02":
            raise RuntimeError(f"Malformed USDZ central directory: {path}")
        name_length, extra_length, comment_length = struct.unpack_from(
            "<HHH", payload, cursor + 28
        )
        local_offset = struct.unpack_from("<I", payload, cursor + 42)[0]
        if payload[local_offset : local_offset + 4] != b"PK\x03\x04":
            raise RuntimeError(f"Malformed USDZ local entry: {path}")
        struct.pack_into("<HH", payload, cursor + 12, fixed_time, fixed_date)
        struct.pack_into("<HH", payload, local_offset + 10, fixed_time, fixed_date)
        cursor += 46 + name_length + extra_length + comment_length
    path.write_bytes(payload)
    pin_timestamp(path)


def strip_volatile_png_metadata(path: Path) -> None:
    """Remove Blender timing and source-path receipts from a review PNG."""

    payload = path.read_bytes()
    signature = b"\x89PNG\r\n\x1a\n"
    if not payload.startswith(signature):
        raise RuntimeError(f"Preview is not PNG: {path}")
    output = bytearray(signature)
    cursor = len(signature)
    volatile_keys = {b"File", b"Date", b"Time", b"RenderTime"}
    while cursor < len(payload):
        if cursor + 12 > len(payload):
            raise RuntimeError(f"Preview PNG is truncated: {path}")
        length = struct.unpack_from(">I", payload, cursor)[0]
        chunk_end = cursor + 12 + length
        if chunk_end > len(payload):
            raise RuntimeError(f"Preview PNG chunk is truncated: {path}")
        chunk_type = payload[cursor + 4 : cursor + 8]
        chunk_data = payload[cursor + 8 : cursor + 8 + length]
        key = chunk_data.split(b"\x00", 1)[0] if chunk_type == b"tEXt" else b""
        if key not in volatile_keys:
            output.extend(payload[cursor:chunk_end])
        cursor = chunk_end
    path.write_bytes(output)
    pin_timestamp(path)


def relative_to_repo(repo_root: Path, path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return resolved.as_posix()


def copy_exact(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    pin_timestamp(destination)


def verify_source_package(source_usdc: Path, source_usdz: Path) -> str:
    with zipfile.ZipFile(source_usdz) as archive:
        candidates = [name for name in archive.namelist() if name.endswith(".usdc")]
        if len(candidates) != 1:
            raise RuntimeError(
                f"Expected one USDC payload in {source_usdz}, found {len(candidates)}"
            )
        payload = archive.read(candidates[0])
    if payload != source_usdc.read_bytes():
        raise RuntimeError(
            f"Sidecar {source_usdc} is not byte-identical to {source_usdz} payload"
        )
    return candidates[0]


def copy_textures(hero_library: Path, hero_output: Path) -> None:
    source_dir = hero_library.parent / "textures"
    destination = hero_output / "textures"
    destination.mkdir(parents=True, exist_ok=True)
    for source in sorted(source_dir.glob("*.png")):
        copy_exact(source, destination / source.name)


def create_animal_variants(
    animal_sources: dict[str, Path], animal_output: Path
) -> dict[str, Path]:
    """Extract deterministic, self-contained cattle roots for cell instancing."""

    animal_output.mkdir(parents=True, exist_ok=True)
    texture_source = animal_sources["sourceLOD0"].parent / "textures"
    texture_destination = animal_output / "textures"
    texture_destination.mkdir(parents=True, exist_ok=True)
    for source in sorted(texture_source.glob("*.png")):
        copy_exact(source, texture_destination / source.name)

    variants: dict[str, Path] = {}
    for animal_name, variant_spec in ANIMAL_VARIANTS.items():
        source = animal_sources[variant_spec["sourceKey"]]
        source_stage = Usd.Stage.Open(str(source))
        if source_stage is None:
            raise RuntimeError(f"Could not open animal library: {source}")
        source_layer = source_stage.GetRootLayer()
        if source_layer.subLayerPaths:
            raise RuntimeError(f"Pinned animal library unexpectedly gained sublayers: {source}")

        destination = animal_output / variant_spec["filename"]
        authoring_layer = animal_output / f".{animal_name}-authoring.usda"
        if destination.exists():
            destination.unlink()
        if authoring_layer.exists():
            authoring_layer.unlink()
        stage = Usd.Stage.CreateNew(str(authoring_layer))
        root = UsdGeom.Xform.Define(stage, "/root").GetPrim()
        UsdGeom.Scope.Define(stage, "/root/_materials")
        stage.SetDefaultPrim(root)
        stage.SetMetadata("metersPerUnit", 1.0)
        stage.SetStartTimeCode(1)
        stage.SetEndTimeCode(64)
        stage.SetTimeCodesPerSecond(24)
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)
        destination_layer = stage.GetRootLayer()
        for material_name in ANIMAL_MATERIALS:
            material_path = Sdf.Path(f"/root/_materials/{material_name}")
            if not Sdf.CopySpec(
                source_layer, material_path, destination_layer, material_path
            ):
                raise RuntimeError(f"Could not copy animal material {material_name}")
        animal_path = Sdf.Path(f"/root/{variant_spec['root']}")
        if not Sdf.CopySpec(
            source_layer, animal_path, destination_layer, animal_path
        ):
            raise RuntimeError(f"Could not copy animal root {animal_name}")
        for prim in stage.TraverseAll():
            for attribute in prim.GetAttributes():
                value = attribute.Get()
                if isinstance(value, Sdf.AssetPath) and value.path.endswith(".png"):
                    attribute.Set(Sdf.AssetPath(f"./textures/{Path(value.path).name}"))
        stage.GetRootLayer().Save()
        converter = subprocess.run(
            ["/usr/bin/usdcat", authoring_layer.name, "-o", destination.name],
            cwd=animal_output,
            check=False,
            text=True,
            capture_output=True,
        )
        authoring_layer.unlink()
        if converter.returncode != 0 or not destination.exists():
            raise RuntimeError(
                f"USD animal variant conversion failed for {animal_name}:\n"
                f"{converter.stdout}\n{converter.stderr}"
            )
        pin_timestamp(destination)
        variants[animal_name] = destination
    return variants


def create_hero_variants(hero_library: Path, hero_output: Path) -> dict[str, Path]:
    hero_output.mkdir(parents=True, exist_ok=True)
    copy_textures(hero_library, hero_output)
    source_stage = Usd.Stage.Open(str(hero_library))
    if source_stage is None:
        raise RuntimeError(f"Could not open hero library: {hero_library}")
    source_layer = source_stage.GetRootLayer()
    if source_layer.subLayerPaths:
        raise RuntimeError("Pinned hero library unexpectedly gained sublayers")
    variants: dict[str, Path] = {}
    for hero_root in HERO_ROOTS:
        destination = hero_output / f"{hero_root}.usdc"
        authoring_layer = hero_output / f".{hero_root}-authoring.usda"
        if destination.exists():
            destination.unlink()
        if authoring_layer.exists():
            authoring_layer.unlink()
        stage = Usd.Stage.CreateNew(str(authoring_layer))
        root = UsdGeom.Xform.Define(stage, "/root").GetPrim()
        UsdGeom.Scope.Define(stage, "/root/_materials")
        stage.SetDefaultPrim(root)
        stage.SetMetadata("metersPerUnit", 1.0)
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)
        destination_layer = stage.GetRootLayer()
        for material_name in HERO_MATERIALS[hero_root]:
            source_path = Sdf.Path(f"/root/_materials/{material_name}")
            destination_path = Sdf.Path(f"/root/_materials/{material_name}")
            if not Sdf.CopySpec(
                source_layer, source_path, destination_layer, destination_path
            ):
                raise RuntimeError(f"Could not copy hero material {material_name}")
        source_path = Sdf.Path(f"/root/{hero_root}")
        destination_path = Sdf.Path(f"/root/{hero_root}")
        if not Sdf.CopySpec(source_layer, source_path, destination_layer, destination_path):
            raise RuntimeError(f"Could not copy hero root {hero_root}")
        for prim in stage.TraverseAll():
            for attribute in prim.GetAttributes():
                value = attribute.Get()
                if isinstance(value, Sdf.AssetPath) and value.path.endswith(".png"):
                    attribute.Set(
                        Sdf.AssetPath(f"./textures/{Path(value.path).name}")
                    )
        stage.GetRootLayer().Save()
        converter = subprocess.run(
            ["/usr/bin/usdcat", authoring_layer.name, "-o", destination.name],
            cwd=hero_output,
            check=False,
            text=True,
            capture_output=True,
        )
        authoring_layer.unlink()
        if converter.returncode != 0 or not destination.exists():
            raise RuntimeError(
                f"USD hero variant conversion failed for {hero_root}:\n"
                f"{converter.stdout}\n{converter.stderr}"
            )
        pin_timestamp(destination)
        variants[hero_root] = destination
    return variants


def binding_paths(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text())
    if isinstance(data.get("runtimeBindings"), dict):
        return data["runtimeBindings"]
    if isinstance(data.get("runtimeNameToUSDPath"), dict):
        return data["runtimeNameToUSDPath"]
    if isinstance(data.get("bindings"), list):
        return {
            item["logicalName"]: item["primPath"]
            for item in data["bindings"]
        }
    raise RuntimeError(f"Unsupported binding registry: {path}")


def path_is_within(path: Sdf.Path, ancestor: Sdf.Path) -> bool:
    return path == ancestor or path.HasPrefix(ancestor)


def hide_placeholder_geometry(
    stage: Usd.Stage,
    placeholder_path: str,
    protected_paths: list[str],
) -> list[str]:
    placeholder = stage.GetPrimAtPath(placeholder_path)
    if not placeholder.IsValid():
        raise RuntimeError(f"Missing placeholder: {placeholder_path}")
    protected = [Sdf.Path(value) for value in protected_paths]
    hidden: list[str] = []
    for prim in Usd.PrimRange(placeholder):
        if prim == placeholder:
            continue
        if any(path_is_within(prim.GetPath(), item) for item in protected):
            continue
        if prim.IsA(UsdGeom.Mesh) or prim.IsA(UsdGeom.BasisCurves):
            UsdGeom.Imageable(prim).MakeInvisible()
            hidden.append(str(prim.GetPath()))
    if not hidden:
        raise RuntimeError(f"No stand-in geometry found below {placeholder_path}")
    return hidden


def add_hero_reference(
    stage: Usd.Stage,
    person: dict,
    hero_relative_path: str,
) -> str:
    placeholder_path = person["placeholder"]
    hero_path = f"{placeholder_path}/enhanced_review_hero"
    hero = UsdGeom.Xform.Define(stage, hero_path).GetPrim()
    hero.GetReferences().AddReference(hero_relative_path, "/root")
    hero.SetInstanceable(True)
    xform = UsdGeom.Xformable(hero)
    xform.ClearXformOpOrder()
    translation = person.get("translation", [0.0, 0.0, 0.0])
    rotation = person.get("rotationDegrees", [0.0, 0.0, 0.0])
    scale = float(person.get("scale", 1.0))
    xform.AddTranslateOp().Set(Gf.Vec3d(*translation))
    xform.AddRotateXYZOp().Set(Gf.Vec3f(*rotation))
    xform.AddScaleOp().Set(Gf.Vec3f(scale, scale, scale))
    hero.CreateAttribute(
        "userProperties:classification", Sdf.ValueTypeNames.String, custom=True
    ).Set(CLASSIFICATION)
    hero.CreateAttribute(
        "userProperties:sourceHero", Sdf.ValueTypeNames.String, custom=True
    ).Set(person["hero"])
    return hero_path


def add_animal_reference(
    stage: Usd.Stage,
    animal: dict,
    animal_relative_path: str,
) -> str:
    placeholder_path = animal["placeholder"]
    animal_path = f"{placeholder_path}/enhanced_review_animal"
    candidate = UsdGeom.Xform.Define(stage, animal_path).GetPrim()
    candidate.GetReferences().AddReference(animal_relative_path, "/root")
    candidate.SetInstanceable(True)
    xform = UsdGeom.Xformable(candidate)
    xform.ClearXformOpOrder()
    translation = animal.get("translation", [0.0, 0.0, 0.0])
    rotation = animal.get("rotationDegrees", [0.0, 0.0, 0.0])
    scale_value = animal.get("scale", 1.0)
    scale = (
        [float(scale_value), float(scale_value), float(scale_value)]
        if isinstance(scale_value, (int, float))
        else [float(value) for value in scale_value]
    )
    if len(scale) != 3:
        raise RuntimeError(f"Animal scale must have three values: {placeholder_path}")
    xform.AddTranslateOp().Set(Gf.Vec3d(*translation))
    xform.AddRotateXYZOp().Set(Gf.Vec3f(*rotation))
    xform.AddScaleOp().Set(Gf.Vec3f(*scale))
    candidate.CreateAttribute(
        "userProperties:classification", Sdf.ValueTypeNames.String, custom=True
    ).Set(CLASSIFICATION)
    candidate.CreateAttribute(
        "userProperties:sourceAnimal", Sdf.ValueTypeNames.String, custom=True
    ).Set(animal["animal"])
    candidate.CreateAttribute(
        "userProperties:directedClip", Sdf.ValueTypeNames.String, custom=True
    ).Set(animal["directedClip"])
    return animal_path


def source_default_prim_path(source: Path) -> Sdf.Path:
    stage = Usd.Stage.Open(str(source))
    if stage is None or not stage.GetDefaultPrim().IsValid():
        raise RuntimeError(f"Source has no valid default prim: {source}")
    return stage.GetDefaultPrim().GetPath()


def create_cell_stage(
    repo_root: Path,
    output_root: Path,
    cell: dict,
    hero_library: Path,
    hero_variants: dict[str, Path],
    animal_library: Path,
    animal_variants: dict[str, Path],
) -> dict:
    cell_dir = output_root / cell["id"]
    source_dir = cell_dir / "source"
    hero_dir = cell_dir / "hero"
    animal_dir = cell_dir / "animal"
    stale_texture_dir = cell_dir / "textures"
    if stale_texture_dir.exists():
        shutil.rmtree(stale_texture_dir)
    if animal_dir.exists():
        shutil.rmtree(animal_dir)
    source = (repo_root / cell["source"]).resolve()
    source_usdz = (repo_root / cell["sourceUSDZ"]).resolve()
    source_package_member = verify_source_package(source, source_usdz)
    bindings_source = (repo_root / cell["bindings"]).resolve()
    copied_source = source_dir / source.name
    copy_exact(source, copied_source)
    copied_hero_variants: list[Path] = []
    for _hero_root, variant in hero_variants.items():
        copied_variant = hero_dir / variant.name
        copy_exact(variant, copied_variant)
        copied_hero_variants.append(copied_variant)
    copy_textures(hero_library, hero_dir)
    hero_texture_paths = sorted(
        path for path in (hero_dir / "textures").glob("*") if path.is_file()
    )
    copied_animal_variants: list[Path] = []
    animal_texture_paths: list[Path] = []
    required_animals = sorted({item["animal"] for item in cell.get("animals", [])})
    if required_animals:
        animal_dir.mkdir(parents=True, exist_ok=True)
        for animal_name in required_animals:
            variant = animal_variants[animal_name]
            copied_variant = animal_dir / variant.name
            copy_exact(variant, copied_variant)
            copied_animal_variants.append(copied_variant)
        copy_textures(animal_library, animal_dir)
        animal_texture_paths = sorted(
            path for path in (animal_dir / "textures").glob("*") if path.is_file()
        )

    legacy_composition = cell_dir / f"{cell['id']}-enhanced-review-composition.usdc"
    if legacy_composition.exists():
        legacy_composition.unlink()
    output_usdc = cell_dir / f"{cell['id']}-enhanced-review.usdc"
    if output_usdc.exists():
        output_usdc.unlink()
    stage = Usd.Stage.CreateNew(str(output_usdc))
    root_layer = stage.GetRootLayer()
    root_layer.subLayerPaths = [f"./source/{copied_source.name}"]
    root_layer.Save()
    stage.Reload()
    default_path = source_default_prim_path(source)
    default_prim = stage.GetPrimAtPath(default_path)
    if not default_prim.IsValid():
        raise RuntimeError(f"Composed source default prim is missing: {default_path}")
    stage.SetDefaultPrim(default_prim)
    source_stage = Usd.Stage.Open(str(source))
    stage.SetMetadata(
        "metersPerUnit", source_stage.GetMetadata("metersPerUnit") or 1.0
    )
    up_axis = UsdGeom.GetStageUpAxis(source_stage)
    UsdGeom.SetStageUpAxis(stage, up_axis)

    hidden_paths: dict[str, list[str]] = {}
    hero_paths: dict[str, str] = {}
    for person in cell["people"]:
        placeholder = person["placeholder"]
        hidden_paths[placeholder] = hide_placeholder_geometry(
            stage, placeholder, person.get("protectedSubtrees", [])
        )
        hero_name = person["hero"]
        hero_paths[placeholder] = add_hero_reference(
            stage, person, f"./hero/{hero_variants[hero_name].name}"
        )

    animal_paths: dict[str, str] = {}
    for animal in cell.get("animals", []):
        placeholder = animal["placeholder"]
        hidden_paths[placeholder] = hide_placeholder_geometry(stage, placeholder, [])
        animal_name = animal["animal"]
        animal_paths[placeholder] = add_animal_reference(
            stage, animal, f"./animal/{animal_variants[animal_name].name}"
        )

    stage.GetRootLayer().Save()
    pin_timestamp(output_usdc)
    composed = Usd.Stage.Open(str(output_usdc))
    if composed is None:
        raise RuntimeError(f"Could not reopen enhanced cell: {output_usdc}")
    bindings = binding_paths(bindings_source)
    missing_bindings = [
        name
        for name, prim_path in bindings.items()
        if not composed.GetPrimAtPath(prim_path).IsValid()
    ]
    if missing_bindings:
        raise RuntimeError(
            f"{cell['id']} lost canonical bindings: {', '.join(missing_bindings)}"
        )
    composed_skeletons = [
        prim
        for prim in composed.Traverse(Usd.TraverseInstanceProxies())
        if prim.IsA(UsdSkel.Skeleton)
    ]
    expected_skeletons = len(cell["people"]) + len(cell.get("animals", []))
    if len(composed_skeletons) != expected_skeletons:
        raise RuntimeError(
            f"{cell['id']} expected {expected_skeletons} skeletons, "
            f"found {len(composed_skeletons)}"
        )
    for person in cell["people"]:
        for protected_path in person.get("protectedSubtrees", []):
            prim = composed.GetPrimAtPath(protected_path)
            if not prim.IsValid():
                raise RuntimeError(f"Protected work prop is missing: {protected_path}")
            imageable = UsdGeom.Imageable(prim)
            if imageable and imageable.ComputeVisibility() == UsdGeom.Tokens.invisible:
                raise RuntimeError(f"Protected work prop became invisible: {protected_path}")

    output_usdz = cell_dir / f"{cell['id']}-enhanced-review.usdz"
    if output_usdz.exists():
        output_usdz.unlink()
    package_candidate = cell_dir / f".{cell['id']}-enhanced-review.usdz"
    if package_candidate.exists():
        package_candidate.unlink()
    package_inputs = [output_usdc.name, f"source/{copied_source.name}"]
    package_inputs.extend(
        f"hero/{path.name}" for path in sorted(copied_hero_variants)
    )
    package_inputs.extend(
        f"hero/textures/{path.name}" for path in hero_texture_paths
    )
    package_inputs.extend(
        f"animal/{path.name}" for path in sorted(copied_animal_variants)
    )
    package_inputs.extend(
        f"animal/textures/{path.name}" for path in animal_texture_paths
    )
    packager = subprocess.run(
        ["/usr/bin/usdzip", package_candidate.name, *package_inputs],
        cwd=cell_dir,
        check=False,
        text=True,
        capture_output=True,
    )
    if packager.returncode != 0 or not package_candidate.exists():
        raise RuntimeError(
            f"usdzip failed for {cell['id']}:\n{packager.stdout}\n{packager.stderr}"
        )
    os.replace(package_candidate, output_usdz)
    normalize_zip(output_usdz)
    with zipfile.ZipFile(output_usdz) as archive:
        packaged_members = archive.namelist()
        if packaged_members != package_inputs:
            raise RuntimeError(
                f"{cell['id']} USDZ member order changed: {packaged_members}"
            )
        for member in packaged_members:
            unpackaged = cell_dir / member
            if archive.read(member) != unpackaged.read_bytes():
                raise RuntimeError(
                    f"{cell['id']} USDZ member changed during packaging: {member}"
                )
    checker = subprocess.run(
        ["/usr/bin/usdchecker", "--arkit", str(output_usdz)],
        check=False,
        text=True,
        capture_output=True,
    )
    if checker.returncode != 0:
        raise RuntimeError(
            f"usdchecker failed for {cell['id']}:\n{checker.stdout}\n{checker.stderr}"
        )
    return {
        "cellID": cell["id"],
        "source": relative_to_repo(repo_root, source),
        "sourceSHA256": sha256(source),
        "sourceUSDZ": relative_to_repo(repo_root, source_usdz),
        "sourceUSDZSHA256": sha256(source_usdz),
        "sourcePackageMember": source_package_member,
        "sourcePackagePayloadMatch": "PASS",
        "outputUSDC": relative_to_repo(repo_root, output_usdc),
        "outputUSDCSHA256": sha256(output_usdc),
        "outputUSDZ": relative_to_repo(repo_root, output_usdz),
        "outputUSDZSHA256": sha256(output_usdz),
        "canonicalBindingCount": len(bindings),
        "heroCount": len(cell["people"]),
        "animalCount": len(cell.get("animals", [])),
        "skeletonCount": len(composed_skeletons),
        "packageDependencyCount": len(package_inputs) - 1,
        "packageCompositionArcs": "CONTAINED",
        "packageMemberOrder": packaged_members,
        "packagePayloadMatch": "PASS",
        "hiddenStandInMeshCount": sum(len(value) for value in hidden_paths.values()),
        "heroPaths": hero_paths,
        "animalPaths": animal_paths,
        "protectedSubtrees": sorted(
            path
            for person in cell["people"]
            for path in person.get("protectedSubtrees", [])
        ),
        "usdcheckerARKit": "PASS",
        "poseRetention": {
            person["placeholder"]: person["poseRetention"]
            for person in cell["people"]
        },
    }


def clear_blender_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.materials,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def look_at(camera: bpy.types.Object, target: list[float]) -> None:
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def create_camera(view: dict, name: str) -> bpy.types.Object:
    camera_data = bpy.data.cameras.new(f"{name}-data")
    camera = bpy.data.objects.new(name, camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = view["cameraPosition"]
    camera_data.lens = float(view.get("lens", 48.0))
    camera_data.sensor_width = 32.0
    look_at(camera, view["cameraTarget"])
    return camera


def remove_preview_lights() -> None:
    for item in list(bpy.context.scene.objects):
        if item.type == "LIGHT":
            bpy.data.objects.remove(item, do_unlink=True)


def add_area_light(
    name: str,
    position: Vector,
    target: Vector,
    energy: float,
    size: float,
    color: tuple[float, float, float],
) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(light)
    light.location = position
    look_at(light, list(target))


def configure_preview_lighting(camera: bpy.types.Object, target: list[float]) -> None:
    remove_preview_lights()
    target_vector = Vector(target)
    forward = (target_vector - camera.location).normalized()
    up = Vector((0.0, 0.0, 1.0))
    right = forward.cross(up)
    if right.length < 0.001:
        right = Vector((1.0, 0.0, 0.0))
    right.normalize()
    add_area_light(
        "enhanced-review-key",
        target_vector - right * 3.2 - forward * 3.0 + up * 4.8,
        target_vector,
        1050.0,
        4.0,
        (1.0, 0.66, 0.38),
    )
    add_area_light(
        "enhanced-review-fill",
        target_vector + right * 4.0 - forward * 1.0 + up * 2.4,
        target_vector,
        560.0,
        5.0,
        (0.44, 0.62, 1.0),
    )
    add_area_light(
        "enhanced-review-rim",
        target_vector + forward * 3.8 + up * 4.0,
        target_vector + up * 0.8,
        820.0,
        3.2,
        (1.0, 0.38, 0.16),
    )


def prepare_preview_presentation(cell: dict) -> None:
    remove_preview_lights()
    hidden_patterns = ["*lod1*", "*lod2*"]
    hidden_patterns.extend(cell["preview"].get("hidePatterns", []))
    for item in bpy.context.scene.objects:
        hide_for_material = any(
            slot.material is not None and slot.material.name == "mat_collision"
            for slot in item.material_slots
        )
        hide_for_name = any(
            fnmatch.fnmatchcase(item.name, pattern) for pattern in hidden_patterns
        )
        if hide_for_material or hide_for_name:
            item.hide_render = True
            item.hide_viewport = True

    material_overrides = cell["preview"].get("materialOverrides", {})
    for material_name, values in material_overrides.items():
        material = bpy.data.materials.get(material_name)
        if material is None or material.node_tree is None:
            continue
        principled = material.node_tree.nodes.get("Principled BSDF")
        if principled is None:
            continue
        if "baseColor" in values and not principled.inputs["Base Color"].is_linked:
            color = values["baseColor"]
            principled.inputs["Base Color"].default_value = (*color, 1.0)
        if "roughness" in values:
            principled.inputs["Roughness"].default_value = float(values["roughness"])


def set_preview_state(view: dict) -> None:
    for name in view.get("forceVisible", []):
        item = bpy.data.objects.get(name)
        if item is not None:
            item.hide_render = False
            item.hide_viewport = False
    for name in view.get("forceHidden", []):
        item = bpy.data.objects.get(name)
        if item is not None:
            item.hide_render = True
            item.hide_viewport = True


def render_cell_preview(output_root: Path, cell: dict) -> list[Path]:
    cell_dir = output_root / cell["id"]
    output_usdc = cell_dir / f"{cell['id']}-enhanced-review.usdc"
    clear_blender_scene()
    result = bpy.ops.wm.usd_import(
        filepath=str(output_usdc),
        import_cameras=True,
        import_lights=True,
        import_materials=True,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender could not import {output_usdc}: {result}")
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 1280
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.dither_intensity = 0.0
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.15
    world = scene.world or bpy.data.worlds.new("enhanced-review-world")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.006, 0.010, 0.017, 1.0)
    background.inputs["Strength"].default_value = 0.08
    prepare_preview_presentation(cell)

    preview_dir = cell_dir / "previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    views = [dict(cell["preview"], suffix="portrait")]
    views.extend(cell["preview"].get("additionalViews", []))
    expected_previews = {
        preview_dir / f"{cell['id']}-{view['suffix']}.png" for view in views
    }
    for stale_preview in preview_dir.glob(f"{cell['id']}-*.png"):
        if stale_preview not in expected_previews:
            stale_preview.unlink()
    rendered: list[Path] = []
    for view_index, view in enumerate(views):
        set_preview_state(view)
        if "cameraObject" in view:
            camera = bpy.data.objects.get(view["cameraObject"])
            if camera is None or camera.type != "CAMERA":
                raise RuntimeError(
                    f"Missing preview camera {view['cameraObject']} for {cell['id']}"
                )
        else:
            camera = create_camera(view, f"enhanced-review-camera-{view_index}")
        scene.camera = camera
        target = view.get("cameraTarget")
        if target is None:
            target = list(camera.location + camera.rotation_euler.to_matrix() @ Vector((0, 0, -5)))
        configure_preview_lighting(camera, target)
        destination = preview_dir / f"{cell['id']}-{view['suffix']}.png"
        scene.render.filepath = str(destination)
        bpy.ops.render.render(write_still=True)
        strip_volatile_png_metadata(destination)
        rendered.append(destination)
    return rendered


def build(
    repo_root: Path,
    output_root: Path,
    config: dict,
    render_previews: bool,
) -> dict:
    output_root.mkdir(parents=True, exist_ok=True)
    hero_config = config["heroLibrary"]
    hero_library = (repo_root / hero_config["source"]).resolve()
    actual_hero_hash = sha256(hero_library)
    if actual_hero_hash != hero_config["expectedSHA256"]:
        raise RuntimeError(
            "Hero library hash changed without a placement review: "
            f"expected {hero_config['expectedSHA256']}, got {actual_hero_hash}"
        )
    pinned_hero_inputs = {
        "sourceUSDZ": "expectedUSDZSHA256",
        "sourceManifest": "expectedManifestSHA256",
        "sourceProvenance": "expectedProvenanceSHA256",
    }
    verified_hero_inputs: dict[str, dict[str, str]] = {}
    for path_key, hash_key in pinned_hero_inputs.items():
        source_path = (repo_root / hero_config[path_key]).resolve()
        actual_hash = sha256(source_path)
        if actual_hash != hero_config[hash_key]:
            raise RuntimeError(
                f"Pinned hero input changed ({path_key}): "
                f"expected {hero_config[hash_key]}, got {actual_hash}"
            )
        verified_hero_inputs[path_key] = {
            "source": relative_to_repo(repo_root, source_path),
            "sha256": actual_hash,
        }
    provenance_path = (repo_root / hero_config["sourceProvenance"]).resolve()
    provenance = json.loads(provenance_path.read_text())
    if provenance.get("rightsGate") != "PASS":
        raise RuntimeError("Hero provenance rightsGate is not PASS")

    animal_config = config["animalLibrary"]
    animal_sources = {
        "sourceLOD0": (repo_root / animal_config["sourceLOD0"]).resolve(),
        "sourceLOD1": (repo_root / animal_config["sourceLOD1"]).resolve(),
    }
    pinned_animal_inputs = {
        "sourceLOD0": "expectedLOD0SHA256",
        "sourceLOD0USDZ": "expectedLOD0USDZSHA256",
        "sourceLOD1": "expectedLOD1SHA256",
        "sourceLOD1USDZ": "expectedLOD1USDZSHA256",
        "sourceManifest": "expectedManifestSHA256",
        "sourceProvenance": "expectedProvenanceSHA256",
    }
    verified_animal_inputs: dict[str, dict[str, str]] = {}
    for path_key, hash_key in pinned_animal_inputs.items():
        source_path = (repo_root / animal_config[path_key]).resolve()
        actual_hash = sha256(source_path)
        if actual_hash != animal_config[hash_key]:
            raise RuntimeError(
                f"Pinned animal input changed ({path_key}): "
                f"expected {animal_config[hash_key]}, got {actual_hash}"
            )
        verified_animal_inputs[path_key] = {
            "source": relative_to_repo(repo_root, source_path),
            "sha256": actual_hash,
        }
    animal_manifest = json.loads(
        (repo_root / animal_config["sourceManifest"]).read_text()
    )
    animal_provenance = json.loads(
        (repo_root / animal_config["sourceProvenance"]).read_text()
    )
    if animal_manifest.get("validation", {}).get("rightsGate") != "PASS":
        raise RuntimeError("Animal manifest rightsGate is not PASS")
    rights_review = animal_provenance.get("rights", {}).get("review", "")
    if not rights_review.startswith("PASS"):
        raise RuntimeError("Animal provenance rights review is not PASS")

    shared_hero_dir = output_root / "shared-hero-variants"
    hero_variants = create_hero_variants(hero_library, shared_hero_dir)
    shared_animal_dir = output_root / "shared-animal-variants"
    animal_variants = create_animal_variants(animal_sources, shared_animal_dir)
    cells = [
        create_cell_stage(
            repo_root,
            output_root,
            cell,
            hero_library,
            hero_variants,
            animal_sources["sourceLOD0"],
            animal_variants,
        )
        for cell in config["cells"]
    ]
    previews: dict[str, list[str]] = {}
    if render_previews:
        for cell in config["cells"]:
            previews[cell["id"]] = [
                relative_to_repo(repo_root, path)
                for path in render_cell_preview(output_root, cell)
            ]
    return {
        "schemaVersion": 1,
        "assetVersion": config["assetVersion"],
        "classification": CLASSIFICATION,
        "finalArtGate": FINAL_ART_GATE,
        "shippingStatus": SHIPPING_STATUS,
        "generatedAt": "deterministic-build",
        "heroLibrary": {
            "source": relative_to_repo(repo_root, hero_library),
            "sha256": actual_hero_hash,
            "classification": hero_config["classification"],
            "finalArtGate": hero_config["finalArtGate"],
            "rightsGate": hero_config["rightsGate"],
            "verifiedInputs": verified_hero_inputs,
        },
        "animalLibrary": {
            "classification": animal_config["classification"],
            "finalArtGate": animal_config["finalArtGate"],
            "rightsGate": animal_config["rightsGate"],
            "verifiedInputs": verified_animal_inputs,
        },
        "cells": cells,
        "previews": previews,
        "openGates": [
            "Visual QA remains failed: continuity geometry, action poses and contacts do not meet simulator-candidate quality.",
            "Final faces, hands, hair, costume and deformation are not approved.",
            "Final cattle anatomy, fur, deformation and environment contact are not approved.",
            "Exact hand-to-tool and foot-to-ground contact remains open.",
            "The source cells remain continuity geometry rather than final environment art.",
            "Physical iPhone performance, thermal and haptic gates remain open."
        ],
    }


def compare_reproducible(first_root: Path, second_root: Path, cells: list[dict]) -> None:
    paths: list[Path] = []
    for cell in cells:
        cell_id = cell["id"]
        paths.extend(
            [
                Path(cell_id) / f"{cell_id}-enhanced-review.usdc",
                Path(cell_id) / f"{cell_id}-enhanced-review.usdz",
            ]
        )
    for hero_root in HERO_ROOTS:
        paths.append(Path("shared-hero-variants") / f"{hero_root}.usdc")
    for variant_spec in ANIMAL_VARIANTS.values():
        paths.append(Path("shared-animal-variants") / variant_spec["filename"])
    mismatched = [
        str(relative)
        for relative in paths
        if (first_root / relative).read_bytes() != (second_root / relative).read_bytes()
    ]
    if mismatched:
        raise RuntimeError(
            "Enhanced review build is not byte reproducible: " + ", ".join(mismatched)
        )


def main() -> None:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    output_root = args.output.resolve()
    config = json.loads(args.config.read_text())
    result = build(repo_root, output_root, config, args.render_previews)
    if args.verify_reproducible:
        with tempfile.TemporaryDirectory(prefix="chapter01-enhanced-review-repro-") as temp:
            second_root = Path(temp) / "generated"
            build(repo_root, second_root, config, False)
            compare_reproducible(output_root, second_root, config["cells"])
        result["byteReproducibility"] = "PASS"
    else:
        result["byteReproducibility"] = "NOT_RUN"
    manifest = output_root / "enhanced-review-build-manifest.json"
    manifest.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    pin_timestamp(manifest)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(1)
