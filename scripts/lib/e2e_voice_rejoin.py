# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Re-clicking a voice channel already left rejoins it, checked at the SFU.

Split out of e2e_voice.py to keep that file under the review budget; it
imports the helpers below rather than duplicating them, the same shape
e2e_canvas_shapes.py already uses against e2e_canvas.py.
"""
import time

import e2e_labels as L
from e2e_voice import _tap_label, participants_with_mics


def _click_channel_row(client, channel, timeout=90):
    """A plain `client.click(channel)` risks landing on the row's own
    kebab ('Manage <channel>') instead of the row, once the roster grows
    a participant count and the row's own text stops being an exact match
    ('lounge' becomes 'lounge\\n1') - `e2e_js.click`'s containment rule
    then prefers the kebab, since it sits nested inside the row's own
    tappable container, the same rule that correctly favours a reply's
    quote button over its enclosing row for a different search. Picking
    the row by its own name as a *prefix* sidesteps that rule entirely,
    without touching it and risking every other scenario that depends on
    it: `join_call`'s own first click of this channel worked precisely
    because the roster was still empty then, and this is that same click
    repeated once the roster is not.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        for n in client.nodes():
            if n["t"].lower().startswith(channel.lower()):
                client.tap(n["x"], n["y"])
                time.sleep(1.5)
                return
        time.sleep(1)
    raise AssertionError(f"{client.name}: no row named {channel!r} found")


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
    _click_channel_row(client, channel)
    parts = participants_with_mics(room_id, expected=1)
    assert len(parts) == 1, \
        f"SFU has {len(parts)} participants after rejoining, expected 1"
    assert parts[0]["state"] == "ACTIVE", f'{parts[0]["identity"]} is {parts[0]["state"]}'
    print(f"  {client.name} rejoined by re-clicking the channel already "
          f"left, confirmed ACTIVE at the SFU")
    _tap_label(client, L.LEAVE_CALL, settle=4)
    print(f"  and {client.name} left again, so no call is left open")
