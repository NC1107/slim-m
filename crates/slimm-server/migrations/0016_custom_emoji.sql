-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Deployment-wide custom emoji, the Discord-shaped kind: a name a member
-- types as `:shortcode:` and an image the deployment supplies.
--
-- The bytes are NOT a new storage mechanism. They go through the same
-- content-addressed `attachments` row and the same on-disk blob as a message
-- attachment, so an emoji uploaded twice, or one whose bytes a member has
-- already attached to a message, is stored once. That is the whole reason
-- `sha256` is the foreign key here rather than a path or a second blob table.
--
-- What this table adds on top is the part attachments cannot express: a name,
-- uniqueness of that name, and the fact that the image is a property of the
-- deployment rather than of any message. `ON DELETE RESTRICT` on the hash
-- keeps the orphan sweep from removing bytes an emoji still points at.
--
-- Access is deliberately asymmetric, and not the attachment rule. An
-- attachment is readable by whoever may view a channel that references it;
-- an emoji is readable by every authenticated member, because it renders in
-- any message anyone may already read and gating it per channel would leak
-- which channels use which emoji. Uploading and removing are gated on
-- MANAGE_SERVER, the bit that already means "change what this deployment is",
-- rather than a new permission nobody's roles carry yet.
CREATE TABLE custom_emoji (
    id          BLOB PRIMARY KEY,
    name        TEXT NOT NULL,
    sha256      BLOB NOT NULL REFERENCES attachments(sha256) ON DELETE RESTRICT,
    uploader_id BLOB REFERENCES users(id) ON DELETE SET NULL,
    created_at  INTEGER NOT NULL
) STRICT;

-- The name is what a member types, so it is the real key from their side and
-- two emoji answering to one `:shortcode:` would be ambiguous at render time.
CREATE UNIQUE INDEX custom_emoji_name ON custom_emoji(name);

-- "Is anything still pointing at these bytes" is asked by the orphan sweep,
-- which otherwise only knows about message_attachments.
CREATE INDEX custom_emoji_by_sha ON custom_emoji(sha256);
