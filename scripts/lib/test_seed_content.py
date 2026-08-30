# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

    def test_the_code_corpus_reads_like_real_functions_not_hello_world(self):
        for _lang, code in seed_content._CODE_SNIPPETS:
            self.assertGreaterEqual(len(code.splitlines()), 5, code)

    def test_the_code_corpus_spans_several_languages(self):
        langs = {lang for lang, _code in seed_content._CODE_SNIPPETS if lang}
        self.assertGreaterEqual(len(langs), 5, langs)

    def test_code_block_message_intro_varies_across_draws(self):
        rng = random.Random(6)
        intros = set()
        for _ in range(60):
            got = seed_content.code_block_message(rng)
            intros.add(got.split("\n```", 1)[0])
        self.assertGreater(len(intros), 2, intros)

    def test_code_block_message_sometimes_skips_the_intro(self):
        rng = random.Random(6)
        results = [seed_content.code_block_message(rng) for _ in range(60)]
        self.assertTrue(any(got.startswith("```") for got in results))
        self.assertTrue(any(not got.startswith("```") for got in results))

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


class PoolDrawingTest(unittest.TestCase):
    """A non-empty `pool` is drawn from; an empty or absent one falls back."""

    def test_short_message_draws_from_a_given_pool(self):
        rng = random.Random(1)
        got = seed_content.short_message(rng, pool=["only-this-one"])
        self.assertEqual(got, "only-this-one")

    def test_short_message_falls_back_on_an_empty_pool(self):
        rng = random.Random(1)
        got = seed_content.short_message(rng, pool=[])
        self.assertTrue(got.endswith("."))

    def test_long_message_draws_from_a_given_pool(self):
        rng = random.Random(1)
        got = seed_content.long_message(rng, pool=["a long generated paragraph"])
        self.assertEqual(got, "a long generated paragraph")

    def test_code_block_message_draws_lang_and_code_from_a_given_pool(self):
        rng = random.Random(2)
        got = seed_content.code_block_message(rng, pool=[("dart", "1+1;")])
        self.assertIn("```dart\n1+1;\n```", got)

    def test_markdown_message_wraps_pooled_text_in_a_recognised_marker(self):
        markers = ("**", "*", "> ", "||", "~~", "# ")
        rng = random.Random(3)
        for _ in range(30):
            got = seed_content.markdown_message(rng, pool=["pooled line"])
            self.assertIn("pooled line", got)
            self.assertTrue(any(m in got for m in markers), got)

    def test_mention_message_uses_the_pooled_text_verbatim(self):
        rng = random.Random(4)
        got = seed_content.mention_message(rng, ["bob"], pool=["pooled reply"])
        self.assertEqual(got, "@bob pooled reply")

    def test_near_limit_message_is_still_exactly_the_ceiling_from_a_pool(self):
        rng = random.Random(1)
        got = seed_content.near_limit_message(rng, pool=["short pooled line"])
        self.assertEqual(len(got), seed_content.MAX_MESSAGE_CHARS)

    def test_poll_draws_the_pooled_question_and_options(self):
        rng = random.Random(5)
        question, options = seed_content.poll(
            rng, pool=[("pooled question?", ["A", "B", "C"])])
        self.assertEqual(question, "pooled question?")
        self.assertEqual(options, ["A", "B", "C"])


if __name__ == "__main__":
    unittest.main()
