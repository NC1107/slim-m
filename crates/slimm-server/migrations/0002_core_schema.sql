-- SPDX-License-Identifier: AGPL-3.0-only
-- Phase 1 core schema: users, auth, RBAC, channels, messages, reactions,
-- attachments, invites, read state, and the canvas tables.
--
-- Conventions:
--   ids            UUIDv7 stored as a 16-byte BLOB (time-ordered, so it sorts
--                  chronologically and keeps good B-tree locality).
--   timestamps     INTEGER unix milliseconds.
--   permissions    a 63-bit bitmask in an INTEGER column.
--   ordering       a per-scope monotonic INTEGER `seq` from channel_seq_counters
--                  is the authoritative total order within one stream; UUIDv7
--                  is identity only.
-- The canvas spatial R-Tree index is added with the Voice Canvas build (Phase 6);
-- the canvas tables themselves exist now so the ordering model is uniform.

-- ---------------------------------------------------------------------------
-- Identity and auth
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id             BLOB PRIMARY KEY,
    username       TEXT NOT NULL,
    display_name   TEXT NOT NULL,
    password_hash  TEXT,                 -- Argon2id; null once anonymized
    created_at     INTEGER NOT NULL,
    deleted_at     INTEGER,              -- tombstone: set on account deletion
    is_anonymized  INTEGER NOT NULL DEFAULT 0
) STRICT;

-- Usernames are unique only among live accounts, so a deleted user's name frees up.
CREATE UNIQUE INDEX users_username_live ON users(username) WHERE deleted_at IS NULL;

CREATE TABLE devices (
    id                  BLOB PRIMARY KEY,
    user_id             BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    push_token_ref      TEXT,            -- opaque relay token handle, not a raw token
    voip_push_token_ref TEXT,
    push_public_key     BLOB,            -- per-device key for content-free encrypted push
    created_at          INTEGER NOT NULL,
    last_seen_at        INTEGER
) STRICT;
CREATE INDEX devices_user ON devices(user_id);

CREATE TABLE sessions (
    id           BLOB PRIMARY KEY,
    user_id      BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id    BLOB NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    created_at   INTEGER NOT NULL,
    last_used_at INTEGER,
    revoked_at   INTEGER
) STRICT;
CREATE INDEX sessions_user ON sessions(user_id);

-- Opaque refresh tokens with a rotating family so a replayed (already-used) token
-- revokes the whole family. Stored only as a hash.
CREATE TABLE refresh_tokens (
    token_hash TEXT PRIMARY KEY,
    session_id BLOB NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    family_id  BLOB NOT NULL,
    issued_at  INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    used_at    INTEGER,
    revoked_at INTEGER
) STRICT;
CREATE INDEX refresh_tokens_family ON refresh_tokens(family_id);

-- Admin-issued one-time reset codes (the no-email recovery path). Hash only.
CREATE TABLE password_reset_codes (
    code_hash  TEXT PRIMARY KEY,
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    issued_by  BLOB REFERENCES users(id) ON DELETE SET NULL,
    issued_at  INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    used_at    INTEGER
) STRICT;

-- ---------------------------------------------------------------------------
-- Roles and permissions (deny-by-default, one community per deployment)
-- ---------------------------------------------------------------------------
CREATE TABLE roles (
    id          BLOB PRIMARY KEY,
    name        TEXT NOT NULL,
    permissions INTEGER NOT NULL DEFAULT 0,  -- 63-bit bitmask
    position    INTEGER NOT NULL DEFAULT 0,  -- higher wins for hierarchy display
    is_everyone INTEGER NOT NULL DEFAULT 0,  -- the @everyone base role
    created_at  INTEGER NOT NULL
) STRICT;

CREATE TABLE member_roles (
    user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id BLOB NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
) STRICT, WITHOUT ROWID;

-- ---------------------------------------------------------------------------
-- Channels and per-scope ordering
-- ---------------------------------------------------------------------------
CREATE TABLE channels (
    id         BLOB PRIMARY KEY,
    name       TEXT NOT NULL,
    kind       TEXT NOT NULL,             -- 'text' | 'voice'
    topic      TEXT,
    position   INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    deleted_at INTEGER
) STRICT;

-- Polymorphic allow/deny overwrites, per role or per member, evaluated after the
-- role union with member overwrites absolute.
CREATE TABLE channel_overwrites (
    channel_id  BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    target_type TEXT NOT NULL,            -- 'role' | 'member'
    target_id   BLOB NOT NULL,
    allow       INTEGER NOT NULL DEFAULT 0,
    deny        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (channel_id, target_type, target_id)
) STRICT, WITHOUT ROWID;

