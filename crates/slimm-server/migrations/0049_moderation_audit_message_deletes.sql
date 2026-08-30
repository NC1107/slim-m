-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Adds `messages_deleted` to `moderation_audit_log`: a moderator removing
-- somebody's messages in bulk is a moderation act, and 0048's action set had
-- no room for one.
--
-- 0015's own decision record predicted this gap in as many words - "a future
-- bulk-unban tool, an admin CLI, or a fifth write path added by somebody who
-- has not read store/moderation_audit.rs will leave the log quietly
-- under-reporting" - so this is the anticipated case arriving, not a surprise.
--
-- A rebuild rather than an ALTER, because SQLite cannot widen a CHECK in
-- place. 0034_canvas_move.sql did the same for the same reason and records the
-- trap that cost it a first attempt: under `foreign_keys=ON`, which db.rs runs
-- with throughout, `DROP TABLE` fires `ON DELETE CASCADE` on children exactly
-- as a DELETE would, and 0034's first version lost every dependent row that
-- way. That trap does not reach here, and this says so rather than leaving the
-- next reader to re-derive it: nothing in the schema references
-- moderation_audit_log as a parent, so there is nothing to cascade to. Its own
-- two foreign keys point outward at `users`, which this does not touch.
--
-- Everything else is copied exactly. `subject_id` stays NOT NULL because a row
-- still names one person the act was about: a bulk delete spanning K authors
-- writes K rows, one per author, rather than one row naming none of them.
-- `until` stays null for the new action, which the existing
-- moderation_audit_until CHECK already requires of anything but a timeout.
--
-- Deliberately no `PRAGMA foreign_keys = OFF` around the swap. It would be a
-- no-op here anyway - sqlx runs a migration inside a transaction and that
-- pragma is ignored within one, which is exactly why 0024 records that the
-- pragma-based procedure "needs PRAGMA foreign_keys = OFF and therefore a
-- COMMIT" and does not use it. No migration in this schema does. Writing one
-- here would read as protection that is not being applied, which is worse
-- than the nothing this actually needs.
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
                          'messages_deleted')),
    -- A lift carries the deadline it cut short, or none if it found nothing.
    CONSTRAINT moderation_audit_until CHECK (
        CASE action
            WHEN 'timeout' THEN until IS NOT NULL
            WHEN 'timeout_cleared' THEN 1
            ELSE until IS NULL
        END
    )
) STRICT;

-- Ids carried across, not reassigned: `id` is the rowid and its order is the
-- only thing that says what happened first, which a read of one member's
-- history depends on.
INSERT INTO moderation_audit_log_new
    (id, actor_id, subject_id, action, reason, until, created_at)
SELECT id, actor_id, subject_id, action, reason, until, created_at
FROM moderation_audit_log;

DROP TABLE moderation_audit_log;
ALTER TABLE moderation_audit_log_new RENAME TO moderation_audit_log;

-- Both indexes are recreated: a rebuild drops them with the old table.
CREATE INDEX moderation_audit_log_subject ON moderation_audit_log(subject_id, created_at);
CREATE INDEX moderation_audit_log_actor ON moderation_audit_log(actor_id) WHERE actor_id IS NOT NULL;
