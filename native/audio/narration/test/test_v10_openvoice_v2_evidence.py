from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

import v10_openvoice_v2_evidence as evidence


class V10OpenVoiceEvidenceTests(unittest.TestCase):
    def test_durable_negative_evidence_passes(self) -> None:
        result = evidence.validate()
        self.assertEqual(result["receiptCount"], 7)
        self.assertEqual(result["sourceBindingCount"], 17)
        self.assertFalse(result["bothReferencesPass"])
        self.assertFalse(result["fullGenerationPermitted"])
        self.assertEqual(result["incrementalCostNOK"], 0)

    def test_a_passing_claim_fails_closed(self) -> None:
        document = json.loads(evidence.EVIDENCE_PATH.read_text(encoding="utf-8"))
        document["decision"]["passesFrozenRepresentativeGate"] = True
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "drifted.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaisesRegex(evidence.EvidenceError, "stopped decision"):
                evidence.validate(path)

    def test_all_live_method_sources_match_frozen_hashes(self) -> None:
        document = json.loads(evidence.EVIDENCE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(
            {item["path"] for item in document["sourceBindings"]},
            set(evidence.EXPECTED_SOURCE_BINDINGS),
        )
        for relative, (size, sha256) in evidence.EXPECTED_SOURCE_BINDINGS.items():
            path = evidence.REPOSITORY_ROOT / relative
            self.assertEqual(path.stat().st_size, size)
            self.assertEqual(evidence._sha256(path), sha256)


if __name__ == "__main__":
    unittest.main()
