# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

    def test_every_link_is_filed_under_exactly_one_category(self):
        seen = set()
        for urls in seed_links.LINKS_BY_CATEGORY.values():
            for url in urls:
                self.assertNotIn(url, seen, url)
                seen.add(url)
        self.assertEqual(seen, set(seed_links.LINKS))

    def test_the_intro_matches_the_urls_own_category(self):
        rng = random.Random(2)
        seen_no_intro = False
        for _ in range(200):
            got = seed_links.link_message(rng)
            url = next(u for u in seed_links.LINKS if u in got)
            category = seed_links._category_of(url)
            prefix = got[:got.index(url)].rstrip(": ")
            if not prefix:
                seen_no_intro = True
                continue
            self.assertIn(prefix, seed_links._INTROS_BY_CATEGORY[category], got)
        self.assertTrue(seen_no_intro)

    def test_a_video_link_never_gets_an_image_or_repo_intro(self):
        rng = random.Random(3)
        for _ in range(200):
            got = seed_links.link_message(rng)
            if any(video_url in got for video_url in
                   seed_links.LINKS_BY_CATEGORY["video"]):
                self.assertNotIn("here's the repo", got)
                self.assertNotIn("look at this", got)


if __name__ == "__main__":
    unittest.main()
