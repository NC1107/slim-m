-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- A minimal moderation trail for canvas remove/clear/restore, independent of
-- and outliving canvas_ops itself.
--
-- canvas_ops.rs's own doc comment names an uncompacted op stream as "the
-- point" that lets a moderator see who removed what, durably. The sweep this
-- migration accompanies starts deleting old remove/clear/restore rows once
-- nothing they touched is still unrestored, which breaks that promise for
-- anything old enough to be swept unless something else keeps the record.
--
-- One row per touched object per action, the shape
-- docs/research/database-review.md's finding 13 suggested. 'place' is
-- deliberately not logged here: canvas_objects.author_id already carries
-- that durably (canvas_objects is never swept - see 0026's own doc comment),
-- so a second copy of the same fact would just be a second place for it to
-- drift.
--
-- actor_id is nulled on account deletion, the same treatment canvas_ops and
-- message_ops already give theirs. No HTTP route reads this table, so it is
-- readable from SQL and nowhere else - the same shape message_ops's own
-- trail already established, and it carries no sweep of its own: "kept
-- longer" than the fine-grained op log is satisfied by not touching it at
-- all here, the same way message_ops itself grows without a sweep.
CREATE TABLE canvas_audit_log (
    id         INTEGER PRIMARY KEY,
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    object_id  BLOB NOT NULL REFERENCES canvas_objects(id),
    actor_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    action     TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    CONSTRAINT canvas_audit_action CHECK (action IN ('remove', 'clear', 'restore'))
) STRICT;

-- A moderator's own read, once one exists, pages one channel newest-first.
CREATE INDEX canvas_audit_log_channel ON canvas_audit_log(channel_id, created_at);

-- Account deletion filters by actor, the same shape canvas_ops_author and
-- message_ops_actor already use.
CREATE INDEX canvas_audit_log_actor ON canvas_audit_log(actor_id) WHERE actor_id IS NOT NULL;
