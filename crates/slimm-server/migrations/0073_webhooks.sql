-- Incoming webhooks: a webhook is a user-shaped principal, exactly as a bot
-- is (migration 0072), but with no session and no roles. See
-- docs/decisions/0030-incoming-webhooks.md for why both departures from
-- 0028's bot shape are deliberate.
--
-- Its own is_webhook flag rather than reusing is_bot: the two differ in what
-- they may do, not only in how they are labelled, and sharing one flag would
-- make the member list, the badge, and every permission read re-derive which
-- kind of account they were looking at.
--
-- password_hash stays null, the same as a bot: a webhook never signs in.
ALTER TABLE users ADD COLUMN is_webhook INTEGER NOT NULL DEFAULT 0;

-- One row per webhook, carrying the principal id it authenticates as and the
-- channel it is fixed to. channel_id has no UPDATE path anywhere in this
-- codebase, only mint-a-new-one: re-pointing a URL already pasted into
-- somebody else's configuration would silently redirect their traffic.
--
-- user_id is UNIQUE, so "the webhook" and "its principal" stay in 1:1
-- correspondence: nothing has to ask which of several webhooks a principal
-- id belongs to.
--
-- Revocation deletes this row outright rather than setting a revoked_at.
-- There is no session and no socket to also close, so the row going away is
-- the whole of it, and it is what makes "revoked" and "no such webhook"
-- answer identically at the delivery route. The users row survives, so
-- messages already posted stay attributed - the same tombstone shape account
-- deletion already gives a person.
CREATE TABLE webhooks (
    id               BLOB PRIMARY KEY,
    user_id          BLOB NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    channel_id       BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    token_hash       TEXT NOT NULL UNIQUE,
    label            TEXT NOT NULL,
    created_at       INTEGER NOT NULL,
    last_delivery_at INTEGER
) STRICT;

CREATE INDEX webhooks_channel ON webhooks(channel_id);

-- A webhook post's optional per-post `username` label (Discord's own field),
-- honoured but never written to `messages.author_display_name` - see the
-- decision record's "`username` becomes a label" section. Side table rather
-- than a column on `messages`, the same rule 0019 already applied to link
-- previews and this record applies again to `embeds`: a field every read
-- path carries for the small fraction of messages that have one is a cost
-- paid forever. Nothing reads this table yet; the enrichment that would
-- surface it on a read path is stage 3's job, alongside `message_embeds`.
CREATE TABLE webhook_message_usernames (
    message_id BLOB PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    username   TEXT NOT NULL
) STRICT;
