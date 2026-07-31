from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).absolute().parents[4]
SCRIPT_PATH = (
    REPOSITORY_ROOT
    / "native/audio/score-soundscape/chapter_01_review_transitions.py"
)
SPEC = importlib.util.spec_from_file_location(
    "chapter_01_review_transitions", SCRIPT_PATH
)
assert SPEC is not None and SPEC.loader is not None
transitions = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(transitions)


class FirstFarmersReviewTransitionTests(unittest.TestCase):
    def test_exact_review_transition_inventory(self) -> None:
        self.assertEqual(
            [item["transitionID"] for item in transitions.TRANSITIONS],
            [
                "transition-aegean-thessaly-v1",
                "transition-store-iron-gates-v1",
                "transition-farming-belt-steppe-v1",
            ],
        )
        self.assertEqual(transitions.SAMPLE_RATE, 48_000)
        self.assertEqual(transitions.CHANNEL_COUNT, 2)
        self.assertEqual(transitions.NOMINAL_OUTPUT_FRAMES, 288_000)

    def test_transitions_reuse_responsive_world_previews(self) -> None:
        self.assertEqual(
            [
                (item["sourceA"], item["sourceB"])
                for item in transitions.TRANSITIONS
            ],
            [
                (
                    ("household-crosses", "consequence/program-preview.wav"),
                    ("harvest", "approach/program-preview.wav"),
                ),
                (
                    ("harvest", "consequence/program-preview.wav"),
                    ("three-records", "approach/program-preview.wav"),
                ),
                (
                    ("continent-remade", "approach/program-preview.wav"),
                    ("continent-remade", "consequence/program-preview.wav"),
                ),
            ],
        )

    def test_generated_manifest_and_assets_validate(self) -> None:
        result = transitions.validate()
        self.assertEqual(result["status"], "NON_SHIPPING_REVIEW")
        self.assertEqual(result["transitionCount"], 3)
        self.assertEqual(len(result["durationFrames"]), 3)


if __name__ == "__main__":
    unittest.main()
