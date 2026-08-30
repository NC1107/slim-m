-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- `messages_channel_live(channel_id, seq DESC)` and `messages_author(author_id)`
-- (0002, 0019) each serve half of "this author's live messages in this
-- channel since T"; neither serves all three, so a moderator selecting a
-- raider's recent messages by author and time window would otherwise walk
-- every live message the channel has ever held.
--
-- `created_at` rather than `seq` as the range column: the window this serves
-- is a time window ("the last N minutes"), and `seq` is a per-channel
-- counter with no fixed relationship to wall-clock time across authors.
-- Partial on `deleted_at IS NULL`, the same shape `messages_channel_live` and
-- `messages_live_created_at` (0044) already use, since a soft-deleted row is
-- exactly what this selection never wants to find.
CREATE INDEX messages_author_channel_window
    ON messages(channel_id, author_id, created_at) WHERE deleted_at IS NULL;
