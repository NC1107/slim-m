# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for the shared REST client's request shape.

No network here: `urllib.request.urlopen` is patched out, and every test
inspects the `Request` object that would have been sent rather than any
real response. What matters is what leaves the process, not what a server
does with it.
"""
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_api  # noqa: E402


def _fake_response(payload=b"{}"):
    response = Mock()
    response.read.return_value = payload
    response.__enter__ = Mock(return_value=response)
    response.__exit__ = Mock(return_value=False)
    return response


class UserAgentTest(unittest.TestCase):
    """Cloudflare answers a default urllib UA with a 403; see CLAUDE.md."""

    def test_every_call_carries_a_non_default_user_agent(self):
        api = e2e_api.Api("https://example.invalid")
        with patch("urllib.request.urlopen", return_value=_fake_response()) as mock_open:
            api.call("GET", "/version")
        request = mock_open.call_args[0][0]
        self.assertEqual(request.get_header("User-agent"), e2e_api.USER_AGENT)
        self.assertNotIn("python-urllib", request.get_header("User-agent").lower())

    def test_the_user_agent_survives_alongside_an_auth_header(self):
        api = e2e_api.Api("https://example.invalid", token="secret-token")
        with patch("urllib.request.urlopen", return_value=_fake_response()) as mock_open:
            api.call("GET", "/me")
        request = mock_open.call_args[0][0]
        self.assertEqual(request.get_header("User-agent"), e2e_api.USER_AGENT)
        self.assertEqual(request.get_header("Authorization"), "Bearer secret-token")

    def test_an_unauthenticated_version_probe_still_carries_it(self):
        # version() builds a second, tokenless Api rather than reusing self.
        api = e2e_api.Api("https://example.invalid", token="secret-token")
        with patch("urllib.request.urlopen", return_value=_fake_response()) as mock_open:
            api.version()
        request = mock_open.call_args[0][0]
        self.assertEqual(request.get_header("User-agent"), e2e_api.USER_AGENT)
        self.assertIsNone(request.get_header("Authorization"))


if __name__ == "__main__":
    unittest.main()
