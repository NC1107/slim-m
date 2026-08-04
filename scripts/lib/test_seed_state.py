# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for the seeding script's shared, cross-account state.

No threads here: the lock's correctness under real concurrency is not what
these check, only that each method's own bookkeeping (what counts as a top
message, whose it is, what a delete removes) is right in isolation.
"""
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_state  # noqa: E402


class SeedStateTest(unittest.TestCase):
    def test_a_fresh_state_has_nothing_to_offer(self):
        state = seed_state.SeedState()
        rng = random.Random(0)
        self.assertIsNone(state.random_top_message(rng))
        self.assertIsNone(state.random_thread(rng))
        self.assertIsNone(state.random_own_message(rng, "alice"))
        self.assertFalse(state.has_top_message())
        self.assertFalse(state.has_thread())

    def test_a_added_top_message_is_findable_by_anyone(self):
        state = seed_state.SeedState()
        state.add_top_message("m1", "c1", "alice")
        rng = random.Random(0)
        got = state.random_top_message(rng)
        self.assertEqual(got, {"id": "m1", "channel_id": "c1", "author": "alice"})
        self.assertTrue(state.has_top_message())

    def test_own_messages_are_scoped_per_author(self):
        state = seed_state.SeedState()
        state.add_top_message("m1", "c1", "alice")
        state.add_top_message("m2", "c1", "bob")
        rng = random.Random(0)
        self.assertEqual(state.random_own_message(rng, "alice")["id"], "m1")
        self.assertEqual(state.random_own_message(rng, "bob")["id"], "m2")
        self.assertIsNone(state.random_own_message(rng, "carol"))

    def test_forgetting_a_message_removes_it_from_its_authors_pool_only(self):
        state = seed_state.SeedState()
        state.add_top_message("m1", "c1", "alice")
        state.add_top_message("m2", "c1", "alice")
        state.forget_own_message("alice", "m1")
        rng = random.Random(0)
        remaining = [state.random_own_message(rng, "alice") for _ in range(5)]
        self.assertTrue(all(m["id"] == "m2" for m in remaining))

    def test_a_thread_is_recorded_as_a_parent_and_channel_pair(self):
        state = seed_state.SeedState()
        state.add_thread("parent-1", "thread-channel-1")
        rng = random.Random(0)
        self.assertEqual(state.random_thread(rng), ("parent-1", "thread-channel-1"))
        self.assertTrue(state.has_thread())

    def test_counts_reflects_what_was_added(self):
        state = seed_state.SeedState()
        state.add_top_message("m1", "c1", "alice")
        state.add_top_message("m2", "c1", "bob")
        state.add_thread("m1", "thread-1")
        self.assertEqual(state.counts(), {"top_messages": 2, "threads": 1})


if __name__ == "__main__":
    unittest.main()
