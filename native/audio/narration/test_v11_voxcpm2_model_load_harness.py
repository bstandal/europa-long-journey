#!/usr/bin/env python3
"""Isolated pre-R5 tests for the VoxCPM2 model-load receipt harness."""

from __future__ import annotations

import ast
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import v11_voxcpm2_model_load_gate as gate


class V11VoxCPM2ModelLoadHarnessTests(unittest.TestCase):
    def test_every_referenced_snapshot_attribute_exists(self) -> None:
        tree = ast.parse(gate.SCRIPT_PATH.read_text(encoding="utf-8"))
        referenced = sorted(
            {
                node.attr
                for node in ast.walk(tree)
                if isinstance(node, ast.Attribute)
                and isinstance(node.value, ast.Name)
                and node.value.id == "snapshot"
            }
        )
        self.assertTrue(referenced)
        self.assertEqual(
            [name for name in referenced if not hasattr(gate.snapshot, name)],
            [],
        )
        self.assertTrue(gate.SNAPSHOT_RECEIPT_PATH.is_file())
        self.assertEqual(
            gate.SNAPSHOT_RECEIPT_PATH,
            gate.snapshot.SNAPSHOT_ROOT / gate.snapshot.RECEIPT_NAME,
        )

    def test_synthetic_worker_json_to_verified_receipt_without_model(self) -> None:
        synthetic_worker = {
            "status": gate.WORKER_STATUS,
            "python": "3.11.15",
            "torch": "2.10.0",
            "architecture": "VoxCPM2Model",
            "runtimeDevice": "mps",
            "floatingParameterDtypes": ["float32"],
            "parameterDevices": ["mps"],
            "parameterCount": 1,
            "modelTraining": False,
            "encodeSampleRate": 16_000,
            "outputSampleRate": 48_000,
            "denoiserLoaded": False,
            "optimisationEnabled": False,
            "networkAttemptCount": 0,
            "memoryBefore": {
                "currentAllocatedBytes": 0,
                "driverAllocatedBytes": 0,
            },
            "memoryAfter": {
                "currentAllocatedBytes": 1,
                "driverAllocatedBytes": 1,
                "processPeakRSSBytes": 1,
            },
            "bytecodeCacheChecks": [{"stage": "synthetic-worker"}],
            "promptEncoded": False,
            "generationMethodCalled": False,
            "generatedAudio": False,
        }
        method_result = {
            "status": gate.method.STATUS,
            "callCount": 28,
            "uniqueSeedCount": 28,
            "modelInitialisation": gate.method.MODEL_INITIALISATION,
            "generationSettings": gate.method.GENERATION_SETTINGS,
        }
        receipt = gate.build_receipt(
            snapshot_result={
                "status": "SYNTHETIC_NO_MODEL",
                "modelTotalBytes": 4_960_731_703,
            },
            runtime_result={
                "status": gate.runtime.STATUS,
                "packageCount": 59,
                "mpsAvailable": True,
            },
            method_result=method_result,
            worker=synthetic_worker,
            bytecode_checks=[{"stage": "synthetic-parent"}],
        )
        self.assertFalse(receipt["generatedAudio"])
        self.assertFalse(receipt["priorUnreceiptedR4LoadUsedAsPassEvidence"])
        with tempfile.TemporaryDirectory(prefix="v11-r5-harness-") as directory:
            path = Path(directory) / "synthetic-receipt.json"
            binding = gate.write_receipt_and_verify(receipt, path)
            payload = path.read_bytes()
            self.assertEqual(binding["bytes"], len(payload))
            self.assertEqual(binding["sha256"], hashlib.sha256(payload).hexdigest())
            self.assertEqual(json.loads(payload), receipt)


if __name__ == "__main__":
    unittest.main()
