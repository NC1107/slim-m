# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""A composite action's steps cannot carry `timeout-minutes`.

GitHub rejects the whole action at load time ("Unexpected value
'timeout-minutes'"), which fails every job that uses it, and actionlint does not
lint composite action files. Bound such a step with `timeout` in its shell
instead; a job-level `timeout-minutes` in the calling workflow still applies.
"""

import pathlib
import re
import unittest

ACTIONS = pathlib.Path(__file__).resolve().parents[2] / ".github" / "actions"
KEY = re.compile(r"^\s*timeout-minutes\s*:")


class CompositeActionsHaveNoStepTimeouts(unittest.TestCase):
    def test_no_composite_action_sets_timeout_minutes(self):
        offenders = []
        for path in sorted(ACTIONS.glob("*/action.y*ml")):
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if KEY.match(line):
                    offenders.append(f"{path.relative_to(ACTIONS.parents[1])}:{number}")
        self.assertEqual(offenders, [], "composite steps cannot set timeout-minutes")

    def test_the_pattern_catches_the_key(self):
        self.assertTrue(KEY.match("      timeout-minutes: 8"))
        self.assertFalse(KEY.match("      # timeout-minutes: 8"))
        self.assertFalse(KEY.match("      run: echo timeout-minutes: 8"))


if __name__ == "__main__":
    unittest.main()
