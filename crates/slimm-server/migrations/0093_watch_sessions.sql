-- SPDX-License-Identifier: AGPL-3.0-only
-- A voice channel's shared watch position (docs/decisions/0050).
--
-- One row per channel, written by the bot that runs the watch party and read
-- by anyone who can view the channel. A side table rather than columns on
-- `channels`: every channel SELECT would otherwise carry it.
--
-- `sampled_at` is the server wall clock the position was read at, in
-- milliseconds, so a reader can advance a playing position by its own clock.
-- `epoch` changes on every seek or title change, and is a millisecond
-- timestamp so it stays monotone across an end and a fresh session. A row the
-- bot stopped refreshing is treated as ended by the reader, not swept.
-- `controller_user_id` is an advisory hint for display, never an authority.
CREATE TABLE watch_sessions (
    channel_id BLOB PRIMARY KEY REFERENCES channels(id) ON DELETE CASCADE,
    bot_user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    item_id TEXT NOT NULL,
    title TEXT NOT NULL,
    duration_ms INTEGER,
    playing INTEGER NOT NULL CHECK (playing IN (0, 1)),
    position_ms INTEGER NOT NULL CHECK (position_ms >= 0),
    sampled_at INTEGER NOT NULL,
    epoch INTEGER NOT NULL,
    controller_user_id BLOB REFERENCES users(id)
) STRICT, WITHOUT ROWID;
