# SPDX-License-Identifier: Apache-2.0
"""Coverage for the hand-rolled UUIDv7 fallback.

Exercises `_build` directly rather than the `uuid7()` wrapper, so these
assertions hold regardless of whether the interpreter running them already
has `uuid.uuid7()` - the fallback still needs to be correct on its own.
"""
import sys
import unittest
import uuid as std_uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import uuid7  # noqa: E402


class FallbackBuildTest(unittest.TestCase):
    def test_version_nibble_is_seven(self):
        for _ in range(20):
            self.assertEqual(uuid7._build().version, 7)

    def test_variant_bits_are_rfc_4122(self):
        for _ in range(20):
            self.assertEqual(uuid7._build().variant, std_uuid.RFC_4122)

    def test_ids_generated_in_sequence_sort_in_creation_order(self):
        """A real client mints these moments apart, so a fixed, strictly
        increasing millisecond clock is what "in sequence" means here."""
        base = 1_700_000_000_000
        ids = [str(uuid7._build(now_ms=base + i)) for i in range(200)]
        self.assertEqual(ids, sorted(ids))

    def test_the_timestamp_field_round_trips(self):
        got = uuid7._build(now_ms=1_700_000_000_123)
        ts_ms = int.from_bytes(got.bytes[0:6], "big")
        self.assertEqual(ts_ms, 1_700_000_000_123)


class PublicHelperTest(unittest.TestCase):
    def test_returns_a_parseable_version_7_uuid_string(self):
        got = uuid7.uuid7()
        parsed = std_uuid.UUID(got)
        self.assertEqual(parsed.version, 7)


if __name__ == "__main__":
    unittest.main()
