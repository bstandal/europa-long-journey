from __future__ import annotations

import unittest

import v10_openvoice_v2_audit_comparison as audit


class V10OpenVoiceAuditComparisonTests(unittest.TestCase):
    def test_generation_receipt_is_exact_and_still_non_shipping(self) -> None:
        document = audit._generation_document()
        self.assertEqual(document["synthesisCount"], 28)
        self.assertFalse(document["representativeGateRun"])
        self.assertFalse(document["fullGenerationPermitted"])
        self.assertTrue(document["rawConverterOutputsRetainedUnmodified"])

    def test_unchanged_gate_function_is_reused(self) -> None:
        self.assertIs(
            audit.frozen_audit._audit_comparison,
            audit.frozen_audit._audit_comparison,
        )
        thresholds = audit.v8.load_config()["pauseDensityLab"]
        self.assertEqual(thresholds["minimumUtteranceIdentityCosine"], 0.98)
        self.assertEqual(thresholds["maximumAggregateWordErrorRate"], 0.03)
        self.assertEqual(thresholds["maximumModelRetainedSilenceFraction"], 0.1)
        self.assertEqual(
            thresholds["maximumRepresentativeMontageSilenceFraction"], 0.115
        )
        self.assertEqual(thresholds["minimumProjectedFullDurationSeconds"], 1080)
        self.assertEqual(thresholds["maximumProjectedFullDurationSeconds"], 1320)


if __name__ == "__main__":
    unittest.main()
