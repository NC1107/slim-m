# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for the link-bearing message generator."""
import random
import sys
import unittest
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_links  # noqa: E402


class LinkMessageTest(unittest.TestCase):
    def test_always_contains_a_url_from_the_pool(self):
        rng = random.Random(1)
        for _ in range(30):
            got = seed_links.link_message(rng)
            self.assertTrue(any(url in got for url in seed_links.LINKS), got)

    def test_same_seed_produces_the_same_message(self):
        first = seed_links.link_message(random.Random(9))
        second = seed_links.link_message(random.Random(9))
        self.assertEqual(first, second)

    def test_every_link_is_a_valid_https_url(self):
        for url in seed_links.LINKS:
            parsed = urllib.parse.urlparse(url)
            self.assertEqual(parsed.scheme, "https")
            self.assertTrue(parsed.hostname)

    def test_the_pool_spans_more_than_one_hostname(self):
        hosts = {urllib.parse.urlparse(url).hostname for url in seed_links.LINKS}
        self.assertGreater(len(hosts), 3)


if __name__ == "__main__":
    unittest.main()
