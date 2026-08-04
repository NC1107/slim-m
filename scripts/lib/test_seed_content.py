# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for the seeding script's content generators.

Every generator is deterministic under a seeded `random.Random`, so this
checks shape (length ceilings, markdown syntax, valid poll structure) rather
than exact strings, and that a seeded run is reproducible.
"""
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_content  # noqa: E402


class PersonaTest(unittest.TestCase):
    def test_distinct_indices_get_distinct_usernames(self):
        seen = {seed_content.persona(i)[0] for i in range(40)}
        self.assertEqual(len(seen), 40)

    def test_a_username_matches_the_server_pattern(self):
        import re
        pattern = re.compile(r"^[A-Za-z0-9_.-]+$")
        for i in range(20):
            username, _ = seed_content.persona(i)
            self.assertTrue(pattern.match(username), username)
            self.assertLessEqual(len(username), 32)


class MessageGeneratorsTest(unittest.TestCase):
    def test_near_limit_message_is_exactly_the_server_ceiling(self):
        rng = random.Random(1)
        got = seed_content.near_limit_message(rng)
        self.assertEqual(len(got), seed_content.MAX_MESSAGE_CHARS)

    def test_short_and_long_messages_stay_under_the_ceiling(self):
        rng = random.Random(1)
        for _ in range(20):
            self.assertLess(len(seed_content.short_message(rng)),
                             seed_content.MAX_MESSAGE_CHARS)
            self.assertLess(len(seed_content.long_message(rng)),
                             seed_content.MAX_MESSAGE_CHARS)

    def test_code_block_message_is_fenced(self):
        rng = random.Random(2)
        got = seed_content.code_block_message(rng)
        self.assertIn("```", got)
        self.assertEqual(got.count("```"), 2)

    def test_markdown_message_uses_a_recognised_marker(self):
        markers = ("**", "*", "> ", "||", "~~", "# ")
        rng = random.Random(3)
        for _ in range(30):
            got = seed_content.markdown_message(rng)
            self.assertTrue(any(m in got for m in markers), got)

    def test_mention_message_addresses_the_given_username(self):
        rng = random.Random(4)
        got = seed_content.mention_message(rng, ["bob"])
        self.assertTrue(got.startswith("@bob "))

    def test_same_seed_produces_the_same_message(self):
        first = seed_content.long_message(random.Random(7))
        second = seed_content.long_message(random.Random(7))
        self.assertEqual(first, second)

    def test_poll_has_between_two_and_four_options(self):
        rng = random.Random(5)
        for _ in range(10):
            _, options = seed_content.poll(rng)
            self.assertGreaterEqual(len(options), 2)
            self.assertLessEqual(len(options), 4)


if __name__ == "__main__":
    unittest.main()
