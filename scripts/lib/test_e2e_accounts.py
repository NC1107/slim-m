# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for e2e_accounts' push preview check.

The switch is account-wide since #1583, so a second device must see the first
one's choice. These stub a server that keeps the choice per device, as it did
before, and pin that the check fails on it, and that a healthy one leaves the
account back at the default.
"""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_accounts  # noqa: E402


class _Server:
    """A /push/preview that is shared across logins, or kept per login."""

    def __init__(self, shared):
        self.shared = shared
        self.value = {None: True}
        self.logins = 0

    def api(self, base, token=None):
        return _Api(self, token)


class _Api:
    def __init__(self, server, token):
        self.server = server
        self.token = token

    def login(self, username, password, device="e2e"):
        self.server.logins += 1
        self.token = "shared" if self.server.shared else f"d{self.server.logins}"

    def call(self, method, path, body=None):
        values = self.server.value
        key = None if self.server.shared else self.token
        if method == "PUT":
            values[key] = body["include_content"]
        return {"include_content": values.get(key, True)}


class PushPreviewTest(unittest.TestCase):
    def _run(self, shared):
        server = _Server(shared)
        with patch.object(e2e_accounts, "Api", server.api):
            e2e_accounts.push_preview_is_account_wide("http://x", "pw")
        return server

    def test_an_account_wide_choice_passes_and_is_restored(self):
        server = self._run(shared=True)
        self.assertTrue(server.value[None])

    def test_a_per_device_choice_is_caught(self):
        with self.assertRaises(AssertionError):
            self._run(shared=False)


if __name__ == "__main__":
    unittest.main()
