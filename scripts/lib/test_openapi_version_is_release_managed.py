# SPDX-License-Identifier: Apache-2.0
"""The wiring that keeps schema/openapi.yaml's info.version bumped for us.

test_openapi_version_matches_cargo.py asserts the two values agree. It says
nothing about HOW they come to agree, and for several releases the answer was
"a human edits the release branch by hand" - done that way for 0.46.0 and
0.47.0, and red on the release PR until someone noticed.

release-please cannot reach a repo-root file from a package rooted at
crates/slimm-server: extra-files paths resolve relative to the package
directory, and a parent-relative path is rejected outright with "illegal
pathing characters in path". That rejection is not a soft failure - it made
every release-please run fail silently and froze the standing release PR
several merges behind main (PR #933, reverted by #940).

So the bump is driven by a second manifest package rooted at `.` whose only
job is that extra-file, held to the server's own version by the
linked-versions plugin. Without that link the root package would compute its
own version from repo-wide commits and drift openapi.yaml away from the
server on any client-only release, which is the failure this whole file
exists to prevent.

This test pins each moving part so a future config edit cannot quietly drop
one and send us back to hand-editing release branches.
"""

import json
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG = REPO_ROOT / "release-please-config.server.json"
MANIFEST = REPO_ROOT / ".release-please-manifest.server.json"
OPENAPI_PATH = "schema/openapi.yaml"


def config() -> dict:
    return json.loads(CONFIG.read_text())


def manifest() -> dict:
    return json.loads(MANIFEST.read_text())


class OpenapiVersionIsReleaseManagedTest(unittest.TestCase):
    def test_a_root_package_carries_the_openapi_extra_file(self):
        root = config().get("packages", {}).get(".")
        self.assertIsNotNone(
            root,
            "release-please-config.server.json lost its `.` package - without "
            "a package rooted at the repo root, nothing can update "
            f"{OPENAPI_PATH}, whose path a crates/slimm-server-rooted package "
            "cannot legally express",
        )
        paths = [entry.get("path") for entry in root.get("extra-files", [])]
        self.assertIn(
            OPENAPI_PATH,
            paths,
            f"the `.` package no longer lists {OPENAPI_PATH} as an extra-file, "
            "so info.version stops being bumped on a server release",
        )

    def test_the_openapi_extra_file_targets_info_version(self):
        root = config()["packages"]["."]
        entry = next(
            e for e in root["extra-files"] if e.get("path") == OPENAPI_PATH
        )
        self.assertEqual(entry.get("type"), "yaml")
        self.assertEqual(
            entry.get("jsonpath"),
            "$.info.version",
            "the extra-file must target info.version specifically; a broader "
            "jsonpath would rewrite unrelated version strings in the schema",
        )

    def test_the_root_package_is_linked_to_the_server_version(self):
        plugins = config().get("plugins", [])
        linked = [
            p
            for p in plugins
            if isinstance(p, dict) and p.get("type") == "linked-versions"
        ]
        self.assertEqual(
            len(linked),
            1,
            "exactly one linked-versions plugin must hold the root package to "
            "the server's version; without it a client-only release drifts "
            "openapi.yaml's info.version away from the server's Cargo version",
        )
        components = linked[0].get("components", [])
        self.assertIn("server", components)
        self.assertIn(config()["packages"]["."]["component"], components)

    def test_the_root_package_publishes_nothing_of_its_own(self):
        root = config()["packages"]["."]
        self.assertTrue(
            root.get("skip-github-release"),
            "the root package exists only to bump a file; a GitHub release "
            "for it would be a second, meaningless release per server tag",
        )
        self.assertTrue(
            root.get("skip-changelog"),
            "the root package must not write a second changelog at the repo "
            "root alongside crates/slimm-server/CHANGELOG.md",
        )

    def test_both_packages_start_from_the_same_version(self):
        entries = manifest()
        self.assertIn(".", entries)
        self.assertIn("crates/slimm-server", entries)
        self.assertEqual(
            entries["."],
            entries["crates/slimm-server"],
            "the manifest's two entries have diverged - linked-versions keeps "
            "them together going forward, but a divergent starting point "
            "makes the first release after it bump the wrong one",
        )


if __name__ == "__main__":
    unittest.main()
