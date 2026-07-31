"""Build the rights-clear Chapter 01 cattle rig library.

The source of authority is this deterministic Blender Python file. Geometry,
UVs, hide textures, materials, skeletons and motion clips are authored here;
the build reads no external animal asset. The runtime roots remain at local
origin so a world-cell generator can clone and place them without baking scene
coordinates into the library.
"""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path
from typing import Iterable, Sequence

import bpy
from mathutils import Euler, Vector
from pxr import Sdf, Usd


FIXED_FILE_TIMESTAMP = 315_532_800
FPS = 24
ROOT_NAMES = ("cattle-adult", "cattle-young")


def pin_timestamp(path: Path) -> None:
    os.utime(path, (FIXED_FILE_TIMESTAMP, FIXED_FILE_TIMESTAMP))


def clear_scene() -> None:
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(collection):
            collection.remove(datablock)


def write_image(
    path: Path,
    name: str,
    width: int,
    height: int,
    pixels: Sequence[float],
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


def procedural_hide_textures(output: Path) -> dict[str, Path]:
    """Write restrained, seamless project-authored hide maps."""

    texture_directory = output / "textures"
    texture_directory.mkdir(parents=True, exist_ok=True)
    size = 384
    palettes = {
        "adult": (0.245, 0.112, 0.040),
        "young": (0.385, 0.205, 0.082),
    }
    paths: dict[str, Path] = {}

    height_field: list[float] = [0.0] * (size * size)
    for y in range(size):
        for x in range(size):
            # Short vertical fibres with several incommensurate, deterministic
            # frequencies. No random generator or external source is used.
            fibre = (
                math.sin((x * 0.47) + (y * 2.31)) * 0.46
                + math.sin((x * 1.17) - (y * 4.07)) * 0.24
                + math.cos((x * 0.13) + (y * 0.29)) * 0.18
                + math.sin((x * 2.41) + (y * 7.19)) * 0.12
            )
            broad = math.sin(x * 0.041) * math.cos(y * 0.027)
            height_field[(y * size) + x] = 0.5 + (fibre * 0.085) + (broad * 0.055)

    for animal_id, base in palettes.items():
        pixels: list[float] = []
        for y in range(size):
            for x in range(size):
                h = height_field[(y * size) + x]
                dorsal = 0.93 + (0.05 * math.cos((x / size) * math.tau))
                irregular = 0.965 + ((h - 0.5) * 0.18)
                pixels.extend(
                    (
                        max(0.0, min(1.0, base[0] * dorsal * irregular)),
                        max(0.0, min(1.0, base[1] * dorsal * irregular)),
                        max(0.0, min(1.0, base[2] * dorsal * irregular)),
                        1.0,
                    )
                )
        path = texture_directory / f"cattle-{animal_id}-hide-basecolor.png"
        write_image(path, f"cattle-{animal_id}-hide-basecolor", size, size, pixels, "sRGB")
        paths[f"{animal_id}Base"] = path

    normal_pixels: list[float] = []
    for y in range(size):
        for x in range(size):
            left = height_field[(y * size) + ((x - 1) % size)]
            right = height_field[(y * size) + ((x + 1) % size)]
            down = height_field[(((y - 1) % size) * size) + x]
            up = height_field[(((y + 1) % size) * size) + x]
            nx = (left - right) * 1.9
            ny = (down - up) * 1.9
            nz = 1.0
            length = math.sqrt((nx * nx) + (ny * ny) + (nz * nz))
            normal_pixels.extend(
                (
                    ((nx / length) * 0.5) + 0.5,
                    ((ny / length) * 0.5) + 0.5,
                    ((nz / length) * 0.5) + 0.5,
                    1.0,
                )
            )
    normal_path = texture_directory / "cattle-hide-normal.png"
    write_image(normal_path, "cattle-hide-normal", size, size, normal_pixels, "Non-Color")
    paths["normal"] = normal_path
    return paths


def solid_material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float,
    metallic: float = 0.0,
) -> bpy.types.Material:
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return result


def hide_material(name: str, base_path: Path, normal_path: Path) -> bpy.types.Material:
    result = solid_material(name, (0.32, 0.15, 0.055, 1.0), 0.83)
    nodes = result.node_tree.nodes
    links = result.node_tree.links
    shader = nodes.get("Principled BSDF")

    base = nodes.new("ShaderNodeTexImage")
    base.name = f"{name}-basecolor"
    base.image = bpy.data.images.load(str(base_path), check_existing=False)
    base.image.colorspace_settings.name = "sRGB"
    base.interpolation = "Linear"
    links.new(base.outputs["Color"], shader.inputs["Base Color"])

    normal = nodes.new("ShaderNodeTexImage")
    normal.name = f"{name}-normal"
    normal.image = bpy.data.images.load(str(normal_path), check_existing=False)
    normal.image.colorspace_settings.name = "Non-Color"
    normal.interpolation = "Linear"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.24
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
    return result


