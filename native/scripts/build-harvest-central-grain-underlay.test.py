#!/usr/bin/env python3
"""Regression tests for the fail-closed Harvest central-grain author."""

from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "native/scripts/build-harvest-central-grain-underlay.py"
SPEC_PATH = ROOT / "native/content/backstage/harvest/central-grain-underlay-v26.spec.json"


def load_author():
    specification = importlib.util.spec_from_file_location("harvest_central_grain_author", SCRIPT)
    if specification is None or specification.loader is None:
        raise RuntimeError("Cannot import central-grain author")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


author = load_author()


class CentralGrainUnderlayTests(unittest.TestCase):
    def test_disk_kernel_is_exact_integer_euclidean_footprint(self) -> None:
        offsets = author.disk_offsets(4)
        self.assertEqual(len(offsets), 49)
        self.assertIn((-4, 0), offsets)
        self.assertIn((0, 4), offsets)
        self.assertNotIn((4, 1), offsets)
        self.assertTrue(all(dx * dx + dy * dy <= 16 for dy, dx in offsets))

    def test_erosion_zero_pads_outside_crop(self) -> None:
        mask = np.ones((9, 9), dtype=bool)
        eroded = author.binary_erode(mask, 4)
        self.assertEqual(int(np.count_nonzero(eroded)), 1)
        self.assertTrue(eroded[4, 4])

    def test_hash_gated_authority_masks_match_forensic_spec(self) -> None:
        _, masks, _ = author.load_inputs(ROOT)
        subject, target, donor, valid, measurements = author.construct_authority_masks(masks)
        self.assertEqual(measurements, author.EXPECTED)
        self.assertEqual(int(np.count_nonzero(subject)), 190_259)
        self.assertEqual(int(np.count_nonzero(target)), 196_727)
        self.assertEqual(int(np.count_nonzero(donor)), 148_493)
        self.assertEqual(int(np.count_nonzero(valid)), 132_392)
        seam = target & ~author.binary_erode(target, author.SEAM_RING_WIDTH)
        core = author.binary_erode(target, author.SEAM_RING_WIDTH)
        legacy_fringe = target & ~subject
        self.assertEqual(int(np.count_nonzero(seam)), 19_805)
        self.assertEqual(
            author.sha256_bytes(seam.astype(np.uint8).tobytes()),
            "36d104f25471704bb9932806ad881dae793e31b0e24676c5b112c7d68e8f7121",
        )
        self.assertEqual(int(np.count_nonzero(core)), 176_922)
        self.assertEqual(
            author.sha256_bytes(core.astype(np.uint8).tobytes()),
            "f8c8374a37e2fe39c10d8ca77cae2c7f059dea119d6774f2e902b6a316e05544",
        )
        self.assertEqual(int(np.count_nonzero(~target)), 606_089)
        self.assertEqual(int(np.count_nonzero(legacy_fringe)), 6_468)

    def test_spec_and_script_remain_fail_closed(self) -> None:
        self.assertEqual(author.sha256_file(SPEC_PATH), author.SPEC["sha256"])
        specification = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        self.assertIs(specification["shippingAllowed"], False)
        self.assertIs(specification["editorApprovalClaimed"], False)
        self.assertEqual(specification["synthesis"]["writeMask"], "AUTHORIZATION_T")
        self.assertEqual(
            specification["synthesis"]["outsideAuthorizationRule"],
            "EXACT_SOURCE_PIXELS",
        )
        self.assertIs(
            specification["synthesis"]["rawSourcePixelsInsideAuthorizationProtected"],
            False,
        )
        self.assertNotIn("outerAuthorizationShellRule", specification["synthesis"])
        script_text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('"shippingAllowed": False', script_text)
        self.assertIn('"productionAssetAuthority": False', script_text)
        self.assertIn('"requiredMethodImplemented": True', script_text)
        self.assertIn('"productionAssetAuthority": False', script_text)
        self.assertNotIn("candidate[authorization_shell]", script_text)

    def test_png_and_json_encodings_are_deterministic(self) -> None:
        sample = np.arange(27, dtype=np.uint8).reshape((3, 3, 3))
        self.assertEqual(author.png_bytes(sample), author.png_bytes(sample.copy()))
        first = author.canonical_json_bytes({"z": 1, "a": [3, 2, 1]})
        second = author.canonical_json_bytes({"a": [3, 2, 1], "z": 1})
        self.assertEqual(first, second)

    def test_scene_diagnostics_use_hash_bound_camera_crops(self) -> None:
        fixture_path = ROOT / author.SCENE_FIXTURE["path"]
        self.assertEqual(
            author.sha256_file(fixture_path),
            author.SCENE_FIXTURE["sha256"],
        )
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        source, _, _ = author.load_inputs(ROOT)
        keyframes = fixture["scene"]["cameraRail"]["keyframes"]
        for crop in fixture["scene"]["sceneCanvas"]["viewportCrops"]:
            for keyframe in (keyframes[0], keyframes[-1]):
                rendered = author.render_camera_crop(source, crop, keyframe)
                self.assertEqual(
                    rendered.shape,
                    (
                        crop["viewport"]["heightPoints"],
                        crop["viewport"]["widthPoints"],
                        3,
                    ),
                )


if __name__ == "__main__":
    unittest.main()