-- One monotonic counter per (channel, stream). A channel's messages and its
-- canvas ops are independent sequence spaces.
CREATE TABLE channel_seq_counters (
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    stream     TEXT NOT NULL,             -- 'message' | 'canvas'
    next_seq   INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (channel_id, stream)
) STRICT, WITHOUT ROWID;

-- ---------------------------------------------------------------------------
-- Messages and reactions
-- ---------------------------------------------------------------------------
CREATE TABLE messages (
    id           BLOB NOT NULL UNIQUE,    -- UUIDv7 identity; rowid drives FTS
    channel_id   BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    author_id    BLOB REFERENCES users(id) ON DELETE SET NULL,  -- null once author anonymized
    seq          INTEGER NOT NULL,
    content      TEXT NOT NULL DEFAULT '',
    is_encrypted INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    edited_at    INTEGER,
    deleted_at   INTEGER,
    PRIMARY KEY (channel_id, seq)
) STRICT;
-- Keyset pagination and unread counts read newest-first, live rows only.
CREATE INDEX messages_channel_live ON messages(channel_id, seq DESC) WHERE deleted_at IS NULL;

CREATE TABLE reactions (
    message_id BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji      TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (message_id, user_id, emoji)
) STRICT, WITHOUT ROWID;

-- ---------------------------------------------------------------------------
-- Attachments (content-addressed; blobs live on disk, metadata here)
-- ---------------------------------------------------------------------------
CREATE TABLE attachments (
    sha256       BLOB PRIMARY KEY,        -- 32 bytes; the storage key
    size         INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    key_version  INTEGER NOT NULL DEFAULT 0,
    is_encrypted INTEGER NOT NULL DEFAULT 1,
    created_at   INTEGER NOT NULL
) STRICT;

CREATE TABLE message_attachments (
    message_id BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    sha256     BLOB NOT NULL REFERENCES attachments(sha256) ON DELETE RESTRICT,
    position   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (message_id, sha256)
) STRICT, WITHOUT ROWID;

-- ---------------------------------------------------------------------------
-- Read state and invites
-- ---------------------------------------------------------------------------
CREATE TABLE read_states (
    user_id       BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel_id    BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    last_read_seq INTEGER NOT NULL DEFAULT 0,
    updated_at    INTEGER NOT NULL,
    PRIMARY KEY (user_id, channel_id)
) STRICT, WITHOUT ROWID;

CREATE TABLE invites (
    code       TEXT PRIMARY KEY,
    created_by BLOB REFERENCES users(id) ON DELETE SET NULL,
    role_grant BLOB REFERENCES roles(id) ON DELETE SET NULL,
    max_uses   INTEGER,                   -- null = unlimited
    uses       INTEGER NOT NULL DEFAULT 0,
    expires_at INTEGER,
    created_at INTEGER NOT NULL,
    revoked_at INTEGER
) STRICT;

-- ---------------------------------------------------------------------------
-- Canvas (tables only for now; spatial R-Tree index arrives in Phase 6)
-- ---------------------------------------------------------------------------
CREATE TABLE canvas_objects (
    id           BLOB NOT NULL UNIQUE,
    channel_id   BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    kind         TEXT NOT NULL,           -- 'stroke' | 'image' | 'gif' | 'window'
    z_index      INTEGER NOT NULL DEFAULT 0,
    x            REAL NOT NULL DEFAULT 0,
    y            REAL NOT NULL DEFAULT 0,
    w            REAL NOT NULL DEFAULT 0,
    h            REAL NOT NULL DEFAULT 0,
    props        TEXT NOT NULL DEFAULT '{}',
    author_id    BLOB REFERENCES users(id) ON DELETE SET NULL,
    seq          INTEGER NOT NULL,
    is_encrypted INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    deleted_at   INTEGER,
    PRIMARY KEY (channel_id, seq)
) STRICT;

CREATE TABLE canvas_ops (
    id           BLOB NOT NULL UNIQUE,
    channel_id   BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    seq          INTEGER NOT NULL,
    author_id    BLOB REFERENCES users(id) ON DELETE SET NULL,
    op           TEXT NOT NULL,
    is_encrypted INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    PRIMARY KEY (channel_id, seq)
) STRICT;

-- ---------------------------------------------------------------------------
-- Full-text search over plaintext messages (external-content FTS5)
-- ---------------------------------------------------------------------------
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='rowid',
    tokenize='unicode61'
);

CREATE TRIGGER messages_fts_ai AFTER INSERT ON messages WHEN NEW.is_encrypted = 0 BEGIN
    INSERT INTO messages_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
END;

CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', OLD.rowid, OLD.content);
END;

CREATE TRIGGER messages_fts_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', OLD.rowid, OLD.content);
    INSERT INTO messages_fts(rowid, content) SELECT NEW.rowid, NEW.content WHERE NEW.is_encrypted = 0;
END;
