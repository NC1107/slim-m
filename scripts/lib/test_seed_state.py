# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
        self.assertIsNone(state.random_unvoted_poll(rng, "alice"))
        self.assertFalse(state.has_top_message())
        self.assertFalse(state.has_thread())
        self.assertFalse(state.has_poll())
        self.assertFalse(state.has_unvoted_poll("alice"))

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

    def test_forgetting_a_message_removes_it_from_its_authors_pool(self):
        state = seed_state.SeedState()
        state.add_top_message("m1", "c1", "alice")
        state.add_top_message("m2", "c1", "alice")
        state.forget_own_message("alice", "m1")
        rng = random.Random(0)
        remaining = [state.random_own_message(rng, "alice") for _ in range(5)]
        self.assertTrue(all(m["id"] == "m2" for m in remaining))

    def test_forgetting_a_message_also_removes_it_from_the_top_level_pool(self):
        """A deleted message must not still be a reachable react/reply/
        settle-pass target, or those calls 404 against a message that is
        no longer there."""
        state = seed_state.SeedState()
        state.add_top_message("m1", "c1", "alice")
        state.add_top_message("m2", "c1", "bob")
        state.forget_own_message("alice", "m1")
        rng = random.Random(0)
        remaining = [state.random_top_message(rng) for _ in range(5)]
        self.assertTrue(all(m["id"] == "m2" for m in remaining))
        self.assertNotIn("m1", {m["id"] for m in state.newest_top_messages(10)})

    def test_forgetting_a_deleted_poll_removes_it_from_the_poll_pools_too(self):
        """A poll is a message too, so deleting one (delete_message draws
        from the same author-scoped pool a poll's own send recorded it
        into) must not leave it reachable to random_unvoted_poll or
        newest_polls - every vote against a dangling entry like that 404s,
        since the message behind it is really gone on the server."""
        state = seed_state.SeedState()
        state.add_top_message("p1", "c1", "alice")
        state.add_poll("p1", "c1", 2)
        state.record_poll_vote("p1", "bob")
        state.forget_own_message("alice", "p1")
        rng = random.Random(0)
        self.assertIsNone(state.random_unvoted_poll(rng, "carol"))
        self.assertEqual(state.newest_polls(10), [])
        self.assertFalse(state.has_poll())
        self.assertEqual(state.poll_voters("p1"), set())

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
        state.add_poll("m3", "c1", 3)
        self.assertEqual(
            state.counts(), {"top_messages": 2, "threads": 1, "polls": 1})

    def test_newest_top_messages_is_a_fixed_tail_slice(self):
        state = seed_state.SeedState()
        for i in range(10):
            state.add_top_message(f"m{i}", "c1", "alice")
        newest = state.newest_top_messages(3)
        self.assertEqual([m["id"] for m in newest], ["m7", "m8", "m9"])

    def test_newest_top_messages_is_never_more_than_the_whole_pool(self):
        state = seed_state.SeedState()
        state.add_top_message("m1", "c1", "alice")
        self.assertEqual(len(state.newest_top_messages(100)), 1)

    def test_newest_threads_is_a_fixed_tail_slice(self):
        state = seed_state.SeedState()
        for i in range(5):
            state.add_thread(f"parent-{i}", f"thread-{i}")
        newest = state.newest_threads(2)
        self.assertEqual(newest, [("parent-3", "thread-3"), ("parent-4", "thread-4")])

    def test_a_fresh_poll_has_no_voters_and_is_findable_by_anyone(self):
        state = seed_state.SeedState()
        state.add_poll("p1", "c1", 3)
        rng = random.Random(0)
        self.assertTrue(state.has_poll())
        self.assertEqual(state.poll_voters("p1"), set())
        self.assertEqual(state.random_unvoted_poll(rng, "alice")["id"], "p1")

    def test_a_recorded_vote_removes_that_voter_from_random_unvoted_poll(self):
        state = seed_state.SeedState()
        state.add_poll("p1", "c1", 2)
        state.record_poll_vote("p1", "alice")
        rng = random.Random(0)
        self.assertEqual(state.poll_voters("p1"), {"alice"})
        self.assertIsNone(state.random_unvoted_poll(rng, "alice"))
        self.assertEqual(state.random_unvoted_poll(rng, "bob")["id"], "p1")

    def test_has_unvoted_poll_is_per_caller_not_deployment_wide(self):
        """`has_poll` stays true forever once a poll has ever existed;
        `has_unvoted_poll` is what `resolve_action` actually needs, since a
        caller who has already voted on every poll has nothing left to vote
        on even though a poll genuinely exists."""
        state = seed_state.SeedState()
        state.add_poll("p1", "c1", 2)
        state.record_poll_vote("p1", "alice")
        self.assertTrue(state.has_poll())
        self.assertFalse(state.has_unvoted_poll("alice"))
        self.assertTrue(state.has_unvoted_poll("bob"))

    def test_has_unvoted_poll_is_true_if_any_poll_is_still_unvoted(self):
        state = seed_state.SeedState()
        state.add_poll("p1", "c1", 2)
        state.add_poll("p2", "c1", 2)
        state.record_poll_vote("p1", "alice")
        self.assertTrue(state.has_unvoted_poll("alice"))

    def test_newest_polls_is_a_fixed_tail_slice(self):
        state = seed_state.SeedState()
        for i in range(5):
            state.add_poll(f"p{i}", "c1", 2)
        newest = state.newest_polls(2)
        self.assertEqual([p["id"] for p in newest], ["p3", "p4"])


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
