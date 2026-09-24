-- SPDX-License-Identifier: AGPL-3.0-only
-- Adds `bot_create`, `bot_revoke` and `bot_permission_grant` to
-- moderation_audit_log: two decision records (0028, 0021) already claimed bot
-- and module lifecycle land on this trail, and at HEAD neither one does.
-- `record_moderation_audit` had exactly five callers before this change, all
-- in messages.rs, messages_bulk.rs and removals.rs/timeouts.rs - none in
-- store/bots.rs. This is the fifth-write-path gap 0015's own decision record
-- predicted in as many words.
--
-- A rebuild rather than an ALTER, for the same reason 0049 needed one: SQLite
-- cannot widen a CHECK constraint in place. Copied from 0049's own template,
-- including its note that this table is never a foreign-key parent, so DROP
-- TABLE under foreign_keys=ON has nothing to cascade away here - but unlike
-- 0049, a later migration (0068) had added a third index since, so all three
-- are recreated below rather than only the two 0049 knew about.
--
-- subject_id is the bot's own user id for all three new actions. `until`
-- stays null for all three, which the existing moderation_audit_until CHECK's
-- ELSE branch already requires of anything but a timeout.
--
-- Module lifecycle (install/enable/grant) is not included here. 0021's claim
-- that it is already audited is corrected in the same change that adds this
-- migration, rather than wired up: that is a separate surface
-- (store/modules.rs, http/dock.rs) with its own shape questions, and bundling
-- it into a bot-focused change would mean shipping it without the same
-- scrutiny this migration's three actions got.
CREATE TABLE moderation_audit_log_new (
    id         INTEGER PRIMARY KEY,
    actor_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    subject_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action     TEXT NOT NULL,
    reason     TEXT,
    -- When a timeout was due to lift; null for the acts that have no deadline.
    until      INTEGER,
    created_at INTEGER NOT NULL,
    CONSTRAINT moderation_audit_action
        CHECK (action IN ('remove', 'restore', 'timeout', 'timeout_cleared',
                          'messages_deleted', 'bot_create', 'bot_revoke',
                          'bot_permission_grant')),
    -- A lift carries the deadline it cut short, or none if it found nothing.
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
