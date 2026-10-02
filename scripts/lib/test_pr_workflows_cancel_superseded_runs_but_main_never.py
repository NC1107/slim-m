# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""A superseded pull request push must stop burning runners, and a main run must never be cancelled.

The org's runners queued 40 to 60 runs deep for hours on 2026-10-01, and a PR
that is pushed to again keeps every job of its older head running unless the
workflow carries a `concurrency` group that cancels it. The opposite rule
matters just as much: release gates read the check runs of the exact release
commit, so a main run that is cancelled blocks a publish that had nothing wrong
with it. This pins both for every workflow with a `pull_request` trigger.

`main-builds` and `release` are push-only on purpose and are not read here.
"""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"


def trigger_block(text: str) -> str:
    match = re.search(r"^on:\s*\n((?:[ \t]+.*\n|\s*\n|#.*\n)+)", text, re.M)
    return match.group(1) if match else ""


def concurrency_block(text: str) -> str:
    match = re.search(r"^concurrency:\s*\n((?:[ \t]+.*\n|#.*\n)+)", text, re.M)
    return match.group(1) if match else ""


def problems(text: str) -> list[str]:
    triggers = trigger_block(text)
    if not re.search(r"^  pull_request:", triggers, re.M):
        return []
    block = concurrency_block(text)
    group = re.search(r"^\s+group:\s*(.*)$", block, re.M)
    cancel = re.search(r"^\s+cancel-in-progress:\s*(.*)$", block, re.M)
    if not group or not cancel:
        return ["no concurrency group with cancel-in-progress"]
    found = []
    if "github.ref" not in group.group(1):
        found.append("the group is not keyed on github.ref, so two PRs share it")
    value = cancel.group(1).strip()
    if value == "false":
        found.append("a superseded pull request run is never cancelled")
    pushes_main = re.search(r"^  push:", triggers, re.M)
    if pushes_main and value == "true" and "github.sha" not in group.group(1):
        found.append("cancel-in-progress is true on main: key the group on github.sha there")
    if pushes_main and value not in ("true", "false") and "refs/heads/main" not in value and "pull_request" not in value:
        found.append("cancel-in-progress is an expression that does not exempt main")
    return found


class PrWorkflowsCancelSupersededRunsButMainNeverTest(unittest.TestCase):
    def test_every_pull_request_workflow(self):
        for path in sorted(WORKFLOWS.glob("*.yml")):
            with self.subTest(workflow=path.name):
                self.assertEqual(problems(path.read_text()), [])

    def test_the_gate_fails_on_each_mistake(self):
        def workflow(group, cancel):
            return (
                "on:\n  pull_request:\n  push:\n    branches: [main]\n\n"
                f"concurrency:\n  group: {group}\n  cancel-in-progress: {cancel}\n"
            )

        ref = "x-${{ github.ref }}"
        cases = [
            (workflow("x", "true"), "keyed on github.ref"),
            (workflow(ref, "false"), "never cancelled"),
            (workflow(ref, "true"), "true on main"),
            (workflow(ref, "${{ github.event_name == 'x' }}"), "exempt main"),
        ]
        for text, expected in cases:
            with self.subTest(expected=expected):
                self.assertTrue(any(expected in p for p in problems(text)), problems(text))
        self.assertEqual(problems(workflow(ref, "${{ github.ref != 'refs/heads/main' }}")), [])
        self.assertEqual(
            problems("on:\n  pull_request:\n\njobs: {}\n"),
            ["no concurrency group with cancel-in-progress"],
        )


if __name__ == "__main__":
    unittest.main()
