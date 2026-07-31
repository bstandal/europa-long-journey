#!/usr/bin/env python3
"""Compile the Chapter 01 directed animation candidate with Blender 5.2.

The JSON score is the authored authority. Blender creates an inspectable
action library while its bundled USD build writes a lightweight UsdSkel clip
library compatible with the pinned Chapter 01 hero skeleton.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import zipfile
from pathlib import Path

import bpy
from mathutils import Vector
from pxr import Gf, Sdf, Usd, UsdGeom, UsdSkel, Vt


EXPECTED_BLENDER = (5, 2, 0)
FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--library-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args(argv)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_blender() -> None:
    if tuple(bpy.app.version[:3]) != EXPECTED_BLENDER:
        raise RuntimeError(
            f"Blender {EXPECTED_BLENDER!r} is required; found {bpy.app.version[:3]!r}"
        )


def joint_leaf(joint_path: str) -> str:
    return joint_path.rsplit("/", 1)[-1]


def slug(value: str) -> str:
    cleaned = "".join(character if character.isalnum() else "_" for character in value)
    return cleaned.strip("_")


def quat_from_euler_degrees(degrees: list[float]) -> Gf.Quatf:
    x, y, z = degrees
    qx = Gf.Rotation(Gf.Vec3d(1, 0, 0), x).GetQuat()
    qy = Gf.Rotation(Gf.Vec3d(0, 1, 0), y).GetQuat()
    qz = Gf.Rotation(Gf.Vec3d(0, 0, 1), z).GetQuat()
    value = qx * qy * qz
    imaginary = value.GetImaginary()
    return Gf.Quatf(
        float(value.GetReal()),
        Gf.Vec3f(float(imaginary[0]), float(imaginary[1]), float(imaginary[2])),
    )


def compose_quat(base: Gf.Quatf, delta: Gf.Quatf) -> Gf.Quatf:
    value = base * delta
    return Gf.Quatf(float(value.GetReal()), Gf.Vec3f(value.GetImaginary()))


def read_hero_skeletons(library_dir: Path, spec: dict) -> dict[str, dict]:
    source = (library_dir / spec["rigContract"]["sourceAsset"]).resolve()
    stage = Usd.Stage.Open(str(source))
    if stage is None:
        raise RuntimeError(f"Could not open hero skeleton source: {source}")
    result = {}
    canonical_joints = None
    for profile in spec["rigContract"]["profiles"]:
        skeleton_path = profile["skeletonPath"]
        skeleton = UsdSkel.Skeleton(stage.GetPrimAtPath(skeleton_path))
        if not skeleton:
            raise RuntimeError(f"Missing skeleton at {skeleton_path}")
        joints = list(skeleton.GetJointsAttr().Get())
        if canonical_joints is None:
            canonical_joints = joints
        elif joints != canonical_joints:
            raise RuntimeError(f"Joint order diverged for rig profile {profile['id']}")
        rest = list(skeleton.GetRestTransformsAttr().Get())
        bind = list(skeleton.GetBindTransformsAttr().Get())
        translations, rotations, scales = UsdSkel.DecomposeTransforms(rest)
        leaves = [joint_leaf(str(joint)) for joint in joints]
        if len(leaves) != len(set(leaves)):
            raise RuntimeError("Hero skeleton has non-unique joint leaf names")
        result[profile["id"]] = {
            "profile": profile,
            "joints": joints,
            "rest": rest,
            "bind": bind,
            "translations": list(translations),
            "rotations": list(rotations),
            "scales": list(scales),
            "leafIndex": {name: index for index, name in enumerate(leaves)},
        }
    return result


def sample_key(key: dict, skeleton_data: dict) -> tuple:
    translations = [Gf.Vec3f(value) for value in skeleton_data["translations"]]
    rotations = [Gf.Quatf(value) for value in skeleton_data["rotations"]]
    scales = [Gf.Vec3h(value) for value in skeleton_data["scales"]]

    # The authored rootOffset is a local centre-of-mass shift. It is applied to
    # the pelvis so the actor root remains fixed and the domain/runtime owns all
    # world translation.
    offset = key.get("rootOffset", [0, 0, 0])
    pelvis_index = skeleton_data["leafIndex"]["pelvis"]
    pelvis = translations[pelvis_index]
    translations[pelvis_index] = Gf.Vec3f(
        pelvis[0] + offset[0], pelvis[1] + offset[1], pelvis[2] + offset[2]
    )

    for name, degrees in key["joints"].items():
        index = skeleton_data["leafIndex"][name]
        rotations[index] = compose_quat(rotations[index], quat_from_euler_degrees(degrees))

    return (
        Vt.Vec3fArray(translations),
        Vt.QuatfArray(rotations),
        Vt.Vec3hArray(scales),
    )


def build_usd(output: Path, spec: dict, skeleton_profiles: dict[str, dict]) -> None:
    stage = Usd.Stage.CreateNew(str(output))
    stage.SetStartTimeCode(0)
    stage.SetEndTimeCode(max(clip["durationFrames"] for clip in spec["clips"]))
    stage.SetTimeCodesPerSecond(spec["framesPerSecond"])
    stage.SetFramesPerSecond(spec["framesPerSecond"])
    stage.SetInterpolationType(Usd.InterpolationTypeLinear)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, spec["coordinateSystem"]["metersPerUnit"])

    library = UsdGeom.Xform.Define(stage, "/Chapter01DirectedAnimations")
    stage.SetDefaultPrim(library.GetPrim())
    library.GetPrim().SetCustomDataByKey("libraryID", spec["libraryID"])
    library.GetPrim().SetCustomDataByKey("classification", spec["classification"])
    library.GetPrim().SetCustomDataByKey("domainCompletion", "forbidden")

    for clip in spec["clips"]:
        clip_slug = slug(clip["id"])
        clip_path = Sdf.Path(f"/Chapter01DirectedAnimations/{clip_slug}")
        clip_root = UsdGeom.Xform.Define(stage, clip_path)
        clip_root.GetPrim().SetCustomDataByKey("clipID", clip["id"])
        clip_root.GetPrim().SetCustomDataByKey("loopMode", clip["loopMode"])
        clip_root.GetPrim().SetCustomDataByKey(
            "safeIncompleteFrame", int(clip["safeIncompleteFrame"])
        )
        for profile_id, skeleton_data in skeleton_profiles.items():
            profile = skeleton_data["profile"]
            if profile["role"] not in clip["roles"]:
                continue
            profile_slug = slug(profile_id)
            root_path = clip_path.AppendChild(profile_slug)
            skel_root = UsdSkel.Root.Define(stage, root_path)
            skel_root.GetPrim().SetCustomDataByKey("rigProfile", profile_id)
            skel_root.GetPrim().SetCustomDataByKey("cloneableRoot", profile["cloneableRoot"])
            joint_tokens = Vt.TokenArray(
                [str(joint) for joint in skeleton_data["joints"]]
            )
            skeleton = UsdSkel.Skeleton.Define(stage, root_path.AppendChild("Rig"))
            skeleton.CreateJointsAttr().Set(joint_tokens)
            skeleton.CreateRestTransformsAttr().Set(Vt.Matrix4dArray(skeleton_data["rest"]))
            skeleton.CreateBindTransformsAttr().Set(Vt.Matrix4dArray(skeleton_data["bind"]))

            # RealityKit does not surface animation resources from an otherwise
            # geometry-free SkelRoot. A one-millimetre project-authored witness
            # triangle makes the animation importable without carrying hero
            # meshes or becoming scene art. Integrators disable this child.
            witness = UsdGeom.Mesh.Define(stage, root_path.AppendChild("AnimationWitness"))
            witness.CreatePointsAttr().Set(
                Vt.Vec3fArray(
                    [Gf.Vec3f(0, 0, 0), Gf.Vec3f(0.001, 0, 0), Gf.Vec3f(0, 0.001, 0)]
                )
            )
            witness.CreateFaceVertexCountsAttr().Set(Vt.IntArray([3]))
            witness.CreateFaceVertexIndicesAttr().Set(Vt.IntArray([0, 1, 2]))
            witness.CreateExtentAttr().Set(
                Vt.Vec3fArray([Gf.Vec3f(0, 0, 0), Gf.Vec3f(0.001, 0.001, 0)])
            )
            witness.CreateSubdivisionSchemeAttr().Set(UsdGeom.Tokens.none)
            witness.CreateDoubleSidedAttr().Set(True)
            witness.GetPrim().SetCustomDataByKey("technicalAnimationWitness", True)
            witness_binding = UsdSkel.BindingAPI.Apply(witness.GetPrim())
            witness_binding.CreateSkeletonRel().SetTargets([skeleton.GetPath()])
            witness_binding.CreateGeomBindTransformAttr().Set(Gf.Matrix4d(1.0))
            witness_binding.CreateJointIndicesPrimvar(False, 1).Set(Vt.IntArray([1, 1, 1]))
            witness_binding.CreateJointWeightsPrimvar(False, 1).Set(
                Vt.FloatArray([1.0, 1.0, 1.0])
            )

            animation = UsdSkel.Animation.Define(
                stage, root_path.AppendChild(f"Clip_{clip_slug}_{profile_slug}")
            )
            animation.CreateJointsAttr().Set(joint_tokens)
            translations_attr = animation.CreateTranslationsAttr()
            rotations_attr = animation.CreateRotationsAttr()
            scales_attr = animation.CreateScalesAttr()
            for key in clip["keys"]:
                translations, rotations, scales = sample_key(key, skeleton_data)
                time = Usd.TimeCode(key["frame"])
                translations_attr.Set(translations, time)
                rotations_attr.Set(rotations, time)
                scales_attr.Set(scales, time)
            UsdSkel.BindingAPI.Apply(
                skeleton.GetPrim()
            ).CreateAnimationSourceRel().SetTargets([animation.GetPath()])

    stage.GetRootLayer().Save()


def approximate_joint_positions(joints: list) -> dict[str, Vector]:
    positions: dict[str, Vector] = {
        "Root": Vector((0, 0, 0)),
        "pelvis": Vector((0, 0, 0.98)),
        "spine_01": Vector((0, 0, 1.08)),
        "spine_02": Vector((0, 0, 1.20)),
        "spine_03": Vector((0, 0, 1.34)),
        "clavicle_l": Vector((0.10, 0, 1.38)),
        "upperarm_l": Vector((0.22, 0, 1.38)),
        "lowerarm_l": Vector((0.48, 0, 1.35)),
        "hand_l": Vector((0.72, 0, 1.32)),
        "clavicle_r": Vector((-0.10, 0, 1.38)),
        "upperarm_r": Vector((-0.22, 0, 1.38)),
        "lowerarm_r": Vector((-0.48, 0, 1.35)),
        "hand_r": Vector((-0.72, 0, 1.32)),
        "neck_01": Vector((0, 0, 1.47)),
        "head": Vector((0, 0, 1.62)),
        "thigh_l": Vector((0.11, 0, 0.90)),
        "calf_l": Vector((0.11, 0, 0.52)),
        "foot_l": Vector((0.11, -0.04, 0.12)),
        "ball_l": Vector((0.11, -0.18, 0.05)),
        "thigh_r": Vector((-0.11, 0, 0.90)),
        "calf_r": Vector((-0.11, 0, 0.52)),
        "foot_r": Vector((-0.11, -0.04, 0.12)),
        "ball_r": Vector((-0.11, -0.18, 0.05)),
    }
    for joint in joints:
        path = str(joint)
        name = joint_leaf(path)
        if name in positions:
            continue
        parent = joint_leaf(path.rsplit("/", 1)[0]) if "/" in path else "Root"
        parent_position = positions.get(parent, Vector((0, 0, 1.0)))
        side = 1 if name.endswith("_l") else -1 if name.endswith("_r") else 0
        if any(token in name for token in ("index", "middle", "ring", "pinky", "thumb")):
            segment = int(name.rsplit("_", 2)[-2]) if name.rsplit("_", 2)[-2].isdigit() else 1
            positions[name] = parent_position + Vector((0.025 * side, -0.01 * segment, 0))
        else:
            positions[name] = parent_position + Vector((0.03 * side, 0, 0.04))
    return positions


def build_blend(output: Path, spec: dict, skeleton_data: dict) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    armature_data = bpy.data.armatures.new("Chapter01DirectedAnimationRig")
    armature = bpy.data.objects.new("chapter01_directed_animation_rig", armature_data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    armature.show_in_front = True
    armature["libraryID"] = spec["libraryID"]
    armature["domainCompletion"] = "forbidden"
    armature["rootMotion"] = "disabled"

    bpy.ops.object.mode_set(mode="EDIT")
    positions = approximate_joint_positions(skeleton_data["joints"])
    edit_bones = {}
    for joint in skeleton_data["joints"]:
        path = str(joint)
        name = joint_leaf(path)
        bone = armature_data.edit_bones.new(name)
        head = positions[name]
        parent_name = joint_leaf(path.rsplit("/", 1)[0]) if "/" in path else None
        parent_position = positions.get(parent_name, head - Vector((0, 0, 0.06)))
        direction = head - parent_position
        if direction.length < 0.02:
            direction = Vector((0, 0, 0.06))
        direction.normalize()
        bone.head = head
        bone.tail = head + direction * 0.075
        if parent_name in edit_bones:
            bone.parent = edit_bones[parent_name]
        edit_bones[name] = bone
    bpy.ops.object.mode_set(mode="POSE")

    armature.animation_data_create()
    for clip in spec["clips"]:
        action = bpy.data.actions.new(clip["id"])
        action.use_fake_user = True
        action["clipID"] = clip["id"]
        action["loopMode"] = clip["loopMode"]
        action["safeIncompleteFrame"] = int(clip["safeIncompleteFrame"])
        armature.animation_data.action = action
        for pose_bone in armature.pose.bones:
            pose_bone.rotation_mode = "XYZ"
            pose_bone.rotation_euler = (0, 0, 0)
            pose_bone.location = (0, 0, 0)
        for key in clip["keys"]:
            frame = key["frame"]
            for name, degrees in key["joints"].items():
                pose_bone = armature.pose.bones[name]
                pose_bone.rotation_euler = tuple(math.radians(value) for value in degrees)
                pose_bone.keyframe_insert(data_path="rotation_euler", frame=frame)
            pelvis = armature.pose.bones["pelvis"]
            # Blender is Z-up; remap the authored USD Y-up offset for inspection.
            x, y, z = key.get("rootOffset", [0, 0, 0])
            pelvis.location = (x, -z, y)
            pelvis.keyframe_insert(data_path="location", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.scene.render.fps = spec["framesPerSecond"]
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = max(clip["durationFrames"] for clip in spec["clips"])
    bpy.context.scene["candidateClassification"] = spec["classification"]
    bpy.context.scene["sourceAuthority"] = "directed-animation-spec.json"
    bpy.ops.wm.save_as_mainfile(filepath=str(output), check_existing=False, compress=True)


def deterministic_usdz(source: Path, output: Path) -> None:
    data = source.read_bytes()
    name = source.name
    header_without_extra = 30 + len(name.encode("utf-8"))
    padding = (-header_without_extra) % 64
    if 0 < padding < 4:
        padding += 64
    if padding:
        extra = struct.pack("<HH", 0xFFFF, padding - 4) + bytes(padding - 4)
    else:
        extra = b""
    info = zipfile.ZipInfo(name, FIXED_ZIP_TIME)
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.extra = extra
    with zipfile.ZipFile(output, "w", allowZip64=True) as archive:
        archive.writestr(info, data)


def main() -> None:
    arguments = parse_args()
    library_dir = arguments.library_dir.resolve()
    output_dir = arguments.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    validate_blender()
    spec = load_json(library_dir / "directed-animation-spec.json")
    skeleton_profiles = read_hero_skeletons(library_dir, spec)
    preview_skeleton = skeleton_profiles["adult-a"]

    usd_path = output_dir / "chapter01-directed-animation-library.usdc"
    usdz_path = output_dir / "chapter01-directed-animation-library.usdz"
    blend_path = output_dir / "chapter01-directed-animation-library.blend"
    build_usd(usd_path, spec, skeleton_profiles)
    deterministic_usdz(usd_path, usdz_path)
    build_blend(blend_path, spec, preview_skeleton)

    print(
        json.dumps(
            {
                "status": "GENERATED",
                "clips": len(spec["clips"]),
                "joints": len(preview_skeleton["joints"]),
                "rigProfiles": len(skeleton_profiles),
                "output": str(output_dir),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
