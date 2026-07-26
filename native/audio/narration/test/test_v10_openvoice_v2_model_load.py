from __future__ import annotations

import unittest

import v10_openvoice_v2_model_load_probe as probe


class V10OpenVoiceModelLoadTests(unittest.TestCase):
    def test_model_paths_are_inside_exact_snapshot(self) -> None:
        for path in (
            probe.MELO_CONFIG,
            probe.MELO_CHECKPOINT,
            probe.BERT_ROOT / "model.safetensors",
            probe.CONVERTER_CONFIG,
            probe.CONVERTER_CHECKPOINT,
            probe.SOURCE_SE,
        ):
            self.assertTrue(path.is_file())
            path.relative_to(probe.runtime.SNAPSHOT_ROOT)

    def test_reference_inventory_is_exact(self) -> None:
        references = probe._reference_bindings()
        self.assertEqual(
            tuple(references), ("voice-candidate-05", "voice-candidate-06")
        )


if __name__ == "__main__":
    unittest.main()
