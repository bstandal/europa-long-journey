from __future__ import annotations

import ast
import json
from pathlib import Path
import sys
import unittest


NARRATION_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NARRATION_ROOT))

import first_farmers_review_narration as review
import first_farmers_voxcpm2_review as vox


class FirstFarmersReviewNarrationTests(unittest.TestCase):
    def test_editor_authority_is_review_only_and_keeps_v12_production_closed(self) -> None:
        authorization = review.validate_authorization()
        self.assertEqual(authorization["configuration"], "NON_SHIPPING_REVIEW")
        self.assertEqual(authorization["shippingState"], "PROHIBITED")
        self.assertTrue(authorization["scope"]["voxcpm2V12"]["permitted"])
        self.assertFalse(
            authorization["scope"]["voxcpm2V12"][
                "productionVoicePromotionPermitted"
            ]
        )
        self.assertFalse(
            authorization["v12PresynthesisAuthority"]["modifiedByThisDecision"]
        )
        closed_path = (
            review.REPOSITORY_ROOT
            / authorization["v12PresynthesisAuthority"]["path"]
        )
        closed = json.loads(closed_path.read_text(encoding="utf-8"))
        self.assertFalse(closed["synthesisPermitted"])
        self.assertTrue(closed["requiresEditorDecision"])

    def test_exact_chapter_structure_projects_to_37_unique_cues(self) -> None:
        _, segments = review.manuscript_segments()
        self.assertEqual(len(segments), 37)
        self.assertEqual(len({item["cueID"] for item in segments}), 37)
        self.assertTrue(
            all(item["cueID"] == f"narration-{item['manuscriptSegmentID']}" for item in segments)
        )
        self.assertTrue(
            all(len(item["manuscriptSegmentSHA256"]) == 64 for item in segments)
        )

    def test_review_output_is_confined_outside_public_content(self) -> None:
        self.assertTrue(
            review.REVIEW_ROOT.absolute().is_relative_to(
                review.NARRATION_ROOT.absolute()
            )
        )
        self.assertFalse(
            review.REVIEW_ROOT.absolute().is_relative_to(
                (review.REPOSITORY_ROOT / "content/public").absolute()
            )
        )
        self.assertEqual(
            review.MANIFEST_PATH.relative_to(review.REPOSITORY_ROOT).as_posix(),
            "native/audio/narration/review/chapter-01/manifest.json",
        )

    def test_voxcpm2_probe_is_two_voices_one_take_and_no_retry(self) -> None:
        tree = ast.parse(vox.SCRIPT_PATH.read_text(encoding="utf-8"))
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
        generate_calls = [
            node
            for node in calls
            if isinstance(node.func, ast.Attribute) and node.func.attr == "generate"
        ]
        self.assertEqual(len(generate_calls), 1)
        source = vox.SCRIPT_PATH.read_text(encoding="utf-8")
        self.assertIn('"retry_badcase": False', source)
        self.assertIn('"oneTakePerSegment": True', source)
        self.assertEqual(vox.PROBE_SEGMENT_COUNT, 4)

    def test_qwen_fallback_is_one_candidate_for_the_whole_chapter(self) -> None:
        authorization = review.validate_authorization()
        fallback = authorization["scope"]["fallback"]
        self.assertEqual(fallback["engine"], "Qwen3-TTS Base")
        self.assertEqual(fallback["candidateID"], "voice-candidate-05")
        self.assertTrue(fallback["wholeChapterOnly"])
        source = review.SCRIPT_PATH.read_text(encoding="utf-8")
        self.assertIn('selection.get("voxcpm2TechnicalPassCount") != 0', source)

    def test_generated_review_manifest_binds_all_37_actual_cues(self) -> None:
        result = review.validate_manifest()
        self.assertEqual(result["status"], "NON_SHIPPING_REVIEW")
        self.assertEqual(result["shippingState"], "PROHIBITED")
        self.assertEqual(result["engine"], "Qwen3-TTS Base")
        self.assertEqual(result["candidateID"], "voice-candidate-05")
        self.assertEqual(result["cueCount"], 37)
        self.assertEqual(result["sampleRate"], 48_000)
        self.assertGreater(result["totalDurationSamples"], 0)

    def test_runtime_duration_excludes_aac_decoder_remainder(self) -> None:
        cue_path = (
            review.CUES_ROOT / "narration-ff-river-world-01.m4a"
        )
        decoded = review.audio_record(cue_path)
        runtime = review.runtime_audio_record(cue_path)
        self.assertLess(runtime["durationSamples"], decoded["durationSamples"])
        self.assertLess(
            decoded["durationSamples"] - runtime["durationSamples"],
            1_024,
        )


if __name__ == "__main__":
    unittest.main()
