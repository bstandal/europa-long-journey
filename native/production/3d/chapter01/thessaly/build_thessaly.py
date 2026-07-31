"""Deterministically author the Chapter 01 Thessaly RealityKit cell.

Run only through build.sh. The script intentionally uses Blender primitives,
symbolic profiles, and seeded arithmetic instead of opaque editor state.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from pxr import Usd, UsdGeom


EXPECTED_BLENDER = (5, 2, 0)
SEED = 0x5448455353414C59
ROOT_LOGICAL_NAME = "thessalian-household-store"

MATERIALS: dict[str, bpy.types.Material] = {}
ROOT: bpy.types.Object
STATE_ROOTS: dict[str, bpy.types.Object] = {}


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--bindings", type=Path)
    return parser.parse_args(raw)


def reset_scene() -> None:
    if tuple(bpy.app.version) != EXPECTED_BLENDER:
        raise RuntimeError(
            f"Pinned Blender {EXPECTED_BLENDER} required; found {tuple(bpy.app.version)}"
        )
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            datablocks.remove(datablock)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 1
    scene.eevee.use_taa_reprojection = False
    scene.eevee.volumetric_samples = 1
    scene.eevee.volumetric_shadow_samples = 1
    scene.render.resolution_x = 720
    scene.render.resolution_y = 960
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 9
    scene.render.film_transparent = False
    scene.render.fps = 30
    scene.render.fps_base = 1.0
    scene.frame_start = 1
    scene.frame_end = 1
    scene.world.color = (0.012, 0.014, 0.012)
    scene.world.use_nodes = True
    world_nodes = scene.world.node_tree.nodes
    world_links = scene.world.node_tree.links
    background = world_nodes.get("Background")
    output = world_nodes.get("World Output")
    background.inputs["Color"].default_value = (0.065, 0.082, 0.090, 1.0)
    background.inputs["Strength"].default_value = 0.34
    volume = world_nodes.new("ShaderNodeVolumeScatter")
    volume.inputs["Color"].default_value = (0.20, 0.25, 0.28, 1.0)
    volume.inputs["Density"].default_value = 0.0025
    volume.inputs["Anisotropy"].default_value = 0.32
    world_links.new(volume.outputs["Volume"], output.inputs["Volume"])
    scene.view_settings.look = "AgX - Medium High Contrast"


def collection(name: str) -> bpy.types.Collection:
    value = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(value)
    return value


def move_to_collection(obj: bpy.types.Object, target: bpy.types.Collection) -> None:
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    target.objects.link(obj)


def tag(
    obj: bpy.types.Object,
    logical_name: str,
    *,
    state: str = "base",
    lod_priority: int = 2,
    semantic_role: str = "visual",
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    obj.name = logical_name
    obj["runtimeName"] = logical_name
    obj["state"] = state
    obj["lodPriority"] = int(lod_priority)
    obj["semanticRole"] = semantic_role
    if parent is None and logical_name != ROOT_LOGICAL_NAME:
        parent = STATE_ROOTS.get(state, ROOT)
    if parent is not None:
        obj.parent = parent
    return obj


def empty(
    name: str,
    location=(0.0, 0.0, 0.0),
    *,
    state="base",
    lod_priority=2,
    semantic_role="group",
    parent=None,
) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.18
    obj.location = location
    return tag(
        obj,
        name,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )


def pbr_material(
    name: str,
    base_color: tuple[float, float, float, float],
    *,
    roughness: float,
    metallic: float = 0.0,
    noise_scale: float | None = None,
    noise_strength: float = 0.16,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (base_color[0], base_color[1], base_color[2], alpha)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (480, 0)
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.location = (120, 0)
    shader.inputs["Base Color"].default_value = base_color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        mat.surface_render_method = "DITHERED"
    if emission is not None:
        shader.inputs["Emission Color"].default_value = emission
        shader.inputs["Emission Strength"].default_value = emission_strength
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    if noise_scale is not None:
        texcoord = nodes.new("ShaderNodeTexCoord")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = noise_scale
        noise.inputs["Detail"].default_value = 4.0
        noise.inputs["Roughness"].default_value = 0.72
        ramp = nodes.new("ShaderNodeValToRGB")
        darker = tuple(max(0.0, value * (1.0 - noise_strength)) for value in base_color[:3]) + (1.0,)
        lighter = tuple(min(1.0, value * (1.0 + noise_strength)) for value in base_color[:3]) + (1.0,)
        ramp.color_ramp.elements[0].color = darker
        ramp.color_ramp.elements[1].color = lighter
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.2
        bump.inputs["Distance"].default_value = 0.08
        links.new(texcoord.outputs["Generated"], noise.inputs["Vector"])
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])

    mat["runtimeName"] = name
    mat["materialFamily"] = "chapter01-thessaly-procedural-pbr"
    MATERIALS[name] = mat
    return mat


def assign(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    if obj.data is not None and hasattr(obj.data, "materials"):
        obj.data.materials.append(material)


def shade_smooth(obj: bpy.types.Object) -> None:
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def apply_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def box(
    name: str,
    location,
    dimensions,
    material,
    *,
    rotation=(0.0, 0.0, 0.0),
    bevel=0.0,
    state="base",
    lod_priority=2,
    semantic_role="visual",
    parent=None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_transform(obj)
    if bevel > 0:
        modifier = obj.modifiers.new("edge-softening", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    assign(obj, material)
    return tag(
        obj,
        name,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )


def cylinder(
    name: str,
    location,
    radius,
    depth,
    material,
    *,
    vertices=12,
    rotation=(0.0, 0.0, 0.0),
    state="base",
    lod_priority=2,
    semantic_role="visual",
    parent=None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    assign(obj, material)
    shade_smooth(obj)
    return tag(
        obj,
        name,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )


def cylinder_between(
    name: str,
    start,
    end,
    radius,
    material,
    *,
    vertices=10,
    state="base",
    lod_priority=2,
    semantic_role="visual",
    parent=None,
) -> bpy.types.Object:
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    obj = cylinder(
        name,
        (start_v + end_v) * 0.5,
        radius,
        direction.length,
        material,
        vertices=vertices,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def ellipsoid(
    name: str,
    location,
    scale,
    material,
    *,
    segments=16,
    rings=8,
    state="base",
    lod_priority=2,
    semantic_role="visual",
    parent=None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, location=location
    )
    obj = bpy.context.object
    obj.scale = scale
    apply_transform(obj)
    assign(obj, material)
    shade_smooth(obj)
    return tag(
        obj,
        name,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )


def cone(
    name: str,
    location,
    radius1,
    radius2,
    depth,
    material,
    *,
    vertices=12,
    rotation=(0.0, 0.0, 0.0),
    state="base",
    lod_priority=2,
    semantic_role="visual",
    parent=None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    assign(obj, material)
    shade_smooth(obj)
    return tag(
        obj,
        name,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )


def polyline_tube(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    material,
    *,
    state="base",
    lod_priority=1,
    semantic_role="visual",
    parent=None,
) -> bpy.types.Object:
    curve_data = bpy.data.curves.new(name, "CURVE")
    curve_data.dimensions = "3D"
    curve_data.resolution_u = 1
    curve_data.bevel_depth = radius
    curve_data.bevel_resolution = 1
    spline = curve_data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, value in zip(spline.points, points):
        point.co = (*value, 1.0)
    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.scene.collection.objects.link(obj)
    assign(obj, material)
    return tag(
        obj,
        name,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def create_materials() -> None:
    pbr_material("mat-soil-worked", (0.18, 0.095, 0.043, 1.0), roughness=0.98, noise_scale=4.6, noise_strength=0.38)
    pbr_material("mat-yard-earth", (0.105, 0.061, 0.031, 1.0), roughness=0.99, noise_scale=5.2, noise_strength=0.42)
    pbr_material("mat-soil-wet", (0.075, 0.047, 0.032, 1.0), roughness=0.42, noise_scale=7.0, noise_strength=0.24)
    pbr_material("mat-grain-dry", (0.52, 0.30, 0.075, 1.0), roughness=0.90, noise_scale=19.0, noise_strength=0.34)
    pbr_material("mat-grain-mass", (0.34, 0.175, 0.045, 1.0), roughness=0.94, noise_scale=7.5, noise_strength=0.38)
    pbr_material("mat-grain-damaged", (0.18, 0.135, 0.07, 1.0), roughness=0.93, noise_scale=15.0, noise_strength=0.46)
    pbr_material("mat-straw", (0.30, 0.17, 0.052, 1.0), roughness=0.98, noise_scale=11.0, noise_strength=0.34)
    pbr_material("mat-thatch-wet", (0.115, 0.058, 0.019, 1.0), roughness=0.99, noise_scale=8.5, noise_strength=0.46)
    pbr_material("mat-sprout", (0.19, 0.31, 0.075, 1.0), roughness=0.82, noise_scale=5.0, noise_strength=0.20)
    pbr_material("mat-timber-oak", (0.13, 0.062, 0.027, 1.0), roughness=0.94, noise_scale=3.2, noise_strength=0.40)
    pbr_material("mat-timber-cut", (0.25, 0.135, 0.052, 1.0), roughness=0.94, noise_scale=9.0, noise_strength=0.29)
    pbr_material("mat-wattle", (0.17, 0.080, 0.026, 1.0), roughness=0.97, noise_scale=8.0, noise_strength=0.36)
    pbr_material("mat-daub", (0.31, 0.235, 0.155, 1.0), roughness=0.99, noise_scale=6.5, noise_strength=0.28)
    pbr_material("mat-pot-fired-clay", (0.22, 0.070, 0.030, 1.0), roughness=0.93, noise_scale=6.0, noise_strength=0.34)
    pbr_material("mat-pot-slip-dark", (0.10, 0.052, 0.035, 1.0), roughness=0.74, noise_scale=12.0, noise_strength=0.18)
    pbr_material("mat-stone", (0.245, 0.225, 0.19, 1.0), roughness=0.99, noise_scale=4.3, noise_strength=0.30)
    pbr_material("mat-skin", (0.39, 0.205, 0.12, 1.0), roughness=0.78, noise_scale=10.0, noise_strength=0.08)
    pbr_material("mat-tunic-flax", (0.43, 0.33, 0.205, 1.0), roughness=0.96, noise_scale=17.0, noise_strength=0.16)
    pbr_material("mat-tunic-ochre", (0.43, 0.185, 0.065, 1.0), roughness=0.94, noise_scale=14.0, noise_strength=0.18)
    pbr_material("mat-leather", (0.13, 0.06, 0.028, 1.0), roughness=0.88, noise_scale=9.0, noise_strength=0.24)
    pbr_material("mat-hair", (0.035, 0.021, 0.014, 1.0), roughness=0.91, noise_scale=18.0, noise_strength=0.12)
    pbr_material("mat-ember", (0.34, 0.025, 0.004, 1.0), roughness=0.55, emission=(1.0, 0.12, 0.008, 1.0), emission_strength=3.0)
    pbr_material("mat-flame", (0.82, 0.12, 0.005, 1.0), roughness=0.34, emission=(1.0, 0.19, 0.012, 1.0), emission_strength=8.0, alpha=0.88)
    pbr_material("mat-rain", (0.22, 0.31, 0.34, 1.0), roughness=0.18, metallic=0.05, alpha=0.42)
    pbr_material("mat-collision", (0.0, 0.0, 0.0, 0.0), roughness=1.0, alpha=0.0)


def create_roots() -> None:
    global ROOT
    ROOT = empty(ROOT_LOGICAL_NAME, semantic_role="world-cell", parent=None)
    ROOT["cellID"] = ROOT_LOGICAL_NAME
    ROOT["schemaVersion"] = 1
    ROOT["defaultState"] = "harvest"
    ROOT["metersPerUnit"] = 1.0
    ROOT["authoredForward"] = "-Z"
    ROOT["authoredUp"] = "+Y"
    for state in ("harvest", "winter", "spring"):
        state_root = empty(
            f"state-{state}",
            state=state,
            semantic_role="material-state",
            parent=ROOT,
        )
        state_root["initiallyVisible"] = state == "harvest"
        STATE_ROOTS[state] = state_root


def mesh_object(
    name: str,
    vertices,
    faces,
    material,
    *,
    state="base",
    lod_priority=2,
    semantic_role="visual",
    parent=None,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}-mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate(verbose=False)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign(obj, material)
    return tag(
        obj,
        name,
        state=state,
        lod_priority=lod_priority,
        semantic_role=semantic_role,
        parent=parent,
    )


def create_field() -> None:
    rng = random.Random(SEED + 1)
    terrain_vertices = []
    terrain_faces = []
    terrain_columns = 13
    terrain_rows = 17
    for row in range(terrain_rows):
        y = -10.0 + 42.0 * row / (terrain_rows - 1)
        for column in range(terrain_columns):
            x = -18.0 + 36.0 * column / (terrain_columns - 1)
            z = -0.015 + 0.010 * math.sin(x * 0.31) + 0.008 * math.sin(y * 0.27)
            terrain_vertices.append((x, y, z))
    for row in range(terrain_rows - 1):
        for column in range(terrain_columns - 1):
            a = row * terrain_columns + column
            terrain_faces.append((a, a + 1, a + terrain_columns + 1, a + terrain_columns))
    mesh_object(
        "thessaly-surrounding-terrain",
        terrain_vertices,
        terrain_faces,
        MATERIALS["mat-yard-earth"],
        lod_priority=2,
        semantic_role="bounded-world-terrain",
    )
    width = 12.0
    depth = 16.0
    columns = 25
    rows = 33
    vertices = []
    faces = []
    for row in range(rows):
        y = -3.0 + depth * row / (rows - 1)
        for column in range(columns):
            x = -width * 0.5 + width * column / (columns - 1)
            edge = 0.04 * math.sin(x * 0.8) + 0.025 * math.sin(y * 1.7)
            worked = 0.018 * ((column + row) % 3)
            jitter = rng.uniform(-0.008, 0.008)
            vertices.append((x, y, edge + worked + jitter))
    for row in range(rows - 1):
        for column in range(columns - 1):
            a = row * columns + column
            faces.append((a, a + 1, a + columns + 1, a + columns))
    field = mesh_object(
        "worked-field",
        vertices,
        faces,
        MATERIALS["mat-soil-worked"],
        semantic_role="persistent-material",
    )
    field["materialChannel"] = "soilCondition"
    field["durableValues"] = "worked,wet,sown,sprouting"

    # Long low ridges remain readable in portrait while the high-frequency
    # clods fall out of secondary-residency LODs.
    for index in range(17):
        x = -5.35 + index * 0.67
        box(
            f"field-furrow-{index:02d}",
            (x, 4.7, 0.07),
            (0.24, 13.8, 0.034),
            MATERIALS["mat-soil-worked"],
            bevel=0.012,
            lod_priority=1 if index % 2 == 0 else 0,
        )

    # Irregular boundary stones tell the player where worked land ends.
    for index in range(22):
        side = -1 if index < 11 else 1
        local_index = index if side < 0 else index - 11
        x = side * (5.75 + rng.uniform(-0.08, 0.08))
        y = -2.3 + local_index * 1.38
        ellipsoid(
            f"field-boundary-stone-{index:02d}",
            (x, y, 0.12),
            (rng.uniform(0.22, 0.34), rng.uniform(0.16, 0.28), rng.uniform(0.10, 0.18)),
            MATERIALS["mat-stone"],
            segments=10,
            rings=6,
            lod_priority=1 if index % 2 == 0 else 0,
        )


def standing_grain_mesh(name: str, *, state: str, density: int, lod_priority: int) -> bpy.types.Object:
    rng = random.Random(SEED + 20 + density)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    columns = max(5, int(math.sqrt(density * 0.65)))
    rows = max(7, density // columns)
    for row in range(rows):
        for column in range(columns):
            x = -4.75 + column * 9.5 / max(1, columns - 1) + rng.uniform(-0.12, 0.12)
            y = 6.5 + row * 4.9 / max(1, rows - 1) + rng.uniform(-0.12, 0.12)
            height = rng.uniform(0.68, 0.96)
            half_width = 0.014
            base = len(vertices)
            vertices.extend(
                [
                    (x - half_width, y, 0.10),
                    (x + half_width, y, 0.10),
                    (x + half_width, y, 0.10 + height),
                    (x - half_width, y, 0.10 + height),
                    (x, y - half_width, 0.10),
                    (x, y + half_width, 0.10),
                    (x, y + half_width, 0.10 + height),
                    (x, y - half_width, 0.10 + height),
                ]
            )
            faces.extend(((base, base + 1, base + 2, base + 3), (base + 4, base + 5, base + 6, base + 7)))
            # A compact faceted head gives a grain-reading silhouette without
            # requiring alpha cards or external textures.
            head_base = len(vertices)
            hz = 0.10 + height + 0.055
            vertices.extend(
                [
                    (x - 0.035, y, hz),
                    (x, y - 0.035, hz),
                    (x + 0.035, y, hz),
                    (x, y + 0.035, hz),
                    (x, y, hz + 0.12),
                    (x, y, hz - 0.08),
                ]
            )
            faces.extend(
                [
                    (head_base, head_base + 1, head_base + 4),
                    (head_base + 1, head_base + 2, head_base + 4),
                    (head_base + 2, head_base + 3, head_base + 4),
                    (head_base + 3, head_base, head_base + 4),
                    (head_base + 1, head_base, head_base + 5),
                    (head_base + 2, head_base + 1, head_base + 5),
                    (head_base + 3, head_base + 2, head_base + 5),
                    (head_base, head_base + 3, head_base + 5),
                ]
            )
    obj = mesh_object(
        name,
        vertices,
        faces,
        MATERIALS["mat-grain-dry"],
        state=state,
        lod_priority=lod_priority,
        semantic_role="material-state",
    )
    obj["materialChannel"] = "standingHarvest"
    return obj


def loose_grain_pile(parent: bpy.types.Object) -> None:
    center = (-0.48, -1.92, 0.12)
    ellipsoid(
        "harvest-loose-grain-core",
        (center[0], center[1], center[2] + 0.16),
        (1.42, 0.92, 0.30),
        MATERIALS["mat-grain-mass"],
        segments=28,
        rings=12,
        state="harvest",
        lod_priority=1,
        semantic_role="material-source",
        parent=parent,
    )
    rng = random.Random(SEED + 21)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for _ in range(260):
        angle = rng.uniform(0.0, 2.0 * math.pi)
        radius = math.sqrt(rng.random())
        x = center[0] + math.cos(angle) * radius * 1.34
        y = center[1] + math.sin(angle) * radius * 0.83
        z = center[2] + 0.16 + 0.30 * math.sqrt(max(0.0, 1.0 - radius * radius)) + rng.uniform(0.012, 0.036)
        length = rng.uniform(0.070, 0.115)
        width = rng.uniform(0.020, 0.034)
        theta = rng.uniform(0.0, math.pi)
        dx = math.cos(theta) * length
        dy = math.sin(theta) * length
        base = len(vertices)
        vertices.extend(
            [
                (x - dx, y - dy, z),
                (x + dx, y + dy, z),
                (x - dy * width / length, y + dx * width / length, z + width),
                (x + dy * width / length, y - dx * width / length, z + width),
            ]
        )
        faces.extend(((base, base + 2, base + 1), (base, base + 1, base + 3)))
    mesh_object(
        "harvest-loose-grain-kernels",
        vertices,
        faces,
        MATERIALS["mat-grain-dry"],
        state="harvest",
        lod_priority=0,
        semantic_role="material-source-detail",
        parent=parent,
    )


def ground_straw_scatter(parent: bpy.types.Object) -> None:
    rng = random.Random(SEED + 22)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for _ in range(95):
        x = rng.uniform(-4.4, 2.3)
        y = rng.uniform(-2.75, 4.3)
        theta = rng.uniform(0.0, math.pi)
        length = rng.uniform(0.15, 0.48)
        width = 0.012
        dx = math.cos(theta) * length * 0.5
        dy = math.sin(theta) * length * 0.5
        wx = -math.sin(theta) * width
        wy = math.cos(theta) * width
        z = 0.115
        base = len(vertices)
        vertices.extend(
            [
                (x - dx - wx, y - dy - wy, z),
                (x + dx - wx, y + dy - wy, z),
                (x + dx + wx, y + dy + wy, z),
                (x - dx + wx, y - dy + wy, z),
            ]
        )
        faces.append((base, base + 1, base + 2, base + 3))
    mesh_object(
        "harvest-ground-straw-scatter",
        vertices,
        faces,
        MATERIALS["mat-straw"],
        state="harvest",
        lod_priority=0,
        semantic_role="material-context",
        parent=parent,
    )


def create_harvest_state() -> None:
    standing_grain_mesh("harvest-standing-grain", state="harvest", density=176, lod_priority=1)
    rng = random.Random(SEED + 2)
    for sheaf_index in range(7):
        sx = -4.0 + sheaf_index * 1.25
        sy = 5.2 + (sheaf_index % 2) * 0.45
        sheaf = empty(
            f"harvest-sheaf-{sheaf_index:02d}",
            state="harvest",
            lod_priority=1,
            semantic_role="harvest-material",
        )
        for stalk_index in range(8):
            angle = 2.0 * math.pi * stalk_index / 8.0
            offset = 0.045 + 0.012 * (stalk_index % 3)
            start = (sx + math.cos(angle) * offset, sy + math.sin(angle) * offset, 0.10)
            lean = rng.uniform(-0.10, 0.10)
            end = (start[0] + lean, start[1] + rng.uniform(-0.08, 0.08), rng.uniform(0.78, 0.96))
            cylinder_between(
                f"harvest-sheaf-{sheaf_index:02d}-stalk-{stalk_index:02d}",
                start,
                end,
                0.011,
                MATERIALS["mat-straw"],
                vertices=6,
                state="harvest",
                lod_priority=0,
                parent=sheaf,
            )
        cylinder(
            f"harvest-sheaf-{sheaf_index:02d}-binding",
            (sx, sy, 0.48),
            0.09,
            0.025,
            MATERIALS["mat-leather"],
            vertices=12,
            rotation=(math.pi * 0.5, 0.0, 0.0),
            state="harvest",
            lod_priority=1,
            parent=sheaf,
        )

    source = empty(
        "harvest-grain-source",
        state="harvest",
        semantic_role="material-source",
    )
    source["materialChannel"] = "unallocatedHarvest"
    loose_grain_pile(source)
    ground_straw_scatter(source)
    cone(
        "harvest-grain-basket",
        (-1.9, -0.65, 0.35),
        0.62,
        0.49,
        0.72,
        MATERIALS["mat-wattle"],
        vertices=20,
        state="harvest",
        parent=source,
    )
    ellipsoid(
        "harvest-grain-mound",
        (-1.9, -0.65, 0.69),
        (0.48, 0.43, 0.18),
        MATERIALS["mat-grain-dry"],
        segments=20,
        rings=8,
        state="harvest",
        semantic_role="material-source",
        parent=source,
    )
    for ring_index in range(4):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.50 - ring_index * 0.025,
            minor_radius=0.018,
            major_segments=20,
            minor_segments=6,
            location=(-1.9, -0.65, 0.16 + ring_index * 0.16),
        )
        ring = bpy.context.object
        assign(ring, MATERIALS["mat-wattle"])
        tag(
            ring,
            f"harvest-basket-weave-{ring_index:02d}",
            state="harvest",
            lod_priority=0,
            parent=source,
        )
    light_rain = empty(
        "harvest-light-rain",
        state="harvest",
        lod_priority=1,
        semantic_role="weather-system",
    )
    light_rain["animationBinding"] = "approaching-rain-loop"
    rain_rng = random.Random(SEED + 23)
    for index in range(24):
        x = rain_rng.uniform(-4.8, 5.3)
        y = rain_rng.uniform(-2.2, 7.8)
        z = rain_rng.uniform(1.0, 5.6)
        cylinder_between(
            f"harvest-rain-streak-{index:02d}",
            (x, y, z),
            (x - 0.08, y + 0.04, z - rain_rng.uniform(0.32, 0.66)),
            0.006,
            MATERIALS["mat-rain"],
            vertices=5,
            state="harvest",
            lod_priority=0,
            semantic_role="weather-particle",
            parent=light_rain,
        )


def revolved_vessel(
    name: str,
    location,
    profile: list[tuple[float, float]],
    material,
    *,
    segments=28,
    parent=None,
) -> bpy.types.Object:
    vertices = []
    faces = []
    for z, radius in profile:
        for index in range(segments):
            angle = 2.0 * math.pi * index / segments
            handbuilt = 1.0 + 0.012 * math.sin(angle * 3.0 + z * 5.0) + 0.006 * math.sin(angle * 7.0)
            vertices.append((location[0] + radius * handbuilt * math.cos(angle), location[1] + radius * handbuilt * math.sin(angle), location[2] + z))
    for row in range(len(profile) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            a = row * segments + index
            b = row * segments + next_index
            c = (row + 1) * segments + next_index
            d = (row + 1) * segments + index
            faces.append((a, b, c, d))
    obj = mesh_object(name, vertices, faces, material, parent=parent)
    shade_smooth(obj)
    obj["vesselConstruction"] = "profile-revolution-open-mouth"
    return obj


def create_storage_vessel(
    logical: str,
    location,
    scale: float,
    grain_name: str,
    *,
    raised: bool = False,
) -> bpy.types.Object:
    vessel = empty(logical, semantic_role="storage-vessel")
    vessel["materialChannel"] = f"{logical}Fill"
    vessel["storageRole"] = logical
    z0 = 1.05 if raised else 0.0
    profile = [
        (0.00, 0.23 * scale),
        (0.10, 0.40 * scale),
        (0.42, 0.55 * scale),
        (0.82, 0.51 * scale),
        (1.06, 0.36 * scale),
        (1.17, 0.30 * scale),
    ]
    revolved_vessel(
        f"{logical}-ceramic-body",
        (location[0], location[1], location[2] + z0),
        profile,
        MATERIALS["mat-pot-fired-clay"],
        parent=vessel,
    )
    for band_index, height in enumerate((0.23, 0.58, 0.93)):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=(0.43 if band_index != 2 else 0.36) * scale,
            minor_radius=0.022,
            major_segments=28,
            minor_segments=6,
            location=(location[0], location[1], location[2] + z0 + height),
        )
        band = bpy.context.object
        assign(band, MATERIALS["mat-pot-slip-dark"])
        tag(band, f"{logical}-ceramic-band-{band_index}", lod_priority=0, parent=vessel)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.30 * scale,
        minor_radius=0.045,
        major_segments=28,
        minor_segments=8,
        location=(location[0], location[1], location[2] + z0 + 1.17),
    )
    rim = bpy.context.object
    assign(rim, MATERIALS["mat-pot-fired-clay"])
    shade_smooth(rim)
    tag(rim, f"{logical}-thickened-rim", lod_priority=1, parent=vessel)
    for handle_index, side in enumerate((-1.0, 1.0)):
        handle_x = location[0] + side * 0.47 * scale
        polyline_tube(
            f"{logical}-handle-{handle_index}",
            [
                (handle_x, location[1], location[2] + z0 + 0.88),
                (handle_x + side * 0.18, location[1], location[2] + z0 + 0.75),
                (handle_x + side * 0.19, location[1], location[2] + z0 + 0.55),
                (handle_x, location[1], location[2] + z0 + 0.47),
            ],
            0.035,
            MATERIALS["mat-pot-fired-clay"],
            lod_priority=1,
            parent=vessel,
        )
    grain = ellipsoid(
        grain_name,
        (location[0], location[1], location[2] + z0 + 1.16),
        (0.28 * scale, 0.28 * scale, 0.085),
        MATERIALS["mat-grain-dry"],
        segments=20,
        rings=8,
        semantic_role="durable-material",
        parent=vessel,
    )
    grain["materialChannel"] = f"{logical}Grain"
    grain["durableValues"] = "empty,dry,wet,damaged,sealed,sown"
    cylinder(
        f"{logical}-woven-lid",
        (location[0] + 0.64 * scale, location[1] + 0.16, location[2] + z0 + 0.38),
        0.39 * scale,
        0.075,
        MATERIALS["mat-wattle"],
        vertices=24,
        rotation=(math.pi * 0.5, 0.12, 0.18),
        lod_priority=1,
        semantic_role="storage-seal",
        parent=vessel,
    )
    return vessel


def create_raised_store() -> bpy.types.Object:
    store = empty("raised-store", (0.0, 0.0, 0.0), semantic_role="persistent-structure")
    store["materialChannel"] = "storeIntegrity"
    store["durableValues"] = "sound,leaking,repaired,sealed"
    center = (3.25, 2.85)
    for index, (dx, dy) in enumerate(((-1.25, -1.0), (1.25, -1.0), (-1.25, 1.0), (1.25, 1.0))):
        ellipsoid(
            f"raised-store-footing-{index}",
            (center[0] + dx, center[1] + dy, 0.16),
            (0.38, 0.34, 0.18),
            MATERIALS["mat-stone"],
            segments=12,
            rings=6,
            parent=store,
        )
        cylinder(
            f"raised-store-post-{index}",
            (center[0] + dx, center[1] + dy, 0.82),
            0.13,
            1.35,
            MATERIALS["mat-timber-oak"],
            vertices=10,
            parent=store,
        )
    box(
        "raised-store-platform",
        (center[0], center[1], 1.37),
        (3.1, 2.55, 0.22),
        MATERIALS["mat-timber-cut"],
        bevel=0.035,
        parent=store,
    )
    for plank in range(8):
        box(
            f"raised-store-floor-plank-{plank:02d}",
            (center[0] - 1.34 + plank * 0.38, center[1], 1.50),
            (0.30, 2.35, 0.09),
            MATERIALS["mat-timber-cut"],
            bevel=0.018,
            lod_priority=0,
            parent=store,
        )
    for wall_index, (location, dimensions) in enumerate(
        [
            ((center[0] - 1.45, center[1], 2.22), (0.16, 2.35, 1.45)),
            ((center[0] + 1.45, center[1], 2.22), (0.16, 2.35, 1.45)),
            ((center[0], center[1] + 1.14, 2.22), (2.85, 0.16, 1.45)),
        ]
    ):
        box(
            f"raised-store-wattle-wall-{wall_index}",
            location,
            dimensions,
            MATERIALS["mat-wattle"],
            bevel=0.025,
            parent=store,
        )
    # Front posts and lintel leave the storage opening visibly operable.
    for index, x in enumerate((center[0] - 1.43, center[0] + 1.43)):
        cylinder(
            f"raised-store-front-post-{index}",
            (x, center[1] - 1.12, 2.2),
            0.10,
            1.55,
            MATERIALS["mat-timber-oak"],
            vertices=10,
            parent=store,
        )
    cylinder_between(
        "raised-store-front-lintel",
        (center[0] - 1.55, center[1] - 1.12, 2.95),
        (center[0] + 1.55, center[1] - 1.12, 2.95),
        0.11,
        MATERIALS["mat-timber-oak"],
        parent=store,
    )
    # Two thick pitched roof planes overlap at the ridge.
    box(
        "raised-store-roof-left",
        (center[0] - 0.77, center[1], 3.27),
        (1.85, 3.12, 0.19),
        MATERIALS["mat-thatch-wet"],
        rotation=(0.0, -0.44, 0.0),
        bevel=0.04,
        parent=store,
    )
    box(
        "raised-store-roof-right",
        (center[0] + 0.77, center[1], 3.27),
        (1.85, 3.12, 0.19),
        MATERIALS["mat-thatch-wet"],
        rotation=(0.0, 0.44, 0.0),
        bevel=0.04,
        parent=store,
    )
    # Wattle and thatch are authored as contact-scale geometry in LOD0. Their
    # shadows provide the material density missing from a texture-only wall.
    for side_index, x in enumerate((center[0] - 1.54, center[0] + 1.54)):
        for rod_index in range(13):
            z = 1.62 + rod_index * 0.105
            cylinder_between(
                f"raised-store-side-{side_index}-wattle-{rod_index:02d}",
                (x, center[1] - 1.06, z),
                (x, center[1] + 1.06, z + (0.025 if rod_index % 2 else -0.018)),
                0.025,
                MATERIALS["mat-wattle"],
                vertices=7,
                lod_priority=0,
                parent=store,
            )
    for roof_side in (-1, 1):
        for strip_index in range(10):
            x = center[0] + roof_side * (0.12 + strip_index * 0.16)
            z = 3.62 - abs(x - center[0]) * math.tan(0.44)
            cylinder_between(
                f"raised-store-roof-thatch-{roof_side:+d}-{strip_index:02d}",
                (x, center[1] - 1.56, z),
                (x, center[1] + 1.56, z),
                0.025,
                MATERIALS["mat-thatch-wet"],
                vertices=7,
                lod_priority=0,
                parent=store,
            )
    # A usable ladder keeps the raised floor credible and creates a strong
    # diagonal leading the eye toward the repair target.
    ladder_x = center[0] + 1.05
    left_bottom = (ladder_x - 0.28, center[1] - 2.05, 0.18)
    left_top = (ladder_x - 0.28, center[1] - 1.10, 1.75)
    right_bottom = (ladder_x + 0.28, center[1] - 2.05, 0.18)
    right_top = (ladder_x + 0.28, center[1] - 1.10, 1.75)
    cylinder_between(
        "raised-store-ladder-left-rail",
        left_bottom,
        left_top,
        0.065,
        MATERIALS["mat-timber-oak"],
        vertices=9,
        parent=store,
    )
    cylinder_between(
        "raised-store-ladder-right-rail",
        right_bottom,
        right_top,
        0.065,
        MATERIALS["mat-timber-oak"],
        vertices=9,
        parent=store,
    )
    for rung_index in range(5):
        t = 0.12 + rung_index * 0.19
        left = Vector(left_bottom).lerp(Vector(left_top), t)
        right = Vector(right_bottom).lerp(Vector(right_top), t)
        cylinder_between(
            f"raised-store-ladder-rung-{rung_index:02d}",
            left,
            right,
            0.05,
            MATERIALS["mat-timber-cut"],
            vertices=9,
            lod_priority=1,
            parent=store,
        )
    return store


def create_household_work_area() -> None:
    work = empty("household-work-area", semantic_role="work-zone")
    # A compact daub windbreak makes the fire and grain preparation legible
    # without turning the cell into a second architecture set.
    box(
        "work-area-daub-wall",
        (-3.25, 0.65, 1.05),
        (0.22, 4.2, 2.1),
        MATERIALS["mat-daub"],
        bevel=0.06,
        parent=work,
    )
    for index, y in enumerate((-1.2, 0.65, 2.5)):
        cylinder(
            f"work-area-wall-post-{index}",
            (-3.25, y, 1.15),
            0.12,
            2.3,
            MATERIALS["mat-timber-oak"],
            vertices=10,
            parent=work,
        )
    for rod_index in range(15):
        z = 0.22 + rod_index * 0.125
        cylinder_between(
            f"work-area-wall-wattle-{rod_index:02d}",
            (-3.38, -1.15, z),
            (-3.38, 2.45, z + (0.025 if rod_index % 2 else -0.02)),
            0.027,
            MATERIALS["mat-wattle"],
            vertices=7,
            lod_priority=0,
            parent=work,
        )
    box(
        "household-shelter-roof-left",
        (-3.83, 0.65, 2.48),
        (1.62, 4.55, 0.20),
        MATERIALS["mat-thatch-wet"],
        rotation=(0.0, -0.48, 0.0),
        bevel=0.05,
        parent=work,
    )
    box(
        "household-shelter-roof-right",
        (-2.63, 0.65, 2.48),
        (1.20, 4.55, 0.20),
        MATERIALS["mat-thatch-wet"],
        rotation=(0.0, 0.48, 0.0),
        bevel=0.05,
        parent=work,
    )
    for strip_index in range(11):
        x = -4.48 + strip_index * 0.17
        z = 2.83 - abs(x + 3.25) * math.tan(0.48)
        cylinder_between(
            f"household-shelter-thatch-{strip_index:02d}",
            (x, -1.65, z),
            (x, 2.95, z),
            0.026,
            MATERIALS["mat-thatch-wet"],
            vertices=7,
            lod_priority=0,
            parent=work,
        )
    # Hearth stones, ember bed, and one named flame are distinct response
    # channels. The flame can dim without deleting the work zone.
    for index in range(10):
        angle = 2.0 * math.pi * index / 10.0
        ellipsoid(
            f"hearth-stone-{index:02d}",
            (-2.0 + math.cos(angle) * 0.58, 0.6 + math.sin(angle) * 0.46, 0.14),
            (0.25, 0.20, 0.13),
            MATERIALS["mat-stone"],
            segments=10,
            rings=6,
            lod_priority=1 if index % 2 == 0 else 0,
            parent=work,
        )
    ellipsoid(
        "household-hearth-embers",
        (-2.0, 0.6, 0.14),
        (0.46, 0.34, 0.09),
        MATERIALS["mat-ember"],
        segments=16,
        rings=6,
        semantic_role="responsive-light",
        parent=work,
    )
    flame = cone(
        "household-hearth-flame",
        (-2.0, 0.6, 0.49),
        0.24,
        0.025,
        0.68,
        MATERIALS["mat-flame"],
        vertices=12,
        semantic_role="responsive-light",
        parent=work,
    )
    flame["materialChannel"] = "hearthFlame"
    flame["durableValues"] = "low,working,banked"

    # Saddle quern and handstone: the work is visible as material contact.
    ellipsoid(
        "saddle-quern",
        (-1.15, -0.05, 0.22),
        (0.72, 0.43, 0.18),
        MATERIALS["mat-stone"],
        segments=18,
        rings=8,
        semantic_role="work-tool",
        parent=work,
    )
    ellipsoid(
        "quern-handstone",
        (-1.05, -0.02, 0.48),
        (0.31, 0.18, 0.13),
        MATERIALS["mat-stone"],
        segments=14,
        rings=7,
        semantic_role="work-tool",
        parent=work,
    )
    # A low woven mat visually gathers loose work materials.
    box(
        "household-work-mat",
        (-0.7, 0.9, 0.055),
        (2.5, 2.1, 0.055),
        MATERIALS["mat-wattle"],
        bevel=0.03,
        parent=work,
    )
    for strip in range(11):
        box(
            f"work-mat-weave-{strip:02d}",
            (-1.8 + strip * 0.22, 0.9, 0.09),
            (0.035, 2.0, 0.018),
            MATERIALS["mat-straw"],
            lod_priority=0,
            parent=work,
        )


def create_yard_details() -> None:
    yard = empty("household-yard-details", semantic_role="material-context")
    rng = random.Random(SEED + 31)
    for index, (x, y, sx, sy) in enumerate(
        [
            (-2.7, -1.9, 0.72, 0.34),
            (1.8, -2.3, 0.92, 0.40),
            (2.7, 0.2, 0.60, 0.28),
            (-1.7, 2.6, 0.78, 0.31),
            (0.2, 3.8, 1.05, 0.42),
        ]
    ):
        ellipsoid(
            f"yard-wet-earth-{index}",
            (x, y, 0.11),
            (sx, sy, 0.022),
            MATERIALS["mat-soil-wet"],
            segments=18,
            rings=6,
            lod_priority=1,
            semantic_role="weathered-ground",
            parent=yard,
        )
    # Firewood and working timber create foreground depth and contact-scale
    # roughness similar to the approved portrait framing.
    for index in range(9):
        layer = index // 3
        slot = index % 3
        start = (1.45, -2.82 + slot * 0.24, 0.17 + layer * 0.15)
        end = (2.72 + rng.uniform(-0.10, 0.10), start[1] + rng.uniform(-0.04, 0.04), start[2] + rng.uniform(-0.025, 0.025))
        cylinder_between(
            f"yard-firewood-{index:02d}",
            start,
            end,
            0.095,
            MATERIALS["mat-timber-oak"],
            vertices=10,
            lod_priority=1 if layer == 0 else 0,
            semantic_role="work-material",
            parent=yard,
        )
    basket = empty("yard-empty-woven-basket", semantic_role="work-container", parent=yard)
    cone(
        "yard-empty-woven-basket-body",
        (-2.45, -1.78, 0.34),
        0.48,
        0.39,
        0.62,
        MATERIALS["mat-wattle"],
        vertices=22,
        parent=basket,
    )
    for ring_index in range(4):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.40 - ring_index * 0.018,
            minor_radius=0.018,
            major_segments=22,
            minor_segments=6,
            location=(-2.45, -1.78, 0.17 + ring_index * 0.15),
        )
        ring = bpy.context.object
        assign(ring, MATERIALS["mat-wattle"])
        tag(ring, f"yard-basket-weave-{ring_index}", lod_priority=0, parent=basket)
    polyline_tube(
        "yard-basket-handle",
        [(-2.86, -1.78, 0.54), (-2.70, -1.78, 0.94), (-2.20, -1.78, 0.94), (-2.04, -1.78, 0.54)],
        0.032,
        MATERIALS["mat-wattle"],
        lod_priority=1,
        semantic_role="work-container",
        parent=basket,
    )
    cylinder_between(
        "yard-digging-stick",
        (-2.85, 2.1, 0.18),
        (-2.45, 3.75, 1.0),
        0.045,
        MATERIALS["mat-timber-cut"],
        vertices=9,
        semantic_role="work-tool",
        parent=yard,
    )


def create_woven_tunic(
    name: str,
    center: tuple[float, float, float],
    height: float,
    material: bpy.types.Material,
    *,
    rotation=(0.0, 0.0, 0.0),
    parent: bpy.types.Object,
) -> bpy.types.Object:
    """Create a softly irregular, closed woven garment instead of a cone."""
    segments = 24
    rings = [
        (0.00, 0.37, 0.29),
        (0.16, 0.355, 0.275),
        (0.44, 0.29, 0.23),
        (0.67, 0.235, 0.195),
        (0.86, 0.29, 0.205),
        (1.00, 0.20, 0.16),
    ]
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for ring_index, (ratio, rx, ry) in enumerate(rings):
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            irregularity = 1.0 + 0.018 * math.sin(angle * 3.0 + ring_index * 0.7)
            hem = 0.025 * math.sin(angle * 5.0) if ring_index == 0 else 0.0
            vertices.append(
                (
                    center[0] + math.cos(angle) * rx * irregularity,
                    center[1] + math.sin(angle) * ry * irregularity,
                    center[2] + ratio * height + hem,
                )
            )
    for ring_index in range(len(rings) - 1):
        for segment in range(segments):
            next_segment = (segment + 1) % segments
            a = ring_index * segments + segment
            b = ring_index * segments + next_segment
            c = (ring_index + 1) * segments + next_segment
            d = (ring_index + 1) * segments + segment
            faces.append((a, b, c, d))
    obj = mesh_object(
        name,
        vertices,
        faces,
        material,
        semantic_role="clothing",
        parent=parent,
    )
    shade_smooth(obj)
    obj.rotation_euler = rotation
    obj["garmentConstruction"] = "woven-irregular-hem"
    return obj


def create_person(
    name: str,
    origin: tuple[float, float, float],
    *,
    tunic_material: bpy.types.Material,
    pose: str,
) -> bpy.types.Object:
    person = empty(name, semantic_role="dressed-human")
    person["period"] = "early-neolithic-thessaly"
    person["animationBinding"] = f"{pose}-work-cycle"
    x, y, z = origin
    if pose == "kneeling-grind":
        hip_z = z + 0.72
        shoulder_z = z + 1.38
        head_z = z + 1.72
        create_woven_tunic(
            f"{name}-tunic",
            (x, y, z + 0.66),
            0.72,
            tunic_material,
            rotation=(0.12, 0.0, -0.18),
            parent=person,
        )
        cylinder_between(
            f"{name}-left-thigh",
            (x - 0.12, y, hip_z),
            (x - 0.25, y + 0.35, z + 0.38),
            0.11,
            MATERIALS["mat-skin"],
            parent=person,
        )
        cylinder_between(
            f"{name}-right-thigh",
            (x + 0.12, y, hip_z),
            (x + 0.27, y + 0.30, z + 0.38),
            0.11,
            MATERIALS["mat-skin"],
            parent=person,
        )
        cylinder_between(
            f"{name}-left-calf",
            (x - 0.25, y + 0.35, z + 0.38),
            (x - 0.35, y + 0.72, z + 0.17),
            0.09,
            MATERIALS["mat-skin"],
            parent=person,
        )
        cylinder_between(
            f"{name}-right-calf",
            (x + 0.27, y + 0.30, z + 0.38),
            (x + 0.40, y + 0.70, z + 0.16),
            0.09,
            MATERIALS["mat-skin"],
            parent=person,
        )
        shoulder_left = (x - 0.22, y, shoulder_z)
        shoulder_right = (x + 0.22, y, shoulder_z)
        elbow_left = (x - 0.40, y + 0.33, z + 1.02)
        elbow_right = (x + 0.37, y + 0.35, z + 1.02)
        hand_left = (x - 0.21, y + 0.72, z + 0.62)
        hand_right = (x + 0.18, y + 0.74, z + 0.64)
    else:
        hip_z = z + 0.93
        shoulder_z = z + 1.55
        head_z = z + 1.91
        create_woven_tunic(
            f"{name}-tunic",
            (x, y, z + 0.74),
            0.88,
            tunic_material,
            parent=person,
        )
        for side, dx in (("left", -0.14), ("right", 0.14)):
            cylinder_between(
                f"{name}-{side}-leg",
                (x + dx, y, hip_z),
                (x + dx * 1.15, y, z + 0.08),
                0.10,
                MATERIALS["mat-skin"],
                parent=person,
            )
            ellipsoid(
                f"{name}-{side}-foot",
                (x + dx * 1.15, y - 0.10, z + 0.07),
                (0.13, 0.25, 0.08),
                MATERIALS["mat-leather"],
                segments=12,
                rings=6,
                parent=person,
            )
        shoulder_left = (x - 0.23, y, shoulder_z)
        shoulder_right = (x + 0.23, y, shoulder_z)
        elbow_left = (x - 0.42, y - 0.20, z + 1.25)
        elbow_right = (x + 0.40, y - 0.19, z + 1.24)
        hand_left = (x - 0.23, y - 0.47, z + 1.06)
        hand_right = (x + 0.21, y - 0.47, z + 1.06)

    # Belt is visibly separate from the woven tunic and remains in LOD1.
    cylinder(
        f"{name}-belt",
        (x, y, hip_z + 0.17),
        0.285,
        0.055,
        MATERIALS["mat-leather"],
        vertices=16,
        parent=person,
    )
    for side, shoulder, elbow, hand in (
        ("left", shoulder_left, elbow_left, hand_left),
        ("right", shoulder_right, elbow_right, hand_right),
    ):
        cylinder_between(
            f"{name}-{side}-upper-arm",
            shoulder,
            elbow,
            0.085,
            MATERIALS["mat-skin"],
            parent=person,
        )
        sleeve_end = Vector(shoulder).lerp(Vector(elbow), 0.48)
        cylinder_between(
            f"{name}-{side}-woven-sleeve",
            shoulder,
            sleeve_end,
            0.105,
            tunic_material,
            vertices=16,
            lod_priority=1,
            semantic_role="clothing",
            parent=person,
        )
        cylinder_between(
            f"{name}-{side}-forearm",
            elbow,
            hand,
            0.073,
            MATERIALS["mat-skin"],
            parent=person,
        )
        ellipsoid(
            f"{name}-{side}-hand",
            hand,
            (0.09, 0.12, 0.07),
            MATERIALS["mat-skin"],
            segments=12,
            rings=6,
            parent=person,
        )
        finger_direction = (Vector(hand) - Vector(elbow)).normalized()
        finger_cross = finger_direction.cross(Vector((0.0, 0.0, 1.0)))
        if finger_cross.length < 0.01:
            finger_cross = Vector((1.0, 0.0, 0.0))
        finger_cross.normalize()
        for finger_index in range(3):
            offset = finger_cross * ((finger_index - 1) * 0.025)
            finger_start = Vector(hand) + offset + finger_direction * 0.045
            finger_end = finger_start + finger_direction * (0.075 + finger_index * 0.008)
            cylinder_between(
                f"{name}-{side}-finger-{finger_index}",
                finger_start,
                finger_end,
                0.014,
                MATERIALS["mat-skin"],
                vertices=8,
                lod_priority=0,
                semantic_role="hand-detail",
                parent=person,
            )
    cylinder_between(
        f"{name}-neck",
        (x, y, shoulder_z + 0.06),
        (x, y, head_z - 0.20),
        0.10,
        MATERIALS["mat-skin"],
        parent=person,
    )
    ellipsoid(
        f"{name}-head",
        (x, y, head_z),
        (0.22, 0.19, 0.27),
        MATERIALS["mat-skin"],
        segments=18,
        rings=10,
        parent=person,
    )
    ellipsoid(
        f"{name}-hair",
        (x, y + 0.070, head_z + 0.13),
        (0.238, 0.175, 0.17),
        MATERIALS["mat-hair"],
        segments=16,
        rings=8,
        lod_priority=1,
        semantic_role="hair-groomed-static",
        parent=person,
    )
    for side, dx in (("left", -0.215), ("right", 0.215)):
        ellipsoid(
            f"{name}-{side}-ear",
            (x + dx, y - 0.01, head_z),
            (0.040, 0.028, 0.067),
            MATERIALS["mat-skin"],
            segments=10,
            rings=5,
            lod_priority=0,
            semantic_role="face-detail",
            parent=person,
        )
    for side, dx in (("left", -0.078), ("right", 0.078)):
        ellipsoid(
            f"{name}-{side}-eye",
            (x + dx, y - 0.178, head_z + 0.035),
            (0.026, 0.014, 0.017),
            MATERIALS["mat-hair"],
            segments=10,
            rings=5,
            lod_priority=0,
            semantic_role="face-detail",
            parent=person,
        )
        cylinder_between(
            f"{name}-{side}-brow",
            (x + dx - 0.038, y - 0.184, head_z + 0.095),
            (x + dx + 0.038, y - 0.187, head_z + 0.090),
            0.009,
            MATERIALS["mat-hair"],
            vertices=7,
            lod_priority=0,
            semantic_role="face-detail",
            parent=person,
        )
    polyline_tube(
        f"{name}-mouth",
        [(x - 0.060, y - 0.190, head_z - 0.105), (x, y - 0.198, head_z - 0.118), (x + 0.060, y - 0.190, head_z - 0.105)],
        0.009,
        MATERIALS["mat-pot-slip-dark"],
        lod_priority=0,
        semantic_role="face-detail",
        parent=person,
    )
    # Small facial planes preserve direction of attention in close framing.
    ellipsoid(
        f"{name}-nose",
        (x, y - 0.185, head_z - 0.015),
        (0.043, 0.064, 0.075),
        MATERIALS["mat-skin"],
        segments=10,
        rings=5,
        lod_priority=0,
        parent=person,
    )
    return person


def create_people() -> None:
    grinder = create_person(
        "person-grinding-grain",
        (-0.84, -0.54, 0.08),
        tunic_material=MATERIALS["mat-tunic-flax"],
        pose="kneeling-grind",
    )
    grinder["workContactEntity"] = "quern-handstone"
    ellipsoid(
        "person-grinding-grain-hair-bun",
        (-0.84, -0.39, 1.88),
        (0.12, 0.13, 0.12),
        MATERIALS["mat-hair"],
        segments=14,
        rings=7,
        lod_priority=0,
        semantic_role="hair-groomed-static",
        parent=grinder,
    )
    carrier = create_person(
        "person-carrying-seed",
        (0.72, -0.80, 0.08),
        tunic_material=MATERIALS["mat-tunic-ochre"],
        pose="standing-carry",
    )
    carrier["workContactEntity"] = "seed-grain"
    for braid_index, dx in enumerate((-0.055, 0.055)):
        polyline_tube(
            f"person-carrying-seed-braid-{braid_index}",
            [
                (0.72 + dx, -0.66, 2.08),
                (0.72 - dx * 0.3, -0.61, 1.86),
                (0.72 + dx * 0.55, -0.59, 1.62),
                (0.72, -0.57, 1.42),
            ],
            0.032,
            MATERIALS["mat-hair"],
            lod_priority=0,
            semantic_role="hair-groomed-static",
            parent=carrier,
        )
    # A carried vessel bridges hand position to the seed store.
    cone(
        "seed-carrying-bowl",
        (0.71, -1.25, 1.18),
        0.31,
        0.21,
        0.22,
        MATERIALS["mat-pot-fired-clay"],
        vertices=18,
        parent=carrier,
    )
    ellipsoid(
        "seed-carrying-bowl-grain",
        (0.71, -1.25, 1.30),
        (0.24, 0.20, 0.055),
        MATERIALS["mat-grain-dry"],
        segments=16,
        rings=6,
        parent=carrier,
    )


def create_winter_state() -> None:
    rain = empty(
        "winter-rain",
        state="winter",
        semantic_role="weather-system",
    )
    rain["animationBinding"] = "winter-rain-fall-loop"
    rain["materialChannel"] = "precipitation"
    rng = random.Random(SEED + 3)
    for index in range(52):
        x = rng.uniform(-6.3, 6.3)
        y = rng.uniform(-3.0, 9.5)
        z = rng.uniform(0.7, 5.7)
        length = rng.uniform(0.42, 0.92)
        cylinder_between(
            f"winter-rain-streak-{index:03d}",
            (x, y, z),
            (x - 0.12, y + 0.05, z - length),
            0.008,
            MATERIALS["mat-rain"],
            vertices=5,
            state="winter",
            lod_priority=0 if index % 3 else 1,
            semantic_role="weather-particle",
            parent=rain,
        )
    for index, (x, y, sx, sy) in enumerate(
        [
            (-1.7, 1.6, 1.2, 0.58),
            (0.8, 2.7, 1.55, 0.7),
            (3.1, -0.2, 1.0, 0.45),
            (-3.6, 4.0, 1.4, 0.64),
            (1.9, 6.0, 1.8, 0.72),
        ]
    ):
        ellipsoid(
            f"winter-wet-ground-{index}",
            (x, y, 0.105),
            (sx, sy, 0.025),
            MATERIALS["mat-soil-wet"],
            segments=18,
            rings=6,
            state="winter",
            lod_priority=1,
            semantic_role="weather-consequence",
        )
    # Damaged grain reads as the direct consequence of a weak allocation.
    damage = ellipsoid(
        "winter-food-grain-damage",
        (-0.15, 2.10, 1.22),
        (0.36, 0.34, 0.12),
        MATERIALS["mat-grain-damaged"],
        segments=18,
        rings=7,
        state="winter",
        semantic_role="allocation-consequence",
    )
    damage["materialChannel"] = "foodGrainDamage"
    damage["durableValues"] = "none,wet,spoiled"
    for index in range(11):
        angle = 2.0 * math.pi * index / 11.0
        ellipsoid(
            f"winter-spilled-grain-{index:02d}",
            (-0.15 + math.cos(angle) * 0.38, 2.10 + math.sin(angle) * 0.31, 0.14),
            (0.055, 0.028, 0.025),
            MATERIALS["mat-grain-damaged"],
            segments=8,
            rings=4,
            state="winter",
            lod_priority=0,
            semantic_role="allocation-consequence",
        )
    # A broken roof edge and a loose lashing remain visibly repairable.
    cylinder_between(
        "winter-store-loose-roof-pole",
        (2.15, 1.60, 3.55),
        (4.25, 3.70, 2.78),
        0.075,
        MATERIALS["mat-timber-cut"],
        state="winter",
        semantic_role="repair-target",
    )
    polyline_tube(
        "winter-store-loose-lashing",
        [(4.23, 3.67, 2.79), (4.46, 3.52, 2.55), (4.40, 3.37, 2.25)],
        0.025,
        MATERIALS["mat-leather"],
        state="winter",
        semantic_role="repair-target",
    )


def sprout_mesh() -> bpy.types.Object:
    rng = random.Random(SEED + 4)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for row in range(16):
        y = -1.5 + row * 0.76
        for column in range(11):
            x = -4.7 + column * 0.94 + rng.uniform(-0.12, 0.12)
            height = rng.uniform(0.10, 0.23)
            width = 0.025
            base = len(vertices)
            vertices.extend(
                [
                    (x - width, y, 0.10),
                    (x + width, y, 0.10),
                    (x, y, 0.10 + height),
                    (x, y - width, 0.10),
                    (x, y + width, 0.10),
                    (x + 0.03, y, 0.10 + height * 0.92),
                ]
            )
            faces.extend(((base, base + 1, base + 2), (base + 3, base + 4, base + 5)))
    sprouts = mesh_object(
        "spring-field-sprouts",
        vertices,
        faces,
        MATERIALS["mat-sprout"],
        state="spring",
        lod_priority=1,
        semantic_role="material-consequence",
    )
    sprouts["materialChannel"] = "springGrowth"
    sprouts["durableValues"] = "sown,germinating,sprouting"
    return sprouts


def create_spring_state() -> None:
    sprout_mesh()
    # The sowing furrow carries the same physical grain motif back into soil.
    spring_line = empty(
        "spring-sowing-line",
        state="spring",
        semantic_role="transition-carrier",
    )
    spring_line["carrierID"] = "grain-motif-return"
    for index in range(24):
        x = -4.45 + index * 0.39
        ellipsoid(
            f"spring-seed-in-soil-{index:02d}",
            (x, -1.35, 0.115),
            (0.055, 0.032, 0.025),
            MATERIALS["mat-grain-dry"],
            segments=8,
            rings=4,
            state="spring",
            lod_priority=0 if index % 2 else 1,
            semantic_role="transition-carrier",
            parent=spring_line,
        )
    box(
        "spring-repaired-store-patch",
        (2.95, 1.72, 3.28),
        (1.7, 0.28, 0.13),
        MATERIALS["mat-straw"],
        rotation=(0.0, -0.38, 0.0),
        bevel=0.025,
        state="spring",
        semantic_role="repair-consequence",
    )
    polyline_tube(
        "spring-repaired-store-lashing",
        [(2.22, 1.68, 3.55), (2.35, 1.59, 3.39), (2.26, 1.69, 3.22), (2.38, 1.63, 3.06)],
        0.028,
        MATERIALS["mat-leather"],
        state="spring",
        semantic_role="repair-consequence",
    )


def action_volume(name: str, location, dimensions, *, action: str) -> bpy.types.Object:
    obj = box(
        name,
        location,
        dimensions,
        MATERIALS["mat-collision"],
        bevel=0.08,
        semantic_role="action-volume",
        parent=ROOT,
    )
    obj["collisionEnabled"] = True
    obj["collisionShape"] = "box"
    obj["interactionAction"] = action
    obj["visibleMaterialOpacity"] = 0.0
    obj.visible_shadow = False
    return obj


def create_action_and_transition_anchors() -> None:
    action_volume(
        "action-grain-source",
        (-1.05, -1.35, 0.62),
        (3.25, 2.45, 1.35),
        action="begin-allocation",
    )
    action_volume("action-food", (-0.15, 2.10, 0.70), (1.3, 1.3, 1.65), action="allocate-food")
    action_volume("action-reserve", (3.25, 2.85, 2.00), (3.25, 2.65, 3.3), action="allocate-reserve")
    action_volume("action-seed", (1.35, 1.35, 0.63), (1.25, 1.25, 1.55), action="allocate-seed")
    action_volume("action-store-seal", (3.25, 1.60, 2.15), (2.7, 0.55, 2.35), action="seal-store")
    action_volume("action-store-repair", (3.45, 2.10, 3.15), (2.6, 1.9, 1.1), action="repair-store")
    action_volume("action-spring-sow", (0.0, -1.25, 0.25), (9.5, 1.25, 0.45), action="sow-spring-seed")

    for name, location, semantic in (
        ("transition-aegean-in", (-1.85, -3.25, 0.42), "transition-entry"),
        ("transition-iron-gates-out", (5.65, 7.2, 0.48), "transition-exit"),
        ("carrier-dry-seed-entry", (-1.85, -2.75, 0.72), "transition-carrier"),
        ("carrier-sown-seed-exit", (0.0, -1.35, 0.16), "transition-carrier"),
    ):
        anchor = empty(name, location, semantic_role=semantic, parent=ROOT)
        anchor["anchorRadius"] = 0.22


def create_camera_and_light_rig() -> None:
    camera_specs = [
        ("camera-harvest-overview", (5.65, -7.85, 3.85), (-0.15, 0.55, 0.78), 45.0),
        ("camera-allocation-close", (4.1, -5.3, 3.0), (0.0, 0.7, 0.85), 53.0),
        ("camera-winter-loss", (7.0, -6.1, 4.8), (1.5, 2.4, 1.6), 51.0),
        ("camera-repair", (7.2, -1.9, 4.4), (3.25, 2.65, 2.55), 56.0),
        ("camera-spring-sowing", (5.6, -7.8, 3.8), (0.0, 1.8, 0.25), 49.0),
    ]
    for index, (name, location, target, lens) in enumerate(camera_specs):
        data = bpy.data.cameras.new(f"{name}-data")
        data.lens = lens
        data.sensor_width = 36.0
        data.dof.use_dof = False
        camera = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(camera)
        camera.location = location
        look_at(camera, target)
        tag(camera, name, semantic_role="camera-anchor", parent=ROOT)
        camera["reduceMotionAnchor"] = True
        camera["cameraOrder"] = index
        camera["portraitSafe"] = True
        if index == 0:
            bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("thessaly-overcast-sun-data", type="SUN")
    sun_data.energy = 2.5
    sun_data.color = (0.58, 0.66, 0.72)
    sun_data.angle = math.radians(32.0)
    sun = bpy.data.objects.new("thessaly-overcast-sun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(28), math.radians(-18), math.radians(-36))
    tag(sun, "thessaly-overcast-sun", lod_priority=2, semantic_role="key-light", parent=ROOT)

    sky_data = bpy.data.lights.new("thessaly-sky-fill-data", type="AREA")
    sky_data.energy = 980.0
    sky_data.shape = "DISK"
    sky_data.size = 8.0
    sky_data.color = (0.36, 0.44, 0.49)
    sky = bpy.data.objects.new("thessaly-sky-fill", sky_data)
    bpy.context.scene.collection.objects.link(sky)
    sky.location = (-2.0, -1.0, 8.8)
    look_at(sky, (0.0, 2.0, 0.0))
    tag(sky, "thessaly-sky-fill", semantic_role="fill-light", parent=ROOT)

    fire_data = bpy.data.lights.new("hearth-practical-light-data", type="POINT")
    fire_data.energy = 280.0
    fire_data.color = (1.0, 0.19, 0.035)
    fire_data.shadow_soft_size = 1.05
    fire = bpy.data.objects.new("hearth-practical-light", fire_data)
    bpy.context.scene.collection.objects.link(fire)
    fire.location = (-2.0, 0.6, 0.62)
    tag(fire, "hearth-practical-light", lod_priority=1, semantic_role="practical-light", parent=ROOT)

    break_data = bpy.data.lights.new("storm-break-rim-data", type="AREA")
    break_data.energy = 900.0
    break_data.shape = "DISK"
    break_data.size = 5.0
    break_data.color = (0.48, 0.60, 0.66)
    break_light = bpy.data.objects.new("storm-break-rim", break_data)
    bpy.context.scene.collection.objects.link(break_light)
    break_light.location = (4.0, 10.5, 8.2)
    look_at(break_light, (0.5, 1.2, 0.8))
    tag(break_light, "storm-break-rim", lod_priority=1, semantic_role="rim-light", parent=ROOT)

    camera_fill_data = bpy.data.lights.new("portrait-readable-fill-data", type="AREA")
    camera_fill_data.energy = 620.0
    camera_fill_data.shape = "DISK"
    camera_fill_data.size = 5.5
    camera_fill_data.color = (0.38, 0.47, 0.50)
    camera_fill = bpy.data.objects.new("portrait-readable-fill", camera_fill_data)
    bpy.context.scene.collection.objects.link(camera_fill)
    camera_fill.location = (3.8, -4.8, 5.2)
    look_at(camera_fill, (-0.2, 0.2, 0.9))
    tag(camera_fill, "portrait-readable-fill", lod_priority=1, semantic_role="readability-light", parent=ROOT)


def create_background_context() -> None:
    distance = pbr_material(
        "mat-distance-vegetation",
        (0.090, 0.118, 0.072, 1.0),
        roughness=0.99,
        noise_scale=2.3,
        noise_strength=0.38,
        emission=(0.028, 0.040, 0.024, 1.0),
        emission_strength=0.42,
    )
    storm_sky = pbr_material(
        "mat-storm-sky",
        (0.105, 0.125, 0.134, 1.0),
        roughness=1.0,
        noise_scale=2.8,
        noise_strength=0.58,
        emission=(0.090, 0.112, 0.120, 1.0),
        emission_strength=0.8,
    )
    storm_break = pbr_material(
        "mat-storm-break",
        (0.19, 0.22, 0.23, 1.0),
        roughness=0.9,
        noise_scale=3.0,
        noise_strength=0.35,
        emission=(0.26, 0.31, 0.33, 1.0),
        emission_strength=2.2,
    )
    box(
        "thessaly-storm-sky-plane",
        (0.0, 30.0, 9.5),
        (120.0, 0.18, 24.0),
        storm_sky,
        lod_priority=2,
        semantic_role="bounded-world-sky",
    )
    ellipsoid(
        "thessaly-storm-light-break",
        (3.1, 23.75, 6.7),
        (2.2, 0.08, 1.25),
        storm_break,
        segments=24,
        rings=12,
        lod_priority=1,
        semantic_role="bounded-world-sky-light",
    )
    for index, (x, y, z, sx, sy, sz) in enumerate(
        [
            (-5.5, 17.5, -0.4, 7.4, 3.4, 1.45),
            (4.2, 18.5, -0.2, 8.5, 3.8, 1.65),
            (0.0, 22.0, 0.0, 12.0, 4.8, 1.85),
        ]
    ):
        ellipsoid(
            f"thessaly-distant-ridge-{index}",
            (x, y, z),
            (sx, sy, sz),
            distance,
            segments=18,
            rings=9,
            lod_priority=2,
            semantic_role="bounded-world-horizon",
        )
    for index, (x, y, scale) in enumerate(
        [(-5.0, 12.2, 0.8), (-3.1, 13.1, 1.0), (-0.8, 12.5, 0.75), (1.8, 13.4, 1.1), (4.2, 12.7, 0.9), (5.6, 14.0, 1.2)]
    ):
        cylinder(
            f"thessaly-midground-tree-{index}-trunk",
            (x, y, 0.85 * scale),
            0.10 * scale,
            1.7 * scale,
            MATERIALS["mat-timber-oak"],
            vertices=8,
            lod_priority=1,
            semantic_role="bounded-world-vegetation",
        )
        ellipsoid(
            f"thessaly-midground-tree-{index}-crown",
            (x, y, 1.95 * scale),
            (0.72 * scale, 0.52 * scale, 0.82 * scale),
            distance,
            segments=12,
            rings=7,
            lod_priority=1,
            semantic_role="bounded-world-vegetation",
        )
    storm = pbr_material(
        "mat-storm-cloud",
        (0.110, 0.125, 0.130, 1.0),
        roughness=1.0,
        noise_scale=2.0,
        noise_strength=0.38,
        emission=(0.095, 0.110, 0.116, 1.0),
        emission_strength=1.0,
    )
    for index, (x, y, z, sx, sy, sz) in enumerate(
        [
            (-5.0, 26.5, 6.5, 3.0, 1.5, 0.70),
            (0.0, 27.5, 7.0, 3.7, 1.7, 0.82),
            (5.4, 26.8, 6.3, 2.8, 1.4, 0.68),
        ]
    ):
        ellipsoid(
            f"thessaly-storm-cloud-{index}",
            (x, y, z),
            (sx, sy, sz),
            storm,
            segments=18,
            rings=9,
            lod_priority=1,
            semantic_role="bounded-world-sky",
        )


def build_scene() -> None:
    reset_scene()
    create_materials()
    create_roots()
    create_field()
    create_background_context()
    create_harvest_state()
    create_household_work_area()
    create_yard_details()
    create_raised_store()
    create_storage_vessel("food-storage", (-0.15, 2.10, 0.05), 1.05, "food-grain")
    create_storage_vessel("reserve-storage", (3.25, 2.85, 0.05), 0.92, "reserve-grain", raised=True)
    create_storage_vessel("seed-storage", (1.35, 1.35, 0.05), 0.86, "seed-grain")
    create_people()
    create_winter_state()
    create_spring_state()
    create_action_and_transition_anchors()
    create_camera_and_light_rig()


def set_render_state(active_state: str) -> None:
    for obj in bpy.context.scene.objects:
        state = obj.get("state", "base")
        obj.hide_render = state not in ("base", active_state)


def render_previews(output_dir: Path) -> None:
    scene = bpy.context.scene
    camera_names = {
        "harvest": "camera-harvest-overview",
        "winter": "camera-winter-loss",
        "spring": "camera-spring-sowing",
    }
    for state in ("harvest", "winter", "spring"):
        set_render_state(state)
        scene.camera = bpy.data.objects[camera_names[state]]
        scene.render.filepath = str(output_dir / f"preview-{state}.png")
        bpy.ops.render.render(write_still=True)
    set_render_state("harvest")
    scene.camera = bpy.data.objects["camera-harvest-overview"]


def select_lod(lod_level: int) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if int(obj.get("lodPriority", 2)) >= lod_level:
            obj.hide_set(False)
            obj.select_set(True)


def export_usdc(path: Path, lod_level: int) -> None:
    # Blender's RENDER evaluation omits hide_render objects instead of
    # preserving them as invisible USD prims. Export every authored state and
    # set initial USD visibility explicitly during canonicalisation below.
    for obj in bpy.context.scene.objects:
        obj.hide_render = False
    select_lod(lod_level)
    bpy.ops.wm.usd_export(
        filepath=str(path),
        check_existing=False,
        selected_objects_only=True,
        export_animation=False,
        export_hair=False,
        export_uvmaps=True,
        rename_uvmaps=True,
        export_mesh_colors=True,
        export_normals=True,
        export_materials=True,
        export_subdivision="IGNORE",
        export_armatures=False,
        export_shapekeys=False,
        use_instancing=False,
        evaluation_mode="RENDER",
        generate_preview_surface=True,
        generate_materialx_network=False,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        export_textures_mode="KEEP",
        relative_paths=True,
        xform_op_mode="TRS",
        root_prim_path="/Chapter01",
        export_custom_properties=True,
        custom_properties_namespace="userProperties",
        author_blender_name=False,
        convert_world_material=False,
        allow_unicode=False,
        export_meshes=True,
        export_lights=True,
        export_cameras=True,
        export_curves=True,
        export_points=False,
        export_volumes=False,
        triangulate_meshes=False,
        merge_parent_xform=False,
        convert_scene_units="METERS",
        meters_per_unit=1.0,
    )


def canonicalize_mesh_topology(stage: Usd.Stage) -> None:
    """Stabilise Blender/BMesh face ordering without changing geometry.

    Blender primitives and applied bevels may emit equivalent faces in a
    different hash-table order on separate processes. USD face order is not
    semantically meaningful here, but it changes crate bytes. Faces are
    cyclically normalised, sorted by vertex tuple, and all face-varying or
    uniform data is moved with them. Exported normals are rounded to four
    decimals (well below the visible threshold) to remove process-local
    floating summation noise from Blender's normal calculation.
    """

    for prim in stage.TraverseAll():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(prim)
        counts_value = mesh.GetFaceVertexCountsAttr().Get()
        indices_value = mesh.GetFaceVertexIndicesAttr().Get()
        if counts_value is None or indices_value is None:
            continue
        counts = [int(value) for value in counts_value]
        indices = [int(value) for value in indices_value]
        if not counts or sum(counts) != len(indices):
            continue

        records = []
        cursor = 0
        for face_index, count in enumerate(counts):
            segment = indices[cursor : cursor + count]
            rotations = [tuple(segment[offset:] + segment[:offset]) for offset in range(count)]
            canonical = min(rotations)
            rotation = rotations.index(canonical)
            records.append(
                {
                    "oldFace": face_index,
                    "cursor": cursor,
                    "count": count,
                    "rotation": rotation,
                    "indices": canonical,
                }
            )
            cursor += count
        records.sort(key=lambda item: (item["indices"], item["count"], item["oldFace"]))
        old_to_new = {record["oldFace"]: new for new, record in enumerate(records)}

        def reordered_corners(values):
            result = []
            for record in records:
                start = record["cursor"]
                count = record["count"]
                rotation = record["rotation"]
                segment = list(values[start : start + count])
                result.extend(segment[rotation:] + segment[:rotation])
            return result

        def reordered_faces(values):
            return [values[record["oldFace"]] for record in records]

        for attribute in prim.GetAttributes():
            name = attribute.GetName()
            if name in {"faceVertexCounts", "faceVertexIndices", "holeIndices"}:
                continue
            value = attribute.Get()
            if value is None or not hasattr(value, "__len__"):
                continue
            interpolation = attribute.GetMetadata("interpolation")
            if name.endswith(":indices"):
                value_attribute = prim.GetAttribute(name[: -len(":indices")])
                if value_attribute:
                    interpolation = value_attribute.GetMetadata("interpolation")
            output = None
            if interpolation == "faceVarying" and len(value) == len(indices):
                output = reordered_corners(value)
            elif interpolation == "uniform" and len(value) == len(counts):
                output = reordered_faces(value)
            if output is None:
                continue
            if name == "normals":
                def canonical_normal_component(component: float) -> float:
                    value = round(float(component), 4)
                    return 0.0 if value == 0.0 else value

                output = [
                    type(vector)(
                        canonical_normal_component(vector[0]),
                        canonical_normal_component(vector[1]),
                        canonical_normal_component(vector[2]),
                    )
                    for vector in output
                ]
            attribute.Set(type(value)(output))

        holes = mesh.GetHoleIndicesAttr().Get()
        if holes:
            mesh.GetHoleIndicesAttr().Set(type(holes)(sorted(old_to_new[int(index)] for index in holes)))
        for child in prim.GetChildren():
            if child.GetTypeName() != "GeomSubset":
                continue
            element_type = child.GetAttribute("elementType").Get()
            subset_indices = child.GetAttribute("indices").Get()
            if element_type == "face" and subset_indices:
                remapped = sorted(old_to_new[int(index)] for index in subset_indices)
                child.GetAttribute("indices").Set(type(subset_indices)(remapped))

        mesh.GetFaceVertexCountsAttr().Set(type(counts_value)([record["count"] for record in records]))
        mesh.GetFaceVertexIndicesAttr().Set(
            type(indices_value)([index for record in records for index in record["indices"]])
        )


def canonicalize_usd(path: Path) -> dict[str, str]:
    stage = Usd.Stage.Open(str(path))
    if stage is None:
        raise RuntimeError(f"Unable to open exported USD: {path}")
    bindings: dict[str, str] = {}
    root_prim = None
    for prim in stage.TraverseAll():
        attribute = prim.GetAttribute("userProperties:runtimeName")
        if not attribute:
            continue
        logical = attribute.Get()
        if not isinstance(logical, str) or not logical:
            continue
        if logical in bindings:
            existing_path = bindings[logical]
            current_path = str(prim.GetPath())
            if current_path.startswith(existing_path + "/"):
                # Blender may author a curve object's custom properties onto
                # its generated geometry child as well. The shallower object
                # prim owns the runtime identity; geometry remains anonymous.
                prim.RemoveProperty("userProperties:runtimeName")
                continue
            if existing_path.startswith(current_path + "/"):
                existing = stage.GetPrimAtPath(existing_path)
                existing.RemoveProperty("userProperties:runtimeName")
            else:
                raise RuntimeError(f"Duplicate runtimeName {logical!r} in {path}")
        prim.SetDisplayName(logical)
        prim.SetCustomDataByKey("runtimeName", logical)
        if logical in {"state-winter", "state-spring"}:
            UsdGeom.Imageable(prim).MakeInvisible()
        elif logical == "state-harvest":
            UsdGeom.Imageable(prim).MakeVisible()
        bindings[logical] = str(prim.GetPath())
        if logical == ROOT_LOGICAL_NAME:
            root_prim = prim
    if root_prim is None:
        raise RuntimeError(f"Missing logical root {ROOT_LOGICAL_NAME!r} in {path}")
    stage.SetDefaultPrim(root_prim)
    canonicalize_mesh_topology(stage)
    stage.GetRootLayer().customLayerData = {
        "assetID": "chapter01-thessaly-household-store",
        "authoringTool": "Blender 5.2.0 LTS",
        "canonicalSeed": str(SEED),
        "contentSchemaVersion": "1",
    }
    # Blender's exporter may author sibling prims in task-completion order.
    # Composition order is made explicit, then Stage.Flatten reauthors the
    # layer by composed order so the binary crate is byte-stable.
    for ordered_prim in [stage.GetPseudoRoot(), *list(stage.TraverseAll())]:
        child_names = sorted(str(name) for name in ordered_prim.GetAllChildrenNames())
        if len(child_names) > 1:
            ordered_prim.SetChildrenReorder(child_names)
        property_names = sorted(prop.GetName() for prop in ordered_prim.GetProperties())
        if len(property_names) > 1:
            ordered_prim.SetPropertyOrder(property_names)
    stage.GetRootLayer().Save()
    canonical_layer = stage.Flatten(addSourceFileComment=False)
    canonical_path = path.with_name(f".{path.stem}.canonical.usdc")
    canonical_path.unlink(missing_ok=True)
    if not canonical_layer.Export(str(canonical_path), args={"format": "usdc"}):
        raise RuntimeError(f"Unable to write canonical USD crate: {canonical_path}")
    canonical_path.replace(path)
    return bindings


def write_ascii_usd(source: Path, destination: Path) -> None:
    stage = Usd.Stage.Open(str(source))
    if stage is None:
        raise RuntimeError(f"Unable to open {source}")
    if not stage.GetRootLayer().Export(str(destination), args={"format": "usda"}):
        raise RuntimeError(f"Unable to export ASCII USD to {destination}")


def build_usdz(source: Path, destination: Path) -> None:
    destination.unlink(missing_ok=True)
    # usdzip stores the source file's DOS timestamp. Pin both the source mtime
    # and packaging timezone so an otherwise identical crate produces an
    # identical USDZ container on every build.
    canonical_mtime = 946684800  # 2000-01-01T00:00:00Z
    os.utime(source, (canonical_mtime, canonical_mtime))
    command = ["/usr/bin/usdzip", "--arkitAsset", str(source), str(destination)]
    environment = dict(os.environ)
    environment["TZ"] = "UTC"
    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
        env=environment,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "USDZ packaging failed\n"
            f"command: {' '.join(command)}\n"
            f"stdout: {result.stdout}\n"
            f"stderr: {result.stderr}"
        )


def verify_bindings(expected_path: Path | None, actual: dict[str, str]) -> None:
    if expected_path is None or not expected_path.exists():
        return
    declared = json.loads(expected_path.read_text(encoding="utf-8"))
    declared_map = {item["logicalName"]: item["primPath"] for item in declared["bindings"]}
    missing = sorted(set(declared_map) - set(actual))
    mismatched = sorted(
        logical for logical, path in declared_map.items() if actual.get(logical) != path
    )
    if missing or mismatched:
        raise RuntimeError(
            f"Entity binding contract changed. Missing={missing}; mismatched={mismatched}"
        )


def main() -> None:
    args = parse_args()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    build_scene()
    render_previews(output_dir)

    full = output_dir / "thessaly-household-store.usdc"
    lod1 = output_dir / "thessaly-household-store-lod1.usdc"
    lod2 = output_dir / "thessaly-household-store-lod2.usdc"
    export_usdc(full, 0)
    full_bindings = canonicalize_usd(full)
    export_usdc(lod1, 1)
    canonicalize_usd(lod1)
    export_usdc(lod2, 2)
    canonicalize_usd(lod2)
    write_ascii_usd(full, output_dir / "thessaly-household-store.usd")
    build_usdz(full, output_dir / "thessaly-household-store.usdz")
    verify_bindings(args.bindings, full_bindings)

    print(
        json.dumps(
            {
                "assetID": "chapter01-thessaly-household-store",
                "bindings": len(full_bindings),
                "objects": len(bpy.context.scene.objects),
                "materials": len(MATERIALS),
                "seed": str(SEED),
                "status": "BUILT",
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
