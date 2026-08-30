# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Records a NEW migration's checksum in migrations.lock.json.

Only ever adds. It refuses to rewrite an entry that already exists, because
changing one is exactly the mistake the lockfile is there to catch: a
deployed database validates every applied migration by this checksum and
refuses to start when it differs.
"""

import hashlib
import json
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATIONS = REPO_ROOT / "crates" / "slimm-server" / "migrations"
LOCKFILE = REPO_ROOT / "crates" / "slimm-server" / "migrations.lock.json"


def main() -> int:
    locked = json.loads(LOCKFILE.read_text()) if LOCKFILE.exists() else {}
    added, conflicts = [], []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        if not re.match(r"^\d+_", path.name):
            continue
        digest = hashlib.sha384(path.read_bytes()).hexdigest()
        if path.name in locked:
            if locked[path.name] != digest:
                conflicts.append(path.name)
            continue
        locked[path.name] = digest
        added.append(path.name)

    if conflicts:
        print(
            "refusing to rewrite an existing entry: "
            f"{conflicts}\nThose migrations were modified after being locked. "
            "A deployed database will refuse to start. Revert the edit and "
            "fix the mistake with a NEW migration instead.",
            file=sys.stderr,
        )
        return 1

    LOCKFILE.write_text(json.dumps(locked, indent=2, sort_keys=True) + "\n")
    print(f"locked {len(added)} new migration(s): {added or 'none'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
