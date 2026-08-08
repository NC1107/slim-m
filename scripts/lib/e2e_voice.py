# SPDX-License-Identifier: Apache-2.0
"""A real voice call across two web clients, checked on both sides.

Every claim is checked twice over: once against what each client renders, and
once against what the SFU itself reports, because a roster that looks right is
not evidence that a track was ever published.
"""
import base64
import hashlib
import hmac
import json
import os
import time
import urllib.request

import e2e_api
import e2e_labels as L


def sfu_participants(room):
    """Ask the SFU itself who is connected, rather than trusting either UI."""
    def b64(b):
        return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

    # Required rather than defaulted: e2e.sh always exports both, and a
    # guessable fallback would quietly sign tokens for whatever SFU answered.
    key = os.environ["LIVEKIT_API_KEY"]
    secret = os.environ["LIVEKIT_API_SECRET"].encode()
    now = int(time.time())
    header = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64(json.dumps({
        "iss": key, "sub": "e2e", "nbf": now - 30, "exp": now + 300,
        "video": {"roomAdmin": True, "room": room}}).encode())
    sig = b64(hmac.new(secret, f"{header}.{payload}".encode(),
                       hashlib.sha256).digest())
    url = os.environ.get("LIVEKIT_HTTP", "http://localhost:7880")
    # e2e_api.py's Cloudflare UA workaround applies here too, if ever pointed off-localhost.
    req = urllib.request.Request(
        f"{url}/twirp/livekit.RoomService/ListParticipants",
        data=json.dumps({"room": room}).encode(),
        headers={"Authorization": f"Bearer {header}.{payload}.{sig}",
                 "Content-Type": "application/json",
                 "User-Agent": e2e_api.USER_AGENT})
    return json.load(urllib.request.urlopen(req)).get("participants", [])


def tracks_of(participant, source):
    return [t for t in participant.get("tracks", [])
            if t.get("source") == source]


def participants_with_mics(room_id, expected=2, timeout=25):
    """The room's participants, once every one of them is publishing a mic.

    "N in call" on screen means the client joined, which the SFU learns
    before the microphone track is published, so reading the roster the
    instant that label appears is a race the caller happens to win or lose.
    The plain-voice path won it and the DM path did not, which read as a DM
    bug rather than as the timing it was. Polling is what makes both honest;
    the assertions the callers run afterwards are unchanged, so a genuinely
    missing track still fails, just after a real wait rather than instantly.
    """
    deadline = time.time() + timeout
    parts = []
    while time.time() < deadline:
        parts = sfu_participants(room_id)
        if (len(parts) == expected
                and all(tracks_of(p, "MICROPHONE") for p in parts)):
            return parts
        time.sleep(1)
    return parts


def join_call(a, b, room_id, channel=L.VOICE_CHANNEL):
    """Both clients into the same room, each publishing and subscribed.

    Clicking a voice channel joins it directly (PR #354 removed the join
    lobby), so the click that used to open a preview is the join itself, and
    the wait for L.IN_CALL is what proves the connect actually completed.
    """
    # Reached through the rail rather than by URL, which is also the only
    # end-to-end check that the rail is reachable at all: it published no
    # accessibility nodes until the shell stopped letting a modal barrier
    # block them, and nothing but a real run would have noticed.
    for c in (a, b):
        c.click(channel)
        c.wait_for(L.IN_CALL)

    for c in (a, b):
        c.wait_for("2 in call")
        c.shot("in-call")
    a.wait_for("Bob")
    b.wait_for("Alice")
    print("  both clients report 2 in call and list each other")

    parts = participants_with_mics(room_id)
    assert len(parts) == 2, f"SFU has {len(parts)} participants, expected 2"
    for p in parts:
        mics = tracks_of(p, "MICROPHONE")
        assert p["state"] == "ACTIVE", f'{p["identity"]} is {p["state"]}'
        assert mics, f'{p["identity"]} published no microphone track'
        assert not mics[0].get("muted"), f'{p["identity"]} is muted on join'
        print(f'  {p["identity"][:13]} ACTIVE, mic published unmuted')


def share_screen(client, other, room_id):
    """Publish a screen track, and see the other side told about it.

    The browser is started with a capture source pre-selected, so the picker
    the operating system would raise never appears; everything after that is
    the app's own path. PR #348 removed the in-call quality dialog this used
    to click through ("Balanced"): quality is read from saved Voice settings
    now, so a click on Share a screen calls getDisplayMedia directly with no
    further interaction, on web where `screenShareNeedsSource` is false.
    """
    client.click(L.SHARE_SCREEN, settle=10)

    deadline = time.time() + 45
    shared = None
    while time.time() < deadline:
        for p in sfu_participants(room_id):
            if tracks_of(p, "SCREEN_SHARE"):
                shared = p
                break
        if shared:
            break
        time.sleep(2)
    assert shared, "no screen-share track ever reached the SFU"
    print(f'  {shared["identity"][:13]} is publishing a screen track')

    client.wait_for(L.SHARING_NOTICE)
    client.shot("sharing-screen")
    other.shot("peer-sharing-screen")
    print("  the sharing client says so on screen")

    client.click(L.STOP_SHARING, settle=8)
    deadline = time.time() + 30
    while time.time() < deadline:
        live = [p for p in sfu_participants(room_id)
                if tracks_of(p, "SCREEN_SHARE")]
        if not live:
            break
        time.sleep(2)
    assert not [p for p in sfu_participants(room_id)
                if tracks_of(p, "SCREEN_SHARE")], "the screen track stayed up"
    print("  and stopping it takes the track down")


