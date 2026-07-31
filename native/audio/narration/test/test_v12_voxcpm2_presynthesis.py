from __future__ import annotations

import ast
import json
from pathlib import Path
import sys
import tempfile
import unittest

NARRATION_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NARRATION_ROOT))

import v12_voxcpm2_presynthesis as v12


class V12VoxCPM2PresynthesisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.lock = v12._load_lock()

    def test_lock_creates_a_distinct_non_authorising_trust_domain(self) -> None:
        self.assertEqual(
            self.lock["trustDomain"], "CODEX_V12_VOXCPM2_PRE_SYNTHESIS_ONLY"
        )
        self.assertNotIn("provisional-audit-v11", str(v12.RUNTIME_ROOT))
        self.assertFalse(
            v12.NUMBA_CACHE_ROOT.absolute().is_relative_to(v12.RUNTIME_ROOT.absolute())
        )

    def test_local_different_method_inventory_is_exactly_empty(self) -> None:
        document = v12.local_method_inventory(self.lock)
        self.assertEqual(document["status"], v12.INVENTORY_STATUS)
        self.assertEqual(document["eligibleDifferentLocalMethods"], [])
        self.assertIsNone(document["selectedMethod"])
        self.assertFalse(document["synthesisPermitted"])
        self.assertFalse(document["scope"]["synthesisExecuted"])

    def test_legacy_numba_inventory_binds_all_46_files(self) -> None:
        document = v12.legacy_numba_cache_inventory(self.lock)
        self.assertEqual(document["status"], v12.LEGACY_CACHE_STATUS)
        self.assertEqual(document["cacheFileCount"], 46)
        self.assertEqual(len(document["cacheFiles"]), 46)
        self.assertTrue(
            all(Path(item["path"]).suffix in {".nbc", ".nbi"} for item in document["cacheFiles"])
        )
        self.assertTrue(all(len(item["sha256"]) == 64 for item in document["cacheFiles"]))
        self.assertEqual(document["runtimeVersions"]["python"], "3.11.15")
        self.assertEqual(
            document["runtimeVersions"]["packages"]["numba"]["version"], "0.66.0"
        )

    def test_tree_manifest_detects_one_byte_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "bound.bin"
            path.write_bytes(b"alpha")
            before = v12._tree_manifest(root)
            path.write_bytes(b"alphb")
            after = v12._tree_manifest(root)
            self.assertNotEqual(before["inventorySHA256"], after["inventorySHA256"])

    def test_worker_source_has_no_generation_call_expression(self) -> None:
        tree = ast.parse(v12.SCRIPT_PATH.read_text(encoding="utf-8"))
        worker = next(
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "_worker"
        )
        calls = [node for node in ast.walk(worker) if isinstance(node, ast.Call)]
        attributes = [
            node.func.attr
            for node in calls
            if isinstance(node.func, ast.Attribute)
        ]
        self.assertIn("build_prompt_cache", attributes)
        self.assertNotIn("generate", attributes)
        self.assertNotIn("generate_streaming", attributes)
        self.assertNotIn("generate_with_prompt_cache", attributes)

    def test_final_validator_requires_a_closed_synthesis_boundary(self) -> None:
        source = v12.SCRIPT_PATH.read_text(encoding="utf-8")
        self.assertIn('"synthesisPermitted": False', source)
        self.assertIn('"requiresEditorDecision": True', source)
        self.assertIn('"v11IsTerminal": True', source)
        self.assertIn('"v11TerminalAuthorityOpened": False', source)

    def test_lock_json_contains_no_synthesis_authority(self) -> None:
        document = json.loads(v12.LOCK_PATH.read_text(encoding="utf-8"))
        payload = json.dumps(document, sort_keys=True)
        self.assertNotIn('"synthesisPermitted": true', payload)
        self.assertEqual(document["legacyNumbaCache"]["expectedFileCount"], 46)


if __name__ == "__main__":
    unittest.main()
