#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Restores a scripts/backup.py snapshot into a scratch location and checks
it, rather than trusting a backup nobody has ever restored.

Three things are verified, none of them by inference:

1. The database snapshot file, copied to a fresh path and opened on its
   own with nothing else present, passes `PRAGMA integrity_check`.
2. Every row in its `attachments` table has a file in the media mirror
   named after that row's own sha256, and the file's real, recomputed
   sha256 actually matches its name - not merely that a file with that
   name exists.
3. Every user the database marks as having an avatar has a file for it
   in the avatars mirror (existence only: an avatar carries no stored
   hash of its own to compare against).

    python3 scripts/restore-drill.py --backup-root /path/to/backups

Exits non-zero, and names every mismatch, if anything referenced by the
database is missing or corrupt in the backup. This is the property a
"restore drill" is for: a backup that has never been restored and checked
is a guess, not a backup.
"""
import argparse
import hashlib
import shutil
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--backup-root", required=True, help="the root scripts/backup.py wrote into"
    )
    parser.add_argument(
        "--db-snapshot",
        default=None,
        help="an explicit snapshot path; defaults to the newest under "
        "<backup-root>/db/",
    )
    parser.add_argument(
        "--scratch-dir",
        default=None,
        help="where to restore into; defaults to a fresh directory under "
        "<backup-root>/restore-drill/",
    )
    return parser.parse_args(argv)


def latest_snapshot(backup_root):
    snapshots = sorted(Path(backup_root, "db").glob("slimm-*.db"))
    return snapshots[-1] if snapshots else None


def restore_database(snapshot, scratch_dir):
    restored = scratch_dir / "slimm.db"
    shutil.copy2(snapshot, restored)
    return restored


def check_integrity(restored_db):
    conn = sqlite3.connect(f"file:{restored_db}?mode=ro", uri=True)
    try:
        return conn.execute("PRAGMA integrity_check").fetchone()[0]
    finally:
        conn.close()


def check_attachments(restored_db, mirror_dir):
    conn = sqlite3.connect(f"file:{restored_db}?mode=ro", uri=True)
    try:
        rows = conn.execute("SELECT sha256, size FROM attachments").fetchall()
    finally:
        conn.close()

    attachments_dir = Path(mirror_dir, "attachments")
    missing, mismatched, verified = [], [], 0
    for blob, size in rows:
        expected = blob.hex()
        path = attachments_dir / expected
        if not path.is_file():
            missing.append(expected)
            continue
        actual_bytes = path.read_bytes()
        actual = hashlib.sha256(actual_bytes).hexdigest()
        if actual != expected or len(actual_bytes) != size:
            mismatched.append((expected, actual, size, len(actual_bytes)))
            continue
        verified += 1
    return {
        "total": len(rows),
        "verified": verified,
        "missing": missing,
        "mismatched": mismatched,
    }


def check_avatars(restored_db, mirror_dir):
    conn = sqlite3.connect(f"file:{restored_db}?mode=ro", uri=True)
    try:
        rows = conn.execute(
            "SELECT id, username FROM users WHERE avatar_updated_at IS NOT NULL"
        ).fetchall()
    finally:
        conn.close()

    avatars_dir = Path(mirror_dir, "avatars")
    missing, verified = [], 0
    for blob, username in rows:
        name = str(uuid.UUID(bytes=blob))
        path = avatars_dir / name
        if not path.is_file() or path.stat().st_size == 0:
            missing.append((name, username))
            continue
        verified += 1
    return {"total": len(rows), "verified": verified, "missing": missing}


def run(args):
    backup_root = Path(args.backup_root)
    snapshot = Path(args.db_snapshot) if args.db_snapshot else latest_snapshot(backup_root)
    if snapshot is None or not snapshot.is_file():
        print(f"no database snapshot found under {backup_root}/db/", file=sys.stderr)
        return 1

    if args.scratch_dir:
        scratch_dir = Path(args.scratch_dir)
    else:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        scratch_dir = backup_root / "restore-drill" / timestamp
    scratch_dir.mkdir(parents=True, exist_ok=True)

    print(f"restoring {snapshot.name} into {scratch_dir}")
    restored_db = restore_database(snapshot, scratch_dir)

    integrity = check_integrity(restored_db)
    print(f"integrity_check: {integrity}")
    ok = integrity == "ok"

    attachments = check_attachments(restored_db, backup_root)
    print(
        f"attachments: {attachments['verified']}/{attachments['total']} verified, "
        f"{len(attachments['missing'])} missing, "
        f"{len(attachments['mismatched'])} hash mismatch"
    )
    for digest in attachments["missing"]:
        print(f"  MISSING    attachments/{digest}", file=sys.stderr)
    for expected, actual, expected_size, actual_size in attachments["mismatched"]:
        print(
            f"  MISMATCH   attachments/{expected} hashes to {actual} "
            f"({actual_size} bytes, expected {expected_size})",
            file=sys.stderr,
        )
    ok = ok and not attachments["missing"] and not attachments["mismatched"]

    avatars = check_avatars(restored_db, backup_root)
    print(f"avatars: {avatars['verified']}/{avatars['total']} verified, "
          f"{len(avatars['missing'])} missing")
    for name, username in avatars["missing"]:
        print(f"  MISSING    avatars/{name} (user {username})", file=sys.stderr)
    ok = ok and not avatars["missing"]

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(run(parse_args(sys.argv[1:])))
