-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
--
-- Polls: a message attachment carrying a question, 2-4 fixed ordered options,
-- and a per-user vote. Keyed by message_id rather than a surrogate id of its
-- own, since a poll never outlives or moves between messages - exactly the
-- same choice pinned_messages made for the same reason.
--
-- One vote per user per poll is enforced here, not only by the store: the
-- primary key is (message_id, user_id), so a changed vote is a REPLACE of
-- that row rather than a second one ever existing to double-count.
--
-- Messages are soft-deleted (deleted_at set; the row never actually goes
-- away), so an ON DELETE CASCADE from messages alone would never fire. The
-- trigger below fires the moment deleted_at is first set, exactly like
-- pinned_messages' own cleanup trigger, so a poll cannot outlive the message
-- that carries it regardless of which code path performs the delete.
CREATE TABLE polls (
    message_id BLOB PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    question   TEXT NOT NULL,
    close_at   INTEGER,             -- unix ms; null means it never closes
    created_by BLOB REFERENCES users(id) ON DELETE SET NULL,
    created_at INTEGER NOT NULL
) STRICT;

-- Options are ordered and fixed at creation, never edited or reordered, so
-- position doubles as the option's identity: a vote references (message_id,
-- position) directly rather than a surrogate option id.
CREATE TABLE poll_options (
    message_id BLOB NOT NULL REFERENCES polls(message_id) ON DELETE CASCADE,
    position   INTEGER NOT NULL,
    label      TEXT NOT NULL,
    PRIMARY KEY (message_id, position)
) STRICT, WITHOUT ROWID;

CREATE TABLE poll_votes (
    message_id BLOB NOT NULL REFERENCES polls(message_id) ON DELETE CASCADE,
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    position   INTEGER NOT NULL,
    voted_at   INTEGER NOT NULL,
    PRIMARY KEY (message_id, user_id),
    -- Ties a vote to one of that same poll's own options, so a vote can never
    -- point at an option row belonging to a different message.
    FOREIGN KEY (message_id, position) REFERENCES poll_options(message_id, position) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

-- Tallying groups by (message_id, position); the primary key above already
-- gives an index led by (message_id, user_id), which is the wrong leading
-- column for that grouping, so a dedicated index carries it instead.
CREATE INDEX poll_votes_by_option ON poll_votes(message_id, position);

CREATE TRIGGER polls_on_message_delete
AFTER UPDATE OF deleted_at ON messages
WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
BEGIN
    DELETE FROM polls WHERE message_id = NEW.id;
END;
