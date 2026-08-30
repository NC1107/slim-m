-- SPDX-License-Identifier: AGPL-3.0-only
-- Blocking and reporting: the safety surface the app stores require, and the
-- one the owner chose (manual reports, no automated scanning).

-- One row per (blocker, blocked). Blocking is one-directional and private: the
-- blocked user is never told.
CREATE TABLE user_blocks (
    blocker_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (blocker_id, blocked_id)
) STRICT, WITHOUT ROWID;

-- Manual reports, queued for a human. Deliberately keeps a copy of the reported
-- content: the author can edit or delete it, and a report about something that
-- no longer exists is useless to a moderator.
CREATE TABLE reports (
    id            BLOB PRIMARY KEY,
    reporter_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    subject_kind  TEXT NOT NULL,            -- 'message' | 'user'
    subject_id    BLOB NOT NULL,
    channel_id    BLOB REFERENCES channels(id) ON DELETE SET NULL,
    reason        TEXT NOT NULL,
    snapshot      TEXT,                     -- the content as reported
    created_at    INTEGER NOT NULL,
    resolved_at   INTEGER,
    resolved_by   BLOB REFERENCES users(id) ON DELETE SET NULL,
    resolution    TEXT
) STRICT;
CREATE INDEX reports_open ON reports(created_at) WHERE resolved_at IS NULL;

-- A user cannot spam the same subject; one open report each.
CREATE UNIQUE INDEX reports_one_open_per_subject
    ON reports(reporter_id, subject_kind, subject_id) WHERE resolved_at IS NULL;
