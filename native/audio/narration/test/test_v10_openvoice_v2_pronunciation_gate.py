from __future__ import annotations

import unittest

import v10_openvoice_v2_pronunciation_gate as gate


class V10OpenVoicePronunciationGateTests(unittest.TestCase):
    def test_critical_register_is_exact_and_complete(self) -> None:
        config = gate.load_config()
        self.assertEqual(
            tuple(config["criticalRegister"]), gate.EXPECTED_CRITICAL_WORDS
        )
        self.assertEqual(len(config["criticalRegister"]), 15)

    def test_only_frozen_project_overrides_exist(self) -> None:
        config = gate.load_config()
        self.assertEqual(
            set(config["projectOverrides"]),
            {"ad", "polis", "excommunication", "monasteries", "lepanto", "portuguese"},
        )
        for item in config["projectOverrides"].values():
            gate._validate_phones(item["phones"])

    def test_unknown_token_fails_closed(self) -> None:
        with self.assertRaisesRegex(gate.v8.V8Error, "unknown normalized token"):
            gate._resolve_token("not_in_the_frozen_dictionary", cmu={}, overrides={})

    def test_punctuation_is_not_sent_to_fallback(self) -> None:
        result = gate._resolve_token(",", cmu={}, overrides={})
        self.assertEqual(result, {"source": "meloPunctuation", "phones": [","]})


if __name__ == "__main__":
    unittest.main()
