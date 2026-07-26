from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "pipeline.py"
SPEC = importlib.util.spec_from_file_location("narration_pipeline", MODULE_PATH)
pipeline = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(pipeline)


class NarrationPipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = pipeline.validate_config()

    def _candidate_set(self, root: Path, binding: dict) -> dict:
        records = []
        for candidate in self.config["candidates"]:
            candidate_id = candidate["id"]
            reference_path = root / "references" / f"{candidate_id}-reference.wav"
            casting_path = root / "candidates" / f"{candidate_id}.wav"
            reference_path.parent.mkdir(parents=True, exist_ok=True)
            casting_path.parent.mkdir(parents=True, exist_ok=True)
            reference_path.write_bytes(f"reference:{candidate_id}".encode())
            casting_path.write_bytes(f"casting:{candidate_id}".encode())
            records.append(
                {
                    "candidateID": candidate_id,
                    "instructionSHA256": pipeline.sha256_text(
                        candidate["instruction"]
                    ),
                    "referenceSeed": candidate["referenceSeed"],
                    "castingSeed": candidate["castingSeed"],
                    "reference": {
                        "path": str(reference_path),
                        "sha256": pipeline.sha256_file(reference_path),
                        "bytes": reference_path.stat().st_size,
                    },
                    "casting": {
                        "path": str(casting_path),
                        "sha256": pipeline.sha256_file(casting_path),
                        "bytes": casting_path.stat().st_size,
                    },
                }
            )
        contract = pipeline.candidate_contract(self.config)
        receipt = {
            "schemaVersion": 2,
            "status": "AWAITING_EDITOR_SELECTION_AND_ARTISTIC_AUDIT",
            "language": self.config["language"],
            "locale": self.config["locale"],
            "identityTextSHA256": self.config["texts"]["identityReference"][
                "textSHA256"
            ],
            "castingTextSHA256": self.config["texts"]["casting"]["textSHA256"],
            "castingWordCount": self.config["texts"]["casting"]["wordCount"],
            "completeCandidateSet": True,
            "candidateCount": 6,
            "candidateIDs": pipeline.EXPECTED_CANDIDATE_IDS,
            "candidateContract": contract,
            "candidateContractSHA256": pipeline.sha256_json(contract),
            "pipelineBinding": binding,
            "models": {
                label: pipeline.model_receipt(record, record["files"])
                for label, record in self.config["models"].items()
            },
            "generation": self.config["generation"],
            "masterFormat": self.config["masterFormat"],
            "candidateRecords": records,
        }
        pipeline.write_receipt(root / "candidate-set.receipt.json", receipt)
        return receipt

    def _selection_record(
        self,
        path: Path,
        candidate_set: dict,
        selected: list[str] | None = None,
    ) -> dict:
        record = {
            "schemaVersion": 1,
            "status": pipeline.EDITOR_SELECTION_STATUS,
            "decisionType": "NARRATION_STRESS_FINALISTS",
            "approvedBy": "editor-in-chief",
            "decidedAt": "2026-07-24T12:00:00+02:00",
            "decisionReference": "test-only editor decision fixture",
            "candidateSetReceiptSHA256": candidate_set["receiptSHA256"],
            "candidateSetReceiptBytes": candidate_set["receiptBytes"],
            "selectedCandidateIDs": selected
            or ["voice-candidate-01", "voice-candidate-03"],
        }
        pipeline.write_receipt(path, record)
        return record

    def test_production_cast_is_exactly_six_anonymous_candidates(self) -> None:
        cast_plan = pipeline.plan(self.config, "cast")
        self.assertEqual(cast_plan["candidateIDs"], pipeline.EXPECTED_CANDIDATE_IDS)
        self.assertEqual(len(self.config["candidates"]), 6)
        self.assertEqual(
            cast_plan["sharedCastingTextSHA256"],
            "c473b155b4cd1696c867fae63a036f32026b9abd02228659716d2267e96114df",
        )
        self.assertEqual(
            cast_plan["synthesisTextSHA256"],
            "360dd0992dec5e8223d3416ff161e58767d8e9f57c91c2e19b52cff4b0edc3a7",
        )
        self.assertEqual(cast_plan["sharedCastingWordCount"], 829)
        self.assertEqual(self.config["generation"]["maxTokens"], 8192)
        self.assertTrue(cast_plan["selfGeneratedReferenceOnly"])

    def test_run_cast_rejects_anything_except_complete_six(self) -> None:
        incomplete = copy.deepcopy(self.config)
        incomplete["candidates"] = incomplete["candidates"][:-1]
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            pipeline, "verify_runtime", return_value={"fixture": True}
        ):
            args = SimpleNamespace(output=Path(temporary) / "cast", offline=True)
            with self.assertRaisesRegex(
                pipeline.PipelineError, "exact complete six-candidate set"
            ):
                pipeline.run_cast(args, incomplete)

    def test_casting_passage_is_exact_approved_prose_with_name_coverage(self) -> None:
        identity = self.config["texts"]["identityReference"]
        identity_text = pipeline.canonical_text(pipeline.HERE / identity["path"])
        identity_source = (
            pipeline.REPOSITORY_ROOT / identity["source"]
        ).read_text(encoding="utf-8")
        self.assertIn(identity_text, identity_source)
        self.assertEqual(
            pipeline.sha256_text(identity_text), identity["sourceSegmentSHA256"]
        )

        casting = self.config["texts"]["casting"]
        segments = pipeline.canonical_text(
            pipeline.HERE / casting["path"]
        ).split("\n\n")
        for segment, source in zip(segments, casting["sourceSegments"], strict=True):
            source_text = (
                pipeline.REPOSITORY_ROOT / source["source"]
            ).read_text(encoding="utf-8")
            self.assertIn(segment, source_text)
            self.assertEqual(pipeline.sha256_text(segment), source["sha256"])

        self.assertEqual(
            [item["tradition"] for item in casting["nameCoverage"]],
            ["Greek", "Latin", "Germanic", "Slavic"],
        )
        for coverage in casting["nameCoverage"]:
            covered = "\n\n".join(
                segments[index - 1] for index in coverage["segmentIndexes"]
            )
            self.assertGreaterEqual(len(coverage["requiredTerms"]), 4)
            for term in coverage["requiredTerms"]:
                self.assertIn(term, covered)

    def test_weight_lineage_is_exact_and_commercially_permissive(self) -> None:
        expected = {
            "voiceDesign": (
                "7d3824abff87e49756bb0f83fb5411de75d160c4",
                "96ae28bec2205ec0b5e0c750bea2b8a5deac4f14d33a8a25a5f753299486b70e",
            ),
            "voiceClone": (
                "a6eb4f68e4b056f1215157bb696209bc82a6db48",
                "81fb76175ff74e69be25fef2cc3e54f016df3034f1514c8e1c89da06a3510cff",
            ),
        }
        for label, (revision, weight_hash) in expected.items():
            model = self.config["models"][label]
            self.assertEqual(model["revision"], revision)
            self.assertEqual(model["license"], "Apache-2.0")
            self.assertEqual(model["controlFileCount"], 12)
            self.assertRegex(model["controlManifestSHA256"], r"^[0-9a-f]{64}$")
            self.assertEqual(model["files"][0]["sha256"], weight_hash)
            self.assertEqual(
                model["files"][1]["sha256"],
                "836b7b357f5ea43e889936a3709af68dfe3751881acefe4ecf0dbd30ba571258",
            )

    def test_stress_contract_is_one_uninterrupted_twenty_minute_generation(self) -> None:
        paragraph = " ".join(["word"] * 290)
        text = "\n\n".join([paragraph] * 10)
        result = pipeline.validate_stress_text(text, self.config)
        self.assertEqual(result["wordCount"], 2900)
        self.assertEqual(result["estimatedMinutes"], 20.0)
        self.assertTrue(result["singleGenerationRequired"])
        self.assertEqual(result["maxTokens"], 20000)
        self.assertNotIn("takes", result)
        pipeline.require_stress_duration(18 * 60, self.config)
        pipeline.require_stress_duration(22 * 60, self.config)
        with self.assertRaisesRegex(pipeline.PipelineError, "18–22"):
            pipeline.require_stress_duration((18 * 60) - 0.001, self.config)

    def test_non_streaming_generation_rejects_split_or_silent_results(self) -> None:
        import numpy as np

        one = SimpleNamespace(audio=np.ones(24, dtype=np.float32), sample_rate=24)
        audio, sample_rate = pipeline.one_generation_audio([one])
        self.assertEqual(sample_rate, 24)
        self.assertEqual(audio.size, 24)
        with self.assertRaisesRegex(pipeline.PipelineError, "one non-streaming result"):
            pipeline.one_generation_audio([one, one])
        silent = SimpleNamespace(audio=np.zeros(24, dtype=np.float32), sample_rate=24)
        with self.assertRaisesRegex(pipeline.PipelineError, "silence"):
            pipeline.one_generation_audio([silent])

    def test_short_text_cannot_be_labelled_a_stress_test(self) -> None:
        with self.assertRaisesRegex(pipeline.PipelineError, "required range"):
            pipeline.validate_stress_text("This is too short.", self.config)

    def test_candidate_set_requires_all_six_bound_audio_records(self) -> None:
        binding = {"schemaVersion": 1, "fixture": "pipeline-binding"}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = self._candidate_set(root, binding)
            verified = pipeline.validate_candidate_set(root, self.config, binding)
            self.assertEqual(
                list(verified["recordsByID"]), pipeline.EXPECTED_CANDIDATE_IDS
            )

            receipt["candidateRecords"] = receipt["candidateRecords"][:-1]
            pipeline.write_receipt(root / "candidate-set.receipt.json", receipt)
            with self.assertRaisesRegex(
                pipeline.PipelineError, "complete six-candidate set|frozen pipeline"
            ):
                pipeline.validate_candidate_set(root, self.config, binding)

    def test_editor_selection_is_byte_bound_and_exactly_two_finalists(self) -> None:
        binding = {"schemaVersion": 1, "fixture": "pipeline-binding"}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cast_root = root / "cast"
            cast_root.mkdir()
            self._candidate_set(cast_root, binding)
            candidate_set = pipeline.validate_candidate_set(
                cast_root, self.config, binding
            )
            selection_root = root / "editor-selections"
            selection_root.mkdir()
            selection_path = selection_root / "stress-finalists.json"
            self._selection_record(selection_path, candidate_set)
            with mock.patch.object(
                pipeline, "EDITOR_SELECTION_ROOT", selection_root
            ):
                selection = pipeline.validate_editor_selection_record(
                    selection_path, candidate_set
                )
                self.assertEqual(
                    selection["selectedCandidateIDs"],
                    ["voice-candidate-01", "voice-candidate-03"],
                )
                self.assertEqual(selection["sha256"], pipeline.sha256_file(selection_path))
                self.assertEqual(selection["bytes"], selection_path.stat().st_size)

                self._selection_record(
                    selection_path, candidate_set, ["voice-candidate-01"]
                )
                with self.assertRaisesRegex(
                    pipeline.PipelineError, "exactly two candidates"
                ):
                    pipeline.validate_editor_selection_record(
                        selection_path, candidate_set
                    )

                invalid = self._selection_record(selection_path, candidate_set)
                invalid["candidateSetReceiptBytes"] += 1
                pipeline.write_receipt(selection_path, invalid)
                with self.assertRaisesRegex(
                    pipeline.PipelineError, "does not bind this candidate set"
                ):
                    pipeline.validate_editor_selection_record(
                        selection_path, candidate_set
                    )

    def test_receipt_binding_covers_pipeline_config_lock_and_ffmpeg_binary(self) -> None:
        runtime = {
            "pythonVersion": self.config["toolchain"]["pythonVersion"],
            "mlxAudioVersion": self.config["toolchain"]["mlxAudioVersion"],
            "uv": {
                "bytes": 1,
                "sha256": "1" * 64,
                "versionFirstLine": "uv 0.11.22",
            },
            "ffmpeg": {
                "bytes": 2,
                "sha256": "2" * 64,
                "versionFirstLine": "ffmpeg version 8.1.2",
            },
            "ffprobe": {
                "bytes": 3,
                "sha256": "3" * 64,
                "versionFirstLine": "ffprobe version 8.1.2",
            },
        }
        binding = pipeline.pipeline_binding(self.config, runtime)
        self.assertEqual(binding["pipelinePy"], pipeline.file_binding(pipeline.PIPELINE_PATH))
        self.assertEqual(
            binding["pipelineConfig"], pipeline.file_binding(pipeline.DEFAULT_CONFIG)
        )
        self.assertEqual(binding["uvLock"], pipeline.file_binding(pipeline.UV_LOCK_PATH))
        self.assertEqual(binding["runtime"]["ffmpeg"], runtime["ffmpeg"])
        contract = pipeline.candidate_contract(self.config)
        self.assertEqual(
            contract[0]["instructionSHA256"],
            pipeline.sha256_text(self.config["candidates"][0]["instruction"]),
        )

    def test_offline_preflight_contract_does_not_synthesize(self) -> None:
        runtime = {
            "pythonVersion": "fixture",
            "mlxAudioVersion": "fixture",
            "uv": {},
            "ffmpeg": {},
            "ffprobe": {},
        }

        def verified_snapshot(record: dict, *, offline: bool):
            self.assertTrue(offline)
            return Path("/fixture/cache"), record["files"]

        with mock.patch.object(
            pipeline, "verify_runtime", return_value=runtime
        ), mock.patch.object(
            pipeline, "verify_model_snapshot", side_effect=verified_snapshot
        ):
            receipt = pipeline.run_preflight(self.config, offline=True)
        self.assertEqual(receipt["status"], "PREFLIGHT_VALID_NO_SYNTHESIS")
        self.assertTrue(receipt["offline"])
        self.assertEqual(receipt["candidateCount"], 6)
        self.assertEqual(
            receipt["candidateContractSHA256"],
            pipeline.sha256_json(pipeline.candidate_contract(self.config)),
        )
        self.assertIn("candidate generation", receipt["claimsExcluded"])

    def test_output_root_must_be_new_or_empty(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "result"
            self.assertEqual(pipeline.prepare_output_root(root), root.resolve())
            (root / "occupied").write_text("x", encoding="utf-8")
            with self.assertRaisesRegex(pipeline.PipelineError, "absent or empty"):
                pipeline.prepare_output_root(root)

    def test_artistic_and_editor_gates_remain_open(self) -> None:
        registry = json.loads(pipeline.REGISTRY_PATH.read_text(encoding="utf-8"))
        unresolved = {item["id"] for item in registry["unresolvedCapabilities"]}
        self.assertIn("final-narration-synthesis", unresolved)
        self.assertEqual(
            self.config["status"], "NON_SHIPPING_UNTIL_EDITOR_VOICE_SELECTION"
        )
        self.assertEqual(pipeline.EDITOR_SELECTION_STATUS, "APPROVED_BY_EDITOR_IN_CHIEF")

    def test_technical_probe_receipt_matches_preserved_audio_without_artistic_claim(self) -> None:
        probe_root = (pipeline.HERE / "probes" / "technical-2026-07-24").resolve()
        receipt = json.loads(
            (probe_root / "technical-probe.receipt.json").read_text(encoding="utf-8")
        )
        reproduction = json.loads(
            (probe_root / "offline-reproducibility.receipt.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            receipt["status"], "TECHNICAL_ONLY_NOT_ARTISTICALLY_APPROVED"
        )
        for label, file_name in [
            ("reference", "technical-reference.wav"),
            ("clone", "technical-clone.wav"),
        ]:
            file_hash = pipeline.sha256_file(probe_root / file_name)
            self.assertEqual(file_hash, receipt[label]["sha256"])
            self.assertEqual(file_hash, reproduction[label]["firstRunSHA256"])
            self.assertEqual(file_hash, reproduction[label]["secondRunSHA256"])
            self.assertTrue(reproduction[label]["byteIdentical"])
            self.assertEqual(receipt[label]["sampleRate"], 48000)
            self.assertEqual(receipt[label]["bitDepth"], 24)
            self.assertEqual(receipt[label]["channels"], 1)
        self.assertIn("artistic approval", receipt["claimsExcluded"])


if __name__ == "__main__":
    unittest.main()
