from __future__ import annotations

import argparse
import copy
import contextlib
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np
from scipy.io import wavfile


NARRATION_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NARRATION_ROOT))

import pipeline as production
import v5_pipeline as v5


NEGATIVE_VECTOR_IDS = {
    "alignment-anchor-ambiguity",
    "alignment-boundary-shift",
    "alignment-boundary-insertion-run",
    "alignment-coverage-loss",
    "alignment-hypothesis-run",
    "alignment-distributed-insertions",
    "alignment-reference-run",
    "alignment-truncation",
    "asr-arguments-config-drift",
    "asr-arguments-runtime-drift",
    "asr-external-transcript",
    "asr-model-parameter-forgery",
    "asr-output-path-escape",
    "asr-preexisting-dangling-symlink",
    "asr-output-symlink",
    "audit-without-offline",
    "cli-external-transcript-argument",
    "config-byte-forgery",
    "config-path-substitution",
    "config-status-drift",
    "config-threshold-drift",
    "duration-over-22-minutes",
    "duration-under-18-minutes",
    "generation-multiple-results",
    "generation-inventory-forgery",
    "generation-pipeline-binding-forgery",
    "generation-progress-forgery",
    "generation-nonfinite-audio",
    "generation-sample-count-forgery",
    "generation-streaming-result",
    "generation-token-at-ceiling",
    "generation-token-boolean",
    "generation-token-missing",
    "generation-token-over-ceiling",
    "generate-without-offline",
    "master-alternate-format",
    "master-duration-truncation",
    "master-forged-native-relation",
    "master-resample",
    "native-resample",
    "output-nested-child",
    "output-nonempty-reuse",
    "output-root-reuse",
    "output-sibling-escape",
    "output-symlink",
    "original-cue04-anchor-ambiguity",
    "parent-chain-hash-forgery",
    "parent-chain-symlink",
    "receipt-absolute-path",
    "receipt-binding-forgery",
    "receipt-parent-escape",
    "receipt-symlink-leaf",
    "receipt-token-count-forgery",
    "repetition-excess-loop",
    "silence-boundary",
    "silence-boundary-after",
    "silence-boundary-one-sided",
    "silence-cue-edge",
    "silence-total-fraction",
    "tempo-cue-outlier",
    "timed-word-empty-transcript",
    "timed-word-nonmonotone",
    "timed-word-out-of-bounds",
    "timed-word-overlap",
    "timed-word-boundary-overflow",
    "validate-without-offline",
    "voice-identity-whole-cue-forgery",
    "voice-identity-window-forgery",
}


