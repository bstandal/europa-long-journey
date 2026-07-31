from __future__ import annotations

import argparse
import contextlib
import copy
import io
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np


NARRATION_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NARRATION_ROOT))

import pipeline as production
import v5_pipeline as v5
import v6_pipeline as v6


class _Tokenizer:
    @staticmethod
    def encode(text: str) -> list[int]:
        return list(range(max(1, len(v5.normalize_words(text)) * 2)))


class _Model:
    tokenizer = _Tokenizer()


class _SyntheticBatchModel(_Model):
    def __init__(self, sample_rate: int) -> None:
        self.sample_rate = sample_rate

    def batch_generate(self, *, texts: list[str], **_kwargs):
        results = []
        for index, text in enumerate(texts):
            word_count = len(v5.normalize_words(text))
            speech_samples = round(self.sample_rate * word_count / 150 * 60)
            phase = np.arange(speech_samples, dtype=np.float32) / self.sample_rate
            speech = (0.16 * np.sin(2 * np.pi * (170 + index) * phase)).astype(
                np.float32
            )
            edge = np.zeros(round(self.sample_rate * 0.12), dtype=np.float32)
            audio = np.concatenate([edge, speech, edge])
            token_count = min(74, max(1, len(self.tokenizer.encode(text)) * 3))
            results.append(
                SimpleNamespace(
                    sequence_idx=index,
                    audio=audio,
                    sample_rate=self.sample_rate,
                    samples=len(audio),
                    token_count=token_count,
                )
            )
        return results


def whisper_document(words: list[str], duration_seconds: float) -> dict:
    step = duration_seconds * 1000 / len(words)
    tokens = []
    for index, word in enumerate(words):
        tokens.append(
            {
                "text": " " + word,
                "offsets": {
                    "from": round(index * step),
                    "to": round((index + 1) * step),
                },
            }
        )
    return {
        "result": {"language": "en"},
        "params": {
            "model": v6.load_config()["offlineASR"]["modelPath"],
            "language": "en",
            "translate": False,
        },
        "transcription": [{"tokens": tokens}],
    }


