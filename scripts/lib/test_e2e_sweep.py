# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for e2e_sweep's read-state and sync checks.

`devices_and_read_state` used to assert only `is not None` on both the read
state and sync answers, which a server that echoes well-formed but wrong JSON
still passes. It also read `api.messages(channel_id)[-1]` as "the latest
message", while `GET /channels/{id}/messages` answers newest-first, so `[-1]`
named the oldest row on the page rather than the newest.

`_StubApi` plays a server closely enough to catch both: `messages()` answers
a multi-message, newest-first list, and a mark-read applies `MAX(current,
seq)`, the same clamp `store/read_state.rs` uses, rather than a test author
handing back a hand-picked read state that cannot tell `[0]` from `[-1]`.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_sweep  # noqa: E402


def _messages_newest_first(count=6):
    """Seq descending, matching `ORDER BY m.seq DESC` on the real route."""
    return [{"id": f"msg-{i}", "seq": i} for i in range(count, 0, -1)]


class _StubApi:
    """A server whose read-state and sync answers derive from its own state,
    rather than from a value a test handed back for the caller to compare
    itself against.
    """

    def __init__(self, messages, last_read_seq=0,
                 broken_read=False, broken_sync=False):
        self._messages = messages
        self._last_read_seq = last_read_seq
        self._broken_read = broken_read
        self._broken_sync = broken_sync

    def call(self, method, path, body=None):
        if path == "/devices":
            return {"devices": [{"id": "device-1"}]}
        if path.endswith("/read"):
            return self._read(method, body)
        if path == "/sync":
            return self._sync(body)
        raise AssertionError(f"unexpected call: {method} {path}")

    def _read(self, method, body):
        if method == "PUT":
            if not self._broken_read:
                self._last_read_seq = max(self._last_read_seq, body["seq"])
            return {}
        unread = sum(1 for m in self._messages
                     if m["seq"] > self._last_read_seq)
        return {"last_read_seq": self._last_read_seq, "unread": unread}

    def _sync(self, body):
        after_seq = body["scopes"][0]["after_seq"]
        carried = [] if self._broken_sync else [
            m for m in reversed(self._messages) if m["seq"] > after_seq]
        return {"scopes": [{
            "channel_id": body["scopes"][0]["channel_id"],
            "messages": carried,
            "has_more": False,
            "reset": False,
        }]}

    def messages(self, channel_id):
        return self._messages


class DevicesAndReadStateTest(unittest.TestCase):
    def test_passes_when_nothing_has_been_read_yet(self):
        api = _StubApi(_messages_newest_first())
        e2e_sweep.devices_and_read_state(api, "chan-1")

    def test_passes_when_the_marker_was_already_at_the_newest_seq(self):
        """Reproduces the live scenario: the sweep's own account has
        already marked the channel read up to its newest message (the
        browser client shares the account), before the sweep runs.

        Marking read to the *oldest* message here would be a no-op against
        an already-current marker, so this is the case that actually
        distinguishes reading index 0 from index -1: both pass against an
        unread channel, only this one tells them apart.
        """
        api = _StubApi(_messages_newest_first(), last_read_seq=6)
        e2e_sweep.devices_and_read_state(api, "chan-1")

    def test_fails_when_the_server_never_advances_the_marker(self):
        api = _StubApi(_messages_newest_first(), broken_read=True)
        with self.assertRaises(AssertionError):
            e2e_sweep.devices_and_read_state(api, "chan-1")

    def test_fails_when_sync_omits_the_message_it_claims_to_carry(self):
        api = _StubApi(_messages_newest_first(), broken_sync=True)
        with self.assertRaises(AssertionError):
            e2e_sweep.devices_and_read_state(api, "chan-1")


if __name__ == "__main__":
    unittest.main()
