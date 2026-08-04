# SPDX-License-Identifier: Apache-2.0
"""The additive-only schema gate must actually be able to appear on the
commit `verify-release-checks.yml` verifies, not just be named in
`required_checks`.

`breaking-change-gate` (schema-ci) is pull_request-only by construction -
diffing needs a PR's base and head, which a bare push does not have - so it
can never carry a check-run on a release commit: a squash-merge mints a new
SHA the PR-time run was never attached to, and a release-please commit never
touches `schema/**` at all. Naming that job in `required_checks` would make
every release time out waiting for a check-run that structurally cannot
exist there.

This is a shape a passing test cannot see by running anything - GitHub
Actions triggers and `if:` conditions are configuration, not code - so it is
checked the way `route_reachability_test.dart` and `tests/canvas_index.rs`
check their own structural properties: by reading the real workflow files
rather than a copy of their intent.
"""
import re
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
RELEASE_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "release.yml"
SCHEMA_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "schema-ci.yml"

# The gate that can actually reach a release commit: unconditioned on any path filter, on every push.
PUSH_GATE_NAME = "breaking-change gate (additive-only, push to main)"
# The PR-time-only gate: correct for a reviewer, unreachable for a release.
PR_ONLY_GATE_NAME = "breaking-change gate (additive-only)"


def _required_checks(text: str) -> list[str]:
    return re.findall(r'required_checks:\s*"([^"]*)"', text)


class ReleaseRequiredChecksSchemaGateTest(unittest.TestCase):
    def setUp(self):
        self.release_text = RELEASE_WORKFLOW.read_text()
        self.schema_doc = yaml.safe_load(SCHEMA_WORKFLOW.read_text())

    def test_both_required_checks_lists_name_the_push_triggered_gate(self):
        lists = _required_checks(self.release_text)
        self.assertEqual(
            len(lists),
            2,
            "expected exactly one required_checks string per verify-release-checks call",
        )
        for entries in lists:
            names = entries.split("|")
            self.assertIn(
                PUSH_GATE_NAME,
                names,
                "a release must require the gate that can actually appear on "
                "the commit it verifies",
            )
            self.assertNotIn(
                PR_ONLY_GATE_NAME,
                names,
                "the pull_request-only gate can never carry a check-run on a "
                "release commit; requiring it times out every release",
            )

    def test_the_push_gate_job_exists_and_runs_on_push(self):
        jobs = self.schema_doc["jobs"]
        matches = [j for j in jobs.values() if j.get("name") == PUSH_GATE_NAME]
        self.assertEqual(
            len(matches),
            1,
            f"expected exactly one job named {PUSH_GATE_NAME!r} in schema-ci.yml",
        )
        condition = matches[0].get("if", "")
        self.assertIn(
            "push",
            condition,
            "the push-triggered gate must actually be gated to push events",
        )

    def test_schema_ci_push_trigger_has_no_path_filter(self):
        # `True` because YAML parses the bare key `on:` as the boolean True.
        triggers = self.schema_doc.get("on") or self.schema_doc.get(True)
        push_trigger = triggers["push"]
        self.assertNotIn(
            "paths",
            push_trigger,
            "a path filter on push means the push-triggered gate never runs "
            "on a release-please commit (version files only, never "
            "schema/**), so verify-release-checks would time out waiting "
            "for a check-run that never gets created",
        )
        self.assertEqual(push_trigger.get("branches"), ["main"])


if __name__ == "__main__":
    unittest.main()
