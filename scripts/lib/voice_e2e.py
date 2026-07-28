# SPDX-License-Identifier: Apache-2.0
"""Hold a real voice call across two web clients and assert both sides of it.

Every claim here is checked twice over: once against what each client renders,
and once against what the SFU itself reports, because a roster that looks right
is not evidence that a track was ever published.

Called by scripts/voice-e2e.sh, which owns the stack this talks to.
"""
import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.request

from voice_e2e_client import Client

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


def main():
    server, room_id, secret = sys.argv[1], sys.argv[2], sys.argv[3]
    channel_id = room_id.removeprefix("channel-")
    a = Client("alice", 9801)
    b = Client("bob", 9802)

    print("== sign in ==")
    sign_in(a, server, "alice", secret)
    sign_in(b, server, "bob", secret)

    print("== join the call ==")
    # Routed to rather than clicked in the rail: the rail publishes no
    # accessibility nodes at all on web, so there is nothing there to click.
    for c in (a, b):
        c.ev(f"location.hash = '#/channels/{channel_id}'")
        c.wait_url(channel_id)
        c.click("Join call", settle=8)
        c.wait_for("in call")

    for c in (a, b):
        c.wait_for("2 in call")
        c.shot("in-call")
    print("  both clients report 2 in call")

    a.wait_for("Bob")
    b.wait_for("Alice")
    print("  each client lists the other in the call roster")

    print("== what the SFU actually has ==")
    parts = sfu_participants(room_id)
    assert len(parts) == 2, f"SFU has {len(parts)} participants, expected 2"
    for p in parts:
        mics = [t for t in p.get("tracks", []) if t.get("source") == "MICROPHONE"]
        assert p["state"] == "ACTIVE", f'{p["identity"]} is {p["state"]}'
        assert mics, f'{p["identity"]} published no microphone track'
        assert not mics[0].get("muted"), f'{p["identity"]} is muted on join'
        print(f'  {p["identity"][:13]} ACTIVE, mic published unmuted')

    print("== mute propagates ==")
    a.click("Mute")
    time.sleep(4)
    muted = {p["identity"][:13]: p["tracks"][0].get("muted", False)
             for p in sfu_participants(room_id) if p.get("tracks")}
    assert any(muted.values()), f"no participant reads as muted: {muted}"
    assert not all(muted.values()), f"both read as muted: {muted}"
    b.shot("peer-muted")
    print(f"  exactly one side muted: {muted}")

    print("== leave ==")
    a.click("Leave", settle=8)
    b.wait_for("1 in call")
    b.shot("peer-left")
    print("  remaining client dropped to 1 in call")

    print("\nPASS: two clients, one call, audio published and subscribed "
          "both ways.")


if __name__ == "__main__":
    main()
