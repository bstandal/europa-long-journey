"""Generate the Chapter 01 hero-character source library with MPFB 2.0.15.

Run inside the pinned Blender 5.2 production environment with the MPFB
extension enabled. MPFB is a build-time tool only; the app receives baked
Blender/USD assets and has no dependency on the extension. Garment topology is
project-authored here from deterministic primitives and rig measurements. No
external garment mesh, clothing archive, MHCLO or OBJ is read or required.
"""

from __future__ import annotations

import math
import hashlib
import os
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector
from pxr import Sdf, Usd

from bl_ext.chapter01_mpfb.mpfb.services.humanservice import HumanService


def material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float,
    metallic: float = 0.0,
) -> bpy.types.Material:
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    principled = result.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    if "Subsurface Weight" in principled.inputs and name.startswith("skin-"):
        principled.inputs["Subsurface Weight"].default_value = 0.055
    return result


def textured_material(
    name: str,
    base_color_path: Path,
    roughness: float,
    normal_path: Path | None = None,
    skin: bool = False,
) -> bpy.types.Material:
    result = material(name, (1.0, 1.0, 1.0, 1.0), roughness)
    nodes = result.node_tree.nodes
    links = result.node_tree.links
    principled = nodes.get("Principled BSDF")

    base_texture = nodes.new("ShaderNodeTexImage")
    base_texture.name = f"{name}-basecolor"
    base_texture.label = "Pinned source texture" if skin else "Baked plain weave"
    base_texture.image = bpy.data.images.load(str(base_color_path), check_existing=False)
    base_texture.image.colorspace_settings.name = "sRGB"
    base_texture.interpolation = "Linear"
    links.new(base_texture.outputs["Color"], principled.inputs["Base Color"])

    if skin:
        if "Subsurface Weight" in principled.inputs:
            principled.inputs["Subsurface Weight"].default_value = 0.055

    if normal_path is not None:
        normal_texture = nodes.new("ShaderNodeTexImage")
        normal_texture.name = f"{name}-normal"
        normal_texture.label = "Baked plain-weave normal"
        normal_texture.image = bpy.data.images.load(str(normal_path), check_existing=False)
        normal_texture.image.colorspace_settings.name = "Non-Color"
        normal_texture.interpolation = "Linear"
        normal_map = nodes.new("ShaderNodeNormalMap")
        normal_map.inputs["Strength"].default_value = 0.11
        links.new(normal_texture.outputs["Color"], normal_map.inputs["Color"])
        links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])

    return result


SKIN = {
    "adult-a": (0.36, 0.19, 0.105, 1.0),
    "adult-b": (0.43, 0.245, 0.145, 1.0),
    "youth": (0.47, 0.285, 0.18, 1.0),
}

CLOTH = {
    "adult-a": (0.23, 0.155, 0.085, 1.0),
    "adult-b": (0.42, 0.31, 0.18, 1.0),
    "youth": (0.31, 0.245, 0.15, 1.0),
}

SKIN_TEXTURES = {
    "adult-a": (
        "middleage_lightskinned_male_diffuse2.png",
        "e897c4cc1b6ad5d10a7d2b2be92402feda4e772e6582dfaf0a1e8fc4621d8097",
    ),
    "adult-b": (
        "middleage_lightskinned_female_diffuse2.png",
        "39c505ca224387bef0b20cd2bf513c3997c27c7e7434447228c9991b87cb8d01",
    ),
    "youth": (
        "young_lightskinned_male_diffuse2.png",
        "03efe1f6b0ae52429649dcefc9dcaef6058032f874a251169cc3e2ed473c3874",
    ),
}

FIXED_FILE_TIMESTAMP = 315_532_800


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def pin_timestamp(path: Path) -> None:
    os.utime(path, (FIXED_FILE_TIMESTAMP, FIXED_FILE_TIMESTAMP))


def write_image(
    path: Path,
    name: str,
    width: int,
    height: int,
    pixels: list[float],
    colorspace: str,
) -> None:
    image = bpy.data.images.new(name, width=width, height=height, alpha=True)
    image.colorspace_settings.name = colorspace
    image.pixels.foreach_set(pixels)
    image.file_format = "PNG"
    image.filepath_raw = str(path)
    image.save()
    bpy.data.images.remove(image)
    pin_timestamp(path)


