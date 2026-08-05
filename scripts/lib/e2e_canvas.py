# SPDX-License-Identifier: Apache-2.0
"""The Voice Canvas across two clients: draw, paste, move, resize, erase,
clear, undo, and a reload that proves what persists actually persists.

The canvas is a `CustomPainter` and publishes almost nothing else to the
accessibility tree this harness drives - see docs/e2e.md's "Driving a canvas
app". Two things stand in for the widgets a normal scenario would click:

- The surface's own container `Semantics` node, whose label always starts
  "Canvas," and states the live object count ("Canvas, 2 objects: 1 stroke,
  1 image"). That label updates on every local and live change, so it is
  this scenario's main proof that both clients agree, without ever opening
  anything.
- `CanvasActivityLog`'s panel (canvas_activity_log.dart, canvas_
  activity_panel.dart), a real list of `AppListRow`s a screen reader - and
  this harness - can browse. It is reached for exactly one thing the object
  count cannot show: that a move (or a resize, which is the same wire op
  with a different box) actually arrived on the client that did not make it,
  not only that the server's own row changed.

Camera math: `Camera` starts at `(0, 0)` with `zoom: 1` (canvas_stroke.dart)
and nothing here ever pans or zooms, so a world coordinate and a page
coordinate differ by exactly one constant offset for the whole scenario -
the canvas surface's own top-left, fetched once as `_origin`.

Drawing, moving and resizing all need raw pointer events: the semantics tree
sits over the canvas and swallows ordinary clicks there, the same reason the
react button needs `gestures(True)` elsewhere in this harness. Every other
control here (the tool buttons, Undo, the overflow menu) is clicked by label
as usual.

The pasted image is placed through the same DOM `paste` event a real Ctrl+V
produces (e2e_js.paste_image), not through the API: the bug this scenario
exists to catch - an image visible only to whoever pasted it, and only until
they reloaded - was a client-side hydration gap, and calling the API
directly would prove nothing about whether a *receiving* client fetches and
decodes the bytes back.
"""
import json
import time

import e2e_labels as L

# Offsets from the canvas's own top-left; the stroke's own midpoint is where the eraser lands on it later.
_STROKE_START = (80, 80)
_STROKE_MID = (150, 80)
_STROKE_END = (220, 80)


def _origin(client):
    rect = client.canvas_rect()
    return rect["x"], rect["y"]


def _at(origin, offset):
    return origin[0] + offset[0], origin[1] + offset[1]


def _summary(client, needle, timeout=30):
    client.wait_for(needle, timeout=timeout)


def _open_activity_log(client):
    client.click(L.MORE_CANVAS_ACTIONS)
    client.click(L.SHOW_ACTIVITY_LOG)


def _close_activity_log(client):
    client.click(L.MORE_CANVAS_ACTIONS)
    client.click(L.HIDE_ACTIVITY_LOG)


def _wait_for_kind_count(api, channel_id, kind, expected, timeout=15):
    """Polls the server, not the screen: the object count on screen drops
    the instant a removal is drawn locally, well before the async submit
    that pushes an undo entry has actually landed - clicking Undo in that
    gap does nothing, since the button is still disabled. Waiting for the
    server's own row to change is what proves the round trip finished.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        count = sum(1 for o in api.canvas_objects(channel_id) if o["kind"] == kind)
        if count == expected:
            return
        time.sleep(0.5)
    raise AssertionError(f"server never settled to {expected} {kind}(s)")


def _fetched_url_containing(client, server, needle):
    raw = client.ev(
        "JSON.stringify(performance.getEntriesByType('resource')"
        ".map(function(e){return e.name;}))")
    return any(needle in url for url in json.loads(raw or "[]")
               if server in url)


def open_on_both(a, b, channel):
    """Both clients into the same channel's canvas, empty."""
    for c in (a, b):
        c.click(channel)
        c.wait_for(L.COMPOSER)
        c.click(L.OPEN_CANVAS)
        c.wait_for("no objects")
    print("  both clients opened the canvas and see it empty")


def draw_stroke_and_see_it_live(a, b):
    """`a` draws a short pen stroke; `b`, already watching, sees it arrive."""
    origin = _origin(a)
    a.gestures(True)
    a.drag([_at(origin, _STROKE_START), _at(origin, _STROKE_MID),
            _at(origin, _STROKE_END)])
    a.gestures(False)
    _summary(a, "1 stroke")
    _summary(b, "1 stroke")
    print("  a's stroke arrived on b's screen live")


def paste_image_and_hydrate(a, b, server, admin_api, channel_id, image_path):
    """`a` pastes a real image; `b` renders it, bytes fetched and all.

    Placing the object is only half the claim in CLAUDE.md's own account of
    the hydration bug: the object row can exist while a receiving client
    still shows nothing but a box, because nothing ever asked the server for
    the pixels. Checking `b`'s own `performance` resource log for a request
    naming this exact attachment id is what tells those two apart.
    """
    a.paste_clipboard_image(image_path)
    _summary(a, "1 image")
    _summary(b, "1 image")
    print("  the pasted image arrived on b's screen live")

    attachment_id = _image_object(admin_api, channel_id)["props"]["attachment"]

    deadline = time.time() + 20
    while time.time() < deadline:
        if _fetched_url_containing(b, server, attachment_id):
            print(f"  b's own browser fetched the attachment bytes "
                  f"({attachment_id}) rather than showing an empty box")
            return
        time.sleep(1)
    raise AssertionError(
        "b's browser never fetched the pasted image's bytes - "
        "it would have rendered as a placeholder, not a picture")


