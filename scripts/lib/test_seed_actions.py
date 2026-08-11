# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for the seeding script's weighted action chooser.

`resolve_action` is the fallback chain a worker leans on when the shared
state does not yet support what it rolled - covered here against every
combination directly, with no server and no shared state object involved.
"""
import random
import sys
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_actions  # noqa: E402


class ChooseActionTest(unittest.TestCase):
    def test_only_named_actions_are_ever_chosen(self):
        rng = random.Random(0)
        names = {name for name, _ in seed_actions.ACTIONS}
        for _ in range(500):
            self.assertIn(seed_actions.choose_action(rng), names)

    def test_a_single_action_is_always_chosen(self):
        rng = random.Random(0)
        got = seed_actions.choose_action(rng, actions=(("only", 1),))
        self.assertEqual(got, "only")

    def test_heavier_weights_are_drawn_more_often(self):
        rng = random.Random(0)
        actions = (("common", 90), ("rare", 10))
        counts = Counter(seed_actions.choose_action(rng, actions=actions)
                          for _ in range(2000))
        self.assertGreater(counts["common"], counts["rare"])


def _resolve(action, **overrides):
    state = {
        "has_top_message": True, "has_own_message": True,
        "has_thread": True, "has_other_account": True, "is_privileged": True,
        "has_unvoted_poll": True,
    }
    state.update(overrides)
    return seed_actions.resolve_action(action, **state)


class ResolveActionTest(unittest.TestCase):
    def test_a_fully_satisfied_state_returns_the_action_unchanged(self):
        for name, _ in seed_actions.ACTIONS:
            self.assertEqual(_resolve(name), name)

    def test_reply_react_open_thread_and_pin_need_a_top_message(self):
        for action in ("reply", "react", "open_thread", "pin_message"):
            self.assertEqual(_resolve(action, has_top_message=False),
                              seed_actions.FALLBACK)

    def test_pin_message_needs_a_privileged_caller(self):
        self.assertEqual(_resolve("pin_message", is_privileged=False),
                          seed_actions.FALLBACK)

    def test_mention_needs_another_account(self):
        self.assertEqual(_resolve("message_mention", has_other_account=False),
                          seed_actions.FALLBACK)

    def test_reply_in_thread_needs_an_existing_thread(self):
        self.assertEqual(_resolve("reply_in_thread", has_thread=False),
                          seed_actions.FALLBACK)

    def test_vote_poll_needs_a_poll_this_caller_has_not_yet_voted_on(self):
        self.assertEqual(_resolve("vote_poll", has_unvoted_poll=False),
                          seed_actions.FALLBACK)

    def test_edit_and_delete_need_a_message_of_ones_own(self):
        for action in ("edit_message", "delete_message"):
            self.assertEqual(_resolve(action, has_own_message=False),
                              seed_actions.FALLBACK)

    def test_an_unaffected_action_ignores_an_unrelated_missing_prerequisite(self):
        self.assertEqual(_resolve("message_short", has_top_message=False),
                          "message_short")


class UtilityActionsTest(unittest.TestCase):
    def test_excludes_every_chat_shaped_action_conversation_replay_covers(self):
        names = {name for name, _weight in seed_actions.UTILITY_ACTIONS}
        self.assertFalse(names & seed_actions.CONVERSATION_COVERED)

    def test_keeps_every_other_action_with_its_original_weight(self):
        as_dict = dict(seed_actions.ACTIONS)
        for name, weight in seed_actions.UTILITY_ACTIONS:
            self.assertEqual(weight, as_dict[name])

    def test_covers_every_named_action_between_the_two_pools(self):
        covered_names = {name for name, _ in seed_actions.UTILITY_ACTIONS} | seed_actions.CONVERSATION_COVERED
        all_names = {name for name, _ in seed_actions.ACTIONS}
        self.assertEqual(covered_names, all_names)


if __name__ == "__main__":
    unittest.main()
