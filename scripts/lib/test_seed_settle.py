# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for the settle pass that keeps the newest messages active.

No network: every context's `api` is a `Mock`, so every assertion is on
which targets and actors were chosen and how many calls landed, not on
what a real server did with them.
"""
import collections
import random
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_settle  # noqa: E402
import seed_state  # noqa: E402
import seed_worker  # noqa: E402


def _ctx(username):
    """A fake `WorkerContext` whose `send_message`/`open_thread` mint a
    unique id per call (`reply-<username>-1`, `-2`, ... / `thread-...`)
    rather than one constant value, or two replies or threads from the same
    account would collide on id and undercount as one in a caller's own
    bookkeeping."""
    fake_api = Mock()
    counter = iter(range(1, 10_000))
    fake_api.send_message.side_effect = (
        lambda *a, **k: {"id": f"reply-{username}-{next(counter)}"})
    call_counter = iter(range(1, 10_000))
    fake_api.call.side_effect = (
        lambda *a, **k: {"id": f"call-{username}-{next(call_counter)}"})
    fake_api.open_thread.side_effect = (
        lambda *a, **k: {"id": f"newthread-{username}-{next(call_counter)}"})
    return seed_worker.WorkerContext(
        api=fake_api, username=username, channel_id="c1",
        state=seed_state.SeedState(), rng=random.Random(username),
        other_usernames=[], is_privileged=False, fixtures=[], corpus=None)


def _state_with_messages(count, author="author"):
    state = seed_state.SeedState()
    for i in range(count):
        state.add_top_message(f"m{i}", "c1", author)
    return state


class RunTest(unittest.TestCase):
    def test_only_reacts_within_the_newest_slice_never_older_messages(self):
        """Original-target ids are `m<N>`; a reaction the pass makes on one
        of its own freshly created replies (`reply-<username>-<N>`) is not
        what this checks and is filtered out rather than mis-parsed."""
        state = _state_with_messages(300)
        contexts = [_ctx("alice"), _ctx("bob")]
        seed_settle.run(contexts, state, random.Random(1))
        reacted_ids = {
            call.args[1].split("/")[2]
            for ctx in contexts
            for call in ctx.api.call.call_args_list
            if call.args[0] == "PUT"
        }
        touched_indices = {
            int(mid[1:]) for mid in reacted_ids if mid.startswith("m") and mid[1:].isdigit()}
        self.assertTrue(touched_indices)
        cutoff = 300 - seed_settle.SETTLE_TARGET_MESSAGES
        self.assertTrue(all(index >= cutoff for index in touched_indices))

    def test_coverage_hits_and_targets_are_reported(self):
        """>=, not ==: targets also counts the pass's own created replies,
        covered separately by test_replies_the_pass_creates_also_count_as_targets."""
        state = _state_with_messages(150)
        contexts = [_ctx("alice"), _ctx("bob")]
        stats, failures = seed_settle.run(contexts, state, random.Random(1))
        self.assertGreaterEqual(stats["settle_coverage_targets"], seed_settle.SETTLE_TARGET_MESSAGES)
        self.assertGreater(stats["settle_coverage_hits"], 0)
        self.assertLessEqual(stats["settle_coverage_hits"], stats["settle_coverage_targets"])
        self.assertEqual(failures, [])

    def test_replies_the_pass_creates_also_count_as_targets(self):
        """A settle_reply is a brand new top-level message, so it starts
        exactly as bare as the problem this pass exists to fix; it must get
        its own chance at a reaction rather than being left off the count."""
        state = _state_with_messages(seed_settle.SETTLE_TARGET_MESSAGES)
        contexts = [_ctx("alice"), _ctx("bob")]
        stats, _failures = seed_settle.run(contexts, state, random.Random(1))
        reply_count = stats["settle_reply"]
        self.assertGreater(reply_count, 0)
        self.assertEqual(
            stats["settle_coverage_targets"],
            seed_settle.SETTLE_TARGET_MESSAGES + reply_count)

    def test_reaction_coverage_is_close_to_the_configured_share(self):
        state = _state_with_messages(seed_settle.SETTLE_TARGET_MESSAGES)
        contexts = [_ctx("alice"), _ctx("bob"), _ctx("carol")]
        stats, _failures = seed_settle.run(contexts, state, random.Random(2))
        rate = stats["settle_coverage_hits"] / stats["settle_coverage_targets"]
        self.assertGreater(rate, seed_settle.SETTLE_REACT_COVERAGE - 0.1)

    def test_never_reacts_to_or_replies_on_an_original_targets_own_author(self):
        """Every original target is authored by alice, so alice's own api
        must never be the one reacting to or replying on one of them - the
        reply-to-its-own-reply follow-up this pass also does is a different
        author each time (whoever created that reply) and is not this
        check's concern, so it is scoped to `m`-prefixed original ids."""
        state = _state_with_messages(seed_settle.SETTLE_TARGET_MESSAGES, author="alice")
        contexts = [_ctx("alice"), _ctx("bob")]
        seed_settle.run(contexts, state, random.Random(3))
        alice_reacted_to_original = [
            call for call in contexts[0].api.call.call_args_list
            if call.args[0] == "PUT" and call.args[1].split("/")[2].startswith("m")]
        alice_replied_to_original = [
            call for call in contexts[0].api.send_message.call_args_list
            if str(call.kwargs.get("reply_to_id", "")).startswith("m")]
        self.assertEqual(alice_reacted_to_original, [])
        self.assertEqual(alice_replied_to_original, [])

    def test_falls_back_to_the_targets_own_author_when_no_one_else_exists(self):
        state = _state_with_messages(seed_settle.SETTLE_TARGET_MESSAGES, author="alice")
        contexts = [_ctx("alice")]
        stats, _failures = seed_settle.run(contexts, state, random.Random(4))
        self.assertGreater(stats["settle_coverage_hits"], 0)

    def test_thread_replies_are_bounded_to_the_newest_threads_only(self):
        state = seed_state.SeedState()
        for i in range(seed_settle.SETTLE_THREAD_TARGETS + 5):
            state.add_thread(f"parent-{i}", f"thread-{i}")
        contexts = [_ctx("alice"), _ctx("bob")]
        stats, _failures = seed_settle.run(contexts, state, random.Random(5))
        self.assertGreater(stats["settle_reply_in_thread"], 0)
        sent_channels = {
            call.args[0] for ctx in contexts
            for call in ctx.api.send_message.call_args_list}
        oldest_thread_channels = {f"thread-{i}" for i in range(5)}
        self.assertFalse(sent_channels & oldest_thread_channels)

    def test_a_failing_call_is_recorded_not_raised(self):
        state = _state_with_messages(5)
        failing = _ctx("alice")
        failing.api.call.side_effect = RuntimeError("boom")
        failing.api.send_message.side_effect = RuntimeError("boom")
        failing.api.open_thread.side_effect = RuntimeError("boom")
        contexts = [failing, _ctx("bob")]
        stats, failures = seed_settle.run(contexts, state, random.Random(6))
        self.assertGreater(len(failures), 0)
        for username, action, reason in failures:
            self.assertIn(action, {
                "settle_react", "settle_reply", "settle_reply_in_thread",
                "settle_open_thread"})
            self.assertIn("boom", reason)

    def test_reactions_include_both_multi_emoji_and_multi_reactor_shapes(self):
        state = _state_with_messages(seed_settle.SETTLE_TARGET_MESSAGES)
        contexts = [_ctx(name) for name in ("alice", "bob", "carol", "dave", "erin")]
        seed_settle.run(contexts, state, random.Random(8))
        reactors_by_target_emoji = collections.defaultdict(set)
        for ctx in contexts:
            for call in ctx.api.call.call_args_list:
                if call.args[0] != "PUT":
                    continue
                parts = call.args[1].split("/")
                mid, emoji = parts[2], parts[4]
                reactors_by_target_emoji[(mid, emoji)].add(ctx.username)
        distinct_emoji_by_target = collections.defaultdict(set)
        for mid, emoji in reactors_by_target_emoji:
            distinct_emoji_by_target[mid].add(emoji)
        self.assertTrue(any(len(v) > 1 for v in distinct_emoji_by_target.values()),
                         "expected at least one target with 2+ distinct emoji")
        self.assertTrue(any(len(v) > 1 for v in reactors_by_target_emoji.values()),
                         "expected at least one (target, emoji) pair with 2+ reactors")

    def test_opens_new_threads_near_the_tail_with_deep_replies(self):
        state = _state_with_messages(seed_settle.SETTLE_TARGET_MESSAGES)
        contexts = [_ctx(name) for name in ("alice", "bob", "carol", "dave")]
        stats, _failures = seed_settle.run(contexts, state, random.Random(7))
        self.assertGreater(stats["settle_open_thread"], 0)
        channel_counts = collections.Counter()
        for ctx in contexts:
            for call in ctx.api.send_message.call_args_list:
                channel_counts[call.args[0]] += 1
        new_thread_channels = [c for c in channel_counts if c.startswith("newthread-")]
        self.assertTrue(new_thread_channels)
        low, high = seed_settle.SETTLE_NEW_THREAD_REPLIES
        self.assertTrue(any(low <= channel_counts[c] <= high for c in new_thread_channels))

    def test_new_threads_are_never_opened_on_a_larger_sample_than_available(self):
        state = _state_with_messages(2)
        contexts = [_ctx("alice"), _ctx("bob")]
        stats, failures = seed_settle.run(contexts, state, random.Random(9))
        self.assertEqual(failures, [])
        self.assertLessEqual(stats["settle_open_thread"], 2)

    def test_polls_near_the_tail_get_a_guaranteed_round_of_votes(self):
        state = seed_state.SeedState()
        for i in range(seed_settle.SETTLE_POLL_TARGETS):
            state.add_poll(f"p{i}", "c1", 3)
        contexts = [_ctx(name) for name in ("alice", "bob", "carol", "dave", "erin")]
        stats, failures = seed_settle.run(contexts, state, random.Random(10))
        self.assertEqual(failures, [])
        self.assertGreater(stats["settle_vote_poll"], 0)

    def test_a_poll_can_get_votes_from_several_distinct_accounts(self):
        state = seed_state.SeedState()
        state.add_poll("p1", "c1", 3)
        contexts = [_ctx(name) for name in ("alice", "bob", "carol", "dave", "erin")]
        seed_settle.run(contexts, state, random.Random(11))
        self.assertGreaterEqual(len(state.poll_voters("p1")), 2)

    def test_the_settle_pass_never_votes_twice_for_one_account_on_one_poll(self):
        state = seed_state.SeedState()
        state.add_poll("p1", "c1", 4)
        contexts = [_ctx(name) for name in ("alice", "bob", "carol")]
        seed_settle.run(contexts, state, random.Random(13))
        votes_by_account = collections.Counter()
        for ctx in contexts:
            for call in ctx.api.call.call_args_list:
                if call.args[0] == "PUT" and call.args[1] == "/messages/p1/polls/vote":
                    votes_by_account[ctx.username] += 1
        self.assertTrue(
            votes_by_account,
            "the fixed seed must record some votes, or the no-double-vote "
            "assertion below passes vacuously",
        )
        self.assertTrue(all(count <= 1 for count in votes_by_account.values()))

    def test_a_poll_the_coverage_roll_skips_gets_no_votes_at_all(self):
        """Not every poll should get votes, or the tail would read as
        uniformly finished rather than a run genuinely still in progress."""
        class _AlwaysSkipsCoverage:
            def random(self):
                return 0.999

        state = seed_state.SeedState()
        state.add_poll("p1", "c1", 3)
        contexts = [_ctx("alice"), _ctx("bob")]
        stats, failures = collections.Counter(), []
        seed_settle._vote_on_poll(
            contexts, _AlwaysSkipsCoverage(), stats, failures, state,
            state.newest_polls(1)[0])
        self.assertEqual(stats["settle_vote_poll"], 0)
        self.assertEqual(state.poll_voters("p1"), set())


class PollVotePlanTest(unittest.TestCase):
    def test_more_voters_than_options_forces_a_repeated_option(self):
        """A pigeonhole guarantee, not a probabilistic one: 5 voters over 2
        options must land at least one repeat, whatever the rng draws -
        the shape a real poll needs so it does not read as one vote apiece."""
        rng = random.Random(0)
        plan = seed_settle._poll_vote_plan(rng, options_count=2, voter_count=5)
        self.assertEqual(len(plan), 5)
        self.assertTrue(all(0 <= option < 2 for option in plan))
        self.assertGreater(len(plan), len(set(plan)))

    def test_every_option_is_reachable_over_many_draws(self):
        rng = random.Random(1)
        seen = set()
        for _ in range(50):
            seen.update(seed_settle._poll_vote_plan(rng, options_count=4, voter_count=1))
        self.assertEqual(seen, {0, 1, 2, 3})


if __name__ == "__main__":
    unittest.main()
