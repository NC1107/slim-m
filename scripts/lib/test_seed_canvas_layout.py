# SPDX-License-Identifier: Apache-2.0
"""Tests for seed_canvas_layout.py; no network, pure sampling."""
import math
import random
import unittest

import seed_canvas_layout as layout


class ClusterCentersTest(unittest.TestCase):
    def test_returns_the_requested_count(self):
        centers = layout.cluster_centers(random.Random(1), 5)
        self.assertEqual(len(centers), 5)

    def test_respects_the_minimum_gap_when_the_range_allows_it(self):
        centers = layout.cluster_centers(random.Random(2), 4, min_gap=500)
        for i, (ax, ay) in enumerate(centers):
            for bx, by in centers[i + 1:]:
                self.assertGreaterEqual(math.hypot(ax - bx, ay - by), 500)


class ClusterWeightsTest(unittest.TestCase):
    def test_returns_one_weight_per_cluster(self):
        weights = layout.cluster_weights(random.Random(3), 6)
        self.assertEqual(len(weights), 6)
        self.assertTrue(all(w > 0 for w in weights))


class SamplePositionTest(unittest.TestCase):
    def test_mostly_lands_near_a_cluster_with_no_stray_chance(self):
        rng = random.Random(4)
        centers = [(0, 0), (5000, 5000)]
        weights = [1, 1]
        near_hits = 0
        for _ in range(200):
            x, y = layout.sample_position(rng, centers, weights,
                                           stray_chance=0.0)
            if any(math.hypot(x - cx, y - cy) < 2000 for cx, cy in centers):
                near_hits += 1
        self.assertGreater(near_hits, 150)

    def test_stray_chance_of_one_always_escapes_the_clusters(self):
        rng = random.Random(5)
        centers = [(0, 0)]
        weights = [1]
        for _ in range(50):
            x, y = layout.sample_position(
                rng, centers, weights, stray_chance=1.0,
                stray_range=((3000, 4000), (3000, 4000)))
            self.assertGreaterEqual(x, 3000)
            self.assertGreaterEqual(y, 3000)

    def test_no_centers_falls_back_to_a_stray_position(self):
        rng = random.Random(6)
        x, y = layout.sample_position(rng, [], [], stray_chance=0.0,
                                       stray_range=((1, 2), (1, 2)))
        self.assertTrue(1 <= x <= 2)
        self.assertTrue(1 <= y <= 2)


class PickersTest(unittest.TestCase):
    def test_color_key_is_one_of_the_defined_tokens(self):
        rng = random.Random(7)
        for _ in range(20):
            self.assertIn(layout.pick_color_key(rng), layout.COLOR_KEYS)

    def test_stroke_width_is_a_plausible_pen_size(self):
        rng = random.Random(8)
        for _ in range(20):
            self.assertTrue(1.0 <= layout.pick_stroke_width(rng) <= 8.0)

    def test_image_scale_is_a_plausible_resize(self):
        rng = random.Random(9)
        for _ in range(20):
            self.assertTrue(0.4 <= layout.pick_image_scale(rng) <= 1.6)


if __name__ == "__main__":
    unittest.main()
