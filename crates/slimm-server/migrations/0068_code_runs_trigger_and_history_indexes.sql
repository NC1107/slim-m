-- SPDX-License-Identifier: AGPL-3.0-only
--
-- Three things a schema audit found missing, none of which changes a row's
-- meaning.
--
-- 1. code_runs never learned about soft deletion. Messages are only ever
--    tombstoned (deleted_at set), so its ON DELETE CASCADE from messages can
--    never fire, and no Rust path deletes from it either: every deleted message
--    that ever ran a code block left up to 64 KiB of output behind for good.
--    polls (0011), pinned_messages (0009) and app_surfaces (0067) all handle
--    this with the same AFTER UPDATE OF deleted_at trigger; code_runs gets it
--    too, plus a one-time sweep of the rows already orphaned.
--
-- 2. The moderation history feed (store/moderation_history.rs) pages resolved
--    reports by (resolved_at DESC, id DESC) and audit rows by
--    (created_at DESC, id DESC). reports' only index is the partial
--    reports_open on the opposite predicate (resolved_at IS NULL), and
--    moderation_audit_log's two indexes lead with subject_id and actor_id, so
--    both halves of every page were a full scan plus a sort. The two indexes
--    below match each query's predicate and order exactly.
--
-- 3. The account-deletion transaction (store/account_deletion.rs) anonymizes
--    eleven more columns than 0019 and 0047 indexed, each with
--    UPDATE ... SET col = NULL WHERE col = ? under SQLite's single write lock.
--    Partial on IS NOT NULL, like 0019 and 0043: every one of these columns
--    is nullable and is exactly what the sweep sets to NULL, so the index
--    shrinks as accounts are deleted rather than filling with rows the sweep
--    can never match again.

CREATE TRIGGER code_runs_on_message_delete
AFTER UPDATE OF deleted_at ON messages
WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
BEGIN
    DELETE FROM code_runs WHERE message_id = NEW.id;
END;

DELETE FROM code_runs
WHERE message_id IN (SELECT id FROM messages WHERE deleted_at IS NOT NULL);

CREATE INDEX reports_resolved
    ON reports(resolved_at DESC, id DESC) WHERE resolved_at IS NOT NULL;
CREATE INDEX moderation_audit_log_created_at
    ON moderation_audit_log(created_at DESC, id DESC);

CREATE INDEX message_forwards_origin_author
    ON message_forwards(origin_author_id) WHERE origin_author_id IS NOT NULL;
CREATE INDEX invites_created_by
    ON invites(created_by) WHERE created_by IS NOT NULL;
CREATE INDEX password_reset_codes_issued_by
    ON password_reset_codes(issued_by) WHERE issued_by IS NOT NULL;
CREATE INDEX reports_reporter
    ON reports(reporter_id) WHERE reporter_id IS NOT NULL;
CREATE INDEX reports_resolved_by
    ON reports(resolved_by) WHERE resolved_by IS NOT NULL;
CREATE INDEX member_timeouts_issued_by
    ON member_timeouts(issued_by) WHERE issued_by IS NOT NULL;
CREATE INDEX space_removals_removed_by
    ON space_removals(removed_by) WHERE removed_by IS NOT NULL;
CREATE INDEX polls_created_by
    ON polls(created_by) WHERE created_by IS NOT NULL;
CREATE INDEX app_surfaces_created_by
    ON app_surfaces(created_by) WHERE created_by IS NOT NULL;
CREATE INDEX pinned_messages_pinned_by
    ON pinned_messages(pinned_by) WHERE pinned_by IS NOT NULL;
CREATE INDEX custom_emoji_uploader
    ON custom_emoji(uploader_id) WHERE uploader_id IS NOT NULL;
