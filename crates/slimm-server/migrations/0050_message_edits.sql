-- SPDX-License-Identifier: AGPL-3.0-only
-- Prior versions of an edited message, one row per superseded content, so a
-- reader can see a message's edit history. The current content stays on
-- `messages`; this table holds only what an edit replaced, captured just
-- before the `messages` row is overwritten.
--
-- Pure DDL. `edit_message` inserts the pre-edit content here inside the same
-- write transaction that updates `messages` and writes the op row, so a row
-- appears here exactly when an edit actually changed the content - never for
-- an edit that resolved to the same text (which writes nothing at all).
--
-- No content is cleared on delete: a soft-deleted message keeps its own
-- `content` too, so these rows are no more retained than the message they
-- belong to. The history read filters `deleted_at IS NULL` on the message,
-- the same gate `message` and `edit_message` already use, so a deleted
-- message exposes no history through the API. ON DELETE CASCADE is defence in
-- depth for any future path that truly removes a message row.

CREATE TABLE message_edits (
    -- INTEGER PRIMARY KEY is the rowid, so it rises with insertion order and
    -- orders one message's revisions chronologically with no separate counter,
    -- even for two edits within the same millisecond.
    id          INTEGER PRIMARY KEY,
    -- Spelled `messages(id)` deliberately: 0024 aliased that to `fts_rowid`.
    message_id  BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    -- The content this edit replaced (the version live before `replaced_at`).
    content     TEXT NOT NULL,
    replaced_at INTEGER NOT NULL
) STRICT;

-- "The revisions of this message, in order", for the history read.
CREATE INDEX message_edits_by_message ON message_edits(message_id, id);
