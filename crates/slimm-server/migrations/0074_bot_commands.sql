-- A bot's registered command palette and its own prefix: advertisement, not
-- interactions (see docs/decisions/0031-bot-command-registration.md). A bot
-- tells the server what it answers to; the composer offers it in the `/`
-- menu; picking it inserts the bot's own prefix and keyword as plain text,
-- exactly the message a bot's own process already parses today. The server
-- never runs a bot command - only Store::set_bot_commands's bulk overwrite
-- and the read paths that list what is currently registered.
--
-- One row per bot for its prefix (bulk-overwrite target: replaced whole, per
-- registration call, mirroring Discord's own bulk command overwrite), and one
-- row per command it currently advertises.
CREATE TABLE bot_command_registrations (
    bot_user_id BLOB PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    prefix      TEXT NOT NULL,
    updated_at  INTEGER NOT NULL
) STRICT, WITHOUT ROWID;

-- position preserves the bot's own declared order, since a composer list
-- ordered by name would scramble a bot author's deliberate grouping.
CREATE TABLE bot_commands (
    bot_user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT NOT NULL,
    usage       TEXT,
    -- A single Permissions bit (same encoding as GET /channels/{id}/permissions),
    -- or null for a command open to anyone who can see the bot at all. A hint
    -- the composer uses to hide the row from a caller who lacks it - never
    -- enforced against the plain message the bot goes on to receive.
    permission  INTEGER,
    position    INTEGER NOT NULL,
    PRIMARY KEY (bot_user_id, name)
) STRICT, WITHOUT ROWID;
