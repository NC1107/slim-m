# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for e2e_sweep's read-state and sync checks.

`devices_and_read_state` used to assert only `is not None` on both the read
state and sync answers, which a server that echoes well-formed but wrong JSON
still passes. `_StubApi` plays exactly that server, and this pins that the
checks now catch it rather than merely checking a response arrived.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_sweep  # noqa: E402


class _StubApi:
    """Answers just enough of the Api surface devices_and_read_state uses."""

    def __init__(self, read_state, sync_messages):
        self._read_state = read_state
        self._sync_messages = sync_messages

    def call(self, method, path, body=None):
        if path == "/devices":
            return {"devices": [{"id": "device-1"}]}
        if path.endswith("/read"):
            return self._read_state
        if path == "/sync":
            channel_id = body["scopes"][0]["channel_id"]
            return {"scopes": [{
                "channel_id": channel_id,
                "messages": self._sync_messages,
                "has_more": False,
                "reset": False,
            }]}
        raise AssertionError(f"unexpected call: {method} {path}")

    def messages(self, channel_id):
        return [{"id": "msg-1", "seq": 7}]


class DevicesAndReadStateTest(unittest.TestCase):
    def test_passes_when_the_server_actually_advanced_the_marker(self):
        api = _StubApi(
            read_state={"last_read_seq": 7, "unread": 0},
            sync_messages=[{"id": "msg-1", "seq": 7}],
        )
        e2e_sweep.devices_and_read_state(api, "chan-1")

    def test_fails_when_the_read_marker_did_not_move(self):
        api = _StubApi(
            read_state={"last_read_seq": 0, "unread": 4},
            sync_messages=[{"id": "msg-1", "seq": 7}],
        )
        with self.assertRaises(AssertionError):
            e2e_sweep.devices_and_read_state(api, "chan-1")

    def test_fails_when_sync_omits_the_message_it_claims_to_carry(self):
        api = _StubApi(
            read_state={"last_read_seq": 7, "unread": 0},
            sync_messages=[],
        )
        with self.assertRaises(AssertionError):
            e2e_sweep.devices_and_read_state(api, "chan-1")


if __name__ == "__main__":
    unittest.main()