class V6PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v6.load_config()
        (
            cls.text,
            cls.stress_record,
            cls.cues,
            cls.utterances,
            cls.utterance_record,
        ) = v6.stress_and_utterance_material(cls.config)

    def parse_silently(self, parser: argparse.ArgumentParser, arguments: list[str]):
        with contextlib.redirect_stderr(io.StringIO()):
            return parser.parse_args(arguments)

    def test_method_is_exact_offline_and_nonshipping(self) -> None:
        self.assertEqual(
            v6.file_binding(v6.CONFIG_PATH)["sha256"], v6.EXPECTED_CONFIG_SHA256
        )
        self.assertEqual(v6.file_binding(v6.CONFIG_PATH)["bytes"], v6.EXPECTED_CONFIG_BYTES)
        self.assertEqual(v6.METHOD_STATUS, self.config["status"])
        self.assertEqual(v6.TRUST_DOMAIN, self.config["trustDomain"])
        self.assertEqual(self.config["costPolicy"]["incrementalCostNOK"], 0)
        self.assertIn("artistic approval", self.config["claimsExcluded"])
        self.assertIn("shipping approval", self.config["claimsExcluded"])
        parser = v6.build_parser()
        self.assertEqual(
            set(parser._subparsers._group_actions[0].choices),
            {"validate", "generate", "audit"},
        )
        with self.assertRaises(SystemExit):
            self.parse_silently(
                parser,
                [
                    "audit",
                    "--stress-set",
                    "x",
                    "--output",
                    "y",
                    "--transcripts",
                    "z",
                    "--offline",
                ],
            )

    def test_config_drift_fails_closed(self) -> None:
        changed = copy.deepcopy(self.config)
        changed["segmentation"]["maximumNormalizedWordsPerUtterance"] = 100
        with self.assertRaises(v6.V6Error):
            v6.validate_config_document(changed)
        changed = copy.deepcopy(self.config)
        changed["generation"]["maximumBatchAttempts"] = 99
        with self.assertRaises(v6.V6Error):
            v6.validate_config_document(changed)
        changed = copy.deepcopy(self.config)
        changed["utteranceGate"]["minimumIdentityCosineToReference"] = 0.1
        with self.assertRaises(v6.V6Error):
            v6.validate_config_document(changed)
        changed = copy.deepcopy(self.config)
        changed["adaptiveSemanticPacing"]["targetMaximumWordsPerMinute"] = 210
        with self.assertRaises(v6.V6Error):
            v6.validate_config_document(changed)

    def test_negative_evidence_is_diagnostic_and_never_parentage(self) -> None:
        parent = v6.validate_parent_chain(self.config)
        evidence = v6.validate_v5_negative_evidence(self.config)
        self.assertFalse(parent["v4OrV5StressEvidencePermittedAsParent"])
        self.assertNotIn(
            self.config["negativeEvidence"]["v5AuditReceiptSHA256"],
            v6.canonical_json(parent),
        )
        self.assertEqual(evidence["passingCandidateCount"], 0)
        self.assertIsNone(evidence["recommendedVoiceID"])
        self.assertEqual(
            [item["candidateID"] for item in evidence["collapseRecords"]],
            v6.EXPECTED_FINALISTS,
        )
        self.assertGreater(
            evidence["collapseRecords"][0]["cueFailures"][1]["occurrences"], 40
        )

    def test_reference_tempo_1p22_is_lowest_proven_factor_not_lab_parentage(self) -> None:
        evidence = v6.validate_reference_tempo_method_evidence(self.config)
        self.assertEqual(evidence["factor"], 1.22)
        self.assertEqual(
            evidence["status"],
            "V6_REFERENCE_TEMPO_1P22_PROVEN_LOWEST_QUALIFYING_FACTOR",
        )
        self.assertFalse(evidence["labAudioPermittedAsArtifactParent"])
        self.assertFalse(evidence["r2AudioPermittedAsArtifactParent"])
        self.assertEqual(
            [item["candidateID"] for item in evidence["records"]],
            v6.EXPECTED_FINALISTS,
        )
        self.assertTrue(all(item["passesLab"] for item in evidence["records"]))

    def test_adaptive_pacing_is_proven_on_exact_rejected_r3_batch(self) -> None:
        evidence = v6.validate_adaptive_semantic_pacing_method_evidence(
            self.config
        )
        self.assertEqual(
            evidence["status"],
            "V6_ADAPTIVE_SEMANTIC_PACING_PROVEN_ON_EXACT_R3_FAILURE_BATCH",
        )
        self.assertEqual(evidence["targetMaximumWordsPerMinute"], 205)
        self.assertEqual(evidence["hardGateMaximumWordsPerMinute"], 210)
        self.assertFalse(evidence["speechTimeStretchApplied"])
        self.assertEqual(
            evidence["records"][0]["changedUtterances"],
            [
                {
                    "utteranceID": "utterance-059",
                    "additionalPauseSamples": 12059,
                    "additionalPauseMilliseconds": 502.4583333333333,
                    "wordsPerMinuteAfterPause": 204.99949910101813,
                }
            ],
        )
        self.assertEqual(evidence["records"][1]["changedUtterances"], [])
        combined = v6.validate_generation_method_evidence(self.config)
        self.assertEqual(
            combined["status"],
            "V6_REFERENCE_TEMPO_AND_ADAPTIVE_SEMANTIC_PACING_PROVEN",
        )

    def test_semantic_partition_is_exact_and_frozen(self) -> None:
        self.assertEqual(len(self.utterances), 123)
        self.assertEqual(
            "".join(item["text"] + item["separatorAfter"] for item in self.utterances),
            self.text,
        )
        self.assertEqual(sum(item["wordCount"] for item in self.utterances), 3400)
        self.assertEqual(
            sum(item["normalizedWordCount"] for item in self.utterances), 3422
        )
        self.assertEqual(
            min(item["normalizedWordCount"] for item in self.utterances), 10
        )
        self.assertEqual(
            max(item["normalizedWordCount"] for item in self.utterances), 36
        )
        self.assertEqual(
            self.utterance_record["manifestSHA256"],
            "570be5df0901c82ceacc18f8c456bade94fd54e72d297431f9150c7c85f48d38",
        )
        cue_by_id = {cue["segmentID"]: cue for cue in self.cues}
        for utterance in self.utterances:
            cue = cue_by_id[utterance["segmentID"]]
            self.assertLessEqual(
                cue["sourceCharacterStartInclusive"],
                utterance["sourceCharacterStartInclusive"],
            )
            self.assertLessEqual(
                utterance["sourceCharacterEndExclusive"],
                cue["sourceCharacterEndExclusive"],
            )

    def test_batches_and_attempt_seeds_are_deterministic(self) -> None:
        specs = v6.batch_specs(self.utterances, self.config)
        self.assertEqual(len(specs), 16)
        self.assertEqual([len(item) for item in specs[:-1]], [8] * 15)
        self.assertEqual(len(specs[-1]), 3)
        candidate = {"stressSeed": 735301}
        self.assertEqual(
            v6._batch_seed(candidate, 0, 1, self.config), 6735301
        )
        self.assertEqual(
            v6._batch_seed(candidate, 7, 3, self.config), 6736003
        )
        tokenizer_count, cap = v6._derived_token_cap(
            _Model(), self.utterances[0]["text"], self.config
        )
        self.assertGreater(tokenizer_count, 0)
        self.assertEqual(
            cap,
            min(
                384,
                max(75, tokenizer_count * 6),
            ),
        )

    def test_processing_is_deterministic_zero_edge_and_pause_bound(self) -> None:
        sample_rate = self.config["master"]["nativeSampleRate"]
        silence = np.zeros(round(sample_rate * 0.2), dtype=np.float32)
        phase = np.arange(round(sample_rate * 0.5), dtype=np.float32) / sample_rate
        speech = (0.2 * np.sin(2 * np.pi * 180 * phase)).astype(np.float32)
        raw = np.concatenate([silence, speech, silence])
        one, record_one = v6.process_utterance_audio(
            raw,
            sample_rate=sample_rate,
            separator_after=" ",
            config=self.config,
        )
        two, record_two = v6.process_utterance_audio(
            raw,
            sample_rate=sample_rate,
            separator_after=" ",
            config=self.config,
        )
        self.assertTrue(np.array_equal(one, two))
        self.assertEqual(record_one, record_two)
        self.assertEqual(one[0], 0.0)
        self.assertEqual(one[-1], 0.0)
        self.assertEqual(record_one["pauseSamples"], 720)
        joined = np.concatenate([one, two])
        selected = [
            {
                "decoded": {"sampleCount": len(one)},
                "utterance": {"utteranceID": "u0"},
            },
            {
                "decoded": {"sampleCount": len(two)},
                "utterance": {"utteranceID": "u1"},
            },
        ]
        seam = v6._seam_audit(joined, selected)
        self.assertTrue(seam["passes"])
        self.assertEqual(seam["maximumAbsoluteDiscontinuity"], 0.0)

    def test_adaptive_pacing_adds_only_bounded_semantic_boundary_silence(self) -> None:
        sample_rate = self.config["master"]["nativeSampleRate"]

        def material(seconds: float) -> np.ndarray:
            edge = np.zeros(round(sample_rate * 0.2), dtype=np.float32)
            phase = (
                np.arange(round(sample_rate * seconds), dtype=np.float32)
                / sample_rate
            )
            speech = (0.2 * np.sin(2 * np.pi * 180 * phase)).astype(np.float32)
            return np.concatenate([edge, speech, edge])

        paced, paced_record = v6.process_utterance_audio(
            material(7.4),
            sample_rate=sample_rate,
            separator_after=" ",
            config=self.config,
            normalized_word_count=27,
        )
        adaptive = paced_record["adaptiveSemanticPacing"]
        self.assertGreater(adaptive["additionalPauseSamples"], 0)
        self.assertLessEqual(adaptive["additionalPauseSamples"], sample_rate)
        self.assertTrue(adaptive["targetReachedBeforeCommitGate"])
        self.assertFalse(adaptive["speechTimeStretchApplied"])
        self.assertEqual(paced[-adaptive["additionalPauseSamples"] :].max(), 0.0)
        self.assertLessEqual(27 / (len(paced) / sample_rate / 60), 205)

        slow, slow_record = v6.process_utterance_audio(
            material(9.0),
            sample_rate=sample_rate,
            separator_after=" ",
            config=self.config,
            normalized_word_count=27,
        )
        self.assertEqual(
            slow_record["adaptiveSemanticPacing"]["additionalPauseSamples"], 0
        )
        self.assertTrue(
            slow_record["adaptiveSemanticPacing"][
                "targetReachedBeforeCommitGate"
            ]
        )
        self.assertEqual(slow[-1], 0.0)

        too_fast, too_fast_record = v6.process_utterance_audio(
            material(5.0),
            sample_rate=sample_rate,
            separator_after=" ",
            config=self.config,
            normalized_word_count=36,
        )
        self.assertEqual(
            too_fast_record["adaptiveSemanticPacing"]["additionalPauseSamples"],
            sample_rate,
        )
        self.assertFalse(
            too_fast_record["adaptiveSemanticPacing"][
                "targetReachedBeforeCommitGate"
            ]
        )
        self.assertEqual(too_fast[-sample_rate:].max(), 0.0)

    def test_utterance_gate_accepts_exact_short_speech(self) -> None:
        utterance = self.utterances[0]
        words = v5.normalize_words(utterance["text"])
        duration = len(words) / 150 * 60
        gate = v6.utterance_asr_gate(
            utterance=utterance,
            transcript=whisper_document(words, duration),
            duration_seconds=duration,
            token_count=80,
            token_cap=120,
            identity_cosine=0.99,
            config=self.config,
        )
        self.assertTrue(gate["passes"])
        self.assertTrue(all(gate["gates"].values()))

    def test_utterance_gate_rejects_token_ceiling_identity_and_loop(self) -> None:
        utterance = self.utterances[0]
        words = v5.normalize_words(utterance["text"])
        looped = words + words[:10]
        duration = len(words) / 150 * 60
        gate = v6.utterance_asr_gate(
            utterance=utterance,
            transcript=whisper_document(looped, duration),
            duration_seconds=duration,
            token_count=120,
            token_cap=120,
            identity_cosine=0.5,
            config=self.config,
        )
        self.assertFalse(gate["passes"])
        self.assertFalse(gate["gates"]["tokenCeiling"])
        self.assertFalse(gate["gates"]["identity"])
        self.assertFalse(gate["gates"]["maximumWordRatio"])
        self.assertFalse(gate["gates"]["repetition"])

    def test_unbounded_whisper_tail_is_a_discarded_variant_not_a_crash(self) -> None:
        utterance = self.utterances[0]
        words = v5.normalize_words(utterance["text"])
        duration = len(words) / 150 * 60
        transcript = whisper_document(words, duration)
        transcript["transcription"][0]["tokens"][-1]["offsets"]["to"] += 1000
        gate = v6.utterance_asr_gate(
            utterance=utterance,
            transcript=transcript,
            duration_seconds=duration,
            token_count=80,
            token_cap=120,
            identity_cosine=0.99,
            config=self.config,
        )
        self.assertFalse(gate["passes"])
        self.assertFalse(gate["gates"]["boundedTimestamps"])
        self.assertIn("outside the decoded master", gate["transcriptStructuralError"])

    def test_inventory_rejects_staging_unknown_candidates_and_nonprefix_paths(self) -> None:
        with tempfile.TemporaryDirectory(dir=NARRATION_ROOT / "work") as temporary:
            root = Path(temporary)
            (root / "batch-commits").mkdir()
            (root / "candidates").mkdir()
            (root / "conditioned-references").mkdir()
            v6.validate_generation_inventory(
                root,
                utterances=self.utterances,
                config=self.config,
                require_complete=False,
            )
            (root / ".staging").mkdir()
            with self.assertRaises(v6.V6Error):
                v6.validate_generation_inventory(
                    root,
                    utterances=self.utterances,
                    config=self.config,
                    require_complete=False,
                )
            (root / ".staging").rmdir()
            (root / "batch-commits" / "unknown").mkdir()
            with self.assertRaises(v6.V6Error):
                v6.validate_generation_inventory(
                    root,
                    utterances=self.utterances,
                    config=self.config,
                    require_complete=False,
                )

    def test_synthetic_batch_commit_is_gated_atomic_and_resumable(self) -> None:
        sample_rate = self.config["master"]["nativeSampleRate"]
        utterances = self.utterances[:8]
        model = _SyntheticBatchModel(sample_rate)
        candidate_id = v6.EXPECTED_FINALISTS[0]
        candidate = {"stressSeed": 735301}
        real_parent = v6._generation_context(self.config)["parentRecords"][candidate_id]
        parent_candidate = {
            "_verifiedReferencePath": real_parent["_verifiedReferencePath"],
            "reference": {"sha256": real_parent["reference"]["sha256"]},
            "instructionSHA256": real_parent["instructionSHA256"],
        }
        parent_chain = v6.validate_parent_chain(self.config)
        negative = v6.validate_v5_negative_evidence(self.config)
        reference_record = {"syntheticTestReference": True}
        model_receipt = {"syntheticTestModel": True}
        method_evidence = {"syntheticTempoMethodEvidence": True}

        def synthetic_whisper_batch(*, audio_paths, staging, config):
            paths = []
            for utterance, audio_path in zip(utterances, audio_paths, strict=True):
                _, info = v5.read_native_audio(audio_path, config)
                duration = info["sampleCount"] / sample_rate
                transcript_path = Path(str(audio_path) + ".json")
                transcript_path.write_text(
                    v6.canonical_json(
                        whisper_document(v5.normalize_words(utterance["text"]), duration)
                    )
                    + "\n",
                    encoding="utf-8",
                )
                paths.append(transcript_path)
            log = staging / "whisper.batch.log.txt"
            log.write_text("synthetic offline Whisper gate\n", encoding="utf-8")
            return paths, {
                "tool": v6.validate_asr_tools(config),
                "arguments": list(config["offlineASR"]["arguments"]),
                "inputCount": len(audio_paths),
                "inputFiles": [v6.file_binding(path) for path in audio_paths],
                "log": v6.file_binding(log),
                "answerPromptUsed": False,
                "externalTranscriptReceiptUsed": False,
                "networkUsed": False,
            }

        frozen_work = v6.work_root(self.config, create=True)
        with tempfile.TemporaryDirectory(dir=frozen_work) as temporary:
            output_root = v6.prepare_generation_root(Path(temporary), self.config)
            failure_log = v6._load_failure_log(
                output_root,
                config=self.config,
                parent_chain=parent_chain,
            )
            reference_path = (
                output_root
                / "conditioned-references"
                / "synthetic-conditioned-reference.wav"
            )
            production.write_float_wav(
                reference_path,
                sample_rate,
                np.zeros(sample_rate, dtype=np.float32),
            )
            conditioning_record = {
                "conditionedReference": v6.file_binding(reference_path)
            }
            with mock.patch.object(v6, "run_whisper_batch", synthetic_whisper_batch):
                committed, returned_log = v6.commit_generated_batch(
                    output_root=output_root,
                    candidate_id=candidate_id,
                    candidate=candidate,
                    parent_candidate=parent_candidate,
                    batch_index=0,
                    utterances=utterances,
                    model=model,
                    extractor=lambda _audio: np.asarray([1.0, 0.0], dtype=np.float32),
                    reference_unit=np.asarray([1.0, 0.0], dtype=np.float32),
                    reference_record=reference_record,
                    generation_reference_path=reference_path,
                    conditioning_record=conditioning_record,
                    method_evidence=method_evidence,
                    identity_text="Synthetic reference text.",
                    model_receipt=model_receipt,
                    config=self.config,
                    parent_chain=parent_chain,
                    negative_evidence=negative,
                    failure_log=failure_log,
                )
            self.assertEqual(returned_log["entries"], [])
            self.assertTrue(
                all(item["record"]["gate"]["passes"] for item in committed["utterances"])
            )
            resumed = v6.validate_batch_commit(
                output_root=output_root,
                candidate_id=candidate_id,
                candidate=candidate,
                parent_candidate=parent_candidate,
                batch_index=0,
                utterances=utterances,
                model=model,
                extractor=lambda _audio: np.asarray([1.0, 0.0], dtype=np.float32),
                reference_unit=np.asarray([1.0, 0.0], dtype=np.float32),
                reference_record=reference_record,
                conditioning_record=conditioning_record,
                method_evidence=method_evidence,
                model_receipt=model_receipt,
                config=self.config,
                parent_chain=parent_chain,
                negative_evidence=negative,
            )
            self.assertEqual(resumed["receiptBinding"], committed["receiptBinding"])
            transcript_path = resumed["utterances"][0]["transcriptPath"]
            transcript_path.write_text("{}\n", encoding="utf-8")
            with self.assertRaises(v6.V6Error):
                v6.validate_batch_commit(
                    output_root=output_root,
                    candidate_id=candidate_id,
                    candidate=candidate,
                    parent_candidate=parent_candidate,
                    batch_index=0,
                    utterances=utterances,
                    model=model,
                    extractor=lambda _audio: np.asarray([1.0, 0.0], dtype=np.float32),
                    reference_unit=np.asarray([1.0, 0.0], dtype=np.float32),
                    reference_record=reference_record,
                    conditioning_record=conditioning_record,
                    method_evidence=method_evidence,
                    model_receipt=model_receipt,
                    config=self.config,
                    parent_chain=parent_chain,
                    negative_evidence=negative,
                )
    def test_cli_refuses_missing_explicit_offline(self) -> None:
        parser = v6.build_parser()
        for arguments in [
            ["validate"],
            ["generate", "--output", "x"],
            ["audit", "--stress-set", "x", "--output", "y"],
        ]:
            with self.assertRaises(SystemExit):
                self.parse_silently(parser, arguments)


if __name__ == "__main__":
    unittest.main()
