# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for scripts/lib/path_guard.py."""
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import path_guard  # noqa: E402


class Sha256HexTest(unittest.TestCase):
    def test_a_real_digest_round_trips_to_its_own_hex(self):
        raw = bytes(range(32))

        self.assertEqual(path_guard.sha256_hex(raw), raw.hex())

    def test_rejects_a_string_even_if_it_looks_like_hex(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.sha256_hex("aa" * 32)

    def test_rejects_a_short_blob(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.sha256_hex(b"too short")

    def test_rejects_a_long_blob(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.sha256_hex(b"x" * 33)

    def test_rejects_none(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.sha256_hex(None)


class AvatarUuidTest(unittest.TestCase):
    def test_a_real_user_id_round_trips_to_its_own_uuid_text(self):
        raw = uuid.uuid4().bytes

        self.assertEqual(path_guard.avatar_uuid(raw), str(uuid.UUID(bytes=raw)))

    def test_rejects_a_string(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.avatar_uuid(str(uuid.uuid4()))

    def test_rejects_a_short_blob(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.avatar_uuid(b"short")

    def test_rejects_a_long_blob(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.avatar_uuid(b"x" * 17)


class ContainedPathTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name) / "mirror"
        self.root.mkdir()

    def test_an_ordinary_name_stays_inside_the_root(self):
        result = path_guard.contained_path(self.root, "abcdef")

        self.assertEqual(result, (self.root / "abcdef").resolve())

    def test_a_parent_traversal_name_is_refused(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.contained_path(self.root, "../escaped")

    def test_a_name_carrying_its_own_separator_is_refused(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.contained_path(self.root, "nested/escaped")

    def test_an_absolute_name_is_refused(self):
        with self.assertRaises(path_guard.PathValidationError):
            path_guard.contained_path(self.root, "/etc/passwd")

    def test_a_symlink_planted_inside_root_pointing_outside_is_refused(self):
        outside = self.root.parent / "outside"
        outside.mkdir()
        link = self.root / "planted"
        link.symlink_to(outside)

        with self.assertRaises(path_guard.PathValidationError):
            path_guard.contained_path(self.root, "planted")


if __name__ == "__main__":
    unittest.main()
