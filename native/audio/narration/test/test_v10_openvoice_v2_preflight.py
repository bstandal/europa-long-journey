from __future__ import annotations

import unittest

import v10_openvoice_v2_preflight as v10
import v10_openvoice_v2_snapshot as snapshot
import v8_pipeline as v8
import v9_local_synthesis_inventory as v9


class V10OpenVoiceV2PreflightTests(unittest.TestCase):
    def test_download_plan_is_exact_and_rejects_mutable_aliases(self) -> None:
        plan = v10.download_plan()
        self.assertEqual(plan["codeArchiveBytes"], 9_067_071)
        self.assertEqual(plan["modelAndEvidenceBytes"], 780_368_220)
        self.assertEqual(plan["totalBoundDownloadBytes"], 789_435_291)
        self.assertFalse(plan["unlistedFilesPermitted"])
        self.assertFalse(plan["mutableRevisionAliasesPermitted"])

    def test_every_whitelisted_model_file_has_a_sha256(self) -> None:
        selected = [
            file
            for spec in v10.MODEL_SPECS.values()
            for file in spec["files"].values()
        ]
        self.assertEqual(len(selected), 14)
        self.assertTrue(all(len(item["sha256"]) == 64 for item in selected))

    def test_method_bypasses_melo_tail_padding(self) -> None:
        method = v10.synthesis_method_contract()
        self.assertEqual(method["baseModelCall"], "TTS.model.infer")
        self.assertFalse(method["publicTtsToFileCallPermitted"])
        self.assertFalse(method["audioNumpyConcatCallPermitted"])
        self.assertFalse(method["automaticSentenceSplitterPermitted"])
        self.assertEqual(method["rawGeneratedSpeechPaddingSamples"], 0)
        self.assertFalse(method["rawOuterActivityCropApplied"])
        self.assertFalse(
            method["toneColourConditioning"]["standardGetSeHelperPermitted"]
        )
        self.assertFalse(
            method["toneColourConditioning"][
                "convertedWaveformPostProcessingPermitted"
            ]
        )
        self.assertEqual(
            method["modelNativeRateControl"]["modelArgument"],
            "length_scale=1.0/speed",
        )
        self.assertFalse(
            method["modelNativeRateControl"]["postSynthesisTimeStretch"]
        )
        self.assertTrue(method["meetsFrozenV8NoRepairContract"])

    def test_authored_pause_values_are_inherited_unchanged(self) -> None:
        pauses = v10.synthesis_method_contract()["authoredBoundaryPauses"]
        self.assertEqual(pauses["intraParagraphMilliseconds"], 30)
        self.assertEqual(pauses["paragraphMilliseconds"], 120)
        self.assertEqual(pauses["finalMilliseconds"], 0)
        self.assertEqual(pauses["intraParagraphBoundaryCount"], 45)
        self.assertEqual(pauses["paragraphBoundaryCount"], 157)
        self.assertEqual(pauses["finalBoundaryCount"], 1)
        self.assertEqual(pauses["totalMillisecondsAcrossCompleteV8Assembly"], 20_190)
        self.assertFalse(pauses["adaptive"])
        self.assertFalse(pauses["durationFilling"])

    def test_candidate_keeps_unchanged_fourteen_by_two_gate(self) -> None:
        comparison = v9.frozen_comparison_contract(v8.load_config())
        self.assertEqual(comparison["utteranceCountPerReference"], 14)
        self.assertEqual(comparison["referenceCount"], 2)
        self.assertEqual(comparison["requiredSynthesisCount"], 28)
        self.assertEqual(
            comparison["representativeSet"]["exactTextManifestSHA256"],
            "822786bfaa942aec932686929d2ece3a7122d5215db654862cad3e28d9a8cb62",
        )

    def test_primary_documents_and_models_are_pinned_to_revisions(self) -> None:
        self.assertTrue(
            all(
                len(spec.get("sha256", spec.get("canonicalSHA256", ""))) == 64
                for spec in v10.PRIMARY_DOCUMENTS.values()
            )
        )
        self.assertEqual(
            v10.MODEL_SPECS["openVoiceV2"]["revision"],
            "f36e7edfe1684461a8343844af60babc2efbb727",
        )
        self.assertEqual(
            v10.MODEL_SPECS["meloEnglish"]["revision"],
            "bb4fb7346d566d277ba8c8c7dbfdf6786139b8ef",
        )
        self.assertEqual(
            v10.MODEL_SPECS["bertBaseUncased"]["revision"],
            "86b5e0934494bd15c9632b12f734a8a67f723594",
        )

    def test_snapshot_inventory_is_the_exact_whitelist(self) -> None:
        inventory = snapshot.download_inventory()
        self.assertEqual(len(inventory), 16)
        self.assertEqual(
            sum(item["bytes"] for item in inventory),
            v10.download_plan()["totalBoundDownloadBytes"],
        )
        self.assertEqual(
            len({item["relativePath"] for item in inventory}), len(inventory)
        )
        self.assertTrue(all(len(item["sha256"]) == 64 for item in inventory))
        self.assertTrue(
            all(item["revision"] not in {"main", "master"} for item in inventory)
        )


if __name__ == "__main__":
    unittest.main()
