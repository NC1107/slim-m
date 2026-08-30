# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Tests for seed_canvas_geometry.py; no network, pure geometry and byte math."""
import math
import random
import unittest

import seed_canvas_geometry as geom


class FreehandStrokeTest(unittest.TestCase):
    def test_produces_many_finite_points(self):
        points = geom.freehand_stroke(random.Random(1), (0, 0), steps=30)
        self.assertGreater(len(points), 25)
        self.assertTrue(all(math.isfinite(x) and math.isfinite(y)
                             for x, y in points))

    def test_is_not_a_straight_line(self):
        points = geom.freehand_stroke(random.Random(2), (0, 0), steps=60,
                                       turn_std=0.6)
        ys = [p[1] for p in points]
        self.assertGreater(max(ys) - min(ys), 5)


class RoughEllipseTest(unittest.TestCase):
    def test_is_closed(self):
        points = geom.rough_ellipse(random.Random(3), (0, 0), 50, 30)
        self.assertEqual(points[0], points[-1])

    def test_stays_roughly_within_radius(self):
        points = geom.rough_ellipse(random.Random(4), (0, 0), 50, 50, wobble=0.05)
        for x, y in points:
            self.assertLess(math.hypot(x, y), 70)


class WavyLineAndZigzagTest(unittest.TestCase):
    def test_wavy_line_leaves_the_direct_path(self):
        points = geom.wavy_line(random.Random(5), (0, 0), (200, 0), amplitude=20)
        self.assertTrue(any(abs(y) > 5 for _, y in points))

    def test_zigzag_alternates_sides(self):
        points = geom.zigzag(random.Random(6), (0, 0), (100, 0), segments=6,
                              spread=20)
        offsets = [y for _, y in points[1:-1]]
        self.assertTrue(any(o > 0 for o in offsets))
        self.assertTrue(any(o < 0 for o in offsets))


class ScribbleBallTest(unittest.TestCase):
    def test_mostly_stays_within_a_generous_bound(self):
        points = geom.scribble_ball(random.Random(7), (0, 0), 100, steps=200)
        far = [p for p in points if math.hypot(*p) > 160]
        self.assertLess(len(far), len(points) * 0.1)


class SplitStrokeTest(unittest.TestCase):
    def test_placements_stay_under_budget_once_actually_encoded(self):
        """The guarantee that matters is on what `stroke_placements` sends
        (each segment relative to its own bounding box), not on the still-
        absolute points `split_stroke` scans - see `_relative_props_size`'s
        own doc comment for why those two byte counts can differ."""
        rng = random.Random(8)
        points = geom.freehand_stroke(rng, (0, 0), steps=2000, step_length=(1, 2))
        ids = (f"id-{i}" for i in range(1000))
        placements = geom.stroke_placements(
            points, 3.0, "annotation", lambda: next(ids), budget=1000)
        for placement in placements:
            pts = list(zip(placement["props"]["points"][0::2],
                            placement["props"]["points"][1::2]))
            self.assertLessEqual(
                geom.props_size(pts, placement["props"]["width"],
                                 placement["props"]["color"]), 1000)

    def test_no_seam_between_segments(self):
        rng = random.Random(9)
        points = geom.quantize(geom.freehand_stroke(
            rng, (0, 0), steps=500, step_length=(1, 2)))
        segments = geom.split_stroke(points, 3.0, "annotation", budget=500)
        self.assertGreater(len(segments), 1)
        for previous, current in zip(segments, segments[1:]):
            self.assertEqual(previous[-1], current[0])

    def test_single_segment_when_small(self):
        points = [(0, 0), (1, 1), (2, 2)]
        segments = geom.split_stroke(points, 3.0, "annotation")
        self.assertEqual(len(segments), 1)

    def test_two_points_never_splits(self):
        points = [(0, 0), (1, 1)]
        segments = geom.split_stroke(points, 3.0, "annotation", budget=1)
        self.assertEqual(len(segments), 1)


class StrokePlacementsTest(unittest.TestCase):
    def test_relative_points_within_bounds(self):
        rng = random.Random(10)
        points = geom.freehand_stroke(rng, (100, 200), steps=40)
        ids = iter(["a", "b", "c", "d", "e"])
        placements = geom.stroke_placements(points, 3.0, "note",
                                             lambda: next(ids))
        for placement in placements:
            relative = placement["props"]["points"]
            xs = relative[0::2]
            ys = relative[1::2]
            self.assertGreaterEqual(min(xs), 0)
            self.assertGreaterEqual(min(ys), 0)
            self.assertLessEqual(max(xs), placement["w"] + 1e-6)
            self.assertLessEqual(max(ys), placement["h"] + 1e-6)

    def test_long_stroke_splits_into_several_objects(self):
        rng = random.Random(11)
        points = geom.freehand_stroke(rng, (0, 0), steps=3000, step_length=(1, 3))
        ids = (f"id-{i}" for i in range(1000))
        placements = geom.stroke_placements(points, 3.0, "shape",
                                             lambda: next(ids))
        self.assertGreater(len(placements), 1)
        for placement in placements:
            self.assertLessEqual(
                geom.props_size(
                    list(zip(placement["props"]["points"][0::2],
                             placement["props"]["points"][1::2])),
                    placement["props"]["width"], placement["props"]["color"]),
                geom.MAX_PROPS_BYTES)


if __name__ == "__main__":
    unittest.main()
