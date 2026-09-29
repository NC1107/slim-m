-- SPDX-License-Identifier: AGPL-3.0-only
-- Buttons on a bot's message, and the clicks they produce
-- (docs/decisions/0038-bot-message-buttons.md).
--
-- `message_components` is a side table like `message_embeds`, never a column
-- on `messages`. Unlike an embed it is replaced whole by the bot (to disable
-- a button, or to clear the row once a choice is made), so it is one JSON
-- document per message, validated and capped by `crate::components` before it
-- is written, rather than normalised rows nothing queries by.
--
-- `interactions` is one click awaiting the bot's answer. The id is chosen by
-- the clicking client, which makes the click idempotent. The user and message
-- ids are plain columns with no foreign key on purpose: a row lives an hour at
-- most (swept), holds no content, and a foreign key to `users` would put it in
-- the account-deletion audit for a row that expires on its own.
CREATE TABLE message_components (
    message_id BLOB PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    components TEXT NOT NULL
) STRICT, WITHOUT ROWID;

CREATE TABLE interactions (
    id BLOB PRIMARY KEY,
    bot_id BLOB NOT NULL,
    clicker_id BLOB NOT NULL,
    channel_id BLOB NOT NULL,
    message_id BLOB NOT NULL,
    custom_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    answered_at INTEGER
) STRICT, WITHOUT ROWID;

CREATE INDEX interactions_created_at ON interactions(created_at);
