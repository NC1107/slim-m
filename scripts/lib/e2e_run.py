# SPDX-License-Identifier: Apache-2.0
"""Drive two web clients through the product, and check the server agrees.

The scenarios run in one session against one deployment, in the order a person
would meet them: sign in, talk, react, attach, change your settings, administer
the Space, then hold a call. Each lives in its own module; this file is the
running order and nothing else.

Called by scripts/e2e.sh, which owns the stack this talks to.
"""
import os
import sys
import tempfile
import time
import traceback

import e2e_admin
import e2e_canvas
import e2e_canvas_shapes
import e2e_labels as L
import e2e_media_slots
import e2e_messaging
import e2e_markdown
import e2e_dm_call
import e2e_reconcile
import e2e_replies
import e2e_settings
import e2e_coverage
import e2e_sweep
import e2e_threads
import e2e_voice
import e2e_voice_rejoin
import e2e_api
from e2e_api import Api
from e2e_client import Client

# A private directory when unset, rather than a guessable shared one; e2e.sh
# always sets it to a directory inside the run's own work area.
FIXTURES = os.environ.get("E2E_FIXTURES") or tempfile.mkdtemp(prefix="e2e-")


def sign_in(client, server, username, password):
    client.enable_semantics()
    client.click("Connect to a Space")
    client.type_into("Server address", server)
    client.click("Continue")
    client.click("It matches")
    client.type_into("Username", username)
    client.type_into("Password", password)
    client.click("Sign in", settle=6)
    client.wait_url("#/channels")
    print(f"  {client.name}: signed in as {username}")


def go_home(client):
    if "#/channels" not in (client.ev("location.href") or ""):
        client.ev("location.hash = '#/channels'")
        time.sleep(2)


