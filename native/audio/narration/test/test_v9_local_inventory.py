from __future__ import annotations

import unittest

import v8_pipeline as v8
import v9_local_synthesis_inventory as v9


class V9LocalSynthesisInventoryTests(unittest.TestCase):
    def test_local_apple_voice_licence_fails_commercial_gate(self) -> None:
        licence = v9.apple_voice_licence()
        self.assertEqual(
            licence["document"]["sha256"],
            "968f97210d609dbd8087f8da9e33a80f6f1b99e888a1cea2edc0b33a043bddcb",
        )
        self.assertTrue(all(licence["restrictionMatches"].values()))
        self.assertFalse(licence["commercialProductionPermitted"])
        self.assertFalse(licence["diagnosticProjectAudioPermitted"])

    def test_apple_say_has_controls_but_cannot_enter_gate(self) -> None:
        candidate = v9.apple_say_runtime(v9.apple_voice_licence())
        self.assertTrue(candidate["installedRuntimeAndWeights"])
        self.assertTrue(candidate["nativeRateControl"])
        self.assertTrue(candidate["nativeAuthoredPauseControl"])
        self.assertFalse(candidate["commerciallyPermissiveExactBytes"])
        self.assertFalse(candidate["conditionsOnBothFrozenReferences"])
        self.assertFalse(candidate["eligible"])
        self.assertGreater(candidate["installedEnglishVoiceCount"], 0)

    def test_cache_has_no_alternative_synthesis_snapshot(self) -> None:
        inventory = v9.hf_cache_inventory()
        self.assertEqual(inventory["cachedAlternativeSynthesisModelIDs"], [])
        self.assertEqual(
            set(inventory["cachedSynthesisModelIDs"]),
            {
                "ResembleAI/chatterbox-turbo",
                "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
                "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
                "mlx-community/chatterbox-turbo-fp16",
            },
        )

    def test_code_only_candidates_fail_before_synthesis(self) -> None:
        candidates = [
            v9.apple_say_runtime(v9.apple_voice_licence()),
            *v9.code_only_candidates(),
        ]
        gate = v9._candidate_gate(candidates)
        self.assertEqual(gate["eligibleCandidateIDs"], [])
        self.assertIsNone(gate["selectedCandidateID"])
        self.assertFalse(gate["passesInventoryGate"])
        self.assertEqual(
            gate["highestProbabilityAssessedCandidateID"],
            "apple-speech-synthesis",
        )
        self.assertTrue(all(item["synthesisExecuted"] is False for item in candidates))

    def test_unchanged_fourteen_by_two_contract_is_bound(self) -> None:
        contract = v9.frozen_comparison_contract(v8.load_config())
        self.assertEqual(contract["utteranceCountPerReference"], 14)
        self.assertEqual(contract["referenceCount"], 2)
        self.assertEqual(contract["requiredSynthesisCount"], 28)
        self.assertEqual(
            contract["representativeSet"]["exactTextManifestSHA256"],
            "822786bfaa942aec932686929d2ece3a7122d5215db654862cad3e28d9a8cb62",
        )
        self.assertEqual(
            contract["unchangedQualityGates"][
                "maximumModelRetainedSilenceFraction"
            ],
            0.1,
        )
        self.assertEqual(
            contract["unchangedQualityGates"][
                "maximumRepresentativeMontageSilenceFraction"
            ],
            0.115,
        )


if __name__ == "__main__":
    unittest.main()
