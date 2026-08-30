-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Widens dm_channels' pair ordering to admit a self pair (user_a = user_b),
-- the row `open_dm` now writes for a personal space: a DM with no second
-- participant, used for private notes that still sync like any other
-- channel. `normalize_pair` in store/dms.rs already produces (a, a) for a
-- self pair unchanged; only the CHECK below ever refused it.
--
-- STRICT tables cannot relax a CHECK constraint by ALTER TABLE, so this is a
-- table rebuild against live data. Unlike 0024's rebuild of `messages`,
-- nothing carries a foreign key on dm_channels, so there is no child to save
-- and restore around the DROP: existing rows are copied straight across, and
-- the guard table below confirms they arrived unchanged.

DROP TABLE IF EXISTS dm_channels_rebuild_guard;
DROP TABLE IF EXISTS dm_channels_rebuild_rows;

CREATE TABLE dm_channels_rebuild_rows AS
    SELECT channel_id, user_a, user_b, created_at FROM dm_channels;

DROP TABLE dm_channels;

CREATE TABLE dm_channels (
    channel_id BLOB PRIMARY KEY REFERENCES channels(id) ON DELETE CASCADE,
    user_a     BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b     BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    CHECK (user_a <= user_b)
) STRICT;

CREATE UNIQUE INDEX dm_channels_pair ON dm_channels(user_a, user_b);

-- The DM list reads "every pair this user is in" from either side.
CREATE INDEX dm_channels_user_b ON dm_channels(user_b);

INSERT INTO dm_channels (channel_id, user_a, user_b, created_at)
    SELECT channel_id, user_a, user_b, created_at FROM dm_channels_rebuild_rows;

CREATE TABLE dm_channels_rebuild_guard (
    rows    INTEGER NOT NULL CONSTRAINT dm_channels_row_count_changed CHECK (rows = 0),
    content INTEGER NOT NULL CONSTRAINT dm_channels_content_changed CHECK (content = 0)
) STRICT;

INSERT INTO dm_channels_rebuild_guard (rows, content) VALUES (
    (SELECT count(*) FROM dm_channels) - (SELECT count(*) FROM dm_channels_rebuild_rows),
    (SELECT count(*) FROM (
        SELECT channel_id, user_a, user_b, created_at FROM dm_channels_rebuild_rows
        EXCEPT
        SELECT channel_id, user_a, user_b, created_at FROM dm_channels))
);

DROP TABLE dm_channels_rebuild_guard;
DROP TABLE dm_channels_rebuild_rows;
