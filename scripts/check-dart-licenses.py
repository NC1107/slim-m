#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""The Dart half of the dependency-license gate.

cargo-deny covers the Rust tree; pub has no equivalent, so this reads
client/pubspec.lock, finds each hosted package in the pub cache, and
classifies its LICENSE text against the same allowlist cargo-deny uses, the
[licenses] table in deny.toml.

Classification is by license text rather than by a declared field because a
pub package declares no license anywhere in its pubspec; pub.dev derives it
from the LICENSE file too. A package whose text matches nothing known is an
error rather than a pass, since a gate that shrugs at what it cannot read is
not a gate. See docs/ci.md.
"""

import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path

GNU_FAMILY = [
    ("AGPL", "gnu affero general public license"),
    ("LGPL", "gnu lesser general public license"),
    ("GPL", "gnu general public license"),
]

MARKERS = [
    ("Apache-2.0", ["apache license", "version 2.0"]),
    ("MPL-2.0", ["mozilla public license"]),
    ("CC0-1.0", ["creative commons", "cc0"]),
    ("Unlicense", ["this is free and unencumbered software released into"]),
    ("BSL-1.0", ["boost software license"]),
    ("ISC", ["permission to use, copy, modify, and/or distribute", "above copyright notice"]),
    ("0BSD", ["permission to use, copy, modify, and/or distribute"]),
    ("MIT", ["permission is hereby granted, free of charge", "the software is provided"]),
]

BSD_STEM = "redistribution and use in source and binary forms"


def classify(text: str) -> str | None:
    flat = re.sub(r"\s+", " ", text.lower())
    # Title block only: MPL-2.0 names all three GNU licenses in its own body.
    head = flat[:600]
    for family, needle in GNU_FAMILY:
        if needle in head:
            version = "3.0" if "version 3" in head else "2.1" if family == "LGPL" else "2.0"
            return f"{family}-{version}-only"
    for name, needles in MARKERS:
        if all(n in flat for n in needles):
            return name
    if BSD_STEM in flat:
        if "endorse or promote" in flat:
            return "BSD-3-Clause"
        if "reproduce the above copyright" in flat:
            return "BSD-2-Clause"
        return "BSD-1-Clause"
    return None


def parse_lock(path: Path) -> list[tuple[str, str, str]]:
    """Every package in a pubspec.lock, as (name, version, source)."""
    packages: list[tuple[str, str, str]] = []
    current: dict[str, str] = {}
    in_packages = False
    for raw in path.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not raw.startswith(" "):
            in_packages = raw.startswith("packages:")
            continue
        if not in_packages:
            continue
        indent = len(raw) - len(raw.lstrip())
        line = raw.strip()
        if indent == 2 and line.endswith(":"):
            if current:
                packages.append(_finish(current, path))
            current = {"key": line[:-1].strip('"')}
        elif current:
            key, _, value = line.partition(":")
            value = value.strip().strip('"')
            if key in ("version", "source", "name") and value:
                current.setdefault(key, value)
    if current:
        packages.append(_finish(current, path))
    return packages


def _finish(entry: dict[str, str], path: Path) -> tuple[str, str, str]:
    name = entry.get("name", entry["key"])
    if "version" not in entry or "source" not in entry:
        sys.exit(f"::error file={path}::{name} has no version or source; lock format changed")
    return name, entry["version"], entry["source"]


def pub_cache() -> Path:
    """The first candidate root that actually holds unpacked pub.dev packages."""
    candidates = []
    if os.environ.get("PUB_CACHE"):
        candidates.append(Path(os.environ["PUB_CACHE"]))
    candidates.append(Path.home() / ".pub-cache")
    if os.environ.get("XDG_CACHE_HOME"):
        candidates.append(Path(os.environ["XDG_CACHE_HOME"]) / "dart")
    candidates.append(Path.home() / ".cache" / "dart")
    for candidate in candidates:
        if (candidate / "hosted" / "pub.dev").is_dir():
            return candidate
    sys.exit(
        "::error::no pub cache found in "
        + ", ".join(str(c) for c in candidates)
        + "; run 'flutter pub get' in client/ first"
    )


def license_text(name: str, version: str, cache: Path) -> tuple[Path, str] | None:
    root = cache / "hosted" / "pub.dev" / f"{name}-{version}"
    for candidate in ("LICENSE", "LICENSE.md", "LICENSE.txt", "license", "COPYING"):
        path = root / candidate
        if path.is_file():
            return path, path.read_text(errors="replace")
    return None


def main() -> int:
    root = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    )
    policy = tomllib.loads((root / "deny.toml").read_text())["licenses"]
    allowed = set(policy["allow"])
    exceptions = {e["name"]: set(e["allow"]) for e in policy.get("exceptions", [])}
    cache = pub_cache()

    lock = root / "client" / "pubspec.lock"
    packages = parse_lock(lock)
    if len(packages) < 50:
        print(f"::error file={lock}::only {len(packages)} packages parsed; the gate is not reading the lockfile")
        return 1

    workspace = {p.name for p in (root / "client" / "packages").iterdir() if p.is_dir()}
    failures: list[str] = []
    seen: dict[str, int] = {}
    hosted = 0
    unpacked = 0
    checked = 0

    for name, version, source in packages:
        if source != "hosted":
            if name not in workspace and source != "sdk":
                failures.append(f"{name} {version} comes from '{source}', not pub.dev; classify it by hand")
            continue
        hosted += 1
        if not (cache / "hosted" / "pub.dev" / f"{name}-{version}").is_dir():
            continue
        unpacked += 1
        found = license_text(name, version, cache)
        if found is None:
            failures.append(f"{name} {version} ships no LICENSE file in the pub cache")
            continue
        path, text = found
        spdx = classify(text)
        if spdx is None:
            failures.append(f"{name} {version} has a LICENSE this gate cannot identify ({path})")
            continue
        checked += 1
        seen[spdx] = seen.get(spdx, 0) + 1
        if spdx not in allowed and spdx not in exceptions.get(name, set()):
            failures.append(f"{name} {version} is {spdx}, which deny.toml does not allow")

    # A gate that skips what it cannot find would go green on an empty cache.
    if unpacked < hosted:
        failures.insert(
            0,
            f"only {unpacked} of {hosted} locked packages are unpacked under {cache}; "
            "run 'flutter pub get --enforce-lockfile' in client/ first",
        )

    for line in failures:
        print(f"::error file=client/pubspec.lock::{line}")
    summary = ", ".join(f"{k} {v}" for k, v in sorted(seen.items()))
    print(f"dart licenses: {checked} pub.dev packages checked ({summary})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
