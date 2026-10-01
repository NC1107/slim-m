# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""A workflow's row in docs/ci.md must mention every trigger kind it has.

`scripts/check-ci-docs.py` enforces that every workflow has a row and every
row names a real workflow. It never reads what the row says, so the "Runs on"
column can describe a trigger the workflow does not have, or omit one it does,
and the gate stays green. That is how two rows came to omit
`workflow_dispatch` while claiming to describe when the workflow runs.

The full column is prose and not mechanically checkable. The trigger *kinds*
are: a row for a workflow with a `schedule:` has to say so somehow, and one
with `workflow_dispatch:` has to admit it can be run by hand. Anything looser
than the accepted vocabulary below is a documentation choice this cannot
judge; anything that omits a kind entirely is a factual gap it can.

CLAUDE.md sends readers to docs/ci.md as the authoritative workflow list, so a
row that is wrong there is worse than no row: it is trusted.

Parsed as text rather than through PyYAML for the reason
test_release_required_checks_exist.py gives - this suite runs on a bare
runner with no pip install step.
"""

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
WORKFLOWS = REPO_ROOT / ".github" / "workflows"
DOC = REPO_ROOT / "docs" / "ci.md"

ROW = re.compile(r"^\|\s*`([a-z0-9._-]+)`\s*\|(.*)$", re.M)
# A trigger key sits at exactly two spaces under the top-level `on:`.
TRIGGER = re.compile(r"^  ([a-z_]+):", re.M)

# Generous on purpose: this gates the omission of a kind, not the wording.
VOCABULARY = {
    "schedule": r"schedul|daily|weekly|hourly|nightly|cron",
    "workflow_dispatch": r"by hand|dispatch|manual",
    "workflow_call": r"called by|reusable",
    "workflow_run": r"completed|finish|after",
    "release": r"release",
    "push_tags": r"tag",
}
CRON = re.compile(r"cron:\s*[\"']([^\"']+)[\"']")


def _cadence_words(cron: str) -> str | None:
    """The word a row must carry for this cron's cadence, as a regex."""
    minute, hour, dom, month, dow = cron.split()
    if hour == "*":
        return r"hourly|every hour"
    step = re.fullmatch(r"\*/(\d+)", hour)
    if step and step.group(1) == "6":
        return r"six-hourly|every six hours|every 6 hours"
    if hour.isdigit() and dow != "*":
        return r"weekly"
    if hour.isdigit():
        return r"daily|nightly"
    return None


def _cadences(text: str) -> list[str]:
    return [w for c in CRON.findall(text) if (w := _cadence_words(c))]


def _trigger_kinds(text: str) -> set[str]:
    lines = text.splitlines()
    start = next((i for i, l in enumerate(lines) if re.match(r"^(on|True):\s*$", l)), None)
    if start is None:
        return set()
    body = []
    for line in lines[start + 1 :]:
        if line.strip() and not line.startswith(" "):
            break
        body.append(line)
    kinds = set(TRIGGER.findall("\n".join(body)))
    if re.search(r"^    tags:", "\n".join(body), re.M):
        kinds.add("push_tags")
    return kinds


class CiDocsTriggersTest(unittest.TestCase):
    def setUp(self):
        self.rows = {m.group(1): m.group(2) for m in ROW.finditer(DOC.read_text())}
        self.workflows = sorted(WORKFLOWS.glob("*.yml"))

    def test_every_workflow_yields_at_least_one_trigger(self):
        """Per file, not in aggregate.

        A workflow with no parseable `on:` block yields no kinds, so every
        assertion below skips it silently while the rest of the suite stays
        green. Checking the total would miss exactly that: one file drifting
        out of reach among twenty that still parse.
        """
        for path in self.workflows:
            self.assertTrue(
                _trigger_kinds(path.read_text()),
                f"no triggers parsed out of {path.name}; either it cannot run at "
                "all, or the layout this reads has drifted and that workflow is "
                "silently exempt from the check below",
            )

    def test_every_row_admits_the_kinds_its_workflow_has(self):
        for path in self.workflows:
            stem = path.stem
            row = self.rows.get(stem)
            self.assertIsNotNone(row, f"{stem} has no row in docs/ci.md")
            for kind, pattern in VOCABULARY.items():
                if kind in _trigger_kinds(path.read_text()):
                    self.assertRegex(
                        row,
                        pattern,
                        f"docs/ci.md's `{stem}` row describes when it runs but never "
                        f"mentions its {kind} trigger",
                    )

    def test_every_scheduled_row_names_its_cadence(self):
        for path in self.workflows:
            row = self.rows.get(path.stem, "")
            for pattern in _cadences(path.read_text()):
                self.assertRegex(
                    row,
                    pattern,
                    f"docs/ci.md's `{path.stem}` row does not name the cadence its cron runs at",
                )

    def test_a_cadence_change_that_the_row_does_not_follow_is_caught(self):
        (pattern,) = _cadences('on:\n  schedule:\n    - cron: "17 7 * * *"\n')
        self.assertNotRegex("an hourly schedule, and by hand", pattern)
        (pattern,) = _cadences('on:\n  schedule:\n    - cron: "17 * * * *"\n')
        self.assertRegex("an hourly schedule, and by hand", pattern)
        (pattern,) = _cadences('on:\n  schedule:\n    - cron: "0 */6 * * *"\n')
        self.assertNotRegex("a daily schedule", pattern)
        self.assertRegex("a six-hourly schedule", pattern)
