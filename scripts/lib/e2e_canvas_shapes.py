# SPDX-License-Identifier: Apache-2.0
"""The three tools e2e_canvas.py's own module doc says it does not cover:
note, shape, and reordering a stroke - each written after the canvas grew
past the single pen it shipped with (see CLAUDE.md's canvas entries).

Split out of e2e_canvas.py to stay under the file budget; every helper used
here (origin, at_frac, wait_for_summary, wait_for_kind_count,
open_activity_log, close_activity_log, object_of_kind, STROKE_MID) is
defined there and imported rather than duplicated.

Note and shape are placed with a single tap, not a drag - `CanvasSurface`
fires `onNotePlace`/`onShapePlace` once, on pointer-down (see
canvas_surface.dart's own `_down`), so a `drag()` call with one point is a
real tap: press and release at the same spot.
"""
import time

import e2e_labels as L
from e2e_canvas import (
    STROKE_MID,
    at,
    at_frac,
    close_activity_log,
    object_of_kind,
    open_activity_log,
    origin,
    wait_for_summary,
)

# A fraction of the surface's own live size, not a fixed pixel offset - see this module's own doc for why.
_NOTE_POINT = (0.15, 0.85)
_SHAPE_POINT = (0.55, 0.85)


def place_note_and_see_it_live(a, b, admin_api, channel_id):
    """`a` drops a note carrying real text with the note tool; `b`, already
    watching, sees it arrive - text and all, not just an empty box.
    """
    point = at_frac(a.canvas_rect(), *_NOTE_POINT)
    a.click(L.NOTE_TOOL)
    a.gestures(True)
    a.drag([point])
    a.gestures(False)

    a.type_into(L.NOTE_TEXT_FIELD, "a note from alice")
    a.click(L.ADD_NOTE)

    wait_for_summary(a, "1 note")
    wait_for_summary(b, "1 note")
    print("  a's note arrived on b's screen live")

    note = object_of_kind(admin_api, channel_id, "note")
    assert note["props"].get("text") == "a note from alice", \
        "the note's own text did not reach the server"


def place_shape_and_see_it_live(a, b, admin_api, channel_id):
    """`a` drops the default (rectangle) shape with the shape tool; `b`
    sees it arrive too.
    """
    point = at_frac(a.canvas_rect(), *_SHAPE_POINT)
    a.click(L.SHAPE_TOOL)
    a.gestures(True)
    a.drag([point])
    a.gestures(False)

    wait_for_summary(a, "1 shape")
    wait_for_summary(b, "1 shape")
    print("  a's shape arrived on b's screen live")

    shape = object_of_kind(admin_api, channel_id, "shape")
    assert shape["props"].get("shape") == "rectangle", \
        "the shape's own kind did not reach the server"


def _others_z(api, channel_id, object_id):
    return [o["z_index"] for o in api.canvas_objects(channel_id)
            if o["id"] != object_id]


def reorder_stroke_and_see_it_live(a, b, admin_api, channel_id):
    """Selects the pen stroke with the Move tool - a stroke can only ever
    be reordered, never dragged, see `beginSelect`'s own doc - and brings
    it above every other object, then sends it back below all of them.

    A stroke's own z_index is the one property this scenario can check on
    the server that a screen genuinely cannot show (`CanvasSurface` paints,
    it does not narrate), so the cross-client proof is `b`'s activity log
    instead: `CanvasObjectReordered` carries no actor field at all (see
    canvas_activity_log.dart's own doc on why a reorder is treated as a
    moderation-shaped event), so "An object's stacking order changed."
    is what a live receiver sees regardless of who moved it.
    """
    stroke = object_of_kind(admin_api, channel_id, "stroke")

    a.click(L.SELECT_TOOL)
    a.gestures(True)
    a.drag([at(origin(a), STROKE_MID)])
    a.gestures(False)

    a.click(L.MORE_CANVAS_ACTIONS)
    a.click(L.BRING_TO_FRONT)

    raised = _wait_until(
        lambda: admin_api.canvas_object(channel_id, stroke["id"]),
        lambda obj: obj["z_index"] > max(_others_z(
            admin_api, channel_id, stroke["id"])),
        "the stroke never rose above every other object on the server")
    print(f"  brought the stroke to the front (z_index {raised['z_index']})")

    open_activity_log(b)
    b.wait_for("stacking order changed", timeout=20)
    b.shot("canvas-reorder-in-activity-log")
    close_activity_log(b)
    print("  b's activity log recorded the reorder live, "
          "not only the server's own row")

    a.click(L.MORE_CANVAS_ACTIONS)
    a.click(L.SEND_TO_BACK)

    lowered = _wait_until(
        lambda: admin_api.canvas_object(channel_id, stroke["id"]),
        lambda obj: obj["z_index"] < min(_others_z(
            admin_api, channel_id, stroke["id"])),
        "the stroke never dropped below every other object on the server")
    print(f"  sent the stroke back (z_index {lowered['z_index']})")


def _wait_until(read, satisfied, failure_message, timeout=15):
    deadline = time.time() + timeout
    current = None
    while time.time() < deadline:
        current = read()
        if satisfied(current):
            return current
        time.sleep(0.5)
    raise AssertionError(failure_message)
