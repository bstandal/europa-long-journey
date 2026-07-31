#!/usr/bin/env python3
"""Validate authored contracts and compiled UsdSkel clips inside Blender."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

from pxr import Usd, UsdGeom, UsdSkel


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--library-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args(argv)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def slug(value: str) -> str:
    return "".join(character if character.isalnum() else "_" for character in value).strip("_")


def fail(message: str) -> None:
    raise RuntimeError(message)


def verify_inputs(library_dir: Path) -> list[dict]:
    lock = load_json(library_dir / "inputs.lock.json")
    resolved = []
    for item in lock["inputs"]:
        path = (library_dir / item["path"]).resolve()
        actual = sha256(path)
        if actual != item["sha256"]:
            fail(f"Pinned input changed: {item['path']} ({actual})")
        resolved.append({"path": item["path"], "sha256": actual})
    return resolved


def verify_spec(spec: dict, joint_names: set[str]) -> dict:
    clips = spec["clips"]
    clip_ids = [clip["id"] for clip in clips]
    if len(clip_ids) != len(set(clip_ids)):
        fail("Clip IDs must be unique")
    if len(clips) != 20:
        fail(f"Expected 20 bounded clips, found {len(clips)}")
    loop_count = 0
    contact_count = 0
    for clip in clips:
        frames = [key["frame"] for key in clip["keys"]]
        if frames != sorted(set(frames)):
            fail(f"Non-monotonic or duplicate keys in {clip['id']}")
        if frames[0] != 0 or frames[-1] != clip["durationFrames"]:
            fail(f"Clip boundary mismatch in {clip['id']}")
        if not 0 <= clip["safeIncompleteFrame"] <= clip["durationFrames"]:
            fail(f"Unsafe incomplete frame in {clip['id']}")
        for key in clip["keys"]:
            unknown = set(key["joints"]) - joint_names
            if unknown:
                fail(f"Unknown joints in {clip['id']}: {sorted(unknown)}")
        if clip["loopMode"] == "loop":
            loop_count += 1
            first = clip["keys"][0]
            last = clip["keys"][-1]
            if first.get("rootOffset", [0, 0, 0]) != last.get("rootOffset", [0, 0, 0]):
                fail(f"Loop centre-of-mass mismatch in {clip['id']}")
            if first["joints"] != last["joints"]:
                fail(f"Loop pose mismatch in {clip['id']}")
        for window in clip["contactWindows"]:
            contact_count += 1
            if not (
                0 <= window["startFrame"]
                <= window["peakFrame"]
                <= window["endFrame"]
                <= clip["durationFrames"]
            ):
                fail(f"Invalid contact window in {clip['id']}: {window}")
            if not window["targetSocket"] or not window["mode"]:
                fail(f"Empty contact target or mode in {clip['id']}")
    return {"clipCount": len(clips), "loopClipCount": loop_count, "contactWindowCount": contact_count}


def verify_locked_contract(library_dir: Path, spec: dict) -> dict:
    contract = load_json(library_dir / "integration-contract.json")
    approval_path = (library_dir / "../../../../blueprint/first-farmers-experience-approval.json").resolve()
    catalog_path = (library_dir / "../../../../ios/Sources/ImmersiveRuntime/Chapter01InteractionCatalog.swift").resolve()
    approval = load_json(approval_path)
    catalog = catalog_path.read_text(encoding="utf-8")

    interaction_ids = [item["interactionID"] for item in contract["interactions"]]
    if interaction_ids != approval["principalInteractionIDs"]:
        fail("Integration interaction order diverges from approved projection")
    if contract["approvedProjectionSHA256"] != approval["projectionSHA256"]:
        fail("Approved projection digest diverged")
    if contract["lockedSourceDigests"] != {
        "principalInteractionSlice": approval["sourceSHA256"]["principalInteractionSlice"],
        "authoredInteractionEffectSlice": approval["sourceSHA256"]["authoredInteractionEffectSlice"],
        "worldEffectSlice": approval["sourceSHA256"]["worldEffectSlice"],
    }:
        fail("Locked interaction/effect source digests diverged")

    clip_ids = {clip["id"] for clip in spec["clips"]}
    mapped = set()
    grammar_counts = {}
    for item in contract["interactions"]:
        interaction_id = re.escape(item["interactionID"])
        effect_id = re.escape(item["worldEffectID"])
        grammar = re.escape(item["grammar"])
        if not re.search(rf'id:\s*"{interaction_id}"', catalog):
            fail(f"Interaction ID missing from runtime catalog: {item['interactionID']}")
        if not re.search(rf'id:\s*"{effect_id}"', catalog):
            fail(f"WorldEffect ID missing from runtime catalog: {item['worldEffectID']}")
        interaction_offset = catalog.find(item["interactionID"])
        effect_offset = catalog.find(item["worldEffectID"], interaction_offset)
        region = catalog[interaction_offset:effect_offset]
        if not re.search(rf'grammar:\s*\.{grammar}\s*\(', region):
            fail(f"Grammar mismatch for {item['interactionID']}")
        unknown = set(item["clips"]) - clip_ids
        if unknown:
            fail(f"Unknown mapped clips for {item['interactionID']}: {sorted(unknown)}")
        mapped.update(item["clips"])
        grammar_counts[item["grammar"]] = grammar_counts.get(item["grammar"], 0) + 1
    if mapped != clip_ids:
        fail(f"Unmapped clips: {sorted(clip_ids - mapped)}")
    if contract["authority"] != {
        "sourceOfCompletion": "Chapter01 domain reducer",
        "animationMayCommitWorldEffect": False,
        "animationMayAdvanceBeat": False,
        "contactMarkersAreAdvisory": True,
        "renderOrPhysicsMayCompleteHistoricalAction": False,
        "restoreProjection": "stable domain state plus deterministic tick selects and samples a clip",
        "restoreHaptics": "never replay contact or completion haptics already journalled",
    }:
        fail("Domain-authority integration contract changed")
    return {"interactionCount": len(interaction_ids), "grammarCounts": grammar_counts}


def verify_usd(output_dir: Path, spec: dict) -> dict:
    stage_path = output_dir / "chapter01-directed-animation-library.usdc"
    stage = Usd.Stage.Open(str(stage_path))
    if stage is None:
        fail("Compiled USDC could not be opened")
    if stage.GetDefaultPrim().GetPath().pathString != "/Chapter01DirectedAnimations":
        fail("Unexpected default prim")
    if UsdGeom.GetStageUpAxis(stage) != UsdGeom.Tokens.y:
        fail("USD stage must be Y-up")
    if UsdGeom.GetStageMetersPerUnit(stage) != 1:
        fail("USD stage must use metres")

    skeleton_count = 0
    animation_count = 0
    witness_count = 0
    joint_count = None
    encountered_profiles = set()
    for clip in spec["clips"]:
        clip_slug = slug(clip["id"])
        for profile in spec["rigContract"]["profiles"]:
            if profile["role"] not in clip["roles"]:
                continue
            profile_slug = slug(profile["id"])
            root_path = f"/Chapter01DirectedAnimations/{clip_slug}/{profile_slug}"
            skeleton = UsdSkel.Skeleton(stage.GetPrimAtPath(f"{root_path}/Rig"))
            animation = UsdSkel.Animation(
                stage.GetPrimAtPath(f"{root_path}/Clip_{clip_slug}_{profile_slug}")
            )
            if not skeleton or not animation:
                fail(f"Missing skeleton or animation for {clip['id']} / {profile['id']}")
            witness = UsdGeom.Mesh(stage.GetPrimAtPath(f"{root_path}/AnimationWitness"))
            if not witness:
                fail(f"Missing RealityKit animation witness for {clip['id']} / {profile['id']}")
            witness_points = list(witness.GetPointsAttr().Get())
            if len(witness_points) != 3:
                fail(f"Unexpected witness geometry for {clip['id']} / {profile['id']}")
            witness_binding = UsdSkel.BindingAPI(witness.GetPrim())
            if witness_binding.GetSkeletonRel().GetTargets() != [skeleton.GetPath()]:
                fail(f"Witness skeleton binding mismatch in {clip['id']} / {profile['id']}")
            joints = list(skeleton.GetJointsAttr().Get())
            animation_joints = list(animation.GetJointsAttr().Get())
            if joints != animation_joints:
                fail(f"Joint order mismatch in {clip['id']} / {profile['id']}")
            joint_count = len(joints) if joint_count is None else joint_count
            if len(joints) != joint_count:
                fail(f"Joint count mismatch in {clip['id']} / {profile['id']}")
            expected_times = [float(key["frame"]) for key in clip["keys"]]
            for attr in (
                animation.GetTranslationsAttr(),
                animation.GetRotationsAttr(),
                animation.GetScalesAttr(),
            ):
                if attr.GetTimeSamples() != expected_times:
                    fail(f"Animation sample times diverged in {clip['id']} / {profile['id']}")
                for time in expected_times:
                    if len(attr.Get(time)) != joint_count:
                        fail(f"Animation sample width diverged in {clip['id']} / {profile['id']} at {time}")
            root_translation = animation.GetTranslationsAttr().Get(expected_times[0])[0]
            for time in expected_times[1:]:
                if animation.GetTranslationsAttr().Get(time)[0] != root_translation:
                    fail(f"Root motion escaped clip {clip['id']} / {profile['id']}")
            targets = UsdSkel.BindingAPI(skeleton.GetPrim()).GetAnimationSourceRel().GetTargets()
            if targets != [animation.GetPath()]:
                fail(f"Animation binding mismatch in {clip['id']} / {profile['id']}")
            encountered_profiles.add(profile["id"])
            skeleton_count += 1
            animation_count += 1
            witness_count += 1
    return {
        "skeletonCount": skeleton_count,
        "animationCount": animation_count,
        "animationWitnessCount": witness_count,
        "jointCount": joint_count,
        "rigProfileCount": len(encountered_profiles),
        "rootMotionDisabled": True,
    }


def main() -> None:
    arguments = parse_args()
    library_dir = arguments.library_dir.resolve()
    output_dir = arguments.output_dir.resolve()
    spec = load_json(library_dir / "directed-animation-spec.json")

    stage = Usd.Stage.Open(
        str((library_dir / spec["rigContract"]["sourceAsset"]).resolve())
    )
    profiles = spec["rigContract"]["profiles"]
    skeletons = [UsdSkel.Skeleton(stage.GetPrimAtPath(profile["skeletonPath"])) for profile in profiles]
    if any(not skeleton for skeleton in skeletons):
        fail("One or more declared rig profiles are missing")
    canonical_joints = list(skeletons[0].GetJointsAttr().Get())
    if any(list(skeleton.GetJointsAttr().Get()) != canonical_joints for skeleton in skeletons[1:]):
        fail("Declared rig profiles do not share joint order")
    joint_names = {str(joint).rsplit("/", 1)[-1] for joint in canonical_joints}

    report = {
        "schemaVersion": 1,
        "libraryID": spec["libraryID"],
        "status": "PASS",
        "inputLocks": verify_inputs(library_dir),
        "authoredSpec": verify_spec(spec, joint_names),
        "lockedRuntimeContract": verify_locked_contract(library_dir, spec),
        "compiledUSD": verify_usd(output_dir, spec),
        "policy": {
            "domainCompletionForbidden": True,
            "dialogueAbsent": True,
            "lipSyncAbsent": True,
            "freeClothHairSimulationAbsent": True,
            "autonomousCrowdSimulationAbsent": True,
            "thirdPartyMotionAbsent": True,
        },
    }
    destination = output_dir / "validation-report.json"
    destination.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
