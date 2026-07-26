from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest

import v5_pipeline as v5
import v7_pipeline as v7


class V7ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v7.load_config()

    def test_frozen_config_validates_and_keeps_approval_exclusions(self) -> None:
        v7.validate_config_document(copy.deepcopy(self.config))
        self.assertFalse(
            self.config["masterConstructionContract"]["oneSynthesisCallRequired"]
        )
        self.assertFalse(self.config["silenceMapping"]["removalAuthorized"])
        self.assertFalse(
            self.config["windowedASR"][
                "monolithicWhisperPermittedAsPassingEvidence"
            ]
        )

    def test_old_one_call_contract_is_rejected(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["masterConstructionContract"]["oneSynthesisCallRequired"] = True
        with self.assertRaisesRegex(v7.V7Error, "construction contract"):
            v7.validate_config_document(changed)

    def test_silence_transform_cannot_be_enabled_in_mapping_revision(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["silenceMapping"]["removalAuthorized"] = True
        with self.assertRaisesRegex(v7.V7Error, "silence-map-only"):
            v7.validate_config_document(changed)

    def test_monolithic_whisper_cannot_become_passing_evidence(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["windowedASR"][
            "monolithicWhisperPermittedAsPassingEvidence"
        ] = True
        with self.assertRaisesRegex(v7.V7Error, "window grid"):
            v7.validate_config_document(changed)

    def test_inherited_cue_coverage_cannot_be_lowered(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["windowedASR"]["aggregateGate"][
            "minimumExactReferenceCoveragePerCue"
        ] = 0.97
        with self.assertRaisesRegex(v7.V7Error, "aggregate"):
            v7.validate_config_document(changed)


class WindowCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v7.load_config()

    def test_regular_grid_reaches_final_sample_with_short_final_window(self) -> None:
        sample_rate = 48_000
        sample_count = 1_297 * sample_rate + 3_140
        intervals = v7._window_intervals(sample_count, sample_rate, self.config)
        self.assertEqual(intervals[0]["startSampleInclusive"], 0)
        self.assertEqual(intervals[-1]["endSampleExclusive"], sample_count)
        self.assertGreater(
            intervals[-1]["endSampleExclusive"]
            - intervals[-1]["startSampleInclusive"],
            10 * sample_rate,
        )
        coverage = v7._coverage_audit(intervals, sample_count)
        self.assertEqual(coverage["coverageFraction"], 1.0)
        self.assertEqual(coverage["gapSampleCount"], 0)
        self.assertGreaterEqual(coverage["minimumCoverageMultiplicity"], 1)

    def test_gap_in_window_inventory_fails(self) -> None:
        with self.assertRaisesRegex(v7.V7Error, "gap"):
            v7._coverage_audit(
                [
                    {
                        "index": 0,
                        "startSampleInclusive": 0,
                        "endSampleExclusive": 100,
                    },
                    {
                        "index": 1,
                        "startSampleInclusive": 101,
                        "endSampleExclusive": 200,
                    },
                ],
                200,
            )


class SegmentTimingFallbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v7.load_config()

    def _document(self) -> dict:
        return {
            "result": {"language": "en"},
            "transcription": [
                {
                    "offsets": {"from": 0, "to": 1_000},
                    "text": " The road holds.",
                    "tokens": [
                        {
                            "text": " The",
                            "offsets": {"from": 0, "to": 300},
                        },
                        {
                            "text": " road",
                            "offsets": {"from": 400, "to": 350},
                        },
                        {
                            "text": " holds",
                            "offsets": {"from": 700, "to": 900},
                        },
                        {"text": ".", "offsets": {"from": 900, "to": 900}},
                    ],
                }
            ],
        }

    def test_malformed_token_geometry_is_recorded_but_not_used(self) -> None:
        words, record = v7.segment_timed_words(
            self._document(), duration_ms=1_000, config=self.config
        )
        self.assertEqual([item.text for item in words], ["the", "road", "holds"])
        self.assertEqual(record["malformedTokenGeometryCount"], 1)
        self.assertFalse(record["malformedTokenGeometryUsedForTiming"])
        self.assertTrue(record["allLexicalParityChecksPass"])

    def test_segment_and_token_lexical_disagreement_fails(self) -> None:
        document = self._document()
        document["transcription"][0]["text"] = " The bridge holds."
        with self.assertRaisesRegex(v7.V7Error, "disagree"):
            v7.segment_timed_words(
                document, duration_ms=1_000, config=self.config
            )


class WindowStitchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v7.load_config()

    @staticmethod
    def _word(text: str, midpoint_ms: float) -> v5.TimedWord:
        return v5.TimedWord(text, midpoint_ms - 10, midpoint_ms + 10, 0, 1)

    def test_exact_overlap_anchor_deduplicates_transcript(self) -> None:
        shared = [f"word{index}" for index in range(20)]
        left = [self._word("before", 49_000)] + [
            self._word(word, 50_250 + index * 450)
            for index, word in enumerate(shared)
        ]
        right = [
            self._word(word, 50_300 + index * 450)
            for index, word in enumerate(shared)
        ] + [self._word("after", 60_500)]
        windows = [
            {
                "index": 0,
                "startSampleInclusive": 0,
                "endSampleExclusive": 60 * 48_000,
            },
            {
                "index": 1,
                "startSampleInclusive": 50 * 48_000,
                "endSampleExclusive": 110 * 48_000,
            },
        ]
        stitched, record = v7.stitch_window_words(
            windows=windows,
            words_by_window=[left, right],
            sample_rate=48_000,
            config=self.config,
        )
        self.assertTrue(record["allBoundariesPass"])
        texts = [item.text for item in stitched]
        for word in shared:
            self.assertEqual(texts.count(word), 1)
        self.assertEqual(texts[0], "before")
        self.assertEqual(texts[-1], "after")

    def test_overlap_without_exact_shared_words_fails(self) -> None:
        left = [self._word(f"left{index}", 50_200 + index * 400) for index in range(20)]
        right = [
            self._word(f"right{index}", 50_200 + index * 400)
            for index in range(20)
        ]
        windows = [
            {
                "index": 0,
                "startSampleInclusive": 0,
                "endSampleExclusive": 60 * 48_000,
            },
            {
                "index": 1,
                "startSampleInclusive": 50 * 48_000,
                "endSampleExclusive": 110 * 48_000,
            },
        ]
        with self.assertRaisesRegex(v7.V7Error, "no exact shared"):
            v7.stitch_window_words(
                windows=windows,
                words_by_window=[left, right],
                sample_rate=48_000,
                config=self.config,
            )

    def test_bounded_independent_decoder_seam_timing_is_reconciled(self) -> None:
        shared = [f"word{index}" for index in range(20)]
        left = [self._word("before", 49_000)] + [
            self._word(word, 50_250 + index * 450)
            for index, word in enumerate(shared)
        ]
        right = [
            self._word(word, 49_650 + index * 450)
            for index, word in enumerate(shared)
        ] + [self._word("after", 59_050)]
        windows = [
            {
                "index": 0,
                "startSampleInclusive": 0,
                "endSampleExclusive": 60 * 48_000,
            },
            {
                "index": 1,
                "startSampleInclusive": 50 * 48_000,
                "endSampleExclusive": 110 * 48_000,
            },
        ]
        stitched, record = v7.stitch_window_words(
            windows=windows,
            words_by_window=[left, right],
            sample_rate=48_000,
            config=self.config,
        )
        reconciliation = record["boundaryRecords"][0]["timestampReconciliation"]
        self.assertTrue(reconciliation["required"])
        self.assertGreater(reconciliation["forwardMilliseconds"], 0)
        self.assertLessEqual(reconciliation["forwardMilliseconds"], 750)
        self.assertTrue(record["monotoneWordCenters"])
        self.assertEqual([item.text for item in stitched].count("word10"), 1)

    def test_excessive_decoder_seam_timing_reversal_fails(self) -> None:
        shared = [f"word{index}" for index in range(20)]
        left = [
            self._word(word, 50_250 + index * 450)
            for index, word in enumerate(shared)
        ]
        right = [
            self._word(word, 48_900 + index * 450)
            for index, word in enumerate(shared)
        ] + [self._word("after", 58_050)]
        windows = [
            {
                "index": 0,
                "startSampleInclusive": 0,
                "endSampleExclusive": 60 * 48_000,
            },
            {
                "index": 1,
                "startSampleInclusive": 50 * 48_000,
                "endSampleExclusive": 110 * 48_000,
            },
        ]
        with self.assertRaisesRegex(v7.V7Error, "reconciliation bound"):
            v7.stitch_window_words(
                windows=windows,
                words_by_window=[left, right],
                sample_rate=48_000,
                config=self.config,
            )


if __name__ == "__main__":
    unittest.main()
