# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""The merge queue ruleset must only require checks a queue entry can actually produce.

A merge queue builds a temporary branch and waits for every required check on
it. A required check that no workflow reports for that event never arrives, and
the queue stalls until its timeout. `merge_group` ignores `paths:` filters, so a
workflow that lists it runs for every entry; a workflow that does not list it
never reports. This reads `.github/rulesets/main-merge-queue.json` and fails
when a required context has no job in a workflow with a `merge_group` trigger,
and when one of the five queue workflows loses the trigger.
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
RULESET = ROOT / ".github" / "rulesets" / "main-merge-queue.json"

QUEUE_WORKFLOWS = ["hygiene.yml", "client-ci.yml", "server-ci.yml", "schema-ci.yml", "licenses.yml"]


def has_merge_group(text: str) -> bool:
    return re.search(r"^on:\s*\n(?:[ \t]+.*\n|#.*\n)*?  merge_group:", text, re.M) is not None


def job_names(text: str) -> set[str]:
    names = set()
    jobs = text.split("\njobs:\n", 1)[-1]
    for match in re.finditer(r"^  ([A-Za-z0-9_-]+):\s*\n((?:    .*\n|\s*\n|  #.*\n)*)", jobs, re.M):
        named = re.search(r"^    name:\s*(.+?)\s*$", match.group(2), re.M)
        names.add(named.group(1).strip("\"'") if named else match.group(1))
    return names


class MergeQueueRulesetMatchesTheWorkflowsTest(unittest.TestCase):
    def test_queue_workflows_run_on_merge_group(self):
        for name in QUEUE_WORKFLOWS:
            with self.subTest(workflow=name):
                self.assertTrue(has_merge_group((WORKFLOWS / name).read_text()))

    def test_every_required_context_is_a_job_that_runs_in_the_queue(self):
        rules = json.loads(RULESET.read_text())["rules"]
        required = [
            check["context"]
            for rule in rules
            if rule["type"] == "required_status_checks"
            for check in rule["parameters"]["required_status_checks"]
        ]
        self.assertTrue(required)
        available = set()
        for name in QUEUE_WORKFLOWS:
            available |= job_names((WORKFLOWS / name).read_text())
        for context in required:
            with self.subTest(context=context):
                self.assertIn(context, available)

    def test_the_trigger_check_is_not_vacuous(self):
        self.assertFalse(has_merge_group("on:\n  push:\n    branches: [main]\n  pull_request:\n\njobs: {}\n"))
        self.assertTrue(has_merge_group("on:\n  merge_group:\n  push:\n\njobs: {}\n"))


if __name__ == "__main__":
    unittest.main()
