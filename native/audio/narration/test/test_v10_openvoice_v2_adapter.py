from __future__ import annotations

import unittest

import numpy as np

import v10_openvoice_v2_adapter as adapter


class V10OpenVoiceAdapterTests(unittest.TestCase):
    def test_method_is_one_fixed_fourteen_by_two_grid(self) -> None:
        config = adapter.load_config()
        self.assertEqual(config["comparison"]["requiredSynthesisCount"], 28)
        self.assertEqual(config["generation"]["speed"], 1.0)
        self.assertTrue(
            config["generation"]["oneDeterministicAttemptPerUtterance"]
        )
        self.assertFalse(
            config["generation"]["parameterSelectionAfterListeningPermitted"]
        )

    def test_seed_grid_is_stable_and_unique(self) -> None:
        seeds = {
            adapter.generation_seed(candidate, utterance)
            for candidate in range(2)
            for utterance in range(14)
        }
        self.assertEqual(len(seeds), 28)
        self.assertEqual(adapter.generation_seed(0, 0), 10_000_000)
        self.assertEqual(adapter.generation_seed(1, 13), 10_100_130)

    def test_unknown_seed_index_fails(self) -> None:
        with self.assertRaises(adapter.v8.V8Error):
            adapter.generation_seed(2, 0)

    def test_audit_derivative_only_resamples_and_adds_authored_pause(self) -> None:
        source = np.linspace(-0.25, 0.25, 22_050, dtype=np.float32)
        derivative, record = adapter.audit_derivative(source, "\n\n")
        self.assertEqual(record["retainedSampleCountBeforePause"], 24_000)
        self.assertEqual(record["pauseSamples"], 2_880)
        self.assertEqual(derivative.size, 26_880)
        self.assertFalse(record["activityCropApplied"])
        self.assertFalse(record["edgeFadeApplied"])
        self.assertTrue(record["onlyAuthoredPauseAppended"])

    def test_phone_distribution_matches_pinned_melo_algorithm(self) -> None:
        self.assertEqual(adapter._distribute_phone(5, 2), [3, 2])
        self.assertEqual(adapter._distribute_phone(2, 4), [1, 1, 0, 0])


if __name__ == "__main__":
    unittest.main()
