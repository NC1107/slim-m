# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""A Windows job must not run `flutter build` under `shell: bash`.

Git Bash rewrites slash-leading environment values into paths, which broke
the 0.89.0 Windows release; `docs/ci.md` has the incident.
"""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"

JOB_HEADER = re.compile(r"^  [A-Za-z0-9_-]+:\s*$")
STEP_START = re.compile(r"^      - ")


def jobs(text: str) -> dict[str, str]:
    """Each job's name mapped to the text of its definition."""
    found: dict[str, list[str]] = {}
    current = None
    in_jobs = False
    for line in text.splitlines():
        if line.startswith("jobs:"):
            in_jobs = True
            continue
        if not in_jobs:
            continue
        if JOB_HEADER.match(line):
            current = line.strip().rstrip(":")
            found[current] = []
        elif current is not None:
            found[current].append(line)
    return {name: "\n".join(body) for name, body in found.items()}


def steps(job: str) -> list[str]:
    """A job's steps, each as its own block of text."""
    blocks: list[list[str]] = []
    for line in job.splitlines():
        if STEP_START.match(line):
            blocks.append([line])
        elif blocks:
            blocks[-1].append(line)
    return ["\n".join(block) for block in blocks]


def offenders(text: str) -> list[str]:
    """Names of Windows jobs holding a bash step that runs `flutter build`."""
    bad = []
    for name, body in jobs(text).items():
        if not re.search(r"^    runs-on:.*windows", body, re.M):
            continue
        for step in steps(body):
            if re.search(r"shell:\s*bash", step) and "flutter build" in step:
                bad.append(name)
    return bad


class WindowsBuildsDoNotRunUnderBashTest(unittest.TestCase):
    def test_no_windows_job_builds_under_bash(self):
        for path in sorted(WORKFLOWS.glob("*.yml")):
            with self.subTest(workflow=path.name):
                self.assertEqual(offenders(path.read_text()), [])

    def test_the_gate_sees_the_step_that_broke_the_release(self):
        broken = (
            "jobs:\n"
            "  windows-client:\n"
            "    runs-on: windows-latest\n"
            "    steps:\n"
            "      - name: build\n"
            "        shell: bash\n"
            "        run: flutter build windows --release\n"
        )
        self.assertEqual(offenders(broken), ["windows-client"])

    def test_a_bash_step_that_only_uploads_is_allowed(self):
        fine = (
            "jobs:\n"
            "  windows-client:\n"
            "    runs-on: windows-latest\n"
            "    steps:\n"
            "      - name: build\n"
            "        run: flutter build windows --release\n"
            "      - name: attach\n"
            "        shell: bash\n"
            "        run: gh release upload v1 a.zip\n"
        )
        self.assertEqual(offenders(fine), [])


if __name__ == "__main__":
    unittest.main()
