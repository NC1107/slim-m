# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Drives `scripts/report-advisory-issue.sh` against a fake `gh`.

A fake on PATH rather than a dry-run flag, deliberately: a dry run would only
prove that a status string reaches the right branch, where the thing actually
worth guarding is which `gh` subcommand each branch invokes - that an already
open issue is left alone rather than duplicated every day, and that a clean
scan closes one rather than silently leaving it open forever.

The fake records its own argv, so an assertion reads what the script really
did instead of what it printed about itself.
"""

from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "report-advisory-issue.sh"

FAKE_GH = """#!/usr/bin/env bash
echo "$@" >> "$GH_CALLS"
# `issue list` is the only call the script reads a value back from.
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
  printf '%s' "${FAKE_EXISTING_ISSUE:-}"
fi
exit 0
"""


def run(tmp_path: Path, status: str, existing: str = "") -> list[str]:
    """Runs the script with a fake `gh`, returning that fake's recorded calls."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text(FAKE_GH)
    gh.chmod(0o755)
    calls = tmp_path / "calls.txt"
    calls.write_text("")

    env = dict(os.environ)
    env.update(
        PATH=f"{bin_dir}:{env['PATH']}",
        GH_CALLS=str(calls),
        FAKE_EXISTING_ISSUE=existing,
        GITHUB_REPOSITORY="owner/repo",
        ADVISORY_STATUS=status,
        RUN_URL="https://example.invalid/run/1",
    )
    subprocess.run(["bash", str(SCRIPT)], env=env, check=True, capture_output=True)
    return [line for line in calls.read_text().splitlines() if line]


def test_a_found_advisory_opens_an_issue(tmp_path: Path) -> None:
    calls = run(tmp_path, "found")
    assert any(c.startswith("issue create") for c in calls), calls


def test_a_found_advisory_does_not_open_a_second_issue(tmp_path: Path) -> None:
    """The check runs daily; without this it would file one issue per day."""
    calls = run(tmp_path, "found", existing="42")
    assert not any(c.startswith("issue create") for c in calls), calls


def test_a_clean_scan_closes_an_open_issue(tmp_path: Path) -> None:
    calls = run(tmp_path, "clean", existing="42")
    assert any(c.startswith("issue close 42") for c in calls), calls


def test_a_clean_scan_with_nothing_open_does_nothing(tmp_path: Path) -> None:
    calls = run(tmp_path, "clean")
    assert not any(c.startswith("issue close") for c in calls), calls
    assert not any(c.startswith("issue create") for c in calls), calls


def test_an_unrecognised_status_refuses_rather_than_guessing(tmp_path: Path) -> None:
    """A typo in the workflow's own expression must not read as 'clean'.

    `ADVISORY_STATUS` is built from a GitHub Actions ternary, so a future edit
    to that expression could produce something neither branch expects; the
    dangerous reading is the silent one, where an advisory scan quietly closes
    the very issue it should have opened.
    """
    env = dict(os.environ)
    env.update(
        GITHUB_REPOSITORY="owner/repo",
        ADVISORY_STATUS="",
        GH_CALLS=str(tmp_path / "unused.txt"),
    )
    done = subprocess.run(
        ["bash", str(SCRIPT)], env=env, capture_output=True, text=True
    )
    assert done.returncode != 0, done.stdout


def test_the_script_is_the_one_the_workflow_runs() -> None:
    """A test against a script no workflow calls proves nothing."""
    workflow = (
        SCRIPT.parents[1] / ".github/workflows/advisory-watchdog.yml"
    ).read_text()
    assert "scripts/report-advisory-issue.sh" in workflow
    assert textwrap.dedent(workflow).count("check advisories") >= 1
