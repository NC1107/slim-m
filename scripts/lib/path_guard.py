# SPDX-License-Identifier: Apache-2.0
"""Validates a database-sourced value before it becomes a filesystem path
component, for backup_lib.py and restore_drill_lib.py.

Both scripts build one path per attachment or avatar out of a value that
came out of the SQLite snapshot rather than off the command line: an
attachment's sha256, or a user id turned into an avatar's uuid filename.
A row that is not exactly what it claims to be - through a bug, a
hand-edited database, a future migration, or a restore of a tampered
snapshot - must not be trusted as a filename, so every such value is
validated here before it is ever joined onto a directory, and every
resulting path is confirmed to still resolve inside the root it was
built from before anything opens, reads or writes it.

This is deliberately not about the command-line arguments (--backup-root,
--media-dir and friends): those are chosen by the operator running the
script, who already has a shell on the box and needs no path check to
reach anywhere on it. The trust boundary this module defends is between
the database's own content and the filesystem, not between the operator
and the filesystem.
"""
import re
import uuid
from pathlib import Path

_SHA256_HEX = re.compile(r"^[0-9a-f]{64}$")
_UUID_TEXT = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


class PathValidationError(ValueError):
    """A database value did not validate as a safe path component."""


def sha256_hex(raw):
    if not isinstance(raw, (bytes, bytearray)) or len(raw) != 32:
        raise PathValidationError(f"attachments.sha256 is not a 32-byte digest: {raw!r}")
    digest = bytes(raw).hex()
    if not _SHA256_HEX.fullmatch(digest):
        raise PathValidationError(f"attachments.sha256 did not hex-encode cleanly: {raw!r}")
    return digest


def avatar_uuid(raw):
    if not isinstance(raw, (bytes, bytearray)) or len(raw) != 16:
        raise PathValidationError(f"users.id is not a 16-byte uuid: {raw!r}")
    text = str(uuid.UUID(bytes=bytes(raw)))
    if not _UUID_TEXT.fullmatch(text):
        raise PathValidationError(f"users.id did not format as a uuid: {raw!r}")
    return text


def contained_path(root, name):
    """Joins name onto root and proves the result still resolves as a
    direct child of root, so neither a traversal sequence nor a symlink
    planted in root can walk the result outside of it."""
    resolved_root = Path(root).resolve()
    candidate = (resolved_root / name).resolve()
    if candidate.parent != resolved_root:
        raise PathValidationError(f"{name!r} would not stay inside {resolved_root}")
    return candidate
