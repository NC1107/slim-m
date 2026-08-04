# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for how a worker's action handlers draw on an ollama corpus.

No network: `ctx.api` is a `Mock` standing in for `e2e_api.Api`, and every
assertion is on what content it was asked to send, so this checks the
pool-wiring in seed_worker.py rather than seed_content.py's own generators
(covered in test_seed_content.py) or seed_ollama_pools.py's fetch/cache logic
(covered in test_seed_ollama.py).
"""
import random
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_actions  # noqa: E402
import seed_ollama_pools  # noqa: E402
import seed_state  # noqa: E402
import seed_worker  # noqa: E402


class HandlersTest(unittest.TestCase):
    def test_every_weighted_action_has_a_handler(self):
        names = {name for name, _weight in seed_actions.ACTIONS}
        self.assertEqual(names, set(seed_worker.HANDLERS))


class RunAccountActionsOverrideTest(unittest.TestCase):
    def test_defaults_to_the_full_action_set(self):
        ctx = _ctx()
        ctx.rng = random.Random(0)
        seed_worker.run_account(ctx, 30, (0, 0))
        self.assertGreater(ctx.api.send_message.call_count, 0)

    def test_an_explicit_actions_override_is_honoured(self):
        ctx = _ctx()
        ctx.rng = random.Random(0)
        stats, _failures = seed_worker.run_account(
            ctx, 10, (0, 0), actions=(("message_short", 1),))
        self.assertEqual(set(stats), {"message_short"})


def _ctx(corpus=None, api=None):
    fake_api = api or Mock()
    fake_api.send_message.return_value = {"id": "m1"}
    fake_api.call.return_value = {"id": "m1"}
    return seed_worker.WorkerContext(
        api=fake_api, username="alice", channel_id="c1",
        state=seed_state.SeedState(), rng=random.Random(1),
        other_usernames=["bob"], is_privileged=True, fixtures=[],
        corpus=corpus)


class PoolHelperTest(unittest.TestCase):
    def test_no_corpus_means_no_pool(self):
        ctx = _ctx(corpus=None)
        self.assertIsNone(seed_worker._pool(ctx, "short"))

    def test_a_corpus_yields_its_named_pool(self):
        ctx = _ctx(corpus=seed_ollama_pools.Corpus(short=["hi"]))
        self.assertEqual(seed_worker._pool(ctx, "short"), ["hi"])

    def test_an_empty_pool_on_a_present_corpus_is_an_empty_list_not_none(self):
        ctx = _ctx(corpus=seed_ollama_pools.Corpus())
        self.assertEqual(seed_worker._pool(ctx, "short"), [])


class HandlerDrawsFromCorpusTest(unittest.TestCase):
    """A pool with exactly one entry makes the draw deterministic."""

    def test_short_message_sends_the_pooled_text(self):
        ctx = _ctx(corpus=seed_ollama_pools.Corpus(short=["pooled short"]))
        seed_worker.handle_message_short(ctx)
        sent = ctx.api.send_message.call_args[0][1]
        self.assertEqual(sent, "pooled short")

    def test_no_corpus_sends_the_canned_short_message(self):
        ctx = _ctx(corpus=None)
        seed_worker.handle_message_short(ctx)
        sent = ctx.api.send_message.call_args[0][1]
        self.assertIn(sent.rstrip("."), seed_worker.seed_content._REACTS)

    def test_send_poll_uses_the_pooled_question_and_options(self):
        ctx = _ctx(corpus=seed_ollama_pools.Corpus(
            polls=[("pooled question?", ["X", "Y"])]))
        seed_worker.handle_send_poll(ctx)
        body = ctx.api.call.call_args[0][2]
        self.assertEqual(body["question"], "pooled question?")
        self.assertEqual(body["options"], ["X", "Y"])

    def test_code_block_message_uses_the_pooled_snippet(self):
        ctx = _ctx(corpus=seed_ollama_pools.Corpus(code=[("dart", "1+1;")]))
        seed_worker.handle_message_code_block(ctx)
        sent = ctx.api.send_message.call_args[0][1]
        self.assertIn("```dart\n1+1;\n```", sent)

    def test_an_empty_code_pool_falls_back_to_canned_snippets(self):
        ctx = _ctx(corpus=seed_ollama_pools.Corpus())
        seed_worker.handle_message_code_block(ctx)
        sent = ctx.api.send_message.call_args[0][1]
        self.assertIn("```", sent)


class LinkHandlerTest(unittest.TestCase):
    def test_sends_a_message_containing_a_link(self):
        ctx = _ctx()
        seed_worker.handle_message_link(ctx)
        sent = ctx.api.send_message.call_args[0][1]
        self.assertIn("https://", sent)


if __name__ == "__main__":
    unittest.main()
