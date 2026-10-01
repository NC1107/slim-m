-- Space-local display names an administrator gives another member or bot
-- (decision 0053), and the two audit actions that record setting and clearing one.
--
-- A side table rather than a column on `users`: `users.display_name` stays the
-- account's own, the name it chose and still sees in its own profile, and the
-- hot `users` row every message and roster query reads does not grow. A row
-- exists only while a nickname is in force; clearing deletes it.
CREATE TABLE member_nicknames (
    user_id  BLOB PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    nickname TEXT NOT NULL,
    set_by   BLOB REFERENCES users(id) ON DELETE SET NULL,
    set_at   INTEGER NOT NULL
) STRICT;

-- A rebuild rather than an ALTER, for the reason 0094 needed one: SQLite cannot
-- widen a CHECK constraint in place. Copied from 0094's own template, all three
-- indexes recreated, and no PRAGMA foreign_keys = OFF for the swap, since this
-- table is never a foreign-key parent. The table has no triggers.
--
-- subject_id is the member or bot renamed, `until` stays null, and `reason`
-- carries the nickname set so the trail says what it was renamed to.
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
                          'account_delete', 'reset_code_issue',
                          'nickname_set', 'nickname_clear')),
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
