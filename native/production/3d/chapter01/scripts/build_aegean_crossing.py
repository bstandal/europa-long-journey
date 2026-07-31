#!/usr/bin/env python3
"""Deterministically build the Chapter 01 Aegean crossing cell in Blender 5.2.0.

The script is the authoritative source for the scene. No downloaded meshes,
textures, or opaque editor work are required. It emits a high-detail cell, a
mobile LOD, a review render, and RealityKit-oriented USD assets.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import traceback
from typing import Iterable, Sequence

import bmesh
import bpy
from mathutils import Matrix, Vector
from pxr import Gf, Sdf, Usd, UsdGeom


BLENDER_VERSION = "5.2.0"
BLENDER_BUILD_HASH = "fbe6228777e7"
ASSET_VERSION = "aegean-crossing-v1"
ROOT_RUNTIME_NAME = "western-anatolia-aegean"
ROOT_USD_NAME = "western_anatolia_aegean"
SEED = 20260730
FIXED_MTIME = 315532800  # 1980-01-01T00:00:00Z, valid in ZIP metadata.

SCRIPT_PATH = Path(__file__).resolve()
CHAPTER_ROOT = SCRIPT_PATH.parent.parent
ART_TARGET = CHAPTER_ROOT / "art-direction" / "aegean-crossing-target-v1.png"
OUTPUT_ROOT = CHAPTER_ROOT / "generated" / ASSET_VERSION
PREVIEW_ROOT = OUTPUT_ROOT / "preview"

EXPORT_COLLECTION: bpy.types.Collection
REVIEW_COLLECTION: bpy.types.Collection
LOD = 0


def stable_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_environment() -> None:
    version = bpy.app.version_string.split()[0]
    if version != BLENDER_VERSION:
        raise RuntimeError(f"Blender {BLENDER_VERSION} required, found {version}")
    if bpy.app.build_hash.decode("ascii") != BLENDER_BUILD_HASH:
        raise RuntimeError(
            f"Blender build {BLENDER_BUILD_HASH} required, found "
            f"{bpy.app.build_hash.decode('ascii')}"
        )
    if not ART_TARGET.is_file():
        raise RuntimeError(f"Missing art-direction target: {ART_TARGET}")


def reset_scene() -> None:
    global EXPORT_COLLECTION, REVIEW_COLLECTION
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(SEED)

    scene = bpy.context.scene
    bpy.context.preferences.filepaths.save_version = 0
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 540
    scene.render.resolution_y = 960
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 15
    scene.render.use_file_extension = True
    scene.render.resolution_percentage = 100
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"

    world = bpy.data.worlds.new("aegean-storm-world")
    scene.world = world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    links = world.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputWorld")
    output.location = (640, 0)
    background = nodes.new("ShaderNodeBackground")
    background.location = (390, 70)
    background.inputs["Strength"].default_value = 0.86
    texcoord = nodes.new("ShaderNodeTexCoord")
    texcoord.location = (-760, 40)
    separate = nodes.new("ShaderNodeSeparateXYZ")
    separate.location = (-570, -120)
    map_range = nodes.new("ShaderNodeMapRange")
    map_range.location = (-390, -150)
    map_range.inputs["From Min"].default_value = -0.08
    map_range.inputs["From Max"].default_value = 0.72
    map_range.inputs["To Min"].default_value = 0.0
    map_range.inputs["To Max"].default_value = 1.0
    map_range.clamp = True
    horizon = nodes.new("ShaderNodeValToRGB")
    horizon.location = (-170, -120)
    horizon.color_ramp.elements.remove(horizon.color_ramp.elements[1])
    horizon.color_ramp.elements[0].position = 0.0
    horizon.color_ramp.elements[0].color = (0.36, 0.235, 0.16, 1.0)
    mid = horizon.color_ramp.elements.new(0.22)
    mid.color = (0.22, 0.235, 0.245, 1.0)
    upper = horizon.color_ramp.elements.new(0.58)
    upper.color = (0.095, 0.12, 0.14, 1.0)
    top = horizon.color_ramp.elements.new(0.88)
    top.color = (0.055, 0.075, 0.09, 1.0)
    noise = nodes.new("ShaderNodeTexNoise")
    noise.location = (-420, 145)
    noise.noise_dimensions = "4D"
    noise.inputs["Scale"].default_value = 1.55
    noise.inputs["Detail"].default_value = 8.0
    noise.inputs["Roughness"].default_value = 0.78
    noise.inputs["Distortion"].default_value = 0.28
    noise.inputs["W"].default_value = 0.314159
    clouds = nodes.new("ShaderNodeValToRGB")
    clouds.location = (-160, 170)
    clouds.color_ramp.elements[0].position = 0.24
    clouds.color_ramp.elements[0].color = (0.08, 0.10, 0.12, 1.0)
    clouds.color_ramp.elements[1].position = 0.78
    clouds.color_ramp.elements[1].color = (0.44, 0.46, 0.47, 1.0)
    mix = nodes.new("ShaderNodeMixRGB")
    mix.location = (130, 75)
    mix.blend_type = "MIX"
    mix.inputs[0].default_value = 0.58
    links.new(texcoord.outputs["Normal"], separate.inputs["Vector"])
    links.new(separate.outputs["Z"], map_range.inputs["Value"])
    links.new(map_range.outputs["Result"], horizon.inputs["Fac"])
    links.new(texcoord.outputs["Normal"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], clouds.inputs["Fac"])
    links.new(horizon.outputs["Color"], mix.inputs[1])
    links.new(clouds.outputs["Color"], mix.inputs[2])
    links.new(mix.outputs["Color"], background.inputs["Color"])
    links.new(background.outputs["Background"], output.inputs["Surface"])

    volume = nodes.new("ShaderNodeVolumePrincipled")
    volume.location = (380, -190)
    volume.inputs["Color"].default_value = (0.10, 0.14, 0.16, 1.0)
    volume.inputs["Density"].default_value = 0.0025
    volume.inputs["Anisotropy"].default_value = 0.22
    links.new(volume.outputs["Volume"], output.inputs["Volume"])

    EXPORT_COLLECTION = bpy.data.collections.new("EXPORT_AEGEAN")
    REVIEW_COLLECTION = bpy.data.collections.new("REVIEW_ONLY")
    scene.collection.children.link(EXPORT_COLLECTION)
    scene.collection.children.link(REVIEW_COLLECTION)


def link_export(obj: bpy.types.Object) -> bpy.types.Object:
    for collection in tuple(obj.users_collection):
        collection.objects.unlink(obj)
    EXPORT_COLLECTION.objects.link(obj)
    return obj


def link_review(obj: bpy.types.Object) -> bpy.types.Object:
    for collection in tuple(obj.users_collection):
        collection.objects.unlink(obj)
    REVIEW_COLLECTION.objects.link(obj)
    return obj


def semantic(obj: bpy.types.Object, runtime_name: str | None = None, **properties) -> None:
    canonical = runtime_name or obj.name
    obj["runtime_name"] = canonical
    obj["asset_version"] = ASSET_VERSION
    obj["lod_level"] = LOD
    for key, value in properties.items():
        obj[key] = value


def empty(name: str, location=(0.0, 0.0, 0.0), parent=None, **properties):
    obj = bpy.data.objects.new(name, None)
    link_export(obj)
    obj.location = location
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.18
    if parent is not None:
        obj.parent = parent
    semantic(obj, name, **properties)
    return obj


def mesh_object(
    name: str,
    vertices: Sequence[Sequence[float]],
    faces: Sequence[Sequence[int]],
    material: bpy.types.Material | None = None,
    parent=None,
    smooth=True,
    **properties,
):
    mesh = bpy.data.meshes.new(f"{name}-geometry")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate(verbose=False)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    link_export(obj)
    if parent is not None:
        obj.parent = parent
    if material is not None:
        obj.data.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    semantic(obj, name, **properties)
    return obj


def set_principled_input(node, name: str, value) -> None:
    socket = node.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def material(
    name: str,
    dark: tuple[float, float, float, float],
    light: tuple[float, float, float, float],
    roughness: float,
    noise_scale: float,
    bump_strength: float,
    metallic: float = 0.0,
    transmission: float = 0.0,
    alpha: float = 1.0,
    coat_weight: float = 0.0,
    coat_roughness: float = 0.25,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = light
    mat.metallic = metallic
    mat.roughness = roughness
    mat["runtime_name"] = name
    mat["pbr_authoring"] = "procedural-noise-color-bump+usd-preview-surface"
    mat["commercial_rights"] = "project-authored-no-external-assets"
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (520, 0)
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.location = (250, 0)
    set_principled_input(principled, "Base Color", light)
    set_principled_input(principled, "Metallic", metallic)
    set_principled_input(principled, "Roughness", roughness)
    set_principled_input(principled, "Transmission Weight", transmission)
    set_principled_input(principled, "Alpha", alpha)
    set_principled_input(principled, "Coat Weight", coat_weight)
    set_principled_input(principled, "Coat Roughness", coat_roughness)

    texcoord = nodes.new("ShaderNodeTexCoord")
    texcoord.location = (-720, 0)
    noise = nodes.new("ShaderNodeTexNoise")
    noise.location = (-520, 70)
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 5.0 if LOD == 0 else 2.0
    noise.inputs["Roughness"].default_value = 0.68
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.location = (-260, 125)
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = dark
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = light
    bump = nodes.new("ShaderNodeBump")
    bump.location = (20, -170)
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.07

    links.new(texcoord.outputs["Generated"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], principled.inputs["Base Color"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], principled.inputs["Normal"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    if alpha < 1.0:
        mat.surface_render_method = "DITHERED"
    return mat


def build_materials() -> dict[str, bpy.types.Material]:
    mats = {
        "wood": material("mat-weathered-oak", (0.045, 0.025, 0.014, 1), (0.24, 0.12, 0.055, 1), 0.76, 3.3, 0.34),
        "wet_wood": material("mat-wet-oak", (0.025, 0.016, 0.010, 1), (0.20, 0.095, 0.036, 1), 0.31, 4.5, 0.26, coat_weight=0.48, coat_roughness=0.20),
        "rope": material("mat-hemp-rope", (0.19, 0.105, 0.040, 1), (0.66, 0.43, 0.17, 1), 0.91, 24.0, 0.45),
        "pottery": material("mat-fired-clay", (0.12, 0.035, 0.017, 1), (0.46, 0.16, 0.065, 1), 0.79, 7.0, 0.30),
        "pottery_dark": material("mat-smoke-fired-clay", (0.035, 0.027, 0.022, 1), (0.18, 0.10, 0.065, 1), 0.72, 9.0, 0.24),
        "reed": material("mat-woven-reed", (0.12, 0.06, 0.015, 1), (0.53, 0.31, 0.095, 1), 0.88, 17.0, 0.32),
        "cloth": material("mat-raw-wool", (0.075, 0.050, 0.032, 1), (0.34, 0.25, 0.16, 1), 0.82, 42.0, 0.38, coat_weight=0.08, coat_roughness=0.50),
        "cloth_warm": material("mat-ochre-wool", (0.10, 0.045, 0.018, 1), (0.42, 0.19, 0.060, 1), 0.78, 38.0, 0.34, coat_weight=0.10, coat_roughness=0.47),
        "cloth_grey": material("mat-ash-wool", (0.052, 0.050, 0.045, 1), (0.26, 0.24, 0.20, 1), 0.80, 41.0, 0.36, coat_weight=0.09, coat_roughness=0.48),
        "wet_cloth": material("mat-rain-darkened-wool", (0.030, 0.026, 0.020, 1), (0.22, 0.16, 0.095, 1), 0.68, 35.0, 0.33, coat_weight=0.16, coat_roughness=0.38),
        "skin": material("mat-weathered-skin", (0.19, 0.082, 0.044, 1), (0.66, 0.34, 0.17, 1), 0.64, 8.0, 0.13),
        "wet_skin": material("mat-rain-wet-skin", (0.16, 0.060, 0.031, 1), (0.58, 0.27, 0.12, 1), 0.38, 8.0, 0.11, coat_weight=0.38, coat_roughness=0.22),
        "hair": material("mat-dark-hair", (0.012, 0.008, 0.005, 1), (0.055, 0.026, 0.012, 1), 0.85, 55.0, 0.30),
        "hide": material("mat-young-bovine-hide", (0.07, 0.025, 0.012, 1), (0.32, 0.12, 0.045, 1), 0.88, 19.0, 0.40),
        "hide_light": material("mat-young-bovine-rain-highlight", (0.095, 0.038, 0.018, 1), (0.39, 0.17, 0.065, 1), 0.62, 21.0, 0.34, coat_weight=0.14, coat_roughness=0.38),
        "muzzle": material("mat-bovine-muzzle", (0.055, 0.038, 0.032, 1), (0.24, 0.16, 0.13, 1), 0.65, 13.0, 0.18),
        "earth": material("mat-aegean-earth", (0.052, 0.050, 0.040, 1), (0.22, 0.20, 0.135, 1), 0.97, 2.2, 0.55),
        "wet_earth": material("mat-wet-shore-earth", (0.034, 0.040, 0.036, 1), (0.14, 0.15, 0.105, 1), 0.58, 3.5, 0.42, coat_weight=0.18, coat_roughness=0.42),
        "rock": material("mat-limestone", (0.095, 0.095, 0.086, 1), (0.38, 0.37, 0.32, 1), 0.92, 4.1, 0.46),
        "foliage": material("mat-olive-scrub", (0.018, 0.036, 0.024, 1), (0.12, 0.17, 0.085, 1), 0.88, 12.0, 0.32),
        "water": material("mat-storm-water", (0.004, 0.020, 0.030, 1), (0.045, 0.17, 0.21, 1), 0.34, 7.5, 0.34, transmission=0.04, coat_weight=0.26, coat_roughness=0.16),
        "current": material("mat-current-foam", (0.018, 0.052, 0.060, 0.38), (0.11, 0.18, 0.19, 0.48), 0.58, 16.0, 0.16, alpha=0.46),
        "foam": material("mat-wave-foam", (0.20, 0.26, 0.26, 0.72), (0.80, 0.82, 0.76, 0.94), 0.66, 20.0, 0.28, alpha=0.90),
        "rain": material("mat-rain-streak", (0.12, 0.16, 0.18, 0.08), (0.34, 0.39, 0.40, 0.16), 0.30, 9.0, 0.03, transmission=0.12, alpha=0.16),
        "sky": material("mat-storm-sky", (0.018, 0.026, 0.034, 1), (0.055, 0.066, 0.078, 1), 1.0, 5.2, 0.0),
        "grain": material("mat-emmer-grain", (0.21, 0.11, 0.025, 1), (0.72, 0.44, 0.105, 1), 0.84, 22.0, 0.24),
        "eye": material("mat-eye-dark", (0.003, 0.002, 0.001, 1), (0.015, 0.008, 0.004, 1), 0.28, 7.0, 0.05),
    }
    sky_nodes = mats["sky"].node_tree.nodes
    sky_principled = next(node for node in sky_nodes if node.bl_idname == "ShaderNodeBsdfPrincipled")
    sky_ramp = next(node for node in sky_nodes if node.bl_idname == "ShaderNodeValToRGB")
    sky_ramp.color_ramp.elements[0].position = 0.39
    sky_ramp.color_ramp.elements[0].color = (0.018, 0.026, 0.034, 1.0)
    sky_ramp.color_ramp.elements[1].position = 0.63
    sky_ramp.color_ramp.elements[1].color = (0.055, 0.066, 0.078, 1.0)
    # USD Preview Surface cannot preserve Blender's procedural sky ramp.
    # Author a restrained constant emission fallback so RealityKit sees a
    # storm-dark dome rather than either the renderer's black clear colour or
    # the previous clipped near-white shell.
    set_principled_input(
        sky_principled,
        "Emission Color",
        (0.040, 0.050, 0.064, 1.0),
    )
    set_principled_input(sky_principled, "Emission Strength", 0.66)
    return mats


def add_primitive(
    kind: str,
    name: str,
    location,
    scale,
    mat,
    parent=None,
    rotation=(0.0, 0.0, 0.0),
    segments: int | None = None,
    **properties,
):
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=segments or (32 if LOD == 0 else 14),
            ring_count=(20 if LOD == 0 else 8),
            location=location,
            rotation=rotation,
        )
    elif kind == "ico":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=(3 if LOD == 0 else 1), location=location)
    elif kind == "cube":
        bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    elif kind == "cylinder":
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=segments or (24 if LOD == 0 else 10),
            radius=1.0,
            depth=2.0,
            location=location,
            rotation=rotation,
        )
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(
            vertices=segments or (24 if LOD == 0 else 10),
            radius1=1.0,
            radius2=0.0,
            depth=2.0,
            location=location,
            rotation=rotation,
        )
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(
            major_radius=1.0,
            minor_radius=0.08,
            major_segments=segments or (36 if LOD == 0 else 14),
            minor_segments=(8 if LOD == 0 else 4),
            location=location,
            rotation=rotation,
        )
    else:
        raise ValueError(kind)
    obj = bpy.context.object
    obj.name = name
    link_export(obj)
    obj.scale = scale
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat is not None:
        obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
    for polygon in obj.data.polygons:
        polygon.use_smooth = kind not in {"cube"}
    semantic(obj, name, **properties)
    return obj


def cylinder_between(name, start, end, radius, mat, parent=None, segments=None, **properties):
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    midpoint = (a + b) * 0.5
    obj = add_primitive(
        "cylinder",
        name,
        midpoint,
        (radius, radius, direction.length * 0.5),
        mat,
        parent,
        segments=segments,
        **properties,
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def tapered_limb(name, start, end, start_radius, end_radius, mat, parent=None, sides=None, **properties):
    a = Vector(start)
    b = Vector(end)
    direction = (b - a).normalized()
    reference = Vector((0.0, 0.0, 1.0))
    if abs(direction.dot(reference)) > 0.88:
        reference = Vector((0.0, 1.0, 0.0))
    side = direction.cross(reference).normalized()
    normal = side.cross(direction).normalized()
    sides = sides or (18 if LOD == 0 else 8)
    ring_t = (0.0, 0.18, 0.52, 0.84, 1.0)
    radii = (
        start_radius * 0.88,
        start_radius,
        start_radius * 0.84 + end_radius * 0.16,
        end_radius,
        end_radius * 0.86,
    )
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for ring_index, t in enumerate(ring_t):
        center = a.lerp(b, t)
        center += normal * (0.018 * math.sin(math.pi * t))
        radius = radii[ring_index]
        for index in range(sides):
            angle = 2 * math.pi * index / sides
            point = center + radius * (math.cos(angle) * side + math.sin(angle) * normal)
            vertices.append(tuple(point))
    for ring_index in range(len(ring_t) - 1):
        for index in range(sides):
            a_index = ring_index * sides + index
            b_index = ring_index * sides + (index + 1) % sides
            c_index = (ring_index + 1) * sides + (index + 1) % sides
            d_index = (ring_index + 1) * sides + index
            faces.append((a_index, b_index, c_index, d_index))
    faces.append(tuple(range(sides - 1, -1, -1)))
    final_ring = (len(ring_t) - 1) * sides
    faces.append(tuple(final_ring + index for index in range(sides)))
    return mesh_object(name, vertices, faces, mat, parent, True, **properties)


def swept_tube(name, points, radius, sides, mat, parent=None, offsets=None, **properties):
    path = [Vector(p) for p in points]
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    offsets = offsets or [(0.0, 0.0)] * len(path)
    for index, point in enumerate(path):
        if index == 0:
            tangent = (path[1] - point).normalized()
        elif index == len(path) - 1:
            tangent = (point - path[index - 1]).normalized()
        else:
            tangent = (path[index + 1] - path[index - 1]).normalized()
        reference = Vector((0.0, 0.0, 1.0))
        if abs(tangent.dot(reference)) > 0.92:
            reference = Vector((0.0, 1.0, 0.0))
        side = tangent.cross(reference).normalized()
        normal = side.cross(tangent).normalized()
        center = point + side * offsets[index][0] + normal * offsets[index][1]
        for ring_index in range(sides):
            angle = 2.0 * math.pi * ring_index / sides
            p = center + radius * (math.cos(angle) * side + math.sin(angle) * normal)
            vertices.append(tuple(p))
    for segment in range(len(path) - 1):
        for side_index in range(sides):
            a = segment * sides + side_index
            b = segment * sides + (side_index + 1) % sides
            c = (segment + 1) * sides + (side_index + 1) % sides
            d = (segment + 1) * sides + side_index
            faces.append((a, b, c, d))
    faces.append(tuple(range(sides - 1, -1, -1)))
    end = (len(path) - 1) * sides
    faces.append(tuple(end + i for i in range(sides)))
    return mesh_object(name, vertices, faces, mat, parent, True, **properties)


def lathe(name, profile, sides, mat, parent=None, location=(0, 0, 0), **properties):
    vertices = []
    faces = []
    for z, radius in profile:
        for side in range(sides):
            angle = 2 * math.pi * side / sides
            vertices.append((location[0] + radius * math.cos(angle), location[1] + radius * math.sin(angle), location[2] + z))
    for row in range(len(profile) - 1):
        for side in range(sides):
            a = row * sides + side
            b = row * sides + (side + 1) % sides
            c = (row + 1) * sides + (side + 1) % sides
            d = (row + 1) * sides + side
            faces.append((a, b, c, d))
    faces.append(tuple(range(sides - 1, -1, -1)))
    end = (len(profile) - 1) * sides
    faces.append(tuple(end + i for i in range(sides)))
    return mesh_object(name, vertices, faces, mat, parent, True, **properties)


def build_sky_dome(mats):
    dome = add_primitive(
        "sphere",
        "storm-sky-dome",
        (0.0, 3.0, 6.0),
        (34.0, 34.0, 25.0),
        mats["sky"],
        segments=64 if LOD == 0 else 28,
        environmental_role="storm-sky",
        lod_policy="background-shell",
    )
    # RealityKit culls the outward-facing triangles of a conventional sphere
    # when the virtual camera is inside it. Author the dome as an interior
    # surface so the storm sky survives USDZ import instead of exposing the
    # renderer's black clear colour.
    mesh = dome.data
    editable = bmesh.new()
    editable.from_mesh(mesh)
    bmesh.ops.reverse_faces(editable, faces=list(editable.faces))
    editable.to_mesh(mesh)
    editable.free()
    mesh.update()
    dome["surface_orientation"] = "inward"
    dome["animation_channel"] = "aegean-cloud-drift"
    return dome


def water_height(x: float, y: float) -> float:
    long_swell = 0.145 * math.sin(0.68 * x + 0.54 * y)
    cross_chop = 0.072 * math.sin(2.15 * x - 1.08 * y + 0.35)
    fine = 0.026 * math.sin(4.7 * x + 2.25 * y)
    return -0.31 + long_swell + cross_chop + fine


def build_water(mats):
    columns = 58 if LOD == 0 else 21
    rows = 48 if LOD == 0 else 16
    width, depth = 23.0, 34.0
    vertices = []
    for row in range(rows):
        y = -12.0 + depth * row / (rows - 1)
        for col in range(columns):
            x = -width * 0.5 + width * col / (columns - 1)
            z = water_height(x, y)
            vertices.append((x, y, z))
    faces = []
    for row in range(rows - 1):
        for col in range(columns - 1):
            a = row * columns + col
            faces.append((a, a + 1, a + 1 + columns, a + columns))
    water = mesh_object("water-surface", vertices, faces, mats["water"], environmental_role="water")
    water["animation_channel"] = "aegean-current-displacement"

    for index in range(4):
        points = []
        count = 25 if LOD == 0 else 9
        for step in range(count):
            y = -6.4 + step * 0.72
            x = -5.0 + index * 3.05 + 0.54 * math.sin(step * 0.51 + index * 1.7)
            z = water_height(x, y) + 0.075
            points.append((x, y, z))
        swept_tube(
            f"current-{index}",
            points,
            0.022 if LOD == 0 else 0.042,
            5 if LOD == 0 else 4,
            mats["current"],
            current_index=index,
            animation_channel=f"current-{index}-flow",
        )

    crest_count = 13 if LOD == 0 else 4
    for index in range(crest_count):
        center_x = -7.2 + ((index * 31) % 144) / 10.0
        center_y = -8.0 + ((index * 47) % 130) / 10.0
        span = 0.42 + ((index * 17) % 25) / 35.0
        points = []
        samples = 9 if LOD == 0 else 4
        for step in range(samples):
            t = step / max(samples - 1, 1)
            x = center_x + (t - 0.5) * span * 2.0
            y = center_y + 0.15 * math.sin(t * math.pi + index)
            points.append((x, y, water_height(x, y) + 0.11 + 0.025 * math.sin(t * math.pi)))
        swept_tube(
            f"wave-crest-{index:02d}",
            points,
            0.018 if LOD == 0 else 0.030,
            5 if LOD == 0 else 4,
            mats["foam"],
            environmental_role="whitecap",
            animation_channel="aegean-wave-foam",
        )

    if LOD == 0:
        rain_vertices: list[tuple[float, float, float]] = []
        rain_faces: list[tuple[int, int, int, int]] = []
        for index in range(48):
            x = -8.5 + ((index * 73) % 170) / 10.0
            y = -6.0 + ((index * 97) % 180) / 10.0
            z = 0.9 + ((index * 43) % 55) / 10.0
            length = 0.18 + ((index * 19) % 14) / 40.0
            width_streak = 0.002 + (index % 3) * 0.001
            base = len(rain_vertices)
            rain_vertices.extend(
                [
                    (x - width_streak, y, z),
                    (x + width_streak, y, z),
                    (x + 0.14 + width_streak, y + 0.05, z - length),
                    (x + 0.14 - width_streak, y + 0.05, z - length),
                ]
            )
            rain_faces.append((base, base + 1, base + 2, base + 3))
        mesh_object(
            "storm-rain",
            rain_vertices,
            rain_faces,
            mats["rain"],
            smooth=False,
            environmental_role="weather-vfx",
            animation_channel="aegean-rain-drift",
        )


def coastline_y(x: float) -> float:
    return 4.85 + 0.42 * math.sin(x * 0.41) + 0.18 * math.sin(x * 1.17 + 0.8)


def terrain_height(x: float, y: float) -> float:
    inland = max(0.0, y - coastline_y(x))
    beach = 0.075 * inland
    rising_ground = 0.0065 * inland * inland
    folded_ridge = max(0.0, math.sin(0.31 * x + 0.18 * y) + 0.38 * math.sin(0.83 * x - 0.21 * y))
    ridge = folded_ridge * min(1.0, inland / 7.0) * 0.92
    headland = 1.55 * math.exp(-(((x - 6.2) / 3.7) ** 2 + ((y - 16.2) / 5.5) ** 2))
    western_mass = 1.05 * math.exp(-(((x + 7.5) / 4.4) ** 2 + ((y - 18.5) / 6.5) ** 2))
    erosion = 0.13 * math.sin(x * 1.55 + y * 0.44) * min(1.0, inland / 3.0)
    return -0.24 + beach + rising_ground + ridge + headland + western_mass + erosion


def build_shore(mats):
    columns = 46 if LOD == 0 else 16
    rows = 36 if LOD == 0 else 12
    vertices = []
    for row in range(rows):
        y = 5.0 + 18.0 * row / (rows - 1)
        for col in range(columns):
            x = -11.0 + 22.0 * col / (columns - 1)
            vertices.append((x, y, terrain_height(x, y)))
    faces = []
    for row in range(rows - 1):
        for col in range(columns - 1):
            a = row * columns + col
            faces.append((a, a + 1, a + 1 + columns, a + columns))
    shore = mesh_object(
        "western-shore",
        vertices,
        faces,
        mats["earth"],
        transition_destination=True,
        carrier_accepts="seed-vessel",
    )

    band_vertices: list[tuple[float, float, float]] = []
    band_faces: list[tuple[int, int, int, int]] = []
    band_columns = 42 if LOD == 0 else 14
    for row, offset in enumerate((0.03, 0.58, 1.22)):
        for col in range(band_columns):
            x = -11.0 + 22.0 * col / (band_columns - 1)
            y = coastline_y(x) + offset
            band_vertices.append((x, y, terrain_height(x, y) + 0.014))
    for row in range(2):
        for col in range(band_columns - 1):
            a = row * band_columns + col
            band_faces.append((a, a + 1, a + 1 + band_columns, a + band_columns))
    mesh_object(
        "western-shore-wet-band",
        band_vertices,
        band_faces,
        mats["wet_earth"],
        shore,
        smooth=True,
        environmental_role="waterline",
    )

    rock_count = 54 if LOD == 0 else 14
    for index in range(rock_count):
        x = -9.5 + ((index * 37) % 190) / 10.0
        y = 5.7 + ((index * 53) % 120) / 10.0
        z = terrain_height(x, y) + 0.10
        scale = 0.14 + ((index * 17) % 21) / 70.0
        rock = add_primitive("ico", f"shore-rock-{index:02d}", (x, y, z), (scale * 1.75, scale, scale * 0.74), mats["rock"], shore)
        rock.rotation_euler = (0.2 * math.sin(index), 0.15 * math.cos(index), index * 0.47)

    tree_count = 18 if LOD == 0 else 5
    for index in range(tree_count):
        x = -8.0 + ((index * 41) % 160) / 10.0
        y = 9.0 + ((index * 29) % 100) / 10.0
        z = terrain_height(x, y)
        trunk = cylinder_between(f"shore-scrub-{index:02d}-trunk", (x, y, z), (x, y, z + 0.75), 0.07, mats["wood"], shore)
        add_primitive("ico", f"shore-scrub-{index:02d}-crown", (x, y, z + 0.84), (0.48, 0.34, 0.27), mats["foliage"], shore)

    outcrop_count = 7 if LOD == 0 else 3
    for index in range(outcrop_count):
        x = -8.2 + index * 2.8
        y = 12.4 + (index % 3) * 2.2
        z = terrain_height(x, y) + 0.6
        outcrop = add_primitive(
            "ico",
            f"ridge-outcrop-{index:02d}",
            (x, y, z),
            (1.35 + 0.18 * (index % 2), 0.72, 0.82 + 0.11 * (index % 3)),
            mats["rock"],
            shore,
        )
        outcrop.rotation_euler = (0.10 * index, -0.08 * index, 0.39 * index)


def boat_path(station_count: int):
    stations = []
    for index in range(station_count):
        t = index / (station_count - 1)
        x = -4.7 + 9.4 * t
        width = 0.17 + 1.22 * (math.sin(math.pi * t) ** 0.58)
        sheer = 0.72 + 0.34 * abs(2 * t - 1) ** 2.3
        stations.append((x, width, sheer))
    return stations


def build_hull_side(name, stations, sign, mat, parent):
    vertices = []
    levels = ((0.04, -0.33), (0.60, -0.11), (0.88, 0.34), (1.0, 0.0))
    for x, width, sheer in stations:
        for width_factor, z_offset in levels:
            vertices.append((x, sign * width * width_factor, z_offset + (sheer if width_factor == 1.0 else 0.0)))
    faces = []
    count = len(levels)
    for station in range(len(stations) - 1):
        for level in range(count - 1):
            a = station * count + level
            if sign > 0:
                faces.append((a, a + count, a + count + 1, a + 1))
            else:
                faces.append((a, a + 1, a + count + 1, a + count))
    obj = mesh_object(name, vertices, faces, mat, parent, True, material_role="boat-hull")
    solidify = obj.modifiers.new("hull-plank-thickness", "SOLIDIFY")
    solidify.thickness = 0.075 if LOD == 0 else 0.10
    solidify.offset = -0.25
    bevel = obj.modifiers.new("worn-hull-edges", "BEVEL")
    bevel.width = 0.022
    bevel.segments = 2 if LOD == 0 else 1
    return obj


def build_boat(mats):
    boat = empty("crossing-boat", semantic_role="transport", period="early-neolithic-aegean")
    stations = boat_path(19 if LOD == 0 else 9)
    build_hull_side("crossing-boat-port-hull", stations, 1, mats["wet_wood"], boat)
    build_hull_side("crossing-boat-starboard-hull", stations, -1, mats["wet_wood"], boat)

    seam_levels = ((0.48, 0.14), (0.74, 0.38), (0.94, 0.64)) if LOD == 0 else ((0.72, 0.38),)
    for sign, side_name in ((1, "port"), (-1, "starboard")):
        for seam_index, (width_factor, z_factor) in enumerate(seam_levels):
            points = []
            for x, width, sheer in stations:
                points.append((x, sign * width * width_factor, -0.20 + sheer * z_factor))
            swept_tube(f"boat-{side_name}-plank-seam-{seam_index}", points, 0.018, 5, mats["wood"], boat)
        gunwale_points = [(x, sign * width, sheer) for x, width, sheer in stations]
        swept_tube(f"boat-{side_name}-gunwale", gunwale_points, 0.075, 8 if LOD == 0 else 5, mats["wood"], boat)

    rib_indices = (2, 4, 6, 8, 10, 12, 14, 16) if LOD == 0 else (2, 4, 6)
    for rib_number, station_index in enumerate(rib_indices):
        x, width, sheer = stations[min(station_index, len(stations) - 2)]
        points = [
            (x, -width * 0.92, sheer - 0.04),
            (x, -width * 0.62, 0.05),
            (x, 0.0, -0.24),
            (x, width * 0.62, 0.05),
            (x, width * 0.92, sheer - 0.04),
        ]
        swept_tube(f"boat-rib-{rib_number:02d}", points, 0.052, 7 if LOD == 0 else 5, mats["wood"], boat)

    floor_count = 7 if LOD == 0 else 3
    for index in range(floor_count):
        y = -0.63 + index * (1.26 / max(floor_count - 1, 1))
        plank = add_primitive("cube", f"boat-floor-plank-{index:02d}", (0, y, -0.08), (3.55, 0.075, 0.045), mats["wood"], boat)
        bevel = plank.modifiers.new("worn-plank", "BEVEL")
        bevel.width = 0.025
        bevel.segments = 2 if LOD == 0 else 1

    for index, x in enumerate((-4.58, 4.58)):
        swept_tube(
            f"boat-end-post-{index}",
            [(x, 0, -0.2), (x + (-0.15 if x < 0 else 0.15), 0, 0.72), (x + (-0.36 if x < 0 else 0.36), 0, 1.42)],
            0.09,
            8 if LOD == 0 else 5,
            mats["wood"],
            boat,
        )
    return boat


def build_action_rope(mats):
    count = 46 if LOD == 0 else 18
    points = []
    for index in range(count):
        t = index / (count - 1)
        x = 7.3 - 12.2 * t
        y = -3.6 + 4.12 * t + 0.16 * math.sin(t * math.pi * 2)
        z = 1.15 + 0.28 * math.sin(t * math.pi) + 0.07 * math.sin(t * math.pi * 5)
        points.append((x, y, z))
    action = swept_tube(
        "action-crossing-line",
        points,
        0.052,
        12 if LOD == 0 else 7,
        mats["rope"],
        semantic_role="primary-interaction",
        interaction_id="first-farmers-household-route",
        collision_ready=True,
        collision_shape="mesh",
        manipulation_axis="line-tension",
    )
    if LOD == 0:
        for strand in range(3):
            offsets = []
            for index in range(count):
                angle = 2 * math.pi * (index / 5.5 + strand / 3)
                offsets.append((0.052 * math.cos(angle), 0.052 * math.sin(angle)))
            swept_tube(f"action-crossing-line-braid-{strand}", points, 0.014, 6, mats["rope"], action, offsets=offsets, render_detail=True)
    return action


def build_seed_vessel(mats):
    profile = [
        (0.00, 0.24), (0.06, 0.38), (0.20, 0.55), (0.55, 0.67),
        (0.86, 0.60), (1.08, 0.42), (1.21, 0.28), (1.33, 0.29), (1.39, 0.36),
    ]
    vessel = lathe(
        "seed-vessel",
        profile,
        44 if LOD == 0 else 18,
        mats["pottery"],
        location=(-0.65, -0.62, 0.04),
        semantic_role="transition-carrier",
        contents="emmer-and-einkorn-seed",
        action_binding="protect-seed",
    )
    add_primitive("torus", "seed-vessel-lip", (-0.65, -0.62, 1.43), (0.37, 0.37, 0.10), mats["pottery_dark"], vessel)
    lid = lathe("seed-vessel-lid", [(0, 0.31), (0.06, 0.36), (0.14, 0.24), (0.21, 0.08)], 36 if LOD == 0 else 14, mats["pottery_dark"], vessel, location=(-0.65, -0.62, 1.42))
    lid["detachable"] = True

    ring_count = 5 if LOD == 0 else 2
    for index in range(ring_count):
        z = 0.30 + index * 0.22
        radius = 0.63 - 0.05 * abs(index - 2)
        add_primitive("torus", f"seed-vessel-net-ring-{index}", (-0.65, -0.62, z), (radius, radius, 0.04), mats["rope"], vessel)
    if LOD == 0:
        for index in range(8):
            angle = 2 * math.pi * index / 8
            points = []
            for step in range(9):
                t = step / 8
                z = 0.12 + t * 1.22
                radius = 0.38 + 0.27 * math.sin(math.pi * t)
                points.append((-0.65 + radius * math.cos(angle), -0.62 + radius * math.sin(angle), z))
            swept_tube(f"seed-vessel-net-strand-{index}", points, 0.022, 5, mats["rope"], vessel)
    return vessel


def build_basket(name, location, scale, mats, parent):
    # Children below are authored in cell coordinates, so the semantic parent
    # remains at identity to avoid a second translation at export.
    basket = empty(name, (0.0, 0.0, 0.0), parent, semantic_role="cargo")
    rings = 8 if LOD == 0 else 3
    for index in range(rings):
        z = index * 0.085
        radius = scale * (0.72 + 0.16 * index / max(rings - 1, 1))
        add_primitive("torus", f"{name}-weft-{index:02d}", (location[0], location[1], location[2] + z), (radius, radius, scale * 0.035), mats["reed"], basket, segments=30 if LOD == 0 else 12)
    stakes = 14 if LOD == 0 else 6
    for index in range(stakes):
        angle = 2 * math.pi * index / stakes
        x = location[0] + scale * 0.72 * math.cos(angle)
        y = location[1] + scale * 0.72 * math.sin(angle)
        cylinder_between(f"{name}-warp-{index:02d}", (x, y, location[2]), (x * 0 + location[0] + scale * 0.88 * math.cos(angle), y * 0 + location[1] + scale * 0.88 * math.sin(angle), location[2] + 0.65), scale * 0.022, mats["reed"], basket, segments=6)
    add_primitive("sphere", f"{name}-grain-load", (location[0], location[1], location[2] + 0.54), (scale * 0.72, scale * 0.72, scale * 0.18), mats["grain"], basket)
    return basket


def build_cargo(mats, boat):
    build_basket("basket-cargo-0", (1.30, -0.47, 0.03), 0.58, mats, boat)
    build_basket("basket-cargo-1", (2.18, 0.44, 0.05), 0.44, mats, boat)
    sack_positions = ((-2.8, -0.64, 0.20), (-2.35, -0.48, 0.22), (2.75, 0.42, 0.20))
    for index, position in enumerate(sack_positions):
        sack = add_primitive("sphere", f"cargo-sack-{index}", position, (0.44, 0.31, 0.48), mats["cloth"], boat, semantic_role="cargo")
        cylinder_between(f"cargo-sack-{index}-tie", (position[0] - 0.16, position[1], position[2] + 0.33), (position[0] + 0.16, position[1], position[2] + 0.33), 0.026, mats["rope"], sack)


def garment_frustum(name, center, height, lower_radius, upper_radius, mat, parent, segments=None):
    segments = segments or (32 if LOD == 0 else 12)
    rings = 7 if LOD == 0 else 3
    vertices = []
    for ring in range(rings):
        t = ring / (rings - 1)
        z = -height * 0.5 + height * t
        radius = lower_radius * (1.0 - t) + upper_radius * t
        if t < 0.2:
            radius *= 1.0 + 0.08 * (1.0 - t / 0.2)
        for index in range(segments):
            angle = 2 * math.pi * index / segments
            fold = 1.0 + (0.055 if LOD == 0 else 0.025) * math.sin(angle * 6 + t * 1.7)
            vertices.append((radius * fold * math.cos(angle), radius * 0.72 * (2.0 - fold) * math.sin(angle), z))
    faces = []
    for ring in range(rings - 1):
        for index in range(segments):
            a = ring * segments + index
            faces.append((a, ring * segments + (index + 1) % segments, (ring + 1) * segments + (index + 1) % segments, (ring + 1) * segments + index))
    faces.append(tuple(range(segments - 1, -1, -1)))
    obj = mesh_object(name, vertices, faces, mat, parent, True)
    obj.location = center
    solidify = obj.modifiers.new("cloth-thickness", "SOLIDIFY")
    solidify.thickness = 0.014 if LOD == 0 else 0.022
    solidify.offset = 0.0
    bevel = obj.modifiers.new("softened-cloth-edges", "BEVEL")
    bevel.width = 0.012
    bevel.segments = 2 if LOD == 0 else 1
    return obj


def build_hand(name, position, mats, parent, semantic_role="contact-hand"):
    x, y, z = position
    hand = add_primitive(
        "sphere",
        name,
        position,
        (0.088, 0.058, 0.105),
        mats["wet_skin"],
        parent,
        semantic_role=semantic_role,
        segments=24 if LOD == 0 else 12,
    )
    if LOD == 0:
        for index in range(4):
            finger_x = x + (index - 1.5) * 0.031
            tapered_limb(
                f"{name}-finger-{index}",
                (finger_x, y - 0.036, z + 0.012),
                (finger_x + 0.006, y - 0.010, z - 0.105),
                0.0145,
                0.010,
                mats["wet_skin"],
                parent,
                sides=8,
            )
        tapered_limb(
            f"{name}-thumb",
            (x - 0.065, y - 0.005, z + 0.005),
            (x - 0.105, y - 0.035, z - 0.052),
            0.021,
            0.014,
            mats["wet_skin"],
            parent,
            sides=8,
        )
    return hand


def build_person(name, role, joints, cloth_mat, mats):
    person = empty(name, semantic_role="human", human_role=role, rig_contract="deterministic-authored-contact")
    hip = Vector(joints["hip"])
    shoulder = Vector(joints["shoulder"])
    torso_mid = (hip + shoulder) * 0.5
    torso = garment_frustum(f"{name}-tunic", torso_mid, (shoulder - hip).length + 0.22, 0.33, 0.25, cloth_mat, person)
    torso.rotation_mode = "QUATERNION"
    torso.rotation_quaternion = (shoulder - hip).to_track_quat("Z", "Y")
    cylinder_between(f"{name}-neck", shoulder, (joints["head"][0], joints["head"][1], joints["head"][2] - 0.23), 0.12, mats["wet_skin"], person)
    add_primitive("sphere", f"{name}-head", joints["head"], (0.205, 0.185, 0.265), mats["wet_skin"], person, semantic_role="face", segments=36 if LOD == 0 else 14)
    add_primitive(
        "sphere",
        f"{name}-jaw",
        (joints["head"][0], joints["head"][1] - 0.012, joints["head"][2] - 0.145),
        (0.165, 0.158, 0.155),
        mats["wet_skin"],
        person,
        segments=30 if LOD == 0 else 12,
    )
    hair = add_primitive("sphere", f"{name}-hair", (joints["head"][0], joints["head"][1] + 0.105, joints["head"][2] + 0.105), (0.235, 0.155, 0.205), mats["hair"], person)
    hair.scale.z = 0.84
    add_primitive("sphere", f"{name}-hair-crown", (joints["head"][0], joints["head"][1] + 0.035, joints["head"][2] + 0.225), (0.19, 0.17, 0.105), mats["hair"], person)
    if LOD == 0:
        add_primitive("cone", f"{name}-nose", (joints["head"][0], joints["head"][1] - 0.195, joints["head"][2] - 0.012), (0.038, 0.038, 0.072), mats["wet_skin"], person, rotation=(math.pi / 2, 0, 0), segments=14)
        for side, sign in (("left", -1), ("right", 1)):
            add_primitive("sphere", f"{name}-eye-{side}", (joints["head"][0] + sign * 0.071, joints["head"][1] - 0.184, joints["head"][2] + 0.034), (0.021, 0.010, 0.014), mats["eye"], person, segments=16)
            cylinder_between(
                f"{name}-brow-{side}",
                (joints["head"][0] + sign * 0.125, joints["head"][1] - 0.181, joints["head"][2] + 0.087),
                (joints["head"][0] + sign * 0.033, joints["head"][1] - 0.194, joints["head"][2] + 0.079),
                0.009,
                mats["hair"],
                person,
                segments=8,
            )
            add_primitive(
                "sphere",
                f"{name}-ear-{side}",
                (joints["head"][0] + sign * 0.205, joints["head"][1] + 0.002, joints["head"][2] - 0.005),
                (0.035, 0.024, 0.058),
                mats["wet_skin"],
                person,
                segments=16,
            )
        swept_tube(
            f"{name}-mouth",
            [
                (joints["head"][0] - 0.055, joints["head"][1] - 0.177, joints["head"][2] - 0.105),
                (joints["head"][0], joints["head"][1] - 0.186, joints["head"][2] - 0.114),
                (joints["head"][0] + 0.055, joints["head"][1] - 0.177, joints["head"][2] - 0.105),
            ],
            0.007,
            6,
            mats["hair"],
            person,
        )

    for side in ("left", "right"):
        shoulder_key = f"{side}_shoulder"
        elbow_key = f"{side}_elbow"
        hand_key = f"{side}_hand"
        tapered_limb(f"{name}-{side}-upper-arm", joints[shoulder_key], joints[elbow_key], 0.135, 0.105, cloth_mat, person)
        tapered_limb(f"{name}-{side}-forearm", joints[elbow_key], joints[hand_key], 0.098, 0.067, mats["wet_skin"], person)
        build_hand(f"{name}-{side}-hand", joints[hand_key], mats, person)
        hip_key = f"{side}_hip"
        knee_key = f"{side}_knee"
        foot_key = f"{side}_foot"
        tapered_limb(f"{name}-{side}-thigh", joints[hip_key], joints[knee_key], 0.165, 0.125, cloth_mat, person)
        tapered_limb(f"{name}-{side}-shin", joints[knee_key], joints[foot_key], 0.120, 0.084, cloth_mat, person)
        add_primitive("sphere", f"{name}-{side}-foot", joints[foot_key], (0.16, 0.28, 0.10), mats["cloth"], person)
    if LOD == 0:
        belt_center = tuple((hip * 0.72 + shoulder * 0.28))
        add_primitive("torus", f"{name}-woven-belt", belt_center, (0.34, 0.25, 0.035), mats["rope"], person, rotation=(0, 0, 0))
        if name == "person-rope-handler":
            add_primitive("sphere", f"{name}-beard", (joints["head"][0], joints["head"][1] - 0.135, joints["head"][2] - 0.165), (0.14, 0.047, 0.15), mats["hair"], person, segments=26)
        elif name == "person-seed-keeper":
            add_primitive("sphere", f"{name}-hair-knot", (joints["head"][0], joints["head"][1] + 0.16, joints["head"][2] + 0.15), (0.11, 0.10, 0.11), mats["hair"], person)
        for strand in range(3):
            strand_x = joints["head"][0] + (strand - 1) * 0.055
            swept_tube(
                f"{name}-wet-hair-strand-{strand}",
                [
                    (strand_x, joints["head"][1] + 0.11, joints["head"][2] + 0.13),
                    (strand_x + 0.015 * (strand - 1), joints["head"][1] + 0.16, joints["head"][2] - 0.06),
                    (strand_x + 0.025 * (strand - 1), joints["head"][1] + 0.12, joints["head"][2] - 0.25),
                ],
                0.012,
                5,
                mats["hair"],
                person,
            )
    return person


def build_people(mats):
    build_person(
        "person-rope-handler",
        "holds-loading-line",
        {
            "hip": (1.15, 0.30, 0.75), "shoulder": (1.48, 0.16, 1.44), "head": (1.64, 0.10, 1.82), "lean": -0.34,
            "left_shoulder": (1.34, 0.08, 1.42), "left_elbow": (1.72, -0.05, 1.10), "left_hand": (2.11, -0.32, 1.17),
            "right_shoulder": (1.60, 0.22, 1.42), "right_elbow": (1.92, 0.02, 1.22), "right_hand": (2.30, -0.25, 1.23),
            "left_hip": (1.03, 0.14, 0.77), "left_knee": (0.82, -0.02, 0.36), "left_foot": (0.53, -0.18, 0.08),
            "right_hip": (1.25, 0.44, 0.77), "right_knee": (1.10, 0.66, 0.34), "right_foot": (1.30, 0.78, 0.07),
        },
        mats["cloth_warm"], mats,
    )
    build_person(
        "person-seed-keeper",
        "protects-seed-vessel",
        {
            "hip": (-0.88, -0.78, 0.62), "shoulder": (-0.73, -0.73, 1.27), "head": (-0.63, -0.78, 1.62), "lean": -0.18,
            "left_shoulder": (-0.88, -0.76, 1.26), "left_elbow": (-0.94, -0.95, 1.02), "left_hand": (-0.99, -0.92, 0.72),
            "right_shoulder": (-0.58, -0.69, 1.25), "right_elbow": (-0.37, -0.91, 1.01), "right_hand": (-0.32, -0.88, 0.72),
            "left_hip": (-1.00, -0.68, 0.63), "left_knee": (-1.35, -0.84, 0.33), "left_foot": (-1.62, -0.74, 0.10),
            "right_hip": (-0.77, -0.86, 0.63), "right_knee": (-0.39, -1.02, 0.31), "right_foot": (-0.20, -0.92, 0.08),
        },
        mats["cloth_grey"], mats,
    )
    build_person(
        "person-stabilizer",
        "steadies-young-bovine",
        {
            "hip": (-2.15, 0.28, 0.64), "shoulder": (-2.02, 0.24, 1.30), "head": (-1.94, 0.20, 1.66), "lean": -0.16,
            "left_shoulder": (-2.18, 0.12, 1.27), "left_elbow": (-1.82, 0.03, 1.04), "left_hand": (-1.42, -0.02, 0.93),
            "right_shoulder": (-1.88, 0.36, 1.27), "right_elbow": (-1.57, 0.42, 1.05), "right_hand": (-1.22, 0.34, 0.91),
            "left_hip": (-2.28, 0.13, 0.64), "left_knee": (-2.57, 0.02, 0.31), "left_foot": (-2.80, -0.12, 0.08),
            "right_hip": (-2.03, 0.42, 0.64), "right_knee": (-1.77, 0.65, 0.31), "right_foot": (-1.55, 0.70, 0.08),
        },
        mats["cloth"], mats,
    )


def build_bovine(mats):
    bovine = empty("young-bovine", (0.70, 0.18, 0.0), semantic_role="livestock", species="bos-taurus-young", anatomy="authored-calf-v1")
    add_primitive("sphere", "young-bovine-ribcage", (-1.12, 0.20, 0.77), (0.69, 0.31, 0.41), mats["hide"], bovine, segments=36 if LOD == 0 else 14)
    add_primitive("sphere", "young-bovine-haunch", (-1.58, 0.20, 0.79), (0.40, 0.33, 0.42), mats["hide_light"], bovine, segments=32 if LOD == 0 else 12)
    add_primitive("sphere", "young-bovine-chest", (-0.67, 0.19, 0.82), (0.36, 0.30, 0.44), mats["hide_light"], bovine, segments=32 if LOD == 0 else 12)
    add_primitive("sphere", "young-bovine-neck", (-0.48, 0.16, 0.99), (0.27, 0.24, 0.39), mats["hide"], bovine, rotation=(0, -0.48, 0), segments=30 if LOD == 0 else 12)
    add_primitive("sphere", "young-bovine-head", (-0.18, 0.10, 1.13), (0.35, 0.23, 0.27), mats["hide"], bovine, rotation=(0, -0.10, 0), segments=34 if LOD == 0 else 13)
    add_primitive("sphere", "young-bovine-muzzle", (0.09, 0.03, 1.02), (0.23, 0.22, 0.15), mats["muzzle"], bovine, segments=28 if LOD == 0 else 12)
    for side, sign in (("left", -1), ("right", 1)):
        add_primitive("sphere", f"young-bovine-ear-{side}", (-0.30, 0.10 + sign * 0.28, 1.22), (0.23, 0.065, 0.095), mats["hide_light"], bovine, rotation=(0, 0.2, sign * 0.32), segments=24 if LOD == 0 else 10)
        add_primitive("sphere", f"young-bovine-eye-{side}", (-0.02, 0.10 + sign * 0.215, 1.17), (0.028, 0.014, 0.026), mats["eye"], bovine, segments=16)
        if LOD == 0:
            add_primitive(
                "cone",
                f"young-bovine-horn-bud-{side}",
                (-0.22, 0.10 + sign * 0.155, 1.36),
                (0.045, 0.045, 0.075),
                mats["muzzle"],
                bovine,
                rotation=(0.18, sign * 0.24, 0),
                segments=12,
            )
    legs = (
        ((-1.50, -0.03, 0.68), (-1.58, -0.05, 0.38), (-1.52, -0.05, 0.09)),
        ((-1.47, 0.43, 0.68), (-1.39, 0.44, 0.37), (-1.46, 0.44, 0.09)),
        ((-0.73, -0.02, 0.68), (-0.63, -0.04, 0.37), (-0.68, -0.04, 0.09)),
        ((-0.68, 0.42, 0.68), (-0.79, 0.43, 0.36), (-0.72, 0.43, 0.09)),
    )
    for index, (upper, knee, hoof) in enumerate(legs):
        tapered_limb(f"young-bovine-leg-{index}-upper", upper, knee, 0.105, 0.076, mats["hide"], bovine, sides=14 if LOD == 0 else 7)
        tapered_limb(f"young-bovine-leg-{index}-lower", knee, hoof, 0.070, 0.050, mats["muzzle"], bovine, sides=12 if LOD == 0 else 6)
        hoof_obj = add_primitive("cube", f"young-bovine-hoof-{index}", (hoof[0] + 0.045, hoof[1] - 0.01, 0.045), (0.115, 0.082, 0.052), mats["muzzle"], bovine)
        bevel = hoof_obj.modifiers.new("rounded-cloven-hoof", "BEVEL")
        bevel.width = 0.026
        bevel.segments = 2 if LOD == 0 else 1
    swept_tube("young-bovine-tail", [(-1.82, 0.20, 0.95), (-2.02, 0.23, 0.73), (-2.10, 0.25, 0.47)], 0.032, 7 if LOD == 0 else 5, mats["hide"], bovine)
    add_primitive("sphere", "young-bovine-tail-tuft", (-2.10, 0.25, 0.44), (0.075, 0.055, 0.12), mats["hair"], bovine)
    return bovine


def build_anchors():
    anchors = {
        "camera-entry": ((6.8, -8.0, 3.60), "entry-portrait"),
        "camera-action-close": ((3.45, -3.35, 2.25), "rope-and-hands"),
        "camera-seed-close": ((1.10, -3.20, 2.05), "seed-vessel-and-keeper"),
        "camera-shore-reveal": ((5.2, -2.1, 3.5), "western-shore"),
        "transition-carrier-seed": ((-0.65, -0.62, 1.03), "seed-vessel"),
        "transition-western-shore": ((0.0, 6.2, 0.15), "western-shore"),
        "interaction-origin": ((2.20, -0.25, 1.22), "action-crossing-line"),
    }
    for name, (location, binding) in anchors.items():
        empty(name, location, semantic_role="anchor", binding=binding)


def look_at(obj: bpy.types.Object, target: Sequence[float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_review_scene() -> None:
    scene = bpy.context.scene
    camera_data = bpy.data.cameras.new("review-camera-data")
    camera = bpy.data.objects.new("review-camera", camera_data)
    link_review(camera)
    camera.location = (7.8, -9.25, 4.15)
    camera_data.lens = 54
    camera_data.sensor_width = 32
    camera_data.dof.use_dof = True
    camera_data.dof.focus_distance = 11.8
    camera_data.dof.aperture_fstop = 5.6
    look_at(camera, (-0.20, 0.92, 1.18))
    scene.camera = camera
    scene.view_settings.look = "AgX - High Contrast"
    scene.view_settings.exposure = 0.62

    sun_data = bpy.data.lights.new("review-sun-data", "SUN")
    sun_data.energy = 1.85
    sun_data.color = (1.0, 0.68, 0.38)
    sun_data.angle = math.radians(10)
    sun = bpy.data.objects.new("review-sun", sun_data)
    link_review(sun)
    sun.rotation_euler = (math.radians(38), math.radians(-24), math.radians(-124))

    area_data = bpy.data.lights.new("review-fill-data", "AREA")
    area_data.energy = 1120
    area_data.color = (0.32, 0.46, 0.58)
    area_data.shape = "DISK"
    area_data.size = 7.0
    area = bpy.data.objects.new("review-fill", area_data)
    link_review(area)
    area.location = (-3.0, -4.0, 6.0)
    look_at(area, (0.0, 0.0, 0.7))

    rim_data = bpy.data.lights.new("review-rim-data", "AREA")
    rim_data.energy = 1050
    rim_data.color = (1.0, 0.48, 0.20)
    rim_data.shape = "RECTANGLE"
    rim_data.size = 4.0
    rim = bpy.data.objects.new("review-rim", rim_data)
    link_review(rim)
    rim.location = (-5.0, 4.0, 5.0)
    look_at(rim, (0.0, 0.0, 0.8))


def build_cell(lod: int) -> None:
    global LOD
    LOD = lod
    reset_scene()
    LOD = lod
    mats = build_materials()
    build_sky_dome(mats)
    build_water(mats)
    build_shore(mats)
    boat = build_boat(mats)
    build_action_rope(mats)
    build_seed_vessel(mats)
    build_cargo(mats, boat)
    build_people(mats)
    build_bovine(mats)
    build_anchors()
    build_review_scene()


def canonicalize_mesh_topology(stage: Usd.Stage) -> None:
    """Give equivalent Blender-evaluated meshes one stable face ordering.

    Blender may schedule modifier evaluation differently between headless runs.
    Vertex positions remain stable, but polygon and face-varying array order can
    change. RealityKit does not depend on polygon order, so canonicalise every
    face by a winding-preserving rotation, then sort faces lexicographically.
    """
    for prim in stage.Traverse():
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

        records: list[tuple[tuple[int, ...], int, list[int], list[int]]] = []
        cursor = 0
        for face_index, count in enumerate(counts):
            face = indices[cursor : cursor + count]
            corners = list(range(cursor, cursor + count))
            if count:
                rotation = min(
                    range(count),
                    key=lambda offset: tuple(face[offset:] + face[:offset]),
                )
                face = face[rotation:] + face[:rotation]
                corners = corners[rotation:] + corners[:rotation]
            records.append((tuple(face), face_index, face, corners))
            cursor += count
        records.sort(key=lambda record: record[0])

        face_order = [record[1] for record in records]
        corner_order = [corner for record in records for corner in record[3]]
        old_to_new = {old: new for new, old in enumerate(face_order)}
        mesh.GetFaceVertexCountsAttr().Set([len(record[2]) for record in records])
        mesh.GetFaceVertexIndicesAttr().Set([index for record in records for index in record[2]])

        normals_attr = mesh.GetNormalsAttr()
        normals = normals_attr.Get() if normals_attr else None
        normals_interpolation = str(mesh.GetNormalsInterpolation())
        if normals is not None:
            # Parallel modifier evaluation can alter the final ULPs of derived
            # normals. Three decimal places are well below render sensitivity
            # while producing stable authored bytes across identical builds.
            normal_values = []
            for value in normals:
                components = []
                for component in value:
                    rounded = round(float(component), 3)
                    components.append(0.0 if abs(rounded) < 0.0005 else rounded)
                normal_values.append(Gf.Vec3f(*components))
            if normals_interpolation == str(UsdGeom.Tokens.faceVarying) and len(normal_values) == len(corner_order):
                normals_attr.Set([normal_values[index] for index in corner_order])
            elif normals_interpolation == str(UsdGeom.Tokens.uniform) and len(normal_values) == len(face_order):
                normals_attr.Set([normal_values[index] for index in face_order])
            else:
                normals_attr.Set(normal_values)

        for primvar in UsdGeom.PrimvarsAPI(prim).GetPrimvars():
            interpolation = str(primvar.GetInterpolation())
            if interpolation == str(UsdGeom.Tokens.faceVarying):
                order = corner_order
            elif interpolation == str(UsdGeom.Tokens.uniform):
                order = face_order
            else:
                continue
            data_attr = primvar.GetIndicesAttr() if primvar.IsIndexed() else primvar.GetAttr()
            values = data_attr.Get() if data_attr else None
            if values is None or len(values) != len(order):
                continue
            value_list = list(values)
            data_attr.Set([value_list[index] for index in order])

        holes_attr = mesh.GetHoleIndicesAttr()
        holes = holes_attr.Get() if holes_attr else None
        if holes is not None:
            holes_attr.Set(sorted(old_to_new[int(index)] for index in holes))
        for child in prim.GetChildren():
            if not child.IsA(UsdGeom.Subset):
                continue
            subset_attr = UsdGeom.Subset(child).GetIndicesAttr()
            subset_indices = subset_attr.Get()
            if subset_indices is not None:
                subset_attr.Set(sorted(old_to_new[int(index)] for index in subset_indices))


def set_display_names_and_contract(path: Path) -> dict[str, str]:
    stage = Usd.Stage.Open(str(path))
    if stage is None:
        raise RuntimeError(f"Could not open exported USD: {path}")
    root = stage.GetPrimAtPath(f"/{ROOT_USD_NAME}")
    if not root:
        raise RuntimeError(f"Missing root /{ROOT_USD_NAME} in {path}")
    canonicalize_mesh_topology(stage)
    root.SetDisplayName(ROOT_RUNTIME_NAME)
    root.CreateAttribute("userProperties:runtime_name", Sdf.ValueTypeNames.String).Set(ROOT_RUNTIME_NAME)
    root.CreateAttribute("userProperties:asset_version", Sdf.ValueTypeNames.String).Set(ASSET_VERSION)
    stage.SetDefaultPrim(root)

    bindings: dict[str, str] = {ROOT_RUNTIME_NAME: str(root.GetPath())}
    for prim in stage.Traverse():
        attr = prim.GetAttribute("userProperties:runtime_name")
        if not attr or not attr.HasAuthoredValueOpinion():
            continue
        runtime_name = attr.Get()
        if isinstance(runtime_name, str) and runtime_name:
            prim.SetDisplayName(runtime_name)
            bindings[runtime_name] = str(prim.GetPath())
    stage.GetRootLayer().Save()
    return dict(sorted(bindings.items()))


def _block_end(lines: list[str], start: int) -> int:
    balance = 0
    opened = False
    indent = len(lines[start]) - len(lines[start].lstrip())
    for index in range(start, len(lines)):
        line = lines[index]
        line_indent = len(line) - len(line.lstrip())
        # A prim's body brace is aligned with its `def`; metadata dictionaries
        # in the header are indented and must not terminate the prim early.
        if line_indent == indent and line.strip() == "{":
            opened = True
        if opened:
            # Generated USDA contains no braces in strings. Counting braces
            # keeps this canonicalizer independent from a second USD parser.
            balance += line.count("{") - line.count("}")
        if opened and balance == 0:
            return index
    raise RuntimeError(f"Unclosed USDA block beginning at line {start + 1}")


def _canonicalize_prim_block(lines: list[str]) -> list[str]:
    parent_indent = len(lines[0]) - len(lines[0].lstrip())
    opening = next(
        (
            index
            for index, line in enumerate(lines)
            if len(line) - len(line.lstrip()) == parent_indent and line.strip() == "{"
        ),
        None,
    )
    if opening is None:
        return lines
    closing = len(lines) - 1
    child_indent = parent_indent + 4
    child_pattern = re.compile(rf"^\s{{{child_indent}}}(?:def|over|class)\s+")
    body_start = opening + 1
    body_end = closing
    output = lines[:body_start]
    cursor = body_start
    while cursor < body_end:
        if not child_pattern.match(lines[cursor]):
            output.append(lines[cursor])
            cursor += 1
            continue
        run: list[list[str]] = []
        while cursor < body_end and child_pattern.match(lines[cursor]):
            end = _block_end(lines, cursor)
            run.append(_canonicalize_prim_block(lines[cursor : end + 1]))
            cursor = end + 1
            while cursor < body_end and not lines[cursor].strip():
                cursor += 1
        run.sort(key=lambda block: block[0].strip())
        for index, block in enumerate(run):
            if output and output[-1].strip():
                output.append("\n")
            output.extend(block)
            if index != len(run) - 1:
                output.append("\n")
    while output and not output[-1].strip():
        output.pop()
    output.append("\n")
    output.extend(lines[closing:])
    return output


def canonicalize_usda(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    root_start = next((index for index, line in enumerate(lines) if re.match(r"^(?:def|over|class)\s+", line)), None)
    if root_start is None:
        raise RuntimeError(f"No root prim in {path}")
    root_end = _block_end(lines, root_start)
    canonical = lines[:root_start] + _canonicalize_prim_block(lines[root_start : root_end + 1]) + lines[root_end + 1 :]
    path.write_text("".join(canonical), encoding="utf-8", newline="\n")


def export_canonical_usda(path: Path) -> dict[str, str]:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=str(path),
        check_existing=False,
        selected_objects_only=False,
        collection=EXPORT_COLLECTION.name,
        export_animation=False,
        export_hair=False,
        export_uvmaps=True,
        export_mesh_colors=True,
        export_normals=True,
        export_materials=True,
        export_cameras=False,
        export_lights=False,
        export_custom_properties=True,
        author_blender_name=True,
        relative_paths=True,
        export_textures_mode="KEEP",
        generate_preview_surface=True,
        generate_materialx_network=False,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        convert_scene_units="METERS",
        meters_per_unit=1.0,
        root_prim_path=f"/{ROOT_USD_NAME}",
        # Keep authored polygon order. Blender's exporter triangulates meshes
        # in parallel and can emit equivalent triangles in a different order
        # across runs, which defeats byte-reproducible production packages.
        # RealityKit accepts the authored quads/ngons directly.
        triangulate_meshes=False,
        evaluation_mode="RENDER",
        xform_op_mode="TRS",
    )
    bindings = set_display_names_and_contract(path)
    canonicalize_usda(path)
    os.utime(path, (FIXED_MTIME, FIXED_MTIME))
    return bindings


def convert_usd(source: Path, destination: Path) -> None:
    if destination.exists():
        destination.unlink()
    result = subprocess.run(
        ["/usr/bin/usdcat", str(source), "-o", str(destination)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not destination.exists():
        raise RuntimeError(f"usdcat failed: {result.stdout}\n{result.stderr}")
    os.utime(destination, (FIXED_MTIME, FIXED_MTIME))


def package_usdz(source: Path, destination: Path) -> None:
    if destination.exists():
        destination.unlink()
    command = ["/usr/bin/usdzip", "--arkitAsset", str(source), str(destination)]
    # usdzip's argument order differs across SDK builds; first try documented order.
    result = subprocess.run(command, cwd=source.parent, capture_output=True, text=True)
    if result.returncode != 0 or not destination.exists():
        command = ["/usr/bin/usdzip", str(destination), str(source.name)]
        result = subprocess.run(command, cwd=source.parent, capture_output=True, text=True)
    if result.returncode != 0 or not destination.exists():
        raise RuntimeError(f"usdzip failed: {result.stdout}\n{result.stderr}")
    os.utime(destination, (FIXED_MTIME, FIXED_MTIME))


def export_lod(lod: int) -> dict[str, object]:
    build_cell(lod)
    suffix = f"aegean-crossing-lod{lod}"
    if lod == 0:
        blend_path = OUTPUT_ROOT / f"{suffix}.blend"
        backup_path = blend_path.with_suffix(blend_path.suffix + "1")
        if backup_path.exists():
            backup_path.unlink()
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False, compress=True)
        os.utime(blend_path, (FIXED_MTIME, FIXED_MTIME))
        scene = bpy.context.scene
        preview_path = PREVIEW_ROOT / f"{suffix}.png"
        scene.render.filepath = str(preview_path)
        bpy.ops.render.render(write_still=True)
        os.utime(preview_path, (FIXED_MTIME, FIXED_MTIME))

    usda_path = OUTPUT_ROOT / f"{suffix}.usda"
    usd_path = OUTPUT_ROOT / f"{suffix}.usd"
    usdc_path = OUTPUT_ROOT / f"{suffix}.usdc"
    bindings = export_canonical_usda(usda_path)
    convert_usd(usda_path, usd_path)
    convert_usd(usda_path, usdc_path)
    usdz_path = OUTPUT_ROOT / f"{suffix}.usdz"
    package_usdz(usdc_path, usdz_path)
    return {
        "lod": lod,
        "bindings": bindings,
        "objects": len(EXPORT_COLLECTION.objects),
        "triangles": sum(len(obj.data.loop_triangles) if hasattr(obj.data, "loop_triangles") else 0 for obj in EXPORT_COLLECTION.objects if obj.type == "MESH"),
        "files": [str(path.relative_to(CHAPTER_ROOT)) for path in (usda_path, usd_path, usdc_path, usdz_path)],
    }


def write_generated_report(lods: list[dict[str, object]]) -> None:
    outputs = sorted(path for path in OUTPUT_ROOT.rglob("*") if path.is_file() and not path.name.endswith(".blend1"))
    report = {
        "schemaVersion": 1,
        "assetVersion": ASSET_VERSION,
        "qualityClassification": "CONTINUITY_PROOF",
        "finalArtGate": "OPEN",
        "classificationReason": "Runtime, interaction and transition continuity proof; photoreal hero-character replacement remains required.",
        "canonicalRootName": ROOT_RUNTIME_NAME,
        "sourceDateEpoch": FIXED_MTIME,
        "timestampPolicy": "No wall-clock generation timestamp is canonical; generated file and archive mtimes are fixed to sourceDateEpoch.",
        "tool": {
            "name": "Blender",
            "version": BLENDER_VERSION,
            "buildHash": BLENDER_BUILD_HASH,
        },
        "rights": {
            "externalAssets": [],
            "geometryAndMaterials": "Project-authored deterministic Blender Python; no downloaded assets or textures.",
            "artDirectionUse": "Composition and lighting reference only; not sampled, projected or shipped.",
        },
        "scriptSHA256": stable_hash(SCRIPT_PATH),
        "artDirectionSHA256": stable_hash(ART_TARGET),
        "lods": lods,
        "outputs": [
            {
                "path": str(path.relative_to(CHAPTER_ROOT)),
                "bytes": path.stat().st_size,
                "sha256": stable_hash(path),
            }
            for path in outputs
            if path.name != "generated-build-report.json"
        ],
    }
    report_path = OUTPUT_ROOT / "generated-build-report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.utime(report_path, (FIXED_MTIME, FIXED_MTIME))


def main() -> None:
    verify_environment()
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    PREVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    lods = [export_lod(0), export_lod(1)]
    write_generated_report(lods)
    print(json.dumps({"asset": ASSET_VERSION, "output": str(OUTPUT_ROOT), "lods": lods}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