def _image_object(api, channel_id):
    return next(o for o in api.canvas_objects(channel_id)
                if o["kind"] == "image")


def move_and_resize_converges(a, b, admin_api, channel_id):
    """Drags the pasted image, then its handle, checked on the server and
    on the one client that never touched it.

    The select tool only ever picks up an image (`hitTestImageAt`), never a
    stroke - canvas_hit_test.dart's own doc says why - so this always moves
    the picture just pasted, not the ink drawn earlier.
    """
    ox, oy = _origin(a)
    image_id = _image_object(admin_api, channel_id)["id"]
    before = admin_api.canvas_object(channel_id, image_id)

    a.click(L.SELECT_TOOL)
    center = a.find("Canvas,")
    cx, cy = center["x"], center["y"]  # the paste centred the image here
    a.gestures(True)
    a.drag([(cx, cy), (cx + 90, cy + 60), (cx + 150, cy + 100)])
    a.gestures(False)
    time.sleep(2)

    moved = admin_api.canvas_object(channel_id, image_id)
    assert abs(moved["x"] - (before["x"] + 150)) < 8, \
        f"x did not track the drag: {moved['x']} vs {before['x'] + 150}"
    assert abs(moved["y"] - (before["y"] + 100)) < 8, \
        f"y did not track the drag: {moved['y']} vs {before['y'] + 100}"
    assert moved["w"] == before["w"] and moved["h"] == before["h"], \
        "a plain move changed the object's size too"
    print(f"  moved the image to ({moved['x']:.0f}, {moved['y']:.0f})")

    corner = (ox + moved["x"] + moved["w"], oy + moved["y"] + moved["h"])
    a.gestures(True)
    a.drag([corner, (corner[0] + 25, corner[1] + 20),
            (corner[0] + 50, corner[1] + 40)])
    a.gestures(False)
    time.sleep(2)

    resized = admin_api.canvas_object(channel_id, image_id)
    assert resized["w"] > moved["w"] and resized["h"] > moved["h"], \
        f"the resize handle did not grow the box: {resized['w']}x{resized['h']}"
    print(f"  resized it to {resized['w']:.0f}x{resized['h']:.0f}")

    _open_activity_log(b)
    b.wait_for("was moved", timeout=20)
    b.shot("canvas-move-in-activity-log")
    _close_activity_log(b)
    print("  b's activity log recorded the move and the resize live, "
          "not only the server's own row")


def erase_undo_clear_and_restore(a, b, admin_api, channel_id):
    """Erases the stroke, undoes it, clears the whole canvas, undoes that.

    Every step is read off the surface's own object-count label on *both*
    clients, since erase, undo, clear and restore all change that count and
    none of them need the activity panel to be seen.
    """
    a.click(L.ERASER_TOOL)
    a.gestures(True)
    a.drag([_at(_origin(a), _STROKE_MID)])
    a.gestures(False)
    for c in (a, b):
        _summary(c, "0 strokes")
    print("  erasing the stroke dropped the count on both clients")
    _wait_for_kind_count(admin_api, channel_id, "stroke", 0)

    a.click(L.UNDO)
    for c in (a, b):
        _summary(c, "1 stroke")
    print("  undo restored it on both clients")

    a.click(L.MORE_CANVAS_ACTIONS)
    a.click(L.CLEAR_CANVAS)
    a.click(L.CLEAR_CANVAS, settle=3)  # the confirm dialog's own button
    for c in (a, b):
        _summary(c, "no objects")
    print("  clearing wiped the canvas on both clients")
    deadline = time.time() + 15
    while time.time() < deadline and admin_api.canvas_objects(channel_id):
        time.sleep(0.5)

    a.click(L.UNDO)
    for c in (a, b):
        _summary(c, "1 stroke, 1 image")
    print("  undo restored the clear on both clients too")

    assert len(admin_api.canvas_objects(channel_id)) == 2, \
        "the server does not hold both objects after the restore"


def reload_persists(client, channel):
    """A fresh reload, not a reopen: drops every in-memory cache and the
    local drift database's cursor alike, so a right answer here can only
    come from a real cold fetch of the server's own rows.
    """
    origin = client.ev("location.origin")
    client.go_away()
    client.come_back(f"{origin}/#/channels")
    client.click(channel)
    client.wait_for(L.COMPOSER)
    client.click(L.OPEN_CANVAS)
    client.wait_for("1 stroke, 1 image", timeout=30)
    client.shot("canvas-after-reload")
    print(f"  after a full reload, {client.name} still sees both objects")


def close_on_both(a, b):
    for c in (a, b):
        c.click(L.CLOSE_CANVAS)
        c.wait_for(L.COMPOSER)
