# SPDX-License-Identifier: Apache-2.0
"""Builds the main pass of placed canvas objects: clustered strokes and
images, plus the one deliberately oversized stroke that proves
`split_stroke`'s byte-budget path runs during a real seeding pass, not just
under a unit test.

Split out of seed_canvas_run.py to keep that file under the review budget.
"""
import uuid7

import seed_canvas_geometry as geom
import seed_canvas_layout as layout
import seed_canvas_ops as ops

_STROKE_BUILDERS = {
    "freehand": lambda rng, center: geom.freehand_stroke(
        rng, center, steps=rng.randint(20, 70)),
    "ellipse": lambda rng, center: geom.rough_ellipse(
        rng, center, rng.uniform(30, 140), rng.uniform(20, 100)),
    "wavy": lambda rng, center: geom.wavy_line(
        rng, (center[0] - rng.uniform(60, 200), center[1]),
        (center[0] + rng.uniform(60, 200), center[1] + rng.uniform(-40, 40))),
    "zigzag": lambda rng, center: geom.zigzag(
        rng, (center[0] - rng.uniform(40, 120), center[1]),
        (center[0] + rng.uniform(40, 120), center[1] + rng.uniform(-30, 30))),
    "scribble": lambda rng, center: geom.scribble_ball(
        rng, center, rng.uniform(40, 160)),
}


def stroke_placements(rng, cx, cy):
    """One doodle style picked at random, turned into one or more
    ready-to-send placements (more than one only if the byte budget forced
    a split)."""
    style = rng.choice(list(_STROKE_BUILDERS))
    points = _STROKE_BUILDERS[style](rng, (cx, cy))
    width = layout.pick_stroke_width(rng)
    color = layout.pick_color_key(rng)
    return geom.stroke_placements(points, width, color, uuid7.uuid7)


def image_placement(rng, attachment, natural_w, natural_h, cx, cy):
    """One image placement centered on `(cx, cy)`, resized from its real
    decoded pixel size rather than always placed at native scale."""
    scale = layout.pick_image_scale(rng)
    w = round(natural_w * scale, 2)
    h = round(natural_h * scale, 2)
    return {
        "id": uuid7.uuid7(), "kind": "image",
        "x": round(cx - w / 2, 2), "y": round(cy - h / 2, 2), "w": w, "h": h,
        "props": {"attachment": attachment["id"],
                   "content_type": attachment["content_type"],
                   "width": natural_w, "height": natural_h},
    }


def upload_images(api_by_index, images):
    """Uploads every fixture from seed_canvas_images.build through *every*
    account, returning `[(attachment, width, height), ...]`.

    A placement's `props.attachment` is only accepted from an account that
    uploaded it itself or already sees it referenced somewhere - see
    `crates/slimm-server/src/store/attachments.rs`'s `may_link` - so a
    fixture uploaded by one account only would be unplaceable by any
    other. Content-addressed storage means every account past the first
    only registers itself as an uploader of bytes already on disk; nothing
    is stored twice.
    """
    uploaded = []
    for data, content_type, filename, width, height in images:
        attachment = None
        for api in api_by_index:
            attachment = ops.upload_attachment(api, filename, data, content_type)
        uploaded.append((attachment, width, height))
    return uploaded


def place_main_pass(api_by_index, channel_id, centers, weights, uploaded,
                     count, image_ratio, rng):
    """Places `count` objects across clustered positions, mixing strokes
    and images at `image_ratio`, round-robin across authors. Returns the
    placed rows (each with `author_index` attached) plus per-kind counts."""
    placed = []
    image_count = 0
    stroke_count = 0
    split_events = 0
    for index in range(count):
        author_index = index % len(api_by_index)
        api = api_by_index[author_index]
        cx, cy = layout.sample_position(rng, centers, weights)
        if rng.random() < image_ratio and uploaded:
            attachment, width, height = rng.choice(uploaded)
            objects = [image_placement(rng, attachment, width, height, cx, cy)]
            image_count += 1
        else:
            objects = stroke_placements(rng, cx, cy)
            stroke_count += 1
            if len(objects) > 1:
                split_events += 1
        for placement in objects:
            result = ops.place_object(api, channel_id, placement)
            result["author_index"] = author_index
            placed.append(result)
    return placed, {"images": image_count, "strokes": stroke_count,
                     "split_stroke_events": split_events}


def place_oversized_stroke(api, channel_id, author_index, centers, weights, rng):
    """One deliberately long freehand stroke - hundreds of points, well past
    what fits in one `MAX_PROPS_BYTES` object - so `split_stroke` genuinely
    splits during this run rather than only in its own unit test. Returns
    `(placed_rows, did_split)`."""
    center = layout.sample_position(rng, centers, weights, stray_chance=0.0)
    points = geom.freehand_stroke(rng, center, steps=900, step_length=(2, 4))
    placements = geom.stroke_placements(
        points, layout.pick_stroke_width(rng), layout.pick_color_key(rng),
        uuid7.uuid7)
    placed = []
    for placement in placements:
        result = ops.place_object(api, channel_id, placement)
        result["author_index"] = author_index
        placed.append(result)
    return placed, len(placements) > 1
