# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Keeps the canvas scenarios' tap points out from under the floating dock.

The dock stacks to three rows at the e2e window's pane width and covers the
bottom of the canvas, so a tap down there lands on the dock and reads later as
a note field that never opened. Runs at unit-test speed instead of inside the
advisory e2e run. The app side is canvas_call_dock_e2e_pane_test.dart.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_canvas_shapes as shapes

MAX_TAP_FRACTION = 0.5


class CanvasTapPointsTest(unittest.TestCase):
    def test_every_tap_point_is_above_the_dock(self):
        points = {k: v for k, v in vars(shapes).items() if k.endswith("_POINT")}
        self.assertTrue(points)
        for name, (_, fy) in points.items():
            self.assertLessEqual(fy, MAX_TAP_FRACTION, name)


if __name__ == "__main__":
    unittest.main()
