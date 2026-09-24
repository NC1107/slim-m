-- Embeds: structured, machine-authored content attached to a message, for
-- webhooks (decision 0030's "Where embeds live") and, per the owner's own
-- follow-up question, bots posting through the ordinary send route.
--
-- A side table, enriched onto the message DTO on read - never a column on
-- `messages`, which every one of that table's many SELECTs would then have
-- to carry for the small fraction of messages that are ever a bot or
-- webhook's structured output. 0019 reached the identical conclusion for
-- link previews and this record cites it directly.
--
-- One message may carry several embeds (Discord's own limit is 10; ours is
-- documented in `schema/openapi.yaml` and enforced in
-- `crates/slimm-server/src/http/embeds.rs`, shared by the webhook and bot
-- send paths so the two cannot drift), so `position` orders them and the
-- pair `(message_id, position)` is the primary key rather than a surrogate
-- id nothing ever looks up by.
--
-- `color` is the caller's raw 24-bit RGB integer, kept only to reproduce the
-- same closed accent bucket on every read - see `http::embeds::accent_for`.
-- It is never rendered as a raw fill: the design system's accent is closed
-- to seven unrelated roles (`docs/decisions/0004-visual-identity-review.md`)
-- and an arbitrary caller hex could fail contrast in either theme, so a
-- caller-supplied colour only ever selects one of a small closed set of
-- pre-tuned swatches.
--
-- `image_url`/`thumbnail_url` are caller-supplied and stored only once they
-- have passed `http::link_preview::ssrf::validate` at write time - a
-- literal blocked host or a bad scheme is dropped there and never reaches
-- this table. The deeper DNS-resolution-time guard still runs again on every
-- read, in `http::link_preview`'s existing fetch path, because a hostname
-- can resolve differently later; either way a refused image is simply
-- absent from the enriched DTO; the embed still posts.
CREATE TABLE message_embeds (
    message_id     BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    position       INTEGER NOT NULL,
    title          TEXT,
    description    TEXT,
    url            TEXT,
    color          INTEGER,
    author_name    TEXT,
    author_url     TEXT,
    footer_text    TEXT,
    embed_timestamp INTEGER,
    image_url      TEXT,
    thumbnail_url  TEXT,
    PRIMARY KEY (message_id, position)
) STRICT;

-- One embed's fields (Discord's own `name`/`value`/`inline` shape). A
-- separate table rather than a packed JSON column on `message_embeds`
-- because the field cap (25 per embed, enforced alongside every other cap in
-- `http::embeds`) and per-field length caps are exactly the kind of
-- structure a JSON blob would hide from a schema reader.
CREATE TABLE message_embed_fields (
    message_id  BLOB NOT NULL,
    position    INTEGER NOT NULL,
    field_index INTEGER NOT NULL,
    name        TEXT NOT NULL,
    value       TEXT NOT NULL,
    inline      INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (message_id, position, field_index),
    FOREIGN KEY (message_id, position) REFERENCES message_embeds(message_id, position) ON DELETE CASCADE
) STRICT;
