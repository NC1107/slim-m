# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Unit coverage for the order and naming of e2e_run's scenarios.

The scenarios run in one browser session against one deployment, so their
order is part of what they mean. Names are what a failure reports and what
E2E_ONLY matches, so two scenarios sharing one would make a red run ambiguous.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_run  # noqa: E402


def _names():
    return [name for name, _ in e2e_run.scenarios(
        None, None, None, None, "room", "http://localhost:0", "secret")]


class ScenarioRegistryTest(unittest.TestCase):
    def test_names_are_unique_and_every_scenario_is_callable(self):
        scenarios = e2e_run.scenarios(
            None, None, None, None, "room", "http://localhost:0", "secret")
        names = [name for name, _ in scenarios]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue(all(callable(run) for _, run in scenarios))

    def test_the_week_s_features_each_have_a_scenario(self):
        names = " | ".join(_names())
        for fragment in (
            "holding a reaction lists who left it",
            "message menu opens on quick reactions",
            "a thread stays off the ordinary channel list",
            "Tab and Shift+Tab move a list item",
            "a typed :shortcode: becomes its emoji",
            "cannot take a standard shortcode's name",
            "renaming a member shows the nickname",
            "push preview is one choice across devices",
            "usernames ignore case",
        ):
            self.assertIn(fragment, names)

    def test_the_scenario_that_wipes_bobs_storage_runs_last(self):
        self.assertIn("usernames ignore case", _names()[-1])


if __name__ == "__main__":
    unittest.main()