class V5PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = v5.load_config()

    def assert_rejected(
        self,
        vector_id: str,
        action,
        exception: type[BaseException] | tuple[type[BaseException], ...] = v5.V5Error,
    ) -> None:
        self.assertIn(vector_id, NEGATIVE_VECTOR_IDS)
        with self.assertRaises(exception):
            action()

    def _parse_silently(self, parser: argparse.ArgumentParser, arguments: list[str]):
        with contextlib.redirect_stderr(io.StringIO()):
            return parser.parse_args(arguments)

    def test_negative_vector_manifest_is_exact_and_exercised_once(self) -> None:
        source = Path(__file__).read_text(encoding="utf-8")
        occurrences = re.findall(
            r'self\.assert_rejected\(\s*"([^"]+)"', source, flags=re.MULTILINE
        )
        self.assertEqual(set(occurrences), NEGATIVE_VECTOR_IDS)
        self.assertEqual(len(occurrences), len(NEGATIVE_VECTOR_IDS))

    def test_v5_is_frozen_nonshipping_and_exposes_only_bound_generation(self) -> None:
        self.assertEqual(
            v5.METHOD_STATUS, "CODEX_V5_METHOD_FROZEN_WITH_BOUND_GENERATOR"
        )
        self.assertEqual(v5.TRUST_DOMAIN, "CODEX_V5_DIAGNOSTIC_NON_SHIPPING")
        self.assertIn("editor voice selection", self.config["claimsExcluded"])
        self.assertIn("shipping approval", self.config["claimsExcluded"])
        parser = v5.build_parser()
        self.assertEqual(
            set(parser._subparsers._group_actions[0].choices),
            {"validate", "generate", "audit"},
        )
        generated = self._parse_silently(
            parser, ["generate", "--output", "future-v5", "--offline"]
        )
        self.assertEqual(generated.command, "generate")
        self.assertTrue(generated.offline)
        self.assert_rejected(
            "cli-external-transcript-argument",
            lambda: self._parse_silently(
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
            ),
            SystemExit,
        )

    def test_exact_config_and_asr_contract_fail_closed(self) -> None:
        self.assertEqual(self.config["offlineASR"]["arguments"], v5.EXPECTED_ASR_ARGUMENTS)
        self.assertEqual(v5.file_binding(v5.CONFIG_PATH)["bytes"], v5.EXPECTED_CONFIG_BYTES)
        self.assertEqual(
            v5.file_binding(v5.CONFIG_PATH)["sha256"], v5.EXPECTED_CONFIG_SHA256
        )
        with tempfile.TemporaryDirectory(dir=NARRATION_ROOT / "work") as temporary:
            alternate = Path(temporary) / "alternate.json"
            alternate.write_bytes(v5.CONFIG_PATH.read_bytes())
            self.assert_rejected(
                "config-path-substitution", lambda: v5.load_config(alternate)
            )
            alternate.write_bytes(v5.CONFIG_PATH.read_bytes() + b" ")
            with mock.patch.object(v5, "CONFIG_PATH", alternate):
                self.assert_rejected(
                    "config-byte-forgery", lambda: v5.load_config(alternate)
                )
        changed = copy.deepcopy(self.config)
        changed["status"] = "APPROVED"
        self.assert_rejected(
            "config-status-drift", lambda: v5.validate_config_document(changed)
        )
        changed = copy.deepcopy(self.config)
        changed["identity"]["minimumWindowToReferenceCosine"] = 0.1
        self.assert_rejected(
            "config-threshold-drift", lambda: v5.validate_config_document(changed)
        )
        changed = copy.deepcopy(self.config)
        changed["offlineASR"]["arguments"] = ["--language", "en"]
        self.assert_rejected(
            "asr-arguments-config-drift",
            lambda: v5.validate_config_document(changed),
        )

    def test_parent_chain_validates_actual_bytes_and_rejects_forgery(self) -> None:
        parent = v5.validate_parent_chain(self.config)
        self.assertEqual(parent["provisionalFinalistIDs"], v5.EXPECTED_FINALISTS)
        self.assertFalse(parent["v4StressEvidencePermittedAsParent"])
        changed = copy.deepcopy(self.config)
        changed["parentChain"]["productionPipelineSHA256"] = "0" * 64
        self.assert_rejected(
            "parent-chain-hash-forgery", lambda: v5.validate_parent_chain(changed)
        )

    def test_completed_generation_lineage_accepts_only_exact_bound_methods(self) -> None:
        current = v5.pipeline_binding(self.config)
        frozen = v5.frozen_completed_generation_pipeline_binding(self.config)
        self.assertEqual(
            v5.validated_generation_pipeline_binding(current, self.config), current
        )
        self.assertEqual(
            v5.validated_generation_pipeline_binding(frozen, self.config), frozen
        )
        self.assertNotEqual(current["script"], frozen["script"])
        forged = copy.deepcopy(frozen)
        forged["script"]["sha256"] = "0" * 64
        self.assert_rejected(
            "generation-pipeline-binding-forgery",
            lambda: v5.validated_generation_pipeline_binding(forged, self.config),
        )

    def test_resegmentation_preserves_text_and_removes_original_cue04_ambiguity(self) -> None:
        text, record, cues = v5.stress_material(self.config)
        self.assertEqual(record["wordCount"], 3400)
        self.assertEqual(
            record["textSHA256"],
            "b375fe2c3ea7658c4cab28f68812dc58a50b0bcb026466e0f777118de2eb8a28",
        )
        self.assertEqual(len(cues), 6)
        self.assertEqual(
            "".join(cue["text"] + cue["separatorAfter"] for cue in cues), text
        )
        self.assertEqual([cue["wordCount"] for cue in cues], [483, 579, 670, 637, 523, 508])
        self.assertEqual([cue["maxTokens"] for cue in cues], [3140, 3764, 4355, 4141, 3400, 3302])
        self.assertEqual(cues[2]["boundaryAfter"], "AUTHORED_SENTENCE")
        self.assertEqual(cues[2]["separatorAfter"], " ")
        self.assertIn("contract-10", cues[2]["contractIDs"])
        self.assertIn("contract-10", cues[3]["contractIDs"])

        contracts = production.load_json(
            v5.REPOSITORY_ROOT / self.config["stressText"]["sourcePath"]
        )
        contract_10 = next(
            item for item in contracts["contracts"] if item["contractID"] == "contract-10"
        )
        old_first_anchor = v5.normalize_words(contract_10["thesis"])[:8]
        old_occurrences = v5._subsequence_starts(v5.normalize_words(text), old_first_anchor)
        self.assertEqual(old_occurrences, [1728, 1832])
        self.assert_rejected(
            "original-cue04-anchor-ambiguity",
            lambda: (_ for _ in ()).throw(v5.V5Error("old anchor ambiguous"))
            if len(old_occurrences) != 1
            else None,
        )
        new_occurrences = v5._subsequence_starts(
            v5.normalize_words(text), cues[3]["firstAnchor"]
        )
        self.assertEqual(new_occurrences, [1743])

    def test_v4_evidence_remains_exact_diagnostic_only(self) -> None:
        result = v5.validate_v4_diagnostic_evidence(self.config, deep=False)
        self.assertEqual(
            result["status"], "REJECTED_DIAGNOSTIC_ONLY_NEVER_A_V5_PARENT"
        )
        self.assertEqual(result["passingCandidateCount"], 0)
        self.assertIsNone(result["recommendedVoiceID"])
        expected = {
            "provisional_pipeline.py": (
                85152,
                "1b0260a85bd2eb56169bc9ecdfd5fcb2e7659da7ebd17e63d9ea43fb11818f31",
            ),
            "provisional-audit-config.json": (
                9564,
                "f99cc46d6d49a545548283b5edf6e5bee1df7af6386699d87b34aed130ac95e3",
            ),
        }
        for name, (byte_count, digest) in expected.items():
            path = NARRATION_ROOT / name
            self.assertEqual(path.stat().st_size, byte_count)
            self.assertEqual(v5.sha256_file(path), digest)

    def test_path_confinement_rejects_escape_nesting_reuse_and_symlinks(self) -> None:
        with tempfile.TemporaryDirectory(dir=NARRATION_ROOT / "work") as temporary:
            repository = Path(temporary) / "repo"
            work = repository / "work"
            work.mkdir(parents=True)
            config = copy.deepcopy(self.config)
            config["paths"]["workRoot"] = "work"
            with mock.patch.object(v5, "REPOSITORY_ROOT", repository):
                valid = v5.prepare_output_root(work / "valid", config)
                self.assertEqual(valid, work / "valid")
                self.assert_rejected(
                    "output-root-reuse",
                    lambda: v5.prepare_output_root(work, config),
                )
                nested_parent = work / "nested"
                nested_parent.mkdir()
                self.assert_rejected(
                    "output-nested-child",
                    lambda: v5.prepare_output_root(nested_parent / "child", config),
                )
                self.assert_rejected(
                    "output-sibling-escape",
                    lambda: v5.prepare_output_root(repository / "sibling", config),
                )
                nonempty = work / "nonempty"
                nonempty.mkdir()
                (nonempty / "leaf").write_text("x", encoding="utf-8")
                self.assert_rejected(
                    "output-nonempty-reuse",
                    lambda: v5.prepare_output_root(nonempty, config),
                )
                outside = repository / "outside"
                outside.mkdir()
                link = work / "linked-output"
                link.symlink_to(outside, target_is_directory=True)
                self.assert_rejected(
                    "output-symlink", lambda: v5.prepare_output_root(link, config)
                )
            parent = repository / "parent"
            target = repository / "target"
            target.mkdir()
            parent.symlink_to(target, target_is_directory=True)
            self.assert_rejected(
                "parent-chain-symlink",
                lambda: v5.confined_path(
                    parent / "leaf", root=repository, must_exist=False
                ),
            )

    def test_generation_resume_inventory_and_progress_are_fail_closed(self) -> None:
        _, stress_record, cues = v5.stress_material(self.config)
        v5_work_root = NARRATION_ROOT / "work" / "provisional-audit-v5"
        v5_work_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=v5_work_root) as temporary:
            output = v5.prepare_generation_root(Path(temporary), self.config)
            v5.validate_generation_inventory(output, self.config, cues)
            rogue = output / "unbound.wav"
            rogue.write_bytes(b"forged")
            self.assert_rejected(
                "generation-inventory-forgery",
                lambda: v5.validate_generation_inventory(output, self.config, cues),
            )
            rogue.unlink()
            progress = output / "generation-progress.v5.receipt.json"
            v5.write_json(progress, {"schemaVersion": 1, "status": "FORGED"})
            self.assert_rejected(
                "generation-progress-forgery",
                lambda: v5.update_generation_progress(
                    output_root=output,
                    work_root=v5_work_root,
                    config=self.config,
                    parent_chain={"fixture": "parent"},
                    stress_record=stress_record,
                    model_receipt={"fixture": "model"},
                    cue_commits=[],
                    candidate_commits=[],
                ),
            )

    def test_composite_cue_receipt_rejects_forged_token_count(self) -> None:
        _, _, cues = v5.stress_material(self.config)
        cue = cues[0]
        base_config = production.validate_config()
        candidate = production.candidate_by_id(base_config, "voice-candidate-05")
        parent_candidate = {
            "reference": {"sha256": "1" * 64, "bytes": 123},
            "instructionSHA256": "2" * 64,
        }
        parent_chain = {"fixture": "fully-bound-parent"}
        model_receipt = {"fixture": "pinned-model"}
        identity_hash = "3" * 64
        v5_work_root = NARRATION_ROOT / "work" / "provisional-audit-v5"
        v5_work_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=v5_work_root) as temporary:
            output = v5.prepare_generation_root(Path(temporary), self.config)
            commit = output / v5._cue_commit_relative(
                "voice-candidate-05", cue["segmentID"]
            )
            commit.mkdir(parents=True)
            audio_path = commit / "audio-f32.wav"
            wavfile.write(audio_path, 24000, np.full(100, 0.1, dtype=np.float32))
            _, decoded = v5.read_native_audio(audio_path, self.config)
            receipt = {
                "schemaVersion": 1,
                "status": v5.CUE_COMMIT_STATUS,
                "trustDomain": v5.TRUST_DOMAIN,
                "createdAt": "fixture",
                "pipelineBinding": v5.pipeline_binding(self.config),
                "parentChain": parent_chain,
                "voiceCloneModel": model_receipt,
                "candidateID": "voice-candidate-05",
                "reference": parent_candidate["reference"],
                "instructionSHA256": parent_candidate["instructionSHA256"],
                "baseStressSeed": candidate["stressSeed"],
                "identityReferenceTextSHA256": identity_hash,
                "cueSpec": v5._cue_public_spec(cue),
                "generationSeed": candidate["stressSeed"] + cue["seedOffset"],
                "generationSettings": v5._expected_generation_settings(
                    base_config, max_tokens=cue["maxTokens"]
                ),
                "generation": {
                    "tokenCount": cue["maxTokens"],
                    "maxTokens": cue["maxTokens"],
                    "tokenCeilingReached": False,
                    "sampleCount": decoded["sampleCount"],
                    "sampleRate": decoded["sampleRate"],
                    "nonStreamingResultCount": 1,
                    "peakAbsolute": float(np.max(np.abs(np.full(100, 0.1, dtype=np.float32)))),
                },
                "wholeUntouchedNonStreamingGeneration": True,
                "audio": {
                    "relativePath": (
                        v5._cue_commit_relative("voice-candidate-05", cue["segmentID"])
                        / "audio-f32.wav"
                    ).as_posix(),
                    "file": v5.file_binding(audio_path),
                    "float32LESHA256": decoded["float32LESHA256"],
                },
                "claimsExcluded": self.config["claimsExcluded"],
            }
            v5.write_json(commit / "cue.v5.receipt.json", receipt)
            self.assert_rejected(
                "receipt-token-count-forgery",
                lambda: v5.validate_cue_commit(
                    output_root=output,
                    candidate_id="voice-candidate-05",
                    candidate=candidate,
                    parent_candidate=parent_candidate,
                    cue=cue,
                    config=self.config,
                    base_config=base_config,
                    parent_chain=parent_chain,
                    model_receipt=model_receipt,
                    identity_text_sha256=identity_hash,
                ),
            )

    def test_failed_generation_commits_remove_uncommitted_staging(self) -> None:
        _, _, cues = v5.stress_material(self.config)
        base_config = production.validate_config()
        candidate_id = "voice-candidate-05"
        candidate = production.candidate_by_id(base_config, candidate_id)
        with tempfile.TemporaryDirectory(dir=NARRATION_ROOT / "work") as temporary:
            work_root = Path(temporary)
            output_root = work_root / "output"
            output_root.mkdir()
            cue = cues[0]
            cue_audio = np.full(100, 0.1, dtype=np.float32)
            bad_generation = {
                "tokenCount": 10,
                "maxTokens": cue["maxTokens"],
                "tokenCeilingReached": False,
                "sampleCount": 99,
                "sampleRate": 24000,
                "nonStreamingResultCount": 1,
                "peakAbsolute": float(np.max(np.abs(cue_audio))),
            }
            with self.assertRaises(v5.V5Error):
                v5.commit_v5_cue(
                    output_root=output_root,
                    work_root=work_root,
                    candidate_id=candidate_id,
                    candidate=candidate,
                    parent_candidate={
                        "reference": {"sha256": "1" * 64, "bytes": 1},
                        "instructionSHA256": "2" * 64,
                    },
                    cue=cue,
                    audio=cue_audio,
                    sample_rate=24000,
                    generation=bad_generation,
                    config=self.config,
                    base_config=base_config,
                    parent_chain={"fixture": "parent"},
                    model_receipt={"fixture": "model"},
                    identity_text_sha256="3" * 64,
                )
            self.assertEqual(list(work_root.glob(".v5-cue-stage-*")), [])

            cue_commits = []
            for item in cues:
                audio = np.full(100, 0.1, dtype=np.float32)
                cue_commits.append(
                    {
                        "receipt": {
                            "candidateID": candidate_id,
                            "cueSpec": {"segmentID": item["segmentID"]},
                            "generationSeed": candidate["stressSeed"]
                            + item["seedOffset"],
                            "generation": {"tokenCount": 10},
                            "audio": {
                                "relativePath": f"fixture/{item['segmentID']}.wav",
                                "file": {"path": "fixture", "bytes": 1, "sha256": "4" * 64},
                            },
                        },
                        "decoded": {
                            "sampleRate": 24000,
                            "sampleCount": 100,
                            "float32LESHA256": v5.native_float32_sha256(audio),
                        },
                        "audio": audio,
                        "receiptBinding": {
                            "path": "fixture",
                            "bytes": 1,
                            "sha256": "5" * 64,
                        },
                    }
                )
            with (
                mock.patch.object(
                    production,
                    "write_float_wav",
                    side_effect=OSError("synthetic staging failure"),
                ),
                self.assertRaises(OSError),
            ):
                v5.commit_v5_candidate(
                    output_root=output_root,
                    work_root=work_root,
                    candidate_id=candidate_id,
                    candidate=candidate,
                    parent_candidate={
                        "reference": {"sha256": "1" * 64, "bytes": 1},
                        "instructionSHA256": "2" * 64,
                    },
                    cues=cues,
                    cue_commits=cue_commits,
                    config=self.config,
                    parent_chain={"fixture": "parent"},
                    model_receipt={"fixture": "model"},
                )
            self.assertEqual(list(work_root.glob(".v5-candidate-stage-*")), [])

    def test_receipt_leaf_paths_are_exact_bound_and_not_redirectable(self) -> None:
        with tempfile.TemporaryDirectory(dir=NARRATION_ROOT / "work") as temporary:
            root = Path(temporary)
            safe = root / "safe.bin"
            safe.write_bytes(b"bound")
            expected = v5.file_binding(safe)
            self.assertEqual(
                v5._relative_bound_file(
                    root, "safe.bin", expected, exact_relative="safe.bin"
                ),
                safe,
            )
            self.assert_rejected(
                "receipt-absolute-path",
                lambda: v5._relative_bound_file(
                    root, str(safe), expected, exact_relative=str(safe)
                ),
            )
            outside = root.parent / "outside-v5.bin"
            self.assert_rejected(
                "receipt-parent-escape",
                lambda: v5._relative_bound_file(
                    root,
                    "../outside-v5.bin",
                    expected,
                    exact_relative="../outside-v5.bin",
                ),
            )
            forged = dict(expected, sha256="0" * 64)
            self.assert_rejected(
                "receipt-binding-forgery",
                lambda: v5._relative_bound_file(
                    root, "safe.bin", forged, exact_relative="safe.bin"
                ),
            )
            link = root / "linked.bin"
            link.symlink_to(safe)
            self.assert_rejected(
                "receipt-symlink-leaf",
                lambda: v5._relative_bound_file(
                    root, "linked.bin", expected, exact_relative="linked.bin"
                ),
            )

    def test_generation_result_retains_token_count_and_fails_at_ceiling(self) -> None:
        good = SimpleNamespace(
            audio=np.ones(12, dtype=np.float32),
            sample_rate=24000,
            samples=12,
            token_count=99,
            is_streaming_chunk=False,
        )
        _, _, record = v5.materialize_generation_result([good], max_tokens=100)
        self.assertEqual(record["tokenCount"], 99)
        self.assertFalse(record["tokenCeilingReached"])
        missing = SimpleNamespace(**{**good.__dict__, "token_count": None})
        self.assert_rejected(
            "generation-token-missing",
            lambda: v5.materialize_generation_result([missing], max_tokens=100),
        )
        boolean = SimpleNamespace(**{**good.__dict__, "token_count": True})
        self.assert_rejected(
            "generation-token-boolean",
            lambda: v5.materialize_generation_result([boolean], max_tokens=100),
        )
        exact = SimpleNamespace(**{**good.__dict__, "token_count": 100})
        self.assert_rejected(
            "generation-token-at-ceiling",
            lambda: v5.materialize_generation_result([exact], max_tokens=100),
        )
        over = SimpleNamespace(**{**good.__dict__, "token_count": 101})
        self.assert_rejected(
            "generation-token-over-ceiling",
            lambda: v5.materialize_generation_result([over], max_tokens=100),
        )
        streaming = SimpleNamespace(**{**good.__dict__, "is_streaming_chunk": True})
        self.assert_rejected(
            "generation-streaming-result",
            lambda: v5.materialize_generation_result([streaming], max_tokens=100),
        )
        self.assert_rejected(
            "generation-multiple-results",
            lambda: v5.materialize_generation_result([good, good], max_tokens=100),
        )
        mismatch = SimpleNamespace(**{**good.__dict__, "samples": 11})
        self.assert_rejected(
            "generation-sample-count-forgery",
            lambda: v5.materialize_generation_result([mismatch], max_tokens=100),
        )
        nonfinite = SimpleNamespace(
            **{**good.__dict__, "audio": np.array([np.nan], dtype=np.float32), "samples": 1}
        )
        self.assert_rejected(
            "generation-nonfinite-audio",
            lambda: v5.materialize_generation_result([nonfinite], max_tokens=100),
        )

    def test_v5_cue_synthesis_uses_pinned_seed_settings_and_retained_tokens(self) -> None:
        captured = {}

        class FakeCloneModel:
            def generate(self, **kwargs):
                captured.update(kwargs)
                yield SimpleNamespace(
                    audio=np.full(24, 0.1, dtype=np.float32),
                    sample_rate=24000,
                    samples=24,
                    token_count=99,
                    is_streaming_chunk=False,
                )

        with mock.patch.object(production, "set_generation_seed") as set_seed:
            audio, rate, record = v5.synthesize_v5_cue(
                FakeCloneModel(),
                text="Bound cue text.",
                reference_path=Path("reference.wav"),
                reference_text="Identity reference.",
                seed=731999,
                max_tokens=100,
                base_config=production.validate_config(),
            )
        set_seed.assert_called_once_with(731999)
        self.assertEqual(rate, 24000)
        self.assertEqual(audio.size, 24)
        self.assertEqual(record["tokenCount"], 99)
        self.assertEqual(captured["max_tokens"], 100)
        self.assertFalse(captured["stream"])
        self.assertEqual(captured["lang_code"], "English")

    def test_synthetic_generation_commits_resumes_and_validates_final_receipt(self) -> None:
        base_config = production.validate_config()
        model_files = copy.deepcopy(base_config["models"]["voiceClone"]["files"])
        work_root = NARRATION_ROOT / "work" / "provisional-audit-v5"
        work_root.mkdir(parents=True, exist_ok=True)
        synthesis_calls = 0

        def synthetic_cue(
            _model,
            *,
            text,
            reference_path,
            reference_text,
            seed,
            max_tokens,
            base_config,
        ):
            nonlocal synthesis_calls
            synthesis_calls += 1
            sample_count = 24000 + synthesis_calls * 24
            phase = np.arange(sample_count, dtype=np.float32)
            audio = np.asarray(
                0.05 * np.sin(2 * np.pi * (70 + synthesis_calls) * phase / 24000),
                dtype=np.float32,
            )
            token_count = 100 + synthesis_calls
            return audio, 24000, {
                "tokenCount": token_count,
                "maxTokens": max_tokens,
                "tokenCeilingReached": False,
                "sampleCount": sample_count,
                "sampleRate": 24000,
                "nonStreamingResultCount": 1,
                "peakAbsolute": float(np.max(np.abs(audio))),
            }

        with tempfile.TemporaryDirectory(
            dir=work_root, prefix="synthetic-v5-e2e-"
        ) as temporary:
            output = Path(temporary)
            arguments = argparse.Namespace(offline=True, output=output)
            with (
                mock.patch.object(
                    production,
                    "verify_model_snapshot",
                    return_value=(NARRATION_ROOT, model_files),
                ),
                mock.patch(
                    "mlx_audio.tts.utils.load_model", return_value=object()
                ),
                mock.patch.object(v5, "synthesize_v5_cue", side_effect=synthetic_cue),
                mock.patch.object(v5, "stress_duration_gate", return_value=True),
            ):
                first = v5.generate_v5(arguments, self.config)
                self.assertTrue(first["generationPerformedThisRun"])
                self.assertEqual(synthesis_calls, 12)
                validated = v5.validate_stress_set(
                    output, self.config, v5.validate_parent_chain(self.config)
                )
                self.assertEqual(
                    validated["receipt"]["rejectedV4DiagnosticEvidence"]
                    ["stressSetReceipt"]["sha256"],
                    self.config["v4DiagnosticEvidence"]["stressSetReceiptSHA256"],
                )
                self.assertNotIn(
                    self.config["v4DiagnosticEvidence"]["stressSetReceiptSHA256"],
                    v5.canonical_json(validated["receipt"]["parentChain"]),
                )
                second = v5.generate_v5(arguments, self.config)
                self.assertTrue(second["resumedExistingCompleteSet"])
                self.assertFalse(second["generationPerformedThisRun"])
                self.assertEqual(synthesis_calls, 12)
                self.assertEqual(
                    first["receipt"], second["receipt"]
                )

    def _write_native(self, path: Path, audio: np.ndarray, rate: int = 24000) -> None:
        wavfile.write(path, rate, np.asarray(audio, dtype=np.float32))

    def test_master_format_duration_and_native_relation_are_recomputed(self) -> None:
        with tempfile.TemporaryDirectory(dir=NARRATION_ROOT / "work") as temporary:
            root = Path(temporary)
            audit = root / "audit"
            audit.mkdir()
            native = root / "native.wav"
            signal = (0.2 * np.sin(np.linspace(0, 40, 12000))).astype(np.float32)
            self._write_native(native, signal)
            first = root / "first.wav"
            second = root / "second.wav"
            v5.render_deterministic_master(
                native, first, self.config, confinement_root=root
            )
            v5.render_deterministic_master(
                native, second, self.config, confinement_root=root
            )
            self.assertEqual(first.read_bytes(), second.read_bytes())
            _, decoded = v5.decode_master(first, self.config)
            self.assertEqual(decoded["sampleRate"], 48000)
            self.assertEqual(decoded["bitDepth"], 24)
            relation = v5.verify_native_master_relation(
                native,
                first,
                self.config,
                audit_root=audit,
                confinement_root=root,
            )
            self.assertTrue(relation["deterministicByteEquality"])
            self.assertEqual(relation["decodedDurationDifferenceSamples"], 0)

            wrong_native = root / "native-44100.wav"
            self._write_native(wrong_native, signal, rate=44100)
            self.assert_rejected(
                "native-resample",
                lambda: v5.read_native_audio(wrong_native, self.config),
            )
            wrong_master = root / "master-44100.wav"
            subprocess.run(
                [
                    self.config["master"]["ffmpegPath"],
                    "-nostdin",
                    "-y",
                    "-loglevel",
                    "error",
                    "-i",
                    str(native),
                    "-ar",
                    "44100",
                    "-ac",
                    "1",
                    "-c:a",
                    "pcm_s24le",
                    str(wrong_master),
                ],
                check=True,
            )
            self.assert_rejected(
                "master-resample",
                lambda: v5.decode_master(wrong_master, self.config),
            )
            alternate = root / "master-s16.wav"
            subprocess.run(
                [
                    self.config["master"]["ffmpegPath"],
                    "-nostdin",
                    "-y",
                    "-loglevel",
                    "error",
                    "-i",
                    str(native),
                    "-ar",
                    "48000",
                    "-ac",
                    "1",
                    "-c:a",
                    "pcm_s16le",
                    str(alternate),
                ],
                check=True,
            )
            self.assert_rejected(
                "master-alternate-format",
                lambda: v5.decode_master(alternate, self.config),
            )
            short_native = root / "short-native.wav"
            short_master = root / "short-master.wav"
            self._write_native(short_native, signal[:-1200])
            v5.render_deterministic_master(
                short_native, short_master, self.config, confinement_root=root
            )
            self.assert_rejected(
                "master-duration-truncation",
                lambda: v5.verify_native_master_relation(
                    native,
                    short_master,
                    self.config,
                    audit_root=audit,
                    confinement_root=root,
                ),
            )
            forged_native = root / "forged-native.wav"
            altered = signal.copy()
            altered[100] += np.float32(0.01)
            self._write_native(forged_native, altered)
            self.assert_rejected(
                "master-forged-native-relation",
                lambda: v5.verify_native_master_relation(
                    forged_native,
                    first,
                    self.config,
                    audit_root=audit,
                    confinement_root=root,
                ),
            )

    def test_candidate_duration_gate_uses_decoded_seconds_and_inclusive_edges(self) -> None:
        self.assertTrue(v5.stress_duration_gate(18 * 60, self.config))
        self.assertTrue(v5.stress_duration_gate(22 * 60, self.config))
        self.assert_rejected(
            "duration-under-18-minutes",
            lambda: (_ for _ in ()).throw(v5.V5Error("under duration"))
            if not v5.stress_duration_gate(18 * 60 - 1 / 48000, self.config)
            else None,
        )
        self.assert_rejected(
            "duration-over-22-minutes",
            lambda: (_ for _ in ()).throw(v5.V5Error("over duration"))
            if not v5.stress_duration_gate(22 * 60 + 1 / 48000, self.config)
            else None,
        )

    def test_identity_recomputes_whole_cues_and_every_20s_10s_window(self) -> None:
        rate = 24000
        reference = np.full(rate * 20, 0.1, dtype=np.float32)
        cues = [
            ("cue-01", np.full(rate * 40, 0.1, dtype=np.float32)),
            ("cue-02", np.full(rate * 40, 0.1, dtype=np.float32)),
        ]

        def extractor(audio: np.ndarray) -> np.ndarray:
            if float(np.mean(audio)) >= 0.6:
                return np.array([0.0, 1.0], dtype=np.float32)
            return np.array([1.0, 0.0], dtype=np.float32)

        result = v5.audit_voice_identity(
            reference_audio=reference,
            cue_audio=cues,
            sample_rate=rate,
            extractor=extractor,
            config=self.config,
        )
        self.assertTrue(result["passes"])
        self.assertEqual([len(item["windows"]) for item in result["cueRecords"]], [3, 3])
        forged_window = [(cue_id, audio.copy()) for cue_id, audio in cues]
        forged_window[1][1][: rate * 20] = 0.8
        window_result = v5.audit_voice_identity(
            reference_audio=reference,
            cue_audio=forged_window,
            sample_rate=rate,
            extractor=extractor,
            config=self.config,
        )
        self.assert_rejected(
            "voice-identity-window-forgery",
            lambda: (_ for _ in ()).throw(v5.V5Error("identity window"))
            if not window_result["passes"]
            else None,
        )
        forged_cue = [(cue_id, audio.copy()) for cue_id, audio in cues]
        forged_cue[1][1][:] = 0.8
        whole_result = v5.audit_voice_identity(
            reference_audio=reference,
            cue_audio=forged_cue,
            sample_rate=rate,
            extractor=extractor,
            config=self.config,
        )
        self.assert_rejected(
            "voice-identity-whole-cue-forgery",
            lambda: (_ for _ in ()).throw(v5.V5Error("identity whole cue"))
            if not whole_result["passes"]
            else None,
        )

    def _fake_whisper_document(self, model: str) -> dict:
        return {
            "params": {"model": model, "language": "en", "translate": False},
            "result": {"language": "en"},
            "transcription": [
                {
                    "tokens": [
                        {"text": " History", "offsets": {"from": 0, "to": 100}}
                    ]
                }
            ],
        }

    def test_whole_master_asr_is_pinned_in_process_and_confined(self) -> None:
        with tempfile.TemporaryDirectory(dir=NARRATION_ROOT / "work") as temporary:
            root = Path(temporary)
            transcripts = root / "transcripts"
            transcripts.mkdir()
            master = root / "master.wav"
            master.write_bytes(b"fixture")

            def runner(command, **kwargs):
                prefix = Path(command[command.index("--output-file") + 1])
                prefix.with_suffix(".json").write_text(
                    json.dumps(
                        self._fake_whisper_document(
                            self.config["offlineASR"]["modelPath"]
                        )
                    ),
                    encoding="utf-8",
                )
                return SimpleNamespace(stdout="", stderr="")

            transcript, receipt = v5.run_pinned_whisper(
                master_path=master,
                output_prefix=transcripts / "candidate",
                config=self.config,
                confinement_root=root,
                runner=runner,
            )
            self.assertTrue(transcript.is_file())
            self.assertFalse(receipt["externalReceiptUsed"])
            command = receipt["command"]
            self.assertEqual(
                command[3 : 3 + len(v5.EXPECTED_ASR_ARGUMENTS)],
                v5.EXPECTED_ASR_ARGUMENTS,
            )
            self.assertNotIn("--prompt", command)

            drifted = copy.deepcopy(self.config)
            drifted["offlineASR"]["arguments"] = ["--language", "fr"]
            self.assert_rejected(
                "asr-arguments-runtime-drift",
                lambda: v5.pinned_whisper_command(
                    master, transcripts / "drifted", drifted
                ),
            )
            external_prefix = transcripts / "external"
            external_prefix.with_suffix(".json").write_text("{}", encoding="utf-8")
            self.assert_rejected(
                "asr-external-transcript",
                lambda: v5.run_pinned_whisper(
                    master_path=master,
                    output_prefix=external_prefix,
                    config=self.config,
                    confinement_root=root,
                    runner=runner,
                ),
            )

            def forged_runner(command, **kwargs):
                prefix = Path(command[command.index("--output-file") + 1])
                prefix.with_suffix(".json").write_text(
                    json.dumps(self._fake_whisper_document("forged-model")),
                    encoding="utf-8",
                )
                return SimpleNamespace(stdout="", stderr="")

            self.assert_rejected(
                "asr-model-parameter-forgery",
                lambda: v5.run_pinned_whisper(
                    master_path=master,
                    output_prefix=transcripts / "forged",
                    config=self.config,
                    confinement_root=root,
                    runner=forged_runner,
                ),
            )
            self.assert_rejected(
                "asr-output-path-escape",
                lambda: v5.run_pinned_whisper(
                    master_path=master,
                    output_prefix=root.parent / "escaped-asr",
                    config=self.config,
                    confinement_root=root,
                    runner=runner,
                ),
            )

            outside = root / "outside.json"
            outside.write_text("{}", encoding="utf-8")

            def symlink_runner(command, **kwargs):
                prefix = Path(command[command.index("--output-file") + 1])
                prefix.with_suffix(".json").symlink_to(outside)
                return SimpleNamespace(stdout="", stderr="")

            self.assert_rejected(
                "asr-output-symlink",
                lambda: v5.run_pinned_whisper(
                    master_path=master,
                    output_prefix=transcripts / "linked",
                    config=self.config,
                    confinement_root=root,
                    runner=symlink_runner,
                ),
            )
            dangling_target = root / "dangling-target.json"
            dangling_leaf = transcripts / "dangling.json"
            dangling_leaf.symlink_to(dangling_target)
            runner_called = False

            def forbidden_runner(command, **kwargs):
                nonlocal runner_called
                runner_called = True
                Path(command[command.index("--output-file") + 1]).with_suffix(
                    ".json"
                ).write_text("{}", encoding="utf-8")
                return SimpleNamespace(stdout="", stderr="")

            self.assert_rejected(
                "asr-preexisting-dangling-symlink",
                lambda: v5.run_pinned_whisper(
                    master_path=master,
                    output_prefix=transcripts / "dangling",
                    config=self.config,
                    confinement_root=root,
                    runner=forbidden_runner,
                ),
            )
            self.assertFalse(runner_called)
            self.assertFalse(dangling_target.exists())

    def test_timed_word_grouping_is_monotone_bounded_and_bpe_aware(self) -> None:
        document = {
            "result": {"language": "en"},
            "transcription": [
                {
                    "tokens": [
                        {"text": " Far", "offsets": {"from": 0, "to": 0}},
                        {"text": "ming", "offsets": {"from": 0, "to": 180}},
                        {"text": " came", "offsets": {"from": 200, "to": 350}},
                        {"text": " A.D.", "offsets": {"from": 360, "to": 500}},
                    ]
                }
            ],
        }
        words, record = v5.timed_words_from_whisper(document, master_duration_ms=500)
        self.assertEqual([item.text for item in words], ["farming", "came", "ad"])
        self.assertTrue(record["monotone"])
        self.assertEqual(words[0].source_token_end_exclusive, 2)
        self.assertEqual(record["clippedSourceTokenCount"], 0)
        self.assertEqual(record["droppedSourceTokenCount"], 0)

        clipped_lexical = copy.deepcopy(document)
        clipped_lexical["transcription"][0]["tokens"][-1]["offsets"]["to"] = 620
        clipped_words, clipped_record = v5.timed_words_from_whisper(
            clipped_lexical, master_duration_ms=500
        )
        self.assertEqual(clipped_words[-1].end_ms, 500)
        self.assertEqual(clipped_record["clippedSourceTokenCount"], 1)
        self.assertEqual(clipped_record["clippedLexicalTokenCount"], 1)
        self.assertEqual(clipped_record["clippedNonLexicalTokenCount"], 0)
        self.assertEqual(clipped_record["maximumTimestampOverrunMilliseconds"], 120)
        self.assertEqual(clipped_record["droppedSourceTokenCount"], 0)

        decoder_tail = copy.deepcopy(document)
        decoder_tail["transcription"][0]["tokens"].extend(
            [
                {"text": " empire", "offsets": {"from": 510, "to": 570}},
                {"text": ".", "offsets": {"from": 570, "to": 610}},
                {"text": "[_TT_800]", "offsets": {"from": 620, "to": 620}},
            ]
        )
        tail_words, tail_record = v5.timed_words_from_whisper(
            decoder_tail, master_duration_ms=500
        )
        self.assertEqual([item.text for item in tail_words], ["farming", "came", "ad"])
        self.assertEqual(tail_words[-1].end_ms, 500)
        self.assertEqual(tail_record["clippedSourceTokenCount"], 0)
        self.assertEqual(tail_record["clippedLexicalTokenCount"], 0)
        self.assertEqual(tail_record["clippedNonLexicalTokenCount"], 0)
        self.assertEqual(tail_record["droppedSourceTokenCount"], 3)
        self.assertEqual(tail_record["droppedLexicalTokenCount"], 1)
        self.assertEqual(tail_record["droppedNonLexicalTokenCount"], 2)
        self.assertEqual(tail_record["maximumTimestampOverrunMilliseconds"], 120)

        nonmonotone = copy.deepcopy(document)
        nonmonotone["transcription"][0]["tokens"][2]["offsets"] = {
            "from": 100,
            "to": 150,
        }
        self.assert_rejected(
            "timed-word-nonmonotone",
            lambda: v5.timed_words_from_whisper(
                nonmonotone, master_duration_ms=500
            ),
        )
        overlap = copy.deepcopy(document)
        overlap["transcription"][0]["tokens"][-1]["offsets"] = {
            "from": 300,
            "to": 500,
        }
        self.assert_rejected(
            "timed-word-overlap",
            lambda: v5.timed_words_from_whisper(overlap, master_duration_ms=500),
        )
        boundary_overflow = copy.deepcopy(document)
        boundary_overflow["transcription"][0]["tokens"][-1]["offsets"] = {
            "from": 501,
            "to": 1001,
        }
        self.assert_rejected(
            "timed-word-boundary-overflow",
            lambda: v5.timed_words_from_whisper(
                boundary_overflow, master_duration_ms=500
            ),
        )
        out_of_bounds = copy.deepcopy(document)
        out_of_bounds["transcription"][0]["tokens"][-1]["offsets"]["to"] = 1001
        self.assert_rejected(
            "timed-word-out-of-bounds",
            lambda: v5.timed_words_from_whisper(
                out_of_bounds, master_duration_ms=500
            ),
        )
        empty = {
            "result": {"language": "en"},
            "transcription": [
                {
                    "tokens": [
                        {"text": "[_BEG_]", "offsets": {"from": 0, "to": 0}}
                    ]
                }
            ],
        }
        self.assert_rejected(
            "timed-word-empty-transcript",
            lambda: v5.timed_words_from_whisper(empty, master_duration_ms=500),
        )

    def test_hirschberg_alignment_is_global_monotone_and_minimal(self) -> None:
        reference = "one two three four five six seven eight nine ten".split()
        hypothesis = "one two extra three four five seven eight nine ten".split()
        steps, record = v5.monotone_global_alignment(reference, hypothesis)
        self.assertTrue(record["monotone"])
        self.assertTrue(record["complete"])
        self.assertEqual(
            record["editDistance"], v5._levenshtein_score_row(reference, hypothesis)[-1]
        )
        self.assertEqual(
            [step.reference_index for step in steps if step.reference_index is not None],
            list(range(len(reference))),
        )
        self.assertEqual(
            [step.hypothesis_index for step in steps if step.hypothesis_index is not None],
            list(range(len(hypothesis))),
        )

    def _alignment_fixture(self, hypothesis: list[str] | None = None, shift_ms: float = 0):
        reference = [f"word{index}" for index in range(100)]
        hypothesis = hypothesis or list(reference)
        duration_ms = 10000.0
        timed = [
            v5.TimedWord(
                text=word,
                start_ms=shift_ms + duration_ms * index / len(hypothesis),
                end_ms=shift_ms + duration_ms * (index + 1) / len(hypothesis),
                source_token_start=index,
                source_token_end_exclusive=index + 1,
            )
            for index, word in enumerate(hypothesis)
        ]
        cue = {
            "segmentID": "cue-01",
            "wordCount": 100,
            "normalizedReferenceStart": 0,
            "normalizedReferenceEndExclusive": 100,
            "firstAnchor": reference[:8],
            "lastAnchor": reference[-8:],
        }
        sample_ranges = [
            {
                "segmentID": "cue-01",
                "startSampleInclusive": 0,
                "endSampleExclusive": 240000,
            }
        ]
        steps, _ = v5.monotone_global_alignment(reference, [item.text for item in timed])
        result = v5.project_alignment_to_cues(
            reference_words=reference,
            hypothesis_words=timed,
            steps=steps,
            cues=[cue],
            cue_sample_ranges=sample_ranges,
            sample_rate=24000,
            config=self.config,
        )
        return reference, result

    def test_cue_projection_enforces_anchors_coverage_runs_and_boundaries(self) -> None:
        reference, perfect = self._alignment_fixture()
        self.assertTrue(perfect["allCuesPass"])
        self.assertEqual(perfect["cueRecords"][0]["exactReferenceCoverage"], 1.0)

        truncated = reference[:-8]
        _, result = self._alignment_fixture(truncated)
        self.assert_rejected(
            "alignment-truncation",
            lambda: (_ for _ in ()).throw(v5.V5Error("truncated"))
            if not result["allCuesPass"]
            else None,
        )
        changed = list(reference)
        changed[40:43] = ["wrong40", "wrong41", "wrong42"]
        _, result = self._alignment_fixture(changed)
        self.assertFalse(
            result["cueRecords"][0]["gates"]["minimumExactReferenceCoverage"]
        )
        self.assert_rejected(
            "alignment-coverage-loss",
            lambda: (_ for _ in ()).throw(v5.V5Error("coverage"))
            if not result["allCuesPass"]
            else None,
        )
        changed = list(reference)
        changed[40:47] = [f"bad{index}" for index in range(7)]
        _, result = self._alignment_fixture(changed)
        self.assertFalse(
            result["cueRecords"][0]["gates"]["maximumNonmatchingReferenceRun"]
        )
        self.assert_rejected(
            "alignment-reference-run",
            lambda: (_ for _ in ()).throw(v5.V5Error("reference run"))
            if not result["allCuesPass"]
            else None,
        )
        inserted = reference[:50] + [f"loop{index}" for index in range(13)] + reference[50:]
        _, result = self._alignment_fixture(inserted)
        self.assertFalse(
            result["cueRecords"][0]["gates"]["maximumNonmatchingHypothesisRun"]
        )
        self.assert_rejected(
            "alignment-hypothesis-run",
            lambda: (_ for _ in ()).throw(v5.V5Error("hypothesis run"))
            if not result["allCuesPass"]
            else None,
        )
        _, shifted = self._alignment_fixture(reference, shift_ms=800)
        self.assert_rejected(
            "alignment-boundary-shift",
            lambda: (_ for _ in ()).throw(v5.V5Error("boundary shift"))
            if not shifted["allCuesPass"]
            else None,
        )
        ambiguous = reference[:50] + reference[:8] + reference[50:]
        _, result = self._alignment_fixture(ambiguous)
        self.assertFalse(result["cueRecords"][0]["gates"]["firstAnchorUnique"])
        self.assert_rejected(
            "alignment-anchor-ambiguity",
            lambda: (_ for _ in ()).throw(v5.V5Error("ambiguous"))
            if not result["allCuesPass"]
            else None,
        )

    def test_alignment_threshold_edges_are_inclusive(self) -> None:
        reference = [f"word{index}" for index in range(100)]
        exact_98 = list(reference)
        exact_98[40] = "changed40"
        exact_98[60] = "changed60"
        _, result = self._alignment_fixture(exact_98)
        cue = result["cueRecords"][0]
        self.assertEqual(cue["exactReferenceCoverage"], 0.98)
        self.assertTrue(cue["gates"]["minimumExactReferenceCoverage"])
        inserted_12 = reference[:50] + [f"insert{index}" for index in range(12)] + reference[50:]
        _, result = self._alignment_fixture(inserted_12)
        cue = result["cueRecords"][0]
        self.assertEqual(cue["maximumNonmatchingHypothesisRunWords"], 12)
        self.assertTrue(cue["gates"]["maximumNonmatchingHypothesisRun"])
        six_changed = list(reference)
        six_changed[40:46] = [f"changed{index}" for index in range(6)]
        _, result = self._alignment_fixture(six_changed)
        cue = result["cueRecords"][0]
        self.assertEqual(cue["maximumNonmatchingReferenceRunWords"], 6)
        self.assertTrue(cue["gates"]["maximumNonmatchingReferenceRun"])
        _, result = self._alignment_fixture(reference, shift_ms=750)
        cue = result["cueRecords"][0]
        self.assertTrue(cue["gates"]["startBoundaryTolerance"])
        self.assertTrue(cue["gates"]["endBoundaryTolerance"])

    def test_alignment_partitions_every_hypothesis_word_across_cue_boundaries(self) -> None:
        reference = [f"word{index}" for index in range(100)]
        boundary_loop = [f"boundaryjunk{index}" for index in range(13)]
        hypothesis = reference[:50] + boundary_loop + reference[50:]
        timed = [
            v5.TimedWord(
                text=word,
                start_ms=10000 * index / len(hypothesis),
                end_ms=10000 * (index + 1) / len(hypothesis),
                source_token_start=index,
                source_token_end_exclusive=index + 1,
            )
            for index, word in enumerate(hypothesis)
        ]
        cues = [
            {
                "segmentID": "cue-01",
                "wordCount": 50,
                "normalizedReferenceStart": 0,
                "normalizedReferenceEndExclusive": 50,
                "firstAnchor": reference[:8],
                "lastAnchor": reference[42:50],
            },
            {
                "segmentID": "cue-02",
                "wordCount": 50,
                "normalizedReferenceStart": 50,
                "normalizedReferenceEndExclusive": 100,
                "firstAnchor": reference[50:58],
                "lastAnchor": reference[-8:],
            },
        ]
        ranges = [
            {
                "segmentID": "cue-01",
                "startSampleInclusive": 0,
                "endSampleExclusive": 120000,
            },
            {
                "segmentID": "cue-02",
                "startSampleInclusive": 120000,
                "endSampleExclusive": 240000,
            },
        ]
        steps, _ = v5.monotone_global_alignment(reference, hypothesis)
        result = v5.project_alignment_to_cues(
            reference_words=reference,
            hypothesis_words=timed,
            steps=steps,
            cues=cues,
            cue_sample_ranges=ranges,
            sample_rate=24000,
            config=self.config,
        )
        self.assertEqual(
            result["cueRecords"][0]["maximumNonmatchingHypothesisRunWords"], 13
        )
        self.assert_rejected(
            "alignment-boundary-insertion-run",
            lambda: (_ for _ in ()).throw(v5.V5Error("boundary insertion run"))
            if not result["allCuesPass"]
            else None,
        )

        distributed = []
        for index, word in enumerate(reference):
            distributed.append(word)
            if index % 10 == 9:
                distributed.append(f"distributed{index}")
        _, distributed_result = self._alignment_fixture(distributed)
        cue = distributed_result["cueRecords"][0]
        self.assertTrue(cue["gates"]["maximumNonmatchingHypothesisRun"])
        self.assertFalse(cue["gates"]["minimumExactHypothesisCoverage"])
        self.assert_rejected(
            "alignment-distributed-insertions",
            lambda: (_ for _ in ()).throw(v5.V5Error("distributed insertions"))
            if not distributed_result["allCuesPass"]
            else None,
        )

    def test_repetition_subtracts_reference_multiset_and_rejects_excess(self) -> None:
        phrase = "one two three four five six seven eight nine ten".split()
        reference = phrase + phrase
        legitimate = v5.reference_aware_repetition(reference, reference, self.config)
        self.assertTrue(legitimate["passes"])
        self.assertEqual(legitimate["excessOccurrenceCount"], 0)
        looped = v5.reference_aware_repetition(reference, phrase * 4, self.config)
        self.assert_rejected(
            "repetition-excess-loop",
            lambda: (_ for _ in ()).throw(v5.V5Error("repetition"))
            if not looped["passes"]
            else None,
        )

    def test_repetition_threshold_is_inclusive_and_requires_two_occurrences(self) -> None:
        reference = [f"token{index}" for index in range(205)]
        phrase = [f"phrase{index}" for index in range(6)]
        reference[10:16] = phrase
        hypothesis = list(reference)
        hypothesis[100:106] = phrase
        edge = v5.reference_aware_repetition(reference, hypothesis, self.config)
        self.assertEqual(edge["excessOccurrenceCount"], 1)
        self.assertEqual(edge["hypothesisNgramCount"], 200)
        self.assertEqual(edge["excessOccurrenceFraction"], 0.005)
        self.assertTrue(edge["passes"])
        single_novel = list(reference)
        single_novel[100:106] = [f"novel{index}" for index in range(6)]
        result = v5.reference_aware_repetition(reference, single_novel, self.config)
        self.assertEqual(result["excessOccurrenceCount"], 0)

    def test_cue_tempo_gate_rejects_a_local_outlier(self) -> None:
        cues = [
            {"segmentID": f"cue-{index:02d}", "wordCount": 150}
            for index in range(1, 7)
        ]
        ranges = []
        cursor = 0
        for index in range(6):
            duration = 24000 * (120 if index == 5 else 60)
            ranges.append(
                {
                    "segmentID": f"cue-{index + 1:02d}",
                    "startSampleInclusive": cursor,
                    "endSampleExclusive": cursor + duration,
                }
            )
            cursor += duration
        result = v5.cue_tempo_audit(cues, ranges, 24000, self.config)
        self.assertFalse(result["cueRecords"][-1]["passes"])
        self.assert_rejected(
            "tempo-cue-outlier",
            lambda: (_ for _ in ()).throw(v5.V5Error("tempo"))
            if not result["passes"]
            else None,
        )

    def test_silence_gate_covers_total_cue_edges_and_boundaries(self) -> None:
        rate = 1000
        time = np.arange(20000) / rate
        active = (0.1 * np.sin(2 * np.pi * 40 * time)).astype(np.float32)
        ranges = [
            {
                "segmentID": "cue-01",
                "startSampleInclusive": 0,
                "endSampleExclusive": 10000,
            },
            {
                "segmentID": "cue-02",
                "startSampleInclusive": 10000,
                "endSampleExclusive": 20000,
            },
        ]
        self.assertTrue(
            v5.silence_audit(
                active,
                sample_rate=rate,
                cue_sample_ranges=ranges,
                config=self.config,
            )["passes"]
        )
        boundary = active.copy()
        boundary[9000:11000] = 0
        result = v5.silence_audit(
            boundary,
            sample_rate=rate,
            cue_sample_ranges=ranges,
            config=self.config,
        )
        self.assert_rejected(
            "silence-boundary",
            lambda: (_ for _ in ()).throw(v5.V5Error("boundary silence"))
            if not result["gates"]["allCueBoundaries"]
            else None,
        )
        one_sided = active.copy()
        one_sided[8000:10000] = 0
        result = v5.silence_audit(
            one_sided,
            sample_rate=rate,
            cue_sample_ranges=ranges,
            config=self.config,
        )
        self.assertGreater(
            result["cueRecords"][0]["trailingSilenceMilliseconds"], 1900
        )
        self.assert_rejected(
            "silence-boundary-one-sided",
            lambda: (_ for _ in ()).throw(v5.V5Error("one-sided boundary silence"))
            if not result["gates"]["allCueBoundaries"]
            else None,
        )
        after_boundary = active.copy()
        after_boundary[10000:12000] = 0
        result = v5.silence_audit(
            after_boundary,
            sample_rate=rate,
            cue_sample_ranges=ranges,
            config=self.config,
        )
        self.assertGreater(
            result["cueRecords"][1]["leadingSilenceMilliseconds"], 1900
        )
        self.assertEqual(
            result["boundaryRecords"][0]["leftTrailingSilenceMilliseconds"],
            0.0,
        )
        self.assertGreater(
            result["boundaryRecords"][0]["rightLeadingSilenceMilliseconds"],
            1900,
        )
        self.assert_rejected(
            "silence-boundary-after",
            lambda: (_ for _ in ()).throw(v5.V5Error("after-boundary silence"))
            if not result["gates"]["allCueBoundaries"]
            else None,
        )
        total = active.copy()
        total[2000:6000] = 0
        result = v5.silence_audit(
            total,
            sample_rate=rate,
            cue_sample_ranges=ranges,
            config=self.config,
        )
        self.assert_rejected(
            "silence-total-fraction",
            lambda: (_ for _ in ()).throw(v5.V5Error("total silence"))
            if not result["gates"]["totalSilence"]
            else None,
        )
        edge = active.copy()
        edge[:1000] = 0
        result = v5.silence_audit(
            edge,
            sample_rate=rate,
            cue_sample_ranges=ranges,
            config=self.config,
        )
        self.assert_rejected(
            "silence-cue-edge",
            lambda: (_ for _ in ()).throw(v5.V5Error("cue edge"))
            if not result["gates"]["allCueEdges"]
            else None,
        )

    def test_offline_is_mandatory_for_validation_and_audit(self) -> None:
        self.assert_rejected(
            "validate-without-offline",
            lambda: v5.validate_only(self.config, deep_v4=False, offline=False),
        )
        args = argparse.Namespace(offline=False, output=Path("x"), stress_set=Path("y"))
        self.assert_rejected(
            "audit-without-offline", lambda: v5.audit_v5(args, self.config)
        )
        generation_args = argparse.Namespace(offline=False, output=Path("x"))
        self.assert_rejected(
            "generate-without-offline",
            lambda: v5.generate_v5(generation_args, self.config),
        )


if __name__ == "__main__":
    unittest.main()
