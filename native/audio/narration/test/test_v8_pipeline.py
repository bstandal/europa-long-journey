from __future__ import annotations

import copy
import unittest

import v7_pipeline as v7
import v8_pipeline as v8


class V8MethodContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v8.load_config()

    def test_frozen_method_validates(self) -> None:
        v8.validate_config_document(copy.deepcopy(self.config))
        self.assertTrue(
            self.config["remediationContract"]
            ["v6R4AudioReuseAsV8MasterParentProhibited"]
        )
        self.assertTrue(
            self.config["promotionContract"]
            ["bothCompleteNewMastersMustPassSameFinalGate"]
        )

    def test_parent_audio_reuse_cannot_be_enabled(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["remediationContract"][
            "v6R4AudioReuseAsV8MasterParentProhibited"
        ] = False
        with self.assertRaisesRegex(v8.V8Error, "remediation"):
            v8.validate_config_document(changed)

    def test_silence_trimming_cannot_be_enabled(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["remediationContract"][
            "masterOrUtteranceSilenceTrimmingProhibited"
        ] = False
        with self.assertRaisesRegex(v8.V8Error, "remediation"):
            v8.validate_config_document(changed)

    def test_final_boundary_gate_cannot_be_lowered(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["finalAudit"]["minimumExactSharedWords"] = 15
        with self.assertRaisesRegex(v8.V8Error, "final audit"):
            v8.validate_config_document(changed)

    def test_single_candidate_cannot_open_editor_choice(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["promotionContract"][
            "singlePassingCandidateCannotOpenEditorChoice"
        ] = False
        with self.assertRaisesRegex(v8.V8Error, "promotion"):
            v8.validate_config_document(changed)


class V8SegmentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v8.load_config()
        cls.text, _, cls.cues, cls.utterances, cls.record = (
            v8.segmentation_material()
        )

    def test_exact_character_partition_and_manifest(self) -> None:
        rebuilt = "".join(
            item["text"] + item["separatorAfter"] for item in self.utterances
        )
        self.assertEqual(rebuilt, self.text)
        self.assertTrue(self.record["exactCharacterPartition"])
        self.assertEqual(self.record["utteranceCount"], 203)
        self.assertEqual(self.record["minimumNormalizedWords"], 9)
        self.assertEqual(self.record["maximumNormalizedWords"], 36)
        self.assertEqual(
            self.record["manifestSHA256"],
            self.config["segmentation"]["utteranceManifestSHA256"],
        )

    def test_representative_set_covers_all_six_cues(self) -> None:
        selected = set(
            self.config["pauseDensityLab"]["representativeUtteranceIDs"]
        )
        cue_ids = {
            item["segmentID"]
            for item in self.utterances
            if item["utteranceID"] in selected
        }
        self.assertEqual(cue_ids, {item["segmentID"] for item in self.cues})


class V8WindowGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v8.load_config()

    def test_30_15_grid_covers_every_sample_without_lowering_boundaries(self) -> None:
        audit_config = v8._v8_audit_config(self.config)
        sample_rate = 48_000
        sample_count = 1_305 * sample_rate + 6_307
        intervals = v7._window_intervals(
            sample_count, sample_rate, audit_config
        )
        coverage = v7._coverage_audit(intervals, sample_count)
        self.assertEqual(coverage["coverageFraction"], 1.0)
        self.assertEqual(coverage["gapSampleCount"], 0)
        self.assertEqual(audit_config["windowedASR"]["windowSeconds"], 30)
        self.assertEqual(audit_config["windowedASR"]["overlapSeconds"], 15)
        self.assertEqual(
            audit_config["windowedASR"]["segmentTextTimingFallback"]
            ["maximumSegmentTailOverrunMilliseconds"],
            100,
        )
        self.assertEqual(
            audit_config["windowedASR"]["boundaryGate"]
            ["minimumExactSharedWords"],
            18,
        )


if __name__ == "__main__":
    unittest.main()
