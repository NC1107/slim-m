-- SPDX-License-Identifier: AGPL-3.0-only
-- Channel categories: rail sections a channel of any kind may be dragged
-- into, per docs/decisions/0006-channel-categories.md. `kind` keeps deciding
-- a channel's behaviour (a transcript or a call); `category_id` decides
-- placement and nothing else - two different facts, so storing both is not
-- the "second authority over one fact" seam this project already warns
-- against, it is the opposite: splitting one column that used to carry two
-- meanings (the rail read `kind` itself to decide the "Text"/"Voice"
-- section).
--
-- No overwrites bucket and no permission columns: a category is
-- organisational only, and inheriting permissions from it is a second
-- resolution dimension on top of the one-hop thread resolution
-- `Store::permission_channel` already does - deliberately not built, see
-- docs/IMPLIED-GAPS.md.
CREATE TABLE channel_categories (
    id         BLOB PRIMARY KEY,
    name       TEXT NOT NULL,
    position   INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    deleted_at INTEGER
) STRICT;

-- Nullable: `NULL` is "uncategorised", which renders as an implicit section
-- above every named category rather than being invalid data. No `ON DELETE`
-- action, because a category's own delete path (`Store::delete_category`)
-- sets every member channel's `category_id` back to `NULL` itself, inside
-- the same transaction as the category's own soft delete - the channels must
-- never be deleted along with it.
ALTER TABLE channels ADD COLUMN category_id BLOB REFERENCES channel_categories(id);

-- The upgrade must be invisible: a deployment that has never seen a category
-- gets a "Text" and a "Voice" one, in that order, and every live, non-DM,
-- non-thread channel is filed into the category matching its current kind -
-- exactly the rail it rendered before, since that rail was reading `kind`
-- for the same grouping this backfill now makes an explicit fact.
--
-- `created_at` is seeded 0 rather than a real timestamp, the same
-- placeholder 0018_space_settings.sql already uses for a row this migration
-- invents rather than a user action: nothing reads a category's creation
-- time as meaningful history.
INSERT INTO channel_categories (id, name, position, created_at)
VALUES
    (randomblob(16), 'Text', 0, 0),
    (randomblob(16), 'Voice', 1, 0);

UPDATE channels
SET category_id = (SELECT id FROM channel_categories WHERE name = 'Text')
WHERE kind = 'text' AND deleted_at IS NULL AND parent_message_id IS NULL;

UPDATE channels
SET category_id = (SELECT id FROM channel_categories WHERE name = 'Voice')
WHERE kind = 'voice' AND deleted_at IS NULL AND parent_message_id IS NULL;
