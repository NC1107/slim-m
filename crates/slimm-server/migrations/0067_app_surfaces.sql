-- SPDX-License-Identifier: AGPL-3.0-only
--
-- App surfaces: a message that launches an installed module's `app` extension
-- point, rendered inline as an interactive, shared surface (a game, a tool)
-- rather than as text. The message carries only which module and command to
-- run; the surface's live, shared state is the module's own output, stored and
-- broadcast through code_runs at block 0 exactly like a run fenced code block -
-- so slim itself still has no notion of what any app does.
--
-- Keyed by message_id rather than a surrogate id of its own, since an app
-- surface never outlives or moves between messages - the same choice polls and
-- pinned_messages made for the same reason.
--
-- Messages are soft-deleted (deleted_at set; the row never actually goes away),
-- so an ON DELETE CASCADE from messages alone would never fire. The trigger
-- below fires the moment deleted_at is first set, exactly like polls' own
-- cleanup trigger, so an app surface cannot outlive the message that carries
-- it regardless of which code path performs the delete.
CREATE TABLE app_surfaces (
    message_id BLOB PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    module_id  TEXT NOT NULL,
    command    TEXT NOT NULL,
    created_by BLOB REFERENCES users(id) ON DELETE SET NULL,
    created_at INTEGER NOT NULL
) STRICT;

CREATE TRIGGER app_surfaces_on_message_delete
AFTER UPDATE OF deleted_at ON messages
WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
BEGIN
    DELETE FROM app_surfaces WHERE message_id = NEW.id;
END;
