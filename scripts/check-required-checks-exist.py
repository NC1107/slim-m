#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Every name in a release.yml required_checks string must be a real job name.

The release gate matches check runs by exact name (scripts/verify-release-checks.sh
splits REQUIRED_CHECKS on '|' and compares each to a check-run name). Nothing
connects that string to the jobs it names, so renaming a job silently points the
gate at a check that will never appear. The verifier does fail loudly when that
happens, but only at release time, on main, after the rename has merged.

This asks the same question on the pull request instead.
"""

import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"


def job_names() -> set[str]:
    names: set[str] = set()
    for path in sorted(WORKFLOWS.glob("*.yml")):
        doc = yaml.safe_load(path.read_text()) or {}
        for key, job in (doc.get("jobs") or {}).items():
            names.add((job or {}).get("name") or key)
    return names


def main() -> int:
    names = job_names()
    release = WORKFLOWS / "release.yml"
    checked = 0
    missing: list[str] = []
    for match in re.finditer(r'required_checks:\s*"([^"]+)"', release.read_text()):
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
