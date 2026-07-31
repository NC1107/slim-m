# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for scripts/decide-latest-tag.sh.

It shipped with nothing binding it: a manual run against a stubbed `gh` is
not something CI can catch a regression with. This drives the real script
through `bash` with a fake `gh` on PATH, so a change to the sort-V comparison
or to the fail-closed handling below fails a test rather than merely a memory
of having checked it once.
"""
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "decide-latest-tag.sh"

FAKE_GH = """#!/usr/bin/env bash
if [ "${FAKE_GH_EXIT_CODE:-0}" -ne 0 ]; then
  echo "${FAKE_GH_STDERR:-gh: simulated failure}" >&2
  exit "${FAKE_GH_EXIT_CODE}"
fi
printf '%s\\n' "${FAKE_GH_STDOUT:-}"
"""


class DecideLatestTagTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        fake = Path(self._tmp.name) / "gh"
        fake.write_text(FAKE_GH)
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        self.fake_gh_dir = str(fake.parent)

    def _run(self, version, published_tags="", exit_code=0, stderr=""):
        env = {
            "PATH": f"{self.fake_gh_dir}:/usr/bin:/bin",
            "FAKE_GH_STDOUT": published_tags,
            "FAKE_GH_EXIT_CODE": str(exit_code),
            "FAKE_GH_STDERR": stderr,
        }
        return subprocess.run(
            ["bash", str(SCRIPT), "ghcr.io/nc1107/slim-m-server", version],
            env=env, capture_output=True, text=True)

    def test_a_forward_version_may_move_latest(self):
        result = self._run("0.12.0", "0.10.0\n0.11.1\n0.11.5")
        self.assertEqual(result.stdout.strip(), "true")

    def test_re_pushing_an_old_tag_refuses(self):
        result = self._run("0.11.1", "0.10.0\n0.11.1\n0.12.0")
        self.assertEqual(result.stdout.strip(), "false")
        self.assertIn("older than the newest published tag", result.stderr)
        self.assertIn("::warning::", result.stderr)

    def test_the_very_first_release_may_move_latest(self):
        result = self._run("0.1.0", "")
        self.assertEqual(result.stdout.strip(), "true")

    def test_a_gh_failure_fails_closed_rather_than_open(self):
        result = self._run(
            "9.9.9", exit_code=1, stderr="gh: rate limit exceeded")
        self.assertEqual(result.stdout.strip(), "false")
        self.assertIn("rate limit exceeded", result.stderr)
        self.assertIn("::warning::", result.stderr)

    def test_an_equal_version_may_move_latest(self):
        """Re-publishing the same version it already is is not a regression."""
        result = self._run("0.12.0", "0.11.1\n0.12.0")
        self.assertEqual(result.stdout.strip(), "true")

    def test_non_semver_tags_in_the_listing_are_ignored(self):
        result = self._run("0.12.0", "latest\nsha-abc123\n0.11.1")
        self.assertEqual(result.stdout.strip(), "true")

    def test_a_multiline_gh_error_collapses_to_one_warning_line(self):
        """A `::warning::` annotation is a single logical line; an embedded
        newline from gh's own error text must not split it in two.
        """
        result = self._run(
            "9.9.9", exit_code=1,
            stderr="gh: Resource not accessible\n{\"message\": \"forbidden\"}")
        warnings = [ln for ln in result.stderr.splitlines()
                    if ln.startswith("::warning::")]
        self.assertEqual(len(warnings), 1)
        self.assertIn("Resource not accessible", warnings[0])
        self.assertIn("forbidden", warnings[0])


if __name__ == "__main__":
    unittest.main()
