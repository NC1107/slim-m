# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Tests for seed_canvas_content.py's pure placement builders; no network."""
import random
import unittest

import seed_canvas_content as content
import seed_canvas_layout as layout


class NotePlacementTest(unittest.TestCase):
    def test_is_a_note_centered_on_the_given_point(self):
        placement = content.note_placement(random.Random(1), 100, 200)
        self.assertEqual(placement["kind"], "note")
        self.assertIsInstance(placement["props"]["text"], str)
        self.assertGreater(len(placement["props"]["text"]), 0)
        cx = placement["x"] + placement["w"] / 2
        cy = placement["y"] + placement["h"] / 2
        self.assertAlmostEqual(cx, 100, places=1)
        self.assertAlmostEqual(cy, 200, places=1)

    def test_box_stays_close_to_the_client_default(self):
        rng = random.Random(2)
        for _ in range(30):
            placement = content.note_placement(rng, 0, 0)
            self.assertTrue(
                layout.DEFAULT_NOTE_WIDTH * 0.8 <= placement["w"]
                <= layout.DEFAULT_NOTE_WIDTH * 1.4)
            self.assertTrue(
                layout.DEFAULT_NOTE_HEIGHT * 0.8 <= placement["h"]
                <= layout.DEFAULT_NOTE_HEIGHT * 1.4)


class ShapePlacementTest(unittest.TestCase):
    def test_is_a_shape_with_a_known_kind(self):
        placement = content.shape_placement(random.Random(3), 50, -50)
        self.assertEqual(placement["kind"], "shape")
        self.assertIn(placement["props"]["shape"], layout.SHAPE_KINDS)

    def test_box_never_goes_negative(self):
        rng = random.Random(4)
        for _ in range(30):
            placement = content.shape_placement(rng, 0, 0)
            self.assertGreater(placement["w"], 0)
            self.assertGreater(placement["h"], 0)


class PlaceMainPassRatiosTest(unittest.TestCase):
    """Drives place_main_pass against a fake api whose `call` just echoes
    the placement straight back with a made-up seq/z_index, the same shape
    a real server response carries - close enough to prove the kind mix
    without a network."""

    class _FakeApi:
        def __init__(self):
            self.next_seq = 1

        def call(self, method, path, body=None, raw=None, content_type=None):
            del method, path, raw, content_type
            body = dict(body)
            body["seq"] = self.next_seq
            body["z_index"] = self.next_seq
            self.next_seq += 1
            return body

    def test_every_kind_appears_at_a_nonzero_ratio(self):
        rng = random.Random(5)
        api = self._FakeApi()
        centers = [(0, 0)]
        weights = [1]
        placed, counts = content.place_main_pass(
            [api], "chan", centers, weights, [], 400, 0.25, 0.15, 0.1, rng)
        self.assertEqual(len(placed), sum(
            counts[k] for k in ("images", "notes", "shapes", "strokes")))
        for kind in ("notes", "shapes", "strokes"):
            self.assertGreater(counts[kind], 0)
        self.assertEqual(counts["images"], 0)  # no uploaded images given
        placed_kinds = {p["kind"] for p in placed}
        self.assertEqual(placed_kinds, {"note", "shape", "stroke"})


if __name__ == "__main__":
    unittest.main()