def mute_propagates(a, b, room_id):
    """One side mutes and the SFU reflects it, then the mute is undone.

    Muting is a persisted preference, not a per-call toggle: leaving a call
    muted carries `microphoneEnabled: false` into VoiceController's next
    `join` (see voice_screen.dart's own doc comment), so a mute left standing
    here would silently carry into whatever call this same client joins
    next, publishing no microphone track at all rather than a muted one.
    Unmuting before returning is this scenario cleaning up after itself, the
    same shape leave_call's own trailing leave already does for the rail.
    """
    a.click(L.MUTE)
    time.sleep(4)
    muted = {p["identity"][:13]: p["tracks"][0].get("muted", False)
             for p in sfu_participants(room_id) if p.get("tracks")}
    assert any(muted.values()), f"no participant reads as muted: {muted}"
    assert not all(muted.values()), f"both read as muted: {muted}"
    b.shot("peer-muted")
    print(f"  exactly one side muted: {muted}")

    a.click(L.UNMUTE)
    time.sleep(4)
    unmuted = {p["identity"][:13]: p["tracks"][0].get("muted", False)
               for p in sfu_participants(room_id) if p.get("tracks")}
    assert not any(unmuted.values()), f"still reads as muted: {unmuted}"
    print("  and unmuting clears it, so the next call this client joins starts unmuted")


def canvas_keeps_call_controls(client, room_id, channel=L.VOICE_CHANNEL):
    """Opening the canvas from inside a call must not cost the call its own
    controls - the owner's own report, and the reason #460 built one shared
    dock. `ConversationPane`'s stage ternary still swaps `VoiceScreen` out
    entirely the instant the canvas opens (home_shell.dart), so the call's
    controls can only still be on screen if the *canvas's own* dock carries
    them: `CanvasCallDock` renders a call row only when the canvas's own
    channel matches the call's, which is why this opens the canvas from the
    voice channel's own wide header rather than the text channel the other
    canvas scenarios in this run use.

    Deliberately never closes the canvas before returning. It did once, and
    that one extra `Client.click(L.CLOSE_CANVAS)` made the very next
    scenario's own `Leave call` click - a real, correctly-found
    `flt-tappable` node, unrelated to the semantics-exposure bug
    `canvas_object_context_menu.dart`'s own fix closed - silently do
    nothing for anywhere between a few seconds and over twenty, reproduced
    across several clean runs. `leave_call` (the next scenario) still
    proves hanging up works, from the ordinary call screen; what this
    scenario needs to prove is only that mute and hang-up survive the
    canvas opening, which the dock while it is still open already answers
    without ever triggering `ConversationPane`'s stage swap back.
    """
    client.click(L.OPEN_CANVAS)
    client.wait_for("no objects")
    client.wait_for(L.MUTE)
    client.wait_for(L.LEAVE_CALL)
    client.shot("canvas-with-call-dock")
    print(f"  {client.name}: mute and leave call stayed reachable "
          f"with the canvas open")

    client.click(L.MUTE)
    time.sleep(3)
    muted = {p["identity"][:13]: p["tracks"][0].get("muted", False)
             for p in sfu_participants(room_id) if p.get("tracks")}
    assert any(muted.values()), \
        f"muting from inside the canvas's own dock never reached the SFU: {muted}"
    client.wait_for(L.UNMUTE)

    client.click(L.UNMUTE)
    time.sleep(3)
    unmuted = {p["identity"][:13]: p["tracks"][0].get("muted", False)
               for p in sfu_participants(room_id) if p.get("tracks")}
    assert not any(unmuted.values()), \
        f"unmuting from inside the canvas's own dock never reached the SFU: {unmuted}"
    print(f"  {client.name}: mute still reaches the SFU with the canvas open")


def leave_call(a, b):
    """Both sides leave: the drop to 1 proves the count, then a real empty room."""
    a.click(L.LEAVE_CALL, settle=8)
    b.wait_for("1 in call")
    b.shot("peer-left")
    print("  the remaining client dropped to 1 in call")
    # A lingering call here reads as "in call" on b's own rail summary too,
    # which would let the next scenario's own IN_CALL wait pass on nothing.
    b.click(L.LEAVE_CALL, settle=4)
    print("  and the remaining client leaves too, so no call is left open")


def rejoin_after_leaving(client, room_id, channel=L.VOICE_CHANNEL):
    """Re-clicking a voice channel already left rejoins it rather than
    stranding the caller on a dead rejoin screen with nothing to press.

    PR #469's second fix: `VoiceScreen`'s own auto-join guard cannot tell a
    re-click of the same channel apart from an incidental ancestor rebuild,
    so the row asks `voiceChannelTapShouldRejoin` directly instead. Checked
    at the SFU rather than a screen label: the caller's canvas is still
    open from the earlier media-slot scenario, and `L.IN_CALL`/"N in call"
    both live in `CallStageLayout`, which the canvas dock replaces rather
    than sits beside while open - the same reason `e2e_media_slots.py`
    checks the SFU directly too.
    """
    client.click(channel)
    parts = participants_with_mics(room_id, expected=1)
    assert len(parts) == 1, \
        f"SFU has {len(parts)} participants after rejoining, expected 1"
    assert parts[0]["state"] == "ACTIVE", f'{parts[0]["identity"]} is {parts[0]["state"]}'
    print(f"  {client.name} rejoined by re-clicking the channel already "
          f"left, confirmed ACTIVE at the SFU")
    client.wait_for(L.LEAVE_CALL)
    client.click(L.LEAVE_CALL, settle=4)
    print(f"  and {client.name} left again, so no call is left open")
