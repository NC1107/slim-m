# SPDX-License-Identifier: Apache-2.0
"""Ask the server what actually happened, rather than believing the screen.

Every scenario drives the UI and then checks here. A roster that renders, a
reaction chip that appears, an avatar that shows: none of those are evidence
the server stored anything, and a client that only ever agrees with itself
would pass a run where nothing was persisted at all.
"""
import json
import urllib.error
import urllib.request

# Every path this helper calls, so a run can report the coverage it truly had
# rather than the coverage somebody once wrote down.
TOUCHED = set()


class Api:
    """One signed-in caller's view of the server."""

    def __init__(self, base, token=None):
        self.base = base.rstrip("/")
        self.token = token

    def call(self, method, path, body=None, raw=None, content_type=None):
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        data = raw
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if content_type:
            headers["Content-Type"] = content_type
        TOUCHED.add(path)
        req = urllib.request.Request(f"{self.base}{path}", data=data,
                                     headers=headers, method=method)
        with urllib.request.urlopen(req) as res:
            payload = res.read()
            if not payload:
                return None
            try:
                return json.loads(payload)
            except ValueError:
                return payload

    def status(self, method, path, body=None):  # noqa: D401
        """The status code alone, for the paths whose refusal is the point."""
        try:
            self.call(method, path, body)
            return 200
        except urllib.error.HTTPError as exc:
            return exc.code

    def login(self, username, password, device="e2e"):
        got = self.call("POST", "/auth/login", {
            "username": username, "password": password, "device_name": device})
        self.token = got["access_token"]
        return got

    def me(self):
        return self.call("GET", "/me")

    def channels(self):
        return self.call("GET", "/channels")

    def channel_named(self, name):
        for c in self.channels():
            if c["name"] == name:
                return c
        raise AssertionError(f"no channel named {name!r}")

    def messages(self, channel_id):
        got = self.call("GET", f"/channels/{channel_id}/messages")
        return got["messages"] if isinstance(got, dict) else got

    def message_with(self, channel_id, needle):
        for m in self.messages(channel_id):
            if needle in (m.get("content") or ""):
                return m
        raise AssertionError(f"no message containing {needle!r}")

    def members(self):
        got = self.call("GET", "/members")
        return got["members"] if isinstance(got, dict) else got

    def member_named(self, display_name):
        for m in self.members():
            if m.get("display_name") == display_name:
                return m
        raise AssertionError(f"no member named {display_name!r}")

    def pins(self, channel_id):
        got = self.call("GET", f"/channels/{channel_id}/pins")
        return got["messages"] if isinstance(got, dict) else got

    def reports(self):
        got = self.call("GET", "/reports")
        return got["reports"] if isinstance(got, dict) else got

    def blocks(self):
        got = self.call("GET", "/blocks")
        return got["blocked"] if isinstance(got, dict) else got

    def roles(self):
        got = self.call("GET", "/roles")
        return got["roles"] if isinstance(got, dict) else got

    def space_settings(self):
        return self.call("GET", "/space/settings")

    def version(self):
        return Api(self.base).call("GET", "/version")
