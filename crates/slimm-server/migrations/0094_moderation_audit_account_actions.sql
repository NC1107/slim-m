-- Adds `account_delete` and `reset_code_issue` to moderation_audit_log: the two
-- most powerful admin acts, permanently deleting another account and issuing a
-- code that takes one over, were the only ones that left no trace.
--
-- A rebuild rather than an ALTER, for the reason 0092 needed one: SQLite cannot
-- widen a CHECK constraint in place. Copied from 0092's own template, all three
-- indexes recreated, and no PRAGMA foreign_keys = OFF for the swap, since this
-- table is never a foreign-key parent. The table has no triggers.
--
-- subject_id is the account deleted or the account the code is for, and `until`
-- stays null for both.
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
                          'webhook_revoke', 'webhook_rotate', 'totp_cleared',
                          'account_delete', 'reset_code_issue')),
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
