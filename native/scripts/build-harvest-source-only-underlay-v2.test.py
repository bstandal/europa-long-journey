#!/usr/bin/env python3
"""Focused tests for the explicit v2 in-place Harvest underlay track."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


DIRECTORY = Path(__file__).parent


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


V2 = load_module("harvest_source_only_underlay_v2_test_target", DIRECTORY / "build-harvest-source-only-underlay-v2.py")
V1_TEST = load_module("harvest_source_only_underlay_v1_test_fixture", DIRECTORY / "build-harvest-source-only-underlay.test.py")


class V2Fixture:
    def __init__(self, root: Path) -> None:
        self.base = V1_TEST.Fixture(root)
        self.root = root
        self.recipe_path = self.base.recipe_path
        self.recipe = self.base.recipe

    def convert(self, coherence: dict[str, float] | None = None) -> None:
        self.recipe["id"] = "test-source-only-underlay-v2"
        self.recipe["synthesis"]["method"] = V2.V2_METHOD
        self.recipe["synthesis"]["propagationCostToleranceFraction"] = 0.25
        self.recipe["thresholds"]["provenanceCoherence"] = coherence or {
            "minimumExactTranslationAdjacencyFraction": 0.4,
            "maximumDisplacementJumpP95": 64.0,
            "maximumDisplacementJumpP99": 64.0,
        }
        self.recipe["output"]["directory"] = "native/.build/harvest-source-only-v2-test/run"
        self.recipe["output"]["receiptPath"] = (
            "native/content/backstage/harvest/receipts/source-only-v2-test.json"
        )
        self.recipe.pop("expected", None)
        self.write()

    def write(self) -> None:
        V1_TEST.write_json(self.recipe_path, self.recipe)

    def inspect_and_lock(self):
        result = V2.run("inspect", self.recipe_path, self.root)
        self.recipe["expected"] = copy.deepcopy(result["lockingValues"])
        self.write()
        return result

    @property
    def output_directory(self) -> Path:
        return self.root / self.recipe["output"]["directory"]

    @property
    def receipt_path(self) -> Path:
        return self.root / self.recipe["output"]["receiptPath"]


class SourceOnlyUnderlayV2Tests(unittest.TestCase):
    def make_fixture(self) -> tuple[tempfile.TemporaryDirectory[str], V2Fixture]:
        temporary = tempfile.TemporaryDirectory()
        fixture = V2Fixture(Path(temporary.name))
        return temporary, fixture

    def test_v1_builder_is_byte_frozen(self) -> None:
        digest = hashlib.sha256(V2.V1_BUILDER.read_bytes()).hexdigest()
        self.assertEqual(digest, V2.V1_BUILDER_SHA256)

    def test_v2_rejects_v1_method(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        with self.assertRaisesRegex(V2.V1.RecipeError, "expected 'deterministic-source-only-patchmatch-v2-inplace'"):
            V2.run("inspect", fixture.recipe_path, fixture.root)

    def test_v2_in_place_propagation_improves_exact_neighbor_coherence(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        v1 = V2.V1.analyze(fixture.recipe_path, fixture.root, require_expected=False)
        v1_metrics = V2._coherence_metrics(v1.loaded.authorization, v1.provenance_y, v1.provenance_x)
        fixture.convert()
        v2 = fixture.inspect_and_lock()
        v2_metrics = v2["metrics"]["provenanceCoherence"]
        self.assertGreater(
            v2_metrics["exactTranslationAdjacencyFraction"],
            v1_metrics["exactTranslationAdjacencyFraction"],
        )
        self.assertGreater(v2_metrics["internalAdjacencyPairCount"], 0)
        self.assertLessEqual(v2_metrics["displacementJump"]["p95"], 64.0)

    def test_v2_build_and_verify_are_byte_exact(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.convert()
        fixture.inspect_and_lock()
        built = V2.run("build", fixture.recipe_path, fixture.root)
        self.assertEqual(built["objectiveGate"], "PASS")
        before = {path.name: path.read_bytes() for path in fixture.output_directory.iterdir()}
        verified = V2.run("verify", fixture.recipe_path, fixture.root)
        after = {path.name: path.read_bytes() for path in fixture.output_directory.iterdir()}
        self.assertEqual(verified["objectiveGate"], "PASS")
        self.assertEqual(before, after)
        receipt = fixture.receipt_path.read_text(encoding="utf-8")
        self.assertIn(V2.V2_METHOD, receipt)
        self.assertIn(V2.V1_BUILDER_SHA256, receipt)

    def test_coherence_gate_fails_closed_without_output(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.convert(
            {
                "minimumExactTranslationAdjacencyFraction": 1.0,
                "maximumDisplacementJumpP95": 0.0,
                "maximumDisplacementJumpP99": 0.0,
            }
        )
        inspected = fixture.inspect_and_lock()
        self.assertEqual(inspected["objectiveGate"], "FAIL")
        self.assertIn("EXACT_TRANSLATION_ADJACENCY_FRACTION_BELOW_MINIMUM", inspected["failedGates"])
        self.assertIn("DISPLACEMENT_JUMP_P95_ABOVE_MAXIMUM", inspected["failedGates"])
        with self.assertRaisesRegex(V2.V1.RecipeError, "objective QA failed"):
            V2.run("build", fixture.recipe_path, fixture.root)
        self.assertFalse(fixture.output_directory.exists())
        self.assertFalse(fixture.receipt_path.exists())

    def test_missing_coherence_thresholds_are_rejected(self) -> None:
        temporary, fixture = self.make_fixture()
        self.addCleanup(temporary.cleanup)
        fixture.convert()
        del fixture.recipe["thresholds"]["provenanceCoherence"]
        fixture.write()
        with self.assertRaisesRegex(V2.V1.RecipeError, "missing=.*provenanceCoherence"):
            V2.run("inspect", fixture.recipe_path, fixture.root)


if __name__ == "__main__":
    unittest.main(verbosity=2)
