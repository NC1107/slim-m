-- Bot accounts: a bot is a user-shaped principal, so it is a row in users with
-- a flag rather than a parallel identity. See docs/decisions/0028-bot-accounts.md.
--
-- password_hash stays null: a bot never signs in with one, and the column has
-- always been nullable.

ALTER TABLE users ADD COLUMN is_bot INTEGER NOT NULL DEFAULT 0;

-- One long-lived credential per row, hashed like every other secret here.
--
-- session_id is what makes a bot fit everything downstream unchanged. A bot
-- token resolves to a real session, so ws tickets, revocation, fan-out
-- authorization and moderation all work on a bot exactly as they do on a
-- person, with no second code path. Revoking the session is what stops a bot.
CREATE TABLE bot_tokens (
    token_hash  TEXT PRIMARY KEY,
    bot_user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id  BLOB NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    created_by  BLOB REFERENCES users(id) ON DELETE SET NULL,
    created_at  INTEGER NOT NULL,
    last_used_at INTEGER,
    revoked_at  INTEGER
) STRICT;

CREATE INDEX bot_tokens_bot ON bot_tokens(bot_user_id);