def woven_texture_pair(
    texture_directory: Path,
    texture_id: str,
    base_color: tuple[float, float, float, float],
) -> tuple[Path, Path]:
    """Bake a restrained, seamless plain weave for preview and USD export."""

    size = 256
    height_field: list[float] = [0.0] * (size * size)
    diffuse_pixels: list[float] = []

    for y in range(size):
        for x in range(size):
            warp_phase = math.tau * (x % 8) / 8.0
            weft_phase = math.tau * (y % 8) / 8.0
            warp = (0.5 + 0.5 * math.cos(warp_phase)) ** 3
            weft = (0.5 + 0.5 * math.cos(weft_phase)) ** 3
            over_under = 1.0 if ((x // 8) + (y // 8)) % 2 == 0 else -1.0
            fibre = math.sin((x * 0.57) + (y * 1.31)) * 0.012
            height_value = 0.48 + ((warp + weft) * 0.09) + (over_under * (warp - weft) * 0.035)
            height_field[(y * size) + x] = height_value
            color_factor = 0.93 + ((warp + weft) * 0.008) + (fibre * 0.15)
            diffuse_pixels.extend(
                (
                    max(0.0, min(1.0, base_color[0] * color_factor)),
                    max(0.0, min(1.0, base_color[1] * color_factor)),
                    max(0.0, min(1.0, base_color[2] * color_factor)),
                    1.0,
                )
            )

    normal_pixels: list[float] = []
    for y in range(size):
        for x in range(size):
            left = height_field[(y * size) + ((x - 1) % size)]
            right = height_field[(y * size) + ((x + 1) % size)]
            down = height_field[(((y - 1) % size) * size) + x]
            up = height_field[(((y + 1) % size) * size) + x]
            nx = (left - right) * 2.2
            ny = (down - up) * 2.2
            nz = 1.0
            length = math.sqrt((nx * nx) + (ny * ny) + (nz * nz))
            normal_pixels.extend(
                (
                    (nx / length * 0.5) + 0.5,
                    (ny / length * 0.5) + 0.5,
                    (nz / length * 0.5) + 0.5,
                    1.0,
                )
            )

    diffuse_path = texture_directory / f"woven-{texture_id}-basecolor.png"
    normal_path = texture_directory / f"woven-{texture_id}-normal.png"
    write_image(
        diffuse_path,
        f"woven-{texture_id}-basecolor",
        size,
        size,
        diffuse_pixels,
        "sRGB",
    )
    write_image(
        normal_path,
        f"woven-{texture_id}-normal",
        size,
        size,
        normal_pixels,
        "Non-Color",
    )
    return diffuse_path, normal_path


def prepare_material_textures(output: Path) -> dict[str, dict[str, Path]]:
    texture_directory = output / "textures"
    texture_directory.mkdir(parents=True, exist_ok=True)
    assets_root = Path(os.environ["CHAPTER01_MAKEHUMAN_ASSETS_ROOT"])
    source_root = Path(
        os.environ.get(
            "CHAPTER01_SKIN_TEXTURES_ROOT",
            str(assets_root / "base/skins/textures"),
        )
    )

    prepared: dict[str, dict[str, Path]] = {}
    for character_id, (filename, expected_hash) in SKIN_TEXTURES.items():
        source = source_root / filename
        if not source.is_file():
            raise RuntimeError(f"Missing pinned skin texture: {source}")
        actual_hash = sha256(source)
        if actual_hash != expected_hash:
            raise RuntimeError(
                f"Skin texture hash mismatch for {filename}: "
                f"expected {expected_hash}, found {actual_hash}"
            )
        destination = texture_directory / f"skin-{character_id}-basecolor.png"
        shutil.copyfile(source, destination)
        pin_timestamp(destination)

        cloth_base, cloth_normal = woven_texture_pair(
            texture_directory,
            character_id,
            CLOTH[character_id],
        )
        dark_color = tuple(component * 0.64 for component in CLOTH[character_id][:3]) + (1.0,)
        trouser_base, trouser_normal = woven_texture_pair(
            texture_directory,
            f"dark-{character_id}",
            dark_color,
        )
        prepared[character_id] = {
            "skin": destination,
            "clothBase": cloth_base,
            "clothNormal": cloth_normal,
            "trouserBase": trouser_base,
            "trouserNormal": trouser_normal,
        }
    return prepared


def clear_scene() -> None:
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


class GarmentMeshBuilder:
    """Accumulate deterministic garment surfaces, UVs and rig weights."""

    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.uvs: list[tuple[float, float]] = []
        self.weights: list[dict[str, float]] = []

    def vertex(
        self,
        coordinate: Vector,
        uv: tuple[float, float],
        weights: dict[str, float],
    ) -> int:
        index = len(self.vertices)
        self.vertices.append(tuple(float(value) for value in coordinate))
        self.uvs.append(uv)
        total = sum(weights.values())
        if total <= 0.0:
            raise RuntimeError("Authored garment vertex has no rig weight")
        self.weights.append(
            {bone: value / total for bone, value in weights.items() if value > 0.0}
        )
        return index

    def horizontal_ring(
        self,
        center: Vector,
        radius_x: float,
        radius_y: float,
        v_coordinate: float,
        weights: dict[str, float],
        segments: int = 20,
        z_shape: float = 0.0,
        front_drop: float = 0.0,
        fold_amplitude: float = 0.0,
        fold_count: int = 0,
        fold_phase: float = 0.0,
    ) -> list[int]:
        ring: list[int] = []
        for segment in range(segments + 1):
            fraction = segment / segments
            angle = math.tau * fraction
            cosine = math.cos(angle)
            sine = math.sin(angle)
            fold = (
                fold_amplitude
                * math.cos((angle * fold_count) + fold_phase)
                if fold_count > 0
                else 0.0
            )
            normalized_x = radius_x + fold
            front_factor = max(0.0, -sine)
            normalized_y = radius_y + (fold * 0.72)
            coordinate = Vector(
                (
                    center.x + (normalized_x * cosine),
                    center.y + (normalized_y * sine),
                    center.z
                    - (z_shape * abs(cosine))
                    - (front_drop * front_factor),
                )
            )
            ring.append(self.vertex(coordinate, (fraction, v_coordinate), weights))
        return ring

    def connect(self, first: list[int], second: list[int], reverse: bool = False) -> None:
        if len(first) != len(second):
            raise RuntimeError("Garment rings must have matching segment counts")
        for index in range(len(first) - 1):
            face = (
                first[index],
                first[index + 1],
                second[index + 1],
                second[index],
            )
            self.faces.append(tuple(reversed(face)) if reverse else face)


def rig_point(rig: bpy.types.Object, bone_name: str, endpoint: str) -> Vector:
    bone = rig.data.bones[bone_name]
    return Vector(bone.head_local if endpoint == "head" else bone.tail_local)


def bind_authored_garment(
    name: str,
    rig: bpy.types.Object,
    builder: GarmentMeshBuilder,
    garment_material: bpy.types.Material,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}-mesh")
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.materials.append(garment_material)
    mesh.validate(verbose=False)
    mesh.update()

    garment = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(garment)
    garment.parent = rig
    garment.location = (0.0, 0.0, 0.0)
    garment["geometryAuthority"] = "project-authored-fitted-and-parametric-garment-v3"
    garment["measurementAuthority"] = "character-rig-rest-bone-endpoints"
    garment["externalGarmentTopology"] = False
    garment["freeClothSimulation"] = False
    garment["silhouetteAuthority"] = "fitted-bodice-fixed-drape-belted-tunic"

    uv_layer = mesh.uv_layers.new(name="project-authored-woven-uv")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = builder.uvs[loop.vertex_index]

    bone_names = sorted({bone for weights in builder.weights for bone in weights})
    groups = {bone: garment.vertex_groups.new(name=bone) for bone in bone_names}
    for vertex_index, weights in enumerate(builder.weights):
        for bone, weight in weights.items():
            groups[bone].add([vertex_index], weight, "REPLACE")

    armature = garment.modifiers.new(name="project-authored-rig", type="ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    solidify = garment.modifiers.new(name="woven-edge-thickness", type="SOLIDIFY")
    solidify.thickness = 0.004
    solidify.offset = 0.0
    solidify.use_even_offset = True
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return garment


def human_vertex_rig_weights(
    human: bpy.types.Object,
    rig: bpy.types.Object,
    vertex_index: int,
) -> dict[str, float]:
    bone_names = set(rig.data.bones.keys())
    weights: dict[str, float] = {}
    for membership in human.data.vertices[vertex_index].groups:
        group_name = human.vertex_groups[membership.group].name
        if group_name in bone_names and membership.weight > 0.0:
            weights[group_name] = membership.weight
    return weights


def append_fitted_bodice(
    builder: GarmentMeshBuilder,
    human: bpy.types.Object,
    rig: bpy.types.Object,
    scale: float,
    shoulder_half_width: float,
    lower_z: float,
    upper_z: float,
) -> None:
    """Add a deterministic fitted upper tunic from the pinned CC0 body.

    This is not imported garment topology. The project selects a bounded
    bodice-and-sleeve surface from the already rights-clear human base,
    expands it in rest space and copies only the rig weights needed to hold
    authored working poses. The flared skirt remains project-parametric.
    """

    body_group = human.vertex_groups.get("body")
    if body_group is None:
        raise RuntimeError("Pinned human is missing its body vertex group")
    body_group_index = body_group.index

    mask_modifiers = [modifier for modifier in human.modifiers if modifier.type == "MASK"]
    original_mask_visibility = [modifier.show_viewport for modifier in mask_modifiers]
    for modifier in mask_modifiers:
        modifier.show_viewport = False
    bpy.context.view_layer.update()

    evaluated_human = human.evaluated_get(bpy.context.evaluated_depsgraph_get())
    evaluated_mesh = evaluated_human.to_mesh()
    try:
        if len(evaluated_mesh.vertices) != len(human.data.vertices):
            raise RuntimeError("Body evaluation changed topology before garment selection")

        body_membership = [False] * len(human.data.vertices)
        for vertex in human.data.vertices:
            body_membership[vertex.index] = any(
                membership.group == body_group_index and membership.weight > 0.5
                for membership in vertex.groups
            )

        upperarm_segments = []
        for suffix in ("l", "r"):
            start = rig_point(rig, f"upperarm_{suffix}", "head")
            end = start.lerp(rig_point(rig, f"upperarm_{suffix}", "tail"), 0.72)
            upperarm_segments.append((start, end))

        def within_upper_sleeve(point: Vector) -> bool:
            for start, end in upperarm_segments:
                segment = end - start
                denominator = segment.length_squared
                if denominator <= 1e-10:
                    continue
                fraction = max(0.0, min(1.0, (point - start).dot(segment) / denominator))
                closest = start + (segment * fraction)
                if (point - closest).length <= (0.105 * scale):
                    return True
            return False

        selected_faces: list[tuple[int, ...]] = []
        selected_indices: set[int] = set()
        torso_half_width = max(shoulder_half_width * 1.16, 0.218 * scale)
        for polygon in evaluated_mesh.polygons:
            polygon_indices = tuple(polygon.vertices)
            if not all(body_membership[index] for index in polygon_indices):
                continue
            center = sum(
                (Vector(evaluated_mesh.vertices[index].co) for index in polygon_indices),
                Vector((0.0, 0.0, 0.0)),
            ) / len(polygon_indices)
            within_torso = (
                lower_z <= center.z <= upper_z
                and abs(center.x) <= torso_half_width
            )
            if not within_torso and not within_upper_sleeve(center):
                continue
            selected_faces.append(polygon_indices)
            selected_indices.update(polygon_indices)

        if not selected_faces:
            raise RuntimeError("Project-authored bodice selection produced no faces")

        torso_center_y = rig_point(rig, "spine_03", "head").y - (0.010 * scale)
        envelope_bins = 18
        front_envelope: list[float | None] = [None] * envelope_bins
        for original_index in selected_indices:
            point = Vector(evaluated_mesh.vertices[original_index].co)
            if not (
                lower_z <= point.z <= upper_z
                and abs(point.x) <= torso_half_width
                and point.y < torso_center_y
            ):
                continue
            fraction = (point.z - lower_z) / max(0.001, upper_z - lower_z)
            envelope_index = min(envelope_bins - 1, max(0, int(fraction * envelope_bins)))
            previous = front_envelope[envelope_index]
            front_envelope[envelope_index] = (
                point.y if previous is None else min(previous, point.y)
            )
        available_envelopes = [value for value in front_envelope if value is not None]
        if not available_envelopes:
            raise RuntimeError("Could not derive the fitted bodice front envelope")
        for envelope_index, value in enumerate(front_envelope):
            if value is not None:
                continue
            nearest = min(
                (
                    (abs(envelope_index - candidate_index), candidate_value)
                    for candidate_index, candidate_value in enumerate(front_envelope)
                    if candidate_value is not None
                ),
                key=lambda item: item[0],
            )
            front_envelope[envelope_index] = nearest[1]
        smoothed_front_envelope = [
            min(
                float(front_envelope[candidate_index])
                for candidate_index in range(
                    max(0, envelope_index - 1),
                    min(envelope_bins, envelope_index + 2),
                )
            )
            for envelope_index in range(envelope_bins)
        ]

        mapping: dict[int, int] = {}
        clearance = 0.016 * scale
        for original_index in sorted(selected_indices):
            evaluated_vertex = evaluated_mesh.vertices[original_index]
            coordinate = Vector(evaluated_vertex.co)
            normal = Vector(evaluated_vertex.normal)
            # A small deterministic ease creates cloth clearance without
            # erasing the body's silhouette or requiring collision solving.
            coordinate.x *= 1.025
            coordinate.y = torso_center_y + ((coordinate.y - torso_center_y) * 1.035)
            within_bodice = (
                lower_z <= coordinate.z <= upper_z
                and abs(coordinate.x) <= torso_half_width
            )
            front_depth = torso_center_y - coordinate.y
            if within_bodice and front_depth > (0.018 * scale):
                fraction = (coordinate.z - lower_z) / max(0.001, upper_z - lower_z)
                envelope_index = min(
                    envelope_bins - 1,
                    max(0, int(fraction * envelope_bins)),
                )
                front_plane = (
                    smoothed_front_envelope[envelope_index]
                    - (0.030 * scale)
                )
                front_factor = min(
                    1.0,
                    max(
                        0.0,
                        (front_depth - (0.018 * scale)) / (0.055 * scale),
                    ),
                )
                coordinate.y = (
                    coordinate.y * (1.0 - front_factor)
                    + front_plane * front_factor
                )
            coordinate += normal * clearance
            weights = human_vertex_rig_weights(human, rig, original_index)
            if not weights:
                raise RuntimeError(
                    f"Selected garment vertex {original_index} has no rig weights"
                )
            mapping[original_index] = builder.vertex(
                coordinate,
                (
                    0.5 + (coordinate.x / max(0.001, 0.52 * scale)),
                    (coordinate.z - lower_z) / max(0.001, upper_z - lower_z),
                ),
                weights,
            )
        for polygon_indices in selected_faces:
            builder.faces.append(tuple(mapping[index] for index in polygon_indices))
    finally:
        evaluated_human.to_mesh_clear()
        for modifier, visible in zip(
            mask_modifiers,
            original_mask_visibility,
            strict=True,
        ):
            modifier.show_viewport = visible
        bpy.context.view_layer.update()


def authored_tunic(
    character_id: str,
    human: bpy.types.Object,
    rig: bpy.types.Object,
    garment_material: bpy.types.Material,
) -> bpy.types.Object:
    """Build a fitted upper tunic and a fixed-drape knee-length skirt."""

    builder = GarmentMeshBuilder()
    height = max(1.0, rig.dimensions.z)
    scale = height / 1.80
    pelvis = rig_point(rig, "pelvis", "head")
    spine_01 = rig_point(rig, "spine_01", "head")
    neck = rig_point(rig, "neck_01", "head")
    shoulder_left = rig_point(rig, "clavicle_l", "tail")
    shoulder_right = rig_point(rig, "clavicle_r", "tail")
    knee = rig_point(rig, "thigh_l", "tail")
    shoulder_half_width = max(abs(shoulder_left.x), abs(shoulder_right.x))
    segments = 32

    fitted_lower_z = spine_01.z - (0.004 * scale)
    fitted_upper_z = neck.z + (0.024 * scale)
    append_fitted_bodice(
        builder,
        human,
        rig,
        scale,
        shoulder_half_width,
        fitted_lower_z,
        fitted_upper_z,
    )

    # The lower cloth hangs from the cinched waist. It is intentionally
    # authored as fixed drape so the same pose and contact replay exactly.
    waist_ring = builder.horizontal_ring(
        Vector((0.0, pelvis.y - (0.030 * scale), spine_01.z - (0.018 * scale))),
        max(shoulder_half_width * 0.94, 0.178 * scale),
        0.190 * scale,
        0.0,
        {"spine_01": 0.64, "pelvis": 0.36},
        segments=segments,
        fold_amplitude=0.0035 * scale,
        fold_count=10,
    )
    hip_ring = builder.horizontal_ring(
        Vector((0.0, pelvis.y - (0.022 * scale), pelvis.z - (0.042 * scale))),
        max(shoulder_half_width * 1.08, 0.202 * scale),
        0.198 * scale,
        0.32,
        {"spine_01": 0.28, "pelvis": 0.72},
        segments=segments,
        fold_amplitude=0.0045 * scale,
        fold_count=10,
    )
    skirt_ring = builder.horizontal_ring(
        Vector((0.0, pelvis.y - (0.018 * scale), pelvis.z - (0.185 * scale))),
        max(shoulder_half_width * 1.18, 0.220 * scale),
        0.202 * scale,
        0.66,
        {"pelvis": 1.0},
        segments=segments,
        fold_amplitude=0.0065 * scale,
        fold_count=10,
    )
    hem_ring = builder.horizontal_ring(
        Vector((0.0, pelvis.y - (0.015 * scale), knee.z + (0.060 * scale))),
        max(shoulder_half_width * 1.34, 0.248 * scale),
        0.218 * scale,
        1.0,
        {"pelvis": 1.0},
        segments=segments,
        z_shape=0.012 * scale,
        front_drop=0.006 * scale,
        fold_amplitude=0.010 * scale,
        fold_count=10,
    )
    builder.connect(waist_ring, hip_ring)
    builder.connect(hip_ring, skirt_ring)
    builder.connect(skirt_ring, hem_ring)

    return bind_authored_garment(
        f"hero-{character_id}-woven-garment",
        rig,
        builder,
        garment_material,
    )


def authored_belt(
    character_id: str,
    rig: bpy.types.Object,
    garment_material: bpy.types.Material,
) -> bpy.types.Object:
    """Build the deterministic cinch that makes the waist and skirt legible."""

    builder = GarmentMeshBuilder()
    height = max(1.0, rig.dimensions.z)
    scale = height / 1.80
    pelvis = rig_point(rig, "pelvis", "head")
    spine_01 = rig_point(rig, "spine_01", "head")
    shoulder_left = rig_point(rig, "clavicle_l", "tail")
    shoulder_right = rig_point(rig, "clavicle_r", "tail")
    shoulder_half_width = max(abs(shoulder_left.x), abs(shoulder_right.x))
    radius_x = max(shoulder_half_width * 0.96, 0.182 * scale)
    center = Vector((0.0, pelvis.y - (0.030 * scale), spine_01.z - (0.018 * scale)))
    top_ring = builder.horizontal_ring(
        Vector((center.x, center.y, center.z + (0.030 * scale))),
        radius_x,
        0.204 * scale,
        0.0,
        {"spine_01": 0.62, "pelvis": 0.38},
        segments=32,
    )
    bottom_ring = builder.horizontal_ring(
        Vector((center.x, center.y, center.z - (0.030 * scale))),
        radius_x,
        0.204 * scale,
        1.0,
        {"spine_01": 0.50, "pelvis": 0.50},
        segments=32,
    )
    builder.connect(top_ring, bottom_ring)

    return bind_authored_garment(
        f"hero-{character_id}-woven-belt",
        rig,
        builder,
        garment_material,
    )


def rotate_bone(
    rig: bpy.types.Object,
    bone_name: str,
    degrees_xyz: tuple[float, float, float],
) -> None:
    bone = rig.pose.bones.get(bone_name)
    if bone is None:
        return
    bone.rotation_mode = "XYZ"
    bone.rotation_euler = Euler(tuple(math.radians(value) for value in degrees_xyz))


def working_pose(rig: bpy.types.Object, variant: int) -> None:
    # Small, grounded variations keep the workers readable in portrait framing.
    if variant == 0:
        rotate_bone(rig, "upperarm_l", (8, -28, -54))
        rotate_bone(rig, "lowerarm_l", (0, -18, -72))
        rotate_bone(rig, "upperarm_r", (-6, 24, 50))
        rotate_bone(rig, "lowerarm_r", (0, 18, 68))
    elif variant == 1:
        rotate_bone(rig, "upperarm_l", (2, -18, -42))
        rotate_bone(rig, "lowerarm_l", (0, -10, -88))
        rotate_bone(rig, "upperarm_r", (-2, 18, 46))
        rotate_bone(rig, "lowerarm_r", (0, 8, 82))
    else:
        rotate_bone(rig, "upperarm_l", (4, -15, -32))
        rotate_bone(rig, "lowerarm_l", (0, -12, -58))
        rotate_bone(rig, "upperarm_r", (-4, 15, 34))
        rotate_bone(rig, "lowerarm_r", (0, 12, 62))


def author_hair_clearance(
    hair: bpy.types.Object,
    rig: bpy.types.Object,
) -> None:
    """Offset the pinned hair shell deterministically away from skin.

    MPFB supplies the rights-clear fitted topology and weights. This small
    project-authored rest-space clearance keeps the hairline and long braid
    from disappearing into the posed head or tunic without introducing a
    runtime collision or hair simulation.
    """

    head = rig.data.bones["head"]
    head_center = (Vector(head.head_local) + Vector(head.tail_local)) * 0.5
    character_scale = max(1.0, rig.dimensions.z) / 1.80
    radial_clearance = 0.0045 * character_scale
    for vertex in hair.data.vertices:
        radial = Vector(
            (
                vertex.co.x - head_center.x,
                vertex.co.y - head_center.y,
                0.0,
            )
        )
        if radial.length_squared > 1e-10:
            vertex.co += radial.normalized() * radial_clearance
    hair.data.update()
    hair["geometryAuthority"] = "pinned-cc0-hair-with-project-clearance-v1"
    hair["runtimeHairSimulation"] = False


def create_character(
    character_id: str,
    phenotype: dict,
    pose_variant: int,
    textures: dict[str, Path],
) -> bpy.types.Object:
    human = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=phenotype,
    )
    human.name = f"hero-{character_id}-body"
    human.data.name = f"hero-{character_id}-body-mesh"
    human.data.materials.append(
        textured_material(
            f"skin-{character_id}",
            textures["skin"],
            0.47,
            skin=True,
        )
    )
    rig = HumanService.add_builtin_rig(human, "game_engine")
    rig.name = f"hero-{character_id}-rig"
    rig.location = (0.0, 0.0, 0.0)

    cloth = textured_material(
        f"cloth-{character_id}",
        textures["clothBase"],
        0.88,
        textures["clothNormal"],
    )
    authored_tunic(character_id, human, rig, cloth)
    authored_belt(
        character_id,
        rig,
        textured_material(
            f"cloth-dark-{character_id}",
            textures["trouserBase"],
            0.92,
            textures["trouserNormal"],
        ),
    )

    assets_root = Path(os.environ["CHAPTER01_MAKEHUMAN_ASSETS_ROOT"])
    hair_asset = {
        "adult-a": "short02",
        "adult-b": "braid01",
        "youth": "short04",
    }[character_id]
    hair_path = assets_root / f"base/hair/{hair_asset}/{hair_asset}.mhclo"
    hair = HumanService.add_mhclo_asset(
        str(hair_path),
        human,
        asset_type="Hair",
        subdiv_levels=1,
        material_type="NONE",
        set_up_rigging=True,
        interpolate_weights=True,
        import_subrig=True,
        import_weights=True,
    )
    hair.name = f"hero-{character_id}-hair"
    hair.data.materials.clear()
    hair.data.materials.append(
        material(f"hair-{character_id}", (0.028, 0.016, 0.008, 1.0), 0.82)
    )
    author_hair_clearance(hair, rig)

    working_pose(rig, pose_variant)

    root = bpy.data.objects.new(f"hero-{character_id}", None)
    bpy.context.collection.objects.link(root)
    root.location = (0.0, 0.0, 0.0)
    rig.parent = root
    return root


def place_preview_roots(roots: list[bpy.types.Object]) -> None:
    preview_positions = (
        (-0.62, 0.10, 0.0),
        (0.00, 0.03, 0.0),
        (0.55, -0.03, 0.0),
    )
    for root, position in zip(roots, preview_positions, strict=True):
        anchor = bpy.data.objects.new(f"preview-only-placement-{root.name}", None)
        bpy.context.collection.objects.link(anchor)
        anchor.location = position
        root.parent = anchor
        root.location = (0.0, 0.0, 0.0)


def add_preview_stage() -> None:
    ground_material = material("preview-ground", (0.055, 0.045, 0.032, 1), 0.94)
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
    ground = bpy.context.object
    ground.name = "preview-ground"
    ground.data.materials.append(ground_material)

    world = bpy.context.scene.world or bpy.data.worlds.new("chapter01-preview-world")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.012, 0.018, 0.023, 1)
    background.inputs["Strength"].default_value = 0.22

    bpy.ops.object.light_add(type="AREA", location=(-3.8, -4.2, 5.8))
    key = bpy.context.object
    key.name = "preview-warm-key"
    key.data.energy = 1_050
    key.data.shape = "DISK"
    key.data.size = 4.5
    key.data.color = (1.0, 0.66, 0.39)
    key.rotation_euler = Euler((math.radians(28), 0, math.radians(-34)))

    bpy.ops.object.light_add(type="AREA", location=(4.0, 1.5, 3.5))
    fill = bpy.context.object
    fill.name = "preview-cool-fill"
    fill.data.energy = 780
    fill.data.size = 5.0
    fill.data.color = (0.29, 0.46, 0.63)
    fill.rotation_euler = Euler((math.radians(64), 0, math.radians(140)))

    bpy.ops.object.camera_add(location=(0, -4.60, 1.48))
    camera = bpy.context.object
    camera.name = "preview-camera"
    direction = Vector((0, 0, 0.92)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 60
    bpy.context.scene.camera = camera


def export_runtime_usd(output: Path) -> None:
    for scene_object in bpy.context.scene.objects:
        scene_object.select_set(scene_object.name.startswith("hero-"))
    bpy.context.view_layer.objects.active = next(
        scene_object
        for scene_object in bpy.context.scene.objects
        if scene_object.name == "hero-adult-a"
    )

    # Runtime USD contains character hierarchies only. Preview staging is
    # deliberately created after this export and can never leak into USDZ.
    bpy.ops.wm.usd_export(
        filepath=str(output / "chapter01-hero-character-library.usdc"),
        selected_objects_only=True,
        export_animation=True,
        export_materials=True,
        export_lights=False,
        export_cameras=False,
        relative_paths=True,
    )
    canonicalize_runtime_usd(output / "chapter01-hero-character-library.usdc")


def canonicalize_runtime_usd(path: Path) -> None:
    """Fix namespace and property order before the canonical binary export."""

    stage = Usd.Stage.Open(str(path))
    if stage is None:
        raise RuntimeError(f"Could not reopen exported USD: {path}")
    prims = [stage.GetPseudoRoot()] + list(stage.TraverseAll())
    for prim in prims:
        child_names = sorted(str(name) for name in prim.GetAllChildrenNames())
        if child_names:
            prim.SetChildrenReorder(child_names)
        property_names = sorted(prop.GetName() for prop in prim.GetAuthoredProperties())
        if property_names:
            prim.SetPropertyOrder(property_names)

    canonical_path = path.with_name(f".{path.stem}.canonical.usdc")
    # Flattening authors a new layer in composed namespace order. Exporting
    # the original root layer would preserve Blender's nondeterministic spec
    # insertion order even with explicit reorder metadata.
    canonical_layer = stage.Flatten()
    canonical_layer.documentation = (
        "Chapter 01 hero-character library; canonical composed runtime stage."
    )
    canonical_stage = Usd.Stage.Open(canonical_layer)
    for prim in canonical_stage.TraverseAll():
        for attribute in prim.GetAttributes():
            value = attribute.Get()
            if isinstance(value, Sdf.AssetPath) and value.path.endswith(".png"):
                texture_name = Path(value.path).name
                attribute.Set(Sdf.AssetPath(f"./textures/{texture_name}"))
    # `reorder` metadata makes composition deterministic but does not change
    # the binary layer's spec insertion order. Apply explicit namespace edits
    # so the canonical USDC bytes no longer depend on Blender datablock order.
    namespace_edits = Sdf.BatchNamespaceEdit()

    def add_namespace_edits(prim_spec: Sdf.PrimSpec) -> None:
        children = sorted(prim_spec.nameChildren, key=lambda child: child.name)
        for index, child in enumerate(children):
            namespace_edits.Add(Sdf.NamespaceEdit.Reorder(child.path, index))
            add_namespace_edits(child)
        properties = sorted(prim_spec.properties, key=lambda prop: prop.name)
        for index, prop in enumerate(properties):
            namespace_edits.Add(Sdf.NamespaceEdit.Reorder(prop.path, index))

    add_namespace_edits(canonical_layer.pseudoRoot)
    if not canonical_layer.Apply(namespace_edits):
        raise RuntimeError("Could not apply canonical USD namespace order")
    if not canonical_stage.GetRootLayer().Export(
        str(canonical_path), args={"format": "usdc"}
    ):
        raise RuntimeError(f"Could not write canonical USD: {canonical_path}")
    os.replace(canonical_path, path)
    pin_timestamp(path)


def save_preview_source(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    blend_path = output / "chapter01-hero-character-library.blend"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 1_280
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output / "chapter01-hero-character-preview.png")
    scene.render.film_transparent = False
    bpy.ops.render.render(write_still=True)


def main() -> None:
    output = Path(
        sys.argv[sys.argv.index("--") + 1]
        if "--" in sys.argv
        else "native/production/3d/chapter01/characters/outputs"
    ).resolve()
    clear_scene()
    output.mkdir(parents=True, exist_ok=True)
    textures = prepare_material_textures(output)
    roots = [create_character(
        "adult-a",
        {
            "gender": 0.82,
            "age": 0.58,
            "muscle": 0.62,
            "weight": 0.48,
            "proportions": 0.54,
            "height": 0.57,
            "cupsize": 0.20,
            "firmness": 0.50,
            "race": {"asian": 0.12, "caucasian": 0.68, "african": 0.20},
        },
        0,
        textures["adult-a"],
    )]
    roots.append(create_character(
        "adult-b",
        {
            "gender": 0.16,
            "age": 0.52,
            "muscle": 0.46,
            "weight": 0.52,
            "proportions": 0.52,
            "height": 0.49,
            "cupsize": 0.46,
            "firmness": 0.52,
            "race": {"asian": 0.16, "caucasian": 0.66, "african": 0.18},
        },
        1,
        textures["adult-b"],
    ))
    roots.append(create_character(
        "youth",
        {
            "gender": 0.46,
            "age": 0.20,
            "muscle": 0.36,
            "weight": 0.42,
            "proportions": 0.46,
            "height": 0.27,
            "cupsize": 0.20,
            "firmness": 0.58,
            "race": {"asian": 0.14, "caucasian": 0.68, "african": 0.18},
        },
        2,
        textures["youth"],
    ))
    export_runtime_usd(output)
    place_preview_roots(roots)
    add_preview_stage()
    save_preview_source(output)


if __name__ == "__main__":
    main()
