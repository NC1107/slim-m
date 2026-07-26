-- SPDX-License-Identifier: AGPL-3.0-only
--
-- Pinned messages: a per-channel highlight set a moderator curates, distinct
-- from ordinary message ordering. The primary key is the whole
-- (channel_id, message_id) pair, so pinning an already-pinned message is a
-- plain INSERT OR IGNORE rather than something the caller has to check for
-- first, the same reason reactions key on their own natural triple.
--
-- message_id references messages(id) - the UNIQUE identity column, not the
-- table's actual primary key of (channel_id, seq) - exactly like reactions
-- and message_attachments already do.
--
-- Messages are soft-deleted (deleted_at set; the row never actually goes
-- away), so an ON DELETE CASCADE foreign key alone would never fire, and a
-- pin would keep pointing at content the message list has already hidden -
-- a dangling reference the UI would render as a blank. The trigger below
-- fires the moment deleted_at is first set, from whichever code path
-- performs that UPDATE, so the cleanup happens no matter which delete path
-- runs and cannot be forgotten by a future one that does not know pins exist.
CREATE TABLE pinned_messages (
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    message_id BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    pinned_by  BLOB REFERENCES users(id) ON DELETE SET NULL,
    pinned_at  INTEGER NOT NULL,
    PRIMARY KEY (channel_id, message_id)
) STRICT, WITHOUT ROWID;

-- Newest-pin-first is the only listing order the store uses, and the channel
-- header's count is COUNT(*) over the same (channel_id, ...) key prefix, so
-- one index serves both reads.
CREATE INDEX pinned_messages_channel ON pinned_messages(channel_id, pinned_at DESC);

CREATE TRIGGER pinned_messages_on_delete
AFTER UPDATE OF deleted_at ON messages
WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
BEGIN
    DELETE FROM pinned_messages WHERE message_id = NEW.id;
END;
