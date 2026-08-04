# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for the seeding run's corpus-status reporting.

Only `_describe_corpus` is covered here: the rest of `seed_run.run` is an
end-to-end orchestration of live HTTP calls with no seam worth faking in a
unit test, and is exercised instead by actually running the script against
a local server (see the docstring on seed-data.py).
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_conversation  # noqa: E402
import seed_ollama_pools  # noqa: E402
import seed_run  # noqa: E402


class DescribeConversationsTest(unittest.TestCase):
    def test_none_means_a_conversation_replay_never_applied(self):
        self.assertIsNone(seed_run._describe_conversations(None))

    def test_an_empty_list_reads_as_unusable_not_silent(self):
        got = seed_run._describe_conversations([])
        self.assertIn("none usable", got)

    def test_a_populated_list_reports_the_count_and_turn_total(self):
        conv = seed_conversation.Conversation(topic="t", turns=[object()] * 5)
        got = seed_run._describe_conversations([conv, conv])
        self.assertIn("2 (", got)
        self.assertIn("10 turns", got)


class DescribeCorpusTest(unittest.TestCase):
    def test_no_corpus_means_ollama_was_never_requested(self):
        self.assertIn("not requested", seed_run._describe_corpus(None))

    def test_an_empty_corpus_reads_as_unavailable_not_silent(self):
        got = seed_run._describe_corpus(seed_ollama_pools.Corpus())
        self.assertIn("unavailable", got)
        self.assertIn("canned", got)

    def test_a_populated_corpus_reports_each_pool_size(self):
        corpus = seed_ollama_pools.Corpus(
            short=["a", "b"], long=["c"], code=[("py", "x")], polls=[])
        got = seed_run._describe_corpus(corpus)
        self.assertIn("2 short", got)
        self.assertIn("1 long", got)
        self.assertIn("1 code", got)
        self.assertIn("0 poll", got)


class ConversationPaceRangeTest(unittest.TestCase):
    def test_a_shorter_conversation_gets_a_slower_per_turn_pace(self):
        """Fewer turns spread over roughly the same target duration means
        each turn has to wait longer, or the short conversation finishes
        first and goes quiet for the rest of the run."""
        short = seed_run._conversation_pace_range(10, 40)
        long = seed_run._conversation_pace_range(40, 40)
        self.assertGreater(sum(short) / 2, sum(long) / 2)

    def test_never_returns_a_zero_or_negative_pace(self):
        low, high = seed_run._conversation_pace_range(10_000, 1)
        self.assertGreater(low, 0)
        self.assertGreater(high, low)

    def test_matching_actions_and_turns_yields_roughly_the_workers_own_pace(self):
        low, high = seed_run._conversation_pace_range(40, 40)
        worker_low, worker_high = seed_run._PACE_RANGE
        worker_mid = (worker_low + worker_high) / 2
        self.assertAlmostEqual((low + high) / 2, worker_mid, delta=0.05)


class SplitConversationTailTest(unittest.TestCase):
    def test_no_conversations_splits_into_two_empty_lists(self):
        interleaved, tail = seed_run._split_conversation_tail([])
        self.assertEqual(interleaved, [])
        self.assertEqual(tail, [])

    def test_every_conversation_lands_in_exactly_one_half(self):
        conversations = list(range(10))
        interleaved, tail = seed_run._split_conversation_tail(conversations)
        self.assertEqual(sorted(interleaved + tail), conversations)

    def test_the_tail_is_never_empty_when_conversations_exist(self):
        for count in (1, 2, 3, 5, 10, 21):
            _interleaved, tail = seed_run._split_conversation_tail(list(range(count)))
            self.assertGreater(len(tail), 0, f"count={count}")

    def test_the_tail_is_the_most_recently_generated_conversations(self):
        conversations = ["a", "b", "c", "d"]
        _interleaved, tail = seed_run._split_conversation_tail(conversations)
        self.assertEqual(tail, conversations[-len(tail):])


if __name__ == "__main__":
    unittest.main()
