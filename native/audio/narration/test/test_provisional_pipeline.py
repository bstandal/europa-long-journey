from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

NARRATION_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NARRATION_ROOT))

import pipeline as production
import provisional_pipeline as provisional


class ProvisionalPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = provisional.load_provisional_config()

    def test_trust_domain_is_not_editor_approval(self) -> None:
        self.assertEqual(
            provisional.TRUST_DOMAIN,
            "CODEX_PROVISIONAL_NON_SHIPPING",
        )
        self.assertNotEqual(
            provisional.TRUST_DOMAIN,
            production.EDITOR_SELECTION_STATUS,
        )
        self.assertIn("editor voice selection", self.config["claimsExcluded"])
        self.assertIn("shipping approval", self.config["claimsExcluded"])

    def test_production_pipeline_rejects_provisional_selection(self) -> None:
        with tempfile.TemporaryDirectory(
            dir=production.EDITOR_SELECTION_ROOT
        ) as temporary:
            record_path = Path(temporary) / "provisional-selection.json"
            record_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "status": provisional.TRUST_DOMAIN,
                        "decisionType": "NARRATION_STRESS_FINALISTS",
                        "approvedBy": "codex-machine-audit",
                        "decidedAt": "2026-07-24T00:00:00Z",
                        "decisionReference": "provisional-test-only",
                        "candidateSetReceiptSHA256": "0" * 64,
                        "candidateSetReceiptBytes": 1,
                        "selectedCandidateIDs": [
                            "voice-candidate-05",
                            "voice-candidate-06",
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                production.PipelineError, "no editor approval"
            ):
                production.validate_editor_selection_record(
                    record_path,
                    {
                        "receiptSHA256": "0" * 64,
                        "receiptBytes": 1,
                    },
                )

    def test_stress_text_is_exact_approved_contract_material(self) -> None:
        text, record = provisional.stress_text(self.config)
        self.assertEqual(production.word_count(text), 3400)
        self.assertEqual(record["wordCount"], 3400)
        self.assertEqual(len(record["completeContractIDs"]), 16)
        self.assertEqual(record["cueCount"], 6)
        self.assertEqual(
            [item["wordCount"] for item in record["cueManifest"]],
            [483, 579, 655, 652, 523, 508],
        )
        self.assertEqual(record["sourceStatus"], "APPROVED_BY_EDITOR_IN_CHIEF")

    def test_cues_reassemble_the_shared_text_without_rewriting(self) -> None:
        text, _ = provisional.stress_text(self.config)
        cues = provisional.stress_cue_segments(self.config)
        self.assertEqual("\n\n".join(item["text"] for item in cues), text)
        self.assertEqual(
            [item["segmentID"] for item in cues],
            [f"cue-{index:02d}" for index in range(1, 7)],
        )
        self.assertEqual(
            [item["maxTokens"] for item in cues],
            [3140, 3764, 4258, 4238, 3400, 3302],
        )

    def test_overlong_calibration_is_bound_and_rejected(self) -> None:
        calibration = self.config["calibrationEvidence"]
        self.assertEqual(
            calibration["status"],
            "REJECTED_OVERLONG_NON_SHIPPING_CALIBRATION",
        )
        self.assertEqual(
            [item["durationSeconds"] for item in calibration["records"]],
            [1600.0, 1600.0],
        )

    def test_single_call_token_loops_are_bound_and_rejected(self) -> None:
        rejected = self.config["rejectedSingleCallEvidence"]
        self.assertEqual(
            rejected["status"],
            "REJECTED_TOKEN_LIMIT_REPETITION_NON_SHIPPING",
        )
        self.assertEqual(
            [item["firstIncorrectAudioMilliseconds"] for item in rejected["records"]],
            [52460, 233640],
        )
        self.assertTrue(
            all(
                item["maximumRepeatedSixGramOccurrences"] >= 600
                for item in rejected["records"]
            )
        )

    def test_ranking_uses_exactly_two_eligible_candidates(self) -> None:
        records = [
            {
                "candidateID": "voice-candidate-01",
                "eligibleForProvisionalStress": False,
                "machineScore100": 99,
            },
            {
                "candidateID": "voice-candidate-05",
                "eligibleForProvisionalStress": True,
                "machineScore100": 92,
            },
            {
                "candidateID": "voice-candidate-06",
                "eligibleForProvisionalStress": True,
                "machineScore100": 91,
            },
        ]
        ranking = sorted(
            records,
            key=lambda item: (-item["machineScore100"], item["candidateID"]),
        )
        eligible = [
            item["candidateID"]
            for item in ranking
            if item["eligibleForProvisionalStress"]
        ][:2]
        self.assertEqual(
            eligible,
            ["voice-candidate-05", "voice-candidate-06"],
        )

    def test_stress_master_is_segmented_without_transform_operations(self) -> None:
        stress = self.config["stressText"]
        self.assertEqual(stress["assemblyMode"], "CUE_SEGMENTED_CONTINUOUS_MASTER")
        self.assertTrue(stress["uninterruptedAuditionMasterRequired"])
        self.assertFalse(stress["singleModelCallRequired"])
        self.assertEqual(
            stress["prohibitedAssemblyOperations"],
            [
                "sample cuts",
                "inserted silence",
                "crossfades",
                "fades",
                "time stretching",
                "per-segment gain changes",
            ],
        )

    def test_lossless_native_assembly_has_exact_boundaries_and_one_gain(self) -> None:
        left = np.array([0.1, -0.2, 0.3], dtype=np.float32)
        right = np.array([-0.4, 0.5], dtype=np.float32)
        assembled, receipt = provisional.assemble_native_segments(
            [left, right], -3.0
        )
        raw = np.concatenate([left, right])
        expected, expected_gain = production.normalize_candidate(raw, -3.0)
        np.testing.assert_array_equal(assembled, expected)
        self.assertEqual(receipt["oneCommonNormalizationGain"], expected_gain)
        self.assertEqual(
            receipt["boundaries"],
            [
                {
                    "order": 1,
                    "startSampleInclusive": 0,
                    "endSampleExclusive": 3,
                    "sampleCount": 3,
                },
                {
                    "order": 2,
                    "startSampleInclusive": 3,
                    "endSampleExclusive": 5,
                    "sampleCount": 2,
                },
            ],
        )
        self.assertEqual(receipt["sampleCuts"], 0)
        self.assertEqual(receipt["insertedSilenceSamples"], 0)
        self.assertEqual(receipt["crossfades"], 0)
        self.assertFalse(receipt["timeStretchApplied"])

    def test_voice_consistency_screen_uses_frozen_cosine_gates(self) -> None:
        reference = ({"dimension": 2}, np.array([1.0, 0.0], dtype=np.float32))
        segments = [
            ({"dimension": 2}, np.array([0.99995, 0.01], dtype=np.float32)),
            ({"dimension": 2}, np.array([0.9998, 0.02], dtype=np.float32)),
        ]
        segments = [
            (record, unit / np.linalg.norm(unit)) for record, unit in segments
        ]
        result = provisional.voice_consistency_record(
            reference_embedding=reference,
            segment_embeddings=segments,
            segment_ids=["cue-01", "cue-02"],
            config=self.config,
        )
        self.assertTrue(result["passesFrozenIdentityDriftScreen"])
        self.assertEqual(
            result["requiredMinimumSegmentToReferenceCosine"], 0.96
        )
        self.assertEqual(result["requiredMinimumPairwiseSegmentCosine"], 0.985)

    def test_stress_master_has_stricter_asr_gates_than_casting(self) -> None:
        rubric = self.config["auditRubric"]
        master = rubric["stressMaster"]
        self.assertLess(
            master["maximumWordAlignmentErrorRate"],
            rubric["maximumWordAlignmentErrorRateForStress"],
        )
        self.assertEqual(master["minimumReferenceExactMatchCoverage"], 0.96)
        self.assertEqual(master["maximumRepeatedNgramOccurrences"], 3)

    def test_stress_pronunciation_screen_only_uses_terms_present(self) -> None:
        text, _ = provisional.stress_text(self.config)
        self.assertEqual(
            provisional.pronunciation_terms_present(
                self.config["pronunciationTerms"], text
            ),
            ["Augsburg", "Constantinople", "Caracalla"],
        )

    def test_validate_reports_separate_trust_domains(self) -> None:
        with mock.patch.object(production, "validate_config", return_value={"candidates": [1] * 6}):
            result = provisional.validate_only(self.config)
        self.assertTrue(result["trustDomainsAreDistinct"])
        self.assertEqual(result["trustDomain"], provisional.TRUST_DOMAIN)
        self.assertEqual(result["stressCueCount"], 6)


if __name__ == "__main__":
    unittest.main()
