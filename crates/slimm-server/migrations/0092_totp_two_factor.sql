-- SPDX-License-Identifier: AGPL-3.0-only
-- Optional TOTP second factor (decision 0048).
--
-- `secret` is the one bearer secret in this schema that is NOT hashed, and
-- that is forced rather than chosen: TOTP is a shared secret, so the server
-- has to recompute HMAC from it on every verification. Everything else about
-- the factor (recovery codes, sign-in challenges) follows the existing
-- hash-only rule, and decision 0048 records what a database leak does and does
-- not buy an attacker here.
CREATE TABLE user_totp_factors (
    user_id         BLOB PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    secret          TEXT NOT NULL,
    created_at      INTEGER NOT NULL,
    -- Null until a code has been verified, which is what "enabled" means:
    -- an enrolment nobody proved they could read is never enforced at
    -- sign-in, so a mis-scanned QR cannot lock anybody out.
    confirmed_at    INTEGER,
    -- The highest counter step already spent, so a code cannot be replayed
    -- and neither can an earlier still-in-window one.
    last_step       INTEGER,
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    -- Set past a run of failures. Persistent, unlike the in-process rate
    -- limiter, so a restart does not hand an attacker a fresh budget.
    locked_until    INTEGER
) STRICT;

CREATE TABLE totp_recovery_codes (
    code_hash  TEXT PRIMARY KEY,
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    used_at    INTEGER
) STRICT;

CREATE INDEX totp_recovery_codes_user ON totp_recovery_codes(user_id);

-- A password that was accepted but has not yet met the second factor. Holds
-- the device fields from the login request so the follow-up call cannot name a
-- different device than the one the password was presented for.
CREATE TABLE totp_challenges (
    challenge_hash TEXT PRIMARY KEY,
    user_id        BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name    TEXT NOT NULL,
    client_kind    TEXT,
    client_version TEXT,
    issued_at      INTEGER NOT NULL,
    expires_at     INTEGER NOT NULL,
    used_at        INTEGER
) STRICT;

CREATE INDEX totp_challenges_expiry ON totp_challenges(expires_at);
CREATE INDEX totp_challenges_user ON totp_challenges(user_id);

-- Whether this deployment offers, ignores, or insists on the factor. Validated
-- in Rust (`store::space`), as `join_policy` is, since SQLite cannot add a
-- CHECK constraint to an existing table.
ALTER TABLE space_settings ADD COLUMN totp_policy TEXT NOT NULL DEFAULT 'optional';

-- `totp_cleared` joins moderation_audit_log: an administrator removing
-- somebody's second factor is the one admin act that can hand an account back
-- to whoever asked for it, so decision 0048 requires it to leave a trace.
--
-- A rebuild rather than an ALTER, for the reason 0077, 0078 and 0086 needed
-- one: SQLite cannot widen a CHECK constraint in place. Copied from 0086's own
-- template, all three indexes recreated, and no PRAGMA foreign_keys = OFF for
-- the swap, since this table is never a foreign-key parent.
--
-- subject_id is the account whose factor was cleared and `until` stays null.
CREATE TABLE moderation_audit_log_new (
    id         INTEGER PRIMARY KEY,
    actor_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    subject_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action     TEXT NOT NULL,
    reason     TEXT,
    until      INTEGER,
    created_at INTEGER NOT NULL,
    CONSTRAINT moderation_audit_action
        CHECK (action IN ('remove', 'restore', 'timeout', 'timeout_cleared',
                          'messages_deleted', 'bot_create', 'bot_revoke',
                          'bot_permission_grant', 'webhook_create',
                          'webhook_revoke', 'webhook_rotate', 'totp_cleared')),
    CONSTRAINT moderation_audit_until CHECK (
        CASE action
            WHEN 'timeout' THEN until IS NOT NULL
            WHEN 'timeout_cleared' THEN 1
            ELSE until IS NULL
        END
    )
) STRICT;

INSERT INTO moderation_audit_log_new
    (id, actor_id, subject_id, action, reason, until, created_at)
SELECT id, actor_id, subject_id, action, reason, until, created_at
FROM moderation_audit_log;

DROP TABLE moderation_audit_log;
ALTER TABLE moderation_audit_log_new RENAME TO moderation_audit_log;

CREATE INDEX moderation_audit_log_subject ON moderation_audit_log(subject_id, created_at);
CREATE INDEX moderation_audit_log_actor ON moderation_audit_log(actor_id) WHERE actor_id IS NOT NULL;
CREATE INDEX moderation_audit_log_created_at
    ON moderation_audit_log(created_at DESC, id DESC);