def scenarios(a, b, admin, member, room_id, server):
    """Every scenario, as (name, callable). Named so a failure says which."""
    picture = os.path.join(FIXTURES, "avatar.png")
    upload = os.path.join(FIXTURES, "attachment.png")
    return [
        ("messaging: a message each way", lambda: (
            e2e_messaging.send_and_receive(
                a, b, L.TEXT_CHANNEL, L.FIRST_MESSAGE, admin),
            e2e_messaging.send_and_receive(
                b, a, L.TEXT_CHANNEL, L.REPLY_MESSAGE, admin))),
        ("messaging: a mention", lambda: e2e_messaging.mention(
            a, b, L.TEXT_CHANNEL, "Bob", admin)),
        ("messaging: a reaction", lambda: e2e_messaging.react(
            a, b, L.FIRST_MESSAGE, "grinning face", admin,
            L.TEXT_CHANNEL)),
        ("messaging: an attachment", lambda: e2e_messaging.attach(
            a, b, L.TEXT_CHANNEL, upload, admin)),
        ("messaging: a reply, and a reply to a deleted message",
         lambda: e2e_replies.reply_and_a_deleted_parent(
             a, b, L.TEXT_CHANNEL, admin)),
        ("messaging: a thread stays off the ordinary channel list",
         lambda: e2e_threads.open_reply_and_stay_off_the_rail(
             a, b, L.TEXT_CHANNEL, admin, member)),
        ("markdown: formatting applies without reaching the wire",
         lambda: e2e_markdown.formats_without_storing_the_markers(
             a, b, L.TEXT_CHANNEL, admin)),
        ("markdown: a spoiler keeps its text out of the tree",
         lambda: e2e_markdown.a_spoiler_hides_its_text(
             a, b, L.TEXT_CHANNEL, admin)),
        ("moderation: reporting a message", lambda: e2e_admin.report_a_message(
            member, admin, admin.channel_named(L.TEXT_CHANNEL)["id"],
            L.FIRST_MESSAGE)),
        ("moderation: blocking a member", lambda: e2e_admin.block_and_unblock(
            member, admin.me()["id"])),
        ("moderation: the capability handshake is honest",
         lambda: e2e_admin.capabilities_are_honest(member)),
        ("permissions: the server refuses what the UI hides",
         lambda: e2e_admin.permissions_are_enforced(member, admin)),
        ("settings: personal settings stand alone",
         lambda: e2e_settings.personal_settings_reachable(a)),
        ("settings: a profile picture", lambda: e2e_settings.upload_avatar(
            a, admin, picture)),
        ("settings: theme and status", lambda: (
            e2e_settings.change_theme(a),
            e2e_settings.change_status(a, admin))),
        ("settings: Space settings stand alone",
         lambda: e2e_settings.space_settings_reachable(a)),
        ("settings: who can join", lambda: e2e_settings.change_join_policy(
            a, admin)),
        ("admin: creating a role", lambda: e2e_admin.create_role(a, admin)),
        ("api: the routes the UI scenarios do not reach",
         lambda: e2e_sweep.run_all(
             admin, admin.channel_named(L.TEXT_CHANNEL)["id"],
             member.me()["id"])),
        ("reconcile: an edit and a delete while a client is away",
         lambda: e2e_reconcile.survives_an_absence(
             b, a, L.TEXT_CHANNEL, admin)),
        ("canvas: opening it from the channel header",
         lambda: e2e_canvas.open_on_both(a, b, L.TEXT_CHANNEL)),
        ("canvas: a stroke arrives on the other client live",
         lambda: e2e_canvas.draw_stroke_and_see_it_live(a, b)),
        ("canvas: a pasted image renders, not just a box",
         lambda: e2e_canvas.paste_image_and_hydrate(
             a, b, server, admin, admin.channel_named(L.TEXT_CHANNEL)["id"],
             upload)),
        ("canvas: moving and resizing it converges on both sides",
         lambda: e2e_canvas.move_and_resize_converges(
             a, b, admin, admin.channel_named(L.TEXT_CHANNEL)["id"])),
        ("canvas: a note arrives on the other client live",
         lambda: e2e_canvas_shapes.place_note_and_see_it_live(
             a, b, admin, admin.channel_named(L.TEXT_CHANNEL)["id"])),
        ("canvas: a shape arrives on the other client live",
         lambda: e2e_canvas_shapes.place_shape_and_see_it_live(
             a, b, admin, admin.channel_named(L.TEXT_CHANNEL)["id"])),
        ("canvas: raising a stroke reorders it on both sides",
         lambda: e2e_canvas_shapes.reorder_stroke_and_see_it_live(
             a, b, admin, admin.channel_named(L.TEXT_CHANNEL)["id"])),
        ("canvas: erase, undo, clear, and undo again",
         lambda: e2e_canvas.erase_undo_clear_and_restore(
             a, b, admin, admin.channel_named(L.TEXT_CHANNEL)["id"])),
        ("canvas: placing a shape selects it, and a drag right after moves "
         "it rather than placing a second one",
         lambda: e2e_canvas_shapes.place_then_move_without_switching_tools(
             a, admin, admin.channel_named(L.TEXT_CHANNEL)["id"])),
        ("canvas: a reload proves it actually persisted",
         lambda: e2e_canvas.reload_persists(
             b, L.TEXT_CHANNEL, admin,
             admin.channel_named(L.TEXT_CHANNEL)["id"])),
        ("canvas: closing it", lambda: e2e_canvas.close_on_both(a, b)),
        ("voice: two clients in one call", lambda: e2e_voice.join_call(
            a, b, room_id)),
        ("voice: sharing a screen", lambda: e2e_voice.share_screen(
            a, b, room_id)),
        ("voice: mute reaches the server", lambda: e2e_voice.mute_propagates(
            a, b, room_id)),
        ("voice: the canvas dock keeps mute and hang-up reachable",
         lambda: e2e_voice.canvas_keeps_call_controls(a, room_id)),
        ("voice: a shared camera tile converges and persists",
         lambda: e2e_media_slots.move_converges_and_persists(
             a, b, admin, admin.channel_named(L.VOICE_CHANNEL)["id"],
             room_id)),
        ("voice: leaving", lambda: e2e_voice.leave_call(a, b, room_id)),
        ("voice: re-clicking a channel already left rejoins it",
         lambda: e2e_voice_rejoin.rejoin_after_leaving(a, room_id)),
        ("voice: calling in a dm", lambda: e2e_dm_call.start_dm_and_call(
            a, b, admin, member)),
    ]


def main():
    server, room_id, secret = sys.argv[1], sys.argv[2], sys.argv[3]
    only = os.environ.get("E2E_ONLY")

    a = Client("alice", 9801)
    b = Client("bob", 9802)
    admin = Api(server)
    admin.login("alice", secret, device="e2e-admin")
    member = Api(server)
    member.login("bob", secret, device="e2e-member")

    print("== sign in ==")
    sign_in(a, server, "alice", secret)
    sign_in(b, server, "bob", secret)

    failures = []
    for name, run in scenarios(a, b, admin, member, room_id, server):
        if only and only not in name:
            continue
        print(f"\n== {name} ==")
        try:
            # Every scenario starts from the channel list, so one that ends on
            # a settings screen cannot strand the next one somewhere it cannot
            # see the rail.
            go_home(a)
            go_home(b)
            run()
        except Exception:
            # Kept going rather than stopped: one broken scenario should not
            # hide the state of every one after it, and the run still fails.
            failures.append(name)
            traceback.print_exc()
            print(f"  FAILED: {name}")

    print("\n== what this run actually touched ==")
    touched = set(e2e_api.TOUCHED)
    for client in (a, b):
        try:
            touched |= e2e_coverage.from_browser(client, server)
        except Exception:
            print(f"  (could not read {client.name}'s request log)")
    e2e_coverage.report(touched, os.environ.get(
        "E2E_SCHEMA", "schema/openapi.yaml"))

    print()
    if failures:
        print(f"FAIL: {len(failures)} scenario(s) failed")
        for name in failures:
            print(f"  - {name}")
        raise SystemExit(1)
    print("PASS: every scenario, checked against the server as well as the UI.")


if __name__ == "__main__":
    main()
