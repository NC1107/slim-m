# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for the optional Ollama-generated seed corpus.

No network and no real Ollama here, matching CI's bare runner: every test
patches `urllib.request.urlopen` (or the module's own orchestration
functions) with a fake, and the point of most of these is that a failure -
unreachable, a missing model, a response that fails to parse - is caught
and answered with an empty or partial `Corpus` rather than raised.
"""
import json
import shutil
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_ollama  # noqa: E402


def _fake_response(payload):
    response = Mock()
    response.read.return_value = json.dumps(payload).encode()
    response.__enter__ = Mock(return_value=response)
    response.__exit__ = Mock(return_value=False)
    return response


def _generate_response(inner):
    """What Ollama's own /api/generate answers: `response` is a JSON string."""
    return _fake_response({"response": json.dumps(inner)})


class CorpusTest(unittest.TestCase):
    def test_a_fresh_corpus_with_nothing_in_it_is_empty(self):
        self.assertTrue(seed_ollama.Corpus().is_empty())

    def test_one_populated_pool_is_enough_to_not_be_empty(self):
        self.assertFalse(seed_ollama.Corpus(short=["hi"]).is_empty())

    def test_round_trips_through_as_dict_and_back(self):
        original = seed_ollama.Corpus(
            short=["hi"], long=["a longer one"],
            code=[("python", "print(1)")], polls=[("q?", ["a", "b"])])
        restored = seed_ollama.Corpus(**json.loads(json.dumps(original.as_dict())))
        self.assertEqual(restored.short, original.short)
        self.assertEqual(restored.code, original.code)
        self.assertEqual(restored.polls, original.polls)


class FetchMessagesTest(unittest.TestCase):
    def test_parses_and_strips_the_message_list(self):
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"messages": [" hi ", "bye"]})):
            got = seed_ollama._fetch_messages("http://x", "m", "prompt", 5)
        self.assertEqual(got, ["hi", "bye"])

    def test_drops_blank_or_non_string_entries(self):
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"messages": ["", "  ", "ok", 5]})):
            got = seed_ollama._fetch_messages("http://x", "m", "prompt", 5)
        self.assertEqual(got, ["ok"])

    def test_a_malformed_response_raises_for_the_caller_to_handle(self):
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"nonsense": True})):
            with self.assertRaises(KeyError):
                seed_ollama._fetch_messages("http://x", "m", "prompt", 5)


class FetchCodeTest(unittest.TestCase):
    def test_parses_lang_and_code_pairs(self):
        items = [{"lang": "Python", "code": "print(1)"},
                  {"lang": "", "code": "echo hi"}]
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"items": items})):
            got = seed_ollama._fetch_code("http://x", "m", 5)
        self.assertEqual(got, [("python", "print(1)"), (None, "echo hi")])

    def test_drops_entries_with_no_code(self):
        items = [{"lang": "python", "code": "  "}, {"lang": "rust", "code": "fn f(){}"}]
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"items": items})):
            got = seed_ollama._fetch_code("http://x", "m", 5)
        self.assertEqual(got, [("rust", "fn f(){}")])


class FetchPollsTest(unittest.TestCase):
    def test_keeps_a_poll_with_two_to_four_options(self):
        polls = [{"question": "tabs or spaces?", "options": ["tabs", "spaces"]}]
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"polls": polls})):
            got = seed_ollama._fetch_polls("http://x", "m", 5)
        self.assertEqual(got, [("tabs or spaces?", ["tabs", "spaces"])])

    def test_drops_a_poll_with_fewer_than_two_options(self):
        polls = [{"question": "only one?", "options": ["a"]}]
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"polls": polls})):
            got = seed_ollama._fetch_polls("http://x", "m", 5)
        self.assertEqual(got, [])

    def test_truncates_a_poll_with_more_than_four_options(self):
        polls = [{"question": "pick one", "options": ["a", "b", "c", "d", "e"]}]
        with patch("urllib.request.urlopen",
                    return_value=_generate_response({"polls": polls})):
            got = seed_ollama._fetch_polls("http://x", "m", 5)
        self.assertEqual(got[0][1], ["a", "b", "c", "d"])


