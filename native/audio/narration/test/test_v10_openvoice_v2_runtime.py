from __future__ import annotations

import unittest

import v10_openvoice_v2_runtime_audit as runtime


class V10OpenVoiceRuntimeAuditTests(unittest.TestCase):
    def test_single_wheel_lock_matches_every_approved_licence(self) -> None:
        lock = runtime.parse_single_wheel_lock()
        self.assertEqual(len(lock), 44)
        self.assertEqual(set(lock), set(runtime.APPROVED_LICENCES))
        self.assertTrue(
            all(len(item["wheelSHA256"]) == 64 for item in lock.values())
        )

    def test_runtime_has_no_unavoidable_copyleft_dependency(self) -> None:
        prohibited = {"GPL", "LGPL", "AGPL"}
        self.assertFalse(
            any(
                any(token in licence for token in prohibited)
                for licence in runtime.APPROVED_LICENCES.values()
            )
        )

    def test_openvoice_patch_is_exactly_one_lazy_import_move(self) -> None:
        archive = runtime.SNAPSHOT_ROOT / "source/openVoice.tar.gz"
        with runtime.tarfile.open(archive, "r:gz") as tar:
            handle = tar.extractfile(
                runtime.OPENVOICE_DIRECTORY + "/openvoice/api.py"
            )
            assert handle is not None
            original = handle.read()
        patched = runtime._patched_api_from_original(original)
        self.assertEqual(runtime.hashlib.sha256(original).hexdigest(), runtime.ORIGINAL_OPENVOICE_API_SHA256)
        self.assertEqual(runtime.hashlib.sha256(patched).hexdigest(), runtime.PATCHED_OPENVOICE_API_SHA256)
        self.assertEqual(patched.count(b"from openvoice.text import text_to_sequence"), 1)


if __name__ == "__main__":
    unittest.main()
