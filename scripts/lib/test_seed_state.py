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


class RecencyChoiceTest(unittest.TestCase):
    """`_recency_choice` in isolation: no lock, no `SeedState`, just the
    weighting a caller with a plain list can check directly."""

    def test_an_empty_pool_offers_nothing(self):
        entry, from_recent = seed_state._recency_choice(random.Random(0), [])
        self.assertIsNone(entry)
        self.assertFalse(from_recent)

    def test_most_draws_land_in_the_recent_window_not_a_hard_cutoff(self):
        pool = list(range(500))
        rng = random.Random(7)
        picks = [seed_state._recency_choice(rng, pool)[0] for _ in range(4000)]
        in_window = sum(1 for p in picks if p >= 500 - seed_state.RECENT_WINDOW)
        rate = in_window / len(picks)
        self.assertGreater(rate, 0.7)
        self.assertLess(rate, 0.95)

    def test_the_long_tail_can_still_revive_old_entries(self):
        """Not a hard cutoff: over enough draws, plenty of entries older
        than the recent window still get picked at least once each - no
        single old id is guaranteed by any one draw, so this checks the
        tail as a whole rather than pinning one index."""
        pool = list(range(500))
        cutoff = 500 - seed_state.RECENT_WINDOW
        rng = random.Random(7)
        picks = {seed_state._recency_choice(rng, pool)[0] for _ in range(4000)}
        old_picks = {p for p in picks if p < cutoff}
        self.assertGreater(len(old_picks), cutoff // 2)


class RecencyStatsTest(unittest.TestCase):
    def test_a_fresh_state_reports_no_draws_yet(self):
        state = seed_state.SeedState()
        self.assertEqual(
            state.recency_stats(), {"draws": 0, "from_recent_window": 0, "rate": None})

    def test_every_real_pick_is_counted_and_the_rate_matches_the_hits(self):
        state = seed_state.SeedState()
        for i in range(200):
            state.add_top_message(f"m{i}", "c1", "alice")
        rng = random.Random(3)
        for _ in range(300):
            state.random_top_message(rng)
        stats = state.recency_stats()
        self.assertEqual(stats["draws"], 300)
        self.assertGreater(stats["from_recent_window"], 0)
        self.assertAlmostEqual(
            stats["rate"], stats["from_recent_window"] / stats["draws"])

    def test_a_draw_against_an_empty_pool_is_not_counted(self):
        state = seed_state.SeedState()
        rng = random.Random(0)
        state.random_top_message(rng)  # nothing to draw yet
        self.assertEqual(state.recency_stats()["draws"], 0)

    def test_reply_in_thread_favours_recently_opened_threads(self):
        """`random_thread` biases the same way as messages, which is what
        keeps a `reply_in_thread` draw landing on a thread that just opened
        rather than one from early in the run."""
        state = seed_state.SeedState()
        for i in range(80):
            state.add_thread(f"parent-{i}", f"thread-{i}")
        rng = random.Random(11)
        picks = [state.random_thread(rng)[1] for _ in range(2000)]
        recent_ids = {f"thread-{i}" for i in range(80 - seed_state.RECENT_WINDOW, 80)}
        recent_hits = sum(1 for p in picks if p in recent_ids)
        self.assertGreater(recent_hits / len(picks), 0.7)


if __name__ == "__main__":
    unittest.main()
