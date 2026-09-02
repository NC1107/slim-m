-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Messages one person kept for themselves.
--
-- The private counterpart to `pinned_messages` (0009), and deliberately not
-- an extension of it. A pin is a property of a channel that everyone in it
-- sees and MANAGE_MESSAGES controls; this is a property of one account that
-- nobody else can read, add to, or count. Sharing one table between the two
-- would mean every pin read carrying a "whose?" filter it has no use for,
-- and one permission bug leaking a private list into a public list.
--
-- Keyed by user and message with no channel column, because a saved list is
-- inherently cross-channel: it is "things I kept", not "things kept here".
-- The channel is reachable through the message whenever it is needed, and
-- storing it again would be a second copy to keep in step with a message
-- that can never move channels anyway.
--
-- Both foreign keys cascade, which is right in both directions: deleting an
-- account takes its private list with it, and hard-deleting a message (which
-- only happens when its channel goes) takes every save of it. Note that an
-- ordinary message delete is a tombstone rather than a row removal, so the
-- cascade does not fire for it - reads filter `messages.deleted_at`
-- themselves, exactly as `list_pinned_messages` already does.
--
-- WITHOUT ROWID for the same reason 0009 uses it: the primary key is the
-- whole row, so a separate rowid would be pure overhead.
CREATE TABLE saved_messages (
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    saved_at   INTEGER NOT NULL,
    PRIMARY KEY (user_id, message_id)
) STRICT, WITHOUT ROWID;

-- The list reads one user's saves newest first, which is the only read this
-- table has; the primary key orders by message id, which is not that.
CREATE INDEX saved_messages_recent ON saved_messages(user_id, saved_at DESC);
