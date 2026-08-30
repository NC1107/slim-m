-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Wires up the `attachments` / `message_attachments` tables that 0002 created
-- but that nothing has ever written to: no route, no store method, anywhere.
-- Reused rather than replaced, because the shape 0002 chose is the right one:
-- content-addressed by sha256, so two messages that happen to carry the same
-- bytes (a screenshot forwarded twice, the same reaction gif) share one
-- stored blob instead of paying for it twice.
--
-- Two additions this migration makes to actually use it:
--
-- `filename` on `attachments`. Content addressing means the row is shared
-- across every message that references those exact bytes, so the display
-- name is a property of the content, not of any one message attaching it:
-- the first upload of a given hash wins the name, which is the same
-- trade-off the content addressing itself already makes. `key_version` and
-- `is_encrypted` are left exactly as 0002 defined them (pre-wired for the
-- opt-in E2EE this project has always planned, `is_encrypted` DEFAULT 1);
-- the store always writes both explicitly as 0 for now, since v1 is
-- transport-only encryption, the same reality `messages.is_encrypted`
-- already reflects. STRICT tables cannot have a column's default changed in
-- place without recreating the table, so changing that default is left for
-- whichever migration actually turns encryption on.
--
-- A covering index on `message_attachments.sha256`. Its primary key is
-- (message_id, sha256), good for "this message's attachments" but useless
-- for "does anything still reference this hash", which is exactly what the
-- fetch-permission check (which channels reference this attachment) and the
-- orphan sweep (is this row referenced by anything at all) both ask.
ALTER TABLE attachments ADD COLUMN filename TEXT NOT NULL DEFAULT '';

CREATE INDEX message_attachments_by_sha ON message_attachments(sha256);

-- Avatars are deliberately NOT this table. An avatar is one mutable image
-- per user, replaced wholesale on upload and with nobody else's permission
-- ever depending on it, not content a caller attaches to a message and that
-- a channel permission decides who may see. Modeling it as an attachment
-- would conflate two different lifetimes and two different access-control
-- questions, so it gets its own column instead: presence of a non-null
-- value here is "this user has an avatar", and its value is a cache-busting
-- version a client appends to the fetch URL, not a foreign key to anything.
ALTER TABLE users ADD COLUMN avatar_updated_at INTEGER;
