#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Every name in a release.yml required_checks string must be a real job name.

The release gate matches check runs by exact name (scripts/verify-release-checks.sh
splits REQUIRED_CHECKS on '|' and compares each to a check-run name). Nothing
connects that string to the jobs it names, so renaming a job silently points the
gate at a check that will never appear. The verifier does fail loudly when that
happens, but only at release time, on main, after the rename has merged.

This asks the same question on the pull request instead.

Job names are read without a YAML parser, so this gate adds no dependency to
hygiene.yml, where every other check is stdlib-only. A job key sits at exactly
two spaces and its `name:` at exactly four, which is unambiguous here because a
step's own `name:` is indented six. That equivalence was checked against PyYAML
across every workflow in the repository before this was written; if the layout
ever drifts, the parser finds no names and every required check reads as
missing, which fails loudly rather than passing empty.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"

JOBS_LINE = re.compile(r"^jobs:\s*$")
JOB_KEY = re.compile(r"^  ([A-Za-z0-9_-]+):\s*$")
JOB_NAME = re.compile(r"^    name:\s*(.+?)\s*$")
REQUIRED = re.compile(r'required_checks:\s*"([^"]+)"')


def names_in(text: str) -> set[str]:
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if JOBS_LINE.match(line)), None)
    if start is None:
        return set()
    found: set[str] = set()
    pending: str | None = None
    for line in lines[start + 1 :]:
        if line.strip() and not line.startswith(" "):
            break
        key = JOB_KEY.match(line)
        if key:
            if pending:
                found.add(pending)
            pending = key.group(1)
            continue
        name = JOB_NAME.match(line)
        if name and pending:
            found.discard(pending)
            found.add(name.group(1).strip("\"'"))
            pending = None
    if pending:
        found.add(pending)
    return found


def main() -> int:
    names: set[str] = set()
    for path in sorted(WORKFLOWS.glob("*.yml")):
        names |= names_in(path.read_text(encoding="utf-8"))

    release = WORKFLOWS / "release.yml"
    checked = 0
    missing: list[str] = []
    for match in REQUIRED.finditer(release.read_text(encoding="utf-8")):
        for check in match.group(1).split("|"):
            checked += 1
            if check not in names:
                missing.append(check)

    if not checked:
        print(f"::error file={release}::no required_checks string found; this gate cannot pass without one")
        return 1
    for check in missing:
        print(f"::error file={release}::required_checks names '{check}', which is no job's name in .github/workflows/")
    print(f"required checks: {checked} named, {len(missing)} unresolved, {len(names)} job names available")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
