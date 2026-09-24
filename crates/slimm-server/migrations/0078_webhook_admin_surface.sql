-- Adds what the webhook admin surface needs that delivery (0073) did not:
-- who minted a webhook, and `webhook_create`/`webhook_revoke` on the
-- moderation audit trail, the same lifecycle 0077 gave bots.
--
-- created_by is nullable (ON DELETE SET NULL) rather than NOT NULL: the
-- minting admin's account can later be deleted while the webhook they made
-- keeps working, the same way a message's author_id survives its author's
-- deletion.
ALTER TABLE webhooks ADD COLUMN created_by BLOB REFERENCES users(id) ON DELETE SET NULL;

-- A rebuild rather than an ALTER, for the reason 0049 and 0077 both needed
-- one: SQLite cannot widen a CHECK constraint in place. Copied from 0077's
-- own template.
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
                          'webhook_revoke')),
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
