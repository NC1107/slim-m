# SPDX-License-Identifier: Apache-2.0
"""Builds the varied image fixtures a canvas seeding run uploads once and
places many times, reusing scripts/lib/seed_media.py's generators rather
than a second image pipeline - the same reuse `seed_fixtures.py` already
does for message attachments.

Distinct real pixel sizes (a sticker up to a near-full-screen photo) so
placed images read as varied at a glance, and so overlap and z-order have
something worth stacking.
"""
import os

import seed_media

_SPECS = (
    ("canvas-sticker.png", 96, 96,
     lambda p, rng: seed_media.checkerboard_png(
         p, 96, 96, (216, 88, 55), (250, 240, 210), cell=6)),
    ("canvas-thumb.png", 220, 160,
     lambda p, rng: seed_media.gradient_png(
         p, 220, 160, (88, 180, 216), (33, 33, 46), axis="x")),
    ("canvas-portrait.png", 260, 480,
     lambda p, rng: seed_media.gradient_png(
         p, 260, 480, (216, 88, 150), (33, 46, 33), axis="y")),
    ("canvas-screenshot.png", 640, 400,
     lambda p, rng: seed_media.rings_png(
         p, 640, 400, (88, 216, 120), (245, 230, 200), ring_width=20)),
    ("canvas-banner.png", 900, 300,
     lambda p, rng: seed_media.gradient_png(
         p, 900, 300, (27, 111, 145), (216, 150, 55), axis="x")),
    ("canvas-photo.png", 1100, 760,
     lambda p, rng: seed_media.noise_png(p, 1100, 760, rng)),
)


def build(scratch_dir, rng):
    """Every image fixture as `(bytes, content_type, filename, width,
    height)`, one per `_SPECS` entry."""
    fixtures = []
    for filename, width, height, build_one in _SPECS:
        path = os.path.join(scratch_dir, filename)
        build_one(path, rng)
        with open(path, "rb") as handle:
            fixtures.append((handle.read(), "image/png", filename, width, height))
    return fixtures
