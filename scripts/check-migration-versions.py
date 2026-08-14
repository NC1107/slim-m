#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Guard the two migration mistakes that only surface at deployment startup.

`main-builds.yml` moves the `latest` server image on every push to main, and
the live instance auto-updates from it, so a migration reaching main is a
migration reaching production within minutes. sqlx records an applied
migration by version number and validates it by a checksum over the file's
own bytes, which makes two edits fatal after the fact:

1. Two files claiming the same version. sqlx keys applied migrations by
   version, so the second one is silently never applied on a database that
   already ran the first, and a fresh database fails outright on the UNIQUE
   constraint. Three files landed on 0044 during the 2026-08-13 merge train.

2. Renaming or editing a migration already on main. The version number is
   the key and the content is the checksum, so changing either makes an
   already-deployed database refuse every later startup with "migration N
   was previously applied but has been modified". That is what took the live
   instance down for five hours on 2026-08-13, and no test could see it: the
   suite only ever builds fresh databases, where the renumbered file applies
   perfectly.

Both are checked against `origin/main` rather than against a recorded list,
so nothing here can go stale.
"""

import hashlib
import pathlib
import re
import subprocess
import sys

MIGRATIONS = pathlib.Path("crates/slimm-server/migrations")
NAME = re.compile(r"^(\d+)_.*\.sql$")


def version_of(name: str) -> int | None:
    m = NAME.match(name)
    return int(m.group(1)) if m else None


def local_migrations() -> dict[int, tuple[str, str]]:
    found: dict[int, list[tuple[str, str]]] = {}
    for path in sorted(MIGRATIONS.glob("*.sql")):
        version = version_of(path.name)
        if version is None:
            continue
        digest = hashlib.sha384(path.read_bytes()).hexdigest()
        found.setdefault(version, []).append((path.name, digest))

    failed = False
    resolved: dict[int, tuple[str, str]] = {}
    for version, entries in sorted(found.items()):
        if len(entries) > 1:
            names = ", ".join(name for name, _ in entries)
            print(
                f"::error::migration {version:04d} is claimed by {len(entries)} files: {names}"
                " - sqlx keys an applied migration by version, so only one of these can ever run"
            )
            failed = True
        resolved[version] = entries[0]
    if failed:
        sys.exit(1)
    return resolved


def published_migrations() -> dict[int, tuple[str, str]] | None:
    listing = subprocess.run(
        ["git", "ls-tree", "-r", "--name-only", "origin/main", str(MIGRATIONS)],
        capture_output=True,
        text=True,
    )
    if listing.returncode != 0:
        return None

    published: dict[int, tuple[str, str]] = {}
    for line in listing.stdout.split():
        name = pathlib.PurePath(line).name
        version = version_of(name)
        if version is None:
            continue
        blob = subprocess.run(
            ["git", "show", f"origin/main:{line}"], capture_output=True
        )
        if blob.returncode != 0:
            continue
        published[version] = (name, hashlib.sha384(blob.stdout).hexdigest())
    return published


def main() -> int:
    if not MIGRATIONS.is_dir():
        print(f"::error::{MIGRATIONS} not found; run this from the repo root")
        return 1

    local = local_migrations()
    published = published_migrations()
    if published is None:
        print("origin/main unavailable; checked duplicate versions only")
        return 0

    failed = False
    for version, (name, digest) in sorted(published.items()):
        if version not in local:
            print(
                f"::error::migration {version:04d} ({name}) is on main and has been deleted"
                " - every deployed database has it applied and will refuse to start without it"
            )
            failed = True
            continue
        local_name, local_digest = local[version]
        if local_digest != digest:
            detail = (
                f"renamed to {local_name}" if local_name != name else "edited in place"
            )
            print(
                f"::error::migration {version:04d} ({name}) is on main and has been {detail}"
                " - a deployed database validates it by checksum and will refuse to start;"
                " add a new migration instead"
            )
            failed = True

    checked = len(published)
    print(f"migrations: {len(local)} local, {checked} already on main, all consistent"
          if not failed else f"migrations: {checked} checked against main")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
