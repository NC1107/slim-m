# SPDX-License-Identifier: Apache-2.0
"""perf/baselines/ must not fall far behind the server's own release tags.

perf/README.md's model is one committed baseline per server release, but
producing one is a manual step (see its "Adding a new baseline" section):
pull a release's criterion artifact, hand-measure idle RSS on real hardware,
and commit the result in a followup pull request. Nobody did that after
0.38.0, and nothing checked it - the server went on to publish through
0.45.2 while the newest committed baseline still read 0.38.0, a lapse of
every release in between.

This asserts a bounded lag rather than exact equality. hygiene.yml runs this
suite on every push and pull_request, and adding a baseline is a real-
hardware step that cannot happen atomically with the release tag landing -
so exact equality would fail every single unrelated pull request from the
moment a release publishes until a human finishes that step, turning normal
release cadence into a blanket failure. MAX_RELEASES_BEHIND instead gives a
few releases of grace for that human step to catch up, while a lapse the
size of the one that produced this test - nine releases, 0.39.0 through
0.45.2 - still fails loudly rather than staying silent indefinitely.

GRANDFATHERED_BASELINE is why that existing nine-release lapse reports as a
skip rather than a failure today. The gap predates this check, and closing it
needs a hand-measurement on real hardware that no amount of CI can perform;
failing on it immediately would paint hygiene red on main and on every
unrelated pull request until a human found the time, which is precisely how a
gate stops being read at all - docs/ci.md records two silent releases lost to
exactly that pattern with e2e. So the pre-existing gap reports loudly and
stays green, and the bounded-lag assertion arms itself permanently the moment
anyone commits a baseline newer than the grandfathered one, at which point the
cadence is being kept and a slip is worth failing over.
"""

import re
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BASELINES_DIR = REPO_ROOT / "perf" / "baselines"

# Releases a missing baseline may lag behind before this fails; see the module doc.
MAX_RELEASES_BEHIND = 3

# The newest committed baseline the day this check landed; see the module doc.
GRANDFATHERED_BASELINE = "0.38.0"

VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def _semver_key(version: str) -> tuple[int, int, int]:
    match = VERSION_RE.match(version)
    if not match:
        raise AssertionError(f"{version!r} is not a plain x.y.z version")
    return tuple(int(part) for part in match.groups())


def committed_baseline_versions() -> list[str]:
    """Versions with a committed perf/baselines/<version>.json, oldest first."""
    return sorted((p.stem for p in BASELINES_DIR.glob("*.json")), key=_semver_key)


def published_server_release_versions() -> list[str]:
    """Every `server-vX.Y.Z` tag reachable from this checkout, oldest first."""
    result = subprocess.run(
        ["git", "tag", "-l", "server-v*"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    versions = [
        line.removeprefix("server-v") for line in result.stdout.splitlines() if line.strip()
    ]
    return sorted(versions, key=_semver_key)


class PerfBaselineFreshnessTest(unittest.TestCase):
    def test_newest_baseline_is_not_far_behind_the_newest_release_tag(self):
        releases = published_server_release_versions()
        if not releases:
            self.skipTest("no server-v* tags reachable from this checkout")

        baselines = committed_baseline_versions()
        self.assertTrue(baselines, "perf/baselines/ has no committed baseline at all")

        newest_release = releases[-1]
        newest_baseline = baselines[-1]
        if newest_baseline == newest_release:
            return

        self.assertIn(
            newest_baseline,
            releases,
            f"perf/baselines/{newest_baseline}.json names a version with no "
            f"matching server-v{newest_baseline} release tag",
        )
        behind = len(releases) - 1 - releases.index(newest_baseline)
        recovery = (
            f"A human needs to run `cargo bench -p slimm-server`, pull the "
            f"criterion-report artifact from the {newest_release} release run "
            "(or the newest one still available), hand-measure idle RSS with "
            "perf/measure-idle-rss.sh on real hardware, and commit "
            f"perf/baselines/{newest_release}.json per perf/README.md's "
            '"Adding a new baseline" section.'
        )
        if newest_baseline == GRANDFATHERED_BASELINE:
            self.skipTest(
                f"perf/baselines/ is {behind} releases behind ({newest_baseline} "
                f"against {newest_release}). This gap predates the check and "
                f"needs a real-hardware measurement, so it reports rather than "
                f"failing; see GRANDFATHERED_BASELINE. {recovery}"
            )
        self.assertLessEqual(
            behind,
            MAX_RELEASES_BEHIND,
            f"perf/baselines/ is {behind} releases behind: the newest "
            f"committed baseline is {newest_baseline}.json but the newest "
            f"published server release is {newest_release}. {recovery}",
        )


if __name__ == "__main__":
    unittest.main()
