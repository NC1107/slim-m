# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for scripts/copr-behind.sh, the gate behind copr-catch-up.yml.

Fixtures mirror the shape of COPR's api_3/build/list answer (newest first),
including the real 2026-09-25 state: 0.86.0 snapshots on COPR while main
was at 0.87.0.
"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "copr-behind.sh"


def build(version, state="succeeded"):
    return {"state": state, "source_package": {"name": "slim-m-client", "version": version}}


def behind(pubspec, *builds):
    with tempfile.TemporaryDirectory() as tmp:
        fixture = Path(tmp) / "builds.json"
        fixture.write_text(json.dumps({"items": list(builds)}))
        out = Path(tmp) / "out"
        env = {
            **os.environ,
            "PUBSPEC_VERSION": pubspec,
            "COPR_BUILDS_JSON": str(fixture),
            "GITHUB_OUTPUT": str(out),
        }
        subprocess.run(["bash", str(SCRIPT)], env=env, check=True, capture_output=True)
        return out.read_text().strip()


class CoprBehindTest(unittest.TestCase):
    def test_behind_when_copr_has_only_an_older_version(self):
        self.assertEqual(behind("0.87.0", build("0.86.0-0.966"), build("0.85.0-0.9")), "behind=true")

    def test_current_when_a_snapshot_of_the_version_exists(self):
        self.assertEqual(behind("0.87.0", build("0.87.0-0.968"), build("0.86.0-0.966")), "behind=false")

    def test_current_when_the_tagged_release_exists(self):
        self.assertEqual(behind("0.87.0", build("0.87.0-1")), "behind=false")

    def test_pending_build_counts_so_a_submit_is_not_doubled(self):
        self.assertEqual(behind("0.87.0", build("0.87.0-0.970", "running"), build("0.86.0-1")), "behind=false")

    def test_failed_and_canceled_builds_do_not_count(self):
        builds = [build("0.87.0-0.970", "failed"), build("0.87.0-0.969", "canceled"), build("0.86.0-1")]
        self.assertEqual(behind("0.87.0", *builds), "behind=true")

    def test_version_compare_is_numeric_not_lexical(self):
        self.assertEqual(behind("0.100.0", build("0.99.0-1")), "behind=true")
        self.assertEqual(behind("0.99.0", build("0.100.0-1")), "behind=false")

    def test_behind_when_copr_has_no_builds(self):
        self.assertEqual(behind("0.87.0"), "behind=true")


if __name__ == "__main__":
    unittest.main()
