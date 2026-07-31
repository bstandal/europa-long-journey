from __future__ import annotations

from pathlib import Path
import sys
import unittest

NARRATION_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NARRATION_ROOT))

import v11_voxcpm2_terminal_evidence as evidence


class V11VoxCPM2TerminalEvidenceTests(unittest.TestCase):
    def test_terminal_negative_evidence_is_exact_and_non_shipping(self) -> None:
        result = evidence.validate()
        self.assertEqual(result["modelLoadGate"], "PASS")
        self.assertEqual(
            result["representativeGeneration"],
            "STOPPED_AT_FIRST_DEVIATION",
        )
        self.assertEqual(result["completedJobCount"], 0)
        self.assertFalse(result["retryPermitted"])
        self.assertFalse(result["resumePermitted"])
        self.assertFalse(result["shippingPermitted"])
        self.assertEqual(result["cacheEvidence"]["fileCount"], 46)

    def test_representative_tree_contains_no_job_or_generation_receipt(self) -> None:
        tree = {
            path.relative_to(evidence.REPRESENTATIVE_ROOT).as_posix()
            for path in evidence.REPRESENTATIVE_ROOT.rglob("*")
            if path.is_file()
        }
        self.assertEqual(tree, evidence.EXPECTED_REPRESENTATIVE_TREE)


if __name__ == "__main__":
    unittest.main()
