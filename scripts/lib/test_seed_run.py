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

import seed_ollama  # noqa: E402
import seed_run  # noqa: E402


class DescribeCorpusTest(unittest.TestCase):
    def test_no_corpus_means_ollama_was_never_requested(self):
        self.assertIn("not requested", seed_run._describe_corpus(None))

    def test_an_empty_corpus_reads_as_unavailable_not_silent(self):
        got = seed_run._describe_corpus(seed_ollama.Corpus())
        self.assertIn("unavailable", got)
        self.assertIn("canned", got)

    def test_a_populated_corpus_reports_each_pool_size(self):
        corpus = seed_ollama.Corpus(
            short=["a", "b"], long=["c"], code=[("py", "x")], polls=[])
        got = seed_run._describe_corpus(corpus)
        self.assertIn("2 short", got)
        self.assertIn("1 long", got)
        self.assertIn("1 code", got)
        self.assertIn("0 poll", got)


if __name__ == "__main__":
    unittest.main()
