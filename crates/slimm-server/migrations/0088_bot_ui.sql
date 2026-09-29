-- SPDX-License-Identifier: AGPL-3.0-only
-- Message context menu entries and call controls a bot registers
-- (docs/decisions/0045-bot-contributed-ui.md).
--
-- `bot_ui_entries` is a bot's whole registered set, replaced in one
-- transaction like `bot_commands`. `surface` is where the entry shows and
-- `entry_id` is what the bot gets back when it is used.
--
-- `interactions` gains a `kind` and a nullable `message_id`: a call control
-- is used on a call, not on a message. The table holds rows for a quarter of
-- an hour at most, so it is rebuilt in place and the rows it holds are kept.
CREATE TABLE bot_ui_entries (
    bot_user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    surface TEXT NOT NULL CHECK (surface IN ('message_menu', 'call_control')),
    entry_id TEXT NOT NULL,
    label TEXT NOT NULL,
    icon TEXT,
    permission INTEGER,
    position INTEGER NOT NULL,
    PRIMARY KEY (bot_user_id, surface, entry_id)
) STRICT, WITHOUT ROWID;

CREATE TABLE interactions_new (
    id BLOB PRIMARY KEY,
    bot_id BLOB NOT NULL,
    clicker_id BLOB NOT NULL,
    channel_id BLOB NOT NULL,
    message_id BLOB,
    custom_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    answered_at INTEGER,
    kind TEXT NOT NULL DEFAULT 'button'
        CHECK (kind IN ('button', 'message_menu', 'call_control'))
) STRICT, WITHOUT ROWID;

INSERT INTO interactions_new
    (id, bot_id, clicker_id, channel_id, message_id, custom_id, created_at, answered_at)
SELECT id, bot_id, clicker_id, channel_id, message_id, custom_id, created_at, answered_at
FROM interactions;

DROP TABLE interactions;
ALTER TABLE interactions_new RENAME TO interactions;
CREATE INDEX interactions_created_at ON interactions(created_at);
