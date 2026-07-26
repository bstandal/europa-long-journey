from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

NARRATION_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NARRATION_ROOT))

import v11_narration_candidate_evidence as evidence
import v11_narration_candidate_preflight as gate


class V11NarrationCandidateGateTests(unittest.TestCase):
    def test_durable_primary_source_gate_passes_offline(self) -> None:
        result = gate.validate()
        self.assertEqual(result["candidateCount"], 5)
        self.assertEqual(result["eligibleCandidateCount"], 1)
        self.assertEqual(result["selectedCandidateID"], "voxcpm2")
        self.assertEqual(result["primaryDocumentCount"], 16)
        self.assertFalse(result["generatedAudio"])

    def test_candidate_universe_and_stopped_decision_are_exact(self) -> None:
        document = json.loads(gate.GATE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(
            [item["candidateID"] for item in document["candidates"]],
            [
                "kokoro-82m",
                "parler-tts-mini-v1",
                "styletts2-libritts",
                "pocket-tts",
                "voxcpm2",
            ],
        )
        self.assertFalse(document["decision"]["comparisonSynthesisPermitted"])
        self.assertFalse(document["decision"]["full203By2GenerationPermitted"])
        self.assertTrue(document["decision"]["exactByteRuntimePreflightPermitted"])

    def test_primary_document_whitelist_cannot_resolve_model_or_audio_bytes(self) -> None:
        forbidden = (".pth", ".pt", ".safetensors", ".wav", ".zip")
        for document in gate.DOCUMENTS:
            url = document["url"].lower().split("?", 1)[0]
            self.assertFalse(url.endswith(forbidden), document["documentID"])

    def test_winner_or_synthesis_permission_mutation_fails_closed(self) -> None:
        document = json.loads(gate.GATE_PATH.read_text(encoding="utf-8"))
        document["decision"]["selectedCandidateID"] = "pocket-tts"
        document["decision"]["comparisonSynthesisPermitted"] = True
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "drifted.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaisesRegex(gate.GateError, "durable V11 candidate gate"):
                gate.validate(path)

    def test_durable_evidence_binds_gate_and_preflight_sources(self) -> None:
        result = evidence.validate()
        self.assertEqual(result["sourceBindingCount"], 2)
        self.assertEqual(result["selectedCandidateID"], "voxcpm2")
        self.assertTrue(result["exactByteRuntimePreflightPermitted"])
        self.assertFalse(result["comparisonSynthesisPermitted"])
        for relative, (size, sha256) in evidence.EXPECTED_SOURCE_BINDINGS.items():
            path = evidence.REPOSITORY_ROOT / relative
            self.assertEqual(path.stat().st_size, size)
            self.assertEqual(evidence._sha256(path), sha256)


if __name__ == "__main__":
    unittest.main()
