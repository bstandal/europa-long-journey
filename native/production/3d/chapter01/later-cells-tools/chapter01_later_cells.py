"""Deterministic Blender production recipes for Chapter 01's later world cells.

Run only through one of the cell-local wrappers.  The recipes use Blender
primitives and generated topology; there are no downloaded models, textures or
other opaque inputs.  Every runtime-facing object carries both ``runtime_name``
and ``runtimeName`` because USD prim identifiers cannot contain the hyphens in
the locked runtime contract.  The exported prim also receives the canonical
name as USD ``displayName`` and the build report records its actual prim path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import struct
import sys
from typing import Callable, Iterable, Sequence
import zipfile

import bpy
from mathutils import Vector
from pxr import Sdf, Usd, UsdGeom, UsdUtils


BLENDER_VERSION = "5.2.0 LTS"
SCHEMA_VERSION = 1
SEED = 6000


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _canonicalize_usd_layer(path: Path) -> None:
    """Rewrite Blender's USD output with stable child/property ordering.

    Blender's dependency graph does not promise iteration order between fresh
    processes.  Geometry and authored names are deterministic, but the raw USD
    layer can therefore serialize sibling prims in a different order.  Copying
    the layer through Sdf with sorted child fields makes the runtime artifact a
    reproducible package input without changing its composed scenegraph.
    """

    source = Sdf.Layer.FindOrOpen(str(path))
    if source is None:
        raise RuntimeError(f"USD source layer failed to open: {path}")
    canonical = Sdf.Layer.CreateAnonymous(f"{path.stem}-canonical.usda")
    for key in sorted(source.pseudoRoot.ListInfoKeys()):
        canonical.pseudoRoot.SetInfo(key, source.pseudoRoot.GetInfo(key))

    def copy_children(
        children_field,
        source_layer,
        source_path,
        field_in_source,
        destination_layer,
        destination_path,
        field_in_destination,
    ):
        del destination_layer, destination_path, field_in_destination
        if not field_in_source:
            return False
        source_spec = source_layer.GetObjectAtPath(source_path)
        children = source_spec.GetInfo(children_field)
        if isinstance(children, (list, tuple)):
            ordered = sorted(children, key=lambda value: str(value))
            return True, ordered, list(ordered)
        return True

    copied = Sdf.CopySpec(
        source,
        Sdf.Path("/root"),
        canonical,
        Sdf.Path("/root"),
        lambda *args: True,
        copy_children,
    )
    if not copied:
        raise RuntimeError(f"USD canonical copy failed: {path}")
    if not canonical.Export(str(path)):
        raise RuntimeError(f"USD canonical export failed: {path}")


def _normalize_usdz_timestamps(path: Path) -> None:
    """Fix ZIP DOS timestamps without disturbing USDZ byte alignment."""

    payload = bytearray(path.read_bytes())
    end_signature = b"PK\x05\x06"
    end_offset = payload.rfind(end_signature)
    if end_offset < 0:
        raise RuntimeError(f"USDZ end-of-central-directory record missing: {path}")
    entry_count = struct.unpack_from("<H", payload, end_offset + 10)[0]
    central_offset = struct.unpack_from("<I", payload, end_offset + 16)[0]
    cursor = central_offset
    fixed_time = 0
    fixed_date = 0x0021  # 1980-01-01, the minimum representable DOS date.
    for _ in range(entry_count):
        if payload[cursor : cursor + 4] != b"PK\x01\x02":
            raise RuntimeError(f"USDZ central-directory entry is malformed: {path}")
        name_length, extra_length, comment_length = struct.unpack_from(
            "<HHH", payload, cursor + 28
        )
        local_offset = struct.unpack_from("<I", payload, cursor + 42)[0]
        if payload[local_offset : local_offset + 4] != b"PK\x03\x04":
            raise RuntimeError(f"USDZ local entry is malformed: {path}")
        struct.pack_into("<HH", payload, cursor + 12, fixed_time, fixed_date)
        struct.pack_into("<HH", payload, local_offset + 10, fixed_time, fixed_date)
        cursor += 46 + name_length + extra_length + comment_length
    path.write_bytes(payload)


def _strip_volatile_png_metadata(path: Path) -> None:
    """Remove Blender timing/path receipts while preserving image bytes."""

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


def _round_vector(values: Sequence[float]) -> list[float]:
    return [round(float(value), 5) for value in values]


class SceneBuilder:
    def __init__(self, cell_id: str, cell_dir: Path):
        self.cell_id = cell_id
        self.cell_dir = cell_dir
        self.random = random.Random(SEED + sum(ord(char) for char in cell_id))
        self.materials: dict[str, bpy.types.Material] = {}
        self.collections: dict[str, bpy.types.Collection] = {}
        self.runtime_objects: dict[str, bpy.types.Object] = {}
        self.root: bpy.types.Object | None = None
        self.camera: bpy.types.Object | None = None

    def reset(self) -> None:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.unit_settings.system = "METRIC"
        scene.unit_settings.scale_length = 1.0
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x = 786
        scene.render.resolution_y = 1704
        scene.render.resolution_percentage = 50
        scene.render.image_settings.file_format = "PNG"
        scene.render.film_transparent = False
        scene.render.image_settings.color_mode = "RGBA"
        scene.render.resolution_percentage = 100
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.image_settings.color_depth = "8"
        scene.view_settings.look = "AgX - Medium High Contrast"
        scene.view_settings.exposure = -0.65
        scene.world = bpy.data.worlds.new("chapter01-world")
        scene.world.use_nodes = True
        world_nodes = scene.world.node_tree.nodes
        background = world_nodes.get("Background")
        sky = world_nodes.new("ShaderNodeTexSky")
        sky.sky_type = "MULTIPLE_SCATTERING"
        sky.sun_elevation = math.radians(17)
        sky.sun_rotation = math.radians(224)
        sky.sun_disc = True
        sky.sun_intensity = 0.16
        sky.air_density = 1.35
        sky.aerosol_density = 3.75
        sky.ozone_density = 1.0
        scene.world.node_tree.links.new(sky.outputs["Color"], background.inputs["Color"])
        background.inputs["Strength"].default_value = 0.045
        scene.render.fps = 30
        scene.frame_start = 1
        scene.frame_end = 1
        bpy.context.preferences.filepaths.save_version = 0

    def collection(self, name: str) -> bpy.types.Collection:
        existing = self.collections.get(name)
        if existing is not None:
            return existing
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
        self.collections[name] = collection
        return collection

    def move_to_collection(self, obj: bpy.types.Object, collection_name: str) -> None:
        collection = self.collection(collection_name)
        for linked in list(obj.users_collection):
            linked.objects.unlink(obj)
        collection.objects.link(obj)

    def register(
        self,
        obj: bpy.types.Object,
        runtime_name: str,
        *,
        semantic_role: str = "scenery",
        collision: str | None = None,
        interaction_id: str | None = None,
        lod_group: str | None = None,
        lod_level: int | None = None,
        state: str = "default",
    ) -> bpy.types.Object:
        obj.name = runtime_name
        # Blender's primitive operators allocate process-global datablock names
        # (for example ``Icosphere.041``).  Those names leak into USD child prims
        # and made two otherwise identical headless builds differ byte-for-byte.
        # Runtime names are unique within a cell, so give every authored
        # datablock a stable name before export as well.
        if obj.data is not None and hasattr(obj.data, "name"):
            obj.data.name = f"{runtime_name}-data"
        obj["runtime_name"] = runtime_name
        obj["runtimeName"] = runtime_name
        obj["canonical_id"] = f"chapter01.{self.cell_id}.{runtime_name}"
        obj["semantic_role"] = semantic_role
        obj["state"] = state
        if collision:
            obj["collision_ready"] = True
            obj["collision_shape"] = collision
        if interaction_id:
            obj["interaction_id"] = interaction_id
        if lod_group:
            obj["lod_group"] = lod_group
        if lod_level is not None:
            obj["lod_level"] = lod_level
        self.runtime_objects[runtime_name] = obj
        return obj

    def empty(
        self,
        runtime_name: str,
        location: Sequence[float] = (0.0, 0.0, 0.0),
        *,
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "group",
        interaction_id: str | None = None,
        state: str = "default",
    ) -> bpy.types.Object:
        obj = bpy.data.objects.new(runtime_name, None)
        obj.location = location
        self.move_to_collection(obj, collection)
        self.register(
            obj,
            runtime_name,
            semantic_role=semantic_role,
            interaction_id=interaction_id,
            state=state,
        )
        if parent is not None:
            obj.parent = parent
        obj.empty_display_type = "PLAIN_AXES"
        obj.empty_display_size = 0.22
        return obj

    def material(
        self,
        name: str,
        rgba: Sequence[float],
        *,
        roughness: float,
        metallic: float = 0.0,
        emission: Sequence[float] | None = None,
        emission_strength: float = 0.0,
        alpha: float = 1.0,
    ) -> bpy.types.Material:
        existing = self.materials.get(name)
        if existing is not None:
            return existing
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        material.diffuse_color = (rgba[0], rgba[1], rgba[2], alpha)
        material.surface_render_method = "BLENDED" if alpha < 1.0 else "DITHERED"
        principled = material.node_tree.nodes.get("Principled BSDF")
        principled.inputs["Base Color"].default_value = (rgba[0], rgba[1], rgba[2], alpha)
        principled.inputs["Roughness"].default_value = roughness
        principled.inputs["Metallic"].default_value = metallic
        principled.inputs["Alpha"].default_value = alpha
        if emission is not None:
            principled.inputs["Emission Color"].default_value = (
                emission[0], emission[1], emission[2], 1.0
            )
            principled.inputs["Emission Strength"].default_value = emission_strength
        elif roughness >= 0.70:
            # Authorable micro-surface response. USD Preview Surface retains the
            # constant PBR channels; Blender keeps this source bump network for
            # later deterministic texture baking.
            noise = material.node_tree.nodes.new("ShaderNodeTexNoise")
            noise.name = f"{name}-microstructure"
            noise.inputs["Scale"].default_value = 7.0 + (sum(ord(c) for c in name) % 11)
            noise.inputs["Detail"].default_value = 3.2
            noise.inputs["Roughness"].default_value = 0.72
            bump = material.node_tree.nodes.new("ShaderNodeBump")
            bump.name = f"{name}-authored-bump"
            bump.inputs["Strength"].default_value = 0.18 if "skin" in name else 0.34
            bump.inputs["Distance"].default_value = 0.055
            material.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
            material.node_tree.links.new(bump.outputs["Normal"], principled.inputs["Normal"])
        material["source"] = "procedural-solid-pbr"
        material["commercial_rights"] = "project-authored"
        self.materials[name] = material
        return material

    @staticmethod
    def assign(obj: bpy.types.Object, material: bpy.types.Material | None) -> None:
        if material is not None and obj.data is not None and hasattr(obj.data, "materials"):
            obj.data.materials.append(material)

    def cube(
        self,
        runtime_name: str,
        location: Sequence[float],
        dimensions: Sequence[float],
        material: bpy.types.Material,
        *,
        rotation: Sequence[float] = (0.0, 0.0, 0.0),
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "scenery",
        collision: str | None = None,
        interaction_id: str | None = None,
        state: str = "default",
        bevel: float = 0.0,
    ) -> bpy.types.Object:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
        obj = bpy.context.object
        obj.dimensions = dimensions
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel > 0:
            modifier = obj.modifiers.new("hand-worked-edges", "BEVEL")
            modifier.width = bevel
            modifier.segments = 2
        self.assign(obj, material)
        self.move_to_collection(obj, collection)
        self.register(
            obj,
            runtime_name,
            semantic_role=semantic_role,
            collision=collision,
            interaction_id=interaction_id,
            state=state,
        )
        if parent is not None:
            obj.parent = parent
        return obj

    def ellipsoid(
        self,
        runtime_name: str,
        location: Sequence[float],
        scale: Sequence[float],
        material: bpy.types.Material,
        *,
        subdivisions: int = 2,
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "scenery",
        collision: str | None = None,
        interaction_id: str | None = None,
        state: str = "default",
    ) -> bpy.types.Object:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
        obj = bpy.context.object
        obj.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        self.assign(obj, material)
        self.move_to_collection(obj, collection)
        self.register(
            obj,
            runtime_name,
            semantic_role=semantic_role,
            collision=collision,
            interaction_id=interaction_id,
            state=state,
        )
        if parent is not None:
            obj.parent = parent
        return obj

    def cylinder(
        self,
        runtime_name: str,
        start: Sequence[float],
        end: Sequence[float],
        radius: float,
        material: bpy.types.Material,
        *,
        vertices: int = 12,
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "scenery",
        collision: str | None = None,
        interaction_id: str | None = None,
        state: str = "default",
    ) -> bpy.types.Object:
        begin = Vector(start)
        finish = Vector(end)
        delta = finish - begin
        midpoint = (begin + finish) / 2.0
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=vertices,
            radius=radius,
            depth=delta.length,
            location=midpoint,
        )
        obj = bpy.context.object
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        self.assign(obj, material)
        self.move_to_collection(obj, collection)
        self.register(
            obj,
            runtime_name,
            semantic_role=semantic_role,
            collision=collision,
            interaction_id=interaction_id,
            state=state,
        )
        if parent is not None:
            obj.parent = parent
        return obj

    def cone(
        self,
        runtime_name: str,
        location: Sequence[float],
        radius1: float,
        radius2: float,
        depth: float,
        material: bpy.types.Material,
        *,
        vertices: int = 16,
        rotation: Sequence[float] = (0.0, 0.0, 0.0),
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "scenery",
        collision: str | None = None,
        interaction_id: str | None = None,
        state: str = "default",
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
        self.assign(obj, material)
        self.move_to_collection(obj, collection)
        self.register(
            obj,
            runtime_name,
            semantic_role=semantic_role,
            collision=collision,
            interaction_id=interaction_id,
            state=state,
        )
        if parent is not None:
            obj.parent = parent
        return obj

    def torus(
        self,
        runtime_name: str,
        location: Sequence[float],
        major_radius: float,
        minor_radius: float,
        material: bpy.types.Material,
        *,
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "scenery",
        state: str = "default",
    ) -> bpy.types.Object:
        bpy.ops.mesh.primitive_torus_add(
            major_radius=major_radius,
            minor_radius=minor_radius,
            major_segments=20,
            minor_segments=5,
            location=location,
        )
        obj = bpy.context.object
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        self.assign(obj, material)
        self.move_to_collection(obj, collection)
        self.register(obj, runtime_name, semantic_role=semantic_role, state=state)
        if parent is not None:
            obj.parent = parent
        return obj

    def mesh(
        self,
        runtime_name: str,
        vertices: Sequence[Sequence[float]],
        faces: Sequence[Sequence[int]],
        material: bpy.types.Material,
        *,
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "scenery",
        collision: str | None = None,
        interaction_id: str | None = None,
        state: str = "default",
    ) -> bpy.types.Object:
        data = bpy.data.meshes.new(f"{runtime_name}-mesh")
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = bpy.data.objects.new(runtime_name, data)
        self.assign(obj, material)
        self.move_to_collection(obj, collection)
        self.register(
            obj,
            runtime_name,
            semantic_role=semantic_role,
            collision=collision,
            interaction_id=interaction_id,
            state=state,
        )
        if parent is not None:
            obj.parent = parent
        return obj

    def path_mesh(
        self,
        runtime_name: str,
        points: Sequence[Sequence[float]],
        radius: float,
        material: bpy.types.Material,
        *,
        parent: bpy.types.Object | None = None,
        collection: str = "WORLD",
        semantic_role: str = "scenery",
        collision: str | None = None,
        interaction_id: str | None = None,
        state: str = "default",
    ) -> bpy.types.Object:
        curve_data = bpy.data.curves.new(f"{runtime_name}-curve", "CURVE")
        curve_data.dimensions = "3D"
        curve_data.resolution_u = 2
        curve_data.bevel_depth = radius
        curve_data.bevel_resolution = 1
        polyline = curve_data.splines.new("POLY")
        polyline.points.add(len(points) - 1)
        for index, point in enumerate(points):
            polyline.points[index].co = (*point, 1.0)
        obj = bpy.data.objects.new(runtime_name, curve_data)
        self.move_to_collection(obj, collection)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        obj = bpy.context.object
        self.assign(obj, material)
        self.register(
            obj,
            runtime_name,
            semantic_role=semantic_role,
            collision=collision,
            interaction_id=interaction_id,
            state=state,
        )
        if parent is not None:
            obj.parent = parent
        obj.select_set(False)
        return obj

    def anchor(
        self,
        runtime_name: str,
        location: Sequence[float],
        target: Sequence[float],
        *,
        category: str,
        parent: bpy.types.Object,
    ) -> bpy.types.Object:
        anchor = self.empty(
            runtime_name,
            location,
            parent=parent,
            collection="ANCHORS",
            semantic_role=category,
        )
        anchor["target"] = _round_vector(target)
        anchor.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        return anchor

    def area_light(
        self,
        name: str,
        location: Sequence[float],
        target: Sequence[float],
        color: Sequence[float],
        energy: float,
        size: float,
        *,
        parent: bpy.types.Object,
    ) -> bpy.types.Object:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        obj.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        self.move_to_collection(obj, "LIGHTS")
        self.register(obj, name, semantic_role="authored-light")
        obj.parent = parent
        return obj

    def sun(self, name: str, rotation: Sequence[float], energy: float, color: Sequence[float]) -> None:
        data = bpy.data.lights.new(name, "SUN")
        data.energy = energy
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = rotation
        self.move_to_collection(obj, "LIGHTS")
        self.register(obj, name, semantic_role="authored-light")
        obj.parent = self.root

    def set_preview_camera(
        self,
        runtime_name: str,
        location: Sequence[float],
        target: Sequence[float],
        *,
        lens: float = 48.0,
    ) -> bpy.types.Object:
        data = bpy.data.cameras.new(runtime_name)
        data.lens = lens
        data.sensor_width = 36.0
        data.dof.use_dof = False
        data.clip_start = 0.05
        data.clip_end = 220.0
        obj = bpy.data.objects.new(runtime_name, data)
        obj.location = location
        obj.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        self.move_to_collection(obj, "CAMERAS")
        self.register(obj, runtime_name, semantic_role="preview-camera")
        obj.parent = self.root
        bpy.context.scene.camera = obj
        self.camera = obj
        return obj

    def terrain(
        self,
        runtime_name: str,
        *,
        x_min: float,
        x_max: float,
        y_min: float,
        y_max: float,
        x_steps: int,
        y_steps: int,
        height: Callable[[float, float], float],
        material: bpy.types.Material,
        parent: bpy.types.Object,
        collection: str = "WORLD",
    ) -> bpy.types.Object:
        vertices: list[tuple[float, float, float]] = []
        for yi in range(y_steps + 1):
            y = y_min + (y_max - y_min) * yi / y_steps
            for xi in range(x_steps + 1):
                x = x_min + (x_max - x_min) * xi / x_steps
                vertices.append((x, y, height(x, y)))
        faces: list[tuple[int, int, int, int]] = []
        width = x_steps + 1
        for yi in range(y_steps):
            for xi in range(x_steps):
                a = yi * width + xi
                faces.append((a, a + 1, a + width + 1, a + width))
        return self.mesh(runtime_name, vertices, faces, material, parent=parent, collection=collection)

    def human(
        self,
        runtime_name: str,
        location: Sequence[float],
        *,
        parent: bpy.types.Object,
        skin: bpy.types.Material,
        cloth: bpy.types.Material,
        hair: bpy.types.Material,
        facing: float = 0.0,
        pose: str = "work",
        scale: float = 1.0,
    ) -> bpy.types.Object:
        group = self.empty(runtime_name, location, parent=parent, semantic_role="representative-person")
        group.rotation_euler[2] = facing
        self.ellipsoid(
            f"{runtime_name}-torso",
            (0, 0, 1.17 * scale),
            (0.25 * scale, 0.17 * scale, 0.40 * scale),
            cloth,
            subdivisions=3,
            parent=group,
        )
        self.cone(
            f"{runtime_name}-tunic",
            (0, 0, 0.86 * scale),
            0.34 * scale,
            0.23 * scale,
            0.55 * scale,
            cloth,
            parent=group,
        )
        self.ellipsoid(
            f"{runtime_name}-head",
            (0, 0, 1.68 * scale),
            (0.15 * scale, 0.13 * scale, 0.18 * scale),
            skin,
            subdivisions=3,
            parent=group,
        )
        self.ellipsoid(
            f"{runtime_name}-hair",
            (0, 0.012 * scale, 1.76 * scale),
            (0.155 * scale, 0.14 * scale, 0.12 * scale),
            hair,
            subdivisions=2,
            parent=group,
        )
        self.ellipsoid(
            f"{runtime_name}-nose",
            (0, -0.125 * scale, 1.67 * scale),
            (0.040 * scale, 0.055 * scale, 0.060 * scale),
            skin,
            subdivisions=2,
            parent=group,
        )
        for index, x in enumerate((-0.145, 0.145)):
            self.ellipsoid(
                f"{runtime_name}-ear-{index}",
                (x * scale, 0, 1.68 * scale),
                (0.032 * scale, 0.022 * scale, 0.052 * scale),
                skin,
                subdivisions=2,
                parent=group,
            )
        self.cone(
            f"{runtime_name}-belt",
            (0, 0, 0.94 * scale),
            0.285 * scale,
            0.285 * scale,
            0.065 * scale,
            hair,
            vertices=24,
            parent=group,
        )
        if pose == "pole":
            arms = [((-0.18, 0, 1.42), (-0.38, 0.28, 1.12)), ((0.18, 0, 1.42), (0.30, -0.18, 1.02))]
        elif pose == "carry":
            arms = [((-0.18, 0, 1.40), (-0.30, 0.30, 1.14)), ((0.18, 0, 1.40), (0.30, 0.30, 1.14))]
        elif pose == "raise":
            arms = [((-0.18, 0, 1.42), (-0.28, 0.14, 1.78)), ((0.18, 0, 1.42), (0.28, 0.14, 1.78))]
        else:
            arms = [((-0.18, 0, 1.42), (-0.35, 0.23, 1.10)), ((0.18, 0, 1.42), (0.35, 0.23, 1.10))]
        for index, (start, end) in enumerate(arms):
            self.cylinder(
                f"{runtime_name}-arm-{index}",
                tuple(value * scale for value in start),
                tuple(value * scale for value in end),
                0.065 * scale,
                skin,
                vertices=10,
                parent=group,
            )
            self.ellipsoid(
                f"{runtime_name}-hand-{index}",
                tuple(value * scale for value in end),
                (0.070 * scale, 0.050 * scale, 0.085 * scale),
                skin,
                subdivisions=2,
                parent=group,
            )
        legs = [((-0.13, 0, 0.72), (-0.14, 0.05, 0.10)), ((0.13, 0, 0.72), (0.14, -0.04, 0.10))]
        for index, (start, end) in enumerate(legs):
            self.cylinder(
                f"{runtime_name}-leg-{index}",
                tuple(value * scale for value in start),
                tuple(value * scale for value in end),
                0.075 * scale,
                skin,
                vertices=10,
                parent=group,
            )
            self.ellipsoid(
                f"{runtime_name}-foot-{index}",
                (end[0] * scale, (end[1] - 0.055) * scale, 0.075 * scale),
                (0.095 * scale, 0.17 * scale, 0.055 * scale),
                skin,
                subdivisions=2,
                parent=group,
            )
        return group

    def cattle(
        self,
        runtime_name: str,
        location: Sequence[float],
        *,
        parent: bpy.types.Object,
        hide: bpy.types.Material,
        horn: bpy.types.Material,
        facing: float = 0.0,
        scale: float = 1.0,
    ) -> bpy.types.Object:
        group = self.empty(runtime_name, location, parent=parent, semantic_role="domestic-cattle")
        group.rotation_euler[2] = facing
        self.ellipsoid(f"{runtime_name}-body", (0, 0, 1.08 * scale), (0.72 * scale, 0.30 * scale, 0.40 * scale), hide, subdivisions=3, parent=group)
        self.ellipsoid(f"{runtime_name}-head", (0.70 * scale, 0, 1.20 * scale), (0.28 * scale, 0.23 * scale, 0.28 * scale), hide, subdivisions=3, parent=group)
        self.ellipsoid(f"{runtime_name}-muzzle", (0.93 * scale, 0, 1.12 * scale), (0.20 * scale, 0.19 * scale, 0.15 * scale), hide, subdivisions=3, parent=group)
        for index, y in enumerate((-0.20, 0.20)):
            self.cone(
                f"{runtime_name}-horn-{index}",
                (0.82 * scale, y * scale, 1.47 * scale),
                0.06 * scale,
                0.012 * scale,
                0.36 * scale,
                horn,
                vertices=8,
                rotation=(0, math.radians(65), 0),
                parent=group,
            )
        for index, (x, y) in enumerate(((-0.44, -0.22), (-0.44, 0.22), (0.42, -0.22), (0.42, 0.22))):
            self.cylinder(
                f"{runtime_name}-leg-{index}",
                (x * scale, y * scale, 0.88 * scale),
                (x * scale, y * scale, 0.10 * scale),
                0.07 * scale,
                hide,
                vertices=8,
                parent=group,
            )
            self.ellipsoid(
                f"{runtime_name}-hoof-{index}",
                (x * scale, (y - 0.02) * scale, 0.08 * scale),
                (0.085 * scale, 0.09 * scale, 0.055 * scale),
                horn,
                subdivisions=1,
                parent=group,
            )
        self.path_mesh(
            f"{runtime_name}-tail",
            [(-0.68 * scale, 0, 1.25 * scale), (-0.88 * scale, 0, 0.98 * scale), (-0.91 * scale, 0, 0.66 * scale)],
            0.025 * scale,
            hide,
            parent=group,
        )
        return group

    def hut(
        self,
        runtime_name: str,
        location: Sequence[float],
        *,
        parent: bpy.types.Object,
        wall: bpy.types.Material,
        thatch: bpy.types.Material,
        scale: float = 1.0,
    ) -> bpy.types.Object:
        group = self.empty(runtime_name, location, parent=parent, semantic_role="fishing-settlement-architecture")
        self.cylinder(f"{runtime_name}-wall", (0, 0, 0), (0, 0, 1.15 * scale), 0.95 * scale, wall, vertices=16, parent=group)
        self.cone(f"{runtime_name}-roof", (0, 0, 1.65 * scale), 1.16 * scale, 0.10 * scale, 1.25 * scale, thatch, vertices=16, parent=group)
        for index in range(12):
            angle = index / 12 * math.tau
            x = 0.965 * scale * math.cos(angle)
            y = 0.965 * scale * math.sin(angle)
            self.cylinder(
                f"{runtime_name}-wattle-post-{index}",
                (x, y, 0.04 * scale),
                (x, y, 1.15 * scale),
                0.022 * scale,
                self.materials["weathered-oak"],
                vertices=7,
                parent=group,
            )
        for index, z in enumerate((0.28, 0.52, 0.76, 0.99)):
            self.torus(
                f"{runtime_name}-wattle-ring-{index}",
                (0, 0, z * scale),
                0.973 * scale,
                0.017 * scale,
                self.materials["bast-rope"],
                parent=group,
            )
        for index in range(16):
            angle = index / 16 * math.tau
            self.cylinder(
                f"{runtime_name}-thatch-strand-{index}",
                (1.10 * scale * math.cos(angle), 1.10 * scale * math.sin(angle), 1.17 * scale),
                (0.08 * scale * math.cos(angle), 0.08 * scale * math.sin(angle), 2.22 * scale),
                0.027 * scale,
                thatch,
                vertices=7,
                parent=group,
            )
        self.cube(f"{runtime_name}-door", (0, -0.93 * scale, 0.55 * scale), (0.50 * scale, 0.10 * scale, 0.96 * scale), self.materials["dark-opening"], parent=group)
        return group

    def add_lod_markers(self, parent: bpy.types.Object, bounds: Sequence[float]) -> None:
        for level, distance in ((0, 0.0), (1, 18.0), (2, 38.0)):
            marker = self.empty(
                f"lod-{level}-contract",
                parent=parent,
                collection="LOD",
                semantic_role="lod-contract",
            )
            marker["screen_space_error"] = (0.0, 1.8, 4.5)[level]
            marker["distance_m"] = distance
            marker["bounds_m"] = _round_vector(bounds)

    def finish_scene(self) -> None:
        bpy.context.scene["cell_id"] = self.cell_id
        bpy.context.scene["schema_version"] = SCHEMA_VERSION
        bpy.context.scene["deterministic_seed"] = SEED
        bpy.context.scene["source_authority"] = "chapter01_later_cells.py"

    def render_preview(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        _strip_volatile_png_metadata(path)

    def export(self) -> dict:
        exports = self.cell_dir / "exports"
        previews = self.cell_dir / "previews"
        exports.mkdir(parents=True, exist_ok=True)
        previews.mkdir(parents=True, exist_ok=True)
        blend = exports / f"{self.cell_id}.blend"
        usda = exports / f"{self.cell_id}.usda"
        usd = exports / f"{self.cell_id}.usd"
        usdc = exports / f"{self.cell_id}.usdc"
        usdz = exports / f"{self.cell_id}.usdz"
        preview = previews / f"{self.cell_id}-portrait.png"

        bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=False)
        self.render_preview(preview)
        bpy.ops.wm.usd_export(
            filepath=str(usda),
            export_animation=False,
            export_hair=False,
            export_uvmaps=True,
            export_normals=True,
            export_materials=True,
            export_armatures=False,
            export_shapekeys=False,
            # Instancing is deliberately disabled for this continuity-proof
            # package.  Blender's implicit prototype allocation order is not a
            # stable contract, while the explicit LOD/state hierarchy is.
            use_instancing=False,
            # State variants and non-current LODs are intentionally hidden
            # from the technical preview but must remain in the runtime stage.
            evaluation_mode="VIEWPORT",
            generate_preview_surface=True,
            generate_materialx_network=False,
            export_textures_mode="KEEP",
            relative_paths=True,
            xform_op_mode="TRS",
            export_custom_properties=True,
            custom_properties_namespace="userProperties",
            export_lights=True,
            export_cameras=True,
            convert_world_material=False,
            triangulate_meshes=True,
            convert_scene_units="METERS",
            meters_per_unit=1.0,
        )

        _canonicalize_usd_layer(usda)

        stage = Usd.Stage.Open(str(usda))
        binding: dict[str, str] = {}
        for prim in stage.Traverse():
            attr = prim.GetAttribute("userProperties:runtime_name")
            if not attr:
                continue
            runtime_name = attr.Get()
            if not runtime_name:
                continue
            runtime_name = str(runtime_name)
            prim.SetDisplayName(runtime_name)
            binding[runtime_name] = str(prim.GetPath())
        stage.GetRootLayer().Save()
        stage.Export(str(usd))
        stage.Export(str(usdc))
        if usdz.exists():
            usdz.unlink()
        created = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(usdc)), str(usdz))
        if not created:
            raise RuntimeError(f"USDZ packaging failed for {self.cell_id}")
        _normalize_usdz_timestamps(usdz)

        # Count the actual exported/evaluated stage.  This includes modifier
        # topology (for example hand-worked bevels) and therefore matches what
        # RealityKit receives rather than Blender's pre-evaluation datablocks.
        exported_meshes = [prim for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
        mesh_count = len(exported_meshes)
        triangle_count = sum(
            len(UsdGeom.Mesh(prim).GetFaceVertexCountsAttr().Get() or [])
            for prim in exported_meshes
        )
        files = [blend, usda, usd, usdc, usdz, preview]
        return {
            "schemaVersion": SCHEMA_VERSION,
            "cellID": self.cell_id,
            "blenderVersion": bpy.app.version_string,
            "deterministicSeed": SEED,
            "meshCount": mesh_count,
            "triangleCount": triangle_count,
            "runtimeBindings": dict(sorted(binding.items())),
            "outputs": {
                str(path.relative_to(self.cell_dir)): {
                    "sha256": _sha256(path),
                    "bytes": path.stat().st_size,
                }
                for path in files
            },
        }


def _shared_materials(builder: SceneBuilder) -> dict[str, bpy.types.Material]:
    return {
        "dark": builder.material("dark-opening", (0.004, 0.005, 0.005), roughness=1.0),
        "earth": builder.material("loess-earth", (0.22, 0.17, 0.10), roughness=0.98),
        "wet_earth": builder.material("wet-earth", (0.075, 0.065, 0.046), roughness=0.78),
        "stone": builder.material("iron-gates-limestone", (0.21, 0.235, 0.215), roughness=0.88),
        "wood": builder.material("worked-oak", (0.20, 0.095, 0.038), roughness=0.82),
        "old_wood": builder.material("weathered-oak", (0.105, 0.076, 0.048), roughness=0.93),
        "rope": builder.material("bast-rope", (0.32, 0.235, 0.115), roughness=0.99),
        "thatch": builder.material("dry-reed-thatch", (0.34, 0.255, 0.105), roughness=1.0),
        "reed": builder.material("river-reed", (0.18, 0.23, 0.115), roughness=0.96),
        "water": builder.material("danube-water", (0.015, 0.055, 0.052), roughness=0.20, metallic=0.05),
        "water_glint": builder.material("water-surface-glint", (0.16, 0.22, 0.20), roughness=0.26, alpha=0.68),
        "mist": builder.material("river-mist", (0.24, 0.28, 0.27), roughness=0.92, alpha=0.025),
        "smoke": builder.material("hearth-smoke", (0.10, 0.11, 0.10), roughness=0.96, alpha=0.06),
        "skin": builder.material("human-skin-midtones", (0.36, 0.225, 0.14), roughness=0.70),
        "cloth": builder.material("undyed-woven-flax", (0.29, 0.245, 0.17), roughness=0.98),
        "cloth_dark": builder.material("smoke-dark-wool", (0.095, 0.085, 0.066), roughness=0.99),
        "hair": builder.material("dark-hair", (0.025, 0.018, 0.012), roughness=0.90),
        "hide": builder.material("cattle-hide", (0.18, 0.105, 0.052), roughness=0.88),
        "hide_light": builder.material("cattle-hide-light", (0.38, 0.30, 0.19), roughness=0.90),
        "bone": builder.material("bone-and-horn", (0.45, 0.41, 0.30), roughness=0.72),
        "clay": builder.material("fired-clay", (0.31, 0.105, 0.050), roughness=0.90),
        "grain": builder.material("dry-grain", (0.52, 0.345, 0.095), roughness=0.90),
        "green": builder.material("field-green", (0.105, 0.18, 0.075), roughness=0.95),
        "regrowth": builder.material("regrowth-green", (0.075, 0.135, 0.062), roughness=1.0),
        "ash": builder.material("cold-ash", (0.11, 0.105, 0.095), roughness=1.0),
        "ember": builder.material("hearth-ember", (0.30, 0.035, 0.006), roughness=0.65, emission=(1.0, 0.10, 0.01), emission_strength=3.5),
        "flame": builder.material("hearth-flame", (0.7, 0.12, 0.01), roughness=0.4, emission=(1.0, 0.18, 0.01), emission_strength=6.0),
        "collision": builder.material("collision-debug-hidden", (0.01, 0.01, 0.01), roughness=1.0, alpha=0.0),
    }


def _make_water_strip(
    builder: SceneBuilder,
    name: str,
    *,
    y_start: float,
    y_end: float,
    segments: int,
    half_width: Callable[[float], float],
    center: Callable[[float], float],
    height: Callable[[float], float],
    material: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    vertices = []
    for index in range(segments + 1):
        t = index / segments
        y = y_start + (y_end - y_start) * t
        c = center(y)
        width = half_width(y)
        z = height(y)
        vertices.extend(((c - width, y, z), (c + width, y, z)))
    faces = []
    for index in range(segments):
        a = index * 2
        faces.append((a, a + 1, a + 3, a + 2))
    return builder.mesh(name, vertices, faces, material, parent=parent, collision="static-triangle-mesh")


def _make_boat(
    builder: SceneBuilder,
    name: str,
    location: Sequence[float],
    *,
    parent: bpy.types.Object,
    wood: bpy.types.Material,
) -> bpy.types.Object:
    group = builder.empty(name, location, parent=parent, semantic_role="working-river-boat")
    sections = 12
    vertices: list[tuple[float, float, float]] = []
    for index in range(sections + 1):
        t = index / sections
        y = -2.8 + 5.6 * t
        taper = max(0.08, math.sin(math.pi * t))
        width = 0.68 * taper
        lift = 0.18 + 0.34 * abs(2 * t - 1) ** 1.7
        vertices.extend(
            [
                (-width, y, lift + 0.30),
                (-width * 0.72, y, lift - 0.14),
                (0.0, y, lift - 0.30),
                (width * 0.72, y, lift - 0.14),
                (width, y, lift + 0.30),
            ]
        )
    faces: list[tuple[int, int, int, int]] = []
    for section in range(sections):
        offset = section * 5
        nxt = offset + 5
        for band in range(4):
            faces.append((offset + band, offset + band + 1, nxt + band + 1, nxt + band))
    hull = builder.mesh(f"{name}-hull", vertices, faces, wood, parent=group, collision="convex-hull")
    hull["lod_group"] = name
    hull["lod_level"] = 0
    for index, y in enumerate((-1.6, -0.6, 0.5, 1.5)):
        builder.cylinder(f"{name}-rib-{index}", (-0.54, y, 0.42), (0.54, y, 0.42), 0.045, wood, vertices=8, parent=group)
    builder.cube(f"{name}-lod1", (0, 0, 0.22), (1.05, 5.2, 0.46), wood, parent=group, collection="LOD", state="lod1", bevel=0.12)
    return group


def build_iron_gates(builder: SceneBuilder) -> None:
    builder.reset()
    mat = _shared_materials(builder)
    root = builder.empty("iron-gates-riverbank", semantic_role="world-cell-root")
    builder.root = root
    default = builder.empty("state-default", parent=root, collection="STATES", semantic_role="state-container")
    tensioned = builder.empty("state-landing-tensioned", parent=root, collection="STATES", semantic_role="state-container", state="landing-tensioned")
    exchange = builder.empty("state-material-exchange", parent=root, collection="STATES", semantic_role="state-container", state="material-exchange")
    departure = builder.empty("state-departure", parent=root, collection="STATES", semantic_role="state-container", state="departure")

    def gorge_height(x: float, y: float) -> float:
        river_center = 0.55 * math.sin(y * 0.12)
        distance = abs(x - river_center)
        bank = max(0.0, distance - 2.45)
        ridge = 0.30 * math.sin(x * 0.8 + y * 0.20) + 0.15 * math.sin(y * 0.7)
        return -0.50 + bank * 0.77 + bank * bank * 0.055 + ridge

    builder.terrain(
        "iron-gates-gorge-terrain-lod0",
        x_min=-15,
        x_max=15,
        y_min=-12,
        y_max=34,
        x_steps=42,
        y_steps=58,
        height=gorge_height,
        material=mat["stone"],
        parent=default,
    )["lod_level"] = 0
    for level, steps in ((1, (20, 28)), (2, (9, 14))):
        lod_terrain = builder.terrain(
            f"iron-gates-gorge-terrain-lod{level}",
            x_min=-15,
            x_max=15,
            y_min=-12,
            y_max=34,
            x_steps=steps[0],
            y_steps=steps[1],
            height=gorge_height,
            material=mat["stone"],
            parent=root,
            collection="LOD",
        )
        lod_terrain["lod_group"] = "iron-gates-gorge-terrain"
        lod_terrain["lod_level"] = level
        lod_terrain.hide_render = True
    _make_water_strip(
        builder,
        "iron-gates-danube-water",
        y_start=-13,
        y_end=35,
        segments=72,
        half_width=lambda y: 2.15 + 0.20 * math.sin(y * 0.17),
        center=lambda y: 0.55 * math.sin(y * 0.12),
        height=lambda y: -0.49 + 0.012 * math.sin(y * 0.9),
        material=mat["water"],
        parent=default,
    )
    for index in range(14):
        y = -7.0 + index * 1.75
        center = 0.55 * math.sin(y * 0.12)
        offset = (-1 if index % 2 else 1) * (0.28 + 0.13 * (index % 4))
        builder.path_mesh(
            f"danube-current-glint-{index}",
            [
                (center - 0.72 + offset, y, -0.455),
                (center + offset, y + 0.16, -0.445),
                (center + 0.72 + offset, y + 0.04, -0.455),
            ],
            0.012,
            mat["water_glint"],
            parent=default,
            semantic_role="water-current-detail",
        )
    builder.mesh(
        "iron-gates-mist-near",
        [(-5.6, 10.5, -0.25), (5.6, 10.5, -0.25), (5.6, 10.5, 4.5), (-5.6, 10.5, 4.5)],
        [(0, 1, 2, 3)],
        mat["mist"],
        parent=default,
        semantic_role="spatial-atmosphere",
    )
    builder.mesh(
        "iron-gates-mist-far",
        [(-7.5, 25.0, 0.0), (7.5, 25.0, 0.0), (7.5, 25.0, 7.5), (-7.5, 25.0, 7.5)],
        [(0, 1, 2, 3)],
        mat["mist"],
        parent=default,
        semantic_role="spatial-atmosphere",
    )
    # Layered rock ledges preserve the steep Iron Gates silhouette on portrait.
    for side in (-1, 1):
        for index in range(3, 9):
            y = -4 + index * 4.4
            x = side * (7.0 + 0.45 * math.sin(index * 1.7))
            builder.ellipsoid(
                f"gorge-rock-{side}-{index}",
                (x, y, 1.4 + (index % 3) * 1.2),
                (2.25, 1.75, 2.2 + (index % 2)),
                mat["stone"],
                subdivisions=1,
                parent=default,
            )
    for index in range(26):
        y = -8 + index * 1.55
        x = (3.3 + 0.15 * math.sin(y)) * (-1 if index % 5 == 0 else 1)
        builder.cylinder(f"bank-reed-{index}", (x, y, -0.32), (x + 0.06, y, 0.58 + 0.15 * (index % 3)), 0.025, mat["reed"], vertices=6, parent=default)

    boat = _make_boat(builder, "iron-gates-boat", (-0.30, -1.0, -0.14), parent=default, wood=mat["old_wood"])
    boat.rotation_euler[2] = math.radians(-7)
    guide = builder.human("iron-gates-local-guide", (-0.26, -0.20, 0.30), parent=boat, skin=mat["skin"], cloth=mat["cloth_dark"], hair=mat["hair"], facing=math.radians(4), pose="pole", scale=0.92)
    builder.cylinder(
        "guide-pole",
        (-0.48, 0.25, 0.42),
        (0.58, -0.52, 4.28),
        0.035,
        mat["wood"],
        vertices=10,
        parent=guide,
        semantic_role="shared-navigation-tool",
        collision="capsule",
        interaction_id="first-farmers-iron-gates-cooperation",
    )
    builder.human("iron-gates-boat-worker", (0.30, -1.52, 0.32), parent=boat, skin=mat["skin"], cloth=mat["cloth"], hair=mat["hair"], facing=math.radians(-12), pose="carry", scale=0.95)
    line_points = [(-1.0, -6.15, 0.82), (-0.55, -3.55, 0.68), (-0.62, -1.20, 0.62), (0.75, -0.55, 0.33), (2.15, -0.15, 0.20), (3.62, 0.15, 0.40)]
    builder.path_mesh(
        "action-landing-line",
        line_points,
        0.07,
        mat["rope"],
        parent=default,
        semantic_role="principal-action",
        collision="compound-capsules",
        interaction_id="first-farmers-iron-gates-cooperation",
    )
    builder.cylinder("landing-line-mooring-post", (3.60, 0.15, -0.05), (3.60, 0.15, 1.40), 0.11, mat["wood"], parent=default)
    builder.ellipsoid("boat-cargo-vessel", (-0.35, -2.25, 0.46), (0.32, 0.32, 0.42), mat["clay"], parent=boat, semantic_role="shared-material")
    builder.cube("boat-cargo-basket", (0.35, -2.0, 0.38), (0.62, 0.52, 0.38), mat["rope"], parent=boat, semantic_role="shared-material", bevel=0.10)

    # Fishing settlement and exchange material on the landing shelf.
    builder.hut("iron-gates-fishing-hut-a", (5.25, 3.0, gorge_height(5.25, 3.0)), parent=default, wall=mat["earth"], thatch=mat["thatch"], scale=0.88)
    builder.hut("iron-gates-fishing-hut-b", (6.2, 7.0, gorge_height(6.2, 7.0)), parent=default, wall=mat["earth"], thatch=mat["thatch"], scale=0.74)
    for index, (x, y, size) in enumerate(((5.25, 3.0, 0.46), (6.2, 7.0, 0.38))):
        z = gorge_height(x, y) + 2.75 * (size / 0.46)
        for puff in range(4):
            smoke = builder.ellipsoid(
                f"iron-gates-hearth-smoke-{index}-{puff}",
                (x + 0.08 * math.sin(puff), y, z + puff * 0.60),
                (size * (1.0 + puff * 0.22), size * 0.62, size * 0.72),
                mat["smoke"],
                subdivisions=2,
                parent=default,
                semantic_role="source-bound-smoke",
            )
            smoke.hide_render = True
    for index in range(4):
        x = 4.25 + index * 0.42
        builder.cylinder(f"fish-drying-rack-post-{index}", (x, 1.62, 0.40), (x, 1.62, 1.76), 0.035, mat["wood"], vertices=8, parent=default)
    builder.cylinder("fish-drying-rack-crossbar", (4.20, 1.62, 1.56), (5.60, 1.62, 1.56), 0.035, mat["wood"], vertices=8, parent=default)
    for index in range(5):
        builder.ellipsoid(f"drying-fish-{index}", (4.38 + index * 0.25, 1.60, 1.32), (0.15, 0.035, 0.05), mat["bone"], subdivisions=1, parent=default)
    resident = builder.human("iron-gates-settlement-resident", (4.18, 0.62, gorge_height(4.18, 0.62)), parent=default, skin=mat["skin"], cloth=mat["cloth_dark"], hair=mat["hair"], facing=math.radians(205), pose="carry", scale=0.93)
    builder.human("iron-gates-line-receiver", (3.45, 0.18, gorge_height(3.45, 0.18)), parent=default, skin=mat["skin"], cloth=mat["cloth"], hair=mat["hair"], facing=math.radians(198), pose="work", scale=0.96)
    builder.human("iron-gates-bank-worker", (4.78, 1.62, gorge_height(4.78, 1.62)), parent=default, skin=mat["skin"], cloth=mat["cloth_dark"], hair=mat["hair"], facing=math.radians(222), pose="carry", scale=0.88)
    for index, (x, y, s) in enumerate(((3.1, 0.92, 0.34), (3.6, 1.18, 0.27), (4.35, 1.0, 0.30))):
        builder.ellipsoid(
            f"landing-cargo-vessel-{index}",
            (x, y, gorge_height(x, y) + s),
            (s * 0.72, s * 0.72, s),
            mat["clay"],
            subdivisions=3,
            parent=default,
            semantic_role="material-exchange",
        )
    builder.ellipsoid("exchange-clay-vessel", (3.72, 0.42, 0.66), (0.27, 0.27, 0.40), mat["clay"], parent=exchange, semantic_role="material-exchange")
    builder.cube("exchange-reed-bundle", (3.25, 0.10, 0.42), (0.70, 0.32, 0.34), mat["reed"], parent=exchange, semantic_role="material-exchange", bevel=0.05)
    builder.path_mesh("landing-line-tensioned", line_points[:-1] + [(3.60, 0.15, 1.02)], 0.075, mat["rope"], parent=tensioned, state="landing-tensioned")
    builder.path_mesh(
        "departure-river-carrier",
        [(-0.3, 0.0, -0.40), (0.1, 5.0, -0.40), (0.6, 11.0, -0.40)],
        0.12,
        mat["water"],
        parent=departure,
        semantic_role="transition-carrier",
        state="departure",
    )
    tensioned.hide_render = True
    exchange.hide_render = True
    departure.hide_render = True

    builder.anchor("camera-iron-gates-entry", (1.80, -8.80, 2.25), (0.10, 0.10, 0.55), category="camera-anchor", parent=root)
    builder.anchor("camera-iron-gates-landing", (5.25, -6.80, 3.20), (0.40, -0.15, 0.65), category="camera-anchor", parent=root)
    builder.anchor("camera-iron-gates-handoff", (4.85, -1.80, 2.20), (3.75, 0.35, 0.75), category="camera-anchor", parent=root)
    builder.anchor("camera-iron-gates-reduce-motion", (4.50, -8.00, 3.65), (0.30, 0.0, 0.70), category="reduce-motion-camera-anchor", parent=root)
    builder.anchor("transition-in-river-current", (0.0, -12.0, -0.20), (0.0, 0.0, 0.0), category="transition-anchor", parent=root)
    builder.anchor("transition-out-shared-material", (3.65, 0.22, 0.82), (0.0, 8.0, 0.0), category="transition-anchor", parent=root)
    builder.set_preview_camera("preview-camera-iron-gates", (-1.10, -6.95, 1.84), (1.72, 0.32, 0.72), lens=36)
    builder.sun("iron-gates-overcast-key", (math.radians(42), math.radians(-26), math.radians(-35)), 1.35, (0.71, 0.78, 0.72))
    builder.area_light("iron-gates-action-light", (1.9, -2.5, 5.5), (0.3, -0.2, 0.4), (0.92, 0.70, 0.43), 410, 5.0, parent=root)
    builder.add_lod_markers(root, (30, 47, 15))
    builder.finish_scene()


def _make_longhouse_frame(builder: SceneBuilder, parent: bpy.types.Object, mat: dict) -> bpy.types.Object:
    frame = builder.empty("longhouse-frame", parent=parent, semantic_role="durable-building-frame")
    length = 18.0
    for row, x in enumerate((-2.45, 0.0, 2.45)):
        for index in range(7):
            y = -length / 2 + index * length / 6
            height = 4.55 if row == 1 else 3.10
            builder.cylinder(f"longhouse-post-{row}-{index}", (x, y, -0.25), (x, y, height), 0.13 if row == 1 else 0.11, mat["wood"], vertices=10, parent=frame)
    for side, x in enumerate((-2.45, 2.45)):
        builder.cylinder(f"longhouse-wall-plate-{side}", (x, -9.2, 3.10), (x, 9.2, 3.10), 0.13, mat["wood"], vertices=10, parent=frame)
    builder.cylinder("longhouse-ridge-beam", (0, -9.2, 4.55), (0, 9.2, 4.55), 0.15, mat["wood"], vertices=12, parent=frame)
    for index in range(13):
        y = -9.0 + index * 1.5
        builder.cylinder(f"longhouse-rafter-left-{index}", (-2.65, y, 3.00), (0, y, 4.65), 0.07, mat["old_wood"], vertices=8, parent=frame)
        builder.cylinder(f"longhouse-rafter-right-{index}", (2.65, y, 3.00), (0, y, 4.65), 0.07, mat["old_wood"], vertices=8, parent=frame)
    return frame


def build_longhouse(builder: SceneBuilder) -> None:
    builder.reset()
    mat = _shared_materials(builder)
    root = builder.empty("danube-loess-longhouse", semantic_role="world-cell-root")
    builder.root = root
    default = builder.empty("state-default", parent=root, collection="STATES", semantic_role="state-container")
    raised = builder.empty("state-frame-raised", parent=root, collection="STATES", semantic_role="state-container", state="frame-raised")
    storm = builder.empty("state-storm-damaged", parent=root, collection="STATES", semantic_role="state-container", state="storm-damaged")
    repaired = builder.empty("state-repaired", parent=root, collection="STATES", semantic_role="state-container", state="repaired")
    succession = builder.empty("state-succession", parent=root, collection="STATES", semantic_role="state-container", state="succession")

    builder.terrain(
        "longhouse-loess-ground",
        x_min=-12,
        x_max=12,
        y_min=-16,
        y_max=18,
        x_steps=28,
        y_steps=38,
        height=lambda x, y: -0.28 + 0.08 * math.sin(x * 0.7) + 0.05 * math.sin(y * 0.46),
        material=mat["earth"],
        parent=default,
    )
    for level, steps in ((1, (14, 20)), (2, (7, 10))):
        lod_ground = builder.terrain(
            f"longhouse-loess-ground-lod{level}",
            x_min=-12,
            x_max=12,
            y_min=-16,
            y_max=18,
            x_steps=steps[0],
            y_steps=steps[1],
            height=lambda x, y: -0.28 + 0.08 * math.sin(x * 0.7) + 0.05 * math.sin(y * 0.46),
            material=mat["earth"],
            parent=root,
            collection="LOD",
        )
        lod_ground["lod_group"] = "longhouse-loess-ground"
        lod_ground["lod_level"] = level
        lod_ground.hide_render = True
    frame = _make_longhouse_frame(builder, default, mat)
    action_posts = builder.empty("action-posts", (0, 0, 0), parent=default, semantic_role="principal-action", interaction_id="first-farmers-house-assemble")
    for index, x in enumerate((-2.45, 0.0, 2.45)):
        post = builder.cylinder(f"action-post-{index}", (x, -7.4, -0.20), (x, -7.4, 3.15 if x else 4.55), 0.15, mat["wood"], vertices=10, parent=action_posts, collision="capsule")
        post["interaction_id"] = "first-farmers-house-assemble"
    action_posts["collision_ready"] = True
    action_posts["collision_shape"] = "compound-capsules"

    # Wattle panels leave the structure readable rather than closing it into a dark box.
    for side, x in enumerate((-2.58, 2.58)):
        for section in range(6):
            y = -7.2 + section * 2.65
            panel = builder.empty(f"wattle-panel-{side}-{section}", (x, y, 0), parent=default)
            for vertical in range(5):
                yy = -1.05 + vertical * 0.52
                builder.cylinder(f"wattle-upright-{side}-{section}-{vertical}", (0, yy, 0.05), (0, yy, 2.55), 0.025, mat["old_wood"], vertices=6, parent=panel)
            for horizontal in range(7):
                z = 0.30 + horizontal * 0.33
                builder.cylinder(f"wattle-weave-{side}-{section}-{horizontal}", (0, -1.22, z), (0, 1.22, z), 0.022, mat["rope"], vertices=6, parent=panel)

    roof = builder.empty("action-roof", parent=default, semantic_role="principal-action-component", interaction_id="first-farmers-house-assemble")
    for side in (-1, 1):
        for index in range(17):
            y = -8.5 + index * 1.06
            for bundle in range(3):
                yy = y + (bundle - 1) * 0.24
                thatch_piece = builder.cylinder(
                    f"thatch-roof-bundle-{side}-{index}-{bundle}",
                    (0.0, yy, 4.55),
                    (side * 2.86, yy, 2.89),
                    0.13 + 0.015 * ((index + bundle) % 2),
                    mat["thatch"],
                    vertices=8,
                    parent=roof,
                )
                if index < 6:
                    thatch_piece.hide_render = True
    roof["collision_ready"] = True
    roof["collision_shape"] = "compound-boxes"

    hearth = builder.empty("action-hearth", (0.0, -1.15, -0.05), parent=default, semantic_role="persistent-household-hearth", interaction_id="first-farmers-house-assemble")
    for index in range(12):
        angle = index / 12 * math.tau
        builder.ellipsoid(f"hearth-stone-{index}", (0.74 * math.cos(angle), 0.74 * math.sin(angle), 0.20), (0.24, 0.17, 0.13), mat["stone"], subdivisions=1, parent=hearth)
    builder.ellipsoid("hearth-ash-bed", (0, 0, 0.15), (0.62, 0.62, 0.10), mat["ash"], parent=hearth, collision="convex-hull")
    flame = builder.cone("action-hearth-flame", (0, 0, 0.68), 0.35, 0.02, 1.0, mat["flame"], vertices=10, parent=hearth, semantic_role="active-mechanism-light")
    flame["interaction_id"] = "first-farmers-house-assemble"
    storage = builder.empty("action-storage", (1.70, 3.7, 0), parent=default, semantic_role="persistent-storage", interaction_id="first-farmers-house-assemble")
    for index, (x, y, s) in enumerate(((0, 0, 1.0), (0.55, 0.18, 0.78), (-0.48, 0.28, 0.72))):
        builder.ellipsoid(f"storage-vessel-{index}", (x, y, 0.50 * s), (0.36 * s, 0.36 * s, 0.58 * s), mat["clay"], parent=storage, collision="convex-hull")
    storage["collision_ready"] = True
    storage["collision_shape"] = "compound-convex"

    # Postholes and repaired timber make endurance legible across time.
    for row, x in enumerate((-2.45, 0.0, 2.45)):
        for index in range(7):
            y = -9 + index * 3
            builder.cylinder(f"posthole-{row}-{index}", (x, y, -0.42), (x, y, -0.18), 0.24, mat["wet_earth"], vertices=12, parent=default, semantic_role="persistent-trace")
    damaged = builder.cylinder("storm-broken-wall-plate", (-2.45, -1.3, 2.95), (-1.62, 0.6, 1.28), 0.16, mat["old_wood"], vertices=9, parent=storm, state="storm-damaged")
    repaired_beam = builder.cylinder("repaired-wall-plate", (-2.45, -2.8, 3.10), (-2.45, 2.8, 3.10), 0.17, mat["wood"], vertices=10, parent=repaired, state="repaired")
    for index, y in enumerate((-0.48, 0.48)):
        builder.cylinder(f"repair-lashing-{index}", (-2.64, y, 2.84), (-2.24, y, 3.34), 0.035, mat["rope"], vertices=8, parent=repaired, state="repaired")
    builder.cylinder("raised-frame-brace-left", (-2.45, -8.2, 0.0), (-2.45, -6.8, 2.75), 0.09, mat["old_wood"], vertices=8, parent=raised, state="frame-raised")
    builder.cylinder("raised-frame-brace-right", (2.45, -8.2, 0.0), (2.45, -6.8, 2.75), 0.09, mat["old_wood"], vertices=8, parent=raised, state="frame-raised")
    builder.cylinder("succession-replacement-post", (2.45, 6.0, -0.25), (2.45, 6.0, 3.10), 0.15, mat["wood"], vertices=10, parent=succession, state="succession")
    builder.path_mesh("succession-post-lashing", [(2.30, 6.0, 2.70), (2.60, 6.0, 3.03), (2.30, 6.0, 3.30)], 0.035, mat["rope"], parent=succession, state="succession")
    storm.hide_render = True
    repaired.hide_render = True
    raised.hide_render = True
    succession.hide_render = True

    builder.human("longhouse-worker-raising", (-3.18, -6.8, -0.10), parent=default, skin=mat["skin"], cloth=mat["cloth"], hair=mat["hair"], facing=math.radians(-38), pose="raise", scale=0.96)
    builder.human("longhouse-worker-pulling", (3.65, -9.15, -0.12), parent=default, skin=mat["skin"], cloth=mat["cloth_dark"], hair=mat["hair"], facing=math.radians(155), pose="raise", scale=0.98)
    builder.human("longhouse-worker-weaving", (3.18, -2.15, -0.12), parent=default, skin=mat["skin"], cloth=mat["cloth_dark"], hair=mat["hair"], facing=math.radians(142), pose="work", scale=0.92)
    builder.human("longhouse-worker-storage", (1.1, 3.0, -0.12), parent=default, skin=mat["skin"], cloth=mat["cloth"], hair=mat["hair"], facing=math.radians(-12), pose="carry", scale=0.88)
    builder.path_mesh(
        "longhouse-raising-line",
        [(-2.45, -7.4, 3.25), (-0.5, -8.1, 2.45), (2.0, -8.8, 1.25), (4.2, -9.6, 0.62)],
        0.055,
        mat["rope"],
        parent=default,
        semantic_role="shared-building-force",
        collision="compound-capsules",
        interaction_id="first-farmers-house-assemble",
    )

    builder.anchor("camera-longhouse-approach", (8.9, -13.8, 4.7), (0.0, -1.0, 2.15), category="camera-anchor", parent=root)
    builder.anchor("camera-longhouse-raise", (5.2, -9.8, 2.8), (-0.8, -6.7, 2.0), category="camera-anchor", parent=root)
    builder.anchor("camera-longhouse-hearth", (4.9, -4.8, 2.0), (0.0, -1.0, 0.62), category="camera-anchor", parent=root)
    builder.anchor("camera-longhouse-repair", (-6.4, -4.5, 3.4), (-2.45, 0.0, 3.0), category="camera-anchor", parent=root)
    builder.anchor("camera-longhouse-reduce-motion", (8.7, -12.8, 5.0), (0.0, -0.5, 2.0), category="reduce-motion-camera-anchor", parent=root)
    builder.anchor("transition-in-threshold", (0.0, -10.2, 0.0), (0.0, -2.0, 1.0), category="transition-anchor", parent=root)
    builder.anchor("transition-out-surviving-posthole", (0.0, 8.7, -0.18), (0.0, 15.0, 0.0), category="transition-anchor", parent=root)
    builder.set_preview_camera("preview-camera-longhouse", (7.4, -14.0, 4.20), (-1.75, -6.25, 1.65), lens=45)
    builder.sun("longhouse-cool-daylight", (math.radians(38), math.radians(-24), math.radians(-48)), 1.30, (0.68, 0.74, 0.69))
    builder.area_light("longhouse-hearth-light", (0.0, -1.1, 3.1), (0.0, -1.1, 0.4), (1.0, 0.28, 0.05), 220, 2.5, parent=root)
    builder.area_light("longhouse-action-light", (5.4, -7.2, 5.8), (-0.3, -5.5, 1.8), (0.76, 0.84, 0.76), 560, 5.0, parent=root)
    builder.add_lod_markers(root, (24, 34, 9))
    builder.finish_scene()


def _make_field(
    builder: SceneBuilder,
    name: str,
    location: Sequence[float],
    dimensions: Sequence[float],
    *,
    parent: bpy.types.Object,
    earth: bpy.types.Material,
    grain: bpy.types.Material,
    rows: int,
    state: str = "default",
) -> bpy.types.Object:
    group = builder.empty(name, location, parent=parent, semantic_role="worked-field", state=state)
    builder.cube(f"{name}-soil", (0, 0, 0.02), dimensions, earth, parent=group, state=state)
    for row in range(rows):
        y = -dimensions[1] * 0.42 + row * dimensions[1] * 0.84 / max(1, rows - 1)
        for plant in range(8):
            x = -dimensions[0] * 0.42 + plant * dimensions[0] * 0.84 / 7
            builder.cylinder(f"{name}-crop-{row}-{plant}", (x, y, 0.08), (x + 0.02 * (row % 2), y, 0.54), 0.013, grain, vertices=5, parent=group, state=state)
    return group


def build_settlement(builder: SceneBuilder) -> None:
    builder.reset()
    mat = _shared_materials(builder)
    root = builder.empty("expanding-settlement-landscape", semantic_role="world-cell-root")
    builder.root = root
    default = builder.empty("state-default", parent=root, collection="STATES", semantic_role="state-container")
    route_open = builder.empty("state-herd-route-open", parent=root, collection="STATES", semantic_role="state-container", state="herd-route-open")
    daughter_grown = builder.empty("state-daughter-settlement-grown", parent=root, collection="STATES", semantic_role="state-container", state="daughter-settlement-grown")
    regrowth = builder.empty("state-abandoned-regrowth", parent=root, collection="STATES", semantic_role="state-container", state="abandoned-regrowth")
    final = builder.empty("state-continent-transformed", parent=root, collection="STATES", semantic_role="state-container", state="continent-transformed")

    def valley_height(x: float, y: float) -> float:
        slope = 0.04 * y
        valley = max(0.0, abs(x - 1.0) - 3.1) * 0.20
        return -0.25 + slope + valley + 0.10 * math.sin(x * 0.47) * math.cos(y * 0.28)

    daughter_grown.location = (-3.7, 23.0, valley_height(-3.7, 23.0))
    final.location = (-1.25, 14.8, valley_height(-1.25, 14.8))

    builder.terrain(
        "expansion-valley-terrain-lod0",
        x_min=-19,
        x_max=19,
        y_min=-18,
        y_max=38,
        x_steps=50,
        y_steps=65,
        height=valley_height,
        material=mat["green"],
        parent=default,
    )
    for level, steps in ((1, (24, 32)), (2, (10, 14))):
        lod_terrain = builder.terrain(
            f"expansion-valley-terrain-lod{level}",
            x_min=-19,
            x_max=19,
            y_min=-18,
            y_max=38,
            x_steps=steps[0],
            y_steps=steps[1],
            height=valley_height,
            material=mat["green"],
            parent=root,
            collection="LOD",
        )
        lod_terrain["lod_group"] = "expansion-valley-terrain"
        lod_terrain["lod_level"] = level
        lod_terrain.hide_render = True
    _make_water_strip(
        builder,
        "valley-water",
        y_start=-19,
        y_end=40,
        segments=72,
        half_width=lambda y: 1.12 + 0.08 * math.sin(y * 0.3),
        center=lambda y: 1.0 + 0.65 * math.sin(y * 0.10),
        height=lambda y: valley_height(1.0, y) - 0.06,
        material=mat["water"],
        parent=default,
    )

    route_points = [(-7.2, -10.0, valley_height(-7.2, -10.0) + 0.06), (-5.8, -4.0, valley_height(-5.8, -4.0) + 0.06), (-4.1, 2.0, valley_height(-4.1, 2.0) + 0.06), (-2.2, 8.5, valley_height(-2.2, 8.5) + 0.06), (-1.0, 15.0, valley_height(-1.0, 15.0) + 0.06), (-3.5, 23.0, valley_height(-3.5, 23.0) + 0.06)]
    builder.path_mesh("action-herd-route", route_points, 0.19, mat["wet_earth"], parent=default, semantic_role="principal-action", collision="compound-capsules", interaction_id="first-farmers-expansion-transform")
    herd = builder.empty("moving-herd", (-6.4, -7.0, valley_height(-6.4, -7.0)), parent=default, semantic_role="dependent-herd", interaction_id="first-farmers-expansion-transform")
    for index, (x, y, facing) in enumerate(((0, 0, 0.1), (1.35, -0.65, -0.1), (-1.2, -0.9, 0.2), (0.40, -1.8, -0.12), (-1.65, -2.15, 0.08))):
        builder.cattle(f"herd-cattle-{index}", (x, y, 0), parent=herd, hide=mat["hide"] if index % 2 else mat["hide_light"], horn=mat["bone"], facing=facing, scale=0.78 + 0.04 * (index % 3))
    builder.human("herd-guide-adult", (-0.8, 0.65, 0.0), parent=herd, skin=mat["skin"], cloth=mat["cloth_dark"], hair=mat["hair"], facing=math.radians(18), pose="pole", scale=0.92)

    field = _make_field(builder, "parent-settlement-field", (-9.0, 2.0, valley_height(-9.0, 2.0)), (6.0, 7.8, 0.10), parent=default, earth=mat["earth"], grain=mat["grain"], rows=7)
    builder.hut("parent-settlement-house-a", (-11.8, -4.2, valley_height(-11.8, -4.2)), parent=default, wall=mat["earth"], thatch=mat["thatch"], scale=0.92)
    builder.hut("parent-settlement-house-b", (-8.9, -5.8, valley_height(-8.9, -5.8)), parent=default, wall=mat["earth"], thatch=mat["thatch"], scale=0.76)
    builder.ellipsoid("parent-settlement-grain-store", (-10.1, -2.8, valley_height(-10.1, -2.8) + 0.52), (0.46, 0.46, 0.64), mat["clay"], parent=default, semantic_role="persistent-storage")
    # A timber-and-brush field edge, intended to resist animal pressure rather than decorate it.
    for index in range(12):
        y = -1.5 + index * 0.70
        builder.cylinder(f"field-edge-post-{index}", (-5.85, y, valley_height(-5.85, y)), (-5.85, y, valley_height(-5.85, y) + 1.0), 0.055, mat["wood"], vertices=8, parent=default)
    for index in range(2):
        z = 0.38 + index * 0.42
        builder.cylinder(f"field-edge-rail-{index}", (-5.85, -1.7, valley_height(-5.85, -1.7) + z), (-5.85, 6.6, valley_height(-5.85, 6.6) + z), 0.055, mat["old_wood"], vertices=8, parent=default)

    # Woodland margins frame the worked valley without obscuring the route.
    tree_points = [(-15.5, -7.0), (-14.8, -0.5), (-15.8, 7.0), (-14.2, 15.0), (-13.8, 24.0), (14.8, -4.0), (15.6, 5.0), (14.4, 14.0), (15.5, 25.0), (12.8, 32.0)]
    for index, (x, y) in enumerate(tree_points):
        z = valley_height(x, y)
        height = 3.4 + 0.35 * (index % 3)
        builder.cylinder(f"valley-tree-trunk-{index}", (x, y, z), (x, y, z + height), 0.18, mat["old_wood"], vertices=9, parent=default)
        builder.ellipsoid(f"valley-tree-crown-{index}-a", (x, y, z + height + 0.65), (1.0, 0.92, 1.25), mat["regrowth"], subdivisions=1, parent=default)
        builder.ellipsoid(f"valley-tree-crown-{index}-b", (x + 0.55, y - 0.2, z + height + 0.25), (0.85, 0.75, 0.90), mat["regrowth"], subdivisions=1, parent=default)

    daughter = builder.empty("daughter-settlement", (-3.7, 23.0, valley_height(-3.7, 23.0)), parent=default, semantic_role="persistent-daughter-settlement")
    builder.hut("daughter-house-a", (0, 0, 0), parent=daughter, wall=mat["earth"], thatch=mat["thatch"], scale=0.78)
    builder.hut("daughter-house-b", (2.2, 1.4, 0.05), parent=daughter, wall=mat["earth"], thatch=mat["thatch"], scale=0.66)
    builder.ellipsoid("daughter-store", (-1.55, 1.2, 0.42), (0.42, 0.42, 0.56), mat["clay"], parent=daughter, semantic_role="persistent-storage")
    _make_field(builder, "daughter-field", (-7.5, 24.0, valley_height(-7.5, 24.0)), (4.6, 5.4, 0.08), parent=default, earth=mat["earth"], grain=mat["grain"], rows=5)

    # Abandonment does not erase the former place: posts, path and regrowth coexist.
    for index in range(22):
        x = -10.8 + (index % 6) * 0.68
        y = 0.4 + (index // 6) * 1.15
        height = valley_height(x, y)
        builder.cone(f"regrowth-shrub-{index}", (x, y, height + 0.28), 0.30 + 0.08 * (index % 3), 0.05, 0.72 + 0.15 * (index % 2), mat["regrowth"], vertices=7, parent=regrowth, state="abandoned-regrowth")
    regrowth.hide_render = True

    gate = builder.empty("action-final-gate", (-1.25, 14.8, valley_height(-1.25, 14.8)), parent=default, semantic_role="principal-action", interaction_id="first-farmers-final-commitment")
    builder.cylinder("final-gate-post-left", (-1.4, 0, 0), (-1.4, 0, 2.15), 0.15, mat["wood"], vertices=10, parent=gate, collision="capsule")
    builder.cylinder("final-gate-post-right", (1.4, 0, 0), (1.4, 0, 2.15), 0.15, mat["wood"], vertices=10, parent=gate, collision="capsule")
    builder.cylinder("final-gate-barrier", (-1.55, 0, 1.25), (1.55, 0, 1.25), 0.17, mat["wood"], vertices=10, parent=gate, collision="capsule")
    gate["collision_ready"] = True
    gate["collision_shape"] = "compound-capsules"
    for index, point in enumerate(route_points[:]):
        trace = builder.ellipsoid(f"farming-trace-{index}", (point[0], point[1], point[2] + 0.02), (0.52, 0.76, 0.06), mat["wet_earth"], subdivisions=1, parent=default, semantic_role="persistent-working-trace")
        trace.rotation_euler[2] = math.radians(-12 + index * 5)
    for index in range(len(route_points), 10):
        y = 16.0 + (index - len(route_points)) * 3.2
        x = -1.4 - 0.5 * math.sin(index)
        trace = builder.ellipsoid(f"farming-trace-{index}", (x, y, valley_height(x, y) + 0.04), (0.50, 0.78, 0.06), mat["wet_earth"], subdivisions=1, parent=default, semantic_role="persistent-working-trace")
        trace.rotation_euler[2] = math.radians(8 + index * 3)

    builder.path_mesh(
        "herd-route-worn",
        route_points,
        0.27,
        mat["wet_earth"],
        parent=route_open,
        semantic_role="persistent-route",
        state="herd-route-open",
    )
    builder.hut("daughter-house-c", (-1.2, -1.7, 0.0), parent=daughter_grown, wall=mat["earth"], thatch=mat["thatch"], scale=0.62)
    builder.path_mesh(
        "final-gate-lashing",
        [(-1.45, 0.0, 1.02), (-1.05, 0.0, 1.45), (-0.62, 0.0, 1.05)],
        0.045,
        mat["rope"],
        parent=final,
        semantic_role="committed-barrier",
        state="continent-transformed",
    )
    final_herd = builder.empty(
        "final-barrier-herd",
        (-3.1, -1.2, 0.0),
        parent=final,
        semantic_role="dependent-herd",
        state="continent-transformed",
    )
    for index, (x, y) in enumerate(((0.0, 0.0), (-1.15, -0.35), (-0.45, 0.85))):
        builder.cattle(
            f"final-barrier-cattle-{index}",
            (x, y, 0.0),
            parent=final_herd,
            hide=mat["hide"] if index != 1 else mat["hide_light"],
            horn=mat["bone"],
            facing=math.radians(7 + index * 6),
            scale=0.82,
        )
    builder.human(
        "final-barrier-worker",
        (2.25, -0.65, 0.0),
        parent=final,
        skin=mat["skin"],
        cloth=mat["cloth_dark"],
        hair=mat["hair"],
        facing=math.radians(168),
        pose="work",
        scale=0.96,
    )

    route_open.hide_render = True
    daughter_grown.hide_render = True
    final.hide_render = True
    builder.anchor("camera-expansion-herd", (-0.8, -13.5, 5.0), (-5.8, -3.0, 0.7), category="camera-anchor", parent=root)
    builder.anchor("camera-expansion-field-edge", (-0.2, -3.4, 4.2), (-7.4, 2.3, 0.5), category="camera-anchor", parent=root)
    builder.anchor("camera-expansion-daughter", (5.6, 10.5, 6.1), (-3.6, 23.0, 1.1), category="camera-anchor", parent=root)
    builder.anchor("camera-expansion-final", (4.6, 9.2, 3.25), (-1.25, 14.8, 1.10), category="camera-anchor", parent=root)
    builder.anchor("camera-expansion-reduce-motion", (8.5, -10.5, 6.8), (-2.9, 8.5, 1.1), category="reduce-motion-camera-anchor", parent=root)
    builder.anchor("transition-in-surviving-posthole", (-8.9, 1.8, valley_height(-8.9, 1.8)), (-5.8, 4.0, 0.0), category="transition-anchor", parent=root)
    builder.anchor("transition-out-eastern-horizon", (-2.1, 36.0, valley_height(-2.1, 36.0) + 1.0), (-2.1, 55.0, 3.5), category="transition-anchor", parent=root)
    builder.set_preview_camera("preview-camera-settlement", (-0.4, -13.4, 2.85), (-6.25, -6.45, 0.68), lens=43)
    builder.sun("settlement-low-eastern-sun", (math.radians(49), math.radians(-20), math.radians(-55)), 1.45, (0.83, 0.70, 0.48))
    builder.area_light("settlement-herd-action-light", (-1.0, -7.4, 5.5), (-6.0, -5.6, 0.6), (0.88, 0.66, 0.38), 560, 5.2, parent=root)
    builder.area_light("settlement-gate-action-light", (4.8, 9.5, 7.0), (-1.2, 14.8, 1.0), (0.95, 0.65, 0.32), 900, 6.0, parent=root)
    builder.add_lod_markers(root, (38, 58, 13))
    builder.finish_scene()


BUILDERS = {
    "iron-gates": build_iron_gates,
    "longhouse": build_longhouse,
    "settlement": build_settlement,
}


def main(cell_id: str, cell_dir: Path) -> int:
    if bpy.app.version_string != BLENDER_VERSION:
        raise RuntimeError(
            f"Locked Blender version is {BLENDER_VERSION}; found {bpy.app.version_string}"
        )
    recipe = BUILDERS.get(cell_id)
    if recipe is None:
        raise ValueError(f"Unknown later Chapter 01 cell: {cell_id}")
    builder = SceneBuilder(cell_id, cell_dir)
    recipe(builder)
    report = builder.export()
    print("CHAPTER01_BUILD_REPORT=" + json.dumps(report, sort_keys=True, separators=(",", ":")))
    return 0


def validate(cell_id: str, cell_dir: Path) -> int:
    if bpy.app.version_string != BLENDER_VERSION:
        raise RuntimeError(
            f"Locked Blender version is {BLENDER_VERSION}; found {bpy.app.version_string}"
        )
    spec_path = cell_dir / "scene-spec.json"
    manifest_path = cell_dir / "build-manifest.json"
    bindings_path = cell_dir / "entity-bindings.json"
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
    failures: list[str] = []
    if spec.get("cellID") != cell_id:
        failures.append("scene-spec cellID mismatch")
    if manifest.get("cellID") != cell_id:
        failures.append("build-manifest cellID mismatch")
    if spec.get("assetStatus") != "CONTINUITY_PROOF":
        failures.append("scene-spec assetStatus must remain CONTINUITY_PROOF")
    if manifest.get("assetStatus") != "CONTINUITY_PROOF":
        failures.append("build-manifest assetStatus must remain CONTINUITY_PROOF")

    for relative, expected in manifest.get("inputs", {}).items():
        path = (cell_dir / relative).resolve()
        if not path.is_file():
            failures.append(f"missing input {relative}")
            continue
        actual = _sha256(path)
        if actual != expected.get("sha256"):
            failures.append(f"input hash mismatch {relative}: {actual}")

    for relative, expected in manifest.get("outputs", {}).items():
        path = cell_dir / relative
        if not path.is_file():
            failures.append(f"missing output {relative}")
            continue
        actual = _sha256(path)
        if expected.get("hashValidation", True) and actual != expected.get("sha256"):
            failures.append(f"hash mismatch {relative}: {actual}")
        if expected.get("sizeValidation", True) and path.stat().st_size != expected.get("bytes"):
            failures.append(f"size mismatch {relative}")

    stage_path = cell_dir / "exports" / f"{cell_id}.usdc"
    stage = Usd.Stage.Open(str(stage_path))
    if stage is None:
        failures.append("USDC stage failed to open")
    else:
        if UsdGeom.GetStageMetersPerUnit(stage) != 1.0:
            failures.append("metersPerUnit is not 1")
        if UsdGeom.GetStageUpAxis(stage) != UsdGeom.Tokens.z:
            failures.append("upAxis is not Z")
        found: dict[str, Usd.Prim] = {}
        duplicate_runtime_names: set[str] = set()
        mesh_count = 0
        triangle_count = 0
        for prim in stage.Traverse():
            if prim.IsA(UsdGeom.Mesh):
                mesh_count += 1
                counts = UsdGeom.Mesh(prim).GetFaceVertexCountsAttr().Get()
                triangle_count += len(counts) if counts is not None else 0
            attr = prim.GetAttribute("userProperties:runtime_name")
            runtime_name = attr.Get() if attr else None
            if runtime_name:
                runtime_name = str(runtime_name)
                if runtime_name in found:
                    duplicate_runtime_names.add(runtime_name)
                found[runtime_name] = prim
            for attribute in prim.GetAttributes():
                type_name = attribute.GetTypeName()
                if type_name == Sdf.ValueTypeNames.Asset:
                    value = attribute.Get()
                    if value and (os.path.isabs(str(value.path)) or ".." in str(value.path)):
                        failures.append(f"non-package asset path on {prim.GetPath()}: {value.path}")
        for runtime_name in sorted(duplicate_runtime_names):
            failures.append(f"duplicate runtime entity {runtime_name}")
        expected_counts = manifest.get("counts", {})
        if mesh_count != expected_counts.get("meshObjects"):
            failures.append(
                f"mesh count mismatch: {mesh_count} != {expected_counts.get('meshObjects')}"
            )
        if triangle_count != expected_counts.get("triangles"):
            failures.append(
                f"triangle count mismatch: {triangle_count} != {expected_counts.get('triangles')}"
            )
        for required in spec.get("requiredEntities", []):
            runtime_name = required["runtimeName"]
            prim = found.get(runtime_name)
            if prim is None:
                failures.append(f"missing runtime entity {runtime_name}")
                continue
            if prim.GetDisplayName() != runtime_name:
                failures.append(f"displayName mismatch for {runtime_name}")
            expected_role = required.get("semanticRole")
            role_attr = prim.GetAttribute("userProperties:semantic_role")
            if expected_role and (not role_attr or role_attr.Get() != expected_role):
                failures.append(f"semantic role mismatch for {runtime_name}")
            if required.get("collisionReady"):
                collision_attr = prim.GetAttribute("userProperties:collision_ready")
                if not collision_attr or not collision_attr.Get():
                    failures.append(f"collision metadata missing for {runtime_name}")
            expected_interaction = required.get("interactionID")
            interaction_attr = prim.GetAttribute("userProperties:interaction_id")
            if expected_interaction and (
                not interaction_attr or interaction_attr.Get() != expected_interaction
            ):
                failures.append(f"interaction binding mismatch for {runtime_name}")
        for state_name in spec.get("stateCollections", []):
            if state_name not in found:
                failures.append(f"missing state collection {state_name}")
        for level in range(3):
            if f"lod-{level}-contract" not in found:
                failures.append(f"missing LOD contract {level}")
        for runtime_name, expected_path in bindings.get("runtimeNameToUSDPath", {}).items():
            prim = found.get(runtime_name)
            if prim is None:
                failures.append(f"binding names absent runtime entity {runtime_name}")
            elif str(prim.GetPath()) != expected_path:
                failures.append(
                    f"binding path mismatch {runtime_name}: {prim.GetPath()} != {expected_path}"
                )

    usdz_path = cell_dir / "exports" / f"{cell_id}.usdz"
    try:
        with zipfile.ZipFile(usdz_path) as archive:
            members = archive.namelist()
            if len(members) != 1 or not members[0].endswith(".usdc"):
                failures.append(f"USDZ has unexpected members: {members}")
            bad = archive.testzip()
            if bad:
                failures.append(f"USDZ CRC failure: {bad}")
    except zipfile.BadZipFile:
        failures.append("USDZ is not a valid archive")

    report = {
        "schemaVersion": SCHEMA_VERSION,
        "cellID": cell_id,
        "blenderVersion": bpy.app.version_string,
        "status": "PASS" if not failures else "FAIL",
        "failures": failures,
    }
    print("CHAPTER01_VALIDATION_REPORT=" + json.dumps(report, sort_keys=True, separators=(",", ":")))
    if failures:
        raise RuntimeError("; ".join(failures))
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("cell_id", choices=sorted(BUILDERS))
    parser.add_argument("cell_dir", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:])
    raise SystemExit(main(args.cell_id, args.cell_dir.resolve()))
