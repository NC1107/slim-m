# SPDX-License-Identifier: Apache-2.0
"""Starting a DM from the member list, then holding a call inside it.

There is no "+" affordance on the DM rail section (deliberately not built,
per CLAUDE.md); the only way to start a fresh DM is "Message" on a member's
own profile popover, reached from the member pane. Once the DM exists, a
call inside it is the same `VoiceScreen` a real voice channel uses (PR #306),
reached through the DM header's own "Call" button rather than a rail row,
and published to LiveKit under `channel-<dmChannelId>` - the same
`room_for_channel` scheme every channel kind already shares - so this reuses
e2e_voice's SFU checks rather than duplicating them.

Bob reaches the DM by its channel id rather than by clicking its rail row:
once alice has opened it, "Bob"/"Alice" name both a member-pane row and a
Direct-messages rail row with the identical text, and this harness's click()
picks whichever tappable match sorts first - not something worth resting a
scenario on when the server can just be asked for the id it already knows.

Run after the shared 'lounge' voice scenarios rather than beside them, so a
call already open in one room can never collide with the other.
"""
import time

import e2e_labels as L
from e2e_voice import sfu_participants, tracks_of


def start_dm_and_call(a, b, admin_api, member_api):
    """Alice starts a DM with Bob, then both hold and leave a call in it."""
    a.click('Bob', settle=2)
    a.click(L.START_DM, settle=3)
    a.wait_for(L.COMPOSER)
    text = f'hello over a fresh dm {int(time.time())}'
    a.type_into(L.COMPOSER, text)
    a.click(L.SEND, settle=2)
    a.wait_for(text)
    print("  alice opened a DM with bob from the member list and sent a message")

    deadline = time.time() + 20
    conversation = None
    while time.time() < deadline and conversation is None:
        rows = member_api.call('GET', '/dms')
        conversation = next(
            (c for c in rows if c['user']['display_name'] == 'Alice'), None)
        if conversation is None:
            time.sleep(1)
    assert conversation, "bob's own /dms never listed the conversation alice opened"
    channel_id = conversation['channel_id']
    print(f"  bob's own account already lists the DM: {channel_id}")

    b.ev(f"location.hash = '#/channels/{channel_id}'")
    b.wait_for(text, timeout=30)
    print("  and the message alice sent is live in it")

    room_id = f'channel-{channel_id}'
    for c in (a, b):
        c.click(L.DM_CALL, settle=2)
        c.click(L.JOIN_CALL, settle=8)
        c.wait_for(L.IN_CALL)
    for c in (a, b):
        c.wait_for('2 in call')
    a.shot('dm-in-call')
    print("  both clients joined the DM's own call")

    parts = sfu_participants(room_id)
    assert len(parts) == 2, f"the DM's SFU room has {len(parts)}, expected 2"
    for p in parts:
        mics = tracks_of(p, 'MICROPHONE')
        assert p['state'] == 'ACTIVE', f'{p["identity"]} is {p["state"]}'
        assert mics, f'{p["identity"]} published no microphone track'
    print("  and the SFU room named after this DM's channel id has both, ACTIVE")

    a.click(L.LEAVE_CALL, settle=8)
    b.wait_for('1 in call')
    b.shot('dm-peer-left')
    print("  leaving dropped the other side to 1 in call")
