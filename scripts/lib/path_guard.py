# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
import uuid
from pathlib import Path


class PathValidationError(ValueError):
    """A database value did not validate as a safe path component."""


def sha256_hex(raw):
    """A bytes object of exactly 32 bytes always hex-encodes to 64 lowercase
    hex characters, so checking the source length is checking the result."""
    if not isinstance(raw, (bytes, bytearray)) or len(raw) != 32:
        raise PathValidationError(f"attachments.sha256 is not a 32-byte digest: {raw!r}")
    return bytes(raw).hex()


def avatar_uuid(raw):
    """A bytes object of exactly 16 bytes always formats as a canonical
    lowercase uuid, so checking the source length is checking the result."""
    if not isinstance(raw, (bytes, bytearray)) or len(raw) != 16:
        raise PathValidationError(f"users.id is not a 16-byte uuid: {raw!r}")
    return str(uuid.UUID(bytes=bytes(raw)))


def contained_path(root, name):
    """Joins name onto root and proves the result still resolves as a
    direct child of root, so neither a traversal sequence nor a symlink
    planted in root can walk the result outside of it."""
    resolved_root = Path(root).resolve()
    candidate = (resolved_root / name).resolve()
    if candidate.parent != resolved_root:
        raise PathValidationError(f"{name!r} would not stay inside {resolved_root}")
    return candidate