class FetchOrEmptyTest(unittest.TestCase):
    def test_returns_the_fetch_result_on_success(self):
        got = seed_ollama._fetch_or_empty("thing", lambda: ["a"])
        self.assertEqual(got, ["a"])

    def test_any_exception_becomes_an_empty_list_not_a_raise(self):
        def boom():
            raise urllib.error.URLError("nope")
        got = seed_ollama._fetch_or_empty("thing", boom)
        self.assertEqual(got, [])


class ReachableTest(unittest.TestCase):
    def test_true_when_the_model_is_in_the_tag_list(self):
        with patch("urllib.request.urlopen",
                    return_value=_fake_response({"models": [{"name": "qwen3:8b"}]})):
            self.assertTrue(seed_ollama._reachable("http://x", "qwen3:8b"))

    def test_false_when_the_model_is_not_pulled(self):
        with patch("urllib.request.urlopen",
                    return_value=_fake_response({"models": [{"name": "other"}]})):
            self.assertFalse(seed_ollama._reachable("http://x", "qwen3:8b"))

    def test_false_when_the_server_is_unreachable(self):
        with patch("urllib.request.urlopen", side_effect=urllib.error.URLError("refused")):
            self.assertFalse(seed_ollama._reachable("http://x", "qwen3:8b"))


class LoadOrGenerateTest(unittest.TestCase):
    def setUp(self):
        self.cache_dir = tempfile.mkdtemp(prefix="seed-ollama-test-")
        self.addCleanup(shutil.rmtree, self.cache_dir, ignore_errors=True)

    def test_an_unreachable_server_never_calls_generate(self):
        with patch("seed_ollama._reachable", return_value=False), \
             patch("seed_ollama.generate") as fake_generate:
            got = seed_ollama.load_or_generate(
                "m", "seed-1", cache_dir=self.cache_dir)
        fake_generate.assert_not_called()
        self.assertTrue(got.is_empty())

    def test_a_successful_generation_is_written_to_the_cache(self):
        corpus = seed_ollama.Corpus(short=["hi"])
        with patch("seed_ollama._reachable", return_value=True), \
             patch("seed_ollama.generate", return_value=corpus):
            seed_ollama.load_or_generate("m", "seed-1", cache_dir=self.cache_dir)
        path = seed_ollama._cache_path("m", "seed-1", self.cache_dir)
        self.assertTrue(Path(path).exists())

    def test_a_second_call_with_the_same_model_and_seed_reads_the_cache(self):
        corpus = seed_ollama.Corpus(short=["hi"])
        with patch("seed_ollama._reachable", return_value=True), \
             patch("seed_ollama.generate", return_value=corpus):
            seed_ollama.load_or_generate("m", "seed-1", cache_dir=self.cache_dir)
        with patch("seed_ollama._reachable") as fake_reachable, \
             patch("seed_ollama.generate") as fake_generate:
            got = seed_ollama.load_or_generate("m", "seed-1", cache_dir=self.cache_dir)
        fake_reachable.assert_not_called()
        fake_generate.assert_not_called()
        self.assertEqual(got.short, ["hi"])

    def test_a_different_seed_does_not_share_the_cache(self):
        corpus = seed_ollama.Corpus(short=["hi"])
        with patch("seed_ollama._reachable", return_value=True), \
             patch("seed_ollama.generate", return_value=corpus):
            seed_ollama.load_or_generate("m", "seed-1", cache_dir=self.cache_dir)
        with patch("seed_ollama._reachable", return_value=False):
            got = seed_ollama.load_or_generate("m", "seed-2", cache_dir=self.cache_dir)
        self.assertTrue(got.is_empty())

    def test_generation_returning_nothing_usable_is_not_cached(self):
        with patch("seed_ollama._reachable", return_value=True), \
             patch("seed_ollama.generate", return_value=seed_ollama.Corpus()):
            seed_ollama.load_or_generate("m", "seed-1", cache_dir=self.cache_dir)
        path = seed_ollama._cache_path("m", "seed-1", self.cache_dir)
        self.assertFalse(Path(path).exists())


if __name__ == "__main__":
    unittest.main()
