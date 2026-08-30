# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""A minimal, schema-faithful SQLite database and media tree for the backup
and restore-drill tests, so they exercise the real column shapes
(crates/slimm-server/migrations/0002_core_schema.sql and 0013_attachments.sql)
rather than a made-up one that could quietly drift from the real schema.

Deliberately narrower than the real schema: only the columns backup_lib.py
and restore_drill_lib.py actually read are declared, since a wider fixture
would just be more surface that could drift from the migrations unnoticed.
"""
import hashlib
import sqlite3
import uuid
from pathlib import Path

SCHEMA = """
CREATE TABLE users (
    id             BLOB PRIMARY KEY,
    username       TEXT NOT NULL,
    display_name   TEXT NOT NULL,
    created_at     INTEGER NOT NULL,
    avatar_updated_at INTEGER
) STRICT;

CREATE TABLE attachments (
    sha256       BLOB PRIMARY KEY,
    size         INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    created_at   INTEGER NOT NULL
) STRICT;
"""


def build_database(path, attachments=(), avatar_users=()):
    """attachments: (sha256_bytes, size, content_type) tuples.
    avatar_users: (user_id_bytes, username) tuples, each marked as having
    an avatar (avatar_updated_at set)."""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    try:
        conn.executescript(SCHEMA)
        conn.executemany(
            "INSERT INTO attachments (sha256, size, content_type, created_at) "
            "VALUES (?, ?, ?, 0)",
            attachments,
        )
        conn.executemany(
            "INSERT INTO users (id, username, display_name, created_at, avatar_updated_at) "
            "VALUES (?, ?, ?, 0, 1)",
            [(user_id, username, username) for user_id, username in avatar_users],
        )
        conn.commit()
    finally:
        conn.close()


def sha256_of(data):
    return hashlib.sha256(data).digest()


def new_user_id():
    return uuid.uuid4().bytes


def write_attachment_file(media_dir, sha256_bytes, data):
    directory = Path(media_dir, "attachments")
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / sha256_bytes.hex()
    path.write_bytes(data)
    return path


def write_avatar_file(media_dir, user_id_bytes, data):
    directory = Path(media_dir, "avatars")
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / str(uuid.UUID(bytes=user_id_bytes))
    path.write_bytes(data)
    return path
