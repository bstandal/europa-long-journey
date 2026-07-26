from __future__ import annotations

import unittest

import v10_openvoice_v2_generate_comparison as generation


class V10OpenVoiceGenerationTests(unittest.TestCase):
    def test_generation_prerequisites_keep_full_work_closed(self) -> None:
        prerequisites = generation._prerequisites()
        self.assertEqual(
            set(prerequisites),
            {
                "modelLoadReceipt",
                "pronunciationReceipt",
                "methodConfiguration",
                "adapter",
            },
        )

    def test_exact_fourteen_utterances_are_bound(self) -> None:
        utterances = generation._utterance_material()
        self.assertEqual(len(utterances), 14)
        self.assertEqual(
            [item["utteranceID"] for item in utterances],
            generation.adapter.load_config()["comparison"]
            and [
                "v8-utterance-006", "v8-utterance-021", "v8-utterance-031",
                "v8-utterance-045", "v8-utterance-067", "v8-utterance-083",
                "v8-utterance-100", "v8-utterance-109", "v8-utterance-131",
                "v8-utterance-149", "v8-utterance-160", "v8-utterance-174",
                "v8-utterance-183", "v8-utterance-195",
            ],
        )

    def test_audio_file_count_is_three_per_synthesis(self) -> None:
        config = generation.adapter.load_config()
        self.assertEqual(config["comparison"]["requiredSynthesisCount"] * 3, 84)


if __name__ == "__main__":
    unittest.main()
