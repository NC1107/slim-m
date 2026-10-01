#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Fail when a published release is missing assets its kind always carries.

release-please publishes the GitHub Release before any asset job runs, so a
release is public while its builds can still fail; client 0.89.0 shipped
without its Windows zip and update manifest and nothing said so. See
docs/ci.md, "release-asset-watchdog".

`judge` is pure so scripts/lib/test_check_release_assets.py can drive it.
Exit 0 when every judged release is complete or still pending, 1 when one
is missing assets.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

DEFAULT_REPO = "Slim-m-org/slim-m"

# One regex per required asset; {v} is the tag's version. Kept in sync with
# release.yml, desktop-clients.yml and update-manifest.yml, and with the
# complete releases client-v0.89.0 (10 assets) and server-v0.77.0 (3).
REQUIRED = {
    "client-v": [
        r"manifest\.json",
        r"manifest\.json\.sig",
        r"SHA256SUMS",
        r"SHA256SUMS\.android",
        r"slim-m-client-{v}-\d+\.fc\d+\.x86_64\.rpm",
        r"slim-m-client-{v}-linux-amd64\.tar\.gz",
        r"slim-m-client-{v}-macos\.zip",
        r"slim-m-client-{v}-windows-x64\.zip",
        r"slim-m-client-{v}\.flatpak",
        r"slim-m-client-android\.apk",
    ],
    "server-v": [
        r"SHA256SUMS",
        r"slimm-server-{v}-linux-amd64",
        r"slimm-server-{v}-linux-arm64",
    ],
}


def describe(pattern, version):
    """A pattern as a readable file name, e.g. slim-m-client-0.89.0-windows-x64.zip."""
    name = pattern.format(v=version)
    name = name.replace(r"\d+\.fc\d+", "<n>.fc<nn>")
    return name.replace("\\", "")


def judge(tag, names, published_at, now, grace):
    """Returns (status, missing): status is ok, pending, incomplete or ignored."""
    prefix = next((p for p in REQUIRED if tag.startswith(p)), None)
    if prefix is None:
        return "ignored", []
    version = re.escape(tag[len(prefix):])
    missing = [
        describe(pattern, tag[len(prefix):])
        for pattern in REQUIRED[prefix]
        if not any(re.fullmatch(pattern.format(v=version), n) for n in names)
    ]
    if not missing:
        return "ok", []
    if now - published_at < grace:
        return "pending", missing
    return "incomplete", missing


def gh_get(path):
    done = subprocess.run(
        ["gh", "api", path], capture_output=True, text=True, check=True
    )
    return json.loads(done.stdout)


def usable_names(release):
    """Asset names, leaving out an empty upload, which is as good as absent."""
    return [a["name"] for a in release.get("assets", []) if a.get("size", 1) > 0]


def parse_time(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def releases_to_check(repo, tag, recent_days, now):
    if tag:
        return [gh_get(f"repos/{repo}/releases/tags/{tag}")]
    cutoff = now - timedelta(days=recent_days)
    listing = gh_get(f"repos/{repo}/releases?per_page=100")
    return [
        r for r in listing
        if not r.get("draft") and parse_time(r["published_at"]) >= cutoff
    ]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("tag", nargs="?", help="one release tag, e.g. client-v0.89.0")
    ap.add_argument("--recent", type=float, metavar="DAYS",
                    help="every client-v* and server-v* release published in this window")
    ap.add_argument("--grace-minutes", type=float, default=90,
                    help="a release younger than this is pending, not failing")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPO))
    args = ap.parse_args(argv)
    if bool(args.tag) == (args.recent is not None):
        ap.error("give a tag or --recent DAYS, not both and not neither")

    now = datetime.now(timezone.utc)
    grace = timedelta(minutes=args.grace_minutes)
    failed = False
    for release in releases_to_check(args.repo, args.tag, args.recent, now):
        tag = release["tag_name"]
        status, missing = judge(
            tag, usable_names(release), parse_time(release["published_at"]), now, grace
        )
        if status == "ignored":
            continue
        detail = f": missing {', '.join(missing)}" if missing else ""
        print(f"{status.upper():10} {tag}{detail}")
        failed = failed or status == "incomplete"
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