def create_armature(animal_id: str, scale: float) -> bpy.types.Object:
    armature_data = bpy.data.armatures.new(f"cattle-{animal_id}-skeleton")
    rig = bpy.data.objects.new(f"cattle-{animal_id}-rig", armature_data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    coordinates = {
        "root": ((0.0, 0.0, 0.04), (0.0, 0.0, 0.26), None),
        "pelvis": ((-0.63, 0.0, 1.08), (-0.28, 0.0, 1.17), "root"),
        "spine": ((-0.30, 0.0, 1.17), (0.47, 0.0, 1.27), "pelvis"),
        "neck": ((0.43, 0.0, 1.27), (0.96, 0.0, 1.44), "spine"),
        "head": ((0.93, 0.0, 1.44), (1.34, 0.0, 1.28), "neck"),
        "tail_base": ((-0.87, 0.0, 1.26), (-1.12, 0.0, 1.04), "pelvis"),
        "tail_tip": ((-1.12, 0.0, 1.04), (-1.17, 0.0, 0.66), "tail_base"),
        "front_upper_l": ((0.49, -0.29, 1.08), (0.47, -0.26, 0.64), "spine"),
        "front_lower_l": ((0.47, -0.26, 0.64), (0.50, -0.24, 0.15), "front_upper_l"),
        "front_hoof_l": ((0.50, -0.24, 0.15), (0.62, -0.24, 0.06), "front_lower_l"),
        "front_upper_r": ((0.49, 0.29, 1.08), (0.47, 0.26, 0.64), "spine"),
        "front_lower_r": ((0.47, 0.26, 0.64), (0.50, 0.24, 0.15), "front_upper_r"),
        "front_hoof_r": ((0.50, 0.24, 0.15), (0.62, 0.24, 0.06), "front_lower_r"),
        "hind_upper_l": ((-0.61, -0.32, 1.05), (-0.67, -0.29, 0.63), "pelvis"),
        "hind_lower_l": ((-0.67, -0.29, 0.63), (-0.61, -0.26, 0.15), "hind_upper_l"),
        "hind_hoof_l": ((-0.61, -0.26, 0.15), (-0.49, -0.26, 0.06), "hind_lower_l"),
        "hind_upper_r": ((-0.61, 0.32, 1.05), (-0.67, 0.29, 0.63), "pelvis"),
        "hind_lower_r": ((-0.67, 0.29, 0.63), (-0.61, 0.26, 0.15), "hind_upper_r"),
        "hind_hoof_r": ((-0.61, 0.26, 0.15), (-0.49, 0.26, 0.06), "hind_lower_r"),
    }
    bones: dict[str, bpy.types.EditBone] = {}
    for name, (head, tail, parent_name) in coordinates.items():
        bone = armature_data.edit_bones.new(name)
        bone.head = Vector(tuple(value * scale for value in head))
        bone.tail = Vector(tuple(value * scale for value in tail))
        if parent_name is not None:
            bone.parent = bones[parent_name]
            bone.use_connect = False
        bones[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    rig.show_in_front = False
    return rig


def bind_mesh(
    obj: bpy.types.Object,
    rig: bpy.types.Object,
    vertex_weights: Sequence[dict[str, float]],
) -> None:
    if len(vertex_weights) != len(obj.data.vertices):
        raise ValueError(f"Weight count mismatch for {obj.name}")
    groups: dict[str, bpy.types.VertexGroup] = {}
    for vertex_index, weights in enumerate(vertex_weights):
        total = sum(weights.values())
        if total <= 0:
            raise ValueError(f"Unweighted vertex {vertex_index} in {obj.name}")
        for bone_name, value in weights.items():
            group = groups.get(bone_name)
            if group is None:
                group = obj.vertex_groups.new(name=bone_name)
                groups[bone_name] = group
            group.add([vertex_index], value / total, "REPLACE")
    obj.parent = rig
    modifier = obj.modifiers.new("cattle-skeleton-deform", "ARMATURE")
    modifier.object = rig


def smoothed_sections(
    sections: Sequence[tuple[float, float, float, float, float, dict[str, float]]],
    subdivisions: int,
) -> list[tuple[float, float, float, float, float, dict[str, float]]]:
    if subdivisions <= 1:
        return list(sections)

    def catmull(a: float, b: float, c: float, d: float, t: float) -> float:
        return 0.5 * (
            (2.0 * b)
            + ((-a + c) * t)
            + ((2.0 * a - 5.0 * b + 4.0 * c - d) * t * t)
            + ((-a + 3.0 * b - 3.0 * c + d) * t * t * t)
        )

    result: list[tuple[float, float, float, float, float, dict[str, float]]] = []
    for index in range(len(sections) - 1):
        p0 = sections[max(0, index - 1)]
        p1 = sections[index]
        p2 = sections[index + 1]
        p3 = sections[min(len(sections) - 1, index + 2)]
        for step in range(subdivisions):
            t = step / subdivisions
            geometry = [catmull(p0[channel], p1[channel], p2[channel], p3[channel], t) for channel in range(5)]
            geometry[3] = max(0.002, geometry[3])
            geometry[4] = max(0.002, geometry[4])
            keys = sorted(set(p1[5]) | set(p2[5]))
            weights = {
                key: (p1[5].get(key, 0.0) * (1.0 - t)) + (p2[5].get(key, 0.0) * t)
                for key in keys
            }
            result.append((*geometry, weights))
    result.append(sections[-1])
    return result


def loft_mesh(
    name: str,
    sections: Sequence[tuple[float, float, float, float, float, dict[str, float]]],
    sides: int,
    material: bpy.types.Material,
    rig: bpy.types.Object,
    irregularity: float = 0.0,
    cap_start: bool = True,
    cap_end: bool = True,
    longitudinal_subdivisions: int = 1,
) -> bpy.types.Object:
    sections = smoothed_sections(sections, longitudinal_subdivisions)
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    weights: list[dict[str, float]] = []
    faces: list[tuple[int, ...]] = []
    section_count = len(sections)
    for section_index, (x, cy, cz, radius_y, radius_z, section_weights) in enumerate(sections):
        for side in range(sides + 1):
            angle = (side / sides) * math.tau
            surface = 1.0 + irregularity * math.sin((side * 2.19) + (section_index * 1.37))
            vertices.append(
                (
                    x,
                    cy + (math.cos(angle) * radius_y * surface),
                    cz + (math.sin(angle) * radius_z * surface),
                )
            )
            uvs.append((side / sides, section_index / max(1, section_count - 1)))
            weights.append(section_weights)
    stride = sides + 1
    for section_index in range(section_count - 1):
        for side in range(sides):
            a = (section_index * stride) + side
            b = a + 1
            c = ((section_index + 1) * stride) + side + 1
            d = c - 1
            faces.append((a, b, c, d))

    first = sections[0]
    if cap_start:
        start_center = len(vertices)
        vertices.append((first[0], first[1], first[2]))
        uvs.append((0.5, 0.0))
        weights.append(first[5])
        for side in range(sides):
            faces.append((start_center, side + 1, side))
    last = sections[-1]
    if cap_end:
        end_center = len(vertices)
        vertices.append((last[0], last[1], last[2]))
        uvs.append((0.5, 1.0))
        weights.append(last[5])
        last_ring = (section_count - 1) * stride
        for side in range(sides):
            faces.append((end_center, last_ring + side, last_ring + side + 1))

    mesh = bpy.data.meshes.new(f"{name}-mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bind_mesh(obj, rig, weights)
    return obj


def ellipsoid(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    rig: bpy.types.Object,
    bone: str,
    segments: int,
    rings: int,
) -> bpy.types.Object:
    # Blender's primitive operator can reorder pole triangles across clean
    # headless processes. Author the topology directly so canonical geometry
    # bytes do not depend on a BMesh hash iteration order.
    cx, cy, cz = location
    sx, sy, sz = scale
    vertices: list[tuple[float, float, float]] = [(cx, cy, cz - sz)]
    uvs: list[tuple[float, float]] = [(0.5, 0.0)]
    faces: list[tuple[int, ...]] = []
    stride = segments + 1
    for ring in range(1, rings):
        phi = (-math.pi * 0.5) + (math.pi * ring / rings)
        radial = math.cos(phi)
        for side in range(segments + 1):
            theta = (side / segments) * math.tau
            vertices.append(
                (
                    cx + (math.cos(theta) * radial * sx),
                    cy + (math.sin(theta) * radial * sy),
                    cz + (math.sin(phi) * sz),
                )
            )
            uvs.append((side / segments, ring / rings))
    top_index = len(vertices)
    vertices.append((cx, cy, cz + sz))
    uvs.append((0.5, 1.0))
    first_ring = 1
    for side in range(segments):
        faces.append((0, first_ring + side + 1, first_ring + side))
    for ring in range(rings - 2):
        first = 1 + (ring * stride)
        second = first + stride
        for side in range(segments):
            faces.append((first + side, first + side + 1, second + side + 1, second + side))
    last_ring = 1 + ((rings - 2) * stride)
    for side in range(segments):
        faces.append((last_ring + side, last_ring + side + 1, top_index))

    mesh = bpy.data.meshes.new(f"{name}-mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bind_mesh(obj, rig, [{bone: 1.0} for _ in obj.data.vertices])
    return obj


def oriented_tube(
    name: str,
    points: Sequence[tuple[float, float, float]],
    radii: Sequence[float],
    material: bpy.types.Material,
    rig: bpy.types.Object,
    bone_weights: Sequence[dict[str, float]],
    sides: int,
) -> bpy.types.Object:
    if len(points) != len(radii) or len(points) != len(bone_weights):
        raise ValueError("Tube sections must match")
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    weights: list[dict[str, float]] = []
    faces: list[tuple[int, ...]] = []
    for index, point in enumerate(points):
        direction = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        direction.normalize()
        reference = Vector((0.0, 0.0, 1.0))
        if abs(direction.dot(reference)) > 0.9:
            reference = Vector((0.0, 1.0, 0.0))
        side_a = direction.cross(reference).normalized()
        side_b = direction.cross(side_a).normalized()
        for side in range(sides + 1):
            angle = (side / sides) * math.tau
            offset = (side_a * math.cos(angle) + side_b * math.sin(angle)) * radii[index]
            position = Vector(point) + offset
            vertices.append(tuple(position))
            uvs.append((side / sides, index / max(1, len(points) - 1)))
            weights.append(bone_weights[index])
    stride = sides + 1
    for section in range(len(points) - 1):
        for side in range(sides):
            a = section * stride + side
            faces.append((a, a + 1, a + stride + 1, a + stride))
    mesh = bpy.data.meshes.new(f"{name}-mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bind_mesh(obj, rig, weights)
    return obj


def leaf_mesh(
    name: str,
    center: tuple[float, float, float],
    length: float,
    width: float,
    side_sign: float,
    material: bpy.types.Material,
    rig: bpy.types.Object,
    bone: str,
) -> bpy.types.Object:
    cx, cy, cz = center
    vertices = [
        (cx, cy, cz),
        (cx - length * 0.25, cy + side_sign * width, cz + length * 0.08),
        (cx - length, cy + side_sign * width * 0.18, cz - length * 0.08),
        (cx - length * 0.25, cy + side_sign * width * 0.22, cz - length * 0.18),
    ]
    mesh = bpy.data.meshes.new(f"{name}-mesh")
    mesh.from_pydata(vertices, [], [(0, 1, 2, 3), (3, 2, 1, 0)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bind_mesh(obj, rig, [{bone: 1.0} for _ in obj.data.vertices])
    return obj


def hoof_claw(
    name: str,
    center: tuple[float, float, float],
    length: float,
    width: float,
    height: float,
    material: bpy.types.Material,
    rig: bpy.types.Object,
    bone: str,
) -> bpy.types.Object:
    cx, cy, cz = center
    back = cx - (length * 0.42)
    front = cx + (length * 0.58)
    vertices = [
        (back, cy - width * 0.5, cz - height * 0.5),
        (back, cy + width * 0.5, cz - height * 0.5),
        (back, cy - width * 0.5, cz + height * 0.5),
        (back, cy + width * 0.5, cz + height * 0.5),
        (front, cy - width * 0.38, cz - height * 0.42),
        (front, cy + width * 0.38, cz - height * 0.42),
        (front, cy - width * 0.28, cz + height * 0.24),
        (front, cy + width * 0.28, cz + height * 0.24),
    ]
    faces = [
        (0, 4, 5, 1),
        (2, 3, 7, 6),
        (0, 2, 6, 4),
        (1, 5, 7, 3),
        (4, 6, 7, 5),
        (0, 1, 3, 2),
    ]
    mesh = bpy.data.meshes.new(f"{name}-mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bind_mesh(obj, rig, [{bone: 1.0} for _ in obj.data.vertices])
    return obj


def create_leg(
    animal_id: str,
    suffix: str,
    scale: float,
    hide: bpy.types.Material,
    hoof: bpy.types.Material,
    rig: bpy.types.Object,
    sides: int,
) -> None:
    front = suffix.startswith("front")
    left = suffix.endswith("l")
    y_sign = -1.0 if left else 1.0
    hip_x = 0.49 if front else -0.61
    hip_y = (0.29 if front else 0.32) * y_sign
    knee_x = 0.47 if front else -0.67
    knee_y = (0.26 if front else 0.29) * y_sign
    ankle_x = 0.50 if front else -0.61
    ankle_y = (0.24 if front else 0.26) * y_sign
    bone_prefix = "front" if front else "hind"
    upper = f"{bone_prefix}_upper_{'l' if left else 'r'}"
    lower = f"{bone_prefix}_lower_{'l' if left else 'r'}"
    hoof_bone = f"{bone_prefix}_hoof_{'l' if left else 'r'}"
    points = [
        (hip_x * scale, hip_y * scale, 1.08 * scale),
        (((hip_x + knee_x) * 0.5) * scale, ((hip_y + knee_y) * 0.5) * scale, 0.83 * scale),
        (knee_x * scale, knee_y * scale, 0.62 * scale),
        (((knee_x + ankle_x) * 0.5) * scale, ((knee_y + ankle_y) * 0.5) * scale, 0.38 * scale),
        (ankle_x * scale, ankle_y * scale, 0.14 * scale),
    ]
    radii = [0.145, 0.125, 0.084, 0.063, 0.048]
    weights = [
        {upper: 1.0},
        {upper: 1.0},
        {upper: 0.45, lower: 0.55},
        {lower: 1.0},
        {lower: 0.35, hoof_bone: 0.65},
    ]
    oriented_tube(
        f"cattle-{animal_id}-{suffix}-leg",
        points,
        [radius * scale for radius in radii],
        hide,
        rig,
        weights,
        sides,
    )
    ellipsoid(
        f"cattle-{animal_id}-{suffix}-upper-muscle",
        (
            ((hip_x * 0.72) + (knee_x * 0.28)) * scale,
            ((hip_y * 0.72) + (knee_y * 0.28)) * scale,
            0.94 * scale,
        ),
        (0.145 * scale, 0.135 * scale, 0.235 * scale),
        hide,
        rig,
        upper,
        max(12, sides),
        max(6, sides // 2),
    )
    ellipsoid(
        f"cattle-{animal_id}-{suffix}-joint",
        (knee_x * scale, knee_y * scale, 0.62 * scale),
        (0.095 * scale, 0.085 * scale, 0.105 * scale),
        hide,
        rig,
        lower,
        max(10, sides),
        max(6, sides // 2),
    )
    # Paired tapered claws retain the cattle silhouette at close range.
    for claw_index, lateral in enumerate((-0.034, 0.034)):
        hoof_claw(
            f"cattle-{animal_id}-{suffix}-hoof-{claw_index}",
            ((ankle_x + 0.050) * scale, (ankle_y + lateral) * scale, 0.073 * scale),
            0.22 * scale,
            0.060 * scale,
            0.080 * scale,
            hoof,
            rig,
            hoof_bone,
        )


def create_animal(
    animal_id: str,
    scale: float,
    lod: int,
    hide: bpy.types.Material,
    materials: dict[str, bpy.types.Material],
) -> tuple[bpy.types.Object, bpy.types.Object]:
    sides = 30 if lod == 0 else 16
    sphere_segments = 28 if lod == 0 else 16
    sphere_rings = 16 if lod == 0 else 8
    rig = create_armature(animal_id, scale)
    root = bpy.data.objects.new(f"cattle-{animal_id}", None)
    bpy.context.collection.objects.link(root)
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.scale = (1.0, 1.0, 1.0)
    rig.parent = root
    root["runtime_name"] = f"cattle-{animal_id}"
    root["semantic_role"] = "domestic-cattle-rig"
    root["quality_classification"] = "ANIMAL_RIG_CANDIDATE"
    root["final_art_gate"] = "OPEN"
    root["lod"] = lod

    if animal_id == "adult":
        root["clip_contract"] = json.dumps(
            {
                "herd-walk": [1, 33],
                "barrier-weight-shift": [40, 56],
                "rest": [60, 64],
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    else:
        root["clip_contract"] = json.dumps(
            {
                "boat-brace": [1, 32],
                "boat-weight-shift": [40, 56],
                "rest": [60, 64],
            },
            sort_keys=True,
            separators=(",", ":"),
        )

    head_scale = 1.08 if animal_id == "young" else 1.0
    main_sections = [
        (-1.04, 0.0, 1.11, 0.18, 0.27, {"pelvis": 1.0}),
        (-0.92, 0.0, 1.12, 0.35, 0.40, {"pelvis": 1.0}),
        (-0.67, 0.0, 1.15, 0.45, 0.46, {"pelvis": 0.90, "spine": 0.10}),
        (-0.25, 0.0, 1.18, 0.47, 0.47, {"pelvis": 0.35, "spine": 0.65}),
        (0.18, 0.0, 1.22, 0.46, 0.48, {"spine": 1.0}),
        (0.47, 0.0, 1.27, 0.41, 0.46, {"spine": 0.78, "neck": 0.22}),
        (0.69, 0.0, 1.34, 0.33, 0.41, {"spine": 0.28, "neck": 0.72}),
        (0.87, 0.0, 1.42, 0.26, 0.34, {"neck": 0.82, "head": 0.18}),
        (1.02, 0.0, 1.47, 0.22 * head_scale, 0.27 * head_scale, {"neck": 0.38, "head": 0.62}),
        (1.18, 0.0, 1.43, 0.245 * head_scale, 0.30 * head_scale, {"head": 1.0}),
        (1.35, 0.0, 1.32, 0.22 * head_scale, 0.27 * head_scale, {"head": 1.0}),
        (1.49, 0.0, 1.21, 0.175 * head_scale, 0.185 * head_scale, {"head": 1.0}),
    ]
    loft_mesh(
        f"cattle-{animal_id}-body-neck-head",
        [
            (x * scale, y * scale, z * scale, ry * scale, rz * scale, weights)
            for x, y, z, ry, rz, weights in main_sections
        ],
        sides,
        hide,
        rig,
        irregularity=0.008 if lod == 0 else 0.0,
        longitudinal_subdivisions=3 if lod == 0 else 2,
    )
    loft_mesh(
        f"cattle-{animal_id}-dewlap",
        [
            (0.40 * scale, 0.0, 1.13 * scale, 0.24 * scale, 0.22 * scale, {"spine": 0.50, "neck": 0.50}),
            (0.61 * scale, 0.0, 1.05 * scale, 0.21 * scale, 0.28 * scale, {"neck": 1.0}),
            (0.84 * scale, 0.0, 1.11 * scale, 0.17 * scale, 0.25 * scale, {"neck": 0.78, "head": 0.22}),
            (1.00 * scale, 0.0, 1.21 * scale, 0.11 * scale, 0.16 * scale, {"neck": 0.40, "head": 0.60}),
        ],
        max(12, sides // 2),
        hide,
        rig,
        irregularity=0.005 if lod == 0 else 0.0,
        cap_start=False,
        cap_end=False,
        longitudinal_subdivisions=2,
    )
    ellipsoid(
        f"cattle-{animal_id}-brow",
        (1.15 * scale, 0.0, 1.50 * scale),
        (0.215 * scale, 0.235 * scale * head_scale, 0.115 * scale),
        hide,
        rig,
        "head",
        sphere_segments,
        sphere_rings,
    )
    ellipsoid(
        f"cattle-{animal_id}-muzzle",
        (1.55 * scale, 0.0, 1.17 * scale),
        (0.235 * scale, 0.205 * scale, 0.165 * scale),
        materials["muzzle"],
        rig,
        "head",
        sphere_segments,
        sphere_rings,
    )
    for side_name, side_sign in (("l", -1.0), ("r", 1.0)):
        eye_y = 0.218 * side_sign * scale * head_scale
        ellipsoid(
            f"cattle-{animal_id}-eye-{side_name}",
            (1.29 * scale, eye_y, 1.40 * scale),
            (0.030 * scale, 0.018 * scale, 0.030 * scale),
            materials["eye"],
            rig,
            "head",
            max(12, sphere_segments // 2),
            max(6, sphere_rings // 2),
        )
        leaf_mesh(
            f"cattle-{animal_id}-ear-{side_name}",
            (1.08 * scale, 0.205 * side_sign * scale, 1.53 * scale),
            0.27 * scale,
            0.16 * scale,
            side_sign,
            hide,
            rig,
            "head",
        )
        leaf_mesh(
            f"cattle-{animal_id}-ear-inner-{side_name}",
            (1.075 * scale, 0.211 * side_sign * scale, 1.525 * scale),
            0.21 * scale,
            0.105 * scale,
            side_sign,
            materials["inner_ear"],
            rig,
            "head",
        )
        # Curved horn: younger animal receives a shorter, blunter horn.
        horn_length = 0.36 if animal_id == "adult" else 0.21
        horn_points = []
        horn_radii = []
        horn_weights = []
        for index in range(6 if lod == 0 else 4):
            t = index / ((6 if lod == 0 else 4) - 1)
            horn_points.append(
                (
                    (1.07 - (0.08 * t)) * scale,
                    (0.17 + horn_length * t) * side_sign * scale,
                    (1.57 + (0.055 * math.sin(t * math.pi * 0.75)) + (0.035 * t)) * scale,
                )
            )
            horn_radii.append((0.040 * (1.0 - (0.88 * t)) + 0.005) * scale)
            horn_weights.append({"head": 1.0})
        oriented_tube(
            f"cattle-{animal_id}-horn-{side_name}",
            horn_points,
            horn_radii,
            materials["horn"],
            rig,
            horn_weights,
            max(8, sides // 2),
        )

    for nostril_index, side_sign in enumerate((-1.0, 1.0)):
        ellipsoid(
            f"cattle-{animal_id}-nostril-{nostril_index}",
            (1.755 * scale, 0.090 * side_sign * scale, 1.205 * scale),
            (0.022 * scale, 0.031 * scale, 0.018 * scale),
            materials["nostril"],
            rig,
            "head",
            10,
            6,
        )
    # A dark lip line avoids a featureless rounded muzzle without requiring a
    # high-cost facial blend system.
    oriented_tube(
        f"cattle-{animal_id}-mouth-line",
        [
            (1.735 * scale, -0.12 * scale, 1.135 * scale),
            (1.755 * scale, 0.0, 1.115 * scale),
            (1.735 * scale, 0.12 * scale, 1.135 * scale),
        ],
        [0.009 * scale, 0.010 * scale, 0.009 * scale],
        materials["nostril"],
        rig,
        [{"head": 1.0}, {"head": 1.0}, {"head": 1.0}],
        7,
    )

    for suffix in ("front-l", "front-r", "hind-l", "hind-r"):
        create_leg(animal_id, suffix, scale, hide, materials["hoof"], rig, max(10, sides // 2))

    tail_points = [
        (-0.87 * scale, 0.0, 1.27 * scale),
        (-1.04 * scale, 0.0, 1.13 * scale),
        (-1.14 * scale, 0.0, 0.91 * scale),
        (-1.16 * scale, 0.0, 0.68 * scale),
    ]
    oriented_tube(
        f"cattle-{animal_id}-tail",
        tail_points,
        [0.040 * scale, 0.034 * scale, 0.027 * scale, 0.020 * scale],
        hide,
        rig,
        [
            {"tail_base": 1.0},
            {"tail_base": 1.0},
            {"tail_base": 0.35, "tail_tip": 0.65},
            {"tail_tip": 1.0},
        ],
        max(8, sides // 2),
    )
    ellipsoid(
        f"cattle-{animal_id}-tail-tuft",
        (-1.16 * scale, 0.0, 0.62 * scale),
        (0.060 * scale, 0.055 * scale, 0.12 * scale),
        materials["tuft"],
        rig,
        "tail_tip",
        max(12, sphere_segments // 2),
        max(6, sphere_rings // 2),
    )
    author_animation(animal_id, rig)
    return root, rig


def reset_pose(rig: bpy.types.Object) -> None:
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = Euler((0.0, 0.0, 0.0))
        bone.location = Vector((0.0, 0.0, 0.0))
        bone.scale = Vector((1.0, 1.0, 1.0))


def keyed_pose(
    rig: bpy.types.Object,
    frame: int,
    rotations: dict[str, tuple[float, float, float]],
    locations: dict[str, tuple[float, float, float]] | None = None,
) -> None:
    reset_pose(rig)
    for name, values in rotations.items():
        bone = rig.pose.bones.get(name)
        if bone is not None:
            bone.rotation_euler = Euler(tuple(math.radians(value) for value in values))
    for name, values in (locations or {}).items():
        bone = rig.pose.bones.get(name)
        if bone is not None:
            bone.location = Vector(values)
    for bone in rig.pose.bones:
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)


def author_animation(animal_id: str, rig: bpy.types.Object) -> None:
    action = bpy.data.actions.new(f"cattle-{animal_id}-directed-clips")
    rig.animation_data_create()
    rig.animation_data.action = action
    if animal_id == "adult":
        walk_a = {
            "front_upper_l": (11, 0, 0),
            "front_lower_l": (-7, 0, 0),
            "hind_upper_r": (10, 0, 0),
            "hind_lower_r": (-6, 0, 0),
            "front_upper_r": (-10, 0, 0),
            "hind_upper_l": (-9, 0, 0),
            "neck": (0, -2.5, 0),
            "head": (0, 2.0, 0),
            "tail_base": (0, 0, -3),
        }
        walk_b = {
            "front_upper_l": (-10, 0, 0),
            "hind_upper_r": (-9, 0, 0),
            "front_upper_r": (11, 0, 0),
            "front_lower_r": (-7, 0, 0),
            "hind_upper_l": (10, 0, 0),
            "hind_lower_l": (-6, 0, 0),
            "neck": (0, 2.0, 0),
            "head": (0, -1.5, 0),
            "tail_base": (0, 0, 3),
        }
        for frame, pose in ((1, walk_a), (9, walk_b), (17, walk_a), (25, walk_b), (33, walk_a)):
            keyed_pose(rig, frame, pose)
        keyed_pose(rig, 40, {})
        keyed_pose(
            rig,
            48,
            {
                "pelvis": (0, 0, -2),
                "spine": (0, 0, 4),
                "neck": (0, -4, 8),
                "head": (0, 5, 9),
                "front_upper_l": (3, 0, -3),
                "hind_upper_r": (-3, 0, 3),
            },
            {"root": (0.0, 0.012, -0.012)},
        )
        keyed_pose(rig, 56, {})
    else:
        brace = {
            "spine": (0, -4, 0),
            "neck": (0, 6, 0),
            "head": (0, 5, 0),
            "front_upper_l": (0, 0, -7),
            "front_upper_r": (0, 0, 7),
            "hind_upper_l": (0, 0, -8),
            "hind_upper_r": (0, 0, 8),
        }
        brace_left = dict(brace)
        brace_left.update({"spine": (0, -5, -4), "neck": (0, 7, 4), "head": (0, 4, 3)})
        brace_right = dict(brace)
        brace_right.update({"spine": (0, -3, 4), "neck": (0, 5, -4), "head": (0, 6, -3)})
        for frame, pose in ((1, brace), (9, brace_left), (17, brace_right), (25, brace_left), (32, brace)):
            keyed_pose(rig, frame, pose)
        keyed_pose(rig, 40, brace)
        keyed_pose(
            rig,
            48,
            {
                **brace,
                "spine": (0, -7, -5),
                "neck": (0, 9, 6),
                "head": (0, 2, 5),
            },
            {"root": (0.0, -0.010, -0.018)},
        )
        keyed_pose(rig, 56, brace)
    keyed_pose(rig, 60, {})
    keyed_pose(rig, 64, {})


def canonicalize_runtime_usd(path: Path) -> None:
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
    canonical_layer = stage.Flatten()
    canonical_layer.documentation = (
        "Chapter 01 project-authored cattle rig library; canonical composed runtime stage."
    )
    canonical_stage = Usd.Stage.Open(canonical_layer)
    for prim in canonical_stage.TraverseAll():
        for attribute in prim.GetAttributes():
            value = attribute.Get()
            if isinstance(value, Sdf.AssetPath) and value.path.endswith(".png"):
                attribute.Set(Sdf.AssetPath(f"./textures/{Path(value.path).name}"))

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
    if not canonical_stage.GetRootLayer().Export(str(canonical_path), args={"format": "usdc"}):
        raise RuntimeError(f"Could not write canonical USD: {canonical_path}")
    os.replace(canonical_path, path)
    pin_timestamp(path)


def runtime_objects(roots: Iterable[bpy.types.Object]) -> set[bpy.types.Object]:
    result: set[bpy.types.Object] = set()

    def visit(obj: bpy.types.Object) -> None:
        result.add(obj)
        for child in obj.children:
            visit(child)

    for root in roots:
        visit(root)
    return result


def export_runtime_usd(output: Path, lod: int, roots: Sequence[bpy.types.Object]) -> Path:
    selected = runtime_objects(roots)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in selected:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = roots[0]
    path = output / f"chapter01-cattle-library-lod{lod}.usdc"
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 64
    bpy.context.scene.render.fps = FPS
    bpy.ops.wm.usd_export(
        filepath=str(path),
        selected_objects_only=True,
        export_animation=True,
        export_materials=True,
        export_lights=False,
        export_cameras=False,
        export_custom_properties=True,
        relative_paths=True,
    )
    canonicalize_runtime_usd(path)
    return path


def add_preview_stage(roots: Sequence[bpy.types.Object], materials: dict[str, bpy.types.Material]) -> None:
    adult, young = roots
    adult_anchor = bpy.data.objects.new("preview-only-adult-placement", None)
    young_anchor = bpy.data.objects.new("preview-only-young-placement", None)
    bpy.context.collection.objects.link(adult_anchor)
    bpy.context.collection.objects.link(young_anchor)
    adult.parent = adult_anchor
    young.parent = young_anchor
    adult.location = (0.0, 0.0, 0.0)
    young.location = (0.0, 0.0, 0.0)
    adult_anchor.location = (-0.25, -0.05, 0.0)
    adult_anchor.rotation_euler[2] = math.radians(28)
    young_anchor.location = (0.72, 1.88, 0.32)
    young_anchor.rotation_euler[2] = math.radians(-18)

    bpy.ops.mesh.primitive_plane_add(size=18, location=(0.0, 0.0, -0.01))
    ground = bpy.context.object
    ground.name = "preview-only-ground"
    ground.data.materials.append(materials["ground"])

    bpy.ops.mesh.primitive_plane_add(
        size=18,
        location=(0.0, 5.4, 4.2),
        rotation=(math.radians(90), 0.0, 0.0),
    )
    backdrop = bpy.context.object
    backdrop.name = "preview-only-storm-backdrop"
    backdrop.data.materials.append(materials["backdrop"])

    for index in range(7):
        bpy.ops.mesh.primitive_cube_add(
            location=(0.75, 1.7 + ((index - 3) * 0.24), 0.17),
            scale=(1.55, 0.105, 0.085),
        )
        plank = bpy.context.object
        plank.name = f"preview-only-boat-plank-{index}"
        plank.rotation_euler[2] = math.radians(-18)
        plank.data.materials.append(materials["wood"])
        bevel = plank.modifiers.new("preview-plank-edge", "BEVEL")
        bevel.width = 0.035
        bevel.segments = 2
    for rail_index, offset in enumerate((-0.90, 0.90)):
        bpy.ops.mesh.primitive_cube_add(
            location=(0.75, 1.70 + offset, 0.42),
            scale=(1.72, 0.065, 0.075),
        )
        rail = bpy.context.object
        rail.name = f"preview-only-boat-rail-{rail_index}"
        rail.rotation_euler[2] = math.radians(-18)
        rail.data.materials.append(materials["wood"])
        bevel = rail.modifiers.new("preview-rail-edge", "BEVEL")
        bevel.width = 0.045
        bevel.segments = 2

    world = bpy.context.scene.world or bpy.data.worlds.new("preview-only-world")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.012, 0.020, 0.028, 1.0)
    background.inputs["Strength"].default_value = 0.32

    lights = [
        ("preview-only-warm-key", "AREA", (-3.6, -4.5, 5.7), 860, (1.0, 0.57, 0.29), 4.5),
        ("preview-only-cool-rim", "AREA", (4.4, 2.5, 4.6), 720, (0.24, 0.40, 0.62), 4.0),
        ("preview-only-eye-fill", "AREA", (1.0, -3.0, 2.2), 220, (0.76, 0.61, 0.42), 2.0),
    ]
    for name, light_type, location, energy, color, size in lights:
        bpy.ops.object.light_add(type=light_type, location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.color = color
        light.data.shape = "DISK"
        light.data.size = size
        target = Vector((0.2, 0.45, 0.95))
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(5.35, -9.35, 2.82))
    camera = bpy.context.object
    camera.name = "preview-only-camera"
    camera.rotation_euler = (Vector((0.02, 0.63, 0.98)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 70
    bpy.context.scene.camera = camera


def save_preview(output: Path) -> None:
    blend_path = output / "chapter01-cattle-rig-library.blend"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 1_365
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output / "chapter01-cattle-rig-preview-9x16.png")
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.frame_set(9)
    bpy.ops.render.render(write_still=True)
    pin_timestamp(blend_path)
    pin_timestamp(output / "chapter01-cattle-rig-preview-9x16.png")


def write_build_report(output: Path, lod: int, roots: Sequence[bpy.types.Object]) -> None:
    mesh_objects = [obj for obj in runtime_objects(roots) if obj.type == "MESH"]
    polygons = sum(len(obj.data.polygons) for obj in mesh_objects)
    triangles = sum(sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons) for obj in mesh_objects)
    report = {
        "animationFrameRange": [1, 64],
        "classification": "ANIMAL_RIG_CANDIDATE",
        "finalArtGate": "OPEN",
        "fps": FPS,
        "lod": lod,
        "meshObjects": len(mesh_objects),
        "polygons": polygons,
        "roots": list(ROOT_NAMES),
        "skeletons": 2,
        "triangles": triangles,
    }
    path = output / f"chapter01-cattle-library-lod{lod}-report.json"
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    pin_timestamp(path)


def main() -> None:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    output = Path(arguments[0] if arguments else "native/production/3d/chapter01/animals/outputs").resolve()
    lod = int(arguments[1]) if len(arguments) > 1 else 0
    render_preview = bool(int(arguments[2])) if len(arguments) > 2 else lod == 0
    if lod not in (0, 1):
        raise ValueError(f"Unsupported LOD: {lod}")
    clear_scene()
    output.mkdir(parents=True, exist_ok=True)
    textures = procedural_hide_textures(output)
    materials = {
        "adult_hide": hide_material("cattle-adult-hide", textures["adultBase"], textures["normal"]),
        "young_hide": hide_material("cattle-young-hide", textures["youngBase"], textures["normal"]),
        "horn": solid_material("cattle-horn", (0.13, 0.095, 0.060, 1.0), 0.68),
        "hoof": solid_material("cattle-cloven-hoof", (0.035, 0.025, 0.018, 1.0), 0.74),
        "muzzle": solid_material("cattle-muzzle", (0.052, 0.027, 0.019, 1.0), 0.58),
        "nostril": solid_material("cattle-nostril", (0.006, 0.004, 0.003, 1.0), 0.38),
        "eye": solid_material("cattle-eye", (0.007, 0.004, 0.002, 1.0), 0.16),
        "inner_ear": solid_material("cattle-inner-ear", (0.205, 0.075, 0.045, 1.0), 0.78),
        "tuft": solid_material("cattle-tail-tuft", (0.070, 0.032, 0.015, 1.0), 0.92),
        "ground": solid_material("preview-only-wet-earth", (0.045, 0.035, 0.023, 1.0), 0.96),
        "wood": solid_material("preview-only-wet-wood", (0.115, 0.067, 0.033, 1.0), 0.82),
        "backdrop": solid_material("preview-only-storm-slate", (0.020, 0.031, 0.040, 1.0), 0.98),
    }
    roots = [
        create_animal("adult", 1.0, lod, materials["adult_hide"], materials),
        create_animal("young", 0.70, lod, materials["young_hide"], materials),
    ]
    root_objects = [entry[0] for entry in roots]
    export_runtime_usd(output, lod, root_objects)
    write_build_report(output, lod, root_objects)
    if render_preview:
        add_preview_stage(root_objects, materials)
        save_preview(output)


if __name__ == "__main__":
    main()
