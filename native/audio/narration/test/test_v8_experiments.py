from __future__ import annotations

import copy
import unittest

import v8_chatterbox_comparison as chatterbox
import v8_decoder_grid_experiment as decoder_grid
import v8_pipeline as v8


class V8DecoderGridExperimentTests(unittest.TestCase):
    def test_grid_experiment_changes_geometry_only(self) -> None:
        frozen = v8._v8_audit_config(v8.load_config())
        changed = decoder_grid._experiment_config(v8.load_config())
        self.assertEqual(
            {
                "windowSeconds": changed["windowedASR"]["windowSeconds"],
                "overlapSeconds": changed["windowedASR"]["overlapSeconds"],
                "strideSeconds": changed["windowedASR"]["strideSeconds"],
            },
            {"windowSeconds": 25, "overlapSeconds": 15, "strideSeconds": 10},
        )
        for key in ("windowSeconds", "overlapSeconds", "strideSeconds", "grid"):
            frozen["windowedASR"].pop(key)
            changed["windowedASR"].pop(key)
        self.assertEqual(changed, frozen)


class V8ChatterboxComparisonTests(unittest.TestCase):
    def test_comparison_uses_exact_frozen_representatives(self) -> None:
        config = v8.load_config()
        selected, record = chatterbox._selected_material(config)
        self.assertEqual(
            [item["utteranceID"] for item in selected],
            config["pauseDensityLab"]["representativeUtteranceIDs"],
        )
        self.assertEqual(len(selected), 14)
        self.assertTrue(record["allSixCuesCovered"])
        self.assertEqual(
            record["exactTextManifestSHA256"],
            "822786bfaa942aec932686929d2ece3a7122d5215db654862cad3e28d9a8cb62",
        )

    def test_comparison_generation_is_bounded_and_single_attempt(self) -> None:
        settings = chatterbox.GENERATION_SETTINGS
        self.assertEqual(settings["maximumSpeechTokens"], 384)
        self.assertTrue(settings["oneDeterministicAttemptPerUtterance"])
        self.assertIsNone(settings["splitPattern"])
        self.assertFalse(settings["stream"])

    def test_pinned_s3_token_derivation_is_exact(self) -> None:
        record = chatterbox._derive_speech_tokens(280 * 960 - 60)
        self.assertTrue(record["integerDerivation"])
        self.assertEqual(record["derivedSpeechTokenCount"], 280)
        self.assertLess(
            record["derivedSpeechTokenCount"],
            chatterbox.GENERATION_SETTINGS["maximumSpeechTokens"],
        )

    def test_critical_pronunciation_gate_requires_every_occurrence(self) -> None:
        reference = list(chatterbox.CRITICAL_PRONUNCIATION_WORDS) + ["vienna"]
        passed = chatterbox._critical_word_gate(reference, copy.copy(reference))
        failed = chatterbox._critical_word_gate(
            reference, [item for item in reference if item != "vienna"]
        )
        self.assertTrue(passed["allPresentExactly"])
        self.assertFalse(failed["allPresentExactly"])


if __name__ == "__main__":
    unittest.main()
