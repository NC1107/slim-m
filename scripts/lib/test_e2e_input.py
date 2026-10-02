# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for e2e_input's key events.

Flutter derives which modifiers are down from the modifier keys themselves, not
from the flag on a character's event, so a Shift+Tab sent as one flagged key
reads as a plain Tab and indents instead of outdenting. These pin that the
modifier is pressed as a key of its own, around the key it modifies.
"""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_input  # noqa: E402


class _Recorder:
    def __init__(self):
        self.sent = []

    def send(self, method, params=None):
        self.sent.append((method, params))

    def gestures(self, on):
        self.sent.append(("gestures", on))


def _keys(client):
    return [(p["type"], p["key"]) for m, p in client.sent
            if m == "Input.dispatchKeyEvent"]


class PressTest(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(e2e_input.time, "sleep")
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_a_plain_key_is_one_down_and_one_up(self):
        client = _Recorder()
        e2e_input.press(client, "Tab")
        self.assertEqual(_keys(client), [("keyDown", "Tab"), ("keyUp", "Tab")])

    def test_shift_is_a_key_pressed_around_the_key(self):
        client = _Recorder()
        e2e_input.press(client, "Tab", shift=True)
        self.assertEqual(_keys(client), [
            ("keyDown", "Shift"), ("keyDown", "Tab"),
            ("keyUp", "Tab"), ("keyUp", "Shift")])

    def test_the_flag_is_set_while_shift_is_down_and_clear_after(self):
        client = _Recorder()
        e2e_input.press(client, "Tab", shift=True)
        flags = [p["modifiers"] for _, p in client.sent]
        self.assertEqual(flags, [8, 8, 8, 0])

    def test_enter_carries_its_text_so_it_reads_as_a_character(self):
        client = _Recorder()
        e2e_input.press(client, "Enter")
        down = client.sent[0][1]
        self.assertEqual(down["text"], "\r")

    def test_clearing_a_field_selects_all_then_deletes(self):
        client = _Recorder()
        e2e_input.clear_field(client)
        self.assertEqual(_keys(client), [
            ("keyDown", "Control"), ("keyDown", "a"), ("keyUp", "a"),
            ("keyUp", "Control"),
            ("keyDown", "Backspace"), ("keyUp", "Backspace")])


class PointerTest(unittest.TestCase):
    def test_a_hold_releases_the_semantics_layer_even_if_a_send_fails(self):
        class Failing(_Recorder):
            def hover(self, x, y, settle=0):
                raise RuntimeError("socket closed")

        client = Failing()
        with self.assertRaises(RuntimeError):
            e2e_input.hold(client, 10, 10)
        self.assertEqual(client.sent[-1], ("gestures", False))


if __name__ == "__main__":
    unittest.main()
