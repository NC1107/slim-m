"""A tapped `slimm://` link reaches the running Linux client.

Spotify's redirect (`slimm://spotify-callback`) and shared invites arrive as
`slim-m <url>`. Three things must all hold or the tap silently does nothing,
which is what the owner saw on Fedora: Chrome's "Open slim-m" did nothing.

1. The .desktop entry claims the scheme and passes the URL (`%u`).
2. The rpm and the Flatpak both install that one entry.
3. The runner's GApplication handles the command line. Without
   `G_APPLICATION_HANDLES_COMMAND_LINE` the second process forwards a bare
   "activate", the URL is dropped, and `app_links` never hears of it.

Stdlib only; hygiene installs nothing.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DESKTOP = ROOT / "packaging" / "rpm" / "top.npcserver.slimm.desktop"
SPEC = ROOT / "packaging" / "rpm" / "slim-m-client.spec"
FLATPAK = ROOT / "packaging" / "flatpak" / "top.npcserver.slimm.yaml"
RUNNER = ROOT / "client" / "packages" / "app" / "linux" / "runner" / "my_application.cc"


def strip_c_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def desktop_keys() -> dict[str, str]:
    keys = {}
    for line in DESKTOP.read_text().splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        keys[key] = value
    return keys


def function_body(source: str, name: str) -> str:
    start = source.index(name + "(")
    brace = source.index("{", start)
    depth = 0
    for i in range(brace, len(source)):
        depth += {"{": 1, "}": -1}.get(source[i], 0)
        if depth == 0:
            return source[brace : i + 1]
    raise AssertionError(f"unbalanced braces after {name}")


class DesktopEntryClaimsTheScheme(unittest.TestCase):
    def test_mime_type_claims_the_slimm_scheme(self):
        mimes = desktop_keys().get("MimeType", "").split(";")
        self.assertIn("x-scheme-handler/slimm", mimes)

    def test_exec_passes_the_url(self):
        exec_line = desktop_keys().get("Exec", "")
        self.assertRegex(exec_line, r"(^|\s)%[uU](\s|$)")

    def test_rpm_installs_the_entry(self):
        self.assertIn("top.npcserver.slimm.desktop", SPEC.read_text())

    def test_flatpak_installs_the_same_entry(self):
        text = FLATPAK.read_text()
        self.assertIn("../rpm/top.npcserver.slimm.desktop", text)
        self.assertIn("/app/share/applications/top.npcserver.slimm.desktop", text)


class RunnerForwardsTheCommandLine(unittest.TestCase):
    def setUp(self):
        self.source = strip_c_comments(RUNNER.read_text())

    def test_application_handles_the_command_line(self):
        new_body = function_body(self.source, "MyApplication* my_application_new")
        self.assertIn("G_APPLICATION_HANDLES_COMMAND_LINE", new_body)

    def test_local_command_line_defers_to_the_package(self):
        body = function_body(self.source, "static gboolean my_application_local_command_line")
        returns = re.findall(r"return\s+(TRUE|FALSE)\s*;", body)
        self.assertEqual(returns[-1], "FALSE", "the success path must return FALSE")

    def test_second_launch_still_raises_the_window(self):
        body = function_body(self.source, "static void my_application_activate")
        self.assertIn("linux_second_instance_channel_notify_focus", body)


if __name__ == "__main__":
    unittest.main()
