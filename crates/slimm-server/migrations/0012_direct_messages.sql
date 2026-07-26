-- SPDX-License-Identifier: AGPL-3.0-only
--
-- Direct messages: a DM is an ordinary channel (kind = 'dm' - no CHECK
-- constraint enforces the enum, exactly like 'text'/'voice' already are not
-- enforced, so this needs no schema change to the channels table itself)
-- plus this table recording its exactly two participants.
--
-- Normalized so the pair (a, b) and (b, a) always resolve to the same row and
-- hence the same channel: the store layer always writes the
-- lexicographically smaller user id as user_a before an insert, and the CHECK
-- below makes that invariant a schema fact rather than a convention a future
-- write path could quietly violate. The unique index is what actually makes
-- opening a DM idempotent under concurrency: two callers racing to open the
-- same pair can insert at most one row between them.
CREATE TABLE dm_channels (
    channel_id BLOB PRIMARY KEY REFERENCES channels(id) ON DELETE CASCADE,
    user_a     BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b     BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    CHECK (user_a < user_b)
) STRICT;

CREATE UNIQUE INDEX dm_channels_pair ON dm_channels(user_a, user_b);

-- The DM list reads "every pair this user is in" from either side.
CREATE INDEX dm_channels_user_b ON dm_channels(user_b);
