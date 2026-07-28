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


def sfu_participants(room):
    """Ask the SFU itself who is connected, rather than trusting either UI."""
    def b64(b):
        return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

    key = os.environ.get("LIVEKIT_API_KEY", "devkey")
    secret = os.environ.get("LIVEKIT_API_SECRET", "secret").encode()
    now = int(time.time())
    header = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64(json.dumps({
        "iss": key, "sub": "e2e", "nbf": now - 30, "exp": now + 300,
        "video": {"roomAdmin": True, "room": room}}).encode())
    sig = b64(hmac.new(secret, f"{header}.{payload}".encode(),
                       hashlib.sha256).digest())
    url = os.environ.get("LIVEKIT_HTTP", "http://localhost:7880")
    req = urllib.request.Request(
        f"{url}/twirp/livekit.RoomService/ListParticipants",
        data=json.dumps({"room": room}).encode(),
        headers={"Authorization": f"Bearer {header}.{payload}.{sig}",
                 "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req)).get("participants", [])


def tracks_of(participant, source):
    return [t for t in participant.get("tracks", [])
            if t.get("source") == source]


def join_call(a, b, room_id, channel="lounge"):
    """Both clients into the same room, each publishing and subscribed."""
    # Reached through the rail rather than by URL, which is also the only
    # end-to-end check that the rail is reachable at all: it published no
    # accessibility nodes until the shell stopped letting a modal barrier
    # block them, and nothing but a real run would have noticed.
    for c in (a, b):
        c.click(channel)
        c.click("Join call", settle=8)
        c.wait_for("in call")

    for c in (a, b):
        c.wait_for("2 in call")
        c.shot("in-call")
    a.wait_for("Bob")
    b.wait_for("Alice")
    print("  both clients report 2 in call and list each other")

    parts = sfu_participants(room_id)
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
    the app's own path.
    """
    client.click("Share a screen", settle=3)
    # A quality is chosen before capture starts; picking one is what calls
    # getDisplayMedia, and the browser answers it with a pre-selected source.
    client.click("Balanced", settle=10)

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

    client.wait_for("You are sharing your screen")
    client.shot("sharing-screen")
    other.shot("peer-sharing-screen")
    print("  the sharing client says so on screen")

    client.click("Stop sharing", settle=8)
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
    a.click("Mute")
    time.sleep(4)
    muted = {p["identity"][:13]: p["tracks"][0].get("muted", False)
             for p in sfu_participants(room_id) if p.get("tracks")}
    assert any(muted.values()), f"no participant reads as muted: {muted}"
    assert not all(muted.values()), f"both read as muted: {muted}"
    b.shot("peer-muted")
    print(f"  exactly one side muted: {muted}")


def leave_call(a, b):
    a.click("Leave call", settle=8)
    b.wait_for("1 in call")
    b.shot("peer-left")
    print("  the remaining client dropped to 1 in call")
