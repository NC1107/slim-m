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

Parsed as text rather than through PyYAML on purpose. The hygiene job runs
`python3 -m unittest` against a bare runner with no pip install step, and
every sibling test in this directory is importable there; a third-party
import here would fail in CI while passing on any machine that happens to
have the module.
"""
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
RELEASE_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "release.yml"
SCHEMA_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "schema-ci.yml"

# The gate that can actually reach a release commit: no path filter, every push.
PUSH_GATE_NAME = "breaking-change gate (additive-only, push to main)"
# The PR-time-only gate: correct for a reviewer, unreachable for a release.
PR_ONLY_GATE_NAME = "breaking-change gate (additive-only)"


def _required_checks(text: str) -> list[str]:
    return re.findall(r'required_checks:\s*"([^"]*)"', text)


def _block_after(text: str, header_pattern: str, indent: int) -> str | None:
    """The lines under the first line matching `header_pattern`, stopping at
    the next line indented at or above `indent`."""
    lines = text.splitlines()
    start = next(
        (i for i, line in enumerate(lines) if re.match(header_pattern, line)),
        None,
    )
    if start is None:
        return None
    body = []
    for line in lines[start + 1 :]:
        if line.strip() and (len(line) - len(line.lstrip())) < indent:
            break
        body.append(line)
    return "\n".join(body)


class ReleaseRequiredChecksSchemaGateTest(unittest.TestCase):
    def setUp(self):
        self.release_text = RELEASE_WORKFLOW.read_text()
        self.schema_text = SCHEMA_WORKFLOW.read_text()

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
        # Block-anchored, since a comment naming the job satisfies a raw search.
        job = _block_after(
            self.schema_text, rf"^    name: {re.escape(PUSH_GATE_NAME)}\s*$", 4
        )
        self.assertIsNotNone(
            job,
            f"expected a job named {PUSH_GATE_NAME!r} in schema-ci.yml",
        )
        condition = job.split("runs-on", 1)[0]
        self.assertIn(
            "github.event_name == 'push'",
            condition,
            "the push-triggered gate must actually be gated to push events, "
            "or it also runs on pull_request where it has no base to diff",
        )

    def test_schema_ci_push_trigger_has_no_path_filter(self):
        on_block = _block_after(self.schema_text, r"^on:\s*$", 1)
        self.assertIsNotNone(on_block, "schema-ci.yml has no `on:` block")
        push_block = _block_after(on_block, r"^  push:\s*$", 3)
        self.assertIsNotNone(push_block, "schema-ci.yml has no `push:` trigger")
        self.assertNotIn(
            "paths:",
            push_block,
            "a path filter on push means the push-triggered gate never runs "
            "on a release-please commit (version files only, never "
            "schema/**), so verify-release-checks would time out waiting "
            "for a check-run that never gets created",
        )
        self.assertIn("branches: [main]", push_block)


if __name__ == "__main__":
    unittest.main()
