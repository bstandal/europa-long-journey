#!/usr/bin/env python3
"""Focused tests for build-harvest-source-only-underlay.py."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image


SCRIPT = Path(__file__).with_name("build-harvest-source-only-underlay.py")
SPEC = importlib.util.spec_from_file_location("harvest_source_only_underlay", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {SCRIPT}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")


class Fixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.backstage = root / "native/content/backstage/harvest"
        self.input_directory = self.backstage / "test-input"
        self.receipt_directory = self.backstage / "receipts"
        self.input_directory.mkdir(parents=True)
        self.receipt_directory.mkdir(parents=True)
        self.recipe_path = self.backstage / "test-source-only-recipe.json"

        height, width = 40, 64
        yy, xx = np.mgrid[:height, :width]
        source = np.stack(
            [
                (17 + xx * 5 + yy * 3) % 223,
                (31 + xx * 2 + yy * 7) % 211,
                (47 + xx * 9 + yy * 2) % 199,
            ],
            axis=2,
        ).astype(np.uint8)
        self.source = source
        self.source_path = self.input_directory / "source.png"
        Image.fromarray(source, mode="RGB").save(self.source_path, format="PNG", optimize=False, compress_level=9)

        subject = np.zeros((height, width), dtype=bool)
        subject[10:34, 46:64] = True
        donor_a = np.zeros_like(subject)
        donor_a[3:37, 3:29] = True
        donor_b = np.zeros_like(subject)
        donor_b[4:36, 25:51] = True
        exclusion = np.zeros_like(subject)
        exclusion[13:28, 21:25] = True
        self.masks = {
            "spring-seed-store": subject,
            "left-donor": donor_a,
            "middle-donor": donor_b,
            "donor-exclusion": exclusion,
        }
        self.mask_paths: dict[str, Path] = {}
        for mask_id, mask in self.masks.items():
            path = self.input_directory / f"{mask_id}.png"
            Image.fromarray(mask.astype(np.uint8) * 255, mode="L").save(
                path, format="PNG", optimize=False, compress_level=9
            )
            self.mask_paths[mask_id] = path

        self.authority_path = self.input_directory / "rail-measurement.json"
        write_json(
            self.authority_path,
            {
                "status": "TEST_MEASUREMENT_AUTHORITY",
                "motion": {"minDx": 0, "maxDx": 4, "minDy": 0, "maxDy": 2},
            },
        )
        self.recipe = self._base_recipe()
        self.write_recipe()

    def relative(self, path: Path) -> str:
        return path.relative_to(self.root).as_posix()

    def _mask_spec(self, mask_id: str) -> dict[str, object]:
        mask = self.masks[mask_id]
        path = self.mask_paths[mask_id]
        return {
            "id": mask_id,
            "path": self.relative(path),
            "sha256": sha256_file(path),
            "pixelSize": [64, 40],
            "expectedPixelCount": int(mask.sum()),
            "expectedByteMaskSha256": sha256_bytes(mask.astype(np.uint8).tobytes(order="C")),
        }

    def _base_recipe(self) -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "id": "test-spring-seed-source-only-underlay",
            "status": "CODEX_NON_SHIPPING_SOURCE_ONLY_UNDERLAY_RECIPE",
            "shippingAllowed": False,
            "editorApprovalClaimed": False,
            "source": {
                "path": self.relative(self.source_path),
                "sha256": sha256_file(self.source_path),
                "pixelSize": [64, 40],
            },
            "bindings": [
                {
                    "id": "rail-measurement",
                    "path": self.relative(self.authority_path),
                    "sha256": sha256_file(self.authority_path),
                }
            ],
            "masks": [self._mask_spec(mask_id) for mask_id in self.masks],
            "crop": {"x": 2, "y": 1, "width": 62, "height": 38},
            "expressions": {
                "subject": {"mask": "spring-seed-store"},
                "authorization": {
                    "op": "directionalReveal",
                    "input": {"mask": "spring-seed-store"},
                    "motion": {
                        "minDx": 0,
                        "maxDx": 4,
                        "minDy": 0,
                        "maxDy": 2,
                        "authority": "rail-measurement",
                    },
                    "seamPixels": 1,
                },
                "donor": {
                    "op": "subtract",
                    "input": {
                        "op": "union",
                        "inputs": [{"mask": "left-donor"}, {"mask": "middle-donor"}],
                    },
                    "subtract": [{"mask": "donor-exclusion"}, {"mask": "spring-seed-store"}],
                },
            },
            "synthesis": {
                "method": "deterministic-source-only-patchmatch-v1",
                "patchRadius": 1,
                "guide": {"algorithm": "telea", "radius": 2.0, "blurSigma": 0.8},
                "initialCandidateCount": 5,
                "sweeps": 2,
                "randomCandidatesPerSweep": 2,
                "tileSize": 16,
            },
            "thresholds": {
                "minimumDonorPixels": 100,
                "minimumValidDonorCenters": 50,
                "minimumUniqueDonorCenters": 1,
                "maximumDonorCenterReuse": 1000,
                "maximumGeneratedSharePerTile": 1.0,
                "crossSeam": {"meanMaximum": 255.0, "p95Maximum": 255.0, "p99Maximum": 255.0},
                "interiorGradientRatio": {"minimum": 0.0, "maximum": 1000.0},
                "generatedLuma": {"p01Minimum": 0.0, "p99Maximum": 255.0},
                "maximumMeanColorDelta": 500.0,
                "changedTargetFraction": {"minimum": 0.0, "maximum": 1.0},
            },
            "output": {
                "directory": "native/.build/harvest-source-only-test/run",
                "receiptPath": "native/content/backstage/harvest/receipts/source-only-test.json",
                "files": {
                    "candidate": "candidate.png",
                    "authorization": "authorization.png",
                    "subject": "subject.png",
                    "donor": "donor.png",
                    "validDonorCenters": "valid-donor-centers.png",
                    "provenanceX": "provenance-x.png",
                    "provenanceY": "provenance-y.png",
                },
            },
        }

    def write_recipe(self) -> None:
        write_json(self.recipe_path, self.recipe)

    def inspect_and_lock(self) -> dict[str, object]:
        self.write_recipe()
        result = MODULE.run("inspect", self.recipe_path, self.root)
        self.recipe["expected"] = copy.deepcopy(result["lockingValues"])
        self.write_recipe()
        return result

    @property
    def output_directory(self) -> Path:
        return self.root / self.recipe["output"]["directory"]  # type: ignore[index]

    @property
    def receipt_path(self) -> Path:
        return self.root / self.recipe["output"]["receiptPath"]  # type: ignore[index]


class SourceOnlyUnderlayTests(unittest.TestCase):
    def make_fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Fixture]:
        temporary = tempfile.TemporaryDirectory()
        fixture = Fixture(Path(temporary.name))
        return temporary, fixture

    def test_directional_reveal_is_top_left_only_and_crop_is_non_square(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        inspection = fixture.inspect_and_lock()
        self.assertEqual(inspection["objectiveGate"], "PASS")
        self.assertFalse(fixture.output_directory.exists(), "inspect must be read-only")

        loaded = MODULE.load_recipe(fixture.recipe_path, fixture.root, require_expected=True)
        authorization = loaded.authorization
        self.assertEqual(authorization.shape, (38, 62))
        self.assertTrue(authorization[19, 44], "positive x motion reveals the left edge")
        self.assertTrue(authorization[9, 53], "positive y motion reveals the top edge")
        self.assertFalse(authorization[19, 61], "right edge is not revealed by positive x motion")
        self.assertFalse(authorization[32, 53], "bottom edge is not revealed by positive y motion")
        self.assertLess(int(authorization.sum()), int(loaded.subject.sum()))
        self.assertFalse(np.any(loaded.donor & authorization))

    def test_build_and_verify_are_byte_exact_and_source_only(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.inspect_and_lock()
        build = MODULE.run("build", fixture.recipe_path, fixture.root)
        self.assertEqual(build["objectiveGate"], "PASS")
        self.assertTrue(fixture.receipt_path.is_file())
        first_files = {
            path.name: path.read_bytes() for path in sorted(fixture.output_directory.iterdir()) if path.is_file()
        }
        verify = MODULE.run("verify", fixture.recipe_path, fixture.root)
        self.assertEqual(verify["objectiveGate"], "PASS")
        second_files = {
            path.name: path.read_bytes() for path in sorted(fixture.output_directory.iterdir()) if path.is_file()
        }
        self.assertEqual(first_files, second_files)

        loaded = MODULE.load_recipe(fixture.recipe_path, fixture.root, require_expected=True)
        with Image.open(fixture.output_directory / "candidate.png") as image:
            candidate = np.asarray(image.convert("RGB"), dtype=np.uint8)
        source_crop = fixture.source[1:39, 2:64]
        self.assertTrue(np.array_equal(candidate[~loaded.authorization], source_crop[~loaded.authorization]))
        with Image.open(fixture.output_directory / "provenance-x.png") as image:
            provenance_x = np.asarray(image, dtype=np.uint16).astype(np.int32) - 1
        with Image.open(fixture.output_directory / "provenance-y.png") as image:
            provenance_y = np.asarray(image, dtype=np.uint16).astype(np.int32) - 1
        target = loaded.authorization
        self.assertTrue(np.all(loaded.valid_donor_centers[provenance_y[target], provenance_x[target]]))
        self.assertTrue(np.array_equal(candidate[target], source_crop[provenance_y[target], provenance_x[target]]))

        tile_size = fixture.recipe["synthesis"]["tileSize"]  # type: ignore[index]
        tile_columns = int(np.ceil(candidate.shape[1] / tile_size))
        tile_ids = (provenance_y[target] // tile_size) * tile_columns + provenance_x[target] // tile_size
        _, tile_counts = np.unique(tile_ids, return_counts=True)
        expected_maximum_tile_share = round(float(tile_counts.max() / int(target.sum())), 6)
        self.assertEqual(build["metrics"]["maximumGeneratedSharePerTile"], expected_maximum_tile_share)

        receipt = json.loads(fixture.receipt_path.read_text(encoding="utf-8"))
        self.assertEqual(receipt["status"], "OBJECTIVE_TECHNICAL_QA_PASS")
        self.assertEqual(receipt["scope"], "NON_SHIPPING_BACKSTAGE_ONLY")
        self.assertFalse(receipt["authority"]["shippingAllowed"])
        self.assertEqual(receipt["determinism"]["inProcessReplayCount"], 2)

    def test_output_tamper_breaks_replay_verification(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.inspect_and_lock()
        MODULE.run("build", fixture.recipe_path, fixture.root)
        candidate = fixture.output_directory / "candidate.png"
        candidate.write_bytes(candidate.read_bytes() + b"tamper")
        with self.assertRaisesRegex(MODULE.RecipeError, "output bytes differ for candidate"):
            MODULE.run("verify", fixture.recipe_path, fixture.root)

    def test_receipt_tamper_breaks_replay_verification(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.inspect_and_lock()
        MODULE.run("build", fixture.recipe_path, fixture.root)
        fixture.receipt_path.write_bytes(fixture.receipt_path.read_bytes() + b" ")
        with self.assertRaisesRegex(MODULE.RecipeError, "receipt bytes do not match replay"):
            MODULE.run("verify", fixture.recipe_path, fixture.root)

    def test_expected_mismatch_fails_before_any_output(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.inspect_and_lock()
        fixture.recipe["expected"]["authorization"]["pixelCount"] += 1  # type: ignore[index]
        fixture.write_recipe()
        with self.assertRaisesRegex(MODULE.RecipeError, "expected forensic mismatch"):
            MODULE.run("build", fixture.recipe_path, fixture.root)
        self.assertFalse(fixture.output_directory.exists())
        self.assertFalse(fixture.receipt_path.exists())

    def test_threshold_failure_is_explicit_and_creates_nothing(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        inspection = fixture.inspect_and_lock()
        target_count = inspection["metrics"]["authorizationPixelCount"]  # type: ignore[index]
        fixture.recipe["thresholds"]["minimumUniqueDonorCenters"] = target_count + 1  # type: ignore[index]
        fixture.recipe.pop("expected")
        inspection = fixture.inspect_and_lock()
        self.assertEqual(inspection["objectiveGate"], "FAIL")
        self.assertIn("UNIQUE_DONOR_CENTERS_BELOW_MINIMUM", inspection["failedGates"])
        with self.assertRaisesRegex(MODULE.RecipeError, "objective QA failed"):
            MODULE.run("build", fixture.recipe_path, fixture.root)
        self.assertFalse(fixture.output_directory.exists())
        self.assertFalse(fixture.receipt_path.exists())

    def test_source_digest_tamper_fails_before_synthesis(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.inspect_and_lock()
        with Image.open(fixture.source_path) as image:
            changed = np.asarray(image.convert("RGB"), dtype=np.uint8).copy()
        changed[0, 0] ^= 255
        Image.fromarray(changed, mode="RGB").save(fixture.source_path, format="PNG")
        with self.assertRaisesRegex(MODULE.RecipeError, "source digest mismatch"):
            MODULE.run("build", fixture.recipe_path, fixture.root)
        self.assertFalse(fixture.output_directory.exists())

    def test_shipping_claim_and_output_escape_are_rejected(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.recipe["shippingAllowed"] = True
        fixture.write_recipe()
        with self.assertRaisesRegex(MODULE.RecipeError, "shippingAllowed must be false"):
            MODULE.run("inspect", fixture.recipe_path, fixture.root)

        fixture.recipe["shippingAllowed"] = False
        fixture.recipe["output"]["directory"] = "native/content/backstage/harvest/generated"  # type: ignore[index]
        fixture.write_recipe()
        with self.assertRaisesRegex(MODULE.RecipeError, "output.directory must be below"):
            MODULE.run("inspect", fixture.recipe_path, fixture.root)

    def test_directional_reveal_requires_hashed_measurement_binding(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.recipe["expressions"]["authorization"]["motion"]["authority"] = "missing"  # type: ignore[index]
        fixture.write_recipe()
        with self.assertRaisesRegex(MODULE.RecipeError, "unknown binding"):
            MODULE.run("inspect", fixture.recipe_path, fixture.root)

    def test_build_refuses_overwrite(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.inspect_and_lock()
        MODULE.run("build", fixture.recipe_path, fixture.root)
        with self.assertRaisesRegex(MODULE.RecipeError, "refuses existing output directory"):
            MODULE.run("build", fixture.recipe_path, fixture.root)


if __name__ == "__main__":
    unittest.main(verbosity=2)
