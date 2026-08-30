# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for e2e_settings' theme and status persistence checks.

`change_theme` and `change_status` used to stop at the control relabelling
itself, which a Riverpod state change produces whether or not anything was
actually written to storage or the server. These stub a UI that relabels but
never persisted, and pin that the checks now catch it.
"""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_settings  # noqa: E402


class _FakeClient:
    """Answers just enough of the Client surface these two functions use."""

    def __init__(self, stored_theme):
        self._stored_theme = stored_theme

    def ev(self, expr):
        if 'location.href' in expr:
            return '#/settings'
        if 'localStorage' in expr:
            return self._stored_theme
        return None

    def find(self, label, field=None):
        return None

    def click(self, label, settle=1.5):
        pass

    def wait_for(self, label, timeout=None, field=None):
        return {'t': label}


class _FakeApi:
    def __init__(self, status):
        self._status = status
        self.user_id = 'user-1'

    def me(self):
        return {'id': self.user_id}

    def call(self, method, path, body=None):
        assert path == f'/presence?ids={self.user_id}'
        return [{'user_id': self.user_id, 'status': self._status}]


class ChangeThemeTest(unittest.TestCase):
    def test_passes_when_the_choice_was_written_to_storage(self):
        e2e_settings.change_theme(_FakeClient(stored_theme='dark'))

    def test_fails_when_nothing_durable_recorded_the_choice(self):
        # The control still relabelled; storage never saw the write.
        with self.assertRaises(AssertionError):
            e2e_settings.change_theme(_FakeClient(stored_theme=None))


class ChangeStatusTest(unittest.TestCase):
    """The control still relabels even when the PATCH never took effect."""

    def test_passes_when_the_server_agrees(self):
        e2e_settings.change_status(
            _FakeClient(stored_theme=None), _FakeApi(status='dnd'))

    def test_fails_when_the_server_never_saw_the_change(self):
        # time.time is stubbed so the 20-second poll below is not real time.
        with patch.object(
            e2e_settings.time, 'time', side_effect=[0, 5, 25]
        ), patch.object(e2e_settings.time, 'sleep'):
            with self.assertRaises(AssertionError):
                e2e_settings.change_status(
                    _FakeClient(stored_theme=None), _FakeApi(status='online'))


if __name__ == '__main__':
    unittest.main()
