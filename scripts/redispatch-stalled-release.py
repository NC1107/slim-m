#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Re-dispatch a release whose verify gate failed but whose checks have since gone green.

verify-release-checks fails closed when the release commit's own checks are
still queued at its deadline, and every publish job behind it is then
skipped. The checks usually finish later; this notices that and dispatches
release.yml on the tag once. See docs/ci.md, "release-tag-watchdog".

The decision is `decide`, pure so scripts/lib/test_redispatch_stalled_release.py
can drive it. Idempotency lives in GitHub's own run history: a
workflow_dispatch run whose head_branch is the tag means it was already done.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PACKAGES = (
    ("server", ".release-please-manifest.server.json"),
    ("client", ".release-please-manifest.client.json"),
)
MAX_AGE_SECONDS = 72 * 3600
VERIFY_FAILED = {"failure", "cancelled", "timed_out"}


def required_checks(release_yml: str, component: str) -> list[str]:
    block = re.search(
        rf'^  verify-{component}-ci:\n(.*?)(?=^  \S)', release_yml, re.S | re.M
    )
    found = re.search(r'required_checks:\s*"([^"]*)"', block.group(1)) if block else None
    return found.group(1).split("|") if found else []


def checks_green(check_runs: list[dict], required: list[str]) -> bool:
    if not required:
        return False
    for name in required:
        matching = sorted(
            (c for c in check_runs if c.get("name") == name),
            key=lambda c: c.get("started_at") or "",
        )
        latest = matching[-1] if matching else None
        if not latest or latest.get("status") != "completed" or latest.get("conclusion") != "success":
            return False
    return True


def verify_conclusion(jobs: list[dict], component: str) -> str | None:
    for job in jobs:
        if job.get("name", "").startswith(f"verify-{component}-ci"):
            return job.get("conclusion") or "pending"
    return None


def decide(component, tag, sha, tag_age, runs, jobs_by_run, check_runs, required):
    """Return (should_dispatch, reason)."""
    if any(r["event"] == "workflow_dispatch" and r["head_branch"] == tag for r in runs):
        return False, "already dispatched"
    mine = [r for r in runs if r["head_sha"] == sha]
    if not mine:
        return False, "no release run for the commit"
    if any(r["status"] != "completed" for r in mine):
        return False, "a release run is still in flight"
    verdicts = [verify_conclusion(jobs_by_run[r["id"]], component) for r in mine]
    if "success" in verdicts:
        return False, "verify passed, so the builds ran"
    if not any(v in VERIFY_FAILED for v in verdicts):
        return False, "verify did not fail"
    if tag_age > MAX_AGE_SECONDS:
        return False, "tag is too old to recover automatically"
    if not checks_green(check_runs, required):
        return False, "release commit checks are not green yet"
    return True, "verify failed and the checks are green now"


def gh_json(*args: str):
    out = subprocess.run(["gh", "api", *args], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def gh_paginated(path: str, key: str) -> list[dict]:
    out = subprocess.run(
        ["gh", "api", path, "--paginate", "--jq", f".{key}[]"],
        check=True, capture_output=True, text=True,
    ).stdout
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True, cwd=REPO_ROOT).stdout.strip()


def main() -> int:
    repo = os.environ["GITHUB_REPOSITORY"]
    dry_run = os.environ.get("DRY_RUN") == "1"
    release_yml = (REPO_ROOT / ".github/workflows/release.yml").read_text()
    for component, manifest in PACKAGES:
        path = REPO_ROOT / manifest
        if not path.is_file():
            continue
        version = next(iter(json.loads(path.read_text()).values()))
        tag = f"{component}-v{version}"
        try:
            sha = git("rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}")
        except subprocess.CalledProcessError:
            print(f"{tag}: no tag yet, release-tag-watchdog owns that")
            continue
        tag_age = int(time.time()) - int(git("log", "-1", "--format=%ct", sha))
        base = f"repos/{repo}/actions/workflows/release.yml/runs"
        by_sha = gh_json(f"{base}?head_sha={sha}&per_page=100")["workflow_runs"]
        dispatched = gh_json(f"{base}?branch={tag}&event=workflow_dispatch&per_page=100")["workflow_runs"]
        relevant = {r["id"]: r for r in by_sha + dispatched}.values()
        jobs = {r["id"]: [] for r in relevant}
        for r in relevant:
            if r["status"] == "completed" and r["head_sha"] == sha:
                jobs[r["id"]] = gh_json(f"repos/{repo}/actions/runs/{r['id']}/jobs?per_page=100")["jobs"]
        checks = gh_paginated(f"repos/{repo}/commits/{sha}/check-runs", "check_runs")
        go, reason = decide(component, tag, sha, tag_age, list(relevant), jobs, checks,
                            required_checks(release_yml, component))
        print(f"{tag}: {'dispatch' if go else 'skip'} - {reason}")
        if go and not dry_run:
            subprocess.run(["gh", "workflow", "run", "release.yml", "--ref", tag], check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
